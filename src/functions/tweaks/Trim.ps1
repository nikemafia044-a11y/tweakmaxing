# functions/tweaks/Trim.ps1
# JOG-040 (origem CS2Tuner STO-001): garante TRIM ativo no SSD/NVMe do sistema.
# Porta de Tweaks/Storage.ps1 (STO-001).
#
# A1: sem valor anterior legivel (fsutil nao devolveu nada reconhecivel) nao ha
# como reverter com seguranca -> nao aplica e NAO grava registro de estado.

function Invoke-TmxFsutil {
    param([Parameter(Mandatory)] [string[]] $Arguments)
    $out = & fsutil.exe @Arguments 2>&1
    [pscustomobject]@{ saida = (@($out) -join "`n"); codigo = $LASTEXITCODE }
}

function Get-TmxTrimDisabled {
    # 0 = TRIM ativo, 1 = desativado, $null = nao foi possivel ler
    $r = Invoke-TmxFsutil @('behavior', 'query', 'DisableDeleteNotify')
    if ($r.saida -match 'NTFS DisableDeleteNotify\s*=\s*(\d)') { return [int]$matches[1] }
    if ($r.saida -match 'DisableDeleteNotify\s*=\s*(\d)')      { return [int]$matches[1] }
    $null
}

function Test-TmxTrim {
    [CmdletBinding()]
    param($Tweak, $Profile)

    $d = Get-TmxTrimDisabled
    [pscustomobject]@{
        aplicado = $(if ($null -eq $d) { $null } else { $d -eq 0 })
        atual    = $d
        esperado = 0
        detalhe  = "NTFS DisableDeleteNotify = $d"
    }
}

function Set-TmxTrim {
    [CmdletBinding()]
    param($Tweak, $Profile, $Parametros)

    $antes = Get-TmxTrimDisabled
    if ($null -eq $antes) {
        # A1: sem valor anterior nao ha reversao possivel -> nao aplica e nao registra.
        return [pscustomobject]@{ ok = $false; detalhe = 'estado anterior ilegivel; nao aplicado' }
    }

    $rec = New-TmxCmdletRecord -TweakId "$($Tweak.id)" -Funcao 'Set-TmxTrim' -Alvo 'NTFS DisableDeleteNotify' `
            -Estado @{ anterior = $antes } -ValorAnterior $antes -ValorNovo 0

    $r = Invoke-TmxFsutil @('behavior', 'set', 'DisableDeleteNotify', 'NTFS', '0')
    if ($r.codigo -ne 0) { $r = Invoke-TmxFsutil @('behavior', 'set', 'DisableDeleteNotify', '0') }
    $ok = ($r.codigo -eq 0) -and ((Get-TmxTrimDisabled) -eq 0)
    Complete-TmxStateRecord -Record $rec -Ok $ok -Erro $(if (-not $ok) { "fsutil: $($r.saida)" }) | Out-Null
    [pscustomobject]@{ ok = $ok; detalhe = "DisableDeleteNotify $antes -> 0"; registro = $rec }
}

function Undo-TmxTrim {
    [CmdletBinding()]
    param($Estado)

    if (-not $Estado -or $null -eq $Estado.anterior) { throw 'valor anterior desconhecido' }
    $r = Invoke-TmxFsutil @('behavior', 'set', 'DisableDeleteNotify', 'NTFS', "$($Estado.anterior)")
    if ($r.codigo -ne 0) { $r = Invoke-TmxFsutil @('behavior', 'set', 'DisableDeleteNotify', "$($Estado.anterior)") }
    if ($r.codigo -ne 0) { throw "fsutil: $($r.saida)" }
    "DisableDeleteNotify restaurado para $($Estado.anterior)"
}
