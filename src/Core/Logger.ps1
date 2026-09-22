# Core/Logger.ps1
# Transcript da sessao + log estruturado (JSON Lines) por execucao.
#
# Regras:
#  - Nada aqui escreve no host. Diagnostico vai para Verbose/Debug/Warning/Error.
#  - Write-TmxLog funciona mesmo sem logger inicializado (so nao persiste em disco).

$script:TmxLog = $null

function Initialize-TmxLogger {
    <#
    .SYNOPSIS
        Inicia transcript e log estruturado na pasta da execucao.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $RunPath,
        [Parameter(Mandatory)] [string] $RunId
    )

    New-Item -ItemType Directory -Path $RunPath -Force | Out-Null

    $transcriptPath = Join-Path $RunPath 'transcript.log'
    $eventsPath     = Join-Path $RunPath 'events.jsonl'

    # Encerra transcript anterior, se houver, para nao vazar entre execucoes.
    try { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null } catch { }

    $transcriptActive = $false
    try {
        Start-Transcript -Path $transcriptPath -Force -ErrorAction Stop | Out-Null
        $transcriptActive = $true
    } catch {
        # Alguns hosts nao suportam transcript; o log JSON continua funcionando.
        Write-Verbose "Transcript indisponivel neste host: $($_.Exception.Message)"
    }

    $script:TmxLog = [pscustomobject]@{
        RunId            = $RunId
        RunPath          = $RunPath
        TranscriptPath   = $transcriptPath
        EventsPath       = $eventsPath
        TranscriptActive = $transcriptActive
        StartedAt        = (Get-Date)
    }

    Write-TmxLog -Level INFO -Message 'Logger inicializado' -Data @{ runId = $RunId; transcript = $transcriptActive }
    $script:TmxLog
}

function Write-TmxLog {
    <#
    .SYNOPSIS
        Registra um evento estruturado. Nunca escreve no fluxo de saida.
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('DEBUG', 'INFO', 'WARN', 'ERROR')]
        [string] $Level = 'INFO',
        [Parameter(Mandatory)] [string] $Message,
        [hashtable] $Data
    )

    $entry = [ordered]@{
        ts      = (Get-Date).ToString('o')
        level   = $Level
        message = $Message
    }
    if ($Data) { $entry.data = $Data }

    if ($script:TmxLog -and $script:TmxLog.EventsPath) {
        try {
            $json = $entry | ConvertTo-Json -Compress -Depth 8
            # -WhatIf:$false: registrar no log nunca e uma acao a simular.
            Add-Content -LiteralPath $script:TmxLog.EventsPath -Value $json -Encoding UTF8 -WhatIf:$false
        } catch {
            Write-Verbose "Falha ao gravar evento no log: $($_.Exception.Message)"
        }
    }

    switch ($Level) {
        'DEBUG' { Write-Debug   $Message }
        'INFO'  { Write-Verbose $Message }
        'WARN'  { Write-Warning $Message }
        'ERROR' { Write-Warning "[ERRO] $Message" }
    }
}

function Stop-TmxLogger {
    [CmdletBinding()]
    param()
    if ($script:TmxLog -and $script:TmxLog.TranscriptActive) {
        try { Stop-Transcript | Out-Null } catch { }
        $script:TmxLog.TranscriptActive = $false
    }
}
