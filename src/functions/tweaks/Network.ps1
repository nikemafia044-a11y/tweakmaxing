# functions/tweaks/Network.ps1
# RED-004: Teredo. RED-005 (FOLCLORE): IPv6 nos adaptadores.

# ---------------------------------------------------------------------------
# RED-004: Teredo
# ---------------------------------------------------------------------------

function Get-TmxTeredoState {
    # 'disabled', 'default', 'client', 'enterpriseclient'... ou $null.
    $r = Invoke-TmxNetsh @('interface', 'teredo', 'show', 'state')
    if ($r.codigo -ne 0) { return $null }
    $m = [regex]::Match("$($r.saida)", '(?im)^\s*\S+\s*:\s*(disabled|default|client|enterpriseclient|server|offline|dormant|qualified|probe)\s*$')
    if ($m.Success) { return $m.Groups[1].Value.ToLowerInvariant() }
    if ("$($r.saida)" -match '(?i)\bdisabled\b') { return 'disabled' }
    $null
}

function Test-TmxTeredo {
    [CmdletBinding()]
    param($Tweak, $Profile)

    $estado = Get-TmxTeredoState
    if ($null -eq $estado) {
        return [pscustomobject]@{ aplicado = $null; atual = $null; esperado = 'disabled'; detalhe = 'netsh nao informou o estado do Teredo' }
    }
    [pscustomobject]@{
        aplicado = ($estado -eq 'disabled')
        atual    = $estado
        esperado = 'disabled'
        detalhe  = "estado do Teredo: $estado"
    }
}

function Set-TmxTeredo {
    [CmdletBinding()]
    param($Tweak, $Profile, $Parametros)

    $antes = Get-TmxTeredoState
    $rec = New-TmxCmdletRecord -TweakId "$($Tweak.id)" -Funcao 'Set-TmxTeredo' -Alvo 'tunel Teredo' `
            -Estado @{ estadoAnterior = $antes } -ValorAnterior $antes -ValorNovo 'disabled'

    try {
        $r = Invoke-TmxNetsh @('interface', 'teredo', 'set', 'state', 'disabled')
        if ($r.codigo -ne 0) { throw "netsh teredo set state disabled falhou ($($r.codigo)): $($r.saida)" }
        Complete-TmxStateRecord -Record $rec -Ok $true | Out-Null
        [pscustomobject]@{ ok = $true; detalhe = "Teredo: $antes -> disabled"; registro = $rec }
    } catch {
        Complete-TmxStateRecord -Record $rec -Ok $false -Erro $_.Exception.Message | Out-Null
        [pscustomobject]@{ ok = $false; detalhe = $_.Exception.Message; registro = $rec }
    }
}

function Undo-TmxTeredo {
    [CmdletBinding()]
    param($Estado)

    $alvo = 'default'
    if ($Estado -and $Estado.estadoAnterior) { $alvo = "$($Estado.estadoAnterior)" }
    if ($alvo -eq 'disabled') { $alvo = 'default' }

    $r = Invoke-TmxNetsh @('interface', 'teredo', 'set', 'state', $alvo)
    if ($r.codigo -ne 0) { throw "netsh teredo set state $alvo falhou ($($r.codigo)): $($r.saida)" }
    "Teredo restaurado para '$alvo'"
}

# ---------------------------------------------------------------------------
# RED-005 (FOLCLORE): IPv6 nos adaptadores
# ---------------------------------------------------------------------------

$script:TmxIpv6Component = 'ms_tcpip6'

function Test-TmxIpv6 {
    [CmdletBinding()]
    param($Tweak, $Profile)

    try {
        $ligacoes = @(Get-TmxNetAdapterBindingState -ComponentID $script:TmxIpv6Component)
    } catch {
        return [pscustomobject]@{ aplicado = $null; atual = $null; esperado = 'IPv6 desabilitado em todos os adaptadores'; detalhe = $_.Exception.Message }
    }
    if ($ligacoes.Count -eq 0) {
        return [pscustomobject]@{ aplicado = $null; atual = $null; esperado = 'IPv6 desabilitado em todos os adaptadores'; detalhe = 'nenhum adaptador com ms_tcpip6' }
    }

    $habilitados = @($ligacoes | Where-Object { $_.Enabled })
    [pscustomobject]@{
        aplicado = ($habilitados.Count -eq 0)
        atual    = "$($habilitados.Count) de $($ligacoes.Count) adaptador(es) com IPv6 ligado"
        esperado = '0 adaptador com IPv6 ligado'
        detalhe  = $(if ($habilitados.Count -gt 0) { "ainda ligados: $(@($habilitados | ForEach-Object { $_.Name }) -join ', ')" } else { 'IPv6 desligado em todos' })
    }
}

function Set-TmxIpv6 {
    [CmdletBinding()]
    param($Tweak, $Profile, $Parametros)

    try {
        $ligacoes = @(Get-TmxNetAdapterBindingState -ComponentID $script:TmxIpv6Component)
    } catch {
        return [pscustomobject]@{ ok = $false; detalhe = "nao foi possivel ler as ligacoes de $($script:TmxIpv6Component): $($_.Exception.Message)" }
    }

    $habilitados = @($ligacoes | Where-Object { $_.Enabled } | ForEach-Object { "$($_.Name)" })
    if ($habilitados.Count -eq 0) {
        return [pscustomobject]@{ ok = $true; naoAplicavel = $true; detalhe = 'IPv6 ja esta desligado em todos os adaptadores' }
    }

    $rec = New-TmxCmdletRecord -TweakId "$($Tweak.id)" -Funcao 'Set-TmxIpv6' -Alvo 'ligacao IPv6 dos adaptadores' `
            -Estado @{ componente = $script:TmxIpv6Component; adaptadoresHabilitados = $habilitados } `
            -ValorAnterior ($habilitados -join ', ') -ValorNovo 'nenhum'

    try {
        foreach ($nome in $habilitados) {
            Set-TmxNetAdapterBindingState -Name $nome -ComponentID $script:TmxIpv6Component -Habilitado $false
        }
        Complete-TmxStateRecord -Record $rec -Ok $true | Out-Null
        [pscustomobject]@{ ok = $true; detalhe = "IPv6 desligado em $($habilitados.Count) adaptador(es)"; registro = $rec }
    } catch {
        Complete-TmxStateRecord -Record $rec -Ok $false -Erro $_.Exception.Message | Out-Null
        [pscustomobject]@{ ok = $false; detalhe = $_.Exception.Message; registro = $rec }
    }
}

function Undo-TmxIpv6 {
    [CmdletBinding()]
    param($Estado)

    if (-not $Estado) { throw 'sem estado: nao da para saber quais adaptadores tinham IPv6 ligado' }
    $componente = "$($Estado.componente)"
    if (-not $componente) { $componente = $script:TmxIpv6Component }

    $nomes = @($Estado.adaptadoresHabilitados)
    if ($nomes.Count -eq 0) { return 'nenhum adaptador tinha IPv6 ligado; nada a restaurar' }

    foreach ($nome in $nomes) {
        if (-not $nome) { continue }
        Set-TmxNetAdapterBindingState -Name "$nome" -ComponentID $componente -Habilitado $true
    }
    "IPv6 religado em $($nomes.Count) adaptador(es): $($nomes -join ', ')"
}
