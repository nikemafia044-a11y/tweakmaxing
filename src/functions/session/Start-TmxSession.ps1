# functions/session/Start-TmxSession.ps1
# A sessao de trabalho: pasta da execucao (state.json) + ponto de restauracao.
#
# Nada e aplicado no sistema antes desta funcao dizer ok. Ela e o unico ponto
# onde a promessa de reversibilidade e cobrada:
#   1. guardas (elevacao, build, disco, reboot pendente);
#   2. New-TmxRun  -> pasta da execucao e state.json;
#   3. ponto de restauracao OBRIGATORIO (ou pulado com a frase exata digitada).
#
# IMPORTANTE (GUI): o estado mutavel do Core ($script:TmxRun,
# $script:TmxStateRecords, $script:TmxLog) vive na runspace onde New-TmxRun
# rodou. O pool de jobs tem UMA runspace justamente para esse estado sobreviver
# de um job para o seguinte, portanto TODO trabalho de sessao tem que rodar
# dentro de um job. A thread da janela nunca le $script:Tmx*: ela le
# $sync.session, que e publicado aqui e viaja pelo evento 'session.changed'.
#
# No modo headless nao existe pool: a funcao tambem roda em processo, na
# thread principal, e funciona igual.

function Register-TmxSessionHkuDrive {
    <#
    .SYNOPSIS
        Garante o PSDrive HKU: nesta runspace (o catalogo tem acao em HKU:\.Default).
    .DESCRIPTION
        Um PSDrive vale so para a runspace onde foi criado: o start.ps1 registra
        o dele na thread principal, e a runspace do pool comeca sem nenhum.
    #>
    [CmdletBinding()]
    param()

    if (Get-PSDrive -Name HKU -ErrorAction SilentlyContinue) { return $false }
    try {
        New-PSDrive -PSProvider Registry -Name HKU -Root HKEY_USERS -Scope Global -ErrorAction Stop | Out-Null
        Write-TmxLog -Level INFO -Message 'PSDrive HKU registrado nesta runspace'
        $true
    } catch {
        Write-TmxLog -Level WARN -Message "Nao foi possivel registrar o PSDrive HKU: $($_.Exception.Message)"
        $false
    }
}

function New-TmxSessionSnapshot {
    <#
    .SYNOPSIS
        Copia independente da sessao, pronta para ser publicada ou enviada.
    .DESCRIPTION
        O que vai para $sync.session e para o payload do 'session.changed' nao
        pode ser a MESMA referencia que continua sendo trabalhada: quem leu
        (a thread da janela, um teste, o log) veria campos mudando debaixo de si.
    #>
    [CmdletBinding()]
    param($Session)

    if ($null -eq $Session) { return $null }

    $rp = @{ estado = 'nenhum'; seq = $null; mensagem = $null }
    if ($Session.restorePoint) {
        if ($Session.restorePoint.estado) { $rp.estado = "$($Session.restorePoint.estado)" }
        $rp.seq = $Session.restorePoint.seq
        if ($Session.restorePoint.mensagem) { $rp.mensagem = "$($Session.restorePoint.mensagem)" }
    }

    @{
        runId        = $Session.runId
        runPath      = $Session.runPath
        statePath    = $Session.statePath
        restorePoint = $rp
        pronto       = [bool]$Session.pronto
        undoCommand  = $Session.undoCommand
        criadoEm     = $Session.criadoEm
    }
}

function Publish-TmxSession {
    <#
    .SYNOPSIS
        Publica UMA transicao da sessao: snapshot novo, uma unica atribuicao em
        $sync.session e o evento para a UI.
    .DESCRIPTION
        Atomico do ponto de vista de quem le: a thread da janela sempre enxerga
        um objeto completo que nunca mais muda. Mutar campo a campo o objeto ja
        publicado abriria a janela em que a UI le pronto=$true com undoCommand
        ainda $null (ou o estado novo com o seq antigo).
    .OUTPUTS
        O snapshot publicado.
    #>
    [CmdletBinding()]
    param($Session)

    $instantaneo = New-TmxSessionSnapshot -Session $Session
    $sync.session = $instantaneo
    Send-TmxUiEvent -Event 'session.changed' -Payload $instantaneo
    $instantaneo
}

