<#
.SYNOPSIS
    Teste de fumaca da tela Configuracoes (v2): abre a janela real e conversa por CDP.
.DESCRIPTION
    Nao e Pester. Semeia duas execucoes antigas (60 dias) e uma recente em
    <home de teste>\runs, sobe a GUI com -TestMode -DebugPort 9353 (porta
    reservada para esta tela) e confere: nome de exibicao (settings.set,
    refletido no Painel), "Usar o nome do Windows" (settings.windowsName),
    idioma, menu recolhido sincronizado com o botao da casca, versao e
    "Verificar atualizacoes" (app.checkUpdate, simulado sem rede), os caminhos
    na tela (app.paths), abrir logs (simulado), limpar cache e excluir
    backups antigos com confirmacao (app.oldBackups/app.deleteOldBackups).
    Tudo acontece na home de teste.

    Deixa um print em tests/gui/out/configuracoes.png. Sai com 1 se qualquer
    verificacao falhar. Sempre fecha a GUI, zera o nome de exibicao e apaga
    as execucoes semeadas.
.EXAMPLE
    .\tests\gui\Test-Configuracoes.ps1
#>
[CmdletBinding()]
param(
    [int] $Port = 9353
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

# Execucoes semeadas na home de teste (Get-TmxRunsRoot): duas antigas, que
# app.oldBackups tem que achar, e uma recente, que nunca pode ser apagada.
$script:HomeTeste = Join-Path (Join-Path ([IO.Path]::GetTempPath()) 'TweakMaxing_Tests') 'home'
$script:Runs      = Join-Path $script:HomeTeste 'runs'
$script:Velhos    = @('00000000-gui-velho-a', '00000000-gui-velho-b')
$script:Recente   = '99999999-gui-recente'
$script:Versao    = (Get-Content -LiteralPath (Join-Path $script:TmxRepoRoot 'VERSION') -Raw).Trim()

function Set-TmxRunsSeed {
    foreach ($n in $script:Velhos) {
        $p = Join-Path $script:Runs $n
        New-Item -ItemType Directory -Path $p -Force | Out-Null
        (Get-Item -LiteralPath $p).CreationTimeUtc = (Get-Date).ToUniversalTime().AddDays(-60)
    }
    New-Item -ItemType Directory -Path (Join-Path $script:Runs $script:Recente) -Force | Out-Null
}

function Clear-TmxRunsSeed {
    foreach ($n in @($script:Velhos + $script:Recente)) {
        $p = Join-Path $script:Runs $n
        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

Wait-TmxOutroTestePid
Set-TmxRunsSeed

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

    Invoke-AB 'click' 'nav [data-tab=configuracoes]' | Out-Null
    Invoke-AB 'wait' '#cf-nome' | Out-Null

    $vazando = Get-TmxEval "String([].filter.call(document.querySelectorAll('main > .tab'), function (s) { return s.id !== 'tab-configuracoes' && getComputedStyle(s).display !== 'none'; }).length)"
    Assert-Tmx -Nome 'so a tela de Configuracoes aparece' -Condicao ($vazando -eq '0') -Detalhe "abas visiveis alem de configuracoes: '$vazando'"

    $secoes = Get-TmxEval "String(document.querySelectorAll('#tab-configuracoes .cf-secao').length)"
    Assert-Tmx -Nome '4 secoes (Perfil, Aparencia, Sistema, Privacidade e dados)' -Condicao ($secoes -eq '4') -Detalhe "obtido: '$secoes'"

    # --- sistema: versao e caminhos -----------------------------------------------
    $versao = Wait-TmxEval -Js "document.getElementById('cf-versao').textContent" -Ok { param($v) $v -eq $script:Versao } -TimeoutSeconds 15
    Assert-Tmx -Nome 'a versao instalada bate com o arquivo VERSION' -Condicao ($versao -eq $script:Versao) -Detalhe "obtido: '$versao' / esperado: '$($script:Versao)'"

    $caminhos = Get-TmxEval "['cf-caminho-cache','cf-caminho-logs','cf-caminho-runs'].map(function (id) { return document.getElementById(id).textContent; }).join('|')"
    Assert-Tmx -Nome 'os caminhos de cache, logs e backups aparecem (home de teste)' `
        -Condicao ((@($caminhos -split '\|' | Where-Object { $_ -like '*TweakMaxing_Tests*' })).Count -eq 3) -Detalhe "obtido: '$caminhos'"

    # --- perfil: nome de exibicao ------------------------------------------------------
    Invoke-AB 'fill' '#cf-nome' 'Jogador GUI' | Out-Null
    Invoke-AB 'click' '#cf-nome-salvar' | Out-Null
    $salvo = Wait-TmxEval -Js "window.tmx.bridge.call('settings.get').then(function (s) { return s.displayName; })" -Ok { param($v) $v -eq 'Jogador GUI' } -TimeoutSeconds 15
    Assert-Tmx -Nome 'Salvar grava displayName (settings.set)' -Condicao ($salvo -eq 'Jogador GUI') -Detalhe "obtido: '$salvo'"
    $noPainel = Wait-TmxEval -Js "document.getElementById('pn-nome') ? document.getElementById('pn-nome').textContent : ''" -Ok { param($v) $v -eq 'Jogador GUI' } -TimeoutSeconds 10
    Assert-Tmx -Nome 'o Painel passa a saudar com o nome novo' -Condicao ($noPainel -eq 'Jogador GUI') -Detalhe "obtido: '$noPainel'"

    Invoke-AB 'click' '#cf-nome-windows' | Out-Null
    $jsWin = "window.tmx.bridge.call('settings.get').then(function (s) { return s.displayName + '|' + document.getElementById('cf-nome').value; })"
    $win = Wait-TmxEval -Js $jsWin -Ok { param($v) $p = "$v" -split '\|'; $p.Count -eq 2 -and $p[0] -ne 'Jogador GUI' -and $p[0] -ne '' -and $p[0] -eq $p[1] } -TimeoutSeconds 15
    $pw = "$win" -split '\|'
    Assert-Tmx -Nome '"Usar o nome do Windows" preenche e salva o nome da conta' -Condicao ($pw.Count -eq 2 -and $pw[0] -ne 'Jogador GUI' -and $pw[0] -ne '' -and $pw[0] -eq $pw[1]) -Detalhe "obtido: '$win'"

    # --- aparencia: idioma ---------------------------------------------------------------
    Invoke-AB 'click' '#cf-lang-en' | Out-Null
    $en = Wait-TmxEval -Js "tmx.i18n.lang + '|' + document.querySelector('#tab-configuracoes .tmx-titulo').textContent + '|' + document.getElementById('cf-lang-en').getAttribute('aria-pressed')" -Ok { param($v) $v -eq 'en|Settings|true' } -TimeoutSeconds 10
    Assert-Tmx -Nome 'o botao English troca o idioma do app' -Condicao ($en -eq 'en|Settings|true') -Detalhe "obtido: '$en'"
    $nav = Get-TmxEval "document.querySelector('nav [data-tab=configuracoes] .aba-rotulo').textContent"
    Assert-Tmx -Nome 'o menu lateral acompanha o idioma' -Condicao ($nav -eq 'Settings') -Detalhe "obtido: '$nav'"
    Invoke-AB 'click' '#cf-lang-pt-BR' | Out-Null
    $pt = Wait-TmxEval -Js "tmx.i18n.lang" -Ok { param($v) $v -eq 'pt-BR' } -TimeoutSeconds 10
    Assert-Tmx -Nome 'volta para Portugues' -Condicao ($pt -eq 'pt-BR') -Detalhe "obtido: '$pt'"

    # --- aparencia: menu recolhido (usa o botao da casca) -----------------------------------
    $antes = Get-TmxEval "document.body.dataset.sidebar || 'expanded'"
    Invoke-AB 'click' '#cf-sidebar' | Out-Null
    $depois = Wait-TmxEval -Js "(document.body.dataset.sidebar || 'expanded') + '|' + document.getElementById('cf-sidebar').getAttribute('aria-checked')" -Ok { param($v) -not ("$v" -like "$antes|*") } -TimeoutSeconds 10
    $esperadoDepois = if ($antes -eq 'collapsed') { 'expanded|false' } else { 'collapsed|true' }
    Assert-Tmx -Nome 'o interruptor recolhe/expande o menu e fica sincronizado' -Condicao ($depois -eq $esperadoDepois) -Detalhe "antes: '$antes' / depois: '$depois'"
    Invoke-AB 'click' '#sidebar-collapse' | Out-Null
    $volta = Wait-TmxEval -Js "(document.body.dataset.sidebar || 'expanded') + '|' + document.getElementById('cf-sidebar').getAttribute('aria-checked')" -Ok { param($v) "$v" -like "$antes|*" } -TimeoutSeconds 10
    Assert-Tmx -Nome 'o botao da casca tambem move o interruptor' -Condicao ("$volta" -like "$antes|*") -Detalhe "obtido: '$volta'"

    # --- sistema: verificar atualizacoes (simulado) ---------------------------------------
    Invoke-AB 'scrollintoview' '#cf-update' | Out-Null
    Invoke-AB 'click' '#cf-update' | Out-Null
    $upd = Wait-TmxEval -Js "(function () { var e = document.getElementById('cf-update-resultado'); return (e.hidden ? 'oculto' : e.className) + '|' + e.textContent; })()" -Ok { param($v) "$v" -like '*cf-update-ok*' } -TimeoutSeconds 40
    Assert-Tmx -Nome '"Verificar atualizacoes" responde (ja na mais recente, modo de teste)' -Condicao ("$upd" -like "*cf-update-ok*$($script:Versao)*") -Detalhe "obtido: '$upd'"

    # --- privacidade e dados ---------------------------------------------------------------
    Invoke-AB 'scrollintoview' '#cf-logs' | Out-Null
    Invoke-AB 'click' '#cf-logs' | Out-Null
    $toastLogs = Wait-TmxEval -Js "document.getElementById('toasts').textContent" -Ok { param($v) "$v" -like '*Modo de teste*' } -TimeoutSeconds 10
    Assert-Tmx -Nome 'abrir logs no modo de teste nao abre o Explorer' -Condicao ("$toastLogs" -like '*Modo de teste*') -Detalhe "obtido: '$toastLogs'"

    # Os toasts (canto inferior direito) cobrem os botoes desta coluna.
    Get-TmxEval "document.getElementById('toasts').innerHTML = ''; 'ok'" | Out-Null
    Invoke-AB 'click' '#cf-cache' | Out-Null
    $toastCache = Wait-TmxEval -Js "document.getElementById('toasts').textContent" -Ok { param($v) "$v" -like '*Cache limpo*' } -TimeoutSeconds 40
    Assert-Tmx -Nome 'limpar cache responde (app.clearCache)' -Condicao ("$toastCache" -like '*Cache limpo*') -Detalhe "obtido: '$toastCache'"

    # Os toasts (canto inferior direito) cobrem os botoes desta coluna.
    Get-TmxEval "document.getElementById('toasts').innerHTML = ''; 'ok'" | Out-Null
    Invoke-AB 'scrollintoview' '#cf-backups' | Out-Null
    Invoke-AB 'click' '#cf-backups' | Out-Null
    Invoke-AB 'wait' '#modal-buttons .cf-confirmar-backups' | Out-Null
    $lista = Get-TmxEval "document.getElementById('cf-lista-backups').textContent"
    Assert-Tmx -Nome 'a confirmacao lista os backups antigos semeados' `
        -Condicao ($lista -like '*gui-velho-a*' -and $lista -like '*gui-velho-b*' -and $lista -notlike '*gui-recente*') -Detalhe "obtido: '$lista'"
    Invoke-AB 'click' '#modal-buttons .cf-confirmar-backups' | Out-Null

    $limite = (Get-Date).AddSeconds(40)
    while ((Get-Date) -lt $limite -and (Test-Path -LiteralPath (Join-Path $script:Runs $script:Velhos[0]))) { Start-Sleep -Milliseconds 400 }
    Assert-Tmx -Nome 'os backups antigos foram apagados' `
        -Condicao (-not (Test-Path -LiteralPath (Join-Path $script:Runs $script:Velhos[0])) -and -not (Test-Path -LiteralPath (Join-Path $script:Runs $script:Velhos[1])))
    Assert-Tmx -Nome 'a execucao recente ficou' -Condicao (Test-Path -LiteralPath (Join-Path $script:Runs $script:Recente))

    Get-TmxEval "document.querySelector('main').scrollTop = 0; 'ok'" | Out-Null
    $print = Join-Path (Initialize-TmxGuiOut) 'configuracoes.png'
    Invoke-AB 'screenshot' $print | Out-Null
    Assert-Tmx -Nome 'screenshot gravado' -Condicao (Test-Path -LiteralPath $print) -Detalhe $print
    Write-Host "Print: $print"

    $erros = "$(Invoke-AB 'errors')".Trim()
    Assert-Tmx -Nome 'nenhum erro de JS' -Condicao ([string]::IsNullOrWhiteSpace($erros) -or $erros -match '(?i)no errors|nenhum erro') -Detalhe "obtido: '$erros'"

    # Nome de exibicao volta ao padrao: outros testes esperam a home de teste limpa.
    Get-TmxEval "window.tmx.bridge.call('settings.set', { displayName: '' }).then(function () { return 'ok'; })" | Out-Null

} catch {
    $script:Falhas++
    Write-Host "FAIL  execucao: $($_.Exception.Message)" -ForegroundColor Red
} finally {
    Write-Host 'Fechando a GUI...' -ForegroundColor Cyan
    $limpo = Stop-TmxGui -Port $Port
    Assert-Tmx -Nome 'porta CDP liberada no fim' -Condicao ([bool]$limpo)
    Clear-TmxRunsSeed
}

Write-Host ''
if ($script:Falhas -gt 0) {
    Write-Host "RESULTADO: $script:Falhas verificacao(oes) falharam." -ForegroundColor Red
    exit 1
}
Write-Host 'RESULTADO: todas as verificacoes passaram.' -ForegroundColor Green
exit 0
