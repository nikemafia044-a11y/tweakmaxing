<#
.SYNOPSIS
    Teste de fumaca da aba MicroWin: abre a janela real e conversa por CDP.
.DESCRIPTION
    Nao e Pester. Sobe a GUI com -TestMode -DebugPort 9342 (porta reservada
    para esta aba), clica na aba MicroWin e confere o aviso de operacao
    avancada, o painel de pre-requisitos, a lista de aplicativos removiveis,
    o botao "Marcar recomendados" e a validacao do nome de usuario.

    Nada e gerado: no modo de teste microwin.build recusa a build de verdade e
    so aceita a simulacao, e este teste nem chega a dispara-la.

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

function ConvertTo-TmxInt {
    param([string] $Texto)
    $n = -1
    [int]::TryParse("$Texto".Trim(), [ref]$n) | Out-Null
    $n
}

function Wait-TmxContagem {
    <#
    .SYNOPSIS
        Espera 'get count <seletor>' chegar a um minimo (a lista de
        aplicativos e os pre-requisitos chegam pela ponte, entao a primeira
        leitura pode pegar a tela vazia).
    #>
    param(
        [Parameter(Mandatory)] [string] $Seletor,
        [Parameter(Mandatory)] [int]    $Minimo,
        [int] $TimeoutSeconds = 40
    )
    $limite = (Get-Date).AddSeconds($TimeoutSeconds)
    $ultimo = '0'
    while ((Get-Date) -lt $limite) {
        $ultimo = "$(Invoke-AB 'get' 'count' $Seletor)".Trim()
        if ((ConvertTo-TmxInt $ultimo) -ge $Minimo) { break }
        Start-Sleep -Milliseconds 400
    }
    $ultimo
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

    Invoke-AB 'click' 'nav [data-tab=microwin]' | Out-Null
    Invoke-AB 'wait' '#mw-grid' | Out-Null

    $visivel = "$(Invoke-AB 'is' 'visible' '#tab-microwin')".Trim()
    Assert-Tmx -Nome 'aba MicroWin fica visivel' -Condicao ($visivel -match '(?i)true') -Detalhe "obtido: '$visivel'"

    # --- aviso de operacao avancada ----------------------------------------
    $banner = "$(Invoke-AB 'get' 'text' '.mw-banner')".Trim()
    Assert-Tmx -Nome 'o aviso diz que a operacao e avancada e demorada' `
        -Condicao ($banner -match '20 a 60') -Detalhe "obtido: '$banner'"
    Assert-Tmx -Nome 'o aviso promete que a ISO original nao e alterada' `
        -Condicao ($banner -match '(?i)original') -Detalhe "obtido: '$banner'"
    Assert-Tmx -Nome 'o aviso cita o Windows ADK' `
        -Condicao ($banner -match '(?i)ADK') -Detalhe "obtido: '$banner'"

    # --- pre-requisitos -----------------------------------------------------
    $pre = Wait-TmxContagem -Seletor '#mw-prereq .mw-pre-item' -Minimo 3
    Assert-Tmx -Nome 'o painel de pre-requisitos lista tres itens' `
        -Condicao ((ConvertTo-TmxInt $pre) -eq 3) -Detalhe "obtido: '$pre'"

    $textoPre = "$(Invoke-AB 'get' 'text' '#mw-prereq')".Trim()
    Assert-Tmx -Nome 'os pre-requisitos citam o oscdimg' `
        -Condicao ($textoPre -match '(?i)oscdimg') -Detalhe "obtido: '$textoPre'"

    # As constantes da aba moram em FUNCAO e nao em '$script:Tmx...': variavel
    # de escopo de script nao atravessa a runspace da janela e chegaria null
    # aqui (minimo de espaco 0, link do ADK vazio, regex de usuario "casa com
    # tudo"). Este eval e a guarda de regressao disso.
    $check = "$(Invoke-AB 'eval' "window.tmx.bridge.call('microwin.check').then(function(r){return r.espacoMinGB+'|'+(r.urlAdk||'');})")".Trim()
    Assert-Tmx -Nome 'microwin.check devolve o minimo de 20 GB pela runspace da janela' `
        -Condicao ($check -match '^\\?"?20\|') -Detalhe "obtido: '$check'"
    Assert-Tmx -Nome 'microwin.check devolve o link do ADK pela runspace da janela' `
        -Condicao ($check -match 'adk-install') -Detalhe "obtido: '$check'"

    # --- aplicativos --------------------------------------------------------
    $apps = Wait-TmxContagem -Seletor '#mw-apps .mw-app' -Minimo 30
    Assert-Tmx -Nome 'a lista traz pelo menos 30 aplicativos removiveis' `
        -Condicao ((ConvertTo-TmxInt $apps) -ge 30) -Detalhe "obtido: '$apps'"

    $marcadosAntes = "$(Invoke-AB 'get' 'count' '#mw-apps input[type=checkbox]:checked')".Trim()
    Assert-Tmx -Nome 'nenhum aplicativo vem marcado por padrao' `
        -Condicao ((ConvertTo-TmxInt $marcadosAntes) -eq 0) -Detalhe "obtido: '$marcadosAntes'"

    Invoke-AB 'click' '#mw-recomendados' | Out-Null
    $marcadosDepois = Wait-TmxContagem -Seletor '#mw-apps input[type=checkbox]:checked' -Minimo 10 -TimeoutSeconds 10
    Assert-Tmx -Nome '"Marcar recomendados" marca pelo menos 10 aplicativos' `
        -Condicao ((ConvertTo-TmxInt $marcadosDepois) -ge 10) -Detalhe "obtido: '$marcadosDepois'"

    # A Calculadora nunca entra no preset recomendado.
    $calc = "$(Invoke-AB 'eval' "(function(){var c=document.querySelectorAll('#mw-apps input[type=checkbox]');for(var i=0;i<c.length;i++){if(c[i].getAttribute('data-pacote')==='Microsoft.WindowsCalculator'){return c[i].checked?'MARCADA':'LIVRE';}}return 'AUSENTE';})()")".Trim()
    Assert-Tmx -Nome 'a Calculadora fica de fora dos recomendados' `
        -Condicao ($calc -match '(?i)livre') -Detalhe "obtido: '$calc'"

    Invoke-AB 'click' '#mw-limpar-apps' | Out-Null
    $limpos = "$(Invoke-AB 'get' 'count' '#mw-apps input[type=checkbox]:checked')".Trim()
    Assert-Tmx -Nome '"Limpar" desmarca tudo' `
        -Condicao ((ConvertTo-TmxInt $limpos) -eq 0) -Detalhe "obtido: '$limpos'"

    # --- limpeza das pastas de trabalho -------------------------------------
    # No modo de teste a raiz de trabalho fica dentro do TWEAKMAXING_HOME da
    # suite, entao apagar tudo ali nao toca em nada do usuario.
    #
    # Esperar a ponte ficar ociosa NAO e frescura: a acao recusa enquanto ha
    # job ativo (a pasta de trabalho de um build sumiria no meio), e as outras
    # abas ainda estao carregando os catalogos delas quando esta roda. Sem a
    # espera o teste media a mensagem de recusa em vez da limpeza.
    $limite = (Get-Date).AddSeconds(90)
    $trabalho = ''
    while ((Get-Date) -lt $limite) {
        $trabalho = "$(Invoke-AB 'get' 'text' '#st-job')".Trim()
        if ($trabalho -match '(?i)ocioso') { break }
        Start-Sleep -Milliseconds 500
    }
    Assert-Tmx -Nome 'a ponte fica ociosa antes da limpeza' `
        -Condicao ($trabalho -match '(?i)ocioso') -Detalhe "obtido: '$trabalho'"

    Invoke-AB 'eval' "document.getElementById('toasts').innerHTML = ''; 'limpo'" | Out-Null

    # O cabecalho e fixo: sem rolar ate o botao o clique pode cair nele.
    Invoke-AB 'scrollintoview' '#mw-limpar-trabalho' | Out-Null
    Invoke-AB 'click' '#mw-limpar-trabalho' | Out-Null
    Invoke-AB 'wait' '#modal-buttons .btn-danger' | Out-Null

    $tituloModal = "$(Invoke-AB 'get' 'text' '#modal-title')".Trim()
    Assert-Tmx -Nome 'o botao de limpeza abre o modal de confirmacao' `
        -Condicao ($tituloModal -match '(?i)limpar pastas') -Detalhe "obtido: '$tituloModal'"

    Invoke-AB 'click' '#modal-buttons .btn-danger' | Out-Null

    $limite = (Get-Date).AddSeconds(15)
    $toast = ''
    while ((Get-Date) -lt $limite) {
        $toast = "$(Invoke-AB 'get' 'text' '#toasts')".Trim()
        if ($toast) { break }
        Start-Sleep -Milliseconds 400
    }
    # A mensagem tem que ser a da LIMPEZA ('Nada a limpar' quando nao havia
    # pasta, ou 'N pasta(s) ... apagada(s)') - nunca a recusa por job ativo.
    Assert-Tmx -Nome 'microwin.cleanupWorkDirs limpa de verdade pela ponte' `
        -Condicao ($toast -match '(?i)nada a limpar|apagada') -Detalhe "toast: '$toast'"

    $modalAberto = "$(Invoke-AB 'is' 'visible' '#modal')".Trim()
    Assert-Tmx -Nome 'o modal de limpeza fecha sozinho' `
        -Condicao ($modalAberto -notmatch '(?i)true') -Detalhe "obtido: '$modalAberto'"

    # --- aviso da senha em texto puro ---------------------------------------
    $quantosAvisos = "$(Invoke-AB 'get' 'count' '.mw-aviso-senha')".Trim()
    Assert-Tmx -Nome 'o bloco de conta local traz o aviso da senha' `
        -Condicao ((ConvertTo-TmxInt $quantosAvisos) -eq 1) -Detalhe "obtido: '$quantosAvisos'"

    $avisoSenha = "$(Invoke-AB 'get' 'text' '.mw-aviso-senha')".Trim()
    Assert-Tmx -Nome 'o aviso diz que a senha fica em texto puro no autounattend.xml' `
        -Condicao (($avisoSenha -match '(?i)texto puro') -and ($avisoSenha -match '(?i)autounattend')) `
        -Detalhe "obtido: '$avisoSenha'"
    Assert-Tmx -Nome 'o aviso manda guardar a ISO como dado sensivel' `
        -Condicao ($avisoSenha -match '(?i)sens') -Detalhe "obtido: '$avisoSenha'"
    Assert-Tmx -Nome 'o aviso lembra que da para trocar a senha depois da instalacao' `
        -Condicao ($avisoSenha -match '(?i)troque a senha') -Detalhe "obtido: '$avisoSenha'"

    # --- validacao do nome de usuario ---------------------------------------
    Invoke-AB 'wait' '#mw-usuario' | Out-Null
    Invoke-AB 'scrollintoview' '#mw-usuario' | Out-Null
    Invoke-AB 'fill' '#mw-usuario' '1fantasy' | Out-Null

    $limite = (Get-Date).AddSeconds(10)
    $erro = ''
    while ((Get-Date) -lt $limite) {
        $erro = "$(Invoke-AB 'get' 'text' '#mw-erro-usuario')".Trim()
        if ($erro) { break }
        Start-Sleep -Milliseconds 300
    }
    Assert-Tmx -Nome 'um nome de usuario invalido mostra erro de validacao' `
        -Condicao ([bool]$erro) -Detalhe "obtido: '$erro'"

    Invoke-AB 'fill' '#mw-usuario' 'fantasy' | Out-Null
    $limite = (Get-Date).AddSeconds(10)
    $erroOk = 'x'
    while ((Get-Date) -lt $limite) {
        $erroOk = "$(Invoke-AB 'get' 'text' '#mw-erro-usuario')".Trim()
        if (-not $erroOk) { break }
        Start-Sleep -Milliseconds 300
    }
    Assert-Tmx -Nome 'um nome de usuario valido limpa o erro' `
        -Condicao (-not $erroOk) -Detalhe "obtido: '$erroOk'"

    # --- a ponte recusa a build de verdade no modo de teste -----------------
    $recusa = "$(Invoke-AB 'eval' "window.tmx.bridge.call('microwin.build',{iso:'C:\\\\x.iso',edicao:1,usuario:'fantasy',senha:'abc',destino:'C:\\\\'}).then(function(){return 'ACEITOU';},function(e){return 'RECUSOU: '+e.message;})")".Trim()
    Assert-Tmx -Nome 'microwin.build recusa uma ISO inexistente pela ponte' `
        -Condicao ($recusa -match '(?i)recusou') -Detalhe "obtido: '$recusa'"

    # --- print --------------------------------------------------------------
    $print = Join-Path (Initialize-TmxGuiOut) 'microwin.png'
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
