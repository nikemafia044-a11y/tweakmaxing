# functions/tweaks/DefenderExclusion.ps1
# JOG-038 (origem CS2Tuner SVC-005): exclusao do Defender para a pasta do CS2.
# requerConsentimentoExtra=true no catalogo (o Engine so aplica com consentido=true).
# Porta de Tweaks/Services.ps1 (SVC-005).

function Get-TmxDefenderExclusions {
    @((Get-MpPreference -ErrorAction Stop).ExclusionPath)
}

function Add-TmxDefenderExclusionPath {
    param([Parameter(Mandatory)] [string] $Path)
    Add-MpPreference -ExclusionPath $Path -ErrorAction Stop
}

function Remove-TmxDefenderExclusionPath {
    param([Parameter(Mandatory)] [string] $Path)
    Remove-MpPreference -ExclusionPath $Path -ErrorAction Stop
}

function Get-TmxCs2Folder {
    <#
    .SYNOPSIS
        Raiz do jogo: pasta 'Counter-Strike Global Offensive', ate 6 niveis
        acima de cs2.exe. $null se o perfil nao tem storage.cs2Path.
    #>
    param($Profile)
    $exe = $Profile.storage.cs2Path
    if (-not $exe) { return $null }
    $dir = Split-Path $exe -Parent
    for ($i = 0; $i -lt 6 -and $dir; $i++) {
        if ((Split-Path $dir -Leaf) -ieq 'Counter-Strike Global Offensive') { return $dir }
        $dir = Split-Path $dir -Parent
    }
    Split-Path (Split-Path (Split-Path (Split-Path $exe -Parent) -Parent) -Parent) -Parent
}

function Test-TmxDefenderExclusion {
    [CmdletBinding()]
    param($Tweak, $Profile)

    $pasta = Get-TmxCs2Folder -Profile $Profile
    if (-not $pasta) { return [pscustomobject]@{ aplicado = $null; atual = $null; esperado = $null; detalhe = 'pasta do CS2 desconhecida' } }
    $ex = Get-TmxDefenderExclusions
    $ok = [bool]($ex | Where-Object { $_ -ieq $pasta })
    [pscustomobject]@{ aplicado = $ok; atual = ($ex -join '; '); esperado = $pasta; detalhe = "exclusao $(if ($ok) { 'presente' } else { 'ausente' }): $pasta" }
}

function Set-TmxDefenderExclusion {
    [CmdletBinding()]
    param($Tweak, $Profile, $Parametros)

    $pasta = Get-TmxCs2Folder -Profile $Profile
    if (-not $pasta) { return [pscustomobject]@{ ok = $false; detalhe = 'pasta do CS2 desconhecida' } }

    $rec = New-TmxCmdletRecord -TweakId "$($Tweak.id)" -Funcao 'Set-TmxDefenderExclusion' -Alvo "exclusao do Defender: $pasta" `
            -Estado @{ pasta = $pasta } -ValorAnterior 'sem exclusao' -ValorNovo 'excluida'
    try {
        Add-TmxDefenderExclusionPath -Path $pasta
        Complete-TmxStateRecord -Record $rec -Ok $true | Out-Null
        [pscustomobject]@{ ok = $true; detalhe = "exclusao adicionada: $pasta"; registro = $rec }
    } catch {
        Complete-TmxStateRecord -Record $rec -Ok $false -Erro $_.Exception.Message | Out-Null
        [pscustomobject]@{ ok = $false; detalhe = $_.Exception.Message; registro = $rec }
    }
}

function Undo-TmxDefenderExclusion {
    [CmdletBinding()]
    param($Estado)

    if (-not $Estado -or -not "$($Estado.pasta)") { throw 'sem pasta no estado; nada a restaurar' }
    Remove-TmxDefenderExclusionPath -Path "$($Estado.pasta)"
    "exclusao removida: $($Estado.pasta)"
}
