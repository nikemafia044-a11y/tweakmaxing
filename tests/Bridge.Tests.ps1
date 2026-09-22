# tests/Bridge.Tests.ps1
# Ponte JSON: contrato de pedido/resposta, acoes da casca e caminho assincrono.
# Nao abre janela e nao exige elevacao.

. (Join-Path $PSScriptRoot '_Helpers.ps1')

Describe 'Ponte JSON' -Tag 'Bridge' {

    BeforeAll {
        . (Join-Path $PSScriptRoot '_Helpers.ps1')
        Import-TmxTestModule
        New-TmxTestHome | Out-Null

        function New-TmxBridgeTestSync {
            <#
            .SYNOPSIS
                $global:sync minimo para a ponte, com coletor de eventos.
            #>
            $s = [Hashtable]::Synchronized(@{})
            $s.version       = '0.1.0-test'
            $s.testMode      = $true
            $s.configs       = @{}
            $s.bridgeActions = @{}
            $s.activeJob     = $null
            $s.session       = $null
            $s.uiEvents      = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList))
            $global:sync = $s
            $s
        }

        function Wait-TmxTestEvent {
            <#
            .SYNOPSIS
                Espera um evento aparecer em $sync.uiEvents (ate TimeoutSeconds).
            #>
            param(
                [Parameter(Mandatory)] [string] $Nome,
                [int] $TimeoutSeconds = 5
            )
            # .ToArray() (que o wrapper Synchronized do ArrayList executa sob
            # lock) em vez de enumerar a lista direto: a runspace do job
            # continua chamando .Add() enquanto esperamos, e um foreach/pipeline
            # sobre a colecao viva estoura com "Colecao foi modificada".
            $limite = (Get-Date).AddSeconds($TimeoutSeconds)
            while ((Get-Date) -lt $limite) {
                $achado = @(@($sync.uiEvents.ToArray()) | Where-Object { $_.event -eq $Nome })
                if ($achado.Count -gt 0) { return $achado[0] }
                Start-Sleep -Milliseconds 100
            }
            $null
        }
    }

    AfterAll {
        if (Get-Command Close-TmxRunspacePool -ErrorAction SilentlyContinue) { Close-TmxRunspacePool }
        Remove-TmxTestHome
        Remove-Variable -Name sync -Scope Global -ErrorAction SilentlyContinue
    }

    BeforeEach {
        New-TmxBridgeTestSync | Out-Null
        Register-TmxShellActions
        # session.* saiu da casca para Actions.Session.ps1 (Task 9).
        Register-TmxSessionActions
    }

    Context 'Contrato do pedido' {

        It 'recusa JSON invalido com requisicao invalida' {
            $r = Invoke-TmxBridgeRequest -Json '{ isso nao e json' | ConvertFrom-Json
            $r.ok | Should -BeFalse
            $r.error.message | Should -Be 'requisicao invalida'
        }

        It 'recusa pedido sem id' {
            $r = Invoke-TmxBridgeRequest -Json '{"action":"shell.ping"}' | ConvertFrom-Json
            $r.ok | Should -BeFalse
            $r.error.message | Should -Be 'requisicao invalida'
        }

        It 'recusa pedido sem action' {
            $r = Invoke-TmxBridgeRequest -Json '{"id":"1"}' | ConvertFrom-Json
            $r.ok | Should -BeFalse
            $r.error.message | Should -Be 'requisicao invalida'
        }

        It 'responde acao desconhecida nomeando a acao' {
            $r = Invoke-TmxBridgeRequest -Json '{"id":"1","action":"nao.existe"}' | ConvertFrom-Json
            $r.id | Should -Be '1'
            $r.ok | Should -BeFalse
            $r.error.message | Should -Be 'acao desconhecida: nao.existe'
        }

        It 'devolve ok:false com a mensagem quando o handler lanca' {
            Register-TmxBridgeAction -Name 'teste.boom' -Handler { param($p) throw 'estourou de proposito' }
            $r = Invoke-TmxBridgeRequest -Json '{"id":"7","action":"teste.boom"}' | ConvertFrom-Json
            $r.id | Should -Be '7'
            $r.ok | Should -BeFalse
            $r.error.message | Should -Be 'estourou de proposito'
        }

        It 'entrega o payload ao handler' {
            Register-TmxBridgeAction -Name 'teste.eco' -Handler { param($p) @{ visto = "$($p.texto)" } }
            $r = Invoke-TmxBridgeRequest -Json '{"id":"8","action":"teste.eco","payload":{"texto":"ola"}}' | ConvertFrom-Json
            $r.ok | Should -BeTrue
            $r.result.visto | Should -Be 'ola'
        }
    }

    Context 'Acoes da casca' {

        It 'shell.ping responde pong' {
            $r = Invoke-TmxBridgeRequest -Json '{"id":"2","action":"shell.ping"}' | ConvertFrom-Json
            $r.ok | Should -BeTrue
            $r.result.pong | Should -BeTrue
            $r.result.ts | Should -Not -BeNullOrEmpty
        }

        It 'shell.version devolve versao e modo de teste' {
            $r = Invoke-TmxBridgeRequest -Json '{"id":"3","action":"shell.version"}' | ConvertFrom-Json
            $r.ok | Should -BeTrue
            $r.result.version | Should -Be '0.1.0-test'
            $r.result.testMode | Should -BeTrue
        }

        It 'session.status devolve nenhum ponto de restauracao por padrao' {
            $r = Invoke-TmxBridgeRequest -Json '{"id":"4","action":"session.status"}' | ConvertFrom-Json
            $r.ok | Should -BeTrue
            $r.result.restorePoint.estado | Should -Be 'nenhum'
            $r.result.runId | Should -BeNullOrEmpty
        }

        It 'session.status reflete a sessao quando ela existe' {
            $sync.session = @{
                restorePoint = @{ estado = 'criado'; seq = 999 }
                runId        = '20260101-000000-abcd'
                runPath      = 'C:\temp\run'
                undoCommand  = 'Undo-TweakMaxing -Latest'
            }
            $r = Invoke-TmxBridgeRequest -Json '{"id":"5","action":"session.status"}' | ConvertFrom-Json
            $r.result.restorePoint.estado | Should -Be 'criado'
            $r.result.restorePoint.seq | Should -Be 999
            $r.result.runId | Should -Be '20260101-000000-abcd'
            $r.result.undoCommand | Should -Be 'Undo-TweakMaxing -Latest'
        }

        It 'log.tail devolve as ultimas linhas do transcript' {
            $log = Join-Path $env:TWEAKMAXING_HOME 'tail.log'
            Set-Content -LiteralPath $log -Value @('um', 'dois', 'tres') -Encoding UTF8
            $sync.logPath = $log
            $r = Invoke-TmxBridgeRequest -Json '{"id":"6","action":"log.tail","payload":{"n":2}}' | ConvertFrom-Json
            $r.ok | Should -BeTrue
            @($r.result.linhas).Count | Should -Be 2
            @($r.result.linhas)[-1] | Should -Be 'tres'
        }

        It 'log.tail sem transcript nao lanca' {
            $r = Invoke-TmxBridgeRequest -Json '{"id":"6b","action":"log.tail"}' | ConvertFrom-Json
            $r.ok | Should -BeTrue
            @($r.result.linhas).Count | Should -Be 0
        }
    }

    Context 'shell.openUrl so aceita https' {

        BeforeEach {
            Mock -ModuleName TweakMaxing -CommandName Start-Process -MockWith { }
        }

        It 'aceita https' {
            $r = Invoke-TmxBridgeRequest -Json '{"id":"10","action":"shell.openUrl","payload":{"url":"https://exemplo.org/a"}}' | ConvertFrom-Json
            $r.ok | Should -BeTrue
            $r.result.aberto | Should -BeTrue
        }

        It 'recusa <alvo>' -ForEach @(
            @{ alvo = 'file:///C:/Windows/System32/cmd.exe' }
            @{ alvo = 'http://exemplo.org' }
            @{ alvo = 'javascript:alert(1)' }
            @{ alvo = 'C:\Windows\System32\cmd.exe' }
        ) {
            $json = (@{ id = 'x'; action = 'shell.openUrl'; payload = @{ url = $alvo } } | ConvertTo-Json -Compress)
            $r = Invoke-TmxBridgeRequest -Json $json | ConvertFrom-Json
            $r.ok | Should -BeFalse
            $r.error.message | Should -Be 'apenas URLs https'
        }
    }

    Context 'Acoes assincronas' {

        AfterEach {
            Wait-TmxRemainingWork -TimeoutSeconds 20 | Out-Null
            # Cada BeforeEach cria um $sync novo, logo um pool novo: fechar aqui
            # evita acumular runspaces abertos durante a suite.
            Close-TmxRunspacePool
        }

        It 'responde jobId na hora e emite started/progress/done' {
            $r = Invoke-TmxBridgeRequest -Json '{"id":"20","action":"shell.async.echo","payload":{"ms":100,"marca":"xyz"}}' | ConvertFrom-Json
            $r.ok | Should -BeTrue
            $r.result.jobId | Should -Not -BeNullOrEmpty

            $iniciado = Wait-TmxTestEvent -Nome 'job.started'
            $iniciado | Should -Not -BeNullOrEmpty
            $iniciado.payload.name | Should -Be 'shell.async.echo'
            $iniciado.payload.jobId | Should -Be $r.result.jobId

            $progresso = Wait-TmxTestEvent -Nome 'job.progress'
            $progresso | Should -Not -BeNullOrEmpty
            $progresso.payload.pct | Should -Be 50

            $pronto = Wait-TmxTestEvent -Nome 'job.done'
            $pronto | Should -Not -BeNullOrEmpty
            $pronto.payload.ok | Should -BeTrue
            $pronto.payload.result.echo.marca | Should -Be 'xyz'
        }

        It 'recusa um segundo trabalho enquanto ha um em andamento' {
            $r1 = Invoke-TmxBridgeRequest -Json '{"id":"21","action":"shell.async.echo","payload":{"ms":1500}}' | ConvertFrom-Json
            $r1.ok | Should -BeTrue

            $r2 = Invoke-TmxBridgeRequest -Json '{"id":"22","action":"shell.async.echo","payload":{"ms":10}}' | ConvertFrom-Json
            $r2.ok | Should -BeFalse
            $r2.error.message | Should -Be 'ja existe um trabalho em andamento'
        }

        It 'enxerga as constantes de escopo de script dentro do job' {
            # Regressao: sem copiar $script:Tmx* para a InitialSessionState,
            # $script:TmxConditionRegex chega $null na runspace do job e
            # ConvertFrom-TmxCondition morre com "Operador '' exige um valor".
            Register-TmxBridgeAction -Name 'teste.async.condicao' -Async -Handler {
                param($p)
                $c = ConvertFrom-TmxCondition -Expression 'os.isLaptop == true :: x'
                @{ caminho = "$($c.caminho)"; operador = "$($c.operador)"; motivo = "$($c.motivo)" }
            }
            $r = Invoke-TmxBridgeRequest -Json '{"id":"24","action":"teste.async.condicao"}' | ConvertFrom-Json
            $r.ok | Should -BeTrue

            $pronto = Wait-TmxTestEvent -Nome 'job.done' -TimeoutSeconds 20
            $pronto | Should -Not -BeNullOrEmpty
            $pronto.payload.ok | Should -BeTrue
            $pronto.payload.result.caminho | Should -Be 'os.isLaptop'
            $pronto.payload.result.operador | Should -Be '=='
            $pronto.payload.result.motivo | Should -Be 'x'
        }

        It 'mantem o estado de execucao de um job para o proximo' {
            # Regressao: o pool tem uma unica runspace justamente para que o
            # $script:TmxRun criado aqui continue valendo no job seguinte.
            Register-TmxBridgeAction -Name 'teste.async.novoRun' -Async -Handler {
                param($p)
                @{ runId = "$((New-TmxRun).RunId)" }
            }
            Register-TmxBridgeAction -Name 'teste.async.leRun' -Async -Handler {
                param($p)
                $r = Get-TmxRun
                @{ runId = "$($r.RunId)" }
            }

            $r1 = Invoke-TmxBridgeRequest -Json '{"id":"25","action":"teste.async.novoRun"}' | ConvertFrom-Json
            $r1.ok | Should -BeTrue
            $criado = Wait-TmxTestEvent -Nome 'job.done' -TimeoutSeconds 20
            $criado | Should -Not -BeNullOrEmpty
            $criado.payload.ok | Should -BeTrue
            $criado.payload.result.runId | Should -Not -BeNullOrEmpty

            $sync.uiEvents.Clear()
            Wait-TmxRemainingWork -TimeoutSeconds 20 | Out-Null

            $r2 = Invoke-TmxBridgeRequest -Json '{"id":"26","action":"teste.async.leRun"}' | ConvertFrom-Json
            $r2.ok | Should -BeTrue
            $lido = Wait-TmxTestEvent -Nome 'job.done' -TimeoutSeconds 20
            $lido | Should -Not -BeNullOrEmpty
            $lido.payload.ok | Should -BeTrue
            $lido.payload.result.runId | Should -Be $criado.payload.result.runId
        }

        It 'reporta erro do handler assincrono em job.done' {
            Register-TmxBridgeAction -Name 'teste.async.boom' -Async -Handler { param($p) throw 'falhou no job' }
            $r = Invoke-TmxBridgeRequest -Json '{"id":"23","action":"teste.async.boom"}' | ConvertFrom-Json
            $r.ok | Should -BeTrue

            $pronto = Wait-TmxTestEvent -Nome 'job.done'
            $pronto | Should -Not -BeNullOrEmpty
            $pronto.payload.ok | Should -BeFalse
            $pronto.payload.error.message | Should -Be 'falhou no job'
        }
    }
}

