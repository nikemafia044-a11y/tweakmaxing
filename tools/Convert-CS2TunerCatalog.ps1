<#
.SYNOPSIS
    Converte o catalogo de tweaks do CS2Tuner (data/tweaks.json) para o schema
    do TweakMaxing, gerando a categoria "Jogos".

.DESCRIPTION
    Le <Source> (o data/tweaks.json do CS2Tuner, 47 tweaks) e grava
    <Out>/tweaks.jogos.json no schema descrito em src/Engine/Catalog.ps1
    (Test-TmxCatalog).

    Mapeamento por tweak (ver docs da tarefa):
      id           : JOG-001..JOG-NNN, ordem do arquivo de origem
      origem       : { cs2tuner: '<id original>' }
      nome/porque/evidencia : copiados
      descricao    : = porque
      categoria    : 'Jogos / ' + categoria original
      tier/risco   : copiados
      presets      : conservador->minimo, competitivo->desktop+notebook,
                     agressivo->desktop (deduplicado, preservando ordem)
      reversivel   : sempre 'total' (fonte so tem reversivel=true)
      controle     : metodo manual -> 'info' (com instrucoes); senao 'checkbox'
      condicoes    : copiadas literalmente (mesma gramatica caminho/operador)
      folclore     : copiado, renomeando porqueNaoAplicamos -> porqueNaoRecomendamos
      acoes[]      : do metodo (registry/powercfg/netadapter/bcdedit/service/
                     powershellCmdlet->funcao/manual->[])
      posAplicar   : metodo.aplicarImediato (SystemParametersInfo/SettingChange)

    Saida: UTF-8 sem BOM, indentacao de 2 espacos, fim de linha LF, ordem de
    chaves estavel. Rodar duas vezes produz bytes identicos.

.PARAMETER Source
    Caminho do data/tweaks.json de origem (CS2Tuner).

.PARAMETER Out
    Diretorio de saida (normalmente src/config). O arquivo gravado e
    tweaks.jogos.json dentro dele.

.EXAMPLE
    .\tools\Convert-CS2TunerCatalog.ps1 -Source C:\Users\fantasy\Desktop\tweak\data\tweaks.json -Out src\config
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Source,
    [Parameter(Mandatory)] [string] $Out
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Leitura tolerante de propriedades (mesmo padrao de tools/Convert-WinUtilCatalog.ps1)
# ---------------------------------------------------------------------------

function Get-TmxConvProp {
    param($Obj, [Parameter(Mandatory)] [string] $Nome, $Padrao = $null)
    if ($null -eq $Obj) { return $Padrao }
    if ($Obj -is [System.Collections.IDictionary]) {
        if (-not $Obj.Contains($Nome)) { return $Padrao }
        $v = $Obj[$Nome]
        if ($null -eq $v) { return $Padrao }
        return $v
    }
    $p = $Obj.PSObject.Properties[$Nome]
    if ($null -eq $p -or $null -eq $p.Value) { return $Padrao }
    $p.Value
}

function Test-TmxConvHasProp {
    param($Obj, [Parameter(Mandatory)] [string] $Nome)
    if ($null -eq $Obj) { return $false }
    if ($Obj -is [System.Collections.IDictionary]) { return $Obj.Contains($Nome) }
    return ($null -ne $Obj.PSObject.Properties[$Nome])
}

# ---------------------------------------------------------------------------
# Serializador JSON proprio (copiado de tools/Convert-WinUtilCatalog.ps1:
# o ConvertTo-Json do PS 5.1 erra ordem de chaves, indentacao e acentos)
# ---------------------------------------------------------------------------

