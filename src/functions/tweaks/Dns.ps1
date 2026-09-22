# functions/tweaks/Dns.ps1
# RED-006: servidores DNS dos adaptadores ativos.
#
# O estado anterior e guardado POR ADAPTADOR (indice + servidores IPv4 e IPv6),
# porque um "restaurar" global nao existe: cada placa pode ter uma configuracao
# diferente, e algumas estao em DHCP (lista vazia) enquanto outras tem servidor fixo.

$script:TmxDnsConfigPath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'config\dns.json'
$script:TmxDnsFamiliaV4  = 2
$script:TmxDnsFamiliaV6  = 23

function Get-TmxDnsProvider {
    <#
    .SYNOPSIS
        Dados de um provedor de DNS: { id, primario, secundario, primario6, secundario6 }.
        Procura primeiro em $sync.configs.dns (quando a UI ja carregou os configs)
        e depois em src/config/dns.json.
    #>
    param([Parameter(Mandatory)] [string] $Nome)

    $syncVar = Get-Variable -Name 'sync' -Scope Global -ErrorAction SilentlyContinue
    if ($syncVar -and $syncVar.Value) {
        $cfg = $syncVar.Value.configs
        if ($cfg -and $cfg.dns -and $cfg.dns.PSObject.Properties[$Nome]) {
            $e = $cfg.dns.$Nome
            return [pscustomobject]@{
                id          = $Nome
                primario    = "$($e.Primary)"
                secundario  = "$($e.Secondary)"
                primario6   = "$($e.Primary6)"
                secundario6 = "$($e.Secondary6)"
            }
        }
    }

    if (-not (Test-TmxItemPath -Path $script:TmxDnsConfigPath)) {
        throw "catalogo de DNS nao encontrado: $($script:TmxDnsConfigPath)"
    }
    $doc = Get-Content -LiteralPath $script:TmxDnsConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($e in @($doc.dns)) {
        if ($null -eq $e) { continue }
        if ("$($e.id)" -ieq $Nome) {
            return [pscustomobject]@{
                id          = "$($e.id)"
                primario    = "$($e.primario)"
                secundario  = "$($e.secundario)"
                primario6   = "$($e.primario6)"
                secundario6 = "$($e.secundario6)"
            }
        }
    }
    throw "provedor de DNS desconhecido: '$Nome'"
}

function Get-TmxDnsProvedorParametro {
    param($Parametros)
    $p = Get-TmxActionProp -Action $Parametros -Nome 'provedor' -Padrao $null
    if (-not $p) { throw "parametro 'provedor' ausente em Set-TmxDns" }
    "$p"
}

function Get-TmxDnsEstadoAtual {
    # [{ indice, nome, v4[], v6[] }] para cada adaptador conectado.
    $lista = New-Object 'System.Collections.Generic.List[object]'
    foreach ($ad in @(Get-TmxActiveNetAdapter)) {
        if ($null -eq $ad) { continue }
        $idx = [int]$ad.InterfaceIndex
        $v4 = @()
        $v6 = @()
        try { $v4 = @((Get-TmxDnsServerAddress -InterfaceIndex $idx -Familia $script:TmxDnsFamiliaV4).ServerAddresses) } catch { $v4 = @() }
        try { $v6 = @((Get-TmxDnsServerAddress -InterfaceIndex $idx -Familia $script:TmxDnsFamiliaV6).ServerAddresses) } catch { $v6 = @() }
        $lista.Add([pscustomobject]@{
            indice = $idx
            nome   = "$($ad.Name)"
            v4     = @($v4 | Where-Object { $_ })
            v6     = @($v6 | Where-Object { $_ })
        })
    }
    , $lista.ToArray()
}

