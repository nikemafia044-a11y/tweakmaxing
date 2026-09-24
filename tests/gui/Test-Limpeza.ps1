<#
.SYNOPSIS
    Teste de fumaca da tela Limpeza (v2): abre a janela real e conversa por CDP.
.DESCRIPTION
    Nao e Pester. Semeia um arquivo de 4 KB em cada item da raiz falsa de
    limpeza (<home de teste>\cleanup-fake, ver Get-TmxCleanupRoots), sobe a
    GUI com -TestMode -DebugPort 9351 (porta reservada para esta tela) e
    confere: os 6 itens, o scan (cleanup.scan) medindo a raiz falsa, Lixeira
    (Perigoso) e Prefetch (Nao recomendado) desmarcados por padrao, o modal de
    confirmacao, a limpeza (cleanup.run) apagando so o que foi marcado,
    lastCleanup/lastCleanupFreed no resumo, o aviso de perigo quando a
    Lixeira entra na selecao e a troca de idioma. Nada toca %TEMP%/%WINDIR%
    reais nem a Lixeira de verdade.

    Deixa um print em tests/gui/out/limpeza.png. Sai com 1 se qualquer
    verificacao falhar. Sempre fecha a GUI e apaga a raiz falsa.
.EXAMPLE
    .\tests\gui\Test-Limpeza.ps1
