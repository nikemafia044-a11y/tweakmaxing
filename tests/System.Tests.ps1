# tests/System.Tests.ps1
# Back-ends de sistema da v2 (src/functions/system/*) e as acoes da ponte de
# Actions.System.ps1. Nao exige elevacao e nunca toca o sistema real: tudo
# roda em modo de teste (raizes falsas na home de teste) ou com os wrappers
# de _Wrappers.ps1 mockados. Nenhum teste aqui passa por job assincrono com
# mock (mocks nao chegam as runspaces do pool).

. (Join-Path $PSScriptRoot '_Helpers.ps1')

Describe 'Back-ends de sistema' -Tag 'System' {

    BeforeAll {
        . (Join-Path $PSScriptRoot '_Helpers.ps1')
        Import-TmxTestModule
        $script:TmxAppsDoc = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\src\config\applications.json') -Raw -Encoding UTF8 | ConvertFrom-Json

        function New-TmxSystemTestSync {
            param([bool] $TestMode = $true)
            $s = [Hashtable]::Synchronized(@{})
            $s.version       = '2.0.0'
            $s.testMode      = $TestMode
            $s.configs       = @{}
            $s.bridgeActions = @{}
            $s.activeJob     = $null
            $s.session       = $null
            $s.uiEvents      = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList))
            $s.configs.applications = $script:TmxAppsDoc
            $global:sync = $s
            $s
        }

        function New-TmxFakeFile {
            param([string] $Path, [int] $Bytes = 100)
            $pasta = Split-Path $Path -Parent
            if (-not (Test-Path -LiteralPath $pasta)) { New-Item -ItemType Directory -Path $pasta -Force | Out-Null }
            [System.IO.File]::WriteAllBytes($Path, (New-Object byte[] $Bytes))
        }

        function Invoke-TmxSystemBridge {
            param([string] $Action, $Payload = @{})
            $json = @{ id = '1'; action = $Action; payload = $Payload } | ConvertTo-Json -Depth 6 -Compress
            Invoke-TmxBridgeRequest -Json $json | ConvertFrom-Json
        }
    }

    BeforeEach {
        New-TmxTestHome | Out-Null
        New-TmxSystemTestSync | Out-Null
    }

    AfterEach {
        Remove-TmxTestHome
    }

    AfterAll {
        if (Get-Command Close-TmxRunspacePool -ErrorAction SilentlyContinue) { Close-TmxRunspacePool }
        Remove-Variable -Name sync -Scope Global -ErrorAction SilentlyContinue
    }

    Context 'Configuracoes (settings.json)' {

        It 'sem arquivo devolve os padroes e o nome efetivo cai no USERNAME' {
            $s = Get-TmxSettings
            $s.language | Should -Be ''
            $s.sidebarCollapsed | Should -BeFalse
            $s.lastCleanupFreed | Should -Be 0
            $s.displayNameEfetivo | Should -Be "$env:USERNAME"
        }

        It 'grava e rele as chaves permitidas' {
            Set-TmxSettings -Payload @{ language = 'en'; displayName = 'Ana'; sidebarCollapsed = 'true' } | Out-Null
            $s = Get-TmxSettings
            $s.language | Should -Be 'en'
            $s.displayNameEfetivo | Should -Be 'Ana'
            $s.sidebarCollapsed | Should -BeTrue
            Test-Path -LiteralPath ((Get-TmxSettingsPath) + '.tmp') | Should -BeFalse
        }

        It 'e tudo ou nada: uma chave desconhecida impede a gravacao das outras' {
            { Set-TmxSettings -Payload @{ language = 'en'; hacker = 1 } } | Should -Throw '*nao permitida*'
            Test-Path -LiteralPath (Get-TmxSettingsPath) | Should -BeFalse
        }

        It 'recusa valores invalidos' {
            { Set-TmxSettings -Payload @{ language = 'fr' } } | Should -Throw '*idioma invalido*'
            { Set-TmxSettings -Payload @{ appliedMode = 'turbo' } } | Should -Throw '*modo invalido*'
            { Set-TmxSettings -Payload @{ displayName = ('x' * 41) } } | Should -Throw '*muito longo*'
            { Set-TmxSettings -Payload @{ lastCleanup = 'ontem' } } | Should -Throw '*data ISO*'
            { Set-TmxSettings -Payload @{ lastCleanupFreed = -1 } } | Should -Throw '*negativo*'
            { Set-TmxSettings -Payload @{} } | Should -Throw '*nenhuma configuracao*'
        }

        It 'arquivo corrompido nao derruba a leitura' {
            Set-Content -LiteralPath (Get-TmxSettingsPath) -Value '{ quebrado' -Encoding UTF8
            (Get-TmxSettings).language | Should -Be ''
        }

        It 'nome do Windows: FullName quando existe, senao USERNAME' {
            Mock -ModuleName TweakMaxing -CommandName Get-TmxWindowsUserAccountSafe -MockWith { [pscustomobject]@{ FullName = 'Ana Silva' } }
            Get-TmxWindowsDisplayName | Should -Be 'Ana Silva'
            Mock -ModuleName TweakMaxing -CommandName Get-TmxWindowsUserAccountSafe -MockWith { $null }
            Get-TmxWindowsDisplayName | Should -Be "$env:USERNAME"
        }
    }

    Context 'Hardware (system.info)' {

        It 'recomendacoes: XMP, HAGS e plano de energia, no maximo 3' {
            $ram  = @{ velocidadeNominal = 6000; velocidadeConfigurada = 4800 }
            $hags = @{ suportado = $true; ligado = $false }
            $r = @(Get-TmxHardwareRecomendacoes -Ram $ram -Hags $hags -Chassi 'notebook')
            $r.Count | Should -Be 3
            $r[0].chave | Should -Be 'painel.rec.xmp'
            $r[1].chave | Should -Be 'painel.rec.hags'
            $r[2].chave | Should -Be 'painel.rec.powerplan.notebook'
        }

        It 'sem XMP pendente e com HAGS ligado so sobra o plano de energia' {
            $ram  = @{ velocidadeNominal = 3200; velocidadeConfigurada = 3200 }
            $hags = @{ suportado = $true; ligado = $true }
            $r = @(Get-TmxHardwareRecomendacoes -Ram $ram -Hags $hags -Chassi 'desktop')
            $r.Count | Should -Be 1
            $r[0].chave | Should -Be 'painel.rec.powerplan.desktop'
        }

        It 'VRAM vem do qwMemorySize, como QWORD ou como binario' {
            Mock -ModuleName TweakMaxing -CommandName Get-TmxRegistryChildNamesSafe -MockWith { @('Properties', '0000', '0001') }
            Mock -ModuleName TweakMaxing -CommandName Get-TmxItemPropertySafe -MockWith {
                if ($Path -like '*0001' -and $Name -eq 'DriverDesc') { return 'GPU Teste' }
                if ($Path -like '*0001') { return , [BitConverter]::GetBytes([uint64]8GB) }
                if ($Name -eq 'DriverDesc') { return 'Outra' }
                $null
            }
            Get-TmxGpuVramBytes -Modelo 'GPU Teste' | Should -Be ([int64]8GB)

            Mock -ModuleName TweakMaxing -CommandName Get-TmxItemPropertySafe -MockWith {
                if ($Name -eq 'DriverDesc') { return 'GPU Teste' }
                [int64]12GB
            }
            Get-TmxGpuVramBytes -Modelo 'GPU Teste' | Should -Be ([int64]12GB)
        }

        It 'RAM: soma os pentes e traduz o tipo SMBIOS' {
            Mock -ModuleName TweakMaxing -CommandName Get-TmxCimSafe -ParameterFilter { $ClassName -eq 'Win32_PhysicalMemory' } -MockWith {
                [pscustomobject]@{ Capacity = 16GB; SMBIOSMemoryType = 34; Speed = 6000; ConfiguredClockSpeed = 4800 }
                [pscustomobject]@{ Capacity = 16GB; SMBIOSMemoryType = 34; Speed = 6000; ConfiguredClockSpeed = 4800 }
            }
            $r = Get-TmxRamInfo
            $r.totalGB | Should -Be 32
            $r.tipo | Should -Be 'DDR5'
            $r.velocidadeConfigurada | Should -Be 4800
        }

        It 'nunca lanca: CIM quebrado vira campos nulos' {
            Mock -ModuleName TweakMaxing -CommandName Get-TmxCimSafe -MockWith { throw 'WMI fora do ar' }
            $info = Get-TmxSystemInfo
            $info.cpu.modelo | Should -BeNullOrEmpty
            $info.ram.totalGB | Should -BeNullOrEmpty
            $info.Keys | Should -Contain 'recomendacoes'
        }
    }

    Context 'Limpeza (modo de teste)' {

        BeforeEach {
            $roots = Get-TmxCleanupRoots
            New-TmxFakeFile -Path (Join-Path $roots['temp-usuario'] 'a.tmp') -Bytes 1000
            New-TmxFakeFile -Path (Join-Path $roots['temp-usuario'] 'sub\b.tmp') -Bytes 500
            New-TmxFakeFile -Path (Join-Path $roots['miniaturas'] 'thumbcache_256.db') -Bytes 300
            New-TmxFakeFile -Path (Join-Path $roots['miniaturas'] 'iconcache_32.db') -Bytes 700
            New-TmxFakeFile -Path (Join-Path (Get-TmxCleanupLixeiraFakeRoot) 'x.txt') -Bytes 50
        }

        It 'as raizes ficam dentro da home de teste' {
            foreach ($p in (Get-TmxCleanupRoots).Values) { $p | Should -BeLike "$env:TWEAKMAXING_HOME*" }
        }

        It 'scan mede sem apagar; miniaturas so conta thumbcache_*.db' {
            $scan = Get-TmxCleanupScan
            @($scan.itens).Count | Should -Be 6
            $tu = @($scan.itens | Where-Object { $_.id -eq 'temp-usuario' })[0]
            $tu.bytes | Should -Be 1500
            $tu.arquivos | Should -Be 2
            (@($scan.itens | Where-Object { $_.id -eq 'miniaturas' })[0]).bytes | Should -Be 300
            (@($scan.itens | Where-Object { $_.id -eq 'lixeira' })[0]).bytes | Should -Be 50
            Test-Path -LiteralPath (Join-Path (Get-TmxCleanupRoots)['temp-usuario'] 'a.tmp') | Should -BeTrue
        }

        It 'run apaga so os itens pedidos e grava lastCleanup' {
            $r = Invoke-TmxCleanupRun -Ids @('temp-usuario', 'miniaturas', 'lixeira')
            $r.liberado | Should -Be 1850
            $r.porItem['miniaturas'] | Should -Be 300
            $roots = Get-TmxCleanupRoots
            Test-Path -LiteralPath (Join-Path $roots['miniaturas'] 'iconcache_32.db') | Should -BeTrue
            (Get-TmxSettings).lastCleanupFreed | Should -Be 1850
            (Get-TmxSettings).lastCleanup | Should -Not -BeNullOrEmpty
        }

        It 'wu-cache em modo de teste nao toca o servico real' {
            Mock -ModuleName TweakMaxing -CommandName Stop-TmxServiceSafe -MockWith { $true }
            Invoke-TmxCleanupRun -Ids @('wu-cache') | Out-Null
            Should -Invoke -ModuleName TweakMaxing -CommandName Stop-TmxServiceSafe -Times 0 -Exactly
        }

        It 'recusa lista vazia e ids desconhecidos' {
            { Invoke-TmxCleanupRun -Ids @('') } | Should -Throw
            { Invoke-TmxCleanupRun -Ids @('temp-usuario', 'C:\Windows') } | Should -Throw '*desconhecido*'
        }
    }

    Context 'Limpeza (modo normal, wrappers mockados)' {

        It 'wuauserv volta a subir mesmo quando um item falha no meio' {
            $global:sync.testMode = $false
            Mock -ModuleName TweakMaxing -CommandName Get-TmxCleanupRoots -MockWith { [ordered]@{ 'wu-cache' = 'X:\nao-existe'; 'temp-usuario' = 'X:\nao-existe' } }
            Mock -ModuleName TweakMaxing -CommandName Stop-TmxServiceSafe -MockWith { $true }
            Mock -ModuleName TweakMaxing -CommandName Start-TmxServiceSafe -MockWith { $true }
            Mock -ModuleName TweakMaxing -CommandName Remove-TmxCleanupFolderContents -MockWith { throw 'disco sumiu' }
            { Invoke-TmxCleanupRun -Ids @('wu-cache') } | Should -Throw '*disco sumiu*'
            Should -Invoke -ModuleName TweakMaxing -CommandName Start-TmxServiceSafe -Times 1 -Exactly
        }
    }

    Context 'Pontos de restauracao (lista falsa)' {

        It 'cria, lista do mais novo para o mais antigo, exclui e restaura com confirmacao' {
            (New-TmxRestoreCreate -Nome 'primeiro').sequencia | Should -Be 1
            $r2 = New-TmxRestoreCreate
            $r2.sequencia | Should -Be 2
            $r2.nome | Should -BeLike 'TweakMaxing *'
            $r2.simulado | Should -BeTrue

            $l = @(Get-TmxRestoreList)
            $l.Count | Should -Be 2
            [int]$l[0].sequencia | Should -Be 2

            { Invoke-TmxRestoreRestore -Sequencia 1 -Confirmado $false } | Should -Throw '*confirmacao pendente*'
            (Invoke-TmxRestoreRestore -Sequencia 1 -Confirmado $true).simulado | Should -BeTrue
            { Invoke-TmxRestoreRestore -Sequencia 9 -Confirmado $true } | Should -Throw '*nao encontrado*'

            Remove-TmxRestorePointById -Sequencia 1 | Out-Null
            @(Get-TmxRestoreList).Count | Should -Be 1
            { Remove-TmxRestorePointById -Sequencia 1 } | Should -Throw '*nao encontrado*'
        }

        It 'modo de teste nunca chama o P/Invoke nem o WMI' {
            Mock -ModuleName TweakMaxing -CommandName Remove-TmxRestorePointNative -MockWith { @{ ok = $true } }
            Mock -ModuleName TweakMaxing -CommandName Invoke-TmxSystemRestoreWmi -MockWith { @{ ok = $true } }
            New-TmxRestoreCreate -Nome 'a' | Out-Null
            Invoke-TmxRestoreRestore -Sequencia 1 -Confirmado $true | Out-Null
            Remove-TmxRestorePointById -Sequencia 1 | Out-Null
            Should -Invoke -ModuleName TweakMaxing -CommandName Remove-TmxRestorePointNative -Times 0 -Exactly
            Should -Invoke -ModuleName TweakMaxing -CommandName Invoke-TmxSystemRestoreWmi -Times 0 -Exactly
        }
    }

    Context 'Verificacao de atualizacao do app' {

        It 'compara versoes com v e sufixo' {
            Compare-TmxVersion -A 'v2.1.0' -B '2.0.9' | Should -Be 1
            Compare-TmxVersion -A '2.0.0' -B '2.0.0-dev' | Should -Be 0
            Compare-TmxVersion -A '1.9.9' -B 'V2.0.0' | Should -Be -1
        }

        It 'modo de teste nao usa a rede' {
            Mock -ModuleName TweakMaxing -CommandName Invoke-TmxHttpGetSafe -MockWith { throw 'nao devia chamar' }
            $r = Get-TmxAppUpdateStatus
            $r.novaDisponivel | Should -BeFalse
            $r.simulado | Should -BeTrue
        }

        It 'modo normal: detecta release mais nova e trata erro de rede e JSON invalido' {
            $global:sync.testMode = $false
            Mock -ModuleName TweakMaxing -CommandName Invoke-TmxHttpGetSafe -MockWith {
                @{ ok = $true; content = '{"tag_name":"v2.1.0","html_url":"https://github.com/x/y/releases/tag/v2.1.0"}' }
            }
            $r = Get-TmxAppUpdateStatus
            $r.ultima | Should -Be '2.1.0'
            $r.novaDisponivel | Should -BeTrue
            $r.url | Should -BeLike 'https://github.com/*'

            Mock -ModuleName TweakMaxing -CommandName Invoke-TmxHttpGetSafe -MockWith { @{ ok = $false; erro = 'timeout' } }
            $r = Get-TmxAppUpdateStatus
            $r.novaDisponivel | Should -BeFalse
            $r.erro | Should -Be 'timeout'

            Mock -ModuleName TweakMaxing -CommandName Invoke-TmxHttpGetSafe -MockWith { @{ ok = $true; content = '<html>' } }
            (Get-TmxAppUpdateStatus).erro | Should -BeLike '*invalida*'
        }
    }

    Context 'Manutencao de dados' {

        It 'backups antigos: so runs com mais de 30 dias, nunca o mais recente' {
            $raiz = Get-TmxRunsRoot
            foreach ($n in 'velho1', 'velho2', 'novo') { New-Item -ItemType Directory -Path (Join-Path $raiz $n) -Force | Out-Null }
            (Get-Item (Join-Path $raiz 'velho1')).CreationTimeUtc = (Get-Date).ToUniversalTime().AddDays(-60)
            (Get-Item (Join-Path $raiz 'velho2')).CreationTimeUtc = (Get-Date).ToUniversalTime().AddDays(-40)

            $alvos = @(Get-TmxOldBackupRuns)
            $alvos.Count | Should -Be 2
            ($alvos | Split-Path -Leaf) | Should -Not -Contain 'novo'

            { Remove-TmxOldBackupRuns -Confirmado $false } | Should -Throw '*confirmacao pendente*'
            @((Remove-TmxOldBackupRuns -Confirmado $true).removidos).Count | Should -Be 2
            Test-Path -LiteralPath (Join-Path $raiz 'novo') | Should -BeTrue
        }

        It 'backup unico, mesmo antigo, e preservado' {
            $p = Join-Path (Get-TmxRunsRoot) 'unico'
            New-Item -ItemType Directory -Path $p -Force | Out-Null
            (Get-Item $p).CreationTimeUtc = (Get-Date).ToUniversalTime().AddDays(-90)
            @(Get-TmxOldBackupRuns).Count | Should -Be 0
        }

        It 'limpar cache apaga icones e UIs de outras versoes, mantendo a atual' {
            New-TmxFakeFile -Path (Join-Path (Get-TmxAppIconCacheDir) 'firefox.png')
            $ui = Join-Path $env:TWEAKMAXING_HOME 'ui'
            New-TmxFakeFile -Path (Join-Path $ui '0.2.0\index.html')
            New-TmxFakeFile -Path (Join-Path $ui '2.0.0\index.html')

            $r = Invoke-TmxClearAppCache
            @($r.removidos).Count | Should -Be 2
            Test-Path -LiteralPath (Join-Path $ui '2.0.0') | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $ui '0.2.0') | Should -BeFalse
        }

        It 'abrir logs em modo de teste nao abre o Explorer' {
            Mock -ModuleName TweakMaxing -CommandName Open-TmxFolderSafe -MockWith { $true }
            $r = Open-TmxLogsFolder
            $r.simulado | Should -BeTrue
            Test-Path -LiteralPath $r.caminho | Should -BeTrue
            Should -Invoke -ModuleName TweakMaxing -CommandName Open-TmxFolderSafe -Times 0 -Exactly
        }
    }

    Context 'Status de otimizacao' {

        It 'disponiveis: modo != extras; sem modo, tier != FOLCLORE' {
            $cat = @(
                [pscustomobject]@{ id = 'A'; modo = 'leve';   tier = 'FOLCLORE' }
                [pscustomobject]@{ id = 'B'; modo = 'extras'; tier = 'MEDIDO' }
                [pscustomobject]@{ id = 'C'; tier = 'TECNICO' }
                [pscustomobject]@{ id = 'D'; tier = 'FOLCLORE' }
            )
            $ids = @(Get-TmxOptimizationAvailableTweaks -Catalog $cat | ForEach-Object { $_.id })
            $ids | Should -Be @('A', 'C')
        }
    }

    Context 'Acoes da ponte' {

        BeforeEach {
            Register-TmxSystemActions
        }

        It 'registra todas as acoes do spec' {
            foreach ($a in 'settings.get', 'settings.set', 'settings.windowsName', 'system.info', 'system.optimizationStatus',
                'cleanup.scan', 'cleanup.run', 'restore.list', 'restore.create', 'restore.delete', 'restore.restore',
                'app.checkUpdate', 'app.clearCache', 'app.openLogs', 'app.oldBackups', 'app.deleteOldBackups',
                'apps.export', 'apps.import', 'shell.saveFile', 'shell.openFile') {
                $sync.bridgeActions.ContainsKey($a) | Should -BeTrue -Because $a
            }
        }

        It 'settings.set recusa chave fora da lista' {
            $r = Invoke-TmxSystemBridge -Action 'settings.set' -Payload @{ nada = 1 }
            $r.ok | Should -BeFalse
            $r.error.message | Should -BeLike '*nao permitida*'
        }

        It 'restore.restore e restore.delete validam o payload antes de criar job' {
            (Invoke-TmxSystemBridge -Action 'restore.restore' -Payload @{ sequencia = 3 }).error.message | Should -BeLike '*confirmacao pendente*'
            (Invoke-TmxSystemBridge -Action 'restore.delete' -Payload @{ sequencia = 0 }).error.message | Should -BeLike '*obrigatoria*'
            (Invoke-TmxSystemBridge -Action 'app.deleteOldBackups' -Payload @{}).error.message | Should -BeLike '*confirmacao pendente*'
            $sync.activeJob | Should -BeNullOrEmpty
        }

        It 'apps.export filtra ids fora do catalogo e apps.import separa desconhecidos' {
            $real = 'chrome'
            $exp = Invoke-TmxSystemBridge -Action 'apps.export' -Payload @{ ids = @($real, 'app-que-nao-existe', $real) }
            $exp.ok | Should -BeTrue
            @($exp.result.apps) | Should -Be @($real)

            $conteudo = @{ apps = @($real, 'app-que-nao-existe') } | ConvertTo-Json -Compress
            $imp = Invoke-TmxSystemBridge -Action 'apps.import' -Payload @{ conteudo = $conteudo }
            @($imp.result.ids) | Should -Be @($real)
            @($imp.result.desconhecidos) | Should -Be @('app-que-nao-existe')

            (Invoke-TmxSystemBridge -Action 'apps.import' -Payload @{ conteudo = '{ ruim' }).error.message | Should -BeLike '*malformado*'
            (Invoke-TmxSystemBridge -Action 'apps.import' -Payload @{ conteudo = '{"x":1}' }).error.message | Should -BeLike '*esperado*'
        }

        It 'shell.saveFile e shell.openFile nao abrem dialogo em modo de teste' {
            $destino = Join-Path $env:TWEAKMAXING_HOME 'export.json'
            $s = Invoke-TmxSystemBridge -Action 'shell.saveFile' -Payload @{ conteudo = '{"apps":[]}'; simular = $destino }
            $s.result.cancelado | Should -BeFalse
            (Get-Content -LiteralPath $destino -Raw).Trim() | Should -Be '{"apps":[]}'

            (Invoke-TmxSystemBridge -Action 'shell.saveFile' -Payload @{ conteudo = 'x' }).result.cancelado | Should -BeTrue
            $o = Invoke-TmxSystemBridge -Action 'shell.openFile' -Payload @{ simularCaminho = 'C:\a.json'; simularConteudo = 'abc' }
            $o.result.conteudo | Should -Be 'abc'
            (Invoke-TmxSystemBridge -Action 'shell.openFile' -Payload @{}).result.cancelado | Should -BeTrue
        }
    }
}
