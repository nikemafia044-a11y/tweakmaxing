# functions/bridge/Invoke-TmxBridgeRequest.ps1
# Unica porta de entrada do JS para o PowerShell.
#
# Contrato (docs/specs 3): pedido { id, action, payload } ->
# resposta { id, ok, result } ou { id, ok:false, error:{ message } }.
# Nunca lanca: a janela nao pode morrer por causa de uma mensagem malformada.

function ConvertTo-TmxBridgeJson {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Objeto)
    $Objeto | ConvertTo-Json -Depth 12 -Compress
}

function New-TmxBridgeError {
    [CmdletBinding()]
    param($Id, [Parameter(Mandatory)] [string] $Message)
    [ordered]@{ id = $Id; ok = $false; error = [ordered]@{ message = $Message } }
}

function Invoke-TmxBridgeRequest {
    <#
    .SYNOPSIS
        Interpreta uma mensagem da UI, despacha para o handler e devolve o JSON da resposta.
    .PARAMETER Json
        O texto recebido em WebMessageReceived (e.WebMessageAsJson).
    .OUTPUTS
        String JSON compacta.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [AllowNull()] [string] $Json
    )

    $req = $null
    try {
        if ($Json) { $req = $Json | ConvertFrom-Json }
    } catch {
        $req = $null
    }

    $id     = $null
    $action = $null
    if ($null -ne $req) {
        # Um JSON que nao seja objeto (ex.: "texto" ou 42) responde $null aqui,
        # sem lancar - cai no mesmo 'requisicao invalida'.
        $id     = $req.id
        $action = $req.action
    }

    if (-not $id -or -not $action) {
        return (ConvertTo-TmxBridgeJson (New-TmxBridgeError -Id $id -Message 'requisicao invalida'))
    }

    $action = "$action"
    $entry  = Get-TmxBridgeAction -Name $action
    if (-not $entry) {
        return (ConvertTo-TmxBridgeJson (New-TmxBridgeError -Id $id -Message "acao desconhecida: $action"))
    }

    $payload = $req.payload

    if ($entry.async) {
        try {
            $jobId = Start-TmxJob -Name $action -Payload $payload -Handler $entry.handler
            return (ConvertTo-TmxBridgeJson ([ordered]@{ id = $id; ok = $true; result = [ordered]@{ jobId = $jobId } }))
        } catch {
            return (ConvertTo-TmxBridgeJson (New-TmxBridgeError -Id $id -Message $_.Exception.Message))
        }
    }

    try {
        $resultado = & $entry.handler $payload
        return (ConvertTo-TmxBridgeJson ([ordered]@{ id = $id; ok = $true; result = $resultado }))
    } catch {
        Write-TmxLog -Level WARN -Message "Acao da ponte falhou: $action" -Data @{ erro = $_.Exception.Message }
        return (ConvertTo-TmxBridgeJson (New-TmxBridgeError -Id $id -Message $_.Exception.Message))
    }
}
