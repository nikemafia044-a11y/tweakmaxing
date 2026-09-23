<#
.SYNOPSIS
    Auditoria do catalogo de tweaks com o Jev: tier coerente, texto sem promessa de ganho, portugues.
.DESCRIPTION
    Para cada tweak (WinUtil + Jogos + Atualizacoes), monta um estado com nome/porque/evidencia/tier e
    faz tres perguntas tipadas por item, em lotes de 25 itens por chamada:
      tier_<id>     (choice)  qual selo o texto sustenta: MEDIDO / TECNICO / FOLCLORE
      promessa_<id> (noul)    o texto promete ganho numerico ou nao verificavel?
      ptbr_<id>     (noul)    o texto esta em portugues do Brasil?
    A saida lista so o que exige atencao humana: tier divergente do declarado com decisao 'auto',
    promessa 'sim', idioma 'nao', e tudo o que ficou 'review'/'incerto'.
    Sem TYPESAFE_API_KEY: gera os payloads em -OutDir (para inspecao) e encerra com codigo 3.
.EXAMPLE
    .\tools\jev\Invoke-TmxJevCatalogQa.ps1
    .\tools\jev\Invoke-TmxJevCatalogQa.ps1 -DryRun -OutDir .\tests\gui\out\jev
#>
[CmdletBinding()]
param(
    [string] $ConfigDir = (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'src\config'),
    [string] $OutDir = (Join-Path $PSScriptRoot 'out'),
    [int] $BatchSize = 25,
    [switch] $DryRun
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Invoke-TmxJev.ps1')

function Get-TmxJevCatalogItems {
    param([string] $Dir)
    $itens = New-Object 'System.Collections.Generic.List[object]'
    foreach ($arquivo in (Get-ChildItem -LiteralPath $Dir -Filter 'tweaks*.json' | Sort-Object Name)) {
        $doc = Get-Content -LiteralPath $arquivo.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($t in @($doc.tweaks)) {
            $itens.Add([pscustomobject]@{
                id = "$($t.id)"; nome = "$($t.nome)"; tier = "$($t.tier)"
                porque = "$($t.porque)"; evidencia = "$($t.evidencia)"; descricao = "$($t.descricao)"
            })
        }
    }
    $itens.ToArray()
}

function New-TmxJevCatalogPayload {
    <#
    .SYNOPSIS
        Estado + perguntas para um lote. As chaves de item sao os ids do catalogo (referenciados em crases).
    #>
    param([Parameter(Mandatory)] [object[]] $Lote)
    $estado = @{ itens = @{} }
    $perguntas = @{}
    foreach ($t in $Lote) {
        $chave = $t.id -replace '[^A-Za-z0-9]', '_'
        $estado.itens[$chave] = @{ nome = $t.nome; porque = $t.porque; evidencia = $t.evidencia; tier_declarado = $t.tier }
        $perguntas["tier_$chave"] = @{
            type = 'choice'
            instructions = ('Considere apenas `itens.' + $chave + '` (nome, porque, evidencia). Qual selo de evidencia o texto sustenta? Ignore o campo tier_declarado.')
            criteria = @{
                MEDIDO   = 'O efeito descrito e direto, verificavel por leitura ou medicao, e o texto nao depende de suposicao (ex.: desligar telemetria, trocar plano de energia, extensao de arquivo visivel).'
                TECNICO  = 'Ha um mecanismo plausivel, mas o ganho depende do contexto, e pequeno ou indireto, e o texto admite isso.'
                FOLCLORE = 'O texto diz que nao ha sustentacao empirica, que o efeito e nulo ou que o custo supera o ganho; item mantido so por transparencia.'
            }
        }
        $perguntas["promessa_$chave"] = @{
            type = 'noul'
            instructions = ('Em `itens.' + $chave + '`, o texto de porque ou evidencia promete ganho de desempenho quantificado ou nao verificavel (percentual, "muito mais rapido", "elimina lag") sem apresentar como medir?')
            criteria = @{ 'true' = 'Promete numero ou ganho garantido sem base'; 'false' = 'Descreve mecanismo e limites de forma honesta, sem prometer numeros' }
        }
        $perguntas["ptbr_$chave"] = @{
            type = 'noul'
            # Em ingles: o Jev e mais forte em ingles (mesma pergunta em portugues deu p=0.69 num texto claramente pt-BR).
            instructions = ('Are the prose sentences in `itens.' + $chave + '` (fields porque and evidencia) written in Portuguese? Accents may be omitted; English technical terms, product and registry names are allowed.')
            criteria = @{ 'true' = 'Sentence grammar and common words are Portuguese'; 'false' = 'Sentences are in English or another language' }
        }
    }
    @{ state = $estado; questions = $perguntas; ids = @($Lote | ForEach-Object { $_.id }) }
}

$itens = Get-TmxJevCatalogItems -Dir $ConfigDir
if ($itens.Count -eq 0) { throw "Nenhum tweak em $ConfigDir" }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$lotes = Split-TmxJevBatches -Items $itens -Size $BatchSize
$n = 0
foreach ($lote in $lotes) {
    $n++
    $payload = New-TmxJevCatalogPayload -Lote $lote
    ($payload | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath (Join-Path $OutDir ("catalogo-lote-{0:00}.json" -f $n)) -Encoding UTF8
}
Write-Host ("Catalogo: {0} tweaks em {1} lote(s); payloads em {2}" -f $itens.Count, $lotes.Count, $OutDir)

if ($DryRun -or -not (Test-TmxJevAvailable)) {
    if (-not $DryRun) { Write-Warning 'TYPESAFE_API_KEY ausente: payloads gerados, nenhuma chamada feita.' }
    exit 3
}

$atencao = New-Object 'System.Collections.Generic.List[object]'
$totalUso = 0
$porId = @{}; foreach ($t in $itens) { $porId[$t.id] = $t }
$n = 0
foreach ($lote in $lotes) {
    $n++
    $payload = New-TmxJevCatalogPayload -Lote $lote
    $resp = Invoke-TmxJev -State $payload.state -Questions $payload.questions
    if ($resp.usage) { $totalUso += [int]$resp.usage.input_tokens + [int]$resp.usage.output_tokens }
    foreach ($id in $payload.ids) {
        $chave = $id -replace '[^A-Za-z0-9]', '_'
        $t = $porId[$id]
        $tier = ConvertTo-TmxJevDecision -Answer $resp.answers."tier_$chave"
        $prom = ConvertTo-TmxJevDecision -Answer $resp.answers."promessa_$chave"
        $pt   = ConvertTo-TmxJevDecision -Answer $resp.answers."ptbr_$chave"
        if ($tier.decisao -eq 'auto' -and $tier.rotulo -cne $t.tier) {
            $atencao.Add([pscustomobject]@{ id = $id; tipo = 'tier'; detalhe = "declarado $($t.tier), Jev sugere $($tier.rotulo) (p=$([math]::Round($tier.probabilidade,2)))" })
        } elseif ($tier.decisao -eq 'review') {
            $atencao.Add([pscustomobject]@{ id = $id; tipo = 'tier-review'; detalhe = "indeciso entre selos (top $($tier.rotulo) p=$([math]::Round($tier.probabilidade,2)))" })
        }
        if ($prom.veredito -eq 'sim')     { $atencao.Add([pscustomobject]@{ id = $id; tipo = 'promessa'; detalhe = "texto promete ganho (p=$([math]::Round($prom.probabilidade,2)))" }) }
        if ($prom.veredito -eq 'incerto') { $atencao.Add([pscustomobject]@{ id = $id; tipo = 'promessa-review'; detalhe = "p=$([math]::Round($prom.probabilidade,2))" }) }
        if ($pt.veredito -ne 'sim')       { $atencao.Add([pscustomobject]@{ id = $id; tipo = 'idioma'; detalhe = "portugues? p=$([math]::Round($pt.probabilidade,2))" }) }
    }
    Write-Host ("lote {0}/{1} ok" -f $n, $lotes.Count)
}

$relatorio = Join-Path $OutDir 'catalogo-atencao.json'
# -InputObject: lista vazia vira '[]'; pelo pipeline nada seria gravado e o relatorio antigo ficaria no disco.
(ConvertTo-Json -InputObject @($atencao.ToArray()) -Depth 5) | Set-Content -LiteralPath $relatorio -Encoding UTF8
Write-Host ("Jev julgou {0} tweaks ({1} tokens). Itens para revisao humana: {2} -> {3}" -f $itens.Count, $totalUso, $atencao.Count, $relatorio)
$atencao.ToArray() | Format-Table -AutoSize | Out-String | Write-Host
exit 0
