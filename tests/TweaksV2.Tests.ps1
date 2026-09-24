# tests/TweaksV2.Tests.ps1
# Testes dos 9 ajustes novos da v2 (docs/specs/2026-09-24-v2-design.md secao 7):
# INT-024, INT-025, PRI-009, JOG-048, JOG-049, SIS-014, APM-006, APM-007, SEC-001.
#
# Regra de sempre: nada aqui toca o sistema de verdade.
#   - Os 3 ajustes declarativos de registro (INT-024/INT-025/PRI-009) sao
#     testados com o 'path' da acao REDIRECIONADO para
#     HKCU:\Software\TweakMaxing_Tests\V2Reg\<id> (nunca para o Control
#     Panel\Desktop ou o HKLM reais do catalogo).
#   - JOG-048 (funcao nomeada) aceita Parametros.path e os testes sempre
#     passam a raiz de teste.
#   - APM-006/APM-007 mockam Get-TmxConfigDocument/Get-TmxAppx/Remove-TmxAppx/
#     Remove-TmxProvisionedAppx/Install-TmxStoreApp - nenhum appx de verdade e tocado.
#   - SIS-014 mocka Get-TmxV2PwshCommand/Invoke-TmxWinget e usa um settings.json
#     de mentira num arquivo temporario (nunca o do Windows Terminal real).
#   - SEC-001 mocka Get-TmxV2DefenderComputerStatus/Get-TmxDefenderExclusions/
#     Add-TmxDefenderExclusionPath/Remove-TmxDefenderExclusionPath/Start-TmxV2DefenderSettingsUri.

. "$PSScriptRoot\_Helpers.ps1"

BeforeAll {
    . "$PSScriptRoot\_Helpers.ps1"
    Import-TmxTestModule
    New-TmxTestHome | Out-Null
    # Uma execucao anterior abortada (timeout) pula o AfterAll e deixa as
    # chaves de teste para tras - o primeiro Test-TmxAction veria 'aplicado'.
    Remove-TmxTestKey -SubKey 'V2Reg'
    Remove-TmxTestKey -SubKey 'JOG048'

    $script:RepoRaiz  = Split-Path $PSScriptRoot -Parent
    $script:CatalogoV2Path = Join-Path $script:RepoRaiz 'src\config\tweaks.v2.json'
    $script:CatalogoV2 = (Get-Content -LiteralPath $script:CatalogoV2Path -Raw -Encoding UTF8 | ConvertFrom-Json).tweaks

    function script:Get-TmxV2Tweak {
        param([Parameter(Mandatory)] [string] $Id)
        $t = $script:CatalogoV2 | Where-Object { "$($_.id)" -eq $Id }
        if (-not $t) { throw "tweak '$Id' nao encontrado em tweaks.v2.json" }
        $t
    }

    function script:Get-TmxRegistrosDoDisco {
        param([Parameter(Mandatory)] [string] $Caminho)
        if (-not (Test-Path -LiteralPath $Caminho)) { return @() }
        $dados = Get-Content -LiteralPath $Caminho -Raw -Encoding UTF8 | ConvertFrom-Json
        @($dados.registros | Where-Object { $null -ne $_ })
    }
}