function Get-TmxSimulatedRestorePointStage {
    <#
    .SYNOPSIS
        Resultado simulado da etapa do ponto de restauracao (SO no modo de teste).
    .DESCRIPTION
        Existe porque um Mock de Invoke-TmxRestorePointStage nao atravessa
        runspaces: o job roda noutra, onde mock nenhum foi instalado. A
        simulacao precisa morar no codigo de producao - e por isso quem a
        destranca e $sync.testMode em Start-TmxSession, nunca uma flag sozinha.

        $sync.simulateRestorePointFailure (uma vez so) faz a proxima criacao
        falhar, para a suite de GUI exercitar o caminho erro -> pular com a frase.
    #>
    [CmdletBinding()]
    param([switch] $Pular)

    if ($Pular) {
        return [pscustomobject]@{
            proceed   = $true
            exitCode  = 0
            mensagem  = 'Modo de teste: ponto de restauracao pulado.'
            pulado    = $true
            resultado = $null
        }
    }

    $falharAgora = $false
    if ($sync.ContainsKey('simulateRestorePointFailure')) {
        $falharAgora = [bool]$sync.simulateRestorePointFailure
    }
    if ($falharAgora) {
        $sync.simulateRestorePointFailure = $false
        return [pscustomobject]@{
            proceed   = $false
            exitCode  = 2
            mensagem  = 'Modo de teste: falha simulada do ponto de restauracao.'
            pulado    = $false
            resultado = $null
        }
    }

    [pscustomobject]@{
        proceed   = $true
        exitCode  = 0
        mensagem  = 'Modo de teste: ponto de restauracao simulado (#999).'
        pulado    = $false
        resultado = [pscustomobject]@{ ok = $true; sequenceNumber = 999; descricao = 'TweakMaxing (teste)' }
    }
}

