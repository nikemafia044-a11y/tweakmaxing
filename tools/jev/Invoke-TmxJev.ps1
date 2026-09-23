# tools/jev/Invoke-TmxJev.ps1
# Cliente minimo da API TypeSafe (modelo Jev, "System One") para verificacoes em lote.
#
# Jev nao escreve texto: recebe um estado + perguntas tipadas (noul = sim/nao, choice = uma
# opcao, score = nivel ordenado) e devolve probabilidades calibradas. Custa centavos e
# responde em menos de 1 s, por isso e usado aqui no lugar de um agente LLM para julgar
# muitos itens pequenos (catalogo, descricoes, falhas de teste).
#
# Requisito: $env:TYPESAFE_API_KEY (console.typesafe.ai/keys). Sem a chave, as funcoes
# lancam com mensagem clara e nenhum script deste diretorio faz chamada de rede.
#
# Referencia da API: https://docs.typesafe.ai/api.md
#   POST https://api.typesafe.ai/v1/systemone  { state, model, questions{ id: {type, instructions, criteria} } }

$script:TmxJevEndpoint = 'https://api.typesafe.ai/v1/systemone'
$script:TmxJevModel    = 'jev-latest'

function Test-TmxJevAvailable {
    <#
    .SYNOPSIS
        $true quando a chave da API esta configurada no ambiente.
    #>
    -not [string]::IsNullOrWhiteSpace($env:TYPESAFE_API_KEY)
}

function Invoke-TmxJev {
    <#
    .SYNOPSIS
        Envia um estado e um mapa de perguntas ao Jev e devolve as respostas tipadas.
    .PARAMETER State
        Texto ou objeto (hashtable/pscustomobject). Sempre a evidencia crua, nunca um resumo.
    .PARAMETER Questions
        Hashtable id -> @{ type='noul'|'choice'|'score'; instructions=...; criteria=... }.
    .OUTPUTS
        Objeto com .answers (por id), .usage e .model, como devolvido pela API.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $State,
        [Parameter(Mandatory)] [hashtable] $Questions,
        [int] $TimeoutSec = 60
    )
    if (-not (Test-TmxJevAvailable)) {
        throw 'TYPESAFE_API_KEY nao definida. Exporte a chave (console.typesafe.ai/keys) e rode de novo.'
    }
    if ($Questions.Count -eq 0) { throw 'Nenhuma pergunta informada.' }

    $body = @{ state = $State; model = $script:TmxJevModel; questions = $Questions } | ConvertTo-Json -Depth 20 -Compress
    if ($body.Length -gt 120000) {
        throw "Requisicao com $($body.Length) caracteres, acima do orcamento (~120K). Divida em lotes menores."
    }

    $headers = @{ Authorization = "Bearer $($env:TYPESAFE_API_KEY)"; 'Content-Type' = 'application/json' }
    # PS 5.1: Invoke-RestMethod envia string como ANSI a menos que o corpo seja bytes UTF-8.
    $bytes = [Text.Encoding]::UTF8.GetBytes($body)
    Invoke-RestMethod -Method Post -Uri $script:TmxJevEndpoint -Headers $headers -Body $bytes -TimeoutSec $TimeoutSec
}

function Split-TmxJevBatches {
    <#
    .SYNOPSIS
        Divide uma lista em lotes de tamanho fixo (limite pratico do Jev: ~40-64 itens por chamada).
    #>
    param([Parameter(Mandatory)] [object[]] $Items, [int] $Size = 40)
    $lotes = New-Object 'System.Collections.Generic.List[object]'
    for ($i = 0; $i -lt $Items.Count; $i += $Size) {
        $fim = [Math]::Min($i + $Size - 1, $Items.Count - 1)
        $lotes.Add(@($Items[$i..$fim]))
    }
    $lotes.ToArray()
}

function ConvertTo-TmxJevDecision {
    <#
    .SYNOPSIS
        Traduz uma resposta em decisao acionavel: 'auto' quando a probabilidade e conclusiva, senao 'review'.
    .NOTES
        noul: p >= Yes -> 'sim'; p <= No -> 'nao'; entre -> 'incerto'.
        choice: opcao vencedora com probabilidade >= Accept e margem >= Margin -> 'auto', senao 'review'.
    #>
    param(
        [Parameter(Mandatory)] $Answer,
        [double] $Yes = 0.8, [double] $No = 0.2,
        [double] $Accept = 0.85, [double] $Margin = 0.5
    )
    # A API devolve noul como { type = 'noul'; noul = <p> }. 'probability' fica
    # aceito por compatibilidade; sem o campo 'noul', toda resposta sim/nao caia
    # em 'desconhecido' e virava p=0 sem veredito.
    $campoP = $null
    foreach ($nomeCampo in 'noul', 'probability') {
        if ($null -ne $Answer.PSObject.Properties[$nomeCampo]) { $campoP = $nomeCampo; break }
    }
    if ($campoP -and $null -eq $Answer.PSObject.Properties['probabilities']) {
        $p = [double]$Answer.$campoP
        $veredito = if ($p -ge $Yes) { 'sim' } elseif ($p -le $No) { 'nao' } else { 'incerto' }
        return [pscustomobject]@{ tipo = 'noul'; probabilidade = $p; veredito = $veredito }
    }
    $probs = $Answer.probabilities
    if ($null -ne $probs) {
        $ordenado = @($probs.PSObject.Properties | Sort-Object { [double]$_.Value } -Descending)
        $top = $ordenado[0]; $segundo = if ($ordenado.Count -gt 1) { [double]$ordenado[1].Value } else { 0.0 }
        $margem = [double]$top.Value - $segundo
        $decisao = if ([double]$top.Value -ge $Accept -and $margem -ge $Margin) { 'auto' } else { 'review' }
        return [pscustomobject]@{ tipo = 'choice'; rotulo = $top.Name; probabilidade = [double]$top.Value; margem = $margem; decisao = $decisao }
    }
    [pscustomobject]@{ tipo = 'desconhecido'; bruto = $Answer }
}
