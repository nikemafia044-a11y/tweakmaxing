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

      4. session.simulateFailure (so no modo de teste) arma UMA falha do ponto:
         o modal de erro aparece, "Prosseguir sem ponto" pede a frase exata,
         a frase errada vira toast e a certa abre a sessao com o ponto pulado.

    Deixa prints em tests/gui/out/sessao.png e sessao-pulado.png. Sai com 1 se algo falhar, e
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

function Invoke-TmxJsBridge {
    <#
    .SYNOPSIS
        Chama uma acao da ponte pela propria pagina e espera a resposta.
    .DESCRIPTION
        O agent-browser nao espera promessa: o resultado e guardado numa
        variavel global unica e lido por polling.
    .OUTPUTS
        O JSON da resposta (texto), ou '' se estourar o tempo.
    #>
    param(
        [Parameter(Mandatory)] [string] $Acao,
        [int] $TimeoutSeconds = 20
    )

    $marca = 'tmx_' + ([guid]::NewGuid().ToString('N'))
    $js = "window.$marca=null;window.tmx.bridge.call('$Acao').then(" +
          "function(r){window.$marca={ok:true,r:r};}," +
          "function(e){window.$marca={ok:false,e:String(e&&e.message)};});'disparado'"
    Invoke-AB 'eval' $js | Out-Null

    $limite = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $limite) {
        $resp = ''
        try { $resp = Invoke-AB 'eval' "JSON.stringify(window.$marca)" } catch { $resp = '' }
        if ($resp -and ($resp -notmatch '^"?null"?$')) { return $resp }
        Start-Sleep -Milliseconds 300
    }
    ''
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
    Close-TmxGuiWelcome

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

    # ------------------------------------------------------------------
    # Fluxo de erro -> prosseguir sem ponto -> frase exata
    # ------------------------------------------------------------------
    $reset = Invoke-TmxJsBridge -Acao 'session.reset'
    Assert-Tmx -Nome 'session.reset devolve ok no modo de teste' -Condicao ($reset -like '*true*') -Detalhe "obtido: '$reset'"

    $armado = Invoke-TmxJsBridge -Acao 'session.simulateFailure'
    Assert-Tmx -Nome 'session.simulateFailure arma a falha do ponto' -Condicao ($armado -like '*armado*') -Detalhe "obtido: '$armado'"

    $rpZerado = Wait-TmxTexto -Seletor '#st-rp' -Curinga '*Nenhum ponto*' -TimeoutSeconds 10
    Assert-Tmx -Nome 'a barra volta a dizer que nao ha ponto' -Condicao ($rpZerado -like '*Nenhum ponto*') -Detalhe "obtido: '$rpZerado'"

    Invoke-AB 'click' '#st-session-start' | Out-Null
    Invoke-AB 'wait' '#modal-buttons .btn-primary' | Out-Null
    Invoke-AB 'click' '#modal-buttons .btn-primary' | Out-Null

    $tituloErro = Wait-TmxTexto -Seletor '#modal-title' -Curinga '*falhou*' -TimeoutSeconds 25
    Assert-Tmx -Nome 'a falha do ponto abre o modal de erro' -Condicao ($tituloErro -like '*falhou*') -Detalhe "obtido: '$tituloErro'"

    $rpFalhou = Invoke-AB 'get' 'text' '#st-rp'
    Assert-Tmx -Nome 'a barra mostra a falha do ponto' -Condicao ($rpFalhou -like '*Falhou:*') -Detalhe "obtido: '$rpFalhou'"

    $prosseguir = Invoke-AB 'get' 'text' '#modal-buttons .btn-danger'
    Assert-Tmx -Nome 'o modal de erro oferece Prosseguir sem ponto' -Condicao ($prosseguir -like '*Prosseguir sem ponto*') -Detalhe "obtido: '$prosseguir'"

    Invoke-AB 'click' '#modal-buttons .btn-danger' | Out-Null
    Invoke-AB 'wait' '#modal-frase' | Out-Null

    $frase = Invoke-AB 'get' 'text' '.sessao-frase'
    Assert-Tmx -Nome 'o modal de pulo mostra a frase exigida' -Condicao ($frase -like '*SEM PONTO DE RESTAURACAO*') -Detalhe "obtido: '$frase'"

    # Frase errada: toast de erro e o modal continua de pe.
    Invoke-AB 'fill' '#modal-frase' 'sem ponto de restauracao' | Out-Null
    Invoke-AB 'click' '#modal-buttons .btn-danger' | Out-Null

    $toast = Wait-TmxTexto -Seletor '#toasts' -Curinga '*frase de confirmacao incorreta*' -TimeoutSeconds 15
    Assert-Tmx -Nome 'frase errada vira toast de erro' -Condicao ($toast -like '*frase de confirmacao incorreta*') -Detalhe "obtido: '$toast'"

    $aindaAberto = Invoke-AB 'is' 'visible' '#modal-frase'
    Assert-Tmx -Nome 'o modal da frase continua aberto apos errar' -Condicao ("$aindaAberto" -match 'true|visible|yes') -Detalhe "obtido: '$aindaAberto'"

    # Frase exata: a sessao abre com o ponto PULADO.
    Invoke-AB 'fill' '#modal-frase' "$frase" | Out-Null
    Invoke-AB 'click' '#modal-buttons .btn-danger' | Out-Null

    $rpPulado = Wait-TmxTexto -Seletor '#st-rp' -Curinga '*Ponto pulado*' -TimeoutSeconds 25
    Assert-Tmx -Nome 'a barra passa a mostrar Ponto pulado' -Condicao ($rpPulado -like '*Ponto pulado*') -Detalhe "obtido: '$rpPulado'"

    Assert-Tmx -Nome 'o modal da frase fecha quando a sessao abre' -Condicao (Wait-TmxModalFechado -TimeoutSeconds 20)

    $printPulado = Join-Path (Initialize-TmxGuiOut) 'sessao-pulado.png'
    Invoke-AB 'screenshot' $printPulado | Out-Null
    Assert-Tmx -Nome 'screenshot do pulo gravado' -Condicao (Test-Path -LiteralPath $printPulado) -Detalhe $printPulado
    Write-Host "Print: $printPulado"

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
