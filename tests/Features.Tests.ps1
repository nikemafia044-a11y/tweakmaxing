# tests/Features.Tests.ps1
# Aba Configurar: catalogo de recursos (DISM) convertido em tweaks
# transitorios, correcoes de manutencao, paineis legados, DNS e as acoes da
# ponte. Nao abre janela e nao exige elevacao.
#
# Nada aqui toca o sistema de verdade: todo wrapper que chamaria netsh, dism,
# sfc, w32tm, regsvr32, servico ou tarefa agendada e mockado, e o unico
# recurso realmente aplicado e o sintetico REC-TST, que escreve em
# HKCU:\Software\TweakMaxing_Tests\Features.

. (Join-Path $PSScriptRoot '_Helpers.ps1')

Describe 'Configurar' -Tag 'Features' {

    BeforeAll {
        . (Join-Path $PSScriptRoot '_Helpers.ps1')
        Import-TmxTestModule
        New-TmxTestHome | Out-Null

        $script:TmxRepo        = Split-Path $PSScriptRoot -Parent
        $script:TmxFeatureJson = Join-Path $script:TmxRepo 'src\config\feature.json'
        $script:TmxWebRoot     = Join-Path $script:TmxRepo 'src\web'
        $script:TmxChaveTeste  = 'HKCU:\Software\TweakMaxing_Tests\Features'

        function New-TmxFeatureTestSync {
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
            $s.features      = $null
            $s.uiEvents      = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList))
            $global:sync = $s
            $s
        }

        function Invoke-TmxBridgeTest {
            <#
            .SYNOPSIS
                Chama uma acao da ponte pelo caminho real (JSON -> handler -> JSON).
            #>
            param(
                [Parameter(Mandatory)] [string] $Action,
                $Payload
            )
            $req = [ordered]@{ id = [guid]::NewGuid().ToString('N'); action = $Action; payload = $Payload }
            $json = Invoke-TmxBridgeRequest -Json ($req | ConvertTo-Json -Depth 12 -Compress)
            $json | ConvertFrom-Json
        }

        function Wait-TmxJobDoneById {
            param(
                [Parameter(Mandatory)] [string] $JobId,
                [int] $TimeoutSeconds = 60
            )
            $limite = (Get-Date).AddSeconds($TimeoutSeconds)
            while ((Get-Date) -lt $limite) {
                # .ToArray() (metodo sincronizado do wrapper) e nao o pipeline
                # direto: o job escreve em $sync.uiEvents de outra runspace e
                # enumerar a lista enquanto ela cresce lanca "Colecao foi
                # modificada" - uma falha intermitente que nao tem nada a ver
                # com o que o teste quer verificar.
                $copia = @()
                try { $copia = $sync.uiEvents.ToArray() } catch { $copia = @() }
                $achado = @($copia | Where-Object { $_.event -eq 'job.done' -and "$($_.payload.jobId)" -eq $JobId })
                if ($achado.Count -gt 0) { return $achado[0].payload }
                Start-Sleep -Milliseconds 100
            }
            $null
        }

        function Invoke-TmxBridgeJobTest {
            <#
            .SYNOPSIS
                Chama a acao e espera o job.done correspondente.
            .OUTPUTS
                { resposta; done } - 'done' fica $null quando a acao nem criou job.
            #>
            param(
                [Parameter(Mandatory)] [string] $Action,
                $Payload,
                [int] $TimeoutSeconds = 60
            )
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
            .NOTES
                Nao usa session.start de proposito: a suite nao precisa (nem quer)
                exercitar guardas e ponto de restauracao aqui - isso e da
                Session.Tests. O que importa e que o run nasca na MESMA runspace
                em que features.apply e dns.apply vao rodar.
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

        function Invoke-TmxUndoInJob {
            param([Parameter(Mandatory)] [string] $TweakId, [int] $TimeoutSeconds = 60)
            $jobId = Start-TmxJob -Name 'test.undo' -Payload @{ id = $TweakId; runId = "$($sync.session.runId)" } -Handler {
                param($p)
                $r = Undo-TweakMaxing -RunId "$($p.runId)" -TweakId "$($p.id)" -Quiet
                @{ revertidos = [int]$r.revertidos; falhas = [int]$r.falhas; total = [int]$r.total }
            }
            Wait-TmxJobDoneById -JobId $jobId -TimeoutSeconds $TimeoutSeconds
        }

        function Get-TmxTestRegValue {
            param([Parameter(Mandatory)] [string] $Path, [Parameter(Mandatory)] [string] $Name)
            $p = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue
            if ($null -eq $p -or -not ($p.PSObject.Properties.Name -contains $Name)) { return $null }
            $p.$Name
        }
    }

    AfterAll {
        if (Get-Command Close-TmxRunspacePool -ErrorAction SilentlyContinue) { Close-TmxRunspacePool }
        Remove-TmxTestHome
        Remove-TmxTestKey -SubKey 'Features'
        Remove-Variable -Name sync -Scope Global -ErrorAction SilentlyContinue
    }

    # -----------------------------------------------------------------------
    Context 'Catalogo de recursos' {

        BeforeAll {
            . (Join-Path $PSScriptRoot '_Helpers.ps1')
            $script:TmxCatFeatures = @(Get-TmxFeatureCatalog -Path $script:TmxFeatureJson -IncluirTeste $false)
        }

        It 'monta pelo menos 6 recursos com id no formato REC-NNN' {
            $script:TmxCatFeatures.Count | Should -BeGreaterOrEqual 6
            foreach ($t in $script:TmxCatFeatures) { "$($t.id)" | Should -Match '^REC-\d{3}$' }
        }

        It 'numera na ordem do arquivo, comecando em REC-001' {
            "$($script:TmxCatFeatures[0].id)" | Should -Be 'REC-001'
            "$($script:TmxCatFeatures[1].id)" | Should -Be 'REC-002'
        }

        It 'passa pelo Test-TmxCatalog como qualquer tweak de producao' {
            $v = Test-TmxCatalog -Catalog $script:TmxCatFeatures
            if (-not $v.ok) { Write-Host ($v.erros -join "`n") }
            $v.ok | Should -BeTrue
        }

        It 'gera uma acao feature Enabled por nome de DISM e o espelho Disabled' {
            $wsl = @($script:TmxCatFeatures | Where-Object { "$($_.winutilId)" -eq 'WPFFeaturewsl' })[0]
            $wsl | Should -Not -BeNullOrEmpty
            @($wsl.acoes).Count | Should -Be 2
            @($wsl.acoes | Where-Object { "$($_.estado)" -eq 'Enabled' }).Count | Should -Be 2
            @($wsl.toggleDesligar | Where-Object { "$($_.estado)" -eq 'Disabled' }).Count | Should -Be 2
            $wsl.controle | Should -Be 'toggle'
            $wsl.requerReboot | Should -BeTrue
        }

        It 'marca o NFS como reversao parcial e explica o porque na evidencia' {
            $nfs = @($script:TmxCatFeatures | Where-Object { "$($_.winutilId)" -eq 'WPFFeaturenfs' })[0]
            $nfs.reversivel | Should -Be 'parcial'
            "$($nfs.parcialNota)" | Should -Match 'nfsadmin'
            "$($nfs.evidencia)"  | Should -Match 'nfsadmin'
        }

        It 'converte RegBackup e Legacy Recovery em acoes de funcao com o trio completo' {
            foreach ($par in @(
                @{ winutil = 'WPFFeatureRegBackup';            funcao = 'Set-TmxRegBackupTask' },
                @{ winutil = 'WPFFeatureEnableLegacyRecovery'; funcao = 'Set-TmxLegacyRecovery' }
            )) {
                $t = @($script:TmxCatFeatures | Where-Object { "$($_.winutilId)" -eq $par.winutil })[0]
                $t | Should -Not -BeNullOrEmpty
                "$($t.acoes[0].tipo)" | Should -Be 'funcao'
                "$($t.acoes[0].nome)" | Should -Be $par.funcao
                $sufixo = $par.funcao.Substring('Set-Tmx'.Length)
                Get-Command "Undo-Tmx$sufixo" -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
                Get-Command "Test-Tmx$sufixo" -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
            }
        }

        It 'absorve o botao "Disable" do Legacy Recovery no toggleDesligar' {
            @($script:TmxCatFeatures | Where-Object { "$($_.winutilId)" -eq 'WPFFeatureDisableLegacyRecovery' }).Count | Should -Be 0
            $t = @($script:TmxCatFeatures | Where-Object { "$($_.winutilId)" -eq 'WPFFeatureEnableLegacyRecovery' })[0]
            "$($t.toggleDesligar[0].parametros.modo)" | Should -Be 'standard'
            "$($t.acoes[0].parametros.modo)" | Should -Be 'legacy'
        }

        It 'acrescenta REC-TST quando o modo de teste pede' {
            $comTeste = @(Get-TmxFeatureCatalog -Path $script:TmxFeatureJson -IncluirTeste $true)
            @($comTeste | Where-Object { "$($_.id)" -eq 'REC-TST' }).Count | Should -Be 1
        }
    }

    # -----------------------------------------------------------------------
    Context 'Paineis legados' {

        BeforeAll {
            . (Join-Path $PSScriptRoot '_Helpers.ps1')
        }

        BeforeEach {
            New-TmxFeatureTestSync -TestMode $false | Out-Null
        }

        It 'lista exatamente 14 paineis, todos com id, nome e comando' {
            $p = @(Get-TmxPanelCatalog)
            $p.Count | Should -Be 14
            foreach ($x in $p) {
                "$($x.id)"      | Should -Not -BeNullOrEmpty
                "$($x.nome)"    | Should -Not -BeNullOrEmpty
                "$($x.comando)" | Should -Not -BeNullOrEmpty
            }
        }

        It 'recusa um id fora da tabela fixa' {
            { Open-TmxPanel -Id 'PAN-INVENTADO' } | Should -Throw '*painel desconhecido*'
        }

        It 'recusa um comando arbitrario passado como id' {
            { Open-TmxPanel -Id 'calc.exe' } | Should -Throw '*painel desconhecido*'
        }

        It 'abre um id conhecido com o comando exato da tabela' {
            $script:comandoAberto = $null
            Mock -CommandName Start-TmxPanelProcess -ModuleName TweakMaxing -MockWith {
                param($Comando)
                $script:comandoAberto = $Comando
                $Comando
            }
            $r = Open-TmxPanel -Id 'PAN-NETWORK'
            $script:comandoAberto | Should -Be 'ncpa.cpl'
            $r.simulado | Should -BeFalse
            Should -Invoke -CommandName Start-TmxPanelProcess -ModuleName TweakMaxing -Times 1 -Exactly
        }

        It 'no modo de teste registra a chamada e nao abre nada' {
            New-TmxFeatureTestSync -TestMode $true | Out-Null
            Mock -CommandName Start-TmxPanelProcess -ModuleName TweakMaxing -MockWith { param($Comando) $Comando }
            $r = Open-TmxPanel -Id 'PAN-CONTROL'
            $r.simulado | Should -BeTrue
            Should -Invoke -CommandName Start-TmxPanelProcess -ModuleName TweakMaxing -Times 0 -Exactly
        }
    }

    # -----------------------------------------------------------------------
    Context 'Correcoes' {

        BeforeAll {
            . (Join-Path $PSScriptRoot '_Helpers.ps1')
        }

        BeforeEach {
            New-TmxFeatureTestSync -TestMode $false | Out-Null
            $script:chamadas = New-Object System.Collections.ArrayList
        }

        It 'Invoke-TmxFixNetwork chama o netsh duas vezes, winsock antes de int ip' {
            Mock -CommandName Invoke-TmxNetsh -ModuleName TweakMaxing -MockWith {
                param($Arguments)
                [void]$script:chamadas.Add(($Arguments -join ' '))
                [pscustomobject]@{ saida = ''; codigo = 0 }
            }

            $r = Invoke-TmxFixNetwork
            $r.ok | Should -BeTrue
            Should -Invoke -CommandName Invoke-TmxNetsh -ModuleName TweakMaxing -Times 2 -Exactly
            $script:chamadas[0] | Should -Be 'winsock reset'
            $script:chamadas[1] | Should -Be 'int ip reset'
            @($r.passos).Count | Should -Be 2
        }

        It 'Invoke-TmxFixWinget delega para Install-TmxWinget -Force' {
            Mock -CommandName Install-TmxWinget -ModuleName TweakMaxing -MockWith {
                [pscustomobject]@{ ok = $true; detalhe = 'winget reparado' }
            }
            $r = Invoke-TmxFixWinget
            $r.ok | Should -BeTrue
            $r.detalhe | Should -Be 'winget reparado'
            Should -Invoke -CommandName Install-TmxWinget -ModuleName TweakMaxing -Times 1 -Exactly
        }

        It 'Invoke-TmxFixAutoLogon so abre a pagina https e nao baixa nada' {
            $script:urlAberta = $null
            Mock -CommandName Start-TmxUrl -ModuleName TweakMaxing -MockWith { param($Url) $script:urlAberta = $Url; $Url }
            Mock -CommandName Invoke-TmxProcess -ModuleName TweakMaxing -MockWith { [pscustomobject]@{ codigo = 0 } }
            Mock -CommandName Invoke-TmxWebRequestText -ModuleName TweakMaxing -MockWith { '' }

            $r = Invoke-TmxFixAutoLogon
            $r.ok | Should -BeTrue
            $script:urlAberta | Should -Be 'https://learn.microsoft.com/sysinternals/downloads/autologon'
            Should -Invoke -CommandName Invoke-TmxProcess -ModuleName TweakMaxing -Times 0 -Exactly
            Should -Invoke -CommandName Invoke-TmxWebRequestText -ModuleName TweakMaxing -Times 0 -Exactly
        }

        It 'Invoke-TmxFixSystemRepair roda o DISM antes do sfc' {
            Mock -CommandName Invoke-TmxDism -ModuleName TweakMaxing -MockWith {
                param($Arguments)
                [void]$script:chamadas.Add('dism ' + ($Arguments -join ' '))
                [pscustomobject]@{ saida = ''; codigo = 0 }
            }
            Mock -CommandName Invoke-TmxSfc -ModuleName TweakMaxing -MockWith {
                param($Arguments)
                [void]$script:chamadas.Add('sfc ' + ($Arguments -join ' '))
                [pscustomobject]@{ saida = ''; codigo = 0 }
            }

            $r = Invoke-TmxFixSystemRepair
            $r.ok | Should -BeTrue
            $script:chamadas[0] | Should -Be 'dism /Online /Cleanup-Image /RestoreHealth'
            $script:chamadas[1] | Should -Be 'sfc /scannow'
        }
    }

    # -----------------------------------------------------------------------
    Context 'Correcao do Windows Update' {

        BeforeAll {
            . (Join-Path $PSScriptRoot '_Helpers.ps1')
        }

        BeforeEach {
            New-TmxFeatureTestSync -TestMode $false | Out-Null
            Mock -CommandName Stop-TmxWindowsService      -ModuleName TweakMaxing -MockWith { param($Nome) [pscustomobject]@{ ok = $true; detalhe = "$Nome parado" } }
            Mock -CommandName Start-TmxWindowsService     -ModuleName TweakMaxing -MockWith { param($Nome) [pscustomobject]@{ ok = $true; detalhe = "$Nome iniciado" } }
            Mock -CommandName Set-TmxWindowsServiceStartup -ModuleName TweakMaxing -MockWith { param($Nome, $Tipo) [pscustomobject]@{ ok = $true; detalhe = "$Nome -> $Tipo" } }
            Mock -CommandName Remove-TmxFilePattern       -ModuleName TweakMaxing -MockWith { param($Padrao) [pscustomobject]@{ ok = $true; detalhe = "removido: $Padrao" } }
            Mock -CommandName Rename-TmxPathItem          -ModuleName TweakMaxing -MockWith { param($Path, $NovoNome) [pscustomobject]@{ ok = $true; detalhe = "$Path -> $NovoNome" } }
            Mock -CommandName Invoke-TmxRegsvr32          -ModuleName TweakMaxing -MockWith { param($Dll) [pscustomobject]@{ saida = ''; codigo = 0 } }
            Mock -CommandName Invoke-TmxNetsh             -ModuleName TweakMaxing -MockWith { param($Arguments) [pscustomobject]@{ saida = ''; codigo = 0 } }
            Mock -CommandName Clear-TmxBitsTransfers      -ModuleName TweakMaxing -MockWith { [pscustomobject]@{ ok = $true; detalhe = 'fila vazia' } }
            Mock -CommandName Invoke-TmxWuauclt           -ModuleName TweakMaxing -MockWith { param($Arguments) [pscustomobject]@{ saida = ''; codigo = 0 } }
            Mock -CommandName Invoke-TmxUsoClient         -ModuleName TweakMaxing -MockWith { param($Arguments) [pscustomobject]@{ saida = ''; codigo = 0 } }
            Mock -CommandName Set-TmxRegistry             -ModuleName TweakMaxing -MockWith {
                param($Path, $Name, $Value, $Type, $TweakId, $Remove, $PassThru)
                [pscustomobject]@{ status = 'aplicado'; existiaAntes = $false; valorAnterior = $null }
            }
        }

        It 'sem -Aggressive nao renomeia SoftwareDistribution e mantem a ordem dos 5 primeiros passos' {
            $r = Invoke-TmxFixUpdate
            Should -Invoke -CommandName Rename-TmxPathItem -ModuleName TweakMaxing -Times 0 -Exactly
            $nomes = @($r.passos | ForEach-Object { "$($_.nome)" })
            $nomes[0] | Should -Be 'parar-servicos'
            $nomes[1] | Should -Be 'remover-qmgr'
            $nomes[2] | Should -Be 'remover-log'
            $nomes[3] | Should -Be 'reregistrar-dlls'
            $nomes[4] | Should -Be 'remover-wsus'
            $nomes | Should -Not -Contain 'renomear-softwaredistribution'
        }

        It 'com -Aggressive renomeia SoftwareDistribution no terceiro passo' {
            $r = Invoke-TmxFixUpdate -Aggressive
            Should -Invoke -CommandName Rename-TmxPathItem -ModuleName TweakMaxing -Times 3 -Exactly
            $nomes = @($r.passos | ForEach-Object { "$($_.nome)" })
            $nomes[0] | Should -Be 'parar-servicos'
            $nomes[1] | Should -Be 'remover-qmgr'
            $nomes[2] | Should -Be 'renomear-softwaredistribution'
            $nomes[3] | Should -Be 'remover-log'
            $nomes[4] | Should -Be 'reregistrar-dlls'
        }

        It 'para os quatro servicos do Windows Update e os religa depois' {
            Invoke-TmxFixUpdate | Out-Null
            Should -Invoke -CommandName Stop-TmxWindowsService  -ModuleName TweakMaxing -Times 4 -Exactly
            Should -Invoke -CommandName Start-TmxWindowsService -ModuleName TweakMaxing -Times 4 -Exactly
        }
    }

    # -----------------------------------------------------------------------
    Context 'Correcao do servidor de horario' {

        BeforeAll {
            . (Join-Path $PSScriptRoot '_Helpers.ps1')
            $script:TmxNtpKey = Join-Path $script:TmxChaveTeste 'W32Time'
        }

        BeforeEach {
            New-TmxFeatureTestSync -TestMode $false | Out-Null
            Remove-TmxTestKey -SubKey 'Features\W32Time'
            New-Item -Path $script:TmxNtpKey -Force | Out-Null
            New-ItemProperty -Path $script:TmxNtpKey -Name 'NtpServer' -Value 'time.windows.com,0x9' -PropertyType String -Force | Out-Null
            New-TmxRun | Out-Null
            Mock -CommandName Invoke-TmxW32tm -ModuleName TweakMaxing -MockWith { param($Arguments) [pscustomobject]@{ saida = ''; codigo = 0 } }
        }

        AfterEach {
            Remove-TmxTestKey -SubKey 'Features\W32Time'
        }

        It 'grava pool.ntp.org guardando o servidor anterior, e o undo devolve o original' {
            $r = Invoke-TmxFixNtp -RegistryPath $script:TmxNtpKey
            $r.ok | Should -BeTrue

            (Get-TmxTestRegValue -Path $script:TmxNtpKey -Name 'NtpServer') | Should -Be 'pool.ntp.org,0x8'
            $passo = @($r.passos | Where-Object { $_.nome -eq 'registrar-ntpserver' })[0]
            "$($passo.saida)" | Should -Match 'time\.windows\.com'

            $registros = @(Get-TmxState | Where-Object { "$($_.tweakId)" -eq 'FIX-NTP' })
            $registros.Count | Should -Be 1
            "$($registros[0].valorAnterior)" | Should -Be 'time.windows.com,0x9'

            Undo-TweakMaxing -StatePath (Get-TmxRun).StatePath -Quiet | Out-Null
            (Get-TmxTestRegValue -Path $script:TmxNtpKey -Name 'NtpServer') | Should -Be 'time.windows.com,0x9'
        }

        It 'configura o w32tm com a lista manual e sincroniza depois' {
            Invoke-TmxFixNtp -RegistryPath $script:TmxNtpKey | Out-Null
            Should -Invoke -CommandName Invoke-TmxW32tm -ModuleName TweakMaxing -Times 2 -Exactly
            Should -Invoke -CommandName Invoke-TmxW32tm -ModuleName TweakMaxing -Times 1 -Exactly -ParameterFilter {
                ($Arguments -join ' ') -eq '/config /manualpeerlist:pool.ntp.org,0x8 /syncfromflags:manual /update'
            }
            Should -Invoke -CommandName Invoke-TmxW32tm -ModuleName TweakMaxing -Times 1 -Exactly -ParameterFilter {
                ($Arguments -join ' ') -eq '/resync'
            }
        }
    }

    # -----------------------------------------------------------------------
    Context 'DNS' {

        BeforeAll {
            . (Join-Path $PSScriptRoot '_Helpers.ps1')
        }

        BeforeEach {
            New-TmxFeatureTestSync -TestMode $false | Out-Null
        }

        It 'le os 8 provedores do dns.json' {
            $c = @(Get-TmxDnsCatalog -Path (Join-Path $script:TmxRepo 'src\config\dns.json'))
            $c.Count | Should -Be 8
            @($c | Where-Object { $_.benchmark }).Count | Should -BeGreaterOrEqual 2
        }

        It 'mede so os provedores elegiveis e ordena do mais rapido para o mais lento' {
            Mock -CommandName Get-TmxDnsCatalog -ModuleName TweakMaxing -MockWith {
                @(
                    [pscustomobject]@{ id = 'Lento';    nome = 'Lento';    primario = '10.0.0.3'; benchmark = $true }
                    [pscustomobject]@{ id = 'Rapido';   nome = 'Rapido';   primario = '10.0.0.1'; benchmark = $true }
                    [pscustomobject]@{ id = 'Filtrado'; nome = 'Filtrado'; primario = '10.0.0.9'; benchmark = $false }
                    [pscustomobject]@{ id = 'Mudo';     nome = 'Mudo';     primario = '10.0.0.4'; benchmark = $true }
                )
            }
            Mock -CommandName Measure-TmxDnsQuery -ModuleName TweakMaxing -MockWith {
                param($Servidor, $Nome)
                switch ($Servidor) {
                    '10.0.0.1' { 10 }
                    '10.0.0.3' { 40 }
                    default    { $null }
                }
            }

            $r = @(Get-TmxDnsBenchmark -Amostras 3)
            $r.Count | Should -Be 3
            $r[0].id | Should -Be 'Rapido'
            $r[0].medioMs | Should -Be 10
            $r[1].id | Should -Be 'Lento'
            $r[1].medioMs | Should -Be 40
            $r[2].id | Should -Be 'Mudo'
            $r[2].medioMs | Should -BeNullOrEmpty
            $r[2].falhas | Should -Be 3
            @($r | Where-Object { $_.id -eq 'Filtrado' }).Count | Should -Be 0
            Should -Invoke -CommandName Measure-TmxDnsQuery -ModuleName TweakMaxing -Times 9 -Exactly
        }

        It 'Get-TmxDnsCurrent devolve adaptadores, nao um array dentro de outro' {
            Mock -CommandName Get-TmxDnsEstadoAtual -ModuleName TweakMaxing -MockWith {
                , @([pscustomobject]@{ indice = 7; nome = 'Ethernet'; v4 = @('8.8.8.8'); v6 = @() })
            }
            $c = @(Get-TmxDnsCurrent)
            $c.Count | Should -Be 1
            $c[0] -is [array] | Should -BeFalse
            "$($c[0].nome)" | Should -Be 'Ethernet'
        }

        It 'dns.list nao inventa um servidor em branco quando nao ha IPv6' {
            Mock -CommandName Get-TmxDnsEstadoAtual -ModuleName TweakMaxing -MockWith {
                , @([pscustomobject]@{ indice = 7; nome = 'Ethernet'; v4 = @('8.8.8.8'); v6 = @() })
            }
            $p = Get-TmxDnsListPayload
            @($p.atual).Count | Should -Be 1
            @($p.atual[0].v4).Count | Should -Be 1
            @($p.atual[0].v6).Count | Should -Be 0
        }

        It 'monta o tweak transitorio RED-DNS com a funcao Set-TmxDns' {
            $t = New-TmxDnsTweak -Provedor 'Cloudflare'
            $t.id | Should -Be 'RED-DNS'
            "$($t.acoes[0].tipo)" | Should -Be 'funcao'
            "$($t.acoes[0].nome)" | Should -Be 'Set-TmxDns'
            "$($t.acoes[0].parametros.provedor)" | Should -Be 'Cloudflare'
        }
    }

    # -----------------------------------------------------------------------
    Context 'Ponte' {

        BeforeAll {
            . (Join-Path $PSScriptRoot '_Helpers.ps1')
        }

        BeforeEach {
            New-TmxFeatureTestSync -TestMode $true | Out-Null
            Register-TmxFeatureActions
            Remove-TmxTestKey -SubKey 'Features'
        }

        It 'features.list devolve pelo menos 6 recursos, cada um com estado' {
            $r = Invoke-TmxBridgeJobTest -Action 'features.list'
            $r.done | Should -Not -BeNullOrEmpty
            $r.done.ok | Should -BeTrue
            $recursos = @($r.done.result.recursos)
            $recursos.Count | Should -BeGreaterOrEqual 6
            foreach ($x in $recursos) {
                "$($x.id)"     | Should -Match '^REC-'
                "$($x.estado)" | Should -BeIn @('Enabled', 'Disabled', 'desconhecido')
            }
        }

        It 'fixes.list descreve as correcoes em pt-BR com o aviso do que sera feito' {
            $r = Invoke-TmxBridgeTest -Action 'fixes.list'
            $r.ok | Should -BeTrue
            $c = @($r.result.correcoes)
            $c.Count | Should -BeGreaterOrEqual 6
            $update = @($c | Where-Object { $_.id -eq 'FIX-UPDATE' })[0]
            $update.requerSessao   | Should -BeTrue
            $update.opcaoAgressiva | Should -BeTrue
            @($update.aviso).Count | Should -BeGreaterThan 3
            $rede = @($c | Where-Object { $_.id -eq 'FIX-NET' })[0]
            $rede.requerSessao | Should -BeFalse
        }

        It 'panels.list devolve os 14 paineis e panels.open recusa id desconhecido' {
            $r = Invoke-TmxBridgeTest -Action 'panels.list'
            @($r.result.paineis).Count | Should -Be 14

            $ruim = Invoke-TmxBridgeTest -Action 'panels.open' -Payload @{ id = 'PAN-NAO-EXISTE' }
            $ruim.ok | Should -BeFalse
            "$($ruim.error.message)" | Should -Match 'painel desconhecido'
        }

        It 'panels.open no modo de teste responde simulado, sem abrir janela' {
            $r = Invoke-TmxBridgeTest -Action 'panels.open' -Payload @{ id = 'PAN-CONTROL' }
            $r.ok | Should -BeTrue
            $r.result.simulado | Should -BeTrue
        }

        It 'dns.list traz os provedores e os servidores em uso' {
            $r = Invoke-TmxBridgeTest -Action 'dns.list'
            $r.ok | Should -BeTrue
            @($r.result.provedores).Count | Should -Be 8
        }

        It 'dns.apply recusa provedores reais no modo de teste' {
            $r = Invoke-TmxBridgeTest -Action 'dns.apply' -Payload @{ provedor = 'Cloudflare' }
            $r.ok | Should -BeFalse
            "$($r.error.message)" | Should -Match 'modo de teste'
        }

        It 'features.apply sem sessao recusa antes de criar job' {
            $sync.session = $null
            $r = Invoke-TmxBridgeTest -Action 'features.apply' -Payload @{ id = 'REC-TST'; ligado = $true }
            $r.ok | Should -BeFalse
            "$($r.error.message)" | Should -Match 'sessao'
            $sync.activeJob | Should -BeNullOrEmpty
        }

        It 'features.apply recusa qualquer recurso que nao seja REC-TST no modo de teste' {
            Start-TmxTestRunSession | Out-Null
            $r = Invoke-TmxBridgeTest -Action 'features.apply' -Payload @{ id = 'REC-001'; ligado = $true }
            $r.ok | Should -BeFalse
            "$($r.error.message)" | Should -Match 'REC-TST'
        }

        It 'fixes.run FIX-TST termina com job.done ok e uma lista de passos' {
            Start-TmxTestRunSession | Out-Null
            $r = Invoke-TmxBridgeJobTest -Action 'fixes.run' -Payload @{ id = 'FIX-TST' }
            $r.done | Should -Not -BeNullOrEmpty
            $r.done.ok | Should -BeTrue
            $r.done.result.id | Should -Be 'FIX-TST'
            $r.done.result.ok | Should -BeTrue
            @($r.done.result.passos).Count | Should -BeGreaterOrEqual 1
        }

        It 'fixes.run recusa qualquer correcao que nao seja FIX-TST no modo de teste' {
            Start-TmxTestRunSession | Out-Null
            $r = Invoke-TmxBridgeTest -Action 'fixes.run' -Payload @{ id = 'FIX-NET' }
            $r.ok | Should -BeFalse
            "$($r.error.message)" | Should -Match 'FIX-TST'
        }

        It 'REC-TST liga, desliga e volta ao estado original pelo Undo' {
            $sessao = Start-TmxTestRunSession
            $sessao.pronto | Should -BeTrue

            # ligar
            $r = Invoke-TmxBridgeJobTest -Action 'features.apply' -Payload @{ id = 'REC-TST'; ligado = $true }
            $r.done | Should -Not -BeNullOrEmpty
            $r.done.ok | Should -BeTrue
            (Get-TmxTestRegValue -Path $script:TmxChaveTeste -Name 'Recurso') | Should -Be 1

            $registros = @(Import-TmxState -StatePath $sessao.statePath | Where-Object { "$($_.tweakId)" -eq 'REC-TST' })
            $registros.Count | Should -BeGreaterOrEqual 1

            $naLista = @($r.done.result.catalogo.recursos | Where-Object { $_.id -eq 'REC-TST' })[0]
            $naLista.estado  | Should -Be 'Enabled'
            $naLista.temUndo | Should -BeTrue

            # desligar usa o toggleDesligar
            $r2 = Invoke-TmxBridgeJobTest -Action 'features.apply' -Payload @{ id = 'REC-TST'; ligado = $false }
            $r2.done.ok | Should -BeTrue
            (Get-TmxTestRegValue -Path $script:TmxChaveTeste -Name 'Recurso') | Should -Be 0

            # undo: a chave criada por nos some
            $undo = Invoke-TmxUndoInJob -TweakId 'REC-TST'
            $undo.ok | Should -BeTrue
            $undo.result.revertidos | Should -BeGreaterOrEqual 2
            (Get-TmxTestRegValue -Path $script:TmxChaveTeste -Name 'Recurso') | Should -BeNullOrEmpty
        }
    }
}
