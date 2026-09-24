# functions/bridge/Start-TmxJob.ps1
# Pool de runspaces + um trabalho de cada vez.
#
# A janela nunca pode bloquear: toda acao longa vai para o pool e conversa com
# a UI por eventos (job.started / job.progress / job.done). Um trabalho por vez
# e deliberado - aplicar tweaks, instalar apps e reverter nao podem se cruzar.

# Nomes de $script:Tmx* que PODEM atravessar para uma runspace nova.
#
# Lista de PERMISSAO, nao de bloqueio: copiar "tudo que comeca com Tmx"
# arrastava junto o estado mutavel de execucao ($script:TmxRun,
# $script:TmxStateRecords, $script:TmxLog, os *BackupFeito) da thread que
# montou o InitialSessionState. Uma runspace que nasce com um $TmxRun
# congelado acha que tem execucao ativa quando nao tem, e grava registros de
# reversao num state.json que ela nunca mais persiste - exatamente o oposto
# da guarda de Core/Backup.ps1 (Assert-TmxRunAtivo).
#
# Criterio de entrada: a variavel e atribuida UMA vez, no dot-source do
# arquivo que a declara, e nunca dentro de uma funcao. Para conferir:
#   grep -rn '\$script:Tmx\w*\s*=' src --include=*.ps1
# (\w, nao [A-Za-z]: ha nomes com digito, como TmxDnsFamiliaV4) e comparar
# com esta lista; o que aparecer atribuido DENTRO de funcao fica de fora
# (ver $script:TmxMutaveisConhecidas logo abaixo). O teste
# 'toda variavel de script Tmx* esta classificada' (tests/Bridge.Tests.ps1)
# quebra se alguem criar uma variavel nova sem passar por aqui.
$script:TmxConstantesRunspace = @(
    # As duas listas desta secao: sem elas, uma runspace que precisasse
    # remontar a ISS (cache de $sync.SessionState vazio) leria uma lista de
    # permissao $null e nao copiaria constante nenhuma.
    'TmxConstantesRunspace', 'TmxMutaveisConhecidas'
    # Core
    'TmxSemRunMsg'
    'TmxThrottleKeyPath', 'TmxThrottleValueName', 'TmxSkipPhrase'
    # Engine
    'TmxTiers', 'TmxRiscos', 'TmxPresets', 'TmxControles', 'TmxReversiveis', 'TmxAcaoTipos'
    'TmxConditionRegex', 'TmxPresetNomes'
    'TmxModos', 'TmxModosPreset', 'TmxCategoriasV2', 'TmxModoOrdem'
    # Ponte
    'TmxTweakTestJson'
    # Recursos / correcoes
    'TmxDnsBenchAmostras', 'TmxDnsBenchNome'
    'TmxFixUpdateServicos', 'TmxFixUpdateDlls', 'TmxFixUpdateWsusValores'
    'TmxFeatureTestePath', 'TmxFeatureBcdOpcao', 'TmxFeatureFuncoes', 'TmxFeatureNomeRegex'
    'TmxRegBackupTarefa', 'TmxRegBackupChave', 'TmxRegBackupMarcador'
    'TmxPanelCatalogo'
    # Tweaks
    'TmxAdobeHostsUrl', 'TmxDnsConfigPath', 'TmxDnsFamiliaV4', 'TmxDnsFamiliaV6'
    'TmxIpv6Component'
    'TmxBagsPath', 'TmxBagMRUPath', 'TmxAllFolders'
    'TmxHibernatePath', 'TmxNativeSource', 'TmxOosuUrl'
    'TmxRightClickClsid', 'TmxRightClickInproc'
    'TmxSvcHostPath', 'TmxSvcHostName'
    'TmxSiufPath', 'TmxSiufName'
    'TmxUltimateSourceGuid', 'TmxUltimateRegex'
    'TmxWidgetPacotes', 'TmxWidgetStoreId'
    'TmxAiPacotes', 'TmxAiServico', 'TmxAiRecurso'
    'TmxEnumRootPadrao'
    # Tweaks v2
    'TmxDirectXRealPath', 'TmxDirectXTestPath', 'TmxDirectXValueName'
    'TmxGamingAppxPacotes', 'TmxGamingAppxGamePassKeep', 'TmxGamingAppxStoreIds'
    # Windows Update
    'TmxUpdateTestRoot'
    'TmxUpdatePolicySubPath', 'TmxUpdateAuSubPath', 'TmxUpdateDriverSubPath'
    'TmxUpdateMetadataSubPath', 'TmxUpdatePauseSubPath'
    'TmxUpdatePolicyValueNames', 'TmxUpdateAuValueNames', 'TmxUpdateDriverValueNames'
    'TmxUpdateMetadataValueNames', 'TmxUpdatePauseValueNames', 'TmxUpdateServiceAlvos'
)

