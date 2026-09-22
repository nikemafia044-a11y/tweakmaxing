<#
.SYNOPSIS
    Teste de GUI do fluxo de sessao: abrir a sessao e ver o ponto na barra de status.
.DESCRIPTION
    Nao e Pester. Sobe a Start-TmxDev.ps1 com -TestMode -DebugPort, conecta o
    agent-browser e exercita a Task 9 pela janela real:
      1. a barra comeca sem ponto de restauracao;
      2. o botao de desenvolvimento #st-session-start (so no modo de teste)
         abre o modal "Ponto de restauracao";
      3. "Criar ponto e continuar" dispara session.start e a barra passa a
         mostrar "Ponto #999" (no modo de teste o Checkpoint-Computer NAO e
         chamado) e o id da execucao.

    Deixa um print em tests/gui/out/sessao.png. Sai com 1 se algo falhar, e
    sempre fecha a GUI.
.EXAMPLE
    .\tests\gui\Test-Session.ps1
#>
[CmdletBinding()]
param(
    [int] $Port = 9336
)

. (Join-Path $PSScriptRoot '_GuiHelpers.ps1')

$script:Falhas = 0

function Assert-Tmx {
    param(
        [Parameter(Mandatory)] [string] $Nome,
        [Parameter(Mandatory)] [bool]   $Condicao,
        [string] $Detalhe
    )
    if ($Condicao) {
        Write-Host "PASS  $Nome" -ForegroundColor Green
    } else {
        $script:Falhas++
        Write-Host "FAIL  $Nome" -ForegroundColor Red
        if ($Detalhe) { Write-Host "      $Detalhe" -ForegroundColor DarkYellow }
    }
}

function Wait-TmxGuiLivre {
    <#
    .SYNOPSIS
        Espera outra GUI de teste (de outra suite rodando em paralelo) terminar.
    .DESCRIPTION
        O Start-TmxGui derruba o PID anterior e todo msedgewebview2 apontado
        para a pasta de teste - isso mataria a GUI de outro teste em andamento.
    #>
    param([int] $TimeoutSeconds = 180)

    $arquivo = Join-Path (Initialize-TmxGuiOut) 'gui.pid'
    $limite  = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $limite) {
        if (-not (Test-Path -LiteralPath $arquivo)) { return $true }

        $pidAnterior = 0
        $texto = ''
        try { $texto = (Get-Content -LiteralPath $arquivo -Raw -ErrorAction Stop).Trim() } catch { }
        [int]::TryParse($texto, [ref]$pidAnterior) | Out-Null
        if ($pidAnterior -le 0) { return $true }
        if (-not (Get-Process -Id $pidAnterior -ErrorAction SilentlyContinue)) { return $true }

        Write-Host "Ha outra GUI de teste viva (PID $pidAnterior); aguardando..." -ForegroundColor DarkYellow
        Start-Sleep -Seconds 5
    }
    Write-Host 'A GUI anterior nao encerrou no tempo limite; seguindo mesmo assim.' -ForegroundColor DarkYellow
    $false
}

function Wait-TmxModalFechado {
    <#
    .SYNOPSIS
        Espera o modal sumir (o fluxo so o fecha quando o job.done chega).
    #>
    param([int] $TimeoutSeconds = 20)

    $limite = (Get-Date).AddSeconds($TimeoutSeconds)
    $visivel = 'true'
    while ((Get-Date) -lt $limite) {
        try { $visivel = Invoke-AB 'is' 'visible' '#modal' } catch { $visivel = 'true' }
        if ("$visivel" -notmatch 'true|visible|yes') { return $true }
        Start-Sleep -Milliseconds 500
    }
    $false
}

function Wait-TmxTexto {
    <#
    .SYNOPSIS
        Espera o texto de um seletor casar com um curinga. Devolve o ultimo lido.
    #>
    param(
        [Parameter(Mandatory)] [string] $Seletor,
        [Parameter(Mandatory)] [string] $Curinga,
        [int] $TimeoutSeconds = 20
    )
    $limite = (Get-Date).AddSeconds($TimeoutSeconds)
    $texto  = ''
    while ((Get-Date) -lt $limite) {
        try { $texto = Invoke-AB 'get' 'text' $Seletor } catch { $texto = '' }
        if ($texto -like $Curinga) { return $texto }
        Start-Sleep -Milliseconds 500
    }
    $texto
}

Wait-TmxGuiLivre | Out-Null

