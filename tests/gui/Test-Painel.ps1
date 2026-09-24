<#
.SYNOPSIS
    Teste de fumaca da tela Painel (v2): abre a janela real e conversa por CDP.
.DESCRIPTION
    Nao e Pester. Sobe a GUI com -TestMode -DebugPort 9350 (porta reservada
    para esta tela) e confere: so o Painel aparece (nenhuma outra aba vaza),
    saudacao com o nome, os 4 cartoes de hardware preenchidos por system.info,
    o cartao do sistema operacional, 1 a 3 recomendacoes ja traduzidas (sem
    chave painel.rec.* crua) com o guia no modal, o anel de status
    (system.optimizationStatus), "Criar ponto agora" (restore.create simulado
    na home de teste), a troca de idioma e o chip de modo que abre
    Otimizacoes. Nada toca o sistema real.

    Deixa um print em tests/gui/out/painel.png. Sai com 1 se qualquer
    verificacao falhar. Sempre fecha a GUI.
.EXAMPLE
    .\tests\gui\Test-Painel.ps1
#>
[CmdletBinding()]
param(
    [int] $Port = 9350
)

. (Join-Path $PSScriptRoot '_GuiHelpers.ps1')

# Sessao isolada do agent-browser: com a sessao 'default' compartilhada, o
# 'close' de um teste de GUI de outra porta derrubava a conexao deste.
$env:AGENT_BROWSER_SESSION = "tmx-gui-$Port"

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

function ConvertTo-TmxInt {
    param([string] $Texto)
    $n = -1
    [int]::TryParse("$Texto".Trim(), [ref]$n) | Out-Null
    $n
}

function Get-TmxEval {
    param([Parameter(Mandatory)] [string] $Js)
    "$(Invoke-AB 'eval' $Js)".Trim().Trim('"')
}

function Wait-TmxEval {
    <#
    .SYNOPSIS
        Repete um eval ate $Ok aceitar o valor (ou estourar o prazo).
        Devolve o ultimo valor lido.
    #>
    param(
        [Parameter(Mandatory)] [string]      $Js,
        [Parameter(Mandatory)] [scriptblock] $Ok,
        [int] $TimeoutSeconds = 30
    )
    $limite = (Get-Date).AddSeconds($TimeoutSeconds)
    $v = ''
    while ((Get-Date) -lt $limite) {
        try { $v = Get-TmxEval $Js } catch { $v = '' }
        if (& $Ok $v) { return $v }
        Start-Sleep -Milliseconds 400
    }
    $v
}

function Wait-TmxOutroTestePid {
    <#
    .SYNOPSIS
        Espera ate 3 minutos se algum tests/gui/out/gui-*.pid de OUTRA porta
        apontar para um processo vivo (outro agente rodando o teste dele).
    #>
    param([int] $TimeoutSeconds = 180)

    $saida = Initialize-TmxGuiOut
    $meu   = Get-TmxGuiPidFile -Port $Port

    $limite = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $limite) {
        $vivos = @()
        foreach ($f in @(Get-ChildItem -LiteralPath $saida -Filter 'gui-*.pid' -File -ErrorAction SilentlyContinue)) {
            if ($f.FullName -ieq $meu) { continue }
            $anterior = 0
            [int]::TryParse((Get-Content -LiteralPath $f.FullName -Raw).Trim(), [ref]$anterior) | Out-Null
            if ($anterior -le 0) { continue }
            if (Get-Process -Id $anterior -ErrorAction SilentlyContinue) { $vivos += "$($f.Name)=$anterior" }
        }
        if ($vivos.Count -eq 0) { return }
        Write-Host "Outro teste de GUI ativo ($($vivos -join ', ')); esperando..." -ForegroundColor Cyan
        Start-Sleep -Seconds 3
    }
    Write-Host 'Tempo de espera esgotado; seguindo mesmo assim.' -ForegroundColor DarkYellow
}