# Mutaveis conhecidas: ficam de fora de proposito. Estao nomeadas so para que
# New-TmxSessionState possa calar o aviso delas e reclamar apenas de uma
# variavel NOVA que ninguem classificou ainda.
#   TmxRun / TmxStateRecords  - execucao ativa (New-TmxRun)
#   TmxLog                    - logger da runspace (Initialize-TmxLogger)
#   Tmx*BackupFeito           - memoria de backup por execucao (Engine/Apply.ps1)
#   TmxEnumRoot               - redirecionavel por Set-TmxEnumRoot (hook de teste);
#                               na runspace vale o padrao de Get-TmxEnumRoot
$script:TmxMutaveisConhecidas = @(
    'TmxRun', 'TmxStateRecords', 'TmxLog',
    'TmxPowerBackupFeito', 'TmxNetBackupFeito', 'TmxBcdBackupFeito',
    'TmxEnumRoot'
)

function New-TmxSessionState {
    <#
    .SYNOPSIS
        InitialSessionState compartilhado pela runspace da UI e pelo pool.
    .DESCRIPTION
        Leva tres coisas para cada runspace nova:
          1. $sync (a mesma referencia - e por onde as threads conversam);
          2. toda funcao do TweakMaxing ja definida nesta sessao (nome com
             '-Tmx' ou 'TweakMaxing');
          3. uma COPIA das CONSTANTES de escopo de script listadas em
             $script:TmxConstantesRunspace - e so delas.

        O item 3 existe porque uma runspace nova so recebe funcoes: sem ele,
        $script:TmxConditionRegex, $script:TmxThrottleKeyPath, $script:TmxSkipPhrase
        e companhia chegam $null e a funcao falha de um jeito dificil de ler
        (o sintoma classico foi "Operador '' exige um valor").

        A lista e de PERMISSAO justamente porque o estado mutavel de execucao
        ($script:TmxRun, $script:TmxStateRecords, $script:TmxLog, os
        *BackupFeito, $script:TmxEnumRoot) NAO pode ser copiado: ele comeca
        zerado aqui e passa a viver dentro da runspace do pool - que e uma so,
        justamente para esse estado sobreviver de um job para o seguinte. Quem
        precisa ver estado de sessao da thread da UI le $sync.session, nunca
        $script:Tmx*.

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

    # Mesma preferencia da thread principal (scripts/start.ps1): uma runspace
    # nova nasceria com 'Continue' e engoliria erro nao-terminante no meio de
    # uma aplicacao de tweaks. Quem realmente garante isso sao as atribuicoes
    # explicitas no Invoke-TmxJobBody e no scriptblock da janela; esta entrada
    # e a rede de seguranca para qualquer scriptblock que rode fora dos dois.
    $iss.Variables.Add(
        (New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry `
            -ArgumentList 'ErrorActionPreference', 'Stop', 'Preferencia herdada da thread principal do TweakMaxing')
    )

    $permitidas = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($n in $script:TmxConstantesRunspace) { [void]$permitidas.Add($n) }
    $mutaveis = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($n in $script:TmxMutaveisConhecidas) { [void]$mutaveis.Add($n) }

    $candidatas = @()
    try {
        $candidatas = @(Get-Variable -Scope Script -Name 'Tmx*' -ErrorAction SilentlyContinue)
    } catch {
        Write-Verbose "Nenhum escopo de script com variaveis Tmx*: $($_.Exception.Message)"
    }
    foreach ($v in $candidatas) {
        if (-not $permitidas.Contains($v.Name)) {
            if (-not $mutaveis.Contains($v.Name)) {
                # Variavel nova que ninguem classificou: nao vai junto (o
                # seguro e o silencio), mas deixa rastro para quem a criou.
                Write-Verbose "Variavel de script '$($v.Name)' fora da lista de permissao: nao copiada para a runspace."
            }
            continue
        }
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

function Invoke-TmxJobBody {
    <#
    .SYNOPSIS
        Ciclo de vida de UM trabalho dentro da runspace do pool:
        job.started -> handler -> job.done, e $sync.activeJob zerado sempre.
    .DESCRIPTION
        job.started e emitido DENTRO do try/finally, nao antes dele. Se o
        envio do evento falhar (a janela morrendo no meio, um sink de teste
        que lanca), o finally ainda zera $sync.activeJob - senao a ponte
        recusaria todo trabalho seguinte com 'ja existe um trabalho em
        andamento' ate o processo reiniciar.

        Os dois Send-TmxUiEvent do caminho de erro sao best-effort pelo mesmo
        motivo: o que nao pode falhar e a limpeza.
    .NOTES
        Recebe o handler como TEXTO: scriptblock tem afinidade com a runspace
        onde nasceu e nao atravessa.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $JobId,
        [Parameter(Mandatory)] [string] $Name,
        $Payload,
        [Parameter(Mandatory)] [string] $HandlerText
    )

    # A runspace do pool nao herda o $ErrorActionPreference da thread principal
    # (o scripts/start.ps1 define 'Stop' la). Sem isto, um erro NAO-terminante
    # dentro do handler - um Get-Item num caminho que sumiu, um Remove-Item sem
    # permissao - seguiria adiante e o trabalho terminaria com ok=true, como se
    # tivesse dado certo. O escopo desta funcao cobre o handler inteiro.
    $ErrorActionPreference = 'Stop'

    try {
        Send-TmxUiEvent -Event 'job.started' -Payload @{ jobId = $JobId; name = $Name }
        $handler   = [scriptblock]::Create($HandlerText)
        $resultado = & $handler $Payload
        Send-TmxUiEvent -Event 'job.done' -Payload @{ jobId = $JobId; name = $Name; ok = $true; result = $resultado }
    } catch {
        $msg = $_.Exception.Message
        try {
            Send-TmxUiEvent -Event 'job.done' -Payload @{ jobId = $JobId; name = $Name; ok = $false; error = @{ message = $msg } }
        } catch {
            Write-Verbose "job.done nao pode ser enviado: $($_.Exception.Message)"
        }
    } finally {
        if ($null -ne $sync) { $sync.activeJob = $null }
    }
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
    # O corpo mora em Invoke-TmxJobBody (funcao normal, logo copiada para a
    # runspace como qualquer outra) para que o contrato "activeJob sempre
    # zerado" possa ser testado sem levantar um pool.
    $null = $ps.AddScript({
        param($jobId, $jobName, $jobPayload, $handlerText)
        Invoke-TmxJobBody -JobId $jobId -Name $jobName -Payload $jobPayload -HandlerText $handlerText
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
        Fecha e descarta o pool de jobs, com tempo limite. Nunca lanca.
    .DESCRIPTION
        RunspacePool.Close() e SINCRONO: com uma runspace ainda ocupada (um
        job que ignorou o timeout de Wait-TmxRemainingWork, um winget
        pendurado) ele espera para sempre e o processo nunca termina de
        fechar. Aqui usamos BeginClose + espera limitada: passado o prazo o
        pool e abandonado com um WARN no log e o processo segue.

        Nada de descartar o pool numa thread de fundo com scriptblock do
        PowerShell: e a mesma armadilha do Task.ContinueWith documentada em
        Start-TmxUserInterface.ps1. BeginClose e assincrono no proprio
        runtime, sem thread nossa.
    .PARAMETER TimeoutSeconds
        Quanto esperar o fechamento antes de abandonar o pool (padrao 10).
    #>
    [CmdletBinding()]
    param([int] $TimeoutSeconds = 10)

    if ($null -eq $sync) { return }
    $pool = $sync.runspacePool
    if ($null -eq $pool) { return }

    # Sai de $sync antes de qualquer espera: um Get-TmxRunspacePool depois
    # daqui tem que abrir um pool novo, nunca reusar este que esta morrendo.
    $sync.Remove('runspacePool')

    if ($null -ne $sync.activeJob) {
        Write-TmxLog -Level WARN -Message 'Pool sendo fechado com trabalho ainda ativo' -Data @{ jobId = "$($sync.activeJob.jobId)"; nome = "$($sync.activeJob.name)" }
    }

    $limite = [timespan]::FromSeconds([math]::Max(1, $TimeoutSeconds))
    try {
        $ar = $pool.BeginClose($null, $null)
        if ($ar.AsyncWaitHandle.WaitOne($limite)) {
            try { $pool.EndClose($ar) } catch { Write-Verbose "Pool nao fechou limpo: $($_.Exception.Message)" }
            try { $pool.Dispose() }     catch { Write-Verbose "Pool nao descartou limpo: $($_.Exception.Message)" }
        } else {
            # Abandonado de proposito: Dispose() aqui bloquearia igual.
            Write-TmxLog -Level WARN -Message "Pool de runspaces nao fechou em $($limite.TotalSeconds)s; seguindo sem esperar"
        }
    } catch {
        Write-TmxLog -Level WARN -Message "Falha ao fechar o pool de runspaces: $($_.Exception.Message)"
    }
}