$gui = $null
try {
    Write-Host "Abrindo a GUI em modo de teste (CDP $Port)..." -ForegroundColor Cyan
    $gui = Start-TmxGui -Port $Port -TestMode
    Write-Host "CDP: $($gui.versaoCdp.Browser)"

    $pagina = Wait-TmxGuiPage -Port $Port
    Write-Host "Pagina: $($pagina.url)"

    Invoke-AB 'connect' "$Port" | Out-Null
    Invoke-AB 'wait' '#st-rp' | Out-Null

    $rp = Invoke-AB 'get' 'text' '#st-rp'
    Assert-Tmx -Nome 'a barra comeca sem ponto de restauracao' -Condicao ($rp -like '*Nenhum ponto*') -Detalhe "obtido: '$rp'"

    $run = Invoke-AB 'get' 'text' '#st-run'
    Assert-Tmx -Nome 'a barra comeca sem sessao' -Condicao ($run -like '*Sem sess*') -Detalhe "obtido: '$run'"

    # O botao so existe depois que shell.version responde testMode=true.
    Invoke-AB 'wait' '#st-session-start' | Out-Null
    $rotulo = Invoke-AB 'get' 'text' '#st-session-start'
    Assert-Tmx -Nome 'botao de desenvolvimento presente no modo de teste' -Condicao ($rotulo -like '*Iniciar sess*') -Detalhe "obtido: '$rotulo'"

    Invoke-AB 'click' '#st-session-start' | Out-Null
    Invoke-AB 'wait' '#modal-buttons .btn-primary' | Out-Null

    $visivel = Invoke-AB 'is' 'visible' '#modal'
    Assert-Tmx -Nome 'modal do ponto de restauracao abre' -Condicao ("$visivel" -match 'true|visible|yes') -Detalhe "obtido: '$visivel'"

    $titulo = Invoke-AB 'get' 'text' '#modal-title'
    Assert-Tmx -Nome 'modal se chama Ponto de restauracao' -Condicao ($titulo -like '*Ponto de restaura*') -Detalhe "obtido: '$titulo'"

    $botao = Invoke-AB 'get' 'text' '#modal-buttons .btn-primary'
    Assert-Tmx -Nome 'modal oferece Criar ponto e continuar' -Condicao ($botao -like '*Criar ponto e continuar*') -Detalhe "obtido: '$botao'"

    Invoke-AB 'click' '#modal-buttons .btn-primary' | Out-Null

    $rp2 = Wait-TmxTexto -Seletor '#st-rp' -Curinga '*Ponto #999*' -TimeoutSeconds 20
    Assert-Tmx -Nome 'a barra passa a mostrar Ponto #999 criado' -Condicao ($rp2 -like '*Ponto #999*') -Detalhe "obtido: '$rp2'"

    $run2 = Wait-TmxTexto -Seletor '#st-run' -Curinga '*-*' -TimeoutSeconds 10
    Assert-Tmx -Nome 'a barra mostra o id da execucao' -Condicao ($run2 -match '^\d{8}-\d{6}-[0-9a-f]+$') -Detalhe "obtido: '$run2'"

    $undo = Invoke-AB 'get' 'text' '#st-undo-texto'
    Assert-Tmx -Nome 'a barra mostra o comando de reversao' -Condicao ($undo -like '*-Headless -Undo*') -Detalhe "obtido: '$undo'"

    # O modal so fecha quando o job.done chega - esperar aqui tambem deixa o
    # print deterministico (senao ele pega o instante anterior ao job.done).
    Assert-Tmx -Nome 'modal fecha sozinho quando a sessao fica pronta' -Condicao (Wait-TmxModalFechado -TimeoutSeconds 20)

    $print = Join-Path (Initialize-TmxGuiOut) 'sessao.png'
    Invoke-AB 'screenshot' $print | Out-Null
    Assert-Tmx -Nome 'screenshot gravado' -Condicao (Test-Path -LiteralPath $print) -Detalhe $print
    Write-Host "Print: $print"

} catch {
    $script:Falhas++
    Write-Host "FAIL  execucao: $($_.Exception.Message)" -ForegroundColor Red
} finally {
    Write-Host 'Fechando a GUI...' -ForegroundColor Cyan
    $limpo = Stop-TmxGui -Port $Port
    Assert-Tmx -Nome 'porta CDP liberada no fim' -Condicao ([bool]$limpo)
}

Write-Host ''
if ($script:Falhas -gt 0) {
    Write-Host "RESULTADO: $script:Falhas verificacao(oes) falharam." -ForegroundColor Red
    exit 1
}
Write-Host 'RESULTADO: todas as verificacoes passaram.' -ForegroundColor Green
exit 0
