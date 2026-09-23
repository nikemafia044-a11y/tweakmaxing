<#
.SYNOPSIS
    Triagem de falhas do Pester com o Jev: ambiente/concorrencia, flaky, ou defeito real.
.DESCRIPTION
    Roda a suite (ou le um resultado NUnit XML ja gerado), extrai cada falha (nome + mensagem +
    trecho da stack) e pede ao Jev uma classificacao por item em uma unica chamada (ate 64 falhas):
      ambiente   : chave de registro de teste apagada por outro processo, porta ocupada, elevacao ausente, winget indisponivel
      flaky      : timing/timeout/race sem relacao com a mudanca de codigo
      defeito    : assercao de comportamento que indica bug real no codigo ou no teste
      outro      : nao da para decidir pela mensagem
    Falhas 'defeito' e 'review' sao listadas primeiro. Sem TYPESAFE_API_KEY, imprime as falhas e sai com 3.
.EXAMPLE
    .\tools\jev\Invoke-TmxJevTestTriage.ps1                 # roda a suite inteira e triagem
    .\tools\jev\Invoke-TmxJevTestTriage.ps1 -Tag Engine
    .\tools\jev\Invoke-TmxJevTestTriage.ps1 -ResultXml .\TestResults.xml
#>
[CmdletBinding()]
param(
    [string[]] $Tag,
    [string] $ResultXml,
    [string] $OutDir = (Join-Path $PSScriptRoot 'out')
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Invoke-TmxJev.ps1')
$raiz = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

if (-not $ResultXml) {
    Import-Module Pester -MinimumVersion 5.0.0
    $cfg = New-PesterConfiguration
    $cfg.Run.Path = Join-Path $raiz 'tests'
    $cfg.Run.Exit = $false
    $cfg.Output.Verbosity = 'Normal'
    $cfg.TestResult.Enabled = $true
    $cfg.TestResult.OutputFormat = 'NUnitXml'
    $ResultXml = Join-Path $OutDir 'pester-resultado.xml'
    $cfg.TestResult.OutputPath = $ResultXml
    if ($Tag) { $cfg.Filter.Tag = $Tag }
    Invoke-Pester -Configuration $cfg | Out-Null
}

[xml]$xml = Get-Content -LiteralPath $ResultXml -Raw -Encoding UTF8
$falhas = @($xml.SelectNodes('//test-case[@result="Failed" or @result="Failure"]') | ForEach-Object {
    $msg = "$($_.failure.message.'#cdata-section')$($_.failure.message.InnerText)"
    $stack = "$($_.failure.'stack-trace'.'#cdata-section')$($_.failure.'stack-trace'.InnerText)"
    [pscustomobject]@{ nome = $_.name; mensagem = $msg.Trim(); stack = ($stack.Trim() -split "`n" | Select-Object -First 6) -join "`n" }
})
Write-Host ("Falhas encontradas: {0}" -f $falhas.Count)
if ($falhas.Count -eq 0) { exit 0 }
if (-not (Test-TmxJevAvailable)) {
    $falhas | Format-Table nome, mensagem -AutoSize | Out-String | Write-Host
    Write-Warning 'TYPESAFE_API_KEY ausente: sem triagem automatica.'
    exit 3
}

$estado = @{ falhas = @{} }; $perguntas = @{}; $i = 0
foreach ($f in ($falhas | Select-Object -First 64)) {
    $i++; $chave = "f$i"
    $estado.falhas[$chave] = @{ teste = $f.nome; mensagem = $f.mensagem; stack = $f.stack }
    $perguntas["classe_$chave"] = @{
        type = 'choice'
        instructions = ('Classifique a falha em `falhas.' + $chave + '` pela mensagem e stack.')
        criteria = @{
            ambiente = 'Causa externa ao codigo: chave HKCU:\Software\TweakMaxing_Tests apagada por outro processo, porta CDP ocupada, falta de elevacao, winget/DISM indisponivel, arquivo de outro agente ausente.'
            flaky    = 'Timeout, espera por evento/job, ordem de eventos, tempo de resposta; passaria se rodasse de novo.'
            defeito  = 'Assercao de valor/estado/contagem errada, excecao no codigo sob teste, contrato de funcao violado: indica bug real.'
            outro    = 'Mensagem insuficiente para decidir.'
        }
    }
}
$resp = Invoke-TmxJev -State $estado -Questions $perguntas
$linhas = New-Object 'System.Collections.Generic.List[object]'; $i = 0
foreach ($f in ($falhas | Select-Object -First 64)) {
    $i++; $d = ConvertTo-TmxJevDecision -Answer $resp.answers."classe_f$i"
    $linhas.Add([pscustomobject]@{ classe = $d.rotulo; decisao = $d.decisao; p = [math]::Round($d.probabilidade, 2); teste = $f.nome; mensagem = ($f.mensagem -replace '\s+', ' ').Substring(0, [Math]::Min(120, $f.mensagem.Length)) })
}
$ordem = @{ defeito = 0; outro = 1; flaky = 2; ambiente = 3 }
$saida = $linhas.ToArray() | Sort-Object { if ($_.decisao -eq 'review') { -1 } else { $ordem[$_.classe] } }
# -InputObject: lista vazia vira '[]' em vez de deixar o relatorio antigo no disco.
(ConvertTo-Json -InputObject @($saida) -Depth 4) | Set-Content -LiteralPath (Join-Path $OutDir 'triagem-falhas.json') -Encoding UTF8
$saida | Format-Table classe, decisao, p, teste -AutoSize | Out-String | Write-Host
$uso = if ($resp.usage) { [int]$resp.usage.input_tokens + [int]$resp.usage.output_tokens } else { 0 }
Write-Host ("Jev triou {0} falhas ({1} tokens). Reveja primeiro as marcadas 'defeito' ou 'review'." -f $linhas.Count, $uso)
exit 0
