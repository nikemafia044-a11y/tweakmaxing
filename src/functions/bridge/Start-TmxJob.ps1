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
        Leva tres coisas para cada runspace nova:
          1. $sync (a mesma referencia - e por onde as threads conversam);
          2. toda funcao do TweakMaxing ja definida nesta sessao (nome com
             '-Tmx' ou 'TweakMaxing');
          3. uma COPIA das variaveis de escopo de script chamadas Tmx* .

        O item 3 existe porque uma runspace nova so recebe funcoes: sem ele,
        $script:TmxConditionRegex, $script:TmxThrottleKeyPath, $script:TmxSkipPhrase
        e companhia chegam $null e a funcao falha de um jeito dificil de ler
        (o sintoma classico foi "Operador '' exige um valor").

        Sao copias por valor, feitas uma unica vez: servem para as CONSTANTES.
        O estado mutavel de execucao ($script:TmxRun, $script:TmxStateRecords,
        $script:TmxLog) comeca $null aqui e passa a viver dentro da runspace do
        pool - que e uma so, justamente para esse estado sobreviver de um job
        para o seguinte. Quem precisa ver estado de sessao da thread da UI le
        $sync.session, nunca $script:Tmx*.

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

    $constantes = @()
    try {
        $constantes = @(Get-Variable -Scope Script -Name 'Tmx*' -ErrorAction SilentlyContinue)
    } catch {
        Write-Verbose "Nenhum escopo de script com variaveis Tmx*: $($_.Exception.Message)"
    }
    foreach ($v in $constantes) {
        if ($v.Name -eq 'sync') { continue }
        $iss.Variables.Add(
            (New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry -ArgumentList $v.Name, $v.Value, $null)
        )
    }

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

    # Exatamente UMA runspace (1,1), reaproveitada por todos os jobs. Nao e por
    # economia: o estado de execucao que um job cria ($script:TmxRun,
    # $script:TmxStateRecords) mora na runspace, e o job seguinte - o Undo, por
    # exemplo - precisa enxergar o mesmo run. Com duas runspaces isso viraria
    # loteria. Serializar os trabalhos ja e a regra da ponte (um por vez).
    $pool = [runspacefactory]::CreateRunspacePool(1, 1, (New-TmxSessionState), $Host)
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
