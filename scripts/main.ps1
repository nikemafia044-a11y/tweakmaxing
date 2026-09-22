<#
.SYNOPSIS
    Orquestrador: decide entre execucao sem janela (headless) e a interface.
.DESCRIPTION
    Roda depois de scripts/start.ps1 (que criou $global:sync) e com todas as
    funcoes do TweakMaxing ja definidas na sessao.

    Headless: -Undo ou -Preset, tudo no console, codigo de saida util em script.
    GUI: a janela vive numa runspace STA propria; esta thread so espera, coleta
    os erros dela e fecha o que ficou aberto. Modelado em
    reference/winutil/scripts/main.ps1, sem o que nao usamos.

    Codigos de saida: 0 sucesso, 1 falha, 2 abortado, 3 nao implementado ainda.
#>
param(
    [switch] $Headless,
    [ValidateSet('desktop', 'notebook', 'minimo', '')]
    [string] $Preset,
    [switch] $DryRun,
    [string] $Undo,
    [int]    $DebugPort,
    [switch] $TestMode,
    [switch] $NoElevate
)

if ($null -eq $global:sync) {
    # start.ps1 delegou a um processo elevado (ou recusou o host).
    return
}
$sync = $global:sync

function Complete-TmxRun {
    <#
    .SYNOPSIS
        Encerra transcript e devolve o codigo de saida.
    #>
    param([int] $Codigo)
    try { Stop-Transcript | Out-Null } catch { }
    $global:TmxExitCode = $Codigo
    $Codigo
}

