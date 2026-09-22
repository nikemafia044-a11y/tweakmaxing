# tests/Bridge.Tweaks.Tests.ps1
# Acoes da aba "Ajustes" na ponte: catalogo com os tweaks de teste, preset,
# previa antes->depois, aplicacao, alternancia e reversao (item e sessao).
#
# Nao abre janela e nao exige elevacao. Tudo que e escrito no sistema fica em
# HKCU:\Software\TweakMaxing_Tests\Gui (os tweaks TST-*), e a guarda do modo de
# teste na propria ponte recusa qualquer id fora de TST-*.
#
# Os handlers que aplicam/revertem rodam num job, porque o estado de execucao
# do Core ($script:TmxRun) vive na unica runspace do pool. Por isso a sessao e
# aberta pela propria ponte (session.start) e os resultados sao lidos do evento
# job.done em $sync.uiEvents, como em Session.Tests.ps1 / Bridge.Tests.ps1.

. (Join-Path $PSScriptRoot '_Helpers.ps1')

Describe 'Ajustes (ponte)' -Tag 'Tweaks' {

    BeforeAll {
        . (Join-Path $PSScriptRoot '_Helpers.ps1')
        Import-TmxTestModule
        New-TmxTestHome | Out-Null
        Remove-TmxTestKey -SubKey 'Gui'

        function Get-TmxTweakTestKeyPath { 'HKCU:\Software\TweakMaxing_Tests\Gui' }

        function New-TmxTweakTestSync {
            <#
            .SYNOPSIS
                $global:sync minimo para a aba Ajustes, com os configs do repo
                carregados (e o mesmo caminho que o Start-TmxDev.ps1 usa).
            #>
            $repo = Split-Path $PSScriptRoot -Parent

            $s = [Hashtable]::Synchronized(@{})
            $s.version       = '0.1.0-test'
            $s.testMode      = $true
            $s.configs       = @{}
            $s.bridgeActions = @{}
            $s.activeJob     = $null
            $s.session       = $null
            $s.tweaks        = $null
            $s.webRoot       = Join-Path $repo 'src\web'
            $s.uiEvents      = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList))

            foreach ($arquivo in (Get-ChildItem -LiteralPath (Join-Path $repo 'src\config') -Filter '*.json' -File)) {
                $s.configs[$arquivo.BaseName] = Get-Content -LiteralPath $arquivo.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            }

            $global:sync = $s
            $s
        }

        function Invoke-TmxTweakBridge {
            <#
            .SYNOPSIS
                Chama uma acao da ponte e, quando ela dispara um job, espera o
                job.done correspondente.
            .OUTPUTS
                [pscustomobject] @{ ok; mensagem; resultado }
            #>
            param(
                [Parameter(Mandatory)] [string] $Action,
                $Payload,
                [int] $TimeoutSeconds = 240
            )

            $antes = $sync.uiEvents.Count
            $json  = (@{ id = [guid]::NewGuid().ToString('N'); action = $Action; payload = $Payload } |
                      ConvertTo-Json -Depth 12 -Compress)
            $r = Invoke-TmxBridgeRequest -Json $json | ConvertFrom-Json

            if (-not $r.ok) {
                return [pscustomobject]@{ ok = $false; mensagem = "$($r.error.message)"; resultado = $null }
            }

            $jobId = $r.result.jobId
            if (-not $jobId) {
                return [pscustomobject]@{ ok = $true; mensagem = $null; resultado = $r.result }
            }

            $limite = (Get-Date).AddSeconds($TimeoutSeconds)
            while ((Get-Date) -lt $limite) {
                # .ToArray(): o wrapper sincronizado protege o metodo, mas nao a
                # enumeracao - o job escreve na lista enquanto o teste le.
                $achado = @(@($sync.uiEvents.ToArray()) | Select-Object -Skip $antes |
                            Where-Object { $_.event -eq 'job.done' -and $_.payload.jobId -eq $jobId })
                if ($achado.Count -gt 0) {
                    $p = $achado[0].payload
                    return [pscustomobject]@{
                        ok        = [bool]$p.ok
                        mensagem  = "$($p.error.message)"
                        resultado = $p.result
                    }
                }
                Start-Sleep -Milliseconds 150
            }
            [pscustomobject]@{ ok = $false; mensagem = "tempo esgotado esperando job.done de $Action"; resultado = $null }
        }

        function Get-TmxTweakTestItem {
            <#
            .SYNOPSIS
                Acha um item pelo id dentro do payload de catalog.get.
            #>
            param(
                [Parameter(Mandatory)] $Catalogo,
                [Parameter(Mandatory)] [string] $Id
            )
            foreach ($cat in @($Catalogo.categorias)) {
                foreach ($item in @($cat.itens)) {
                    if ("$($item.id)" -eq $Id) { return $item }
                }
            }
            $null
        }

        function Get-TmxTweakTestValue {
            <#
            .SYNOPSIS
                Le um valor da chave de testes ($null quando nao existe).
            #>
            param([Parameter(Mandatory)] [string] $Nome)
            $chave = Get-TmxTweakTestKeyPath
            if (-not (Test-Path -LiteralPath $chave)) { return $null }
            $p = Get-ItemProperty -LiteralPath $chave -Name $Nome -ErrorAction SilentlyContinue
            if ($null -eq $p) { return $null }
            $p.$Nome
        }

        New-TmxTweakTestSync | Out-Null
        Register-TmxShellActions
        Register-TmxSessionActions
        Register-TmxTweakActions
    }

    AfterAll {
        if (Get-Command Wait-TmxRemainingWork -ErrorAction SilentlyContinue) {
            Wait-TmxRemainingWork -TimeoutSeconds 60 | Out-Null
        }
        if (Get-Command Close-TmxRunspacePool -ErrorAction SilentlyContinue) { Close-TmxRunspacePool }
        Remove-TmxTestKey -SubKey 'Gui'
        Remove-TmxTestHome
        Remove-Variable -Name TmxTesteCatalogo -Scope Global -ErrorAction SilentlyContinue
        Remove-Variable -Name sync -Scope Global -ErrorAction SilentlyContinue
    }

    Context 'Antes de abrir a sessao' {

        It 'plan.apply recusa sem ponto de restauracao, antes de existir job' {
            $r = Invoke-TmxTweakBridge -Action 'plan.apply' -Payload @{ ids = @('TST-001') }

            $r.ok | Should -BeFalse
            $r.mensagem | Should -BeLike '*sessao sem ponto*'
            $sync.activeJob | Should -BeNullOrEmpty
        }
    }

    Context 'Catalogo, aplicacao e reversao' {

        BeforeAll {
            $abertura = Invoke-TmxTweakBridge -Action 'session.start' -Payload @{ skip = $false }
            if (-not $abertura.ok) { throw "session.start falhou: $($abertura.mensagem)" }

            $carga = Invoke-TmxTweakBridge -Action 'catalog.get' -Payload @{ preset = 'desktop' }
            if (-not $carga.ok) { throw "catalog.get falhou: $($carga.mensagem)" }
            $global:TmxTesteCatalogo = $carga.resultado
        }

        It 'catalog.get traz os tweaks de teste com tier e reversibilidade corretos' {
            $cat = $global:TmxTesteCatalogo

            $cat.preset | Should -Be 'desktop'
            @($cat.categorias).Count | Should -BeGreaterThan 1

            $t1 = Get-TmxTweakTestItem -Catalogo $cat -Id 'TST-001'
            $t2 = Get-TmxTweakTestItem -Catalogo $cat -Id 'TST-002'
            $t3 = Get-TmxTweakTestItem -Catalogo $cat -Id 'TST-003'

            $t1 | Should -Not -BeNullOrEmpty
            $t1.tier | Should -Be 'MEDIDO'
            $t1.reversivel | Should -Be 'total'
            $t1.categoria | Should -Be 'Teste'
            $t1.temUndo | Should -BeFalse

            $t2 | Should -Not -BeNullOrEmpty
            $t2.tier | Should -Be 'MEDIDO'
            $t2.controle | Should -Be 'toggle'

            $t3 | Should -Not -BeNullOrEmpty
            $t3.tier | Should -Be 'FOLCLORE'
        }

        It 'catalog.get deixa o item de folclore desmarcado e com o bloco de folclore' {
            $t3 = Get-TmxTweakTestItem -Catalogo $global:TmxTesteCatalogo -Id 'TST-003'

            $t3.selecionado | Should -BeFalse
            $t3.status | Should -Be 'folclore'
            $t3.alternavel | Should -BeTrue
            $t3.folclore | Should -Not -BeNullOrEmpty
            $t3.folclore.porqueNaoRecomendamos | Should -Not -BeNullOrEmpty
        }

        It 'catalog.get poe as categorias de Jogos depois das demais' {
            $nomes = @(@($global:TmxTesteCatalogo.categorias) | ForEach-Object { "$($_.nome)" })

            $viuJogos = $false
            $foraDeLugar = New-Object 'System.Collections.Generic.List[string]'
            foreach ($n in $nomes) {
                if ($n -like 'Jogos*') { $viuJogos = $true; continue }
                if ($viuJogos) { $foraDeLugar.Add($n) }
            }

            $viuJogos | Should -BeTrue
            $foraDeLugar.ToArray() -join ', ' | Should -Be ''
        }

        It 'preset.apply desktop seleciona TST-001 e nao seleciona TST-003' {
            $r = Invoke-TmxTweakBridge -Action 'preset.apply' -Payload @{ preset = 'desktop' }

            $r.ok | Should -BeTrue -Because $r.mensagem
            $r.resultado.preset | Should -Be 'desktop'

            (Get-TmxTweakTestItem -Catalogo $r.resultado -Id 'TST-001').selecionado | Should -BeTrue
            (Get-TmxTweakTestItem -Catalogo $r.resultado -Id 'TST-003').selecionado | Should -BeFalse
        }

        It 'plan.preview mostra o valor atual e o valor alvo de TST-001' {
            $r = Invoke-TmxTweakBridge -Action 'plan.preview' -Payload @{ ids = @('TST-001') }

            $r.ok | Should -BeTrue -Because $r.mensagem
            $linhas = @($r.resultado.itens)
            $linhas.Count | Should -Be 1
            $linhas[0].tweakId | Should -Be 'TST-001'
            $linhas[0].alvo | Should -BeLike '*TweakMaxing_Tests\Gui::Valor'
            $linhas[0].antes | Should -Be '<ausente>'
            $linhas[0].depois | Should -Be '1'
            @($r.resultado.faltaConsentimento).Count | Should -Be 0
        }

        It 'plan.apply grava o valor de TST-001 e libera o desfazer do item' {
            $r = Invoke-TmxTweakBridge -Action 'plan.apply' -Payload @{ ids = @('TST-001') }

            $r.ok | Should -BeTrue -Because $r.mensagem
            $r.resultado.resultado.aplicados | Should -Be 1
            $r.resultado.resultado.falhas | Should -Be 0
            @($r.resultado.resultado.itens)[0].status | Should -Be 'aplicado'

            Get-TmxTweakTestValue -Nome 'Valor' | Should -Be 1
            (Get-TmxTweakTestItem -Catalogo $r.resultado.catalogo -Id 'TST-001').temUndo | Should -BeTrue
        }

        It 'undo.tweak restaura TST-001 e marca o registro como revertido' {
            $r = Invoke-TmxTweakBridge -Action 'undo.tweak' -Payload @{ id = 'TST-001' }

            $r.ok | Should -BeTrue -Because $r.mensagem
            $r.resultado.resumo.revertidos | Should -BeGreaterOrEqual 1
            $r.resultado.resumo.falhas | Should -Be 0
            @($r.resultado.resumo.itens)[0].resultado | Should -Be 'revertido'

            Get-TmxTweakTestValue -Nome 'Valor' | Should -BeNullOrEmpty
        }

        It 'plan.applyToggle liga TST-002 gravando 1' {
            $r = Invoke-TmxTweakBridge -Action 'plan.applyToggle' -Payload @{ id = 'TST-002'; ligado = $true }

            $r.ok | Should -BeTrue -Because $r.mensagem
            $r.resultado.ligado | Should -BeTrue
            Get-TmxTweakTestValue -Nome 'Toggle' | Should -Be 1
        }

        It 'plan.applyToggle desliga TST-002 gravando 0' {
            $r = Invoke-TmxTweakBridge -Action 'plan.applyToggle' -Payload @{ id = 'TST-002'; ligado = $false }

            $r.ok | Should -BeTrue -Because $r.mensagem
            $r.resultado.ligado | Should -BeFalse
            Get-TmxTweakTestValue -Nome 'Toggle' | Should -Be 0
        }

        It 'plan.apply recusa qualquer id fora de TST- no modo de teste' {
            $r = Invoke-TmxTweakBridge -Action 'plan.apply' -Payload @{ ids = @('PRI-001') }

            $r.ok | Should -BeFalse
            $r.mensagem | Should -Be 'modo de teste: apenas tweaks TST-*'
        }

        It 'plan.apply so aceita o item irreversivel depois da frase exata' {
            $sel = Invoke-TmxTweakBridge -Action 'plan.setSelection' -Payload @{ id = 'TST-004'; selecionado = $true }
            $sel.resultado.ok | Should -BeTrue

            $semConsentimento = Invoke-TmxTweakBridge -Action 'plan.apply' -Payload @{ ids = @('TST-004') }
            $semConsentimento.ok | Should -BeFalse
            $semConsentimento.mensagem | Should -BeLike '*consentimento pendente*TST-004*'

            $errada = Invoke-TmxTweakBridge -Action 'plan.setConsent' -Payload @{ id = 'TST-004'; frase = 'aceito acao irreversivel' }
            $errada.resultado.ok | Should -BeFalse
            $errada.resultado.mensagem | Should -Be 'frase incorreta'

            $certa = Invoke-TmxTweakBridge -Action 'plan.setConsent' -Payload @{ id = 'TST-004'; frase = 'ACEITO ACAO IRREVERSIVEL' }
            $certa.resultado.ok | Should -BeTrue

            $aplicado = Invoke-TmxTweakBridge -Action 'plan.apply' -Payload @{ ids = @('TST-004') }
            $aplicado.ok | Should -BeTrue -Because $aplicado.mensagem
            Get-TmxTweakTestValue -Nome 'Irreversivel' | Should -Be 1
        }

        It 'undo.run reverte tudo o que a execucao gravou' {
            $r = Invoke-TmxTweakBridge -Action 'undo.run' -Payload @{}

            $r.ok | Should -BeTrue -Because $r.mensagem
            $r.resultado.atual | Should -BeTrue
            $r.resultado.resumo.revertidos | Should -BeGreaterOrEqual 1
            $r.resultado.resumo.falhas | Should -Be 0
            $r.resultado.catalogo | Should -Not -BeNullOrEmpty

            Get-TmxTweakTestValue -Nome 'Toggle' | Should -BeNullOrEmpty
            Get-TmxTweakTestValue -Nome 'Irreversivel' | Should -BeNullOrEmpty
        }

        It 'runs.list traz a execucao atual com registros revertidos' {
            $r = Invoke-TmxTweakBridge -Action 'runs.list' -Payload @{}

            $r.ok | Should -BeTrue -Because $r.mensagem
            $execucoes = @($r.resultado.execucoes)
            $execucoes.Count | Should -BeGreaterOrEqual 1

            $atual = @($execucoes | Where-Object { $_.atual })
            $atual.Count | Should -Be 1
            $atual[0].runId | Should -Be "$($sync.session.runId)"
            $atual[0].revertidos | Should -BeGreaterThan 0
        }

        It 'undo.command devolve o comando de reversao da sessao' {
            $r = Invoke-TmxTweakBridge -Action 'undo.command' -Payload @{}

            $r.ok | Should -BeTrue
            $r.resultado.comando | Should -Be "TweakMaxing.ps1 -Headless -Undo $($sync.session.runId)"
        }
    }
}