Describe 'Isolamento da runspace do pool' -Tag 'Bridge' {

    BeforeAll {
        . (Join-Path $PSScriptRoot '_Helpers.ps1')
        Import-TmxTestModule
    }

    AfterAll {
        Remove-Variable -Name sync -Scope Global -ErrorAction SilentlyContinue
        Remove-Module TweakMaxing -Force -ErrorAction SilentlyContinue
    }

    BeforeEach {
        $s = [Hashtable]::Synchronized(@{})
        $s.activeJob = $null
        $s.uiEvents  = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList))
        $global:sync = $s
    }

    It 'a InitialSessionState leva as constantes e nao o estado de execucao' {
        # A runspace do pool tem que comecar SEM execucao ativa: um $TmxRun
        # copiado da thread que montou a ISS faria a guarda de Core/Backup.ps1
        # passar numa runspace que nao persiste nada.
        $iss = New-TmxSessionState
        $nomes = @($iss.Variables | ForEach-Object { "$($_.Name)" })

        $nomes | Should -Contain 'TmxConditionRegex'
        $nomes | Should -Contain 'TmxThrottleKeyPath'
        $nomes | Should -Contain 'TmxSkipPhrase'

        $nomes | Should -Not -Contain 'TmxRun'
        $nomes | Should -Not -Contain 'TmxStateRecords'
        $nomes | Should -Not -Contain 'TmxLog'
        $nomes | Should -Not -Contain 'TmxPowerBackupFeito'
        $nomes | Should -Not -Contain 'TmxEnumRoot'
    }

    It 'toda variavel de script Tmx* esta classificada' {
        # A lista de permissao so protege se estiver completa: uma constante
        # nova que ninguem classificou nao chega a runspace do pool e vira um
        # $null dificil de diagnosticar la dentro. Aqui a omissao quebra o
        # teste em vez de quebrar um job.
        InModuleScope TweakMaxing {
            $todas = @(Get-Variable -Scope Script -Name 'Tmx*' -ErrorAction SilentlyContinue | ForEach-Object { "$($_.Name)" })
            $classificadas = @($script:TmxConstantesRunspace) + @($script:TmxMutaveisConhecidas)
            $orfas = @($todas | Where-Object { $classificadas -notcontains $_ })
            $orfas.Count | Should -Be 0 -Because "sem classificacao em Start-TmxJob.ps1: $($orfas -join ', ')"
        }
    }

    It 'Get-TmxEnumRoot cai no padrao quando a variavel nao atravessou' {
        # Corolario do teste acima: $script:TmxEnumRoot fica fora da ISS, entao
        # quem le a raiz Enum tem que passar por Get-TmxEnumRoot.
        InModuleScope TweakMaxing {
            $anterior = $script:TmxEnumRoot
            try {
                $script:TmxEnumRoot = $null
                Get-TmxEnumRoot | Should -Be 'HKLM:\SYSTEM\CurrentControlSet\Enum'
            } finally {
                $script:TmxEnumRoot = $anterior
            }
        }
    }

    Context 'Invoke-TmxJobBody' {

        It 'zera o activeJob mesmo quando Send-TmxUiEvent lanca' {
            # Se o job.started morresse fora do try/finally, $sync.activeJob
            # ficaria preso e a ponte recusaria TODO trabalho seguinte com
            # 'ja existe um trabalho em andamento' ate reiniciar o processo.
            Mock -ModuleName TweakMaxing -CommandName Send-TmxUiEvent -MockWith { throw 'janela morreu' }

            $sync.activeJob = @{ jobId = 'j1'; name = 'teste' }
            { Invoke-TmxJobBody -JobId 'j1' -Name 'teste' -HandlerText 'param($p) 1' } | Should -Not -Throw
            $sync.activeJob | Should -BeNullOrEmpty
        }

        It 'zera o activeJob e reporta job.done ok:false quando o handler lanca' {
            $sync.activeJob = @{ jobId = 'j2'; name = 'teste' }
            Invoke-TmxJobBody -JobId 'j2' -Name 'teste' -HandlerText 'param($p) throw ''boom'''

            $sync.activeJob | Should -BeNullOrEmpty
            $eventos = @($sync.uiEvents.ToArray())
            @($eventos | Where-Object { $_.event -eq 'job.started' }).Count | Should -Be 1
            $done = @($eventos | Where-Object { $_.event -eq 'job.done' })[0]
            $done.payload.ok | Should -BeFalse
            $done.payload.error.message | Should -Be 'boom'
        }

        It 'emite started e done com o resultado no caminho feliz' {
            $sync.activeJob = @{ jobId = 'j3'; name = 'teste' }
            Invoke-TmxJobBody -JobId 'j3' -Name 'teste' -Payload @{ n = 7 } -HandlerText 'param($p) @{ dobro = ([int]$p.n * 2) }'

            $sync.activeJob | Should -BeNullOrEmpty
            $eventos = @($sync.uiEvents.ToArray())
            $eventos[0].event | Should -Be 'job.started'
            $done = @($eventos | Where-Object { $_.event -eq 'job.done' })[0]
            $done.payload.ok | Should -BeTrue
            $done.payload.result.dobro | Should -Be 14
        }
    }
}