function Start-TmxSession {
    <#
    .SYNOPSIS
        Abre a sessao de trabalho: guardas, pasta da execucao e ponto de restauracao.
    .DESCRIPTION
        Idempotente: com a sessao ja pronta ($sync.session.pronto) nao cria
        run nem ponto novo - devolve a que existe.

        Publica $sync.session e emite 'session.changed' pelo menos duas vezes
        (ao criar o run e ao fechar o ponto de restauracao), para a barra de
        status acompanhar sem perguntar. Cada publicacao e um objeto novo e
        completo (ver Publish-TmxSession).
    .PARAMETER SkipConfirmado
        O usuario ja digitou a frase exata (a ponte valida antes de chamar):
        o ponto de restauracao e PULADO.
    .PARAMETER DryRun
        Simulacao: nenhum ponto e criado, a sessao fica pronta mesmo assim.
    .OUTPUTS
        [pscustomobject] @{ ok; mensagem; session }
    #>
    [CmdletBinding()]
    param(
        [switch] $SkipConfirmado,
        [switch] $DryRun
    )

    if ($null -eq $sync) { throw 'Start-TmxSession: $sync nao existe (bootstrap nao rodou).' }

    # --- 0. Ja pronta? -----------------------------------------------------
    $atual = $sync.session
    if ($atual -and $atual.runId -and $atual.pronto -eq $true) {
        return [pscustomobject]@{
            ok       = $true
            mensagem = "Sessao $($atual.runId) ja estava aberta."
            session  = $atual
        }
    }

    Register-TmxSessionHkuDrive | Out-Null

    $testMode = [bool]$sync.testMode

    # --- 1. Guardas --------------------------------------------------------
    # Sem elevacao nada disso se aplica de verdade; so o modo de teste passa.
    $guardas = Assert-TmxGuards -AllowUnelevated:$testMode
    if (-not $guardas.ok) {
        $motivo = (@($guardas.bloqueios) -join ' ')
        Write-TmxLog -Level ERROR -Message 'Sessao bloqueada pelas guardas' -Data @{ bloqueios = $guardas.bloqueios }
        return [pscustomobject]@{ ok = $false; mensagem = $motivo; session = $sync.session }
    }

    # --- 2. Pasta da execucao ----------------------------------------------
    $run = New-TmxRun

    # Copia de trabalho. O que esta em $sync.session so muda por
    # Publish-TmxSession: inteiro, uma transicao por vez.
    $sessao = @{
        runId        = "$($run.RunId)"
        runPath      = "$($run.RunPath)"
        statePath    = "$($run.StatePath)"
        restorePoint = @{ estado = 'criando'; seq = $null; mensagem = $null }
        pronto       = $false
        undoCommand  = $null
        criadoEm     = (Get-Date).ToString('o')
    }
    Publish-TmxSession -Session $sessao | Out-Null

    # --- 3. Ponto de restauracao -------------------------------------------
    # A simulacao SO existe dentro do modo de teste. $sync.restorePointMock nao
    # e uma chave de fabrica: fora do -TestMode ela e ignorada e o ponto real e
    # sempre criado.
    $usarMock = $testMode
    if ($testMode -and $sync.ContainsKey('restorePointMock') -and $null -ne $sync.restorePointMock) {
        $usarMock = [bool]$sync.restorePointMock
    }

    if ($usarMock) {
        $etapa = Get-TmxSimulatedRestorePointStage -Pular:($SkipConfirmado -or $DryRun)
        Write-TmxLog -Level WARN -Message 'Modo de teste: Checkpoint-Computer NAO foi chamado' -Data @{
            pulado  = $etapa.pulado
            proceed = $etapa.proceed
        }
    } else {
        # A frase de confirmacao ja foi conferida pela ponte (ou pelo dialogo
        # WPF no headless), por isso o -ConfirmSkip aqui so confirma.
        $etapa = Invoke-TmxRestorePointStage `
                    -SkipRestorePoint:$SkipConfirmado `
                    -IUnderstandTheRisk:$SkipConfirmado `
                    -DryRun:$DryRun `
                    -ConfirmSkip { $true }
    }

    if (-not $etapa.proceed) {
        $sessao.restorePoint.estado   = 'falhou'
        $sessao.restorePoint.mensagem = "$($etapa.mensagem)"
        $sessao.pronto                = $false
        $publicada = Publish-TmxSession -Session $sessao
        Write-TmxLog -Level ERROR -Message 'Sessao abortada: ponto de restauracao falhou' -Data @{ mensagem = "$($etapa.mensagem)" }
        return [pscustomobject]@{ ok = $false; mensagem = "$($etapa.mensagem)"; session = $publicada }
    }

    if ($etapa.pulado) {
        $sessao.restorePoint.estado   = 'pulado'
        $sessao.restorePoint.mensagem = "$($etapa.mensagem)"
    } else {
        $sessao.restorePoint.estado   = 'criado'
        $sessao.restorePoint.mensagem = "$($etapa.mensagem)"
        if ($etapa.resultado) { $sessao.restorePoint.seq = $etapa.resultado.sequenceNumber }
    }

    # pronto e undoCommand entram na MESMA publicacao que o estado final do
    # ponto: a UI nunca ve uma sessao pronta sem o comando de reversao.
    $sessao.pronto      = $true
    $sessao.undoCommand = "TweakMaxing.ps1 -Headless -Undo $($sessao.runId)"
    $publicada = Publish-TmxSession -Session $sessao

    Write-TmxLog -Level INFO -Message 'Sessao pronta' -Data @{
        runId        = $publicada.runId
        restorePoint = $publicada.restorePoint.estado
        seq          = $publicada.restorePoint.seq
    }

    [pscustomobject]@{ ok = $true; mensagem = "$($etapa.mensagem)"; session = $publicada }
}