Describe 'Aplicacao em lote com a sessao caindo no meio' -Tag 'Tweaks' {

    # Assert-TmxTweakApplyReady confere a sessao UMA vez, antes do job. Uma
    # lista longa leva minutos, e nesse intervalo a janela pode fechar ou o
    # usuario reverter tudo: daquele ponto em diante nada mais pode ser
    # escrito. Aqui o segundo id tem que sair 'pulado', nao aplicado.

    BeforeAll {
        . (Join-Path $PSScriptRoot '_Helpers.ps1')
        Import-TmxTestModule

        function New-TmxLoteItem {
            param([string] $Id, [string] $Nome)
            [pscustomobject]@{
                id          = $Id
                nome        = $Nome
                tier        = 'MEDIDO'
                consentido  = $true
                selecionado = $true
                tweak       = [pscustomobject]@{ id = $Id; nome = $Nome; controle = 'checkbox'; acoes = @(); opcoes = @() }
            }
        }
    }

    AfterAll {
        Remove-Variable -Name sync -Scope Global -ErrorAction SilentlyContinue
        Remove-Module TweakMaxing -Force -ErrorAction SilentlyContinue
    }

    BeforeEach {
        $s = [Hashtable]::Synchronized(@{})
        $s.testMode  = $true
        $s.activeJob = $null
        $s.session   = @{ runId = 'run-de-teste'; pronto = $true }
        $s.tweaks    = @{
            catalog     = @()
            profile     = @{}
            preset      = 'desktop'
            carregadoEm = (Get-Date)
            plan        = [pscustomobject]@{
                itens = @((New-TmxLoteItem -Id 'TST-001' -Nome 'um'), (New-TmxLoteItem -Id 'TST-002' -Nome 'dois'))
            }
        }
        $global:sync = $s
    }

    It 'para no ponto da queda e marca os ids restantes como pulado' {
        Mock -ModuleName TweakMaxing -CommandName Send-TmxJobProgress          -MockWith { }
        Mock -ModuleName TweakMaxing -CommandName Get-TmxTweakEffectiveActions -MockWith { @() }
        Mock -ModuleName TweakMaxing -CommandName New-TmxTweakVariant          -MockWith { $Tweak }
        Mock -ModuleName TweakMaxing -CommandName New-TmxTweakSingleItemPlan   -MockWith { [pscustomobject]@{ itens = @() } }
        Mock -ModuleName TweakMaxing -CommandName Invoke-TmxPlan -MockWith {
            # a sessao acaba enquanto o primeiro id e aplicado
            $sync.session.pronto = $false
            [pscustomobject]@{ itens = @([pscustomobject]@{
                id = 'TST-001'; nome = 'um'; tier = 'MEDIDO'; status = 'aplicado'
                detalhe = 'ok'; antes = '0'; depois = '1'; registros = 1; requerReboot = $false; avisos = @()
            }) }
        }

        $r = Invoke-TmxTweakApplyIds -Ids @('TST-001', 'TST-002')

        @($r.itens).Count   | Should -Be 2
        $r.itens[0].id      | Should -Be 'TST-001'
        $r.itens[0].status  | Should -Be 'aplicado'
        $r.itens[1].id      | Should -Be 'TST-002'
        $r.itens[1].status  | Should -Be 'pulado'
        $r.itens[1].detalhe | Should -Be 'sessao encerrada'

        $r.aplicados | Should -Be 1
        $r.pulados   | Should -Be 1

        # O segundo id nunca chegou ao Engine.
        Should -Invoke -ModuleName TweakMaxing -CommandName Invoke-TmxPlan -Times 1 -Exactly
    }

    It 'com a sessao de pe aplica os dois ids' {
        Mock -ModuleName TweakMaxing -CommandName Send-TmxJobProgress          -MockWith { }
        Mock -ModuleName TweakMaxing -CommandName Get-TmxTweakEffectiveActions -MockWith { @() }
        Mock -ModuleName TweakMaxing -CommandName New-TmxTweakVariant          -MockWith { $Tweak }
        Mock -ModuleName TweakMaxing -CommandName New-TmxTweakSingleItemPlan   -MockWith { [pscustomobject]@{ itens = @() } }
        Mock -ModuleName TweakMaxing -CommandName Invoke-TmxPlan -MockWith {
            [pscustomobject]@{ itens = @([pscustomobject]@{
                id = 'X'; nome = 'x'; tier = 'MEDIDO'; status = 'aplicado'
                detalhe = 'ok'; antes = '0'; depois = '1'; registros = 1; requerReboot = $false; avisos = @()
            }) }
        }

        $r = Invoke-TmxTweakApplyIds -Ids @('TST-001', 'TST-002')

        $r.aplicados | Should -Be 2
        $r.pulados   | Should -Be 0
        Should -Invoke -ModuleName TweakMaxing -CommandName Invoke-TmxPlan -Times 2 -Exactly
    }
}