Wait-TmxOutroTestePid

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
    Get-TmxEval "tmx.i18n.set('pt-BR'); 'ok'" | Out-Null

    Invoke-AB 'click' 'nav [data-tab=painel]' | Out-Null
    Invoke-AB 'wait' '#pn-hw' | Out-Null

    # --- so o Painel na tela --------------------------------------------------
    $visivel = Get-TmxEval "String(getComputedStyle(document.getElementById('tab-painel')).display !== 'none')"
    Assert-Tmx -Nome 'o Painel fica visivel' -Condicao ($visivel -eq 'true') -Detalhe "obtido: '$visivel'"

    $vazando = Get-TmxEval "String([].filter.call(document.querySelectorAll('main > .tab'), function (s) { return s.id !== 'tab-painel' && getComputedStyle(s).display !== 'none'; }).length)"
    Assert-Tmx -Nome 'nenhuma outra aba aparece junto com o Painel' -Condicao ($vazando -eq '0') -Detalhe "abas visiveis alem do painel: '$vazando'"

    $placeholder = Get-TmxEval "String(document.querySelectorAll('#tab-painel [data-i18n=""painel.emConstrucao""]').length)"
    Assert-Tmx -Nome 'o placeholder "Em construcao" saiu' -Condicao ($placeholder -eq '0') -Detalhe "obtido: '$placeholder'"

    # --- saudacao -------------------------------------------------------------
    $titulo = Get-TmxEval "document.querySelector('#tab-painel .pn-titulo').textContent"
    Assert-Tmx -Nome 'saudacao "Bem-vindo de volta"' -Condicao ($titulo -like 'Bem-vindo de volta*') -Detalhe "obtido: '$titulo'"

    $nome = Wait-TmxEval -Js "document.getElementById('pn-nome').textContent" -Ok { param($v) "$v".Trim() -ne '' } -TimeoutSeconds 20
    Assert-Tmx -Nome 'o nome de exibicao aparece na saudacao' -Condicao ("$nome".Trim() -ne '') -Detalhe "obtido: '$nome'"

    # --- hardware (system.info) ------------------------------------------------
    $cartoes = Get-TmxEval "String(document.querySelectorAll('#pn-hw .pn-hw-card').length)"
    Assert-Tmx -Nome '4 cartoes de hardware' -Condicao ($cartoes -eq '4') -Detalhe "obtido: '$cartoes'"

    $jsCpu = "(function () { var e = document.getElementById('pn-hw-cpu-valor'); var t = e ? e.textContent : ''; return (t && t.indexOf('Lendo') !== 0) ? t : ''; })()"
    $cpu = Wait-TmxEval -Js $jsCpu -Ok { param($v) "$v".Trim() -ne '' } -TimeoutSeconds 90
    Assert-Tmx -Nome 'processador preenchido pelo system.info' -Condicao ("$cpu".Trim() -ne '') -Detalhe "obtido: '$cpu'"

    $preenchidos = Get-TmxEval "String(['gpu','ram','disco'].filter(function (id) { var t = document.getElementById('pn-hw-' + id + '-valor').textContent; return t && t.indexOf('Lendo') !== 0; }).length)"
    Assert-Tmx -Nome 'GPU, memoria e armazenamento preenchidos' -Condicao ($preenchidos -eq '3') -Detalhe "obtido: '$preenchidos'"

    $os = Get-TmxEval "document.getElementById('pn-os-edicao').textContent"
    Assert-Tmx -Nome 'cartao do sistema operacional mostra o Windows' -Condicao ($os -like '*Windows*') -Detalhe "obtido: '$os'"

    # --- recomendacoes ----------------------------------------------------------
    $recs = Wait-TmxEval -Js "String(document.querySelectorAll('#pn-recs .pn-rec').length)" -Ok { param($v) (ConvertTo-TmxInt $v) -ge 1 } -TimeoutSeconds 20
    $nRecs = ConvertTo-TmxInt $recs
    Assert-Tmx -Nome 'de 1 a 3 recomendacoes' -Condicao ($nRecs -ge 1 -and $nRecs -le 3) -Detalhe "obtido: '$recs'"

    $crua = Get-TmxEval "String([].some.call(document.querySelectorAll('#pn-recs .pn-rec-titulo, #pn-recs .pn-rec-texto, #pn-recs .pn-rec-tipo'), function (e) { return /^painel\./.test(e.textContent); }))"
    Assert-Tmx -Nome 'recomendacoes traduzidas (nenhuma chave painel.rec.* crua)' -Condicao ($crua -eq 'false') -Detalhe "obtido: '$crua'"

    Invoke-AB 'scrollintoview' '#pn-rec-0 .pn-rec-guia' | Out-Null
    Invoke-AB 'click' '#pn-rec-0 .pn-rec-guia' | Out-Null
    Invoke-AB 'wait' '#modal-buttons button' | Out-Null
    $guia = Get-TmxEval "String(document.querySelectorAll('#modal-body li, #modal-body p').length)"
    Assert-Tmx -Nome 'o passo a passo abre no modal' -Condicao ((ConvertTo-TmxInt $guia) -ge 1) -Detalhe "obtido: '$guia'"
    Invoke-AB 'click' '#modal-buttons button' | Out-Null

    # --- status de otimizacao (job que rele o catalogo inteiro) ----------------
    $pct = Wait-TmxEval -Js "document.getElementById('pn-pct').textContent" -Ok { param($v) "$v" -match '^\d{1,3}%$' } -TimeoutSeconds 150
    Assert-Tmx -Nome 'anel de status mostra a porcentagem' -Condicao ("$pct" -match '^\d{1,3}%$') -Detalhe "obtido: '$pct'"

    $disp = Get-TmxEval "document.getElementById('pn-disponiveis').textContent"
    Assert-Tmx -Nome 'status mostra quantos ajustes estao disponiveis' -Condicao ((ConvertTo-TmxInt (($disp -replace '[^\d]', ''))) -ge 1) -Detalhe "obtido: '$disp'"

    $modo = Get-TmxEval "document.getElementById('pn-modo-atual').textContent"
    Assert-Tmx -Nome 'status mostra o modo atual' -Condicao ("$modo".Trim() -ne '' -and $modo -ne '...') -Detalhe "obtido: '$modo'"

    # --- criar ponto (restore.create simulado) ---------------------------------
    Invoke-AB 'scrollintoview' '#pn-criar-ponto' | Out-Null
    Invoke-AB 'click' '#pn-criar-ponto' | Out-Null
    $ponto = Wait-TmxEval -Js "document.getElementById('pn-ponto-texto').textContent" -Ok { param($v) "$v" -like '*hoje*' } -TimeoutSeconds 40
    Assert-Tmx -Nome '"Criar ponto agora" atualiza o ultimo ponto para hoje' -Condicao ("$ponto" -like '*hoje*') -Detalhe "obtido: '$ponto'"

    # --- idioma -----------------------------------------------------------------
    Get-TmxEval "tmx.i18n.set('en'); 'ok'" | Out-Null
    $tituloEn = Get-TmxEval "document.querySelector('#tab-painel .pn-titulo').textContent"
    Assert-Tmx -Nome 'em ingles a saudacao vira "Welcome back"' -Condicao ($tituloEn -like 'Welcome back*') -Detalhe "obtido: '$tituloEn'"
    $rotuloEn = Get-TmxEval "document.querySelector('#pn-hw-cpu .pn-hw-rotulo').textContent"
    Assert-Tmx -Nome 'em ingles o cartao de CPU diz "Processor"' -Condicao ($rotuloEn -eq 'Processor') -Detalhe "obtido: '$rotuloEn'"
    Get-TmxEval "tmx.i18n.set('pt-BR'); 'ok'" | Out-Null

    # --- print ------------------------------------------------------------------
    Get-TmxEval "document.querySelector('main').scrollTop = 0; 'ok'" | Out-Null
    $print = Join-Path (Initialize-TmxGuiOut) 'painel.png'
    Invoke-AB 'screenshot' $print | Out-Null
    Assert-Tmx -Nome 'screenshot gravado' -Condicao (Test-Path -LiteralPath $print) -Detalhe $print
    Write-Host "Print: $print"

    # --- chip de modo abre Otimizacoes -----------------------------------------
    Invoke-AB 'click' '#pn-modos .pn-modo[data-modo=moderado]' | Out-Null
    $otim = Wait-TmxEval -Js "String(!document.getElementById('tab-otimizacoes').hidden && document.getElementById('tab-painel').hidden)" -Ok { param($v) $v -eq 'true' } -TimeoutSeconds 10
    Assert-Tmx -Nome 'o chip "Moderado" abre a tela de Otimizacoes' -Condicao ($otim -eq 'true') -Detalhe "obtido: '$otim'"

    $erros = "$(Invoke-AB 'errors')".Trim()
    Assert-Tmx -Nome 'nenhum erro de JS' -Condicao ([string]::IsNullOrWhiteSpace($erros) -or $erros -match '(?i)no errors|nenhum erro') -Detalhe "obtido: '$erros'"

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
