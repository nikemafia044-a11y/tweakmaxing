<#
.SYNOPSIS
    Verifica com o Jev quais descricoes de applications.json ainda nao estao em portugues do Brasil.
.DESCRIPTION
    236 apps em lotes de 60; uma pergunta noul por item ("descricao em pt-BR?"). Lista os ids com
    veredito 'nao' ou 'incerto' para alimentar src/config/overlay/applications.overrides.json.
    Sem TYPESAFE_API_KEY: gera os payloads e sai com codigo 3.
#>
[CmdletBinding()]
param(
    [string] $ConfigDir = (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'src\config'),
    [string] $OutDir = (Join-Path $PSScriptRoot 'out'),
    [int] $BatchSize = 60,
    [switch] $DryRun
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Invoke-TmxJev.ps1')

$docApps = Get-Content -LiteralPath (Join-Path $ConfigDir 'applications.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$apps = @(if ($null -ne $docApps.PSObject.Properties['aplicativos']) { $docApps.aplicativos } else { $docApps })
if ($apps.Count -eq 0) { throw 'applications.json vazio' }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function New-TmxJevAppsPayload {
    param([Parameter(Mandatory)] [object[]] $Lote)
    $estado = @{ apps = @{} }; $perguntas = @{}
    foreach ($a in $Lote) {
        $chave = "$($a.id)" -replace '[^A-Za-z0-9]', '_'
        $estado.apps[$chave] = @{ nome = "$($a.nome)"; descricao = "$($a.descricao)" }
        $perguntas["ptbr_$chave"] = @{
            type = 'noul'
            # Em ingles: o Jev e mais forte em ingles.
            instructions = ('Is the sentence in `apps.' + $chave + '.descricao` written in Portuguese? Accents may be omitted; English product names do not count as English.')
            criteria = @{ 'true' = 'Sentence grammar and common words are Portuguese'; 'false' = 'Sentence is in English or another language' }
        }
    }
    @{ state = $estado; questions = $perguntas; ids = @($Lote | ForEach-Object { "$($_.id)" }) }
}

$lotes = Split-TmxJevBatches -Items $apps -Size $BatchSize
$n = 0
foreach ($lote in $lotes) { $n++; ((New-TmxJevAppsPayload -Lote $lote) | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath (Join-Path $OutDir ("apps-lote-{0:00}.json" -f $n)) -Encoding UTF8 }
Write-Host ("Apps: {0} em {1} lote(s); payloads em {2}" -f $apps.Count, $lotes.Count, $OutDir)
if ($DryRun -or -not (Test-TmxJevAvailable)) { if (-not $DryRun) { Write-Warning 'TYPESAFE_API_KEY ausente: nenhuma chamada feita.' }; exit 3 }

$pendentes = New-Object 'System.Collections.Generic.List[object]'; $uso = 0; $n = 0
foreach ($lote in $lotes) {
    $n++
    $payload = New-TmxJevAppsPayload -Lote $lote
    $resp = Invoke-TmxJev -State $payload.state -Questions $payload.questions
    if ($resp.usage) { $uso += [int]$resp.usage.input_tokens + [int]$resp.usage.output_tokens }
    foreach ($id in $payload.ids) {
        $chave = $id -replace '[^A-Za-z0-9]', '_'
        $d = ConvertTo-TmxJevDecision -Answer $resp.answers."ptbr_$chave"
        if ($d.veredito -ne 'sim') { $pendentes.Add([pscustomobject]@{ id = $id; veredito = $d.veredito; p = [math]::Round($d.probabilidade, 2) }) }
    }
    Write-Host ("lote {0}/{1} ok" -f $n, $lotes.Count)
}
$saida = Join-Path $OutDir 'apps-sem-ptbr.json'
# -InputObject: lista vazia vira '[]'; pelo pipeline nada seria gravado e o relatorio antigo ficaria no disco.
(ConvertTo-Json -InputObject @($pendentes.ToArray()) -Depth 4) | Set-Content -LiteralPath $saida -Encoding UTF8
Write-Host ("Jev julgou {0} descricoes ({1} tokens). Sem pt-BR ou incertas: {2} -> {3}" -f $apps.Count, $uso, $pendentes.Count, $saida)
exit 0
