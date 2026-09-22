# tests/Session.Tests.ps1
# A sessao de trabalho: guardas -> pasta da execucao -> ponto de restauracao,
# e as acoes session.* da ponte. Nao abre janela e nao exige elevacao.
#
# O ponto de restauracao NUNCA e criado de verdade aqui: no modo de teste a
# propria Start-TmxSession simula (#999) sem chamar Checkpoint-Computer, e nos
# contextos de modo normal o Invoke-TmxRestorePointStage e mockado.

. (Join-Path $PSScriptRoot '_Helpers.ps1')

Describe 'Sessao' -Tag 'Session' {

    BeforeAll {
        . (Join-Path $PSScriptRoot '_Helpers.ps1')
        Import-TmxTestModule
        New-TmxTestHome | Out-Null

        function New-TmxSessionTestSync {
            <#
            .SYNOPSIS
                $global:sync minimo, com coletor de eventos da UI.
            #>
            param([bool] $TestMode = $true)

            $s = [Hashtable]::Synchronized(@{})
            $s.version       = '0.1.0-test'
            $s.testMode      = $TestMode
            $s.configs       = @{}
            $s.bridgeActions = @{}
            $s.activeJob     = $null
            $s.session       = $null
            $s.uiEvents      = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList))
            $global:sync = $s
            $s
        }

        function Get-TmxTestEvents {
            param([Parameter(Mandatory)] [string] $Nome)
            # ,@(...): sem a virgula um unico evento sai desenrolado e
            # ([pscustomobject]).Count e $null no PS 5.1 (nao 1).
            ,@($sync.uiEvents | Where-Object { $_.event -eq $Nome })
        }

        function Wait-TmxTestEvent {
            param(
                [Parameter(Mandatory)] [string] $Nome,
                [int] $TimeoutSeconds = 20
            )
            $limite = (Get-Date).AddSeconds($TimeoutSeconds)
            while ((Get-Date) -lt $limite) {
                $achado = @($sync.uiEvents | Where-Object { $_.event -eq $Nome })
                if ($achado.Count -gt 0) { return $achado[0] }
                Start-Sleep -Milliseconds 100
            }
            $null
        }

        function Measure-TmxRunFolders {
            $raiz = Get-TmxRunsRoot
            if (-not (Test-Path -LiteralPath $raiz)) { return 0 }
            @(Get-ChildItem -LiteralPath $raiz -Directory -ErrorAction SilentlyContinue).Count
        }

        function New-TmxGuardasOk {
            [pscustomobject]@{
                ok        = $true
                bloqueios = @()
                avisos    = @()
                contexto  = [pscustomobject]@{ elevado = $true }
            }
        }
    }

    AfterAll {
        if (Get-Command Close-TmxRunspacePool -ErrorAction SilentlyContinue) { Close-TmxRunspacePool }
        Remove-TmxTestHome
        Remove-Variable -Name sync -Scope Global -ErrorAction SilentlyContinue
    }

    Context 'Modo de teste: ponto simulado' {

        BeforeEach {
            New-TmxSessionTestSync -TestMode $true | Out-Null
            Mock -ModuleName TweakMaxing -CommandName Assert-TmxGuards -MockWith { New-TmxGuardasOk }
        }

        It 'abre a sessao com run, ponto #999 e comando de reversao' {
            $r = Start-TmxSession

            $r.ok | Should -BeTrue
            $r.session.runId | Should -Not -BeNullOrEmpty
            $r.session.pronto | Should -BeTrue
            $r.session.restorePoint.estado | Should -Be 'criado'
            $r.session.restorePoint.seq | Should -Be 999
            $r.session.undoCommand | Should -Be "TweakMaxing.ps1 -Headless -Undo $($r.session.runId)"
            Test-Path -LiteralPath $r.session.runPath | Should -BeTrue
            Test-Path -LiteralPath $r.session.statePath | Should -BeTrue
        }

        It 'publica a sessao em sync.session e avisa a UI pelo menos duas vezes' {
            Start-TmxSession | Out-Null

            $sync.session | Should -Not -BeNullOrEmpty
            $sync.session.pronto | Should -BeTrue

            $eventos = Get-TmxTestEvents -Nome 'session.changed'
            $eventos.Count | Should -BeGreaterOrEqual 2
            $eventos[0].payload.restorePoint.estado | Should -Be 'criando'
            $eventos[-1].payload.restorePoint.estado | Should -Be 'criado'
        }

        It 'nao cria um segundo run quando a sessao ja esta pronta' {
            $primeiro = Start-TmxSession
            $antes = Measure-TmxRunFolders

            $segundo = Start-TmxSession

            $segundo.ok | Should -BeTrue
            $segundo.session.runId | Should -Be $primeiro.session.runId
            Measure-TmxRunFolders | Should -Be $antes
        }

        It 'aceita falta de elevacao apenas no modo de teste' {
            Start-TmxSession | Out-Null
            Should -Invoke -CommandName Assert-TmxGuards -ModuleName TweakMaxing -Times 1 -Exactly `
                -ParameterFilter { $AllowUnelevated -eq $true }
        }

        It 'nunca publica pronto sem o comando de reversao' {
            Start-TmxSession | Out-Null

            $eventos = Get-TmxTestEvents -Nome 'session.changed'
            foreach ($ev in $eventos) {
                if ($ev.payload.pronto -eq $true) {
                    $ev.payload.undoCommand | Should -Not -BeNullOrEmpty
                    $ev.payload.restorePoint.estado | Should -Not -Be 'criando'
                }
            }
            # O primeiro evento continua dizendo 'criando' depois do fim: cada
            # transicao publica um objeto novo, nunca muta o ja publicado.
            $eventos[0].payload.pronto | Should -BeFalse
            $eventos[0].payload.undoCommand | Should -BeNullOrEmpty
            $eventos[0].payload.restorePoint.seq | Should -BeNullOrEmpty
        }

        It 'troca a referencia publicada a cada transicao' {
            Start-TmxSession | Out-Null

            $eventos = Get-TmxTestEvents -Nome 'session.changed'
            $eventos.Count | Should -BeGreaterOrEqual 2
            [object]::ReferenceEquals($eventos[0].payload, $eventos[-1].payload) | Should -BeFalse
            [object]::ReferenceEquals($sync.session, $eventos[0].payload) | Should -BeFalse
        }

        It 'session.simulateFailure derruba so a proxima criacao' {
            $sync.simulateRestorePointFailure = $true

            $falhou = Start-TmxSession
            $falhou.ok | Should -BeFalse
            $falhou.session.restorePoint.estado | Should -Be 'falhou'
            $falhou.session.pronto | Should -BeFalse
            $sync.simulateRestorePointFailure | Should -BeFalse

            $depois = Start-TmxSession
            $depois.ok | Should -BeTrue
            $depois.session.restorePoint.estado | Should -Be 'criado'
        }

        It 'Get-TmxSessionStatus reflete a sessao pronta' {
            $r = Start-TmxSession
            $st = Get-TmxSessionStatus

            $st.pronto | Should -BeTrue
            $st.runId  | Should -Be $r.session.runId
            $st.restorePoint.estado | Should -Be 'criado'
            $st.restorePoint.seq | Should -Be 999
            $st.testMode | Should -BeTrue
            $st.undoCommand | Should -Not -BeNullOrEmpty
        }

        It 'Get-TmxSessionStatus sem sessao diz nenhum' {
            $st = Get-TmxSessionStatus
            $st.restorePoint.estado | Should -Be 'nenhum'
            $st.pronto | Should -BeFalse
            $st.runId | Should -BeNullOrEmpty
        }
    }

    Context 'Modo normal: o ponto de restauracao manda' {

        BeforeEach {
            New-TmxSessionTestSync -TestMode $false | Out-Null
            Mock -ModuleName TweakMaxing -CommandName Assert-TmxGuards -MockWith { New-TmxGuardasOk }
        }

        It 'aborta a sessao quando o ponto falha e nada e aplicado' {
            Mock -ModuleName TweakMaxing -CommandName Invoke-TmxRestorePointStage -MockWith {
                [pscustomobject]@{ proceed = $false; exitCode = 2; mensagem = 'x'; pulado = $false; resultado = $null }
            }

            $r = Start-TmxSession

            $r.ok | Should -BeFalse
            $r.mensagem | Should -Be 'x'
            $sync.session.restorePoint.estado | Should -Be 'falhou'
            $sync.session.restorePoint.mensagem | Should -Be 'x'
            $sync.session.pronto | Should -BeFalse
            $sync.session.undoCommand | Should -BeNullOrEmpty
            @(Get-TmxState | Where-Object { $_.status -eq 'aplicado' }).Count | Should -Be 0
        }

        It 'exige elevacao fora do modo de teste' {
            Mock -ModuleName TweakMaxing -CommandName Invoke-TmxRestorePointStage -MockWith {
                [pscustomobject]@{ proceed = $true; exitCode = 0; mensagem = 'ok'; pulado = $false; resultado = [pscustomobject]@{ sequenceNumber = 7 } }
            }

            Start-TmxSession | Out-Null
            Should -Invoke -CommandName Assert-TmxGuards -ModuleName TweakMaxing -Times 1 -Exactly `
                -ParameterFilter { $AllowUnelevated -ne $true }
        }

        It 'ignora restorePointMock fora do modo de teste' {
            # A flag e uma facilidade de teste, nao uma chave de fabrica: sem
            # -TestMode o ponto real tem que ser sempre tentado.
            $sync.restorePointMock = $true
            Mock -ModuleName TweakMaxing -CommandName Invoke-TmxRestorePointStage -MockWith {
                [pscustomobject]@{ proceed = $true; exitCode = 0; mensagem = 'real'; pulado = $false; resultado = [pscustomobject]@{ sequenceNumber = 42 } }
            }

            $r = Start-TmxSession

            Should -Invoke -CommandName Invoke-TmxRestorePointStage -ModuleName TweakMaxing -Times 1 -Exactly
            $r.ok | Should -BeTrue
            $r.session.restorePoint.seq | Should -Be 42
        }

        It 'ignora simulateRestorePointFailure fora do modo de teste' {
            $sync.simulateRestorePointFailure = $true
            Mock -ModuleName TweakMaxing -CommandName Invoke-TmxRestorePointStage -MockWith {
                [pscustomobject]@{ proceed = $true; exitCode = 0; mensagem = 'real'; pulado = $false; resultado = [pscustomobject]@{ sequenceNumber = 43 } }
            }

            $r = Start-TmxSession

            $r.ok | Should -BeTrue
            $r.session.restorePoint.seq | Should -Be 43
        }

        It 'marca o ponto como pulado quando o usuario confirmou a frase' {
            Mock -ModuleName TweakMaxing -CommandName Invoke-TmxRestorePointStage -MockWith {
                [pscustomobject]@{ proceed = $true; exitCode = 0; mensagem = 'Ponto de restauracao PULADO por decisao explicita do usuario.'; pulado = $true; resultado = $null }
            }

            $r = Start-TmxSession -SkipConfirmado

            $r.ok | Should -BeTrue
            $r.session.restorePoint.estado | Should -Be 'pulado'
            $r.session.restorePoint.seq | Should -BeNullOrEmpty
            $r.session.pronto | Should -BeTrue
            $r.session.undoCommand | Should -Not -BeNullOrEmpty

            Should -Invoke -CommandName Invoke-TmxRestorePointStage -ModuleName TweakMaxing -Times 1 -Exactly `
                -ParameterFilter { $SkipRestorePoint -eq $true -and $IUnderstandTheRisk -eq $true }
        }
    }

    Context 'Guardas bloqueadas' {

        BeforeEach {
            New-TmxSessionTestSync -TestMode $true | Out-Null
            Mock -ModuleName TweakMaxing -CommandName Assert-TmxGuards -MockWith {
                [pscustomobject]@{
                    ok        = $false
                    bloqueios = @('E necessario executar como Administrador.', 'Ha uma reinicializacao pendente.')
                    avisos    = @()
                    contexto  = [pscustomobject]@{ elevado = $false }
                }
            }
            Mock -ModuleName TweakMaxing -CommandName New-TmxRun -MockWith { throw 'New-TmxRun nao deveria ser chamado' }
        }

        It 'recusa a sessao com os bloqueios na mensagem e nao cria run' {
            $antes = Measure-TmxRunFolders

            $r = Start-TmxSession

            $r.ok | Should -BeFalse
            $r.mensagem | Should -BeLike '*Administrador*'
            $r.mensagem | Should -BeLike '*reinicializacao pendente*'
            $sync.session | Should -BeNullOrEmpty
            Measure-TmxRunFolders | Should -Be $antes
            Should -Invoke -CommandName New-TmxRun -ModuleName TweakMaxing -Times 0
        }
    }

    Context 'Acoes da ponte' {

        BeforeEach {
            New-TmxSessionTestSync -TestMode $true | Out-Null
            Register-TmxShellActions
            Register-TmxSessionActions
        }

        AfterEach {
            Wait-TmxRemainingWork -TimeoutSeconds 30 | Out-Null
            Close-TmxRunspacePool
        }

        It 'session.skipPhrase devolve a frase exigida' {
            $r = Invoke-TmxBridgeRequest -Json '{"id":"1","action":"session.skipPhrase"}' | ConvertFrom-Json
            $r.ok | Should -BeTrue
            $r.result.frase | Should -Be (Get-TmxSkipPhrase)
        }

        It 'session.start com frase errada recusa antes de existir job' {
            $json = (@{ id = '2'; action = 'session.start'; payload = @{ skip = $true; frase = 'sem ponto de restauracao' } } | ConvertTo-Json -Compress)
            $r = Invoke-TmxBridgeRequest -Json $json | ConvertFrom-Json

            $r.ok | Should -BeFalse
            $r.error.message | Should -Be 'frase de confirmacao incorreta'
            $sync.activeJob | Should -BeNullOrEmpty
            (Get-TmxTestEvents -Nome 'job.started').Count | Should -Be 0
        }

        It 'session.start com a frase exata dispara o job e ele termina bem' {
            $json = (@{ id = '3'; action = 'session.start'; payload = @{ skip = $true; frase = (Get-TmxSkipPhrase) } } | ConvertTo-Json -Compress)
            $r = Invoke-TmxBridgeRequest -Json $json | ConvertFrom-Json

            $r.ok | Should -BeTrue
            $r.result.jobId | Should -Not -BeNullOrEmpty

            $pronto = Wait-TmxTestEvent -Nome 'job.done' -TimeoutSeconds 60
            $pronto | Should -Not -BeNullOrEmpty
            $pronto.payload.ok | Should -BeTrue -Because "erro: $($pronto.payload.error.message)"
            $pronto.payload.result.session.pronto | Should -BeTrue

            $st = Invoke-TmxBridgeRequest -Json '{"id":"4","action":"session.status"}' | ConvertFrom-Json
            $st.result.pronto | Should -BeTrue
            $st.result.runId | Should -Be $pronto.payload.result.session.runId
            $st.result.undoCommand | Should -Not -BeNullOrEmpty
        }

        It 'session.start sem pular cria a sessao com o ponto simulado' {
            $r = Invoke-TmxBridgeRequest -Json '{"id":"5","action":"session.start","payload":{"skip":false}}' | ConvertFrom-Json
            $r.ok | Should -BeTrue

            $pronto = Wait-TmxTestEvent -Nome 'job.done' -TimeoutSeconds 60
            $pronto | Should -Not -BeNullOrEmpty
            $pronto.payload.ok | Should -BeTrue -Because "erro: $($pronto.payload.error.message)"
            $pronto.payload.result.session.restorePoint.estado | Should -Be 'criado'
            $pronto.payload.result.session.restorePoint.seq | Should -Be 999
        }

        It 'session.status devolve nenhum ponto antes de qualquer sessao' {
            $r = Invoke-TmxBridgeRequest -Json '{"id":"6","action":"session.status"}' | ConvertFrom-Json
            $r.ok | Should -BeTrue
            $r.result.restorePoint.estado | Should -Be 'nenhum'
            $r.result.pronto | Should -BeFalse
            $r.result.runId | Should -BeNullOrEmpty
        }

        It 'session.reset limpa a sessao no modo de teste' {
            $sync.session = @{
                runId        = '20260101-000000-abcd'
                restorePoint = @{ estado = 'criado'; seq = 999; mensagem = $null }
                pronto       = $true
                undoCommand  = 'TweakMaxing.ps1 -Headless -Undo 20260101-000000-abcd'
            }

            $r = Invoke-TmxBridgeRequest -Json '{"id":"7","action":"session.reset"}' | ConvertFrom-Json

            $r.ok | Should -BeTrue
            $sync.session | Should -BeNullOrEmpty
            (Get-TmxTestEvents -Nome 'session.changed').Count | Should -BeGreaterOrEqual 1
        }

        It 'session.simulateFailure arma a flag no modo de teste' {
            $r = Invoke-TmxBridgeRequest -Json '{"id":"9","action":"session.simulateFailure"}' | ConvertFrom-Json
            $r.ok | Should -BeTrue
            $r.result.armado | Should -BeTrue
            $sync.simulateRestorePointFailure | Should -BeTrue
        }

        It 'session.simulateFailure nao existe fora do modo de teste' {
            $sync.testMode = $false
            $r = Invoke-TmxBridgeRequest -Json '{"id":"10","action":"session.simulateFailure"}' | ConvertFrom-Json
            $r.ok | Should -BeFalse
            $r.error.message | Should -Be 'session.simulateFailure so existe no modo de teste'
        }

        It 'session.reset nao existe fora do modo de teste' {
            $sync.testMode = $false
            $r = Invoke-TmxBridgeRequest -Json '{"id":"8","action":"session.reset"}' | ConvertFrom-Json
            $r.ok | Should -BeFalse
            $r.error.message | Should -Be 'session.reset so existe no modo de teste'
        }
    }
}