# ===========================================================================
# Headless
# ===========================================================================
if ($Headless -or $Undo) {

    # --- Reverter -----------------------------------------------------------
    if ($Undo) {
        try {
            $resumo = if ($Undo -eq 'latest') { Undo-TweakMaxing -Latest } else { Undo-TweakMaxing -RunId $Undo }
            Write-Host ''
            Write-Host ("Reversao: {0} revertidos, {1} pulados, {2} falhas (de {3} registros)." -f `
                $resumo.revertidos, $resumo.pulados, $resumo.falhas, $resumo.total)
            exit (Complete-TmxRun ([int]($resumo.falhas -gt 0)))
        } catch {
            Write-Host "Nao foi possivel reverter: $($_.Exception.Message)" -ForegroundColor Red
            exit (Complete-TmxRun 1)
        }
    }

    # --- Preset -------------------------------------------------------------
    if (-not $Preset) {
        Write-Host 'Modo headless exige -Preset (desktop, notebook, minimo) ou -Undo.' -ForegroundColor Yellow
        exit (Complete-TmxRun 1)
    }

    $perfil = Get-TmxProfile

    # O catalogo pode ainda nao existir (tweaks*.json chegam em outra task):
    # a casca tem que abrir e simular mesmo assim.
    $catalogo = @()
    try {
        $catalogo = @(Get-TmxCatalog)
    } catch {
        Write-Warning "Catalogo indisponivel ($($_.Exception.Message)). Seguindo com catalogo vazio."
    }

    # --- Aplicacao real -----------------------------------------------------
    # Sem janela nao ha pool de jobs: a sessao e aberta nesta mesma thread, o
    # que faz o $script:TmxRun ficar visivel para o Engine logo abaixo.
    if (-not $DryRun) {
        $sessao = Start-TmxSession
        if (-not $sessao.ok) {
            Write-Host ''
            Write-Host "Abortado: $($sessao.mensagem)" -ForegroundColor Red
            Write-Host 'Nada foi alterado.' -ForegroundColor Red
            exit (Complete-TmxRun 2)
        }

        Write-Host ''
        Write-Host "Sessao $($sessao.session.runId): $($sessao.mensagem)"
        Write-Host "Para reverter: $($sessao.session.undoCommand)"

        if ($catalogo.Count -eq 0) {
            Write-Host 'Catalogo vazio: nenhum tweak para aplicar.' -ForegroundColor Yellow
            exit (Complete-TmxRun 1)
        }

        try {
            $plano    = Resolve-TmxPlan -Catalog $catalogo -Profile $perfil -Preset $Preset
            $execucao = Invoke-TmxPlan -Plan $plano -Profile $perfil
        } catch {
            Write-Host "Nao foi possivel aplicar o preset '$Preset': $($_.Exception.Message)" -ForegroundColor Red
            exit (Complete-TmxRun 1)
        }

        $aplicados = @($execucao.itens)
        Write-Host ''
        Write-Host "Preset '$Preset' aplicado:"
        if ($aplicados.Count -gt 0) {
            $aplicados |
                Select-Object @{ n = 'id'; e = { $_.id } },
                              @{ n = 'tier'; e = { $_.tier } },
                              @{ n = 'status'; e = { $_.status } },
                              @{ n = 'detalhe'; e = { $_.detalhe } } |
                Format-Table -AutoSize | Out-Host
        } else {
            Write-Host '  (nenhum tweak selecionado)'
        }

        Write-Host ("Resultado: {0} aplicados, {1} ja aplicados, {2} pulados, {3} falhas (de {4} itens)." -f `
            $execucao.aplicados, $execucao.jaAplicados, $execucao.pulados, $execucao.falhas, $aplicados.Count)
        if ($execucao.requerReboot) {
            Write-Host 'Reinicie o Windows para que tudo valha.' -ForegroundColor Yellow
        }
        Write-Host "Para reverter: $($sessao.session.undoCommand)"

        exit (Complete-TmxRun ([int]($execucao.falhas -gt 0)))
    }

    # A casca nao pode morrer por causa do catalogo: um tweaks.json quebrado
    # vira aviso visivel e simulacao de zero itens, nao um stack trace.
    $itens = @()
    if ($catalogo.Count -gt 0) {
        try {
            $plano = Resolve-TmxPlan -Catalog $catalogo -Profile $perfil -Preset $Preset
            $execucao = Invoke-TmxPlan -Plan $plano -Profile $perfil -WhatIf
            $itens = @($execucao.itens)
        } catch {
            Write-Warning "Nao foi possivel montar o plano: $($_.Exception.Message)"
        }
    }

    Write-Host ''
    Write-Host "Simulacao do preset '$Preset' (nada foi alterado):"
    if ($itens.Count -gt 0) {
        $itens |
            Select-Object @{ n = 'id'; e = { $_.id } },
                          @{ n = 'tier'; e = { $_.tier } },
                          @{ n = 'status'; e = { $_.status } },
                          @{ n = 'detalhe'; e = { $_.detalhe } } |
            Format-Table -AutoSize | Out-Host
    } else {
        Write-Host '  (nenhum tweak selecionado)'
    }
    Write-Host ("Simulacao concluida: {0} itens" -f $itens.Count)
    exit (Complete-TmxRun 0)
}

# ===========================================================================
# Interface
# ===========================================================================
# A janela nunca roda nesta thread: ShowDialog bloquearia o orquestrador e
# qualquer erro derrubaria o processo sem transcript. Ela ganha uma runspace
# STA (exigencia do WPF) montada a partir do mesmo InitialSessionState que o
# pool de jobs usa - por isso a janela e os jobs enxergam as mesmas funcoes.

$sessionState = New-TmxSessionState

$sync.UIRunspace = [runspacefactory]::CreateRunspace($Host, $sessionState)
$sync.UIRunspace.ApartmentState = 'STA'
$sync.UIRunspace.ThreadOptions  = 'ReuseThread'
$sync.UIRunspace.Open()

$uiShell = [powershell]::Create()
$uiShell.Runspace = $sync.UIRunspace
[void]$uiShell.AddScript({ Start-TmxUserInterface })

Write-TmxLog -Level INFO -Message 'Iniciando a thread da interface'
$uiHandle = $uiShell.BeginInvoke()

[void]$uiHandle.AsyncWaitHandle.WaitOne()

$uiFalhou = $false
try {
    $uiShell.EndInvoke($uiHandle) | Out-Null
} catch {
    $uiFalhou = $true
    Write-TmxLog -Level ERROR -Message "A thread da interface parou: $($_.Exception.Message)"
    Write-Host "A interface parou: $($_.Exception.Message)" -ForegroundColor Red
}

foreach ($aviso in $uiShell.Streams.Warning) {
    Write-TmxLog -Level WARN -Message "$($aviso.Message)"
}
foreach ($erro in $uiShell.Streams.Error) {
    $uiFalhou = $true
    Write-TmxLog -Level ERROR -Message "$($erro.Exception.Message)" -Data @{ origem = 'thread da interface' }
    Write-Host "Erro na interface: $($erro.Exception.Message)" -ForegroundColor Red
}

$uiShell.Dispose()
$sync.UIRunspace.Dispose()
$sync.Remove('UIRunspace')

# A janela pode ter fechado por cima de um trabalho que o usuario deixou terminar.
Wait-TmxRemainingWork | Out-Null
Close-TmxRunspacePool
[System.GC]::Collect()

exit (Complete-TmxRun ([int]$uiFalhou))
