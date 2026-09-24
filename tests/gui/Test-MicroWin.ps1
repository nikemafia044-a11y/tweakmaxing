<#
.SYNOPSIS
    Teste de fumaca da tela MicroWin (v2): abre a janela real e conversa por CDP.
.DESCRIPTION
    Nao e Pester. Sobe a GUI com -TestMode -DebugPort 9342 (porta reservada
    para esta aba), abre a aba MicroWin e confere o layout novo (aviso, "Como
    funciona", "Configurar" com as sete opcoes e os padroes da imagem, os tres
    cards de baixo), os pre-requisitos, a lista de aplicativos removiveis, a
    limpeza das pastas de trabalho, o aviso da senha, a validacao do usuario,
    uma build SIMULADA completa (progresso por etapa, log visivel, resultado),
    o cancelamento no meio (microwin.cancel) e a troca de idioma.

    Nada e gerado de verdade: no modo de teste microwin.info e microwin.build
    so rodam simulados (nenhuma imagem e montada).

    Deixa um print em tests/gui/out/microwin.png. Sai com 1 se qualquer
    verificacao falhar. Sempre fecha a GUI.
.EXAMPLE
    .\tests\gui\Test-MicroWin.ps1
#>
[CmdletBinding()]
param(
    [int] $Port = 9342
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

function Get-TmxTexto {
    param([Parameter(Mandatory)] [string] $Seletor)
    "$(Invoke-AB 'get' 'text' $Seletor)".Trim()
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

function Wait-TmxOcioso {
    # A ponte roda um job por vez: espera a barra de status dizer "Ocioso".
    Wait-TmxCondicao -Segundos 90 { (Get-TmxTexto '#st-job') -match '(?i)ocioso|idle' }
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
        Write-Host "Esperando outro teste de GUI terminar: $($vivos -join ', ')" -ForegroundColor DarkYellow
        Start-Sleep -Seconds 3
    }
}

# ISO falsa (so precisa existir) e pastas de destino.
$pastaTemp = Join-Path ([System.IO.Path]::GetTempPath()) ('tmx-gui-mw-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $pastaTemp -Force | Out-Null
$isoFalsa = Join-Path $pastaTemp 'Win11_24H2.iso'
Set-Content -LiteralPath $isoFalsa -Value 'iso falsa' -Encoding ASCII
$destino1 = (New-Item -ItemType Directory -Path (Join-Path $pastaTemp 'saida1') -Force).FullName
$destino2 = (New-Item -ItemType Directory -Path (Join-Path $pastaTemp 'saida2') -Force).FullName

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

    Invoke-AB 'click' 'nav [data-tab=microwin]' | Out-Null
    Invoke-AB 'wait' '#mw-grid' | Out-Null

    $visivel = "$(Invoke-AB 'is' 'visible' '#tab-microwin')".Trim()
    Assert-Tmx -Nome 'aba MicroWin fica visivel' -Condicao ($visivel -match '(?i)true') -Detalhe "obtido: '$visivel'"

    # --- layout da imagem 04-microwin.png ------------------------------------
    $titulo = Get-TmxTexto '#tab-microwin .mw-titulo'
    Assert-Tmx -Nome 'titulo MicroWin' -Condicao ($titulo -eq 'MicroWin') -Detalhe "obtido: '$titulo'"
    $eyebrow = Get-TmxTexto '#tab-microwin .mw-eyebrow'
    Assert-Tmx -Nome 'sobretitulo Ferramenta avancada' -Condicao ($eyebrow -match '(?i)ferramenta avan') -Detalhe "obtido: '$eyebrow'"
    $info = Get-TmxTexto '#tab-microwin .mw-info'
    Assert-Tmx -Nome 'aviso diz que o Windows em uso nao e tocado' -Condicao ($info -match 'mexe no Windows') -Detalhe "obtido: '$info'"
    $nComo = Get-TmxCount '#tab-microwin .mw-como > li'
    Assert-Tmx -Nome '"Como funciona" tem 5 passos' -Condicao ($nComo -eq 5) -Detalhe "obtido: $nComo"
    $nMini = Get-TmxCount '#tab-microwin .mw-grade3 .mw-card'
    Assert-Tmx -Nome 'tres cards de baixo (ganha, riscos, antes)' -Condicao ($nMini -eq 3) -Detalhe "obtido: $nMini"

    $padroes = Get-TmxEval "['mw-op-apps','mw-op-onedrive','mw-op-edge','mw-op-telemetria','mw-op-conta','mw-op-drivers','mw-op-defender'].map(function(i){return document.getElementById(i).checked?'1':'0';}).join('')"
    Assert-Tmx -Nome 'sete opcoes com os padroes da imagem (5 ligadas, drivers e Defender desligados)' -Condicao ($padroes -eq '1111100') -Detalhe "obtido: '$padroes'"
    $perigo = Get-TmxCount '#tab-microwin .mw-op-perigo #mw-op-defender'
    Assert-Tmx -Nome 'a opcao do Defender e marcada como perigosa (vermelha)' -Condicao ($perigo -eq 1) -Detalhe "obtido: $perigo"

    # --- pre-requisitos -------------------------------------------------------
    Wait-TmxCondicao -Segundos 40 { (Get-TmxCount '#mw-prereq .mw-pre-item') -ge 3 } | Out-Null
    $pre = Get-TmxCount '#mw-prereq .mw-pre-item'
    Assert-Tmx -Nome 'o painel de pre-requisitos lista tres itens' -Condicao ($pre -eq 3) -Detalhe "obtido: $pre"
    $textoPre = Get-TmxTexto '#mw-prereq'
    Assert-Tmx -Nome 'os pre-requisitos citam o oscdimg' -Condicao ($textoPre -match '(?i)oscdimg') -Detalhe "obtido: '$textoPre'"

    # Guarda de regressao: as constantes moram em FUNCAO (variavel de script
    # nao atravessa a runspace da janela).
    $check = Get-TmxEval "window.tmx.bridge.call('microwin.check').then(function(r){return r.espacoMinGB+'|'+(r.urlAdk||'');})"
    Assert-Tmx -Nome 'microwin.check devolve o minimo de 20 GB sem ISO' -Condicao ($check -match '^20\|') -Detalhe "obtido: '$check'"
    Assert-Tmx -Nome 'microwin.check devolve o link do ADK' -Condicao ($check -match 'adk-install') -Detalhe "obtido: '$check'"
    $espacoAntes = Get-TmxTexto '#mw-antes-espaco'
    Assert-Tmx -Nome '"Antes de comecar" mostra o espaco necessario (20 GB sem ISO)' -Condicao ($espacoAntes -match '20 GB') -Detalhe "obtido: '$espacoAntes'"

    # --- aplicativos ----------------------------------------------------------
    Wait-TmxCondicao -Segundos 40 { (Get-TmxCount '#mw-apps .mw-app') -ge 30 } | Out-Null
    $apps = Get-TmxCount '#mw-apps .mw-app'
    Assert-Tmx -Nome 'a lista traz pelo menos 30 aplicativos removiveis' -Condicao ($apps -ge 30) -Detalhe "obtido: $apps"
    $marcadosPadrao = Get-TmxCount '#mw-apps input[type=checkbox]:checked'
    Assert-Tmx -Nome 'com "Remover apps" ligado os recomendados ja vem marcados' -Condicao ($marcadosPadrao -ge 10) -Detalhe "obtido: $marcadosPadrao"
    $calc = Get-TmxEval "(function(){var c=document.querySelectorAll('#mw-apps input[type=checkbox]');for(var i=0;i<c.length;i++){if(c[i].getAttribute('data-pacote')==='Microsoft.WindowsCalculator'){return c[i].checked?'MARCADA':'LIVRE';}}return 'AUSENTE';})()"
    Assert-Tmx -Nome 'a Calculadora fica de fora dos recomendados' -Condicao ($calc -match '(?i)livre') -Detalhe "obtido: '$calc'"

    Invoke-AB 'scrollintoview' '#mw-apps-bloco' | Out-Null
    Invoke-AB 'click' '#mw-apps-bloco > summary' | Out-Null
    Invoke-AB 'click' '#mw-limpar-apps' | Out-Null
    $limpos = Get-TmxCount '#mw-apps input[type=checkbox]:checked'
    Assert-Tmx -Nome '"Limpar" desmarca tudo' -Condicao ($limpos -eq 0) -Detalhe "obtido: $limpos"
    Invoke-AB 'click' '#mw-recomendados' | Out-Null
    $rec = Get-TmxCount '#mw-apps input[type=checkbox]:checked'
    Assert-Tmx -Nome '"Marcar recomendados" marca pelo menos 10' -Condicao ($rec -ge 10) -Detalhe "obtido: $rec"

    Invoke-AB 'uncheck' '#mw-op-apps' | Out-Null
    $escondido = Get-TmxEval "String(document.getElementById('mw-apps-bloco').hidden)"
    Assert-Tmx -Nome 'desligar "Remover apps" esconde a lista' -Condicao ($escondido -eq 'true') -Detalhe "obtido: '$escondido'"
    Invoke-AB 'check' '#mw-op-apps' | Out-Null
    Invoke-AB 'uncheck' '#mw-op-conta' | Out-Null
    $contaOculta = Get-TmxEval "String(document.getElementById('mw-conta-bloco').hidden)"
    Assert-Tmx -Nome 'desligar "conta local" esconde usuario e senha' -Condicao ($contaOculta -eq 'true') -Detalhe "obtido: '$contaOculta'"
    Invoke-AB 'check' '#mw-op-conta' | Out-Null

    # --- limpeza das pastas de trabalho --------------------------------------
    # "Ocioso" na barra de status aparece 4 s depois do ultimo job.done, mas
    # outra aba pode abrir um job nesse meio tempo: a acao recusa ("espere o
    # trabalho atual terminar") e o teste tenta de novo, ate 5 vezes.
    Assert-Tmx -Nome 'a ponte fica ociosa antes da limpeza' -Condicao (Wait-TmxOcioso)
    $toast = ''
    $tituloModal = ''
    for ($tentativa = 1; $tentativa -le 5; $tentativa++) {
        Get-TmxEval "document.getElementById('toasts').innerHTML = ''; 'limpo'" | Out-Null
        Invoke-AB 'scrollintoview' '#mw-limpar-trabalho' | Out-Null
        Invoke-AB 'click' '#mw-limpar-trabalho' | Out-Null
        Invoke-AB 'wait' '#modal-buttons .btn-danger' | Out-Null
        $tituloModal = Get-TmxTexto '#modal-title'
        Invoke-AB 'click' '#modal-buttons .btn-danger' | Out-Null
        Wait-TmxCondicao -Segundos 15 { [bool](Get-TmxTexto '#toasts') } | Out-Null
        $toast = Get-TmxTexto '#toasts'
        if ($toast -notmatch '(?i)espere o trabalho') { break }
        Start-Sleep -Seconds 2
        Wait-TmxOcioso | Out-Null
    }
    Assert-Tmx -Nome 'o botao de limpeza abre o modal de confirmacao' -Condicao ($tituloModal -match '(?i)limpar pastas') -Detalhe "obtido: '$tituloModal'"
    Assert-Tmx -Nome 'microwin.cleanupWorkDirs limpa de verdade pela ponte' -Condicao ($toast -match '(?i)nada a limpar|apagada') -Detalhe "toast: '$toast'"

    # --- aviso da senha e validacao do usuario --------------------------------
    $avisoSenha = Get-TmxTexto '.mw-aviso-senha'
    Assert-Tmx -Nome 'o aviso diz que a senha fica em texto puro no autounattend.xml' `
        -Condicao (($avisoSenha -match '(?i)texto puro') -and ($avisoSenha -match '(?i)autounattend')) -Detalhe "obtido: '$avisoSenha'"
    Assert-Tmx -Nome 'o aviso manda guardar a ISO como dado sensivel e trocar a senha' `
        -Condicao (($avisoSenha -match '(?i)sens') -and ($avisoSenha -match '(?i)troque a senha')) -Detalhe "obtido: '$avisoSenha'"

    Invoke-AB 'scrollintoview' '#mw-usuario' | Out-Null
    Invoke-AB 'fill' '#mw-usuario' '1fantasy' | Out-Null
    $temErro = Wait-TmxCondicao -Segundos 10 { [bool](Get-TmxTexto '#mw-erro-usuario') }
    Assert-Tmx -Nome 'um nome de usuario invalido mostra erro de validacao' -Condicao $temErro
    Invoke-AB 'fill' '#mw-usuario' 'fantasy' | Out-Null
    $semErro = Wait-TmxCondicao -Segundos 10 { -not (Get-TmxTexto '#mw-erro-usuario') }
    Assert-Tmx -Nome 'um nome de usuario valido limpa o erro' -Condicao $semErro

    # --- a ponte recusa a build de verdade no modo de teste --------------------
    $recusa = Get-TmxEval "window.tmx.bridge.call('microwin.build',{iso:'C:\\\\x.iso',edicao:1,usuario:'fantasy',senha:'abc',destino:'C:\\\\'}).then(function(){return 'ACEITOU';},function(e){return 'RECUSOU: '+e.message;})"
    Assert-Tmx -Nome 'microwin.build recusa uma ISO inexistente pela ponte' -Condicao ($recusa -match '(?i)recusou') -Detalhe "obtido: '$recusa'"

    # --- ISO: escolher + ler edicoes (simulado) ------------------------------
    Assert-Tmx -Nome 'a ponte fica ociosa antes de ler a ISO' -Condicao (Wait-TmxOcioso)
    Invoke-AB 'scrollintoview' '#mw-iso' | Out-Null
    Invoke-AB 'fill' '#mw-iso' $isoFalsa | Out-Null
    Invoke-AB 'click' '#mw-escolher' | Out-Null
    $leu = Wait-TmxCondicao -Segundos 30 { (Get-TmxCount '#mw-edicao option') -eq 3 }
    Assert-Tmx -Nome 'ler a ISO preenche as edicoes' -Condicao $leu
    $edicao = Get-TmxEval "document.getElementById('mw-edicao').selectedOptions[0].text"
    Assert-Tmx -Nome 'Windows 11 Pro vem escolhido por padrao' -Condicao ($edicao -match 'Windows 11 Pro') -Detalhe "obtido: '$edicao'"
    $recalc = Wait-TmxCondicao -Segundos 15 { (Get-TmxTexto '#mw-antes-espaco') -match '\b5 GB' }
    Assert-Tmx -Nome 'com a ISO o espaco vira tamanho x 3 + 5 GB' -Condicao $recalc -Detalhe "obtido: '$(Get-TmxTexto '#mw-antes-espaco')'"

    # --- build simulada completa ----------------------------------------------
    Invoke-AB 'fill' '#mw-senha' 'Abc12345' | Out-Null
    Invoke-AB 'fill' '#mw-senha2' 'Abc12345' | Out-Null
    Invoke-AB 'fill' '#mw-destino' $destino1 | Out-Null
    Get-TmxEval "window.tmxMicroWinAtrasoMs = 150; 'ok'" | Out-Null
    Invoke-AB 'scrollintoview' '#mw-gerar' | Out-Null
    Invoke-AB 'click' '#mw-gerar' | Out-Null
    Invoke-AB 'wait' '#modal-buttons .btn-primary' | Out-Null
    $resumo = Get-TmxTexto '#modal-body'
    Assert-Tmx -Nome 'o resumo lista as opcoes ligadas' -Condicao ($resumo -match 'OneDrive' -and $resumo -match 'Edge' -and $resumo -match 'telemetria') -Detalhe "obtido: '$resumo'"
    Invoke-AB 'click' '#modal-buttons .btn-primary' | Out-Null

    $progVisivel = Wait-TmxCondicao -Segundos 10 { (Get-TmxEval "String(!document.getElementById('mw-prog').hidden)") -eq 'true' }
    Assert-Tmx -Nome 'o painel de progresso aparece' -Condicao $progVisivel
    $terminou = Wait-TmxCondicao -Segundos 60 { ((Get-TmxTexto '#modal-title') -match '(?i)ISO gerada') -and ("$(Invoke-AB 'is' 'visible' '#modal')" -match '(?i)true') }
    Assert-Tmx -Nome 'a build simulada termina com "ISO gerada"' -Condicao $terminou -Detalhe "titulo: '$(Get-TmxTexto '#modal-title')'"
    Assert-Tmx -Nome 'a build simulada escreve so o arquivo de simulacao' -Condicao (Test-Path -LiteralPath (Join-Path $destino1 'microwin-simulado.txt'))
    $linhasLog = 0
    [void][int]::TryParse((Get-TmxEval "String(document.getElementById('mw-log').textContent.split('\n').filter(function(l){return l;}).length)"), [ref]$linhasLog)
    Assert-Tmx -Nome 'o log visivel registra as etapas' -Condicao ($linhasLog -ge 8) -Detalhe "linhas: $linhasLog"
    $etapas = Get-TmxTexto '#mw-etapas'
    Assert-Tmx -Nome 'as etapas das opcoes aparecem no resultado' -Condicao ($etapas -match 'remover-onedrive' -and $etapas -match 'telemetria' -and $etapas -notmatch 'remover-defender') -Detalhe "obtido: '$etapas'"
    $barra = Get-TmxEval "document.getElementById('mw-barra').getAttribute('aria-valuenow')"
    Assert-Tmx -Nome 'a barra chega a 100%' -Condicao ($barra -eq '100') -Detalhe "obtido: '$barra'"
    Invoke-AB 'click' '#modal-buttons button' | Out-Null

    $print = Join-Path (Initialize-TmxGuiOut) 'microwin.png'
    Invoke-AB 'scrollintoview' '#tab-microwin .mw-topo' | Out-Null
    Invoke-AB 'screenshot' $print | Out-Null
    Assert-Tmx -Nome 'screenshot gravado' -Condicao (Test-Path -LiteralPath $print) -Detalhe $print
    Write-Host "Print: $print"

    # --- Defender: aviso vermelho no resumo -------------------------------------
    Assert-Tmx -Nome 'a ponte fica ociosa depois da build' -Condicao (Wait-TmxOcioso)
    Invoke-AB 'scrollintoview' '#mw-op-defender' | Out-Null
    Invoke-AB 'check' '#mw-op-defender' | Out-Null
    Invoke-AB 'scrollintoview' '#mw-gerar' | Out-Null
    Invoke-AB 'click' '#mw-gerar' | Out-Null
    Invoke-AB 'wait' '#modal-buttons button' | Out-Null
    $alerta = Get-TmxCount '#modal-body .mw-alerta-defender'
    Assert-Tmx -Nome 'com o Defender marcado o resumo mostra o alerta vermelho' -Condicao ($alerta -eq 1) -Detalhe "obtido: $alerta"
    Invoke-AB 'click' '#modal-buttons button:last-child' | Out-Null
    Invoke-AB 'scrollintoview' '#mw-op-defender' | Out-Null
    Invoke-AB 'uncheck' '#mw-op-defender' | Out-Null

    # --- cancelamento no meio ------------------------------------------------------
    Invoke-AB 'fill' '#mw-destino' $destino2 | Out-Null
    Get-TmxEval "window.tmxMicroWinAtrasoMs = 700; 'ok'" | Out-Null
    Invoke-AB 'scrollintoview' '#mw-gerar' | Out-Null
    Invoke-AB 'click' '#mw-gerar' | Out-Null
    Invoke-AB 'wait' '#modal-buttons .btn-primary' | Out-Null
    Invoke-AB 'click' '#modal-buttons .btn-primary' | Out-Null
    $cancelVisivel = Wait-TmxCondicao -Segundos 15 { (Get-TmxEval "String(!document.getElementById('mw-cancelar').hidden && document.getElementById('mw-log').textContent.length > 0)") -eq 'true' }
    Assert-Tmx -Nome 'o botao Cancelar aparece durante a build' -Condicao $cancelVisivel
    Start-Sleep -Milliseconds 800
    Invoke-AB 'scrollintoview' '#mw-cancelar' | Out-Null
    Invoke-AB 'click' '#mw-cancelar' | Out-Null
    $cancelou = Wait-TmxCondicao -Segundos 40 { ((Get-TmxTexto '#modal-title') -match '(?i)cancelada') -and ("$(Invoke-AB 'is' 'visible' '#modal')" -match '(?i)true') }
    Assert-Tmx -Nome 'microwin.cancel interrompe a build (modal "Geracao cancelada")' -Condicao $cancelou -Detalhe "titulo: '$(Get-TmxTexto '#modal-title')'"
    Assert-Tmx -Nome 'a build cancelada nao grava nada no destino' -Condicao (-not (Test-Path -LiteralPath (Join-Path $destino2 'microwin-simulado.txt')))
    Invoke-AB 'click' '#modal-buttons button' | Out-Null

    # --- idioma --------------------------------------------------------------
    Get-TmxEval "tmx.i18n.set('en'); 'ok'" | Out-Null
    Start-Sleep -Milliseconds 300
    $comoEn = Get-TmxTexto '#mw-h-como'
    Assert-Tmx -Nome 'em ingles "Como funciona" vira "How it works"' -Condicao ($comoEn -eq 'How it works') -Detalhe "obtido: '$comoEn'"
    $opEn = Get-TmxTexto 'label[for=mw-op-onedrive]'
    Assert-Tmx -Nome 'em ingles as opcoes sao traduzidas' -Condicao ($opEn -eq 'Remove OneDrive') -Detalhe "obtido: '$opEn'"
    Get-TmxEval "tmx.i18n.set('pt-BR'); 'ok'" | Out-Null

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