#>
[CmdletBinding()]
param(
    [int] $Port = 9351
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

# Raiz falsa da limpeza no modo de teste (Get-TmxCleanupRoots): nunca %TEMP%
# nem %WINDIR% reais. Um arquivo conhecido de 4 KB em cada item.
$script:HomeTeste = Join-Path (Join-Path ([IO.Path]::GetTempPath()) 'TweakMaxing_Tests') 'home'
$script:RaizFalsa = Join-Path $script:HomeTeste 'cleanup-fake'
$script:Semente = [ordered]@{
    'temp-usuario' = 'lixo-usuario.tmp'
    'temp-sistema' = 'lixo-sistema.tmp'
    'wu-cache'     = 'pacote.cab'
    'miniaturas'   = 'thumbcache_256.db'
    'lixeira'      = 'apagado.bin'
    'prefetch'     = 'JOGO.EXE-1234.pf'
}

function Reset-TmxCleanupSeed {
    if (Test-Path -LiteralPath $script:RaizFalsa) {
        Remove-Item -LiteralPath $script:RaizFalsa -Recurse -Force -ErrorAction SilentlyContinue
    }
    foreach ($id in $script:Semente.Keys) {
        $pasta = Join-Path $script:RaizFalsa $id
        New-Item -ItemType Directory -Path $pasta -Force | Out-Null
        [IO.File]::WriteAllBytes((Join-Path $pasta $script:Semente[$id]), (New-Object byte[] 4096))
    }
}

function Test-TmxSemente {
    param([string] $Id)
    Test-Path -LiteralPath (Join-Path (Join-Path $script:RaizFalsa $Id) $script:Semente[$Id])
}

Wait-TmxOutroTestePid
Reset-TmxCleanupSeed

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

    Invoke-AB 'click' 'nav [data-tab=limpeza]' | Out-Null
    Invoke-AB 'wait' '#lp-itens' | Out-Null

    $vazando = Get-TmxEval "String([].filter.call(document.querySelectorAll('main > .tab'), function (s) { return s.id !== 'tab-limpeza' && getComputedStyle(s).display !== 'none'; }).length)"
    Assert-Tmx -Nome 'so a tela de Limpeza aparece' -Condicao ($vazando -eq '0') -Detalhe "abas visiveis alem da limpeza: '$vazando'"

    $itens = Get-TmxEval "String(document.querySelectorAll('#lp-itens .lp-item').length)"
    Assert-Tmx -Nome '6 itens de limpeza' -Condicao ($itens -eq '6') -Detalhe "obtido: '$itens'"

    # --- cleanup.scan mede a raiz falsa ---------------------------------------
    $tam = Wait-TmxEval -Js "document.getElementById('lp-tam-temp-usuario').textContent" -Ok { param($v) "$v" -match '^4\s*KB$' } -TimeoutSeconds 60
    Assert-Tmx -Nome 'o scan mede 4 KB em Temporarios do usuario' -Condicao ("$tam" -match '^4\s*KB$') -Detalhe "obtido: '$tam'"

    $arq = Get-TmxEval "document.getElementById('lp-arq-miniaturas').textContent"
    Assert-Tmx -Nome 'miniaturas contam 1 arquivo (thumbcache_*.db)' -Condicao ($arq -like '1 *') -Detalhe "obtido: '$arq'"

    # --- selos e marcacao padrao ------------------------------------------------
    $marcados = Get-TmxEval "[].map.call(document.querySelectorAll('.lp-chk'), function (c) { return c.value + '=' + c.checked; }).join(',')"
    $esperado = 'temp-usuario=true,temp-sistema=true,wu-cache=true,miniaturas=true,lixeira=false,prefetch=false'
    Assert-Tmx -Nome 'Lixeira e Prefetch comecam desmarcados; o resto marcado' -Condicao ($marcados -eq $esperado) -Detalhe "obtido: '$marcados'"

    $seloLixeira = Get-TmxEval "String(document.querySelectorAll('#lp-item-lixeira .lp-selo-perigoso').length)"
    Assert-Tmx -Nome 'Lixeira tem o selo Perigoso' -Condicao ($seloLixeira -eq '1') -Detalhe "obtido: '$seloLixeira'"
    $seloPrefetch = Get-TmxEval "String(document.querySelectorAll('#lp-item-prefetch .lp-selo-naoRecomendado').length)"
    Assert-Tmx -Nome 'Prefetch tem o selo Nao recomendado' -Condicao ($seloPrefetch -eq '1') -Detalhe "obtido: '$seloPrefetch'"

    $total = Get-TmxEval "document.getElementById('lp-total').textContent"
    Assert-Tmx -Nome 'o resumo soma os 4 itens marcados (16 KB)' -Condicao ($total -match '^16\s*KB$') -Detalhe "obtido: '$total'"

    # --- limpar: modal de confirmacao e cleanup.run ------------------------------
    Invoke-AB 'click' '#lp-limpar' | Out-Null
    Invoke-AB 'wait' '#modal-buttons .lp-confirmar' | Out-Null
    $linhas = Get-TmxEval "String(document.querySelectorAll('#modal-body .lp-confirmar-lista li').length)"
    Assert-Tmx -Nome 'o modal lista os 4 itens que serao apagados' -Condicao ($linhas -eq '4') -Detalhe "obtido: '$linhas'"
    $avisoLixeira = Get-TmxEval "String(document.querySelectorAll('#modal-body .lp-aviso-perigoso').length)"
    Assert-Tmx -Nome 'sem a Lixeira na selecao, nao ha aviso de perigo' -Condicao ($avisoLixeira -eq '0') -Detalhe "obtido: '$avisoLixeira'"

    Invoke-AB 'click' '#modal-buttons .lp-confirmar' | Out-Null

    $jsLiberado = "(function () { var e = document.getElementById('lp-liberado'); return e ? e.textContent : ''; })()"
    $liberado = Wait-TmxEval -Js $jsLiberado -Ok { param($v) "$v" -match '16\s*KB' } -TimeoutSeconds 60
    Assert-Tmx -Nome 'o resultado mostra 16 KB liberados' -Condicao ("$liberado" -match '16\s*KB') -Detalhe "obtido: '$liberado'"

    Assert-Tmx -Nome 'o arquivo de Temporarios do usuario foi apagado (raiz falsa)' -Condicao (-not (Test-TmxSemente 'temp-usuario'))
    Assert-Tmx -Nome 'o cache do Windows Update (raiz falsa) foi apagado' -Condicao (-not (Test-TmxSemente 'wu-cache'))
    Assert-Tmx -Nome 'a Lixeira (desmarcada) ficou intacta' -Condicao (Test-TmxSemente 'lixeira')
    Assert-Tmx -Nome 'o Prefetch (desmarcado) ficou intacto' -Condicao (Test-TmxSemente 'prefetch')

    $ultima = Wait-TmxEval -Js "document.getElementById('lp-ultima').textContent" -Ok { param($v) "$v" -match '16\s*KB' } -TimeoutSeconds 20
    Assert-Tmx -Nome 'lastCleanup/lastCleanupFreed aparecem no resumo' -Condicao ("$ultima" -match '16\s*KB') -Detalhe "obtido: '$ultima'"

    $reescaneado = Wait-TmxEval -Js "document.getElementById('lp-tam-temp-usuario').textContent" -Ok { param($v) "$v" -match '^0\s*B$' } -TimeoutSeconds 30
    Assert-Tmx -Nome 'depois da limpeza o scan refeito mostra 0 B' -Condicao ("$reescaneado" -match '^0\s*B$') -Detalhe "obtido: '$reescaneado'"

    # --- marcar a Lixeira traz o aviso de perigo ----------------------------------
    Invoke-AB 'scrollintoview' '#lp-chk-lixeira' | Out-Null
    Invoke-AB 'click' '#lp-chk-lixeira' | Out-Null
    Get-TmxEval "document.querySelector('main').scrollTop = 0; 'ok'" | Out-Null
    Invoke-AB 'click' '#lp-limpar' | Out-Null
    Invoke-AB 'wait' '#modal-buttons .lp-confirmar' | Out-Null
    $perigo = Get-TmxEval "String(document.querySelectorAll('#modal-body .lp-aviso-perigoso').length) + '/' + String(document.querySelector('#modal-buttons .lp-confirmar').classList.contains('btn-danger'))"
    Assert-Tmx -Nome 'com a Lixeira marcada o modal avisa e o botao fica vermelho' -Condicao ($perigo -eq '1/true') -Detalhe "obtido: '$perigo'"
    Invoke-AB 'click' '#modal-buttons button:last-child' | Out-Null
    Start-Sleep -Milliseconds 800
    Assert-Tmx -Nome 'cancelar nao apaga nada' -Condicao (Test-TmxSemente 'lixeira')

    # --- idioma ---------------------------------------------------------------------
    Get-TmxEval "tmx.i18n.set('en'); 'ok'" | Out-Null
    $tituloEn = Get-TmxEval "document.querySelector('#tab-limpeza .tmx-titulo').textContent"
    Assert-Tmx -Nome 'em ingles o titulo vira "Free up disk space"' -Condicao ($tituloEn -eq 'Free up disk space') -Detalhe "obtido: '$tituloEn'"
    $itemEn = Get-TmxEval "document.querySelector('#lp-item-lixeira .lp-item-nome').textContent"
    Assert-Tmx -Nome 'em ingles os itens sao traduzidos' -Condicao ($itemEn -like 'Recycle Bin*') -Detalhe "obtido: '$itemEn'"
    Get-TmxEval "tmx.i18n.set('pt-BR'); 'ok'" | Out-Null

    $print = Join-Path (Initialize-TmxGuiOut) 'limpeza.png'
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
    if (Test-Path -LiteralPath $script:RaizFalsa) { Remove-Item -LiteralPath $script:RaizFalsa -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host ''
if ($script:Falhas -gt 0) {
    Write-Host "RESULTADO: $script:Falhas verificacao(oes) falharam." -ForegroundColor Red
    exit 1
}
Write-Host 'RESULTADO: todas as verificacoes passaram.' -ForegroundColor Green
exit 0
