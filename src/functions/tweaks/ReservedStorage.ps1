# functions/tweaks/ReservedStorage.ps1
# SIS-005: Armazenamento Reservado. O estado vem do proprio DISM, nao do registro:
# a chave interna muda entre builds, o comando nao.

function Get-TmxReservedStorageState {
    # 'Enabled', 'Disabled' ou $null quando o DISM nao responde.
    $r = Invoke-TmxDism @('/Online', '/Get-ReservedStorageState')
    if ($r.codigo -ne 0) { return $null }
    if ("$($r.saida)" -match '(?i)\bdisabled\b') { return 'Disabled' }
    if ("$($r.saida)" -match '(?i)\benabled\b')  { return 'Enabled' }
    $null
}

function Test-TmxReservedStorage {
    [CmdletBinding()]
    param($Tweak, $Profile)

    $estado = Get-TmxReservedStorageState
    if ($null -eq $estado) {
        return [pscustomobject]@{ aplicado = $null; atual = $null; esperado = 'Disabled'; detalhe = 'DISM nao informou o estado' }
    }
    [pscustomobject]@{
        aplicado = ($estado -ieq 'Disabled')
        atual    = $estado
        esperado = 'Disabled'
        detalhe  = "Armazenamento Reservado: $estado"
    }
}

function Set-TmxReservedStorage {
    [CmdletBinding()]
    param($Tweak, $Profile, $Parametros)

    $antes = Get-TmxReservedStorageState
    if ($antes -ieq 'Disabled') {
        return [pscustomobject]@{ ok = $true; naoAplicavel = $true; detalhe = 'Armazenamento Reservado ja esta desativado' }
    }

    $rec = New-TmxCmdletRecord -TweakId "$($Tweak.id)" -Funcao 'Set-TmxReservedStorage' -Alvo 'Armazenamento Reservado' `
            -Estado @{ estadoAnterior = $antes } -ValorAnterior $antes -ValorNovo 'Disabled'

    try {
        $r = Invoke-TmxDism @('/Online', '/Set-ReservedStorageState', '/State:Disabled')
        if ($r.codigo -ne 0) { throw "DISM /Set-ReservedStorageState falhou ($($r.codigo)): $($r.saida)" }
        Complete-TmxStateRecord -Record $rec -Ok $true | Out-Null
        [pscustomobject]@{ ok = $true; detalhe = 'Armazenamento Reservado desativado'; registro = $rec }
    } catch {
        Complete-TmxStateRecord -Record $rec -Ok $false -Erro $_.Exception.Message | Out-Null
        [pscustomobject]@{ ok = $false; detalhe = $_.Exception.Message; registro = $rec }
    }
}

function Undo-TmxReservedStorage {
    [CmdletBinding()]
    param($Estado)

    $alvo = 'Enabled'
    if ($Estado -and $Estado.estadoAnterior) { $alvo = "$($Estado.estadoAnterior)" }
    if ($alvo -ine 'Enabled' -and $alvo -ine 'Disabled') { $alvo = 'Enabled' }

    $r = Invoke-TmxDism @('/Online', '/Set-ReservedStorageState', "/State:$alvo")
    if ($r.codigo -ne 0) { throw "DISM /Set-ReservedStorageState /State:$alvo falhou ($($r.codigo)): $($r.saida)" }
    "Armazenamento Reservado restaurado para $alvo"
}