function ConvertTo-TmxJsonString {
    param([string] $Texto)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('"')
    foreach ($ch in $Texto.ToCharArray()) {
        $code = [int][char]$ch
        if     ($ch -ceq '"')  { [void]$sb.Append('\"') }
        elseif ($ch -ceq '\')  { [void]$sb.Append('\\') }
        elseif ($code -eq 8)   { [void]$sb.Append('\b') }
        elseif ($code -eq 12)  { [void]$sb.Append('\f') }
        elseif ($code -eq 10)  { [void]$sb.Append('\n') }
        elseif ($code -eq 13)  { [void]$sb.Append('\r') }
        elseif ($code -eq 9)   { [void]$sb.Append('\t') }
        elseif ($code -lt 32)  { [void]$sb.AppendFormat('\u{0:x4}', $code) }
        else                   { [void]$sb.Append($ch) }
    }
    [void]$sb.Append('"')
    $sb.ToString()
}

function ConvertTo-TmxJsonText {
    param($Valor, [int] $Nivel = 0)

    $ind  = ' ' * (2 * $Nivel)
    $ind2 = ' ' * (2 * ($Nivel + 1))
    $inv  = [System.Globalization.CultureInfo]::InvariantCulture

    if ($null -eq $Valor) { return 'null' }
    if ($Valor -is [bool]) { if ($Valor) { return 'true' } else { return 'false' } }
    if ($Valor -is [string]) { return (ConvertTo-TmxJsonString -Texto $Valor) }
    if ($Valor -is [int] -or $Valor -is [long] -or $Valor -is [int16] -or $Valor -is [byte] -or
        $Valor -is [uint16] -or $Valor -is [uint32] -or $Valor -is [uint64]) {
        return ([int64]$Valor).ToString($inv)
    }
    if ($Valor -is [double] -or $Valor -is [single] -or $Valor -is [decimal]) {
        return ([double]$Valor).ToString('R', $inv)
    }

    if ($Valor -is [System.Collections.IDictionary]) {
        $chaves = @($Valor.Keys)
        if ($chaves.Count -eq 0) { return '{}' }
        $linhas = New-Object 'System.Collections.Generic.List[string]'
        foreach ($k in $chaves) {
            $linhas.Add(('{0}{1}: {2}' -f $ind2, (ConvertTo-TmxJsonString -Texto "$k"),
                (ConvertTo-TmxJsonText -Valor $Valor[$k] -Nivel ($Nivel + 1))))
        }
        return ("{`n" + ($linhas.ToArray() -join ",`n") + "`n$ind}")
    }

    if ($Valor -is [pscustomobject]) {
        $props = @($Valor.PSObject.Properties)
        if ($props.Count -eq 0) { return '{}' }
        $linhas = New-Object 'System.Collections.Generic.List[string]'
        foreach ($p in $props) {
            $linhas.Add(('{0}{1}: {2}' -f $ind2, (ConvertTo-TmxJsonString -Texto $p.Name),
                (ConvertTo-TmxJsonText -Valor $p.Value -Nivel ($Nivel + 1))))
        }
        return ("{`n" + ($linhas.ToArray() -join ",`n") + "`n$ind}")
    }

    if ($Valor -is [System.Collections.IEnumerable]) {
        $itens = @($Valor)
        if ($itens.Count -eq 0) { return '[]' }
        $linhas = New-Object 'System.Collections.Generic.List[string]'
        foreach ($i in $itens) {
            $linhas.Add(('{0}{1}' -f $ind2, (ConvertTo-TmxJsonText -Valor $i -Nivel ($Nivel + 1))))
        }
        return ("[`n" + ($linhas.ToArray() -join ",`n") + "`n$ind]")
    }

    ConvertTo-TmxJsonString -Texto "$Valor"
}

function Save-TmxJsonFile {
    param([Parameter(Mandatory)] [string] $Path, [Parameter(Mandatory)] $Valor)
    $texto = (ConvertTo-TmxJsonText -Valor $Valor -Nivel 0) + "`n"
    $texto = $texto -replace "`r`n", "`n"
    $dir = Split-Path -Path $Path -Parent
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [System.IO.File]::WriteAllText($Path, $texto, (New-Object System.Text.UTF8Encoding($false)))
}

function Read-TmxJsonFile {
    param([Parameter(Mandatory)] [string] $Path)
    if (-not (Test-Path -LiteralPath $Path)) { throw "Arquivo nao encontrado: $Path" }
    Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

# ---------------------------------------------------------------------------
# Mapas de conversao
# ---------------------------------------------------------------------------

$script:TmxJogosPresetMap = @{
    'conservador' = @('minimo')
    'competitivo' = @('desktop', 'notebook')
    'agressivo'   = @('desktop')
}

$script:TmxJogosCmdletMap = @{
    'Set-TunerUltimatePowerPlan'  = 'Set-TmxUltimatePowerPlan'
    'Set-TunerNicPowerManagement' = 'Set-TmxNicPower'
    'Add-TunerDefenderExclusion'  = 'Set-TmxDefenderExclusion'
    'Enable-TunerTrim'            = 'Set-TmxTrim'
    'Set-TunerPagefile'           = 'Set-TmxPagefile'
    'Set-TunerGpuMsiMode'         = 'Set-TmxGpuMsi'
}

function ConvertTo-TmxJogosPresets {
    param($OrigPresets)
    $result = New-Object 'System.Collections.Generic.List[string]'
    foreach ($p in @($OrigPresets)) {
        if (-not $p) { continue }
        $chave = "$p"
        if (-not $script:TmxJogosPresetMap.ContainsKey($chave)) {
            throw "Convert-CS2TunerCatalog: preset de origem desconhecido '$chave'"
        }
        foreach ($mapeado in $script:TmxJogosPresetMap[$chave]) {
            if (-not $result.Contains($mapeado)) { $result.Add($mapeado) }
        }
    }
    , $result.ToArray()
}

function ConvertTo-TmxJogosAcoes {
    param($Metodo, [Parameter(Mandatory)] [string] $Id)

    $acoes = New-Object 'System.Collections.Generic.List[object]'
    $tipo  = "$(Get-TmxConvProp -Obj $Metodo -Nome 'tipo')"

    switch ($tipo) {

        'registry' {
            foreach ($e in @(Get-TmxConvProp -Obj $Metodo -Nome 'entradas')) {
                if ($null -eq $e) { continue }
                $acoes.Add([ordered]@{
                    tipo      = 'registry'
                    path      = "$($e.path)"
                    name      = "$($e.name)"
                    value     = $e.value
                    valueType = "$($e.type)"
                })
            }
        }

        'powercfg' {
            $acoes.Add([ordered]@{
                tipo         = 'powercfg'
                subgrupo     = "$(Get-TmxConvProp -Obj $Metodo -Nome 'subgrupo')"
                configuracao = "$(Get-TmxConvProp -Obj $Metodo -Nome 'configuracao')"
                valor        = (Get-TmxConvProp -Obj $Metodo -Nome 'valor')
                descricao    = "$(Get-TmxConvProp -Obj $Metodo -Nome 'descricao')"
            })
        }

        'netadapter' {
            $acoes.Add([ordered]@{
                tipo          = 'netadapter'
                chaves        = @(Get-TmxConvProp -Obj $Metodo -Nome 'chaves')
                valorRegistro = "$(Get-TmxConvProp -Obj $Metodo -Nome 'valorRegistro')"
                valorExibicao = "$(Get-TmxConvProp -Obj $Metodo -Nome 'valorExibicao')"
                aplicarTodas  = [bool](Get-TmxConvProp -Obj $Metodo -Nome 'aplicarTodas' -Padrao $false)
            })
        }

        'bcdedit' {
            $o = [ordered]@{
                tipo  = 'bcdedit'
                acao  = "$(Get-TmxConvProp -Obj $Metodo -Nome 'acao')"
                opcao = "$(Get-TmxConvProp -Obj $Metodo -Nome 'opcao')"
            }
            if (Test-TmxConvHasProp -Obj $Metodo -Nome 'valor') {
                $o['valor'] = "$(Get-TmxConvProp -Obj $Metodo -Nome 'valor')"
            }
            $acoes.Add($o)
        }

        'service' {
            $acoes.Add([ordered]@{
                tipo       = 'service'
                nome       = "$(Get-TmxConvProp -Obj $Metodo -Nome 'nome')"
                tipoInicio = "$(Get-TmxConvProp -Obj $Metodo -Nome 'tipoInicio')"
                parar      = [bool](Get-TmxConvProp -Obj $Metodo -Nome 'parar' -Padrao $false)
            })
        }

        'powershellCmdlet' {
            $origFn = "$(Get-TmxConvProp -Obj $Metodo -Nome 'funcao')"
            if (-not $script:TmxJogosCmdletMap.ContainsKey($origFn)) {
                throw "Convert-CS2TunerCatalog: cmdlet '$origFn' sem mapeamento (tweak $Id). Adicione-o a `$script:TmxJogosCmdletMap."
            }
            $novoFn = $script:TmxJogosCmdletMap[$origFn]
            $par = [ordered]@{}
            $fonte = Get-TmxConvProp -Obj $Metodo -Nome 'parametros' -Padrao $null
            if ($fonte) {
                foreach ($pp in $fonte.PSObject.Properties) { $par[$pp.Name] = $pp.Value }
            }
            $acoes.Add([ordered]@{ tipo = 'funcao'; nome = $novoFn; parametros = $par })
        }

        'manual' {
            # sem acoes: vai para 'instrucoes' no nivel do tweak.
        }

        default {
            throw "Convert-CS2TunerCatalog: metodo.tipo desconhecido '$tipo' (tweak $Id)"
        }
    }

    , $acoes.ToArray()
}

function ConvertTo-TmxJogosFolclore {
    param($Folclore)
    if (-not $Folclore) { return $null }
    [ordered]@{
        oQueE                 = "$(Get-TmxConvProp -Obj $Folclore -Nome 'oQueE' -Padrao '')"
        porqueCircula         = "$(Get-TmxConvProp -Obj $Folclore -Nome 'porqueCircula' -Padrao '')"
        porqueNaoRecomendamos = "$(Get-TmxConvProp -Obj $Folclore -Nome 'porqueNaoAplicamos' -Padrao '')"
    }
}

function ConvertTo-TmxJogosConsentimento {
    param($Consentimento)
    [ordered]@{
        titulo   = Get-TmxConvProp -Obj $Consentimento -Nome 'titulo'   -Padrao $null
        tradeoff = Get-TmxConvProp -Obj $Consentimento -Nome 'tradeoff' -Padrao $null
        frase    = Get-TmxConvProp -Obj $Consentimento -Nome 'frase'    -Padrao $null
    }
}

# ---------------------------------------------------------------------------
# Conversao de um tweak
# ---------------------------------------------------------------------------

function ConvertTo-TmxJogosTweak {
    param([Parameter(Mandatory)] $Origem, [Parameter(Mandatory)] [int] $Indice)

    $id     = 'JOG-{0:D3}' -f $Indice
    $origId = "$($Origem.id)"
    $metodo = Get-TmxConvProp -Obj $Origem -Nome 'metodo' -Padrao $null
    $tipoMetodo = "$(Get-TmxConvProp -Obj $metodo -Nome 'tipo')"
    $ehManual = ($tipoMetodo -eq 'manual')

    $controle = if ($ehManual) { 'info' } else { 'checkbox' }
    $instrucoes = if ($ehManual) { "$(Get-TmxConvProp -Obj $metodo -Nome 'instrucoes' -Padrao '')" } else { $null }

    $posAplicar = Get-TmxConvProp -Obj $metodo -Nome 'aplicarImediato' -Padrao $null
    if ($posAplicar) { $posAplicar = "$posAplicar" }

    $condOrigem = Get-TmxConvProp -Obj $Origem -Nome 'condicoes' -Padrao $null
    $condicoes = [ordered]@{
        requer     = @(Get-TmxConvProp -Obj $condOrigem -Nome 'requer')
        bloqueiaSe = @(Get-TmxConvProp -Obj $condOrigem -Nome 'bloqueiaSe')
    }

    $consOrigem = Get-TmxConvProp -Obj $Origem -Nome 'consentimento' -Padrao $null
    $consentimento = ConvertTo-TmxJogosConsentimento -Consentimento $consOrigem

    $folcloreOrigem = Get-TmxConvProp -Obj $Origem -Nome 'folclore' -Padrao $null
    $folclore = ConvertTo-TmxJogosFolclore -Folclore $folcloreOrigem

    [ordered]@{
        id     = $id
        origem = [ordered]@{ cs2tuner = $origId }

        nome                     = "$($Origem.nome)"
        descricao                = "$($Origem.porque)"
        categoria                = "Jogos / $($Origem.categoria)"
        tier                     = "$($Origem.tier)"
        risco                    = "$($Origem.risco)"
        presets                  = (ConvertTo-TmxJogosPresets -OrigPresets $Origem.presets)
        controle                 = $controle
        opcoes                   = @()
        grupo                    = $null
        reversivel               = 'total'
        requerReboot             = [bool](Get-TmxConvProp -Obj $Origem -Nome 'requerReboot' -Padrao $false)
        requerConsentimentoExtra = [bool](Get-TmxConvProp -Obj $Origem -Nome 'requerConsentimentoExtra' -Padrao $false)
        consentimento            = $consentimento
        condicoes                = $condicoes
        porque                   = "$($Origem.porque)"
        evidencia                = "$($Origem.evidencia)"
        folclore                 = $folclore
        instrucoes               = $instrucoes
        posAplicar               = $posAplicar
        acoes                    = (ConvertTo-TmxJogosAcoes -Metodo $metodo -Id $id)
    }
}

# ---------------------------------------------------------------------------
# Execucao
# ---------------------------------------------------------------------------

$sourcePath = $Source
if (-not [System.IO.Path]::IsPathRooted($sourcePath)) { $sourcePath = Join-Path (Get-Location).Path $sourcePath }
$outDir = $Out
if (-not [System.IO.Path]::IsPathRooted($outDir)) { $outDir = Join-Path (Get-Location).Path $outDir }

if (-not (Test-Path -LiteralPath $sourcePath)) {
    throw "Convert-CS2TunerCatalog: catalogo de origem nao encontrado: '$sourcePath'."
}

$origemDoc = Read-TmxJsonFile -Path $sourcePath
$origemTweaks = @($origemDoc.tweaks)
if ($origemTweaks.Count -eq 0) {
    throw "Convert-CS2TunerCatalog: '$sourcePath' nao tem nenhum tweak em .tweaks."
}

$saida = New-Object 'System.Collections.Generic.List[object]'
$idsVistos = New-Object 'System.Collections.Generic.HashSet[string]'
$indice = 0
foreach ($t in $origemTweaks) {
    if ($null -eq $t) { continue }
    $indice++
    if (-not $idsVistos.Add("$($t.id)")) {
        throw "Convert-CS2TunerCatalog: id de origem duplicado '$($t.id)' no arquivo '$sourcePath'."
    }
    $saida.Add((ConvertTo-TmxJogosTweak -Origem $t -Indice $indice))
}

if (-not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }

$documento = [ordered]@{
    versao    = 1
    descricao = 'Catalogo de tweaks de jogos (fonte: CS2Tuner). Tier: MEDIDO (efeito reprodutivel), TECNICO (mecanismo plausivel, ganho pequeno/dependente), FOLCLORE (nunca selecionado automaticamente).'
    tweaks    = $saida.ToArray()
}

$destino = Join-Path $outDir 'tweaks.jogos.json'
Save-TmxJsonFile -Path $destino -Valor $documento

Write-Output ('Convert-CS2TunerCatalog: {0} tweak(s) -> {1}' -f $saida.Count, $destino)
[pscustomobject]@{ tweaks = $saida.Count; saida = $destino }
