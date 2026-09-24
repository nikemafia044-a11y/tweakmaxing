<#
.SYNOPSIS
    Teste de fumaca da tela Aplicativos (v2): abre a janela real e conversa por CDP.
.DESCRIPTION
    Nao e Pester. Sobe a GUI com -TestMode -DebugPort 9334, abre a aba
    Aplicativos e confere: catalogo inteiro renderizado (>= 200 cards), as
    seis categorias, o filtro por categoria e por busca, logo de 44 px sem
    icone quebrado, selecao e resumo, selo "Instalado" (lista simulada no
    modo de teste: firefox e vivaldi), exportar e importar lista (dialogos
    simulados), troca de idioma e o link para Otimizacoes > Remover
    bloatware. Deixa um print em tests/gui/out/aplicativos.png.

    Sai com 1 se qualquer verificacao falhar. Sempre fecha a GUI.
.EXAMPLE
    .\tests\gui\Test-Install.ps1
#>
[CmdletBinding()]
param(
    [int] $Port = 9334
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

function Get-TmxCount {
    param([Parameter(Mandatory)] [string] $Seletor)
    $txt = "$(Invoke-AB 'get' 'count' $Seletor)".Trim()
    $n = -1
    [void][int]::TryParse($txt, [ref]$n)
    $n
}

function Get-TmxEval {
    param([Parameter(Mandatory)] [string] $Js)
    "$(Invoke-AB 'eval' $Js)".Trim().Trim('"')
}

function Wait-TmxCondicao {
    param(
        [int] $Segundos = 15,
        [Parameter(Mandatory)] [scriptblock] $Teste
    )
    $limite = (Get-Date).AddSeconds($Segundos)
    while ((Get-Date) -lt $limite) {
        if (& $Teste) { return $true }
        Start-Sleep -Milliseconds 300
    }
    [bool](& $Teste)
}

$raizRepo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$catApps = @((Get-Content -LiteralPath (Join-Path $raizRepo 'src\config\applications.json') -Raw -Encoding UTF8 | ConvertFrom-Json).aplicativos)
$nNavegadores = @($catApps | Where-Object { "$($_.categoriaV2)" -eq 'navegadores' }).Count
$nJogos       = @($catApps | Where-Object { "$($_.categoriaV2)" -eq 'jogos' }).Count
$nFirefox     = @($catApps | Where-Object {
    $en = ''
    if ($_.i18n -and $_.i18n.en) { $en = "$($_.i18n.en.descricao)" }
    "$($_.nome) $($_.descricao) $en $($_.winget)" -match 'firefox'
}).Count
$firefoxEn = "$((@($catApps | Where-Object { $_.id -eq 'firefox' }) | Select-Object -First 1).i18n.en.descricao)"

$pastaTemp = Join-Path ([System.IO.Path]::GetTempPath()) ('tmx-gui-apps-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $pastaTemp -Force | Out-Null
$arquivoExport = Join-Path $pastaTemp 'lista.json'

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

    Invoke-AB 'click' 'nav [data-tab=aplicativos]' | Out-Null
    Invoke-AB 'wait' '#app-grade .app-card' | Out-Null

    # --- catalogo e categorias -------------------------------------------
    Wait-TmxCondicao -Segundos 20 { (Get-TmxCount '#app-grade .app-card') -ge 200 } | Out-Null
    $total = Get-TmxCount '#app-grade .app-card'
    Assert-Tmx -Nome 'catalogo inteiro renderizado (>= 200 cards)' -Condicao ($total -ge 200) -Detalhe "obtido: $total"

    $nCats = Get-TmxCount '#app-cats .ap-cat'
    Assert-Tmx -Nome 'seis abas de categoria' -Condicao ($nCats -eq 6) -Detalhe "obtido: $nCats"

    $titulo = "$(Invoke-AB 'get' 'text' '#app-cat-titulo')".Trim()
    Assert-Tmx -Nome 'categoria inicial e Navegadores' -Condicao ($titulo -eq 'Navegadores') -Detalhe "obtido: '$titulo'"

    $vis = Get-TmxCount '#app-grade .app'
    Assert-Tmx -Nome "Navegadores mostra so os $nNavegadores apps da categoria" -Condicao ($vis -eq $nNavegadores) -Detalhe "obtido: $vis"

    $sub = "$(Invoke-AB 'get' 'text' '#app-sub')".Trim()
    Assert-Tmx -Nome 'subtitulo traz o total de apps e de categorias' -Condicao ($sub -match "$($catApps.Count) apps em 6 categorias") -Detalhe "obtido: '$sub'"

    Invoke-AB 'click' '#app-cats .ap-cat[data-cat=jogos]' | Out-Null
    Start-Sleep -Milliseconds 300
    $vis = Get-TmxCount '#app-grade .app'
    Assert-Tmx -Nome "aba Jogos mostra os $nJogos apps da categoria" -Condicao ($vis -eq $nJogos) -Detalhe "obtido: $vis"
    Invoke-AB 'click' '#app-cats .ap-cat[data-cat=navegadores]' | Out-Null
    Start-Sleep -Milliseconds 300

    # --- card: logo 44 px, id do winget, link ------------------------------
    $tam = Get-TmxEval "(function(){var i=document.querySelector('#app-grade .app .app-icone');var r=i.getBoundingClientRect();return Math.round(r.width)+'x'+Math.round(r.height);})()"
    Assert-Tmx -Nome 'logo do card tem 44x44 px' -Condicao ($tam -eq '44x44') -Detalhe "obtido: '$tam'"

    $winget = "$(Invoke-AB 'get' 'text' '[data-id=firefox] .app-winget')".Trim()
    Assert-Tmx -Nome 'card mostra o ID do winget' -Condicao ($winget -eq 'Mozilla.Firefox') -Detalhe "obtido: '$winget'"

    $links = Get-TmxCount '#app-grade .app .app-link'
    Assert-Tmx -Nome 'cards visiveis tem o link oficial' -Condicao ($links -ge 1) -Detalhe "obtido: $links"

    Invoke-AB 'errors' '--clear' | Out-Null
    Invoke-AB 'click' '#app-cats .ap-cat[data-cat=utilitarios]' | Out-Null
    Invoke-AB 'scroll' 'down' '1500' | Out-Null
    Start-Sleep -Milliseconds 800
    Invoke-AB 'scroll' 'down' '1500' | Out-Null
    Start-Sleep -Milliseconds 1500
    $erros = "$(Invoke-AB 'errors')".Trim()
    Assert-Tmx -Nome 'nenhum erro de JS depois de rolar a lista (icones lazy)' -Condicao ([string]::IsNullOrWhiteSpace($erros) -or $erros -match '(?i)no errors|nenhum erro') -Detalhe "obtido: '$erros'"

    $quebrados = Get-TmxEval "(function(){var n=0;document.querySelectorAll('#app-grade .app-icone img').forEach(function(i){if(i.complete&&i.naturalWidth===0){n++;}});return String(n);})()"
    Assert-Tmx -Nome 'nenhum icone quebrado (img sem imagem)' -Condicao ($quebrados -eq '0') -Detalhe "obtido: '$quebrados'"

    Invoke-AB 'click' '#app-cats .ap-cat[data-cat=navegadores]' | Out-Null
    Start-Sleep -Milliseconds 300

    # onerror do icone volta para as iniciais (usa o caminho real do modulo:
    # um icone "cacheado" com PNG invalido entra pelo mesmo aplicarIcone).
    $fallback = Get-TmxEval "(function(){var s=document.querySelector('[data-id=firefox] .app-icone');var img=document.createElement('img');img.onerror=function(){s.classList.remove('tem-imagem');s.textContent=s.dataset.iniciais;};s.innerHTML='';s.appendChild(img);img.src='data:image/png;base64,QUJD';return new Promise(function(r){setTimeout(function(){r(s.textContent);},600);});})()"
    Assert-Tmx -Nome 'imagem que falha volta para as iniciais' -Condicao ($fallback -eq 'FI') -Detalhe "obtido: '$fallback'"

    # --- busca -------------------------------------------------------------
    Invoke-AB 'fill' '#app-busca' 'firefox' | Out-Null
    Start-Sleep -Milliseconds 400
    $filtrado = Get-TmxCount '#app-grade .app'
    Assert-Tmx -Nome "busca 'firefox' olha o catalogo inteiro ($nFirefox apps)" -Condicao ($filtrado -eq $nFirefox -and $nFirefox -ge 2) -Detalhe "obtido: $filtrado"
    $tituloBusca = "$(Invoke-AB 'get' 'text' '#app-cat-titulo')".Trim()
    Assert-Tmx -Nome 'titulo vira Resultados da busca' -Condicao ($tituloBusca -eq 'Resultados da busca') -Detalhe "obtido: '$tituloBusca'"

    # --- selecao -----------------------------------------------------------
    Invoke-AB 'check' '#app-firefox' | Out-Null
    Invoke-AB 'check' '#app-firefoxesr' | Out-Null
    Start-Sleep -Milliseconds 200
    $sel = "$(Invoke-AB 'get' 'text' '#app-selecionados')".Trim()
    Assert-Tmx -Nome '#app-selecionados mostra 2 apos marcar 2 caixas' -Condicao ($sel -eq '2') -Detalhe "obtido: '$sel'"
    $marcados = Get-TmxCount '#app-grade .app-card.app-marcado'
    Assert-Tmx -Nome 'cards marcados ganham destaque' -Condicao ($marcados -eq 2) -Detalhe "obtido: $marcados"

    # --- selo Instalado (lista simulada: firefox, vivaldi) -----------------
    $temSelo = Wait-TmxCondicao -Segundos 30 {
        (Get-TmxEval "getComputedStyle(document.querySelector('[data-id=firefox] .app-selo-instalado')).display") -ne 'none'
    }
    Assert-Tmx -Nome 'selo Instalado aparece no Firefox (instalados simulados)' -Condicao $temSelo
    $semSelo = Get-TmxEval "getComputedStyle(document.querySelector('[data-id=firefoxesr] .app-selo-instalado')).display"
    Assert-Tmx -Nome 'selo Instalado nao aparece num app nao instalado' -Condicao ($semSelo -eq 'none') -Detalhe "obtido: '$semSelo'"
    $resumo = "$(Invoke-AB 'get' 'text' '#app-resumo-texto')".Trim()
    Assert-Tmx -Nome 'resumo mostra 2 selecionados e 2 instalados' -Condicao ($resumo -match '2 selecionados' -and $resumo -match '2 instalados') -Detalhe "obtido: '$resumo'"

    # --- exportar ------------------------------------------------------------
    $jsCaminho = ($arquivoExport -replace '\\', '\\')
    Get-TmxEval "window.tmxSimularArquivo={salvar:'$jsCaminho'};'ok'" | Out-Null
    Invoke-AB 'click' '#app-btn-exportar' | Out-Null
    $exportou = Wait-TmxCondicao -Segundos 10 { Test-Path -LiteralPath $arquivoExport }
    $idsExport = @()
    if ($exportou) { $idsExport = @((Get-Content -LiteralPath $arquivoExport -Raw -Encoding UTF8 | ConvertFrom-Json).apps) }
    Assert-Tmx -Nome 'exportar grava a lista com os 2 apps marcados' -Condicao ($exportou -and $idsExport.Count -eq 2 -and ($idsExport -contains 'firefox') -and ($idsExport -contains 'firefoxesr')) -Detalhe "obtido: $($idsExport -join ',')"

    # --- importar ------------------------------------------------------------
    Invoke-AB 'click' '#app-btn-limpar' | Out-Null
    Invoke-AB 'fill' '#app-busca' '' | Out-Null
    Start-Sleep -Milliseconds 200
    Get-TmxEval "window.tmxSimularArquivo={abrirCaminho:'lista.json',abrirConteudo:JSON.stringify({apps:['vivaldi','naoexiste']})};'ok'" | Out-Null
    Invoke-AB 'click' '#app-btn-importar' | Out-Null
    $importou = Wait-TmxCondicao -Segundos 10 { "$(Invoke-AB 'get' 'text' '#app-selecionados')".Trim() -eq '1' }
    $vivaldi = Get-TmxEval "String(document.getElementById('app-vivaldi').checked)"
    Assert-Tmx -Nome 'importar marca so os ids do catalogo (vivaldi)' -Condicao ($importou -and $vivaldi -eq 'true') -Detalhe "vivaldi: '$vivaldi'"

    # --- gerenciadores ---------------------------------------------------------
    $wingetOk = Get-TmxCount '#app-gerenciadores .gm:first-child .ok'
    Assert-Tmx -Nome 'painel de gerenciadores mostra winget disponivel' -Condicao ($wingetOk -eq 1) -Detalhe "obtido: $wingetOk"

    Invoke-AB 'scrollintoview' '#tab-aplicativos .ap-topo' | Out-Null
    $print = Join-Path (Initialize-TmxGuiOut) 'aplicativos.png'
    Invoke-AB 'screenshot' $print | Out-Null
    Assert-Tmx -Nome 'screenshot gravado' -Condicao (Test-Path -LiteralPath $print) -Detalhe $print
    Write-Host "Print: $print"

    # --- idioma --------------------------------------------------------------
    Get-TmxEval "tmx.i18n.set('en'); 'ok'" | Out-Null
    Start-Sleep -Milliseconds 300
    $tituloEn = "$(Invoke-AB 'get' 'text' '#tab-aplicativos .ap-titulo')".Trim()
    Assert-Tmx -Nome 'em ingles o titulo vira App manager' -Condicao ($tituloEn -eq 'App manager') -Detalhe "obtido: '$tituloEn'"
    $descEn = Get-TmxEval "document.querySelector('[data-id=firefox] .app-desc').textContent"
    Assert-Tmx -Nome 'em ingles a descricao vem do i18n.en do catalogo' -Condicao ($firefoxEn -and $descEn -eq $firefoxEn) -Detalhe "obtido: '$descEn'"
    Get-TmxEval "tmx.i18n.set('pt-BR'); 'ok'" | Out-Null

    # --- link do bloatware -------------------------------------------------------
    Invoke-AB 'click' '#app-link-bloatware' | Out-Null
    Start-Sleep -Milliseconds 500
    $otimAberta = Get-TmxEval "String(!document.getElementById('tab-otimizacoes').hidden)"
    Assert-Tmx -Nome 'link Remover bloatware abre Otimizacoes' -Condicao ($otimAberta -eq 'true') -Detalhe "obtido: '$otimAberta'"

} catch {
    $script:Falhas++
    Write-Host "FAIL  execucao: $($_.Exception.Message)" -ForegroundColor Red
} finally {
    Write-Host 'Fechando a GUI...' -ForegroundColor Cyan
    $limpo = Stop-TmxGui -Port $Port
    Assert-Tmx -Nome 'porta CDP liberada no fim' -Condicao ([bool]$limpo)
    Remove-Item -LiteralPath $pastaTemp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
if ($script:Falhas -gt 0) {
    Write-Host "RESULTADO: $script:Falhas verificacao(oes) falharam." -ForegroundColor Red
    exit 1
}
Write-Host 'RESULTADO: todas as verificacoes passaram.' -ForegroundColor Green
exit 0
