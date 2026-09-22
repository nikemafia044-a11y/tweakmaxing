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
        Copia rasa da sessao para viajar num evento.
    .DESCRIPTION
        O payload do 'session.changed' nao pode ser a MESMA referencia que
        continua sendo mutada depois: quem guardou o evento (testes, log,
        fila da UI) veria o estado final, nao o do instante do envio.
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

function Start-TmxSession {
    <#
    .SYNOPSIS
        Abre a sessao de trabalho: guardas, pasta da execucao e ponto de restauracao.
    .DESCRIPTION
        Idempotente: com a sessao ja pronta ($sync.session.pronto) nao cria
        run nem ponto novo - devolve a que existe.

        Publica $sync.session e emite 'session.changed' pelo menos duas vezes
        (ao criar o run e ao fechar o ponto de restauracao), para a barra de
        status acompanhar sem perguntar.
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

    $sessao = @{
        runId        = "$($run.RunId)"
        runPath      = "$($run.RunPath)"
        statePath    = "$($run.StatePath)"
        restorePoint = @{ estado = 'criando'; seq = $null; mensagem = $null }
        pronto       = $false
        undoCommand  = $null
        criadoEm     = (Get-Date).ToString('o')
    }
    $sync.session = $sessao
    Send-TmxUiEvent -Event 'session.changed' -Payload (New-TmxSessionSnapshot -Session $sessao)

    # --- 3. Ponto de restauracao -------------------------------------------
    # No modo de teste o Checkpoint-Computer NAO e chamado: um mock de
    # Invoke-TmxRestorePointStage nao atravessa runspaces (o job roda noutra),
    # entao a simulacao mora aqui, controlada por $sync.restorePointMock.
    $usarMock = $testMode
    if ($sync.ContainsKey('restorePointMock') -and $null -ne $sync.restorePointMock) {
        $usarMock = [bool]$sync.restorePointMock
    }

    if ($usarMock) {
        if ($SkipConfirmado -or $DryRun) {
            $etapa = [pscustomobject]@{
                proceed   = $true
                exitCode  = 0
                mensagem  = 'Modo de teste: ponto de restauracao pulado.'
                pulado    = $true
                resultado = $null
            }
        } else {
            $etapa = [pscustomobject]@{
                proceed   = $true
                exitCode  = 0
                mensagem  = 'Modo de teste: ponto de restauracao simulado (#999).'
                pulado    = $false
                resultado = [pscustomobject]@{ ok = $true; sequenceNumber = 999; descricao = 'TweakMaxing (teste)' }
            }
        }
        Write-TmxLog -Level WARN -Message 'Modo de teste: Checkpoint-Computer NAO foi chamado' -Data @{ pulado = $etapa.pulado; seq = 999 }
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
        $sessao.pronto = $false
        $sync.session  = $sessao
        Send-TmxUiEvent -Event 'session.changed' -Payload (New-TmxSessionSnapshot -Session $sessao)
        Write-TmxLog -Level ERROR -Message 'Sessao abortada: ponto de restauracao falhou' -Data @{ mensagem = "$($etapa.mensagem)" }
        return [pscustomobject]@{ ok = $false; mensagem = "$($etapa.mensagem)"; session = $sessao }
    }

    if ($etapa.pulado) {
        $sessao.restorePoint.estado   = 'pulado'
        $sessao.restorePoint.mensagem = "$($etapa.mensagem)"
    } else {
        $sessao.restorePoint.estado   = 'criado'
        $sessao.restorePoint.mensagem = "$($etapa.mensagem)"
        if ($etapa.resultado) { $sessao.restorePoint.seq = $etapa.resultado.sequenceNumber }
    }

    $sessao.pronto      = $true
    $sessao.undoCommand = "TweakMaxing.ps1 -Headless -Undo $($sessao.runId)"
    $sync.session       = $sessao
    Send-TmxUiEvent -Event 'session.changed' -Payload (New-TmxSessionSnapshot -Session $sessao)

    Write-TmxLog -Level INFO -Message 'Sessao pronta' -Data @{
        runId        = $sessao.runId
        restorePoint = $sessao.restorePoint.estado
        seq          = $sessao.restorePoint.seq
    }

    [pscustomobject]@{ ok = $true; mensagem = "$($etapa.mensagem)"; session = $sessao }
}