function Test-TmxDns {
    [CmdletBinding()]
    param($Tweak, $Profile)

    $atual = Get-TmxDnsEstadoAtual
    if ($atual.Count -eq 0) {
        return [pscustomobject]@{ aplicado = $null; atual = $null; esperado = $null; detalhe = 'nenhum adaptador conectado' }
    }
    $resumo = @($atual | ForEach-Object { "$($_.nome)=[$($_.v4 -join ',')]" }) -join '; '
    [pscustomobject]@{
        aplicado = $null
        atual    = $resumo
        esperado = 'depende do provedor escolhido na combobox'
        detalhe  = "DNS por adaptador: $resumo"
    }
}

function Set-TmxDns {
    [CmdletBinding()]
    param($Tweak, $Profile, $Parametros)

    $provedor = Get-TmxDnsProvedorParametro -Parametros $Parametros
    $ehDhcp = ($provedor -ieq 'dhcp')

    $servidores = @()
    $dados = $null
    if (-not $ehDhcp) {
        $dados = Get-TmxDnsProvider -Nome $provedor
        foreach ($s in @($dados.primario, $dados.secundario, $dados.primario6, $dados.secundario6)) {
            if ($s) { $servidores += "$s" }
        }
        if ($servidores.Count -eq 0) { throw "provedor '$provedor' nao tem servidor configurado" }
    }

    $antes = Get-TmxDnsEstadoAtual
    if ($antes.Count -eq 0) {
        return [pscustomobject]@{ ok = $true; naoAplicavel = $true; detalhe = 'nenhum adaptador conectado' }
    }

    $estado = @{
        provedor    = $provedor
        adaptadores = @($antes | ForEach-Object { @{ indice = $_.indice; nome = $_.nome; v4 = @($_.v4); v6 = @($_.v6) } })
    }

    $rec = New-TmxCmdletRecord -TweakId "$($Tweak.id)" -Funcao 'Set-TmxDns' -Alvo 'servidores DNS dos adaptadores ativos' `
            -Estado $estado `
            -ValorAnterior (@($antes | ForEach-Object { "$($_.nome)=[$($_.v4 -join ',')]" }) -join '; ') `
            -ValorNovo $(if ($ehDhcp) { 'DHCP' } else { $servidores -join ', ' })

    try {
        foreach ($a in $antes) {
            if ($ehDhcp) { Set-TmxDnsServerAddress -InterfaceIndex $a.indice -Reset }
            else         { Set-TmxDnsServerAddress -InterfaceIndex $a.indice -Servidores $servidores }
        }
        Complete-TmxStateRecord -Record $rec -Ok $true | Out-Null
        $detalhe = "DNS de $($antes.Count) adaptador(es) -> $(if ($ehDhcp) { 'DHCP' } else { "$provedor ($($servidores -join ', '))" })"
        [pscustomobject]@{ ok = $true; detalhe = $detalhe; registro = $rec }
    } catch {
        Complete-TmxStateRecord -Record $rec -Ok $false -Erro $_.Exception.Message | Out-Null
        [pscustomobject]@{ ok = $false; detalhe = $_.Exception.Message; registro = $rec }
    }
}

function Undo-TmxDns {
    [CmdletBinding()]
    param($Estado)

    if (-not $Estado) { throw 'sem estado: nao da para saber qual era o DNS de cada adaptador' }
    $adaptadores = @($Estado.adaptadores)
    if ($adaptadores.Count -eq 0) { return 'nenhum adaptador registrado; nada a restaurar' }

    $partes = New-Object 'System.Collections.Generic.List[string]'
    foreach ($a in $adaptadores) {
        if ($null -eq $a) { continue }
        $idx = [int]$a.indice
        $servidores = @()
        foreach ($s in @($a.v4)) { if ($s) { $servidores += "$s" } }
        foreach ($s in @($a.v6)) { if ($s) { $servidores += "$s" } }

        if ($servidores.Count -eq 0) {
            Set-TmxDnsServerAddress -InterfaceIndex $idx -Reset
            $partes.Add("$($a.nome): de volta ao DHCP")
        } else {
            Set-TmxDnsServerAddress -InterfaceIndex $idx -Servidores $servidores
            $partes.Add("$($a.nome): $($servidores -join ', ')")
        }
    }
    "DNS restaurado - $($partes.ToArray() -join '; ')"
}
