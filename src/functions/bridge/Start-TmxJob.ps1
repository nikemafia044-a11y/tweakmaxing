# functions/bridge/Start-TmxJob.ps1
# Pool de runspaces + um trabalho de cada vez.
#
# A janela nunca pode bloquear: toda acao longa vai para o pool e conversa com
# a UI por eventos (job.started / job.progress / job.done). Um trabalho por vez
# e deliberado - aplicar tweaks, instalar apps e reverter nao podem se cruzar.

function New-TmxSessionState {
    <#
    .SYNOPSIS
        InitialSessionState compartilhado pela runspace da UI e pelo pool.
    .DESCRIPTION
        Leva o $sync e toda funcao do TweakMaxing ja definida nesta sessao
        (nome contendo '-Tmx' ou 'TweakMaxing'). E o que permite a um job
        chamar qualquer helper sem reinjetar definicoes.
        Fica em cache em $sync.SessionState: montar isso nao e barato.
    #>
    [CmdletBinding()]
    param()

    if ($null -ne $sync -and $null -ne $sync.SessionState) {
        return $sync.SessionState
    }

    $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $iss.Variables.Add(
        (New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry -ArgumentList 'sync', $sync, $null)
    )

    foreach ($fn in (Get-Command -CommandType Function -ErrorAction SilentlyContinue)) {
        if ($fn.Name -notmatch '-Tmx|TweakMaxing') { continue }
        try {
            $iss.Commands.Add(
                (New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry -ArgumentList $fn.Name, $fn.Definition)
            )
        } catch {
            Write-Verbose "Funcao '$($fn.Name)' nao pode ser exportada para o runspace: $($_.Exception.Message)"
        }
    }

    if ($null -ne $sync) { $sync.SessionState = $iss }
    $iss
}

function Get-TmxRunspacePool {
    <#
    .SYNOPSIS
        Abre (uma vez) o pool onde os jobs rodam.
    #>
    [CmdletBinding()]
    param()

    if ($null -eq $sync) { throw 'Get-TmxRunspacePool: $sync nao existe (bootstrap nao rodou).' }

    $pool = $sync.runspacePool
    if ($null -ne $pool -and "$($pool.RunspacePoolStateInfo.State)" -eq 'Opened') { return $pool }

    $pool = [runspacefactory]::CreateRunspacePool(1, 2, (New-TmxSessionState), $Host)
    $pool.Open()
    $sync.runspacePool = $pool
    $pool
}

function Start-TmxJob {
    <#
    .SYNOPSIS
        Roda um handler no pool e devolve o jobId imediatamente.
    .DESCRIPTION
        Emite job.started antes e job.done depois (com ok/result ou ok/error).
        Um trabalho por vez: pedir outro enquanto ha um ativo lanca.
    .OUTPUTS
        O jobId (string).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Name,
        $Payload,
        [Parameter(Mandatory)] [scriptblock] $Handler
    )

    if ($null -eq $sync) { throw 'Start-TmxJob: $sync nao existe (bootstrap nao rodou).' }
    if ($null -ne $sync.activeJob) {
        throw 'ja existe um trabalho em andamento'
    }

    $jobId = [guid]::NewGuid().ToString('N')
    $pool  = Get-TmxRunspacePool

    $ps = [powershell]::Create()
    $ps.RunspacePool = $pool

    # O handler e reconstruido dentro do runspace do job: scriptblock tem
    # afinidade com o runspace onde nasceu e nao pode atravessar direto.
    $null = $ps.AddScript({
        param($jobId, $jobName, $jobPayload, $handlerText)

        Send-TmxUiEvent -Event 'job.started' -Payload @{ jobId = $jobId; name = $jobName }
        try {
            $handler = [scriptblock]::Create($handlerText)
            $resultado = & $handler $jobPayload
            Send-TmxUiEvent -Event 'job.done' -Payload @{ jobId = $jobId; name = $jobName; ok = $true; result = $resultado }
        } catch {
            Send-TmxUiEvent -Event 'job.done' -Payload @{ jobId = $jobId; name = $jobName; ok = $false; error = @{ message = $_.Exception.Message } }
        } finally {
            $sync.activeJob = $null
        }
    }).AddArgument($jobId).AddArgument($Name).AddArgument($Payload).AddArgument($Handler.ToString())

    # O hashtable local sobrevive mesmo depois que o job zera $sync.activeJob.
    $job = @{ jobId = $jobId; name = $Name; shell = $ps; handle = $null; iniciadoEm = (Get-Date) }
    $sync.activeJob = $job
    try {
        $job.handle = $ps.BeginInvoke()
    } catch {
        $sync.activeJob = $null
        $ps.Dispose()
        throw
    }

    Write-TmxLog -Level INFO -Message 'Job iniciado' -Data @{ jobId = $jobId; nome = $Name }
    $jobId
}

function Wait-TmxRemainingWork {
    <#
    .SYNOPSIS
        Espera o trabalho ativo terminar (a janela pode ter fechado por cima dele).
    .OUTPUTS
        $true se nada ficou pendente.
    #>
    [CmdletBinding()]
    param([int] $TimeoutSeconds = 600)

    if ($null -eq $sync) { return $true }
    $limite = (Get-Date).AddSeconds($TimeoutSeconds)

    while ($null -ne $sync.activeJob -and (Get-Date) -lt $limite) {
        Start-Sleep -Milliseconds 200
    }

    $pendente = ($null -ne $sync.activeJob)
    if ($pendente) {
        Write-TmxLog -Level WARN -Message 'Trabalho ainda ativo apos o tempo limite de espera' -Data @{ jobId = $sync.activeJob.jobId }
    }
    -not $pendente
}

function Close-TmxRunspacePool {
    <#
    .SYNOPSIS
        Fecha e descarta o pool de jobs. Nunca lanca.
    #>
    [CmdletBinding()]
    param()

    if ($null -eq $sync) { return }
    $pool = $sync.runspacePool
    if ($null -eq $pool) { return }

    try { $pool.Close() }   catch { Write-Verbose "Pool nao fechou limpo: $($_.Exception.Message)" }
    try { $pool.Dispose() } catch { Write-Verbose "Pool nao descartou limpo: $($_.Exception.Message)" }
    $sync.Remove('runspacePool')
}