AfterAll {
    Remove-TmxTestKey -SubKey 'V2Reg'
    Remove-TmxTestKey -SubKey 'JOG048'
    Remove-TmxTestHome
    Stop-TmxLogger
    Remove-Module TweakMaxing -Force -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------------------
# Metadados do catalogo (os 9 ids, todos os campos novos da v2)
# ---------------------------------------------------------------------------

Describe 'Metadados dos 9 ajustes novos da v2' -Tag 'TweaksV2' {

    $ids = 'INT-024', 'INT-025', 'PRI-009', 'JOG-048', 'JOG-049', 'SIS-014', 'APM-006', 'APM-007', 'SEC-001'

    It '<_> existe e tem os campos v2 (modo, categoriasV2, oQueFaz, beneficio, atencao, i18n.en)' -ForEach $ids {
        $id = $_
        $t = Get-TmxV2Tweak -Id $id
        $t.modo          | Should -Not -BeNullOrEmpty
        @($t.categoriasV2).Count | Should -BeGreaterThan 0
        $t.oQueFaz       | Should -Not -BeNullOrEmpty
        $t.beneficio     | Should -Not -BeNullOrEmpty
        "$($t.atencao)"  | Should -Not -BeNullOrEmpty
        $t.i18n.en.nome      | Should -Not -BeNullOrEmpty
        $t.i18n.en.oQueFaz   | Should -Not -BeNullOrEmpty
        $t.i18n.en.beneficio | Should -Not -BeNullOrEmpty
        "$($t.i18n.en.atencao)" | Should -Not -BeNullOrEmpty
    }

    It 'os modos batem com o pedido: leve para os 3 declarativos, moderado p/ JOG-048, extras p/ JOG-049 e SIS-014, avancado p/ APM-006/007, ultimate p/ SEC-001' {
        (Get-TmxV2Tweak 'INT-024').modo | Should -Be 'leve'
        (Get-TmxV2Tweak 'INT-025').modo | Should -Be 'leve'
        (Get-TmxV2Tweak 'PRI-009').modo | Should -Be 'leve'
        (Get-TmxV2Tweak 'JOG-048').modo | Should -Be 'moderado'
        (Get-TmxV2Tweak 'JOG-049').modo | Should -Be 'extras'
        (Get-TmxV2Tweak 'SIS-014').modo | Should -Be 'extras'
        (Get-TmxV2Tweak 'APM-006').modo | Should -Be 'avancado'
        (Get-TmxV2Tweak 'APM-007').modo | Should -Be 'avancado'
        (Get-TmxV2Tweak 'SEC-001').modo | Should -Be 'ultimate'
    }

    It 'JOG-049 fica em extras por ser controle info (regra do S6), mesmo a tabela do pedido dizendo moderado' {
        (Get-TmxV2Tweak 'JOG-049').controle | Should -Be 'info'
        (Get-TmxV2Tweak 'JOG-049').modo     | Should -Be 'extras'
    }

    It 'SEC-001 e risco alto com requerConsentimentoExtra=true' {
        $t = Get-TmxV2Tweak 'SEC-001'
        $t.risco | Should -Be 'alto'
        $t.requerConsentimentoExtra | Should -BeTrue
        "$($t.consentimento.frase)" | Should -Not -BeNullOrEmpty
    }

    It 'passa inteiro em Test-TmxCatalog junto com o resto do catalogo' {
        $catalogoCompleto = Get-TmxCatalog -Path (Join-Path $script:RepoRaiz 'src\config')
        $r = Test-TmxCatalog -Catalog $catalogoCompleto
        $r.ok | Should -BeTrue -Because ($r.erros -join "`n")
    }
}

# ---------------------------------------------------------------------------
# INT-024 / INT-025 / PRI-009: acoes de registro declarativas
# ---------------------------------------------------------------------------

Describe 'Ajustes declarativos de registro (INT-024, INT-025, PRI-009)' -Tag 'TweaksV2' {

    BeforeEach {
        Remove-TmxTestKey -SubKey 'V2Reg'
        $script:run = New-TmxRun
    }

    It 'INT-024: MenuShowDelay = "0" (String) em HKCU\Control Panel\Desktop' {
        $t = Get-TmxV2Tweak 'INT-024'
        @($t.acoes).Count | Should -Be 1
        $t.acoes[0].tipo      | Should -Be 'registry'
        $t.acoes[0].path      | Should -Be 'HKCU:\Control Panel\Desktop'
        $t.acoes[0].name      | Should -Be 'MenuShowDelay'
        $t.acoes[0].value     | Should -Be '0'
        $t.acoes[0].valueType | Should -Be 'String'
    }

    It 'INT-025: duas chaves DWord=0 no ContentDeliveryManager' {
        $t = Get-TmxV2Tweak 'INT-025'
        @($t.acoes).Count | Should -Be 2
        foreach ($a in $t.acoes) {
            $a.tipo      | Should -Be 'registry'
            $a.path      | Should -Be 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
            $a.value     | Should -Be 0
            $a.valueType | Should -Be 'DWord'
        }
        @($t.acoes.name) | Should -Contain 'RotatingLockScreenOverlayEnabled'
        @($t.acoes.name) | Should -Contain 'SubscribedContent-338387Enabled'
    }

    It 'PRI-009: AutoConnectAllowedOEM=0 (DWord) em HKLM WcmSvc' {
        $t = Get-TmxV2Tweak 'PRI-009'
        @($t.acoes).Count | Should -Be 1
        $t.acoes[0].tipo      | Should -Be 'registry'
        $t.acoes[0].path      | Should -Be 'HKLM:\SOFTWARE\Microsoft\WcmSvc\wifinetworkmanager\config'
        $t.acoes[0].name      | Should -Be 'AutoConnectAllowedOEM'
        $t.acoes[0].value     | Should -Be 0
        $t.acoes[0].valueType | Should -Be 'DWord'
    }

    It '<_> : cada acao aplica, verifica e desfaz na raiz de teste (nunca no caminho real do catalogo)' -ForEach @('INT-024', 'INT-025', 'PRI-009') {
        $id = $_
        $t = Get-TmxV2Tweak $id
        $tweakFake = [pscustomobject]@{ id = $t.id }

        $acoesTeste = @($t.acoes | ForEach-Object {
            [pscustomobject]@{
                tipo      = $_.tipo
                path      = "HKCU:\Software\TweakMaxing_Tests\V2Reg\$id"
                name      = $_.name
                value     = $_.value
                valueType = $_.valueType
            }
        })

        foreach ($acao in $acoesTeste) {
            (Test-TmxAction -Action $acao -Tweak $tweakFake -Profile $null).aplicado | Should -BeFalse
        }

        foreach ($acao in $acoesTeste) {
            $r = Invoke-TmxAction -Action $acao -Tweak $tweakFake -Profile $null
            $r.ok | Should -BeTrue
        }

        foreach ($acao in $acoesTeste) {
            (Test-TmxAction -Action $acao -Tweak $tweakFake -Profile $null).aplicado | Should -BeTrue
        }

        Undo-TweakMaxing -Latest 6> $null | Out-Null

        foreach ($acao in $acoesTeste) {
            (Test-TmxAction -Action $acao -Tweak $tweakFake -Profile $null).aplicado | Should -BeFalse
        }
    }
}

# ---------------------------------------------------------------------------
# JOG-048: DirectXUserGlobalSettings (mesclagem de string)
# ---------------------------------------------------------------------------

Describe 'Set-/Test-/Undo-TmxDirectXWindowedGames (JOG-048)' -Tag 'TweaksV2' {

    BeforeEach {
        Remove-TmxTestKey -SubKey 'JOG048'
        $script:run = New-TmxRun
        $script:Tweak = [pscustomobject]@{ id = 'JOG-048' }
        $script:TestRoot = 'HKCU:\Software\TweakMaxing_Tests\JOG048'
        $script:Parametros = [pscustomobject]@{ path = $script:TestRoot }
    }

    It 'a acao do catalogo aponta para a funcao nomeada, sem parametros fixos de caminho' {
        $t = Get-TmxV2Tweak 'JOG-048'
        @($t.acoes).Count | Should -Be 1
        $t.acoes[0].tipo | Should -Be 'funcao'
        $t.acoes[0].nome | Should -Be 'Set-TmxDirectXWindowedGames'
    }

    It 'sem valor previo: cria a string so com SwapEffectUpgradeEnable=1 e o Undo apaga o valor' {
        (Test-TmxDirectXWindowedGames -Tweak $script:Tweak -Profile $null -Parametros $script:Parametros).aplicado | Should -BeFalse

        $r = Set-TmxDirectXWindowedGames -Tweak $script:Tweak -Profile $null -Parametros $script:Parametros
        $r.ok | Should -BeTrue

        (Get-ItemProperty -LiteralPath $script:TestRoot -Name 'DirectXUserGlobalSettings').DirectXUserGlobalSettings | Should -Be 'SwapEffectUpgradeEnable=1;'

        (Test-TmxDirectXWindowedGames -Tweak $script:Tweak -Profile $null -Parametros $script:Parametros).aplicado | Should -BeTrue

        Undo-TweakMaxing -Latest 6> $null | Out-Null
        (Get-ItemProperty -LiteralPath $script:TestRoot -Name 'DirectXUserGlobalSettings' -ErrorAction SilentlyContinue).DirectXUserGlobalSettings | Should -BeNullOrEmpty
    }

    It 'com valor previo: MESCLA sem apagar os outros pares e o Undo restaura a string exata anterior' {
        New-Item -Path $script:TestRoot -Force | Out-Null
        New-ItemProperty -LiteralPath $script:TestRoot -Name 'DirectXUserGlobalSettings' -PropertyType String -Value 'D3D12FSEEnable=0;VRROptimizeEnable=1;' -Force | Out-Null

        $r = Set-TmxDirectXWindowedGames -Tweak $script:Tweak -Profile $null -Parametros $script:Parametros
        $r.ok | Should -BeTrue
        (Get-ItemProperty -LiteralPath $script:TestRoot -Name 'DirectXUserGlobalSettings').DirectXUserGlobalSettings |
            Should -Be 'D3D12FSEEnable=0;VRROptimizeEnable=1;SwapEffectUpgradeEnable=1;'

        Undo-TweakMaxing -Latest 6> $null | Out-Null
        (Get-ItemProperty -LiteralPath $script:TestRoot -Name 'DirectXUserGlobalSettings').DirectXUserGlobalSettings |
            Should -Be 'D3D12FSEEnable=0;VRROptimizeEnable=1;'
    }

    It 'ja aplicado (SwapEffectUpgradeEnable=1 presente) -> naoAplicavel, nao escreve de novo' {
        New-Item -Path $script:TestRoot -Force | Out-Null
        New-ItemProperty -LiteralPath $script:TestRoot -Name 'DirectXUserGlobalSettings' -PropertyType String -Value 'SwapEffectUpgradeEnable=1;' -Force | Out-Null

        $r = Set-TmxDirectXWindowedGames -Tweak $script:Tweak -Profile $null -Parametros $script:Parametros
        $r.ok | Should -BeTrue
        $r.naoAplicavel | Should -BeTrue
        @(Get-TmxRegistrosDoDisco $script:run.StatePath).Count | Should -Be 0
    }
}

# ---------------------------------------------------------------------------
# JOG-049: guia do painel da GPU (so leitura)
# ---------------------------------------------------------------------------

Describe 'Guia do painel da GPU (JOG-049)' -Tag 'TweaksV2' {

    BeforeEach {
        $script:TweakGuia = Get-TmxV2Tweak 'JOG-049'
    }

    It 'controle info e sem acoes: nenhuma mudanca de sistema' {
        $script:TweakGuia.controle | Should -Be 'info'
        @($script:TweakGuia.acoes).Count | Should -Be 0
        "$($script:TweakGuia.instrucoes)" | Should -Not -BeNullOrEmpty
    }

    It 'detecta o fabricante pelo perfil quando Profile.gpu.vendor esta presente' {
        $perfil = [pscustomobject]@{ gpu = [pscustomobject]@{ vendor = 'NVIDIA' } }
        Get-TmxGpuVendorDetectado -Profile $perfil | Should -Be 'NVIDIA'
    }

    It 'sem perfil, detecta pelo Win32_VideoController (wrapper mockado)' {
        Mock Get-TmxV2VideoControllers -ModuleName TweakMaxing {
            [pscustomobject]@{ AdapterCompatibility = 'Advanced Micro Devices, Inc.'; Name = 'AMD Radeon RX 7900 XTX' }
        }
        Get-TmxGpuVendorDetectado -Profile $null | Should -Be 'AMD'
    }

    It 'fabricante Intel via wrapper' {
        Mock Get-TmxV2VideoControllers -ModuleName TweakMaxing {
            [pscustomobject]@{ AdapterCompatibility = 'Intel Corporation'; Name = 'Intel(R) Arc(TM) A770 Graphics' }
        }
        Get-TmxGpuVendorDetectado -Profile $null | Should -Be 'Intel'
    }

    It 'devolve o guia do catalogo (guia.NVIDIA.pt) para o fabricante detectado' {
        $perfil = [pscustomobject]@{ gpu = [pscustomobject]@{ vendor = 'NVIDIA' } }
        $g = Get-TmxGpuPanelGuia -Tweak $script:TweakGuia -Profile $perfil
        $g.vendor | Should -Be 'NVIDIA'
        $g.encontrado | Should -BeTrue
        @($g.guia.pt).Count | Should -BeGreaterThan 0
        @($g.guia.en).Count | Should -BeGreaterThan 0
    }

    It 'fabricante sem guia especifico (Outro) -> encontrado=false' {
        Mock Get-TmxV2VideoControllers -ModuleName TweakMaxing {
            [pscustomobject]@{ AdapterCompatibility = 'VMware, Inc.'; Name = 'VMware SVGA 3D' }
        }
        $g = Get-TmxGpuPanelGuia -Tweak $script:TweakGuia -Profile $null
        $g.vendor     | Should -Be 'Outro'
        $g.encontrado | Should -BeFalse
        $g.guia       | Should -BeNullOrEmpty
    }

    It 'Get-TmxGpuPanelGuiaPassos devolve os passos no idioma pedido e cai para pt quando falta traducao' {
        $guiaNvidia = $script:TweakGuia.guia.NVIDIA
        $pt = Get-TmxGpuPanelGuiaPassos -Guia $guiaNvidia -Idioma 'pt'
        $en = Get-TmxGpuPanelGuiaPassos -Guia $guiaNvidia -Idioma 'en'
        @($pt).Count | Should -BeGreaterThan 0
        @($en).Count | Should -BeGreaterThan 0
        ($pt -join ' ') | Should -Not -Be ($en -join ' ')

        $semEn = [pscustomobject]@{ pt = @('passo unico') }
        @(Get-TmxGpuPanelGuiaPassos -Guia $semEn -Idioma 'en') | Should -Be @('passo unico')
    }
}

# ---------------------------------------------------------------------------
# SIS-014: PowerShell 7 como padrao do Windows Terminal
# ---------------------------------------------------------------------------

Describe 'Set-/Test-/Undo-TmxPowerShell7Default (SIS-014)' -Tag 'TweaksV2' {

    BeforeEach {
        $script:run = New-TmxRun
        $script:Tweak = [pscustomobject]@{ id = 'SIS-014' }
        $script:SettingsPath = Join-Path $env:TWEAKMAXING_HOME ('terminal-settings-{0}.json' -f ([guid]::NewGuid().ToString('N')))

        $script:TextoOriginal = @'
{
  "defaultProfile": "{00000000-0000-0000-0000-000000000001}",
  "profiles": {
    "list": [
      { "guid": "{00000000-0000-0000-0000-000000000001}", "name": "Windows PowerShell", "commandline": "powershell.exe" },
      { "guid": "{00000000-0000-0000-0000-000000000002}", "name": "PowerShell", "source": "Windows.Terminal.PowershellCore" }
    ]
  }
}
'@
        Set-Content -LiteralPath $script:SettingsPath -Value $script:TextoOriginal -Encoding UTF8 -NoNewline

        # pwsh presente por padrao (nao chama winget), a menos que o teste sobrescreva.
        Mock Get-TmxV2PwshCommand -ModuleName TweakMaxing { [pscustomobject]@{ Source = 'C:\Program Files\PowerShell\7\pwsh.exe' } }
        Mock Invoke-TmxWinget -ModuleName TweakMaxing { [pscustomobject]@{ saida = ''; codigo = 0 } }
    }

    AfterEach {
        Remove-Item -LiteralPath $script:SettingsPath -Force -ErrorAction SilentlyContinue
    }

    It 'a acao do catalogo aponta para a funcao nomeada' {
        $t = Get-TmxV2Tweak 'SIS-014'
        @($t.acoes).Count | Should -Be 1
        $t.acoes[0].tipo | Should -Be 'funcao'
        $t.acoes[0].nome | Should -Be 'Set-TmxPowerShell7Default'
    }

    It 'troca defaultProfile para o guid do PowerShell 7, guarda o arquivo original e o Undo restaura BYTE A BYTE' {
        $parametros = [pscustomobject]@{ settingsPath = $script:SettingsPath }

        (Test-TmxPowerShell7Default -Tweak $script:Tweak -Profile $null -Parametros $parametros).aplicado | Should -BeFalse

        $r = Set-TmxPowerShell7Default -Tweak $script:Tweak -Profile $null -Parametros $parametros
        $r.ok | Should -BeTrue

        $depois = Get-Content -LiteralPath $script:SettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $depois.defaultProfile | Should -Be '{00000000-0000-0000-0000-000000000002}'

        (Test-TmxPowerShell7Default -Tweak $script:Tweak -Profile $null -Parametros $parametros).aplicado | Should -BeTrue

        Undo-TweakMaxing -Latest 6> $null | Out-Null
        $textoDepoisDoUndo = Get-Content -LiteralPath $script:SettingsPath -Raw -Encoding UTF8
        $textoDepoisDoUndo | Should -Be $script:TextoOriginal

        Should -Invoke -CommandName Invoke-TmxWinget -ModuleName TweakMaxing -Times 0
    }

    It 'pwsh ausente: instala pelo winget antes de mexer no settings.json' {
        Mock Get-TmxV2PwshCommand -ModuleName TweakMaxing { $null }
        $parametros = [pscustomobject]@{ settingsPath = $script:SettingsPath }

        $r = Set-TmxPowerShell7Default -Tweak $script:Tweak -Profile $null -Parametros $parametros
        $r.ok | Should -BeTrue

        Should -Invoke -CommandName Invoke-TmxWinget -ModuleName TweakMaxing -Times 1 -ParameterFilter {
            $Arguments -contains 'install' -and $Arguments -contains '--id' -and $Arguments -contains 'Microsoft.PowerShell'
        }
    }

    It 'winget falhando nao mexe no settings.json e nao cria registro de estado' {
        Mock Get-TmxV2PwshCommand -ModuleName TweakMaxing { $null }
        Mock Invoke-TmxWinget -ModuleName TweakMaxing { [pscustomobject]@{ saida = 'erro de rede'; codigo = 1 } }
        $parametros = [pscustomobject]@{ settingsPath = $script:SettingsPath }

        $r = Set-TmxPowerShell7Default -Tweak $script:Tweak -Profile $null -Parametros $parametros
        $r.ok | Should -BeFalse
        $r.detalhe | Should -Match 'winget'
        @(Get-TmxRegistrosDoDisco $script:run.StatePath).Count | Should -Be 0
        (Get-Content -LiteralPath $script:SettingsPath -Raw -Encoding UTF8) | Should -Be $script:TextoOriginal
    }

    It 'settings.json ausente -> naoAplicavel' {
        $parametros = [pscustomobject]@{ settingsPath = (Join-Path $env:TWEAKMAXING_HOME 'nao-existe.json') }
        $r = Set-TmxPowerShell7Default -Tweak $script:Tweak -Profile $null -Parametros $parametros
        $r.ok | Should -BeTrue
        $r.naoAplicavel | Should -BeTrue
    }

    It 'perfil do PowerShell 7 ausente no Windows Terminal -> falha clara, sem escrever' {
        $semPS7 = @'
{
  "defaultProfile": "{00000000-0000-0000-0000-000000000001}",
  "profiles": { "list": [
    { "guid": "{00000000-0000-0000-0000-000000000001}", "name": "Windows PowerShell", "commandline": "powershell.exe" }
  ] }
}
'@
        Set-Content -LiteralPath $script:SettingsPath -Value $semPS7 -Encoding UTF8 -NoNewline
        $parametros = [pscustomobject]@{ settingsPath = $script:SettingsPath }

        $r = Set-TmxPowerShell7Default -Tweak $script:Tweak -Profile $null -Parametros $parametros
        $r.ok | Should -BeFalse
        $r.detalhe | Should -Match 'PowerShell 7'
        @(Get-TmxRegistrosDoDisco $script:run.StatePath).Count | Should -Be 0
    }

    It 'ja e o padrao -> naoAplicavel' {
        $jaPadrao = @'
{
  "defaultProfile": "{00000000-0000-0000-0000-000000000002}",
  "profiles": { "list": [
    { "guid": "{00000000-0000-0000-0000-000000000001}", "name": "Windows PowerShell", "commandline": "powershell.exe" },
    { "guid": "{00000000-0000-0000-0000-000000000002}", "name": "PowerShell", "source": "Windows.Terminal.PowershellCore" }
  ] }
}
'@
        Set-Content -LiteralPath $script:SettingsPath -Value $jaPadrao -Encoding UTF8 -NoNewline
        $parametros = [pscustomobject]@{ settingsPath = $script:SettingsPath }

        $r = Set-TmxPowerShell7Default -Tweak $script:Tweak -Profile $null -Parametros $parametros
        $r.ok | Should -BeTrue
        $r.naoAplicavel | Should -BeTrue
    }
}

# ---------------------------------------------------------------------------
# APM-006: bloatware chooser (parametro 'manter')
# ---------------------------------------------------------------------------

Describe 'Set-/Test-/Undo-TmxBloatwareChooser (APM-006)' -Tag 'TweaksV2' {

    BeforeEach {
        $script:run = New-TmxRun
        $script:Tweak = [pscustomobject]@{ id = 'APM-006' }

        $global:TmxT_Presentes  = @{ 'Contoso.A' = $true; 'Contoso.B' = $true; 'Contoso.C' = $true }
        $global:TmxT_Removidos  = New-Object System.Collections.ArrayList
        $global:TmxT_Instalados = New-Object System.Collections.ArrayList

        Mock Get-TmxConfigDocument -ModuleName TweakMaxing {
            param($Name)
            if ("$Name" -ne 'appx') { return $null }
            [pscustomobject]@{
                appx = @(
                    [pscustomobject]@{ id = 'WPFAppxA'; nome = 'App A'; pacote = 'Contoso.A'; storeId = '9AAA' }
                    [pscustomobject]@{ id = 'WPFAppxB'; nome = 'App B'; pacote = 'Contoso.B'; storeId = '9BBB' }
                    [pscustomobject]@{ id = 'WPFAppxC'; nome = 'App C'; pacote = 'Contoso.C'; storeId = $null }
                )
            }
        }
        Mock Get-TmxAppx -ModuleName TweakMaxing {
            param($Pacote, [switch] $TodosUsuarios)
            if ($global:TmxT_Presentes["$Pacote"]) {
                [pscustomobject]@{ PackageFullName = "$Pacote`_1.0.0.0_x64__abc" }
            }
        }
        Mock Remove-TmxAppx -ModuleName TweakMaxing {
            param($PackageFullName, [switch] $TodosUsuarios)
            $null = $global:TmxT_Removidos.Add("$PackageFullName")
            foreach ($k in @($global:TmxT_Presentes.Keys)) {
                if ("$PackageFullName" -like "$k*") { $global:TmxT_Presentes[$k] = $false }
            }
        }
        Mock Remove-TmxProvisionedAppx -ModuleName TweakMaxing { }
        Mock Install-TmxStoreApp -ModuleName TweakMaxing {
            param($StoreId)
            $null = $global:TmxT_Instalados.Add("$StoreId")
            0
        }
    }

    It 'a acao do catalogo documenta o contrato de parametros (manter: [])' {
        $t = Get-TmxV2Tweak 'APM-006'
        @($t.acoes).Count | Should -Be 1
        $t.acoes[0].tipo | Should -Be 'funcao'
        $t.acoes[0].nome | Should -Be 'Set-TmxBloatwareChooser'
        $t.acoes[0].parametros.PSObject.Properties.Name | Should -Contain 'manter'
    }

    It 'mantem o(s) pacote(s) marcados e remove o resto; Undo reinstala pela Store' {
        $parametros = [pscustomobject]@{ manter = @('WPFAppxA') }

        (Test-TmxBloatwareChooser -Tweak $script:Tweak -Profile $null -Parametros $parametros).aplicado | Should -BeFalse

        $r = Set-TmxBloatwareChooser -Tweak $script:Tweak -Profile $null -Parametros $parametros
        $r.ok | Should -BeTrue
        $global:TmxT_Removidos.Count | Should -Be 2
        $global:TmxT_Removidos | Should -Contain 'Contoso.B_1.0.0.0_x64__abc'
        $global:TmxT_Removidos | Should -Contain 'Contoso.C_1.0.0.0_x64__abc'
        $global:TmxT_Removidos | Should -Not -Contain 'Contoso.A_1.0.0.0_x64__abc'

        (Test-TmxBloatwareChooser -Tweak $script:Tweak -Profile $null -Parametros $parametros).aplicado | Should -BeTrue

        Undo-TweakMaxing -Latest 6> $null | Out-Null
        $global:TmxT_Instalados | Should -Contain '9BBB'
    }

    It 'aceita "manter" pelo nome do pacote, nao so pelo id' {
        $parametros = [pscustomobject]@{ manter = @('Contoso.A', 'Contoso.B') }
        $r = Set-TmxBloatwareChooser -Tweak $script:Tweak -Profile $null -Parametros $parametros
        $r.ok | Should -BeTrue
        $global:TmxT_Removidos.Count | Should -Be 1
        $global:TmxT_Removidos | Should -Contain 'Contoso.C_1.0.0.0_x64__abc'
    }

    It 'sem manter nenhum: remove tudo; Undo relata falha so para quem nao tem storeId' {
        $parametros = [pscustomobject]@{ manter = @() }
        Set-TmxBloatwareChooser -Tweak $script:Tweak -Profile $null -Parametros $parametros | Out-Null
        $global:TmxT_Removidos.Count | Should -Be 3

        $sumario = Undo-TweakMaxing -Latest 6> $null
        $item = @($sumario.itens | Where-Object { "$($_.tipo)" -eq 'cmdlet' })[0]
        $item.resultado | Should -Be 'falha'
        $item.detalhe   | Should -Match 'sem storeId'
        $item.detalhe   | Should -Match '9AAA'
        $item.detalhe   | Should -Match '9BBB'
    }

    It 'nada instalado fora da lista de manter -> naoAplicavel' {
        $global:TmxT_Presentes = @{ 'Contoso.A' = $false; 'Contoso.B' = $false; 'Contoso.C' = $false }
        $r = Set-TmxBloatwareChooser -Tweak $script:Tweak -Profile $null -Parametros ([pscustomobject]@{ manter = @() })
        $r.ok | Should -BeTrue
        $r.naoAplicavel | Should -BeTrue
    }
}

# ---------------------------------------------------------------------------
# APM-007: apps de jogos da Microsoft (parametro 'usaGamePass')
# ---------------------------------------------------------------------------

Describe 'Set-/Test-/Undo-TmxGamingApps (APM-007)' -Tag 'TweaksV2' {

    BeforeEach {
        $script:run = New-TmxRun
        $script:Tweak = [pscustomobject]@{ id = 'APM-007' }

        $script:TodosPacotes = @(
            'Microsoft.XboxApp', 'Microsoft.GamingApp', 'Microsoft.XboxGamingOverlay',
            'Microsoft.XboxIdentityProvider', 'Microsoft.XboxSpeechToTextOverlay',
            'Microsoft.Xbox.TCUI', 'Microsoft.MicrosoftSolitaireCollection'
        )
        $global:TmxT_Presentes = @{}
        foreach ($p in $script:TodosPacotes) { $global:TmxT_Presentes[$p] = $true }
        $global:TmxT_Removidos  = New-Object System.Collections.ArrayList
        $global:TmxT_Instalados = New-Object System.Collections.ArrayList

        Mock Get-TmxConfigDocument -ModuleName TweakMaxing {
            param($Name)
            if ("$Name" -ne 'appx') { return $null }
            [pscustomobject]@{
                appx = @(
                    [pscustomobject]@{ id = 'WPFAppxMicrosoft_GamingApp'; pacote = 'Microsoft.GamingApp'; storeId = '9MV0B5HZVK9Z' }
                    [pscustomobject]@{ id = 'WPFAppxMicrosoft_XboxGamingOverlay'; pacote = 'Microsoft.XboxGamingOverlay'; storeId = '9NZKPSTSNW4P' }
                )
            }
        }
        Mock Get-TmxAppx -ModuleName TweakMaxing {
            param($Pacote, [switch] $TodosUsuarios)
            if ($global:TmxT_Presentes["$Pacote"]) {
                [pscustomobject]@{ PackageFullName = "$Pacote`_1.0.0.0_x64__8wekyb3d8bbwe" }
            }
        }
        Mock Remove-TmxAppx -ModuleName TweakMaxing {
            param($PackageFullName, [switch] $TodosUsuarios)
            $null = $global:TmxT_Removidos.Add("$PackageFullName")
            foreach ($k in @($global:TmxT_Presentes.Keys)) {
                if ("$PackageFullName" -like "$k*") { $global:TmxT_Presentes[$k] = $false }
            }
        }
        Mock Remove-TmxProvisionedAppx -ModuleName TweakMaxing { }
        Mock Install-TmxStoreApp -ModuleName TweakMaxing {
            param($StoreId)
            $null = $global:TmxT_Instalados.Add("$StoreId")
            0
        }
    }

    It 'a acao do catalogo documenta o contrato de parametros (usaGamePass: false)' {
        $t = Get-TmxV2Tweak 'APM-007'
        @($t.acoes).Count | Should -Be 1
        $t.acoes[0].nome | Should -Be 'Set-TmxGamingApps'
        $t.acoes[0].parametros.PSObject.Properties.Name | Should -Contain 'usaGamePass'
    }

    It 'usaGamePass=false remove os 7 pacotes de jogos' {
        $r = Set-TmxGamingApps -Tweak $script:Tweak -Profile $null -Parametros ([pscustomobject]@{ usaGamePass = $false })
        $r.ok | Should -BeTrue
        $global:TmxT_Removidos.Count | Should -Be 7
    }

    It 'usaGamePass=true preserva GamingApp/Game Bar/Xbox Identity Provider/Xbox TCUI' {
        $r = Set-TmxGamingApps -Tweak $script:Tweak -Profile $null -Parametros ([pscustomobject]@{ usaGamePass = $true })
        $r.ok | Should -BeTrue
        $global:TmxT_Removidos.Count | Should -Be 3
        $global:TmxT_Removidos | Should -Contain 'Microsoft.XboxApp_1.0.0.0_x64__8wekyb3d8bbwe'
        $global:TmxT_Removidos | Should -Contain 'Microsoft.XboxSpeechToTextOverlay_1.0.0.0_x64__8wekyb3d8bbwe'
        $global:TmxT_Removidos | Should -Contain 'Microsoft.MicrosoftSolitaireCollection_1.0.0.0_x64__8wekyb3d8bbwe'
        $global:TmxT_Removidos | Should -Not -Contain 'Microsoft.GamingApp_1.0.0.0_x64__8wekyb3d8bbwe'
        $global:TmxT_Removidos | Should -Not -Contain 'Microsoft.Xbox.TCUI_1.0.0.0_x64__8wekyb3d8bbwe'

        (Test-TmxGamingApps -Tweak $script:Tweak -Profile $null -Parametros ([pscustomobject]@{ usaGamePass = $true })).aplicado | Should -BeTrue
    }

    It 'Undo reinstala pela Store quando o storeId e conhecido (catalogo ou mapa de fallback)' {
        Set-TmxGamingApps -Tweak $script:Tweak -Profile $null -Parametros ([pscustomobject]@{ usaGamePass = $false }) | Out-Null
        $sumario = Undo-TweakMaxing -Latest 6> $null
        $item = @($sumario.itens | Where-Object { "$($_.tipo)" -eq 'cmdlet' })[0]
        # XboxApp legado e Xbox.TCUI/XboxSpeechToTextOverlay nao tem storeId conhecido -> falha parcial esperada.
        $item.resultado | Should -Be 'falha'
        $global:TmxT_Instalados | Should -Contain '9MV0B5HZVK9Z'
    }
}

# ---------------------------------------------------------------------------
# SEC-001: protecao em tempo real do Defender
# ---------------------------------------------------------------------------

Describe 'SEC-001 - Defender real-time protection' -Tag 'TweaksV2' {

    BeforeEach {
        $script:run = New-TmxRun
        $script:Tweak = [pscustomobject]@{ id = 'SEC-001' }
    }

    It 'nunca chama nada que desligue a Protecao em Tempo Real por script' {
        $arquivo = Join-Path $script:RepoRaiz 'src\functions\tweaks\V2DefenderRealtime.ps1'
        $linhasDeCodigo = @(Get-Content -LiteralPath $arquivo | Where-Object { $_.TrimStart() -notmatch '^#' })
        $texto = $linhasDeCodigo -join "`n"
        $texto | Should -Not -Match 'Set-MpPreference'
        $texto | Should -Not -Match 'DisableRealtimeMonitoring'
    }

    It 'le o estado (RTP + Protecao contra Adulteracao) sem escrever nada' {
        Mock Get-TmxV2DefenderComputerStatus -ModuleName TweakMaxing {
            [pscustomobject]@{ RealTimeProtectionEnabled = $true; IsTamperProtected = $true }
        }
        $st = Get-TmxDefenderRealtimeStatus -Tweak $script:Tweak -Profile $null
        $st.protecaoTempoRealAtiva   | Should -BeTrue
        $st.protecaoAdulteracaoAtiva | Should -BeTrue
    }

    It 'falha ao ler o Defender vira estado desconhecido, nao excecao' {
        Mock Get-TmxV2DefenderComputerStatus -ModuleName TweakMaxing { throw 'Get-MpComputerStatus indisponivel' }
        $st = Get-TmxDefenderRealtimeStatus -Tweak $script:Tweak -Profile $null
        $st.protecaoTempoRealAtiva | Should -BeNullOrEmpty
        $st.detalhe | Should -Match 'Defender'
    }

    It 'abre a tela de configuracoes do Defender pelo wrapper (uri propria, nao https)' {
        Mock Start-TmxV2DefenderSettingsUri -ModuleName TweakMaxing { 'windowsdefender://threatsettings' }
        $r = Open-TmxDefenderManualSettings -Tweak $script:Tweak -Profile $null
        $r.ok | Should -BeTrue
        Should -Invoke -CommandName Start-TmxV2DefenderSettingsUri -ModuleName TweakMaxing -Times 1
    }

    It 'alternativa segura: exclui as pastas do jogo, verifica e o Undo remove a exclusao' {
        $global:TmxT_Excluidas = New-Object 'System.Collections.Generic.List[string]'
        Mock Get-TmxDefenderExclusions -ModuleName TweakMaxing { @($global:TmxT_Excluidas.ToArray()) }
        Mock Add-TmxDefenderExclusionPath -ModuleName TweakMaxing {
            param($Path)
            if (-not $global:TmxT_Excluidas.Contains("$Path")) { $global:TmxT_Excluidas.Add("$Path") }
        }
        Mock Remove-TmxDefenderExclusionPath -ModuleName TweakMaxing {
            param($Path)
            [void]$global:TmxT_Excluidas.Remove("$Path")
        }

        $parametros = [pscustomobject]@{ pastas = @('C:\Games\MeuJogo') }

        (Test-TmxDefenderExclusionAlternative -Tweak $script:Tweak -Profile $null -Parametros $parametros).aplicado | Should -BeFalse

        $r = Set-TmxDefenderExclusionAlternative -Tweak $script:Tweak -Profile $null -Parametros $parametros
        $r.ok | Should -BeTrue
        Should -Invoke -CommandName Add-TmxDefenderExclusionPath -ModuleName TweakMaxing -Times 1 -ParameterFilter { $Path -eq 'C:\Games\MeuJogo' }

        (Test-TmxDefenderExclusionAlternative -Tweak $script:Tweak -Profile $null -Parametros $parametros).aplicado | Should -BeTrue

        Undo-TweakMaxing -Latest 6> $null | Out-Null
        Should -Invoke -CommandName Remove-TmxDefenderExclusionPath -ModuleName TweakMaxing -Times 1 -ParameterFilter { $Path -eq 'C:\Games\MeuJogo' }
        (Test-TmxDefenderExclusionAlternative -Tweak $script:Tweak -Profile $null -Parametros $parametros).aplicado | Should -BeFalse
    }

    It 'sem pastas informadas -> naoAplicavel, nunca chama Add-TmxDefenderExclusionPath' {
        Mock Add-TmxDefenderExclusionPath -ModuleName TweakMaxing { }
        $r = Set-TmxDefenderExclusionAlternative -Tweak $script:Tweak -Profile $null -Parametros ([pscustomobject]@{ pastas = @() })
        $r.ok | Should -BeTrue
        $r.naoAplicavel | Should -BeTrue
        Should -Invoke -CommandName Add-TmxDefenderExclusionPath -ModuleName TweakMaxing -Times 0
    }
}
