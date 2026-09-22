# functions/tweaks/NicPower.ps1
# JOG-007 (origem CS2Tuner PWR-007): impede o Windows de desligar o adaptador
# de rede ativo para economizar energia. Porta de Tweaks/Power.ps1 (PWR-007).

function Get-TmxNicPm {
    param([Parameter(Mandatory)] [string] $Name)
    Get-NetAdapterPowerManagement -Name $Name -ErrorAction Stop
}

function Set-TmxNicPm {
    param([Parameter(Mandatory)] [string] $Name, [Parameter(Mandatory)] [string] $Allow)
    Set-NetAdapterPowerManagement -Name $Name -AllowComputerToTurnOffDevice $Allow -ErrorAction Stop
}

function Test-TmxNicPower {
    [CmdletBinding()]
    param($Tweak, $Profile)

    $n = $Profile.network.adaptadorAtivo.nome
    if (-not $n) {
        return [pscustomobject]@{ aplicado = $null; atual = $null; esperado = 'Disabled'; detalhe = 'adaptador ativo desconhecido' }
    }
    $pm = Get-TmxNicPm -Name $n
    $v = "$($pm.AllowComputerToTurnOffDevice)"
    [pscustomobject]@{ aplicado = ($v -eq 'Disabled'); atual = $v; esperado = 'Disabled'; detalhe = "AllowComputerToTurnOffDevice=$v em '$n'" }
}

function Set-TmxNicPower {
    [CmdletBinding()]
    param($Tweak, $Profile, $Parametros)

    $n = $Profile.network.adaptadorAtivo.nome
    if (-not $n) { return [pscustomobject]@{ ok = $false; detalhe = 'adaptador ativo desconhecido' } }

    $pm = Get-TmxNicPm -Name $n
    $antes = "$($pm.AllowComputerToTurnOffDevice)"
    if ($antes -eq 'Unsupported') {
        return [pscustomobject]@{ ok = $true; naoAplicavel = $true; detalhe = "'$n' nao suporta gerenciamento de energia" }
    }

    $rec = New-TmxCmdletRecord -TweakId "$($Tweak.id)" -Funcao 'Set-TmxNicPower' -Alvo "energia do adaptador '$n'" `
            -Estado @{ adaptador = $n; anterior = $antes } -ValorAnterior $antes -ValorNovo 'Disabled'
    try {
        Set-TmxNicPm -Name $n -Allow 'Disabled'
        Complete-TmxStateRecord -Record $rec -Ok $true | Out-Null
        [pscustomobject]@{ ok = $true; detalhe = "'$n': $antes -> Disabled"; registro = $rec }
    } catch {
        Complete-TmxStateRecord -Record $rec -Ok $false -Erro $_.Exception.Message | Out-Null
        [pscustomobject]@{ ok = $false; detalhe = $_.Exception.Message; registro = $rec }
    }
}

function Undo-TmxNicPower {
    [CmdletBinding()]
    param($Estado)

    if (-not $Estado -or -not "$($Estado.adaptador)") { throw 'sem adaptador no estado; nada a restaurar' }
    Set-TmxNicPm -Name "$($Estado.adaptador)" -Allow "$($Estado.anterior)"
    "'$($Estado.adaptador)': AllowComputerToTurnOffDevice restaurado para $($Estado.anterior)"
}
