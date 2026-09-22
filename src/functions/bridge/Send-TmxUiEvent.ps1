# functions/bridge/Send-TmxUiEvent.ps1
# Caminho de volta: PowerShell -> JS. Sem correlacao de id, so { event, payload }.
#
# Tres destinos possiveis, nesta ordem:
#   1. $sync.uiEvents   - lista (testes e diagnostico); sempre recebe.
#   2. $sync.uiEventSink- scriptblock (testes); melhor esforco, nunca derruba.
#   3. $sync.webview    - a janela real, via Dispatcher (thread da UI).

function Send-TmxUiEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Event,
        $Payload
    )

    if ($null -eq $sync) { return }

    $envelope = [ordered]@{
        event   = $Event
        payload = $Payload
        ts      = (Get-Date).ToString('o')
    }

    # $null -ne ...: uma List/ArrayList VAZIA e falsy no PS 5.1, entao
    # 'if ($sync.uiEvents)' descartaria justamente o primeiro evento.
    if ($null -ne $sync.uiEvents) {
        try { [void]$sync.uiEvents.Add([pscustomobject]$envelope) } catch { }
    }

    if ($null -ne $sync.uiEventSink) {
        # Melhor esforco: o sink pode ter nascido em outro runspace (job), e
        # invocar um scriptblock de outro runspace lanca. O registro em
        # $sync.uiEvents acima ja garante observabilidade nos testes.
        try { & $sync.uiEventSink $envelope } catch { Write-Verbose "uiEventSink falhou: $($_.Exception.Message)" }
        return
    }

    if ($null -ne $sync.webview) {
        $json = ([pscustomobject]$envelope | ConvertTo-Json -Depth 12 -Compress)
        $wv   = $sync.webview
        try {
            $wv.Dispatcher.Invoke([action] {
                if ($wv.CoreWebView2) { $wv.CoreWebView2.PostWebMessageAsJson($json) }
            })
        } catch {
            Write-Verbose "Falha ao postar evento '$Event' na UI: $($_.Exception.Message)"
        }
    }
}

function Send-TmxJobProgress {
    <#
    .SYNOPSIS
        Progresso do job ativo (chamado de dentro do handler assincrono).
    #>
    [CmdletBinding()]
    param(
        [int]    $Pct,
        [string] $Status
    )

    $jobId = $null
    if ($null -ne $sync -and $null -ne $sync.activeJob) { $jobId = $sync.activeJob.jobId }
    Send-TmxUiEvent -Event 'job.progress' -Payload @{ jobId = $jobId; pct = $Pct; status = $Status }
}
