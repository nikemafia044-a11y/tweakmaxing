<#
.SYNOPSIS
    Teste de fumaca da tela Restauracao (v2): abre a janela real e conversa por CDP.
.DESCRIPTION
    Nao e Pester. Semeia a lista falsa de pontos de restauracao do modo de
    teste (<home de teste>\restore-points-fake.json, ver RestorePoints.ps1)
    com dois pontos, sobe a GUI com -TestMode -DebugPort 9352 (porta
    reservada para esta tela) e confere: a lista (restore.list), criar um
    ponto com nome (restore.create), excluir um ponto com confirmacao
    (restore.delete), restaurar com confirmacao e o aviso de reinicio
    (restore.restore, simulado) e a recusa da ponte sem confirmado:true.
    Nenhuma das quatro acoes toca os pontos reais do Windows.

    Deixa um print em tests/gui/out/restauracao.png. Sai com 1 se qualquer
    verificacao falhar. Sempre fecha a GUI e devolve a lista falsa anterior.
.EXAMPLE
    .\tests\gui\Test-Restauracao.ps1
#>
[CmdletBinding()]
param(
    [int] $Port = 9352
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

# Lista falsa do modo de teste (Get-TmxRestoreFakeListPath). O conteudo que
# existia antes (outros testes criam pontos pela sessao) volta no finally.
$script:HomeTeste  = Join-Path (Join-Path ([IO.Path]::GetTempPath()) 'TweakMaxing_Tests') 'home'
$script:ListaFalsa = Join-Path $script:HomeTeste 'restore-points-fake.json'
$script:ListaAntes = $null

function Set-TmxRestoreSeed {
    if (-not (Test-Path -LiteralPath $script:HomeTeste)) { New-Item -ItemType Directory -Path $script:HomeTeste -Force | Out-Null }
    if (Test-Path -LiteralPath $script:ListaFalsa) { $script:ListaAntes = [IO.File]::ReadAllText($script:ListaFalsa) }
    $ontem = (Get-Date).AddDays(-1).ToString('o')
    $semana = (Get-Date).AddDays(-7).ToString('o')
    $json = '[{"sequencia":1,"nome":"Semente GUI antigo","data":"' + $semana + '"},' +
            '{"sequencia":2,"nome":"Semente GUI ontem","data":"' + $ontem + '"}]'
    [IO.File]::WriteAllText($script:ListaFalsa, $json, (New-Object System.Text.UTF8Encoding($false)))
}

function Restore-TmxRestoreSeed {
    if ($null -ne $script:ListaAntes) {
        [IO.File]::WriteAllText($script:ListaFalsa, $script:ListaAntes, (New-Object System.Text.UTF8Encoding($false)))
    } elseif (Test-Path -LiteralPath $script:ListaFalsa) {
        Remove-Item -LiteralPath $script:ListaFalsa -Force -ErrorAction SilentlyContinue
    }
}

function Get-TmxQtdPontos {
    Get-TmxEval "String(document.querySelectorAll('#rs-lista .rs-ponto').length)"
}

Wait-TmxOutroTestePid
Set-TmxRestoreSeed

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

    Invoke-AB 'click' 'nav [data-tab=restauracao]' | Out-Null
    Invoke-AB 'wait' '#rs-lista' | Out-Null

    $vazando = Get-TmxEval "String([].filter.call(document.querySelectorAll('main > .tab'), function (s) { return s.id !== 'tab-restauracao' && getComputedStyle(s).display !== 'none'; }).length)"
    Assert-Tmx -Nome 'so a tela de Restauracao aparece' -Condicao ($vazando -eq '0') -Detalhe "abas visiveis alem da restauracao: '$vazando'"

    # --- restore.list ----------------------------------------------------------
    $qtd = Wait-TmxEval -Js "String(document.querySelectorAll('#rs-lista .rs-ponto').length)" -Ok { param($v) $v -eq '2' } -TimeoutSeconds 60
    Assert-Tmx -Nome 'a lista mostra os 2 pontos semeados' -Condicao ($qtd -eq '2') -Detalhe "obtido: '$qtd'"

    $ordem = Get-TmxEval "[].map.call(document.querySelectorAll('#rs-lista .rs-ponto'), function (e) { return e.getAttribute('data-seq'); }).join(',')"
    Assert-Tmx -Nome 'mais recente primeiro (2,1)' -Condicao ($ordem -eq '2,1') -Detalhe "obtido: '$ordem'"

    $nome2 = Get-TmxEval "document.querySelector('#rs-ponto-2 .rs-ponto-nome').textContent"
    Assert-Tmx -Nome 'o nome do ponto aparece' -Condicao ($nome2 -like 'Semente GUI ontem*') -Detalhe "obtido: '$nome2'"

    $selo = Get-TmxEval "String(document.querySelectorAll('#rs-ponto-2 .rs-selo').length)"
    Assert-Tmx -Nome 'o ponto mais recente ganha o selo' -Condicao ($selo -eq '1') -Detalhe "obtido: '$selo'"

    # --- restore.create com nome -------------------------------------------------
    Invoke-AB 'fill' '#rs-nome' 'Antes do teste GUI' | Out-Null
    Invoke-AB 'click' '#rs-criar' | Out-Null
    $qtd = Wait-TmxEval -Js "String(document.querySelectorAll('#rs-lista .rs-ponto').length)" -Ok { param($v) $v -eq '3' } -TimeoutSeconds 40
    Assert-Tmx -Nome 'criar ponto acrescenta um item na lista' -Condicao ($qtd -eq '3') -Detalhe "obtido: '$qtd'"
    $novo = Get-TmxEval "(function () { var e = document.querySelector('#rs-ponto-3 .rs-ponto-nome'); return e ? e.textContent : ''; })()"
    Assert-Tmx -Nome 'o ponto novo usa o nome digitado e vai para o topo' -Condicao ($novo -like 'Antes do teste GUI*') -Detalhe "obtido: '$novo'"
    $campo = Get-TmxEval "document.getElementById('rs-nome').value"
    Assert-Tmx -Nome 'o campo de nome e limpo depois de criar' -Condicao ($campo -eq '') -Detalhe "obtido: '$campo'"

    # --- restore.delete com confirmacao -------------------------------------------
    Invoke-AB 'scrollintoview' '#rs-ponto-1 .rs-excluir' | Out-Null
    Invoke-AB 'click' '#rs-ponto-1 .rs-excluir' | Out-Null
    Invoke-AB 'wait' '#modal-buttons .rs-confirmar-excluir' | Out-Null
    $textoExcluir = Get-TmxEval "document.getElementById('modal-body').textContent"
    Assert-Tmx -Nome 'o modal de exclusao cita o ponto' -Condicao ($textoExcluir -like '*Semente GUI antigo*') -Detalhe "obtido: '$textoExcluir'"
    Invoke-AB 'click' '#modal-buttons .rs-confirmar-excluir' | Out-Null
    $qtd = Wait-TmxEval -Js "String(document.querySelectorAll('#rs-lista .rs-ponto').length)" -Ok { param($v) $v -eq '2' } -TimeoutSeconds 40
    Assert-Tmx -Nome 'excluir tira o ponto da lista' -Condicao ($qtd -eq '2') -Detalhe "obtido: '$qtd'"
    $sumiu = Get-TmxEval "String(document.querySelectorAll('#rs-ponto-1').length)"
    Assert-Tmx -Nome 'o ponto #1 nao existe mais' -Condicao ($sumiu -eq '0') -Detalhe "obtido: '$sumiu'"

    # --- restore.restore com confirmacao e aviso de reinicio ------------------------
    Invoke-AB 'scrollintoview' '#rs-ponto-2 .rs-restaurar' | Out-Null
    Invoke-AB 'click' '#rs-ponto-2 .rs-restaurar' | Out-Null
    Invoke-AB 'wait' '#modal-buttons .rs-confirmar-restaurar' | Out-Null
    $avisos = Get-TmxEval "String(document.querySelectorAll('#modal-body .rs-avisos li').length)"
    Assert-Tmx -Nome 'a confirmacao de restaurar lista os avisos' -Condicao ($avisos -eq '3') -Detalhe "obtido: '$avisos'"
    Invoke-AB 'click' '#modal-buttons .rs-confirmar-restaurar' | Out-Null
    $agendada = Wait-TmxEval -Js "(function () { var e = document.querySelector('#modal-body .rs-agendada'); return e ? e.textContent : ''; })()" -Ok { param($v) "$v" -like '*Reinicie*' } -TimeoutSeconds 40
    Assert-Tmx -Nome 'depois de restaurar a tela pede para reiniciar' -Condicao ("$agendada" -like '*Reinicie*') -Detalhe "obtido: '$agendada'"
    $simulado = Get-TmxEval "String(document.querySelectorAll('#modal-body .rs-nota').length)"
    Assert-Tmx -Nome 'no modo de teste o modal diz que foi simulado' -Condicao ($simulado -eq '1') -Detalhe "obtido: '$simulado'"
    Invoke-AB 'click' '#modal-buttons button' | Out-Null

    # --- a ponte recusa restaurar sem confirmado:true -------------------------------
    $recusa = Get-TmxEval "window.tmx.bridge.call('restore.restore',{sequencia:2}).then(function(){return 'ACEITOU';},function(e){return 'RECUSOU: '+e.message;})"
    Assert-Tmx -Nome 'restore.restore sem confirmado:true e recusado' -Condicao ($recusa -like 'RECUSOU*confirmacao*') -Detalhe "obtido: '$recusa'"

    # --- idioma -------------------------------------------------------------------
    Get-TmxEval "tmx.i18n.set('en'); 'ok'" | Out-Null
    $botaoEn = Get-TmxEval "document.querySelector('#rs-ponto-2 .rs-restaurar').textContent"
    Assert-Tmx -Nome 'em ingles os botoes sao traduzidos' -Condicao ($botaoEn -eq 'Restore') -Detalhe "obtido: '$botaoEn'"
    Get-TmxEval "tmx.i18n.set('pt-BR'); 'ok'" | Out-Null

    Get-TmxEval "document.querySelector('main').scrollTop = 0; 'ok'" | Out-Null
    $print = Join-Path (Initialize-TmxGuiOut) 'restauracao.png'
    Invoke-AB 'screenshot' $print | Out-Null
    Assert-Tmx -Nome 'screenshot gravado' -Condicao (Test-Path -LiteralPath $print) -Detalhe $print
    Write-Host "Print: $print"

    $erros = "$(Invoke-AB 'errors')".Trim()
    Assert-Tmx -Nome 'nenhum erro de JS' -Condicao ([string]::IsNullOrWhiteSpace($erros) -or $erros -match '(?i)no errors|nenhum erro') -Detalhe "obtido: '$erros'"

} catch {
    $script:Falhas++
    Write-Host "FAIL  execucao: $($_.Exception.Message)" -ForegroundColor Red
} finally {
    Write-Host 'Fechando a GUI...' -ForegroundColor Cyan
    $limpo = Stop-TmxGui -Port $Port
    Assert-Tmx -Nome 'porta CDP liberada no fim' -Condicao ([bool]$limpo)
    Restore-TmxRestoreSeed
}

Write-Host ''
if ($script:Falhas -gt 0) {
    Write-Host "RESULTADO: $script:Falhas verificacao(oes) falharam." -ForegroundColor Red
    exit 1
}
Write-Host 'RESULTADO: todas as verificacoes passaram.' -ForegroundColor Green
exit 0
