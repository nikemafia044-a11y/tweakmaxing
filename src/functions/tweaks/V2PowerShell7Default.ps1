# functions/tweaks/V2PowerShell7Default.ps1
# SIS-014: PowerShell 7 como padrao do Windows Terminal.
#
# Sequencia: instala o PowerShell 7 pelo winget se pwsh.exe nao estiver no
# PATH, acha o guid do perfil "PowerShell" (source
# Windows.Terminal.PowershellCore, ou commandline apontando para pwsh.exe) no
# settings.json do Windows Terminal, guarda o CONTEUDO INTEIRO do arquivo
# antes de escrever e troca defaultProfile para esse guid.
#
# Reversibilidade PARCIAL DE PROPOSITO: o Desfazer restaura o settings.json
# exatamente como estava, mas NAO desinstala o PowerShell 7 - decisao do
# usuario, documentada no catalogo (campo 'atencao').

function Get-TmxWindowsTerminalSettingsPath {
    Join-Path $env:LocalAppData 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
}

function Resolve-TmxWindowsTerminalSettingsPath {
    <#
    .SYNOPSIS
        Caminho efetivo do settings.json: -SettingsPath explicito vence;
        senao Parametros.settingsPath (e assim que os testes e o modo de
        teste da ponte redirecionam para um arquivo temporario, sem tocar no
        Windows Terminal de verdade); senao o caminho real.
    #>
    [CmdletBinding()]
    param($Parametros, [string] $SettingsPath)

    if ($SettingsPath) { return $SettingsPath }
    $viaParam = "$(Get-TmxActionProp -Action $Parametros -Nome 'settingsPath' -Padrao '')"
    if ($viaParam) { return $viaParam }
    Get-TmxWindowsTerminalSettingsPath
}

function Find-TmxPowerShell7ProfileGuid {
    <#
    .SYNOPSIS
        Guid do perfil do PowerShell 7 em profiles.list, ou $null se nao
        achar (o Terminal so grava o perfil depois de ser aberto uma vez com
        o pwsh.exe presente).
    #>
    [CmdletBinding()]
    param($SettingsJson)

    $profiles = Get-TmxActionProp -Action $SettingsJson -Nome 'profiles' -Padrao $null
    $lista    = @(Get-TmxActionProp -Action $profiles -Nome 'list' -Padrao @())
    foreach ($p in $lista) {
        $source = "$(Get-TmxActionProp -Action $p -Nome 'source' -Padrao '')"
        $cmd    = "$(Get-TmxActionProp -Action $p -Nome 'commandline' -Padrao '')"
        if ($source -ieq 'Windows.Terminal.PowershellCore' -or $cmd -match '(?i)(^|[\\"])pwsh(\.exe)?("|\s|$)') {
            return "$(Get-TmxActionProp -Action $p -Nome 'guid' -Padrao '')"
        }
    }
    $null
}

function Test-TmxPowerShell7Default {
    [CmdletBinding()]
    param($Tweak, $Profile, $Parametros)

    $settingsPath = Resolve-TmxWindowsTerminalSettingsPath -Parametros $Parametros
    $texto = Get-TmxV2FileTextRaw -Path $settingsPath
    if ($null -eq $texto) {
        return [pscustomobject]@{ aplicado = $null; atual = $null; esperado = $null; detalhe = "settings.json nao encontrado: $settingsPath" }
    }

    try { $json = $texto | ConvertFrom-Json -ErrorAction Stop }
    catch { return [pscustomobject]@{ aplicado = $null; atual = $null; esperado = $null; detalhe = "settings.json invalido: $($_.Exception.Message)" } }

    $guid = Find-TmxPowerShell7ProfileGuid -SettingsJson $json
    $atualDefault = "$(Get-TmxActionProp -Action $json -Nome 'defaultProfile' -Padrao $null)"

    [pscustomobject]@{
        aplicado = $(if ($guid) { ($atualDefault -eq $guid) } else { $false })
        atual    = $atualDefault
        esperado = $(if ($guid) { $guid } else { '<perfil do PowerShell 7 nao encontrado>' })
        detalhe  = "defaultProfile atual: $atualDefault"
    }
}

function Set-TmxPowerShell7Default {
    [CmdletBinding()]
    param($Tweak, $Profile, $Parametros)

    if (-not (Get-TmxV2PwshCommand)) {
        $r = Invoke-TmxWinget @('install', '--id', 'Microsoft.PowerShell', '--source', 'winget',
                                 '--accept-package-agreements', '--accept-source-agreements')
        if ($r.codigo -ne 0) {
            return [pscustomobject]@{ ok = $false; detalhe = "winget install Microsoft.PowerShell falhou ($($r.codigo)): $($r.saida)" }
        }
    }

    $settingsPath = Resolve-TmxWindowsTerminalSettingsPath -Parametros $Parametros
    if (-not (Test-TmxItemPath -Path $settingsPath)) {
        return [pscustomobject]@{ ok = $true; naoAplicavel = $true; detalhe = "Windows Terminal nao encontrado (settings.json ausente em $settingsPath)" }
    }

    $textoAnterior = Get-TmxV2FileTextRaw -Path $settingsPath
    try { $json = $textoAnterior | ConvertFrom-Json -ErrorAction Stop }
    catch { return [pscustomobject]@{ ok = $false; detalhe = "settings.json invalido: $($_.Exception.Message)" } }

    $guid = Find-TmxPowerShell7ProfileGuid -SettingsJson $json
    if (-not $guid) {
        return [pscustomobject]@{ ok = $false; detalhe = 'perfil do PowerShell 7 nao encontrado no Windows Terminal (abra o Terminal uma vez depois de instalar e tente de novo)' }
    }

    $defaultAnterior = "$(Get-TmxActionProp -Action $json -Nome 'defaultProfile' -Padrao $null)"
    if ($defaultAnterior -eq $guid) {
        return [pscustomobject]@{ ok = $true; naoAplicavel = $true; detalhe = 'o PowerShell 7 ja e o perfil padrao do Windows Terminal' }
    }

    $rec = New-TmxCmdletRecord -TweakId "$($Tweak.id)" -Funcao 'Set-TmxPowerShell7Default' `
            -Alvo "Windows Terminal defaultProfile ($settingsPath)" `
            -Estado @{ path = $settingsPath; textoAnterior = $textoAnterior } `
            -ValorAnterior $defaultAnterior -ValorNovo $guid

    try {
        $json | Add-Member -NotePropertyName 'defaultProfile' -NotePropertyValue $guid -Force
        $novoTexto = $json | ConvertTo-Json -Depth 30
        Set-TmxV2FileTextRaw -Path $settingsPath -Texto $novoTexto
        Complete-TmxStateRecord -Record $rec -Ok $true | Out-Null
        [pscustomobject]@{ ok = $true; detalhe = "defaultProfile do Windows Terminal definido para o PowerShell 7 ($guid)"; registro = $rec }
    } catch {
        Complete-TmxStateRecord -Record $rec -Ok $false -Erro $_.Exception.Message | Out-Null
        [pscustomobject]@{ ok = $false; detalhe = $_.Exception.Message; registro = $rec }
    }
}

function Undo-TmxPowerShell7Default {
    [CmdletBinding()]
    param($Estado)

    if (-not $Estado -or -not "$($Estado.path)") { throw 'sem path no estado; nada a restaurar' }
    Set-TmxV2FileTextRaw -Path "$($Estado.path)" -Texto "$($Estado.textoAnterior)"
    'settings.json do Windows Terminal restaurado; o PowerShell 7 instalado nao foi removido'
}
