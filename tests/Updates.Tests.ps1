# tests/Updates.Tests.ps1
# Aba Atualizacoes: tres politicas de Windows Update (UPD-001/002/003),
# reversiveis, com o servico do Windows Update NUNCA desativado.
#
# Nada aqui toca servico real: Get-/Set-TmxServiceState sao sempre mockados
# quando o teste envolve UPD-001 (funcao) ou UPD-002 (acao 'service' direta
# no catalogo). O caminho pela ponte usa o modo de teste, que reescreve as
# acoes para a raiz HKCU:\Software\TweakMaxing_Tests\Updates e DESCARTA
# qualquer acao 'service' antes de chegar no Engine - por isso o teste de
# ponte com UPD-002 nao precisa mockar nada.

. (Join-Path $PSScriptRoot '_Helpers.ps1')

Describe 'Atualizacoes' -Tag 'Updates' {

    BeforeAll {
        . (Join-Path $PSScriptRoot '_Helpers.ps1')
        Import-TmxTestModule
        New-TmxTestHome | Out-Null

        $script:TmxRepo           = Split-Path $PSScriptRoot -Parent
        $script:TmxWebRoot        = Join-Path $script:TmxRepo 'src\web'
        $script:TmxUpdatesJson    = Join-Path $script:TmxRepo 'src\config\tweaks.updates.json'
        $script:TmxUpdateTestRoot = 'HKCU:\Software\TweakMaxing_Tests\Updates'
        $script:TmxCatalogoUpd    = @(Get-TmxCatalog -Path $script:TmxUpdatesJson)

        function New-TmxUpdateTestSync {
            <#
            .SYNOPSIS
                $global:sync minimo para as acoes da ponte, com coletor de eventos.
            #>
            param([bool] $TestMode = $true)

            $s = [Hashtable]::Synchronized(@{})
            $s.version       = '0.1.0-test'
            $s.testMode      = $TestMode
            $s.webRoot       = $script:TmxWebRoot
            $s.configs       = @{}
            $s.bridgeActions = @{}
            $s.activeJob     = $null
            $s.session       = $null
            $s.uiEvents      = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList))
            $global:sync = $s
            $s
        }

        function Invoke-TmxBridgeTest {
            param([Parameter(Mandatory)] [string] $Action, $Payload)
            $req = [ordered]@{ id = [guid]::NewGuid().ToString('N'); action = $Action; payload = $Payload }
            $json = Invoke-TmxBridgeRequest -Json ($req | ConvertTo-Json -Depth 12 -Compress)
            $json | ConvertFrom-Json
        }

        function Wait-TmxJobDoneById {
            param([Parameter(Mandatory)] [string] $JobId, [int] $TimeoutSeconds = 60)
            $limite = (Get-Date).AddSeconds($TimeoutSeconds)
            while ((Get-Date) -lt $limite) {
                $copia = @()
                try { $copia = $sync.uiEvents.ToArray() } catch { $copia = @() }
                $achado = @($copia | Where-Object { $_.event -eq 'job.done' -and "$($_.payload.jobId)" -eq $JobId })
                if ($achado.Count -gt 0) { return $achado[0].payload }
                Start-Sleep -Milliseconds 100
            }
            $null
        }

        function Invoke-TmxBridgeJobTest {
            param([Parameter(Mandatory)] [string] $Action, $Payload, [int] $TimeoutSeconds = 60)
            $r = Invoke-TmxBridgeTest -Action $Action -Payload $Payload
            if (-not $r.ok -or -not $r.result.jobId) {
                return [pscustomobject]@{ resposta = $r; done = $null }
            }
            [pscustomobject]@{ resposta = $r; done = (Wait-TmxJobDoneById -JobId "$($r.result.jobId)" -TimeoutSeconds $TimeoutSeconds) }
        }

        function Start-TmxTestRunSession {
            <#
            .SYNOPSIS
                Abre a execucao DENTRO da runspace do pool (onde os jobs seguintes
                vao procurar $script:TmxRun) e publica $sync.session pronta.
            #>
            param([int] $TimeoutSeconds = 60)

            $jobId = Start-TmxJob -Name 'test.session' -Payload $null -Handler {
                param($p)
                $run = New-TmxRun
                $sync.session = @{
                    runId        = "$($run.RunId)"
                    runPath      = "$($run.RunPath)"
                    statePath    = "$($run.StatePath)"
                    restorePoint = @{ estado = 'pulado'; seq = $null; mensagem = 'suite de testes' }
                    pronto       = $true
                    undoCommand  = "TweakMaxing.ps1 -Headless -Undo $($run.RunId)"
                    criadoEm     = (Get-Date).ToString('o')
                }
                @{ ok = $true; runId = "$($run.RunId)" }
            }
            Wait-TmxJobDoneById -JobId $jobId -TimeoutSeconds $TimeoutSeconds | Out-Null
            $sync.session
        }
    }

    AfterAll {
        if (Get-Command Close-TmxRunspacePool -ErrorAction SilentlyContinue) { Close-TmxRunspacePool }
        Remove-TmxTestHome
        Remove-TmxTestKey -SubKey 'Updates'
        Remove-Variable -Name sync -Scope Global -ErrorAction SilentlyContinue
    }

    # -----------------------------------------------------------------------
    Context 'Catalogo' {

        It 'tweaks.updates.json passa pelo Test-TmxCatalog junto com o resto do catalogo' {
            $catalogo = @(Get-TmxCatalog -Path (Join-Path $script:TmxRepo 'src\config'))
            $v = Test-TmxCatalog -Catalog $catalogo
            if (-not $v.ok) { Write-Host ($v.erros -join "`n") }
            $v.ok | Should -BeTrue
        }

        It 'tem exatamente 3 tweaks UPD-*, todos radio no grupo windows-update' {
            $script:TmxCatalogoUpd.Count | Should -Be 3
            foreach ($t in $script:TmxCatalogoUpd) {
                "$($t.id)" | Should -Match '^UPD-\d{3}$'
                $t.controle | Should -Be 'radio'
                $t.grupo | Should -Be 'windows-update'
                # sem literal acentuado aqui: este arquivo .ps1 nao tem BOM e o
                # parser do PowerShell 5.1 sem BOM le UTF-8 como codepage ANSI,
                # corrompendo qualquer acento embutido direto na string (mesma
                # armadilha documentada em Engine/Catalog.ps1).
                "$($t.categoria)" | Should -Match '^Atualiza'
            }
        }

        It 'Assert-TmxUpdateServicesNeverDisabled passa no catalogo real' {
            { Assert-TmxUpdateServicesNeverDisabled -Catalogo $script:TmxCatalogoUpd } | Should -Not -Throw
        }

        It 'Assert-TmxUpdateServicesNeverDisabled lanca quando uma acao forjada desativa um servico do Windows Update' {
            $forjado = @(
                [pscustomobject]@{
                    id    = 'UPD-999'
                    acoes = @([pscustomobject]@{ tipo = 'service'; nome = 'wuauserv'; tipoInicio = 'Disabled' })
                }
            )
            { Assert-TmxUpdateServicesNeverDisabled -Catalogo $forjado } | Should -Throw '*nunca pode ser desativado*'
        }
    }

    # -----------------------------------------------------------------------
    Context 'Set-TmxUpdatePause' {

        BeforeEach {
            Remove-TmxTestKey -SubKey 'Updates'
            New-TmxRun | Out-Null
        }

        AfterEach {
            Remove-TmxTestKey -SubKey 'Updates'
        }

        It 'grava as 6 chaves de pausa com expiracao futura, deixa registro no state.json, e o undo as remove' {
            $tweak = [pscustomobject]@{ id = 'UPD-003' }
            $r = Set-TmxUpdatePause -Tweak $tweak -Profile $null -Parametros @{ dias = 35 } -RegistryRoot $script:TmxUpdateTestRoot
            $r.ok | Should -BeTrue
            @($r.registros).Count | Should -Be 6

            $p = Join-Path $script:TmxUpdateTestRoot 'Microsoft\WindowsUpdate\UX\Settings'
            $expira = (Get-ItemProperty -LiteralPath $p -Name 'PauseUpdatesExpiryTime').PauseUpdatesExpiryTime
            ([datetime]::Parse($expira)).ToUniversalTime() | Should -BeGreaterThan (Get-Date).ToUniversalTime()

            $teste = Test-TmxUpdatePause -Tweak $tweak -Profile $null -RegistryRoot $script:TmxUpdateTestRoot
            $teste.aplicado | Should -BeTrue

            $registros = @(Get-TmxState | Where-Object { "$($_.tweakId)" -eq 'UPD-003' })
            $registros.Count | Should -Be 6
            foreach ($reg in $registros) { "$($reg.status)" | Should -Be 'aplicado' }

            Undo-TweakMaxing -StatePath (Get-TmxRun).StatePath -TweakId 'UPD-003' -Quiet | Out-Null
            (Get-ItemProperty -LiteralPath $p -Name 'PauseUpdatesExpiryTime' -ErrorAction SilentlyContinue) | Should -BeNullOrEmpty
        }
    }

    # -----------------------------------------------------------------------
    Context 'Set-TmxUpdatePolicyDefault' {

        BeforeEach {
            Remove-TmxTestKey -SubKey 'Updates'
            New-TmxRun | Out-Null

            $script:TmxPolPath = Join-Path $script:TmxUpdateTestRoot 'Policies\Microsoft\Windows\WindowsUpdate'
            New-Item -Path $script:TmxPolPath -Force | Out-Null
            New-ItemProperty -Path $script:TmxPolPath -Name 'DeferFeatureUpdates' -Value 1 -PropertyType DWord -Force | Out-Null
            New-ItemProperty -Path $script:TmxPolPath -Name 'DeferFeatureUpdatesPeriodInDays' -Value 365 -PropertyType DWord -Force | Out-Null

            Mock -CommandName Get-TmxServiceState -ModuleName TweakMaxing -MockWith {
                param($Nome)
                [pscustomobject]@{ startType = 'Automatic'; status = 'Running' }
            }
            Mock -CommandName Set-TmxServiceState -ModuleName TweakMaxing -MockWith {
                param($Nome, $StartType, $Parar, $Iniciar)
            }
        }

        AfterEach {
            Remove-TmxTestKey -SubKey 'Updates'
        }

        It 'remove os valores pre-existentes com o valor anterior capturado, normaliza servicos e o undo restaura os dois' {
            $tweak = [pscustomobject]@{ id = 'UPD-001' }
            $r = Set-TmxUpdatePolicyDefault -Tweak $tweak -Profile $null -Parametros @{} -RegistryRoot $script:TmxUpdateTestRoot
            $r.ok | Should -BeTrue

            (Get-ItemProperty -LiteralPath $script:TmxPolPath -Name 'DeferFeatureUpdates' -ErrorAction SilentlyContinue) | Should -BeNullOrEmpty

            $registros = @(Get-TmxState | Where-Object { "$($_.tweakId)" -eq 'UPD-001' })
            $regDefer = @($registros | Where-Object { "$($_.detalhe.name)" -eq 'DeferFeatureUpdates' })
            $regDefer.Count | Should -Be 1
            $regDefer[0].valorAnterior | Should -Be 1

            Should -Invoke -CommandName Set-TmxServiceState -ModuleName TweakMaxing -Times 3 -Exactly

            $teste = Test-TmxUpdatePolicyDefault -Tweak $tweak -Profile $null -RegistryRoot $script:TmxUpdateTestRoot
            $teste.aplicado | Should -BeTrue

            Undo-TweakMaxing -StatePath (Get-TmxRun).StatePath -TweakId 'UPD-001' -Quiet | Out-Null
            (Get-ItemProperty -LiteralPath $script:TmxPolPath -Name 'DeferFeatureUpdates' -ErrorAction SilentlyContinue).DeferFeatureUpdates | Should -Be 1

            # 3 chamadas na aplicacao + 3 chamadas no undo (Undo-TmxUpdatePolicyDefault restaura um a um)
            Should -Invoke -CommandName Set-TmxServiceState -ModuleName TweakMaxing -Times 6 -Exactly
        }
    }

    # -----------------------------------------------------------------------
    Context 'UPD-002 via Invoke-TmxPlan (raiz HKCU)' {

        BeforeAll {
            $script:TmxUpd002 = @($script:TmxCatalogoUpd | Where-Object { "$($_.id)" -eq 'UPD-002' })[0]
        }

        BeforeEach {
            Remove-TmxTestKey -SubKey 'Updates'
            New-TmxRun | Out-Null

            # Estado falso POR SERVICO (nao um valor fixo para os tres): a
            # pos-verificacao do Engine confere cada servico contra o
            # tipoInicio esperado da propria acao (BITS/wuauserv=Manual,
            # UsoSvc=Automatic) - um mock que devolvesse sempre o mesmo valor
            # faria a verificacao de UsoSvc falhar sempre.
            $script:TmxMockSvcState = @{
                BITS     = @{ startType = 'Automatic'; status = 'Running' }
                wuauserv = @{ startType = 'Automatic'; status = 'Running' }
                UsoSvc   = @{ startType = 'Manual';    status = 'Stopped' }
            }
            Mock -CommandName Get-TmxServiceState -ModuleName TweakMaxing -MockWith {
                param($Nome)
                $s = $script:TmxMockSvcState["$Nome"]
                [pscustomobject]@{ startType = $s.startType; status = $s.status }
            }
            Mock -CommandName Set-TmxServiceState -ModuleName TweakMaxing -MockWith {
                param($Nome, $StartType, $Parar, $Iniciar)
                $script:TmxMockSvcState["$Nome"].startType = "$StartType"
                if ($Parar)   { $script:TmxMockSvcState["$Nome"].status = 'Stopped' }
                if ($Iniciar) { $script:TmxMockSvcState["$Nome"].status = 'Running' }
            }
        }

        AfterEach {
            Remove-TmxTestKey -SubKey 'Updates'
        }

        It 'grava os 12 valores de registro sob a raiz de teste e o undo os remove' {
            $prefixo = 'HKLM:\SOFTWARE'
            $acoesReescritas = @($script:TmxUpd002.acoes | ForEach-Object {
                if ("$($_.tipo)" -eq 'registry') {
                    $c = $_.PSObject.Copy()
                    $c.path = $script:TmxUpdateTestRoot + "$($_.path)".Substring($prefixo.Length)
                    $c
                } else {
                    $_
                }
            })
            $tweak = $script:TmxUpd002.PSObject.Copy()
            $tweak | Add-Member -NotePropertyName acoes -NotePropertyValue $acoesReescritas -Force

            $plano = [pscustomobject]@{
                preset   = 'manual'
                geradoEm = (Get-Date).ToString('o')
                itens    = @([pscustomobject]@{ id = "$($tweak.id)"; nome = "$($tweak.nome)"; selecionado = $true; consentido = $true; tweak = $tweak })
                resumo   = $null
            }
            $r = Invoke-TmxPlan -Plan $plano -Profile @{}
            $r.itens[0].status | Should -BeIn @('aplicado', 'aplicadoNaoVerificado')

            $regValores = @($tweak.acoes | Where-Object { "$($_.tipo)" -eq 'registry' })
            $regValores.Count | Should -Be 12
            foreach ($a in $regValores) {
                (Get-ItemProperty -LiteralPath $a.path -Name $a.name -ErrorAction SilentlyContinue).$($a.name) | Should -Be $a.value
            }

            Undo-TweakMaxing -StatePath (Get-TmxRun).StatePath -TweakId "$($tweak.id)" -Quiet | Out-Null
            foreach ($a in $regValores) {
                (Get-ItemProperty -LiteralPath $a.path -Name $a.name -ErrorAction SilentlyContinue) | Should -BeNullOrEmpty
            }
        }
    }

    # -----------------------------------------------------------------------
    Context 'Ponte' {

        BeforeEach {
            New-TmxUpdateTestSync -TestMode $true | Out-Null
            Register-TmxUpdateActions
            Remove-TmxTestKey -SubKey 'Updates'
        }

        AfterEach {
            Remove-TmxTestKey -SubKey 'Updates'
        }

        It 'updates.list devolve os 3 itens com ativo booleano e ao menos uma chave cada' {
            $r = Invoke-TmxBridgeJobTest -Action 'updates.list'
            $r.done | Should -Not -BeNullOrEmpty
            $r.done.ok | Should -BeTrue
            $itens = @($r.done.result.itens)
            $itens.Count | Should -Be 3
            foreach ($it in $itens) {
                "$($it.id)" | Should -Match '^UPD-\d{3}$'
                ($it.ativo -is [bool]) | Should -BeTrue
                @($it.chaves).Count | Should -BeGreaterThan 0
            }
        }

        It 'updates.apply sem sessao recusa antes de criar job' {
            $sync.session = $null
            $r = Invoke-TmxBridgeTest -Action 'updates.apply' -Payload @{ id = 'UPD-003' }
            $r.ok | Should -BeFalse
            "$($r.error.message)" | Should -Match 'sessao'
            $sync.activeJob | Should -BeNullOrEmpty
        }

        It 'updates.apply recusa id fora do formato UPD-NNN' {
            Start-TmxTestRunSession | Out-Null
            $r = Invoke-TmxBridgeTest -Action 'updates.apply' -Payload @{ id = 'TST-001' }
            $r.ok | Should -BeFalse
            "$($r.error.message)" | Should -Match 'atualizacoes'
        }

        It 'no modo de teste aplica UPD-003 e depois UPD-002: o primeiro e revertido antes do segundo' {
            $sessao = Start-TmxTestRunSession
            $sessao.pronto | Should -BeTrue

            $r1 = Invoke-TmxBridgeJobTest -Action 'updates.apply' -Payload @{ id = 'UPD-003' }
            $r1.done | Should -Not -BeNullOrEmpty
            $r1.done.ok | Should -BeTrue

            # regressao: a pos-verificacao do Invoke-TmxPlan tem que ler a
            # MESMA raiz de teste que Set-TmxUpdatePause escreveu (via
            # Get-TmxUpdateDefaultRegistryRoot), senao reporta 'falha' para
            # uma escrita que deu certo (Test-TmxAction 'funcao' nunca recebe
            # -Parametros do despacho generico do Engine).
            $itemUpd003 = $r1.done.result.resultado.itens[0]
            $itemUpd003.status | Should -BeIn @('aplicado', 'aplicadoNaoVerificado')

            $r2 = Invoke-TmxBridgeJobTest -Action 'updates.apply' -Payload @{ id = 'UPD-002' }
            $r2.done | Should -Not -BeNullOrEmpty
            $r2.done.ok | Should -BeTrue

            $registros = @(Import-TmxState -StatePath $sessao.statePath)
            $upd003 = @($registros | Where-Object { "$($_.tweakId)" -eq 'UPD-003' })
            $upd003.Count | Should -BeGreaterThan 0
            @($upd003 | Where-Object { "$($_.status)" -ne 'revertido' }).Count | Should -Be 0

            $upd002 = @($registros | Where-Object { "$($_.tweakId)" -eq 'UPD-002' })
            $upd002.Count | Should -Be 12
            @($upd002 | Where-Object { "$($_.tipo)" -eq 'service' }).Count | Should -Be 0

            $listaFinal = $r2.done.result.lista
            $itemAtivo = @($listaFinal.itens | Where-Object { $_.id -eq 'UPD-002' })[0]
            $itemAtivo.ativo | Should -BeTrue
        }
    }
}
