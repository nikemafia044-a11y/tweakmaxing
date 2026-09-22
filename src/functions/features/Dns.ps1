# functions/features/Dns.ps1
# Catalogo e medicao de DNS da aba "Configurar".
#
# A APLICACAO do DNS nao mora aqui: e Set-TmxDns (functions/tweaks/Dns.ps1),
# chamada pelo Engine atraves de um tweak transitorio RED-DNS. Este arquivo
# so le o catalogo, o estado atual e mede latencia.

$script:TmxDnsBenchAmostras = 3
$script:TmxDnsBenchNome     = 'www.microsoft.com'

function Get-TmxDnsCatalogPath {
    [CmdletBinding()]
    param()
    $dir = Get-TmxFeatureConfigDir
    if ($dir) { return (Join-Path $dir 'dns.json') }
    $null
}

function Get-TmxDnsCatalog {
    <#
    .SYNOPSIS
        Provedores de src/config/dns.json, na ordem do arquivo.
    .OUTPUTS
        Array de { id, nome, primario, secundario, primario6, secundario6, doh, benchmark }.
    #>
    [CmdletBinding()]
    param([string] $Path)

    if (-not $Path) {
        $cfg = $null
        if ($null -ne $sync) { $cfg = $sync.configs }
        if ($null -ne $cfg -and $cfg -is [System.Collections.IDictionary] -and $cfg.Contains('dns')) {
            $doc = $cfg['dns']
            if ($null -ne $doc -and $null -ne $doc.dns) { return (ConvertTo-TmxDnsCatalogEntries -Entradas $doc.dns) }
        }
        $Path = Get-TmxDnsCatalogPath
    }

    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) {
        throw "dns.json nao encontrado (procurado em: '$Path')"
    }
    $doc = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    ConvertTo-TmxDnsCatalogEntries -Entradas $doc.dns
}

function ConvertTo-TmxDnsCatalogEntries {
    [CmdletBinding()]
    param($Entradas)

    $lista = New-Object 'System.Collections.Generic.List[object]'
    foreach ($e in @($Entradas)) {
        if ($null -eq $e -or -not "$($e.id)") { continue }
        $lista.Add([pscustomobject]@{
            id          = "$($e.id)"
            nome        = "$($e.nome)"
            primario    = "$($e.primario)"
            secundario  = "$($e.secundario)"
            primario6   = "$($e.primario6)"
            secundario6 = "$($e.secundario6)"
            doh         = "$($e.doh)"
            benchmark   = [bool]$e.benchmark
        })
    }
    # .ToArray(): @() sobre List generica vazia falha no PS 5.1
    $lista.ToArray()
}

function Get-TmxDnsCurrent {
    <#
    .SYNOPSIS
        Servidores DNS de cada adaptador conectado.
    .OUTPUTS
        Array de { indice, nome, v4[], v6[] }.
    #>
    [CmdletBinding()]
    param()

    # Sem a protecao de virgula, e de proposito: Get-TmxDnsEstadoAtual JA
    # devolve o array protegido, e proteger de novo por cima faz
    # '@(Get-TmxDnsCurrent)' virar um array DENTRO de um array - quem indexar
    # o resultado recebe um Object[] onde esperava o adaptador e le .v4/.v6
    # como $null. Aqui a saida segue a mesma convencao de Get-TmxPanelCatalog
    # e Get-TmxDnsCatalog: o chamador envolve com @() ou percorre com foreach.
    $lista = New-Object 'System.Collections.Generic.List[object]'
    try {
        foreach ($a in (Get-TmxDnsEstadoAtual)) { if ($a) { $lista.Add($a) } }
    } catch {
        Write-TmxLog -Level WARN -Message "Estado de DNS nao pode ser lido: $($_.Exception.Message)"
    }
    $lista.ToArray()
}

