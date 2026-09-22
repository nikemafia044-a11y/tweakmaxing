# functions/tweaks/DeviceBlock.ps1
# SIS-008 / SIS-009: bloqueio das pastas que o Windows Update usa para reinstalar
# software de periferico (Razer Synapse e Logi Download Assistant).
#
# O mecanismo e o mesmo nos dois: esvaziar a pasta, garantir que ela exista e
# negar escrita para Everyone. Sem escrita, o instalador nao se recria.

function Get-TmxRazerBlockPath {
    Join-Path $env:SystemRoot 'Installer\Razer'
}

function Get-TmxLogiBlockPath {
    $programas = $env:ProgramW6432
    if (-not $programas) { $programas = $env:ProgramFiles }
    Join-Path $programas 'LogiDownloadAssistant'
}

function Get-TmxBloqueioDePasta {
    # Helper compartilhado: a pasta existe e a ACL tem negacao?
    param([Parameter(Mandatory)] [string] $Pasta)
    if (-not (Test-TmxItemPath -Path $Pasta)) {
        return [pscustomobject]@{ aplicado = $false; atual = 'pasta ausente'; esperado = 'pasta com negacao de escrita'; detalhe = "$Pasta nao existe" }
    }
    $r = Invoke-TmxIcacls @($Pasta)
    $temDeny = ("$($r.saida)" -match '(?i)\(DENY\)')
    [pscustomobject]@{
        aplicado = $temDeny
        atual    = $(if ($temDeny) { 'com negacao' } else { 'sem negacao' })
        esperado = 'com negacao'
        detalhe  = "ACL de ${Pasta}: $(if ($temDeny) { 'nega escrita' } else { 'sem negacao' })"
    }
}

function New-TmxBloqueioDePasta {
    # Helper compartilhado: esvazia, cria e nega escrita. Devolve o registro.
    param(
        [Parameter(Mandatory)] $Tweak,
        [Parameter(Mandatory)] [string] $Funcao,
        [Parameter(Mandatory)] [string] $Pasta,
        [Parameter(Mandatory)] [string] $Alvo,
        [string[]] $PararProcessos = @()
    )

    $rec = New-TmxCmdletRecord -TweakId "$($Tweak.id)" -Funcao $Funcao -Alvo $Alvo `
            -Estado @{ pasta = $Pasta; existiaAntes = (Test-TmxItemPath -Path $Pasta) } `
            -ValorAnterior 'sem negacao' -ValorNovo 'escrita negada para Everyone'

    try {
        if ($PararProcessos.Count -gt 0) { Stop-TmxProcessByName -Nome $PararProcessos }

        if (Test-TmxItemPath -Path $Pasta) {
            Remove-TmxItemPath -Path (Join-Path $Pasta '*') -Recursivo -Silencioso
        } else {
            New-TmxDirectory -Path $Pasta | Out-Null
        }

        $r = Invoke-TmxIcacls @($Pasta, '/deny', '*S-1-1-0:(W)')
        if ($r.codigo -ne 0) { throw "icacls /deny falhou em $Pasta ($($r.codigo)): $($r.saida)" }

        Complete-TmxStateRecord -Record $rec -Ok $true | Out-Null
        [pscustomobject]@{ ok = $true; detalhe = "escrita negada em $Pasta"; registro = $rec }
    } catch {
        Complete-TmxStateRecord -Record $rec -Ok $false -Erro $_.Exception.Message | Out-Null
        [pscustomobject]@{ ok = $false; detalhe = $_.Exception.Message; registro = $rec }
    }
}

function Remove-TmxBloqueioDePasta {
    param([Parameter(Mandatory)] [string] $Pasta)
    if (-not (Test-TmxItemPath -Path $Pasta)) { return "$Pasta nao existe; nada a liberar" }
    $r = Invoke-TmxIcacls @($Pasta, '/remove:d', '*S-1-1-0')
    if ($r.codigo -ne 0) { throw "icacls /remove:d falhou em $Pasta ($($r.codigo)): $($r.saida)" }
    "negacao de escrita removida em $Pasta"
}

# --- SIS-008: Razer --------------------------------------------------------

function Test-TmxRazerBlock {
    [CmdletBinding()]
    param($Tweak, $Profile)
    Get-TmxBloqueioDePasta -Pasta (Get-TmxRazerBlockPath)
}

function Set-TmxRazerBlock {
    [CmdletBinding()]
    param($Tweak, $Profile, $Parametros)
    New-TmxBloqueioDePasta -Tweak $Tweak -Funcao 'Set-TmxRazerBlock' -Pasta (Get-TmxRazerBlockPath) -Alvo 'pasta de instalacao da Razer'
}

function Undo-TmxRazerBlock {
    [CmdletBinding()]
    param($Estado)
    $pasta = Get-TmxRazerBlockPath
    if ($Estado -and $Estado.pasta) { $pasta = "$($Estado.pasta)" }
    Remove-TmxBloqueioDePasta -Pasta $pasta
}

# --- SIS-009: Logitech -----------------------------------------------------

function Test-TmxLogiBlock {
    [CmdletBinding()]
    param($Tweak, $Profile)
    Get-TmxBloqueioDePasta -Pasta (Get-TmxLogiBlockPath)
}

function Set-TmxLogiBlock {
    [CmdletBinding()]
    param($Tweak, $Profile, $Parametros)
    New-TmxBloqueioDePasta -Tweak $Tweak -Funcao 'Set-TmxLogiBlock' -Pasta (Get-TmxLogiBlockPath) `
        -Alvo 'pasta do Logi Download Assistant' -PararProcessos @('logi_download_assistant')
}

function Undo-TmxLogiBlock {
    [CmdletBinding()]
    param($Estado)
    $pasta = Get-TmxLogiBlockPath
    if ($Estado -and $Estado.pasta) { $pasta = "$($Estado.pasta)" }
    Remove-TmxBloqueioDePasta -Pasta $pasta
}
