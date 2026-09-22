# functions/tweaks/BitLocker.ps1
# SIS-003: desativar o BitLocker na unidade do sistema.
#
# Reversibilidade PARCIAL: reativar recriptografa o volume e gera uma chave de
# recuperacao nova. A anterior deixa de valer, e isso esta dito no consentimento.

function Test-TmxBitLocker {
    [CmdletBinding()]
    param($Tweak, $Profile)

    try {
        $v = Get-TmxBitLockerStatus -MountPoint $env:SystemDrive
    } catch {
        return [pscustomobject]@{ aplicado = $null; atual = $null; esperado = 'Off'; detalhe = "BitLocker indisponivel: $($_.Exception.Message)" }
    }
    $protecao = "$($v.ProtectionStatus)"
    [pscustomobject]@{
        aplicado = ($protecao -ieq 'Off')
        atual    = $protecao
        esperado = 'Off'
        detalhe  = "ProtectionStatus em $($env:SystemDrive): $protecao"
    }
}

function Set-TmxBitLocker {
    [CmdletBinding()]
    param($Tweak, $Profile, $Parametros)

    $montagem = $env:SystemDrive
    try {
        $v = Get-TmxBitLockerStatus -MountPoint $montagem
    } catch {
        return [pscustomobject]@{ ok = $true; naoAplicavel = $true; detalhe = "BitLocker indisponivel nesta edicao: $($_.Exception.Message)" }
    }

    $protecao = "$($v.ProtectionStatus)"
    if ($protecao -ieq 'Off') {
        return [pscustomobject]@{ ok = $true; naoAplicavel = $true; detalhe = "BitLocker ja esta desligado em $montagem" }
    }

    $rec = New-TmxCmdletRecord -TweakId "$($Tweak.id)" -Funcao 'Set-TmxBitLocker' -Alvo "BitLocker em $montagem" `
            -Estado @{ montagem = "$montagem"; protecaoAnterior = $protecao } `
            -ValorAnterior $protecao -ValorNovo 'Off'

    try {
        Disable-TmxBitLockerVolume -MountPoint $montagem
        Complete-TmxStateRecord -Record $rec -Ok $true | Out-Null
        [pscustomobject]@{ ok = $true; detalhe = "descriptografia iniciada em $montagem"; registro = $rec }
    } catch {
        Complete-TmxStateRecord -Record $rec -Ok $false -Erro $_.Exception.Message | Out-Null
        [pscustomobject]@{ ok = $false; detalhe = $_.Exception.Message; registro = $rec }
    }
}

function Undo-TmxBitLocker {
    [CmdletBinding()]
    param($Estado)

    $montagem = $env:SystemDrive
    if ($Estado -and $Estado.montagem) { $montagem = "$($Estado.montagem)" }

    $anterior = $null
    if ($Estado) { $anterior = "$($Estado.protecaoAnterior)" }
    if ($anterior -ine 'On') {
        return "BitLocker nao estava ligado antes em $montagem; nada a reativar"
    }

    Enable-TmxBitLockerVolume -MountPoint $montagem
    "BitLocker reativado em $montagem (chave de recuperacao nova: guarde-a)"
}