function Get-TmxDnsBenchmark {
    <#
    .SYNOPSIS
        Mede a latencia dos provedores marcados como elegiveis no dns.json.
    .DESCRIPTION
        Porta de reference/winutil/functions/private/Get-WinUtilDNSBenchmark.ps1
        com duas diferencas: mede uma CONSULTA DNS de verdade (Resolve-DnsName)
        em vez de um handshake TCP na porta 53 - um servidor pode aceitar a
        conexao e demorar para responder - e tira N amostras, porque a primeira
        consulta carrega custo de cache frio que nao representa o provedor.

        Provedores com benchmark=false ficam de fora: sao os filtrados
        (malware/adulto/anuncios), que nunca devem ser escolhidos por serem
        rapidos - a escolha ali e de politica, nao de latencia.
    .OUTPUTS
        Array de { id, nome, medioMs, falhas, amostras } ordenado por medioMs
        (quem falhou em tudo vai para o fim, com medioMs = $null).
    #>
    [CmdletBinding()]
    param(
        [int] $Amostras = $script:TmxDnsBenchAmostras,
        [string] $NomeConsulta = $script:TmxDnsBenchNome
    )

    if ($Amostras -lt 1) { $Amostras = 1 }

    $provedores = @(Get-TmxDnsCatalog | Where-Object { $_.benchmark -and $_.primario })
    $total      = [math]::Max($provedores.Count, 1)
    $resultados = New-Object 'System.Collections.Generic.List[object]'
    $i = 0

    foreach ($p in $provedores) {
        $i++
        Send-TmxFixProgress -Pct ([int](($i - 1) / $total * 95)) -Status "Medindo $($p.nome)..."

        $tempos = New-Object 'System.Collections.Generic.List[int]'
        $falhas = 0
        for ($n = 0; $n -lt $Amostras; $n++) {
            $ms = Measure-TmxDnsQuery -Servidor $p.primario -Nome $NomeConsulta
            if ($null -eq $ms) { $falhas++ } else { $tempos.Add([int]$ms) }
        }

        $arr = $tempos.ToArray()
        $medio = $null
        if ($arr.Count -gt 0) {
            $medio = [int][math]::Round((($arr | Measure-Object -Sum).Sum / $arr.Count), 0)
        }

        $resultados.Add([pscustomobject]@{
            id       = "$($p.id)"
            nome     = "$($p.nome)"
            servidor = "$($p.primario)"
            medioMs  = $medio
            falhas   = $falhas
            amostras = $Amostras
        })
    }

    Send-TmxFixProgress -Pct 100 -Status 'Concluido'

    # $null vai para o fim: Sort-Object coloca $null primeiro, e "nao respondeu"
    # nao pode aparecer como o provedor mais rapido da lista.
    $ok    = @($resultados.ToArray() | Where-Object { $null -ne $_.medioMs } | Sort-Object medioMs)
    $ruins = @($resultados.ToArray() | Where-Object { $null -eq $_.medioMs } | Sort-Object nome)

    $final = New-Object 'System.Collections.Generic.List[object]'
    foreach ($r in $ok)    { $final.Add($r) }
    foreach ($r in $ruins) { $final.Add($r) }
    $final.ToArray()
}

function New-TmxDnsTweak {
    <#
    .SYNOPSIS
        Tweak transitorio RED-DNS: aplica um provedor (ou 'dhcp') pelo Engine,
        para que a mudanca caia no state.json e o Undo saiba restaurar os
        servidores anteriores de cada adaptador.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Provedor)

    $rotulo = if ($Provedor -ieq 'dhcp') { 'Padrao do roteador (DHCP)' } else { $Provedor }

    [pscustomobject]@{
        id                       = 'RED-DNS'
        nome                     = "Servidores DNS - $rotulo"
        descricao                = 'Define os servidores DNS de todos os adaptadores conectados.'
        categoria                = 'Rede'
        tier                     = 'MEDIDO'
        risco                    = 'baixo'
        presets                  = @()
        controle                 = 'combobox'
        opcoes                   = @()
        grupo                    = $null
        reversivel               = 'total'
        requerReboot             = $false
        requerConsentimentoExtra = $false
        consentimento            = @{ titulo = $null; tradeoff = $null; frase = $null }
        condicoes                = @{ requer = @(); bloqueiaSe = @() }
        porque                   = 'O servidor DNS decide quanto tempo cada nome leva para virar endereco; trocar por um resolvedor proximo e uma mudanca medivel e reversivel.'
        evidencia                = 'A latencia de cada provedor e medida na propria maquina pelo botao "Testar latencia"; os servidores anteriores de cada adaptador vao para o state.json antes da troca.'
        folclore                 = $null
        instrucoes               = $null
        posAplicar               = $null
        acoes                    = @(@{ tipo = 'funcao'; nome = 'Set-TmxDns'; parametros = @{ provedor = $Provedor } })
    }
}
