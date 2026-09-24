<#
.SYNOPSIS
    Teste de GUI da aba Otimizacoes (v2): modos, cards didaticos, filtros,
    confirmacao do Ultimate, idioma, previa, aplicar e desfazer.
.DESCRIPTION
    Nao e Pester. Sobe a Start-TmxDev.ps1 com -TestMode -DebugPort, conecta o
    agent-browser e exercita a tela pela janela real:
      1. a aba Otimizacoes abre pelo menu e lista o catalogo inteiro em cards;
      2. os quatro modos aparecem, um so marcado; Leve deixa o ajuste de
         Moderado (TST-002) esmaecido com "Entra no modo Moderado";
      3. o item de FOLCLORE (TST-003) fica nos Extras, desligado e avisado;
      4. o card traz O que faz / Beneficio / Atencao e o "Saiba mais";
      5. filtro por categoria e busca escondem/mostram os cards certos;
      6. o Ultimate pede confirmacao separada (caixa marcada) antes de trocar;
      7. em ingles, titulo e nome do tweak vem da traducao;
      8. com a sessao aberta, so TST-001 ligado: a barra fixa resume o modo,
         a previa antes->depois abre, a aplicacao termina, o modo fica
         marcado como aplicado e o Desfazer do item reverte.

    SEGURANCA: no modo de teste a ponte recusa qualquer id fora de TST-*, e o
    teste limpa a selecao antes de aplicar - nada do catalogo real e tocado.

    Deixa prints em tests/gui/out/otimizacoes.png, otimizacoes-ultimate.png e
    previa.png. Sai com 1 se algo falhar, e sempre fecha a GUI.
.EXAMPLE
    .\tests\gui\Test-Tweaks.ps1
#>
[CmdletBinding()]
param(
    [int] $Port = 9338
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
        Espera uma GUI de teste anterior DESTA porta terminar (PID em out\gui-<porta>.pid).
    #>
    param(
        [Parameter(Mandatory)] [int] $Porta,
        [int] $TimeoutSeconds = 180
    )

    Initialize-TmxGuiOut | Out-Null
    $arquivo = Get-TmxGuiPidFile -Port $Porta
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

function Get-TmxAb {
    <#
    .SYNOPSIS
        Invoke-AB que devolve '' em vez de lancar (para usar dentro de espera).
    #>
    param([Parameter(ValueFromRemainingArguments = $true)] [string[]] $Argumentos)
    try { return (Invoke-AB @Argumentos) } catch { return '' }
}

function Get-TmxEval {
    <#
    .SYNOPSIS
        Avalia JS na pagina e devolve o texto sem aspas ('' se falhar).
    #>
    param([Parameter(Mandatory)] [string] $Js)
    "$(Get-TmxAb 'eval' $Js)".Trim().Trim('"')
}

function Wait-TmxEval {
    <#
    .SYNOPSIS
        Espera uma expressao JS devolver um texto que case com o curinga. Devolve o ultimo lido.
    #>
    param(
        [Parameter(Mandatory)] [string] $Js,
        [Parameter(Mandatory)] [string] $Curinga,
        [int] $TimeoutSeconds = 30
    )
    $limite = (Get-Date).AddSeconds($TimeoutSeconds)
    $v = ''
    while ((Get-Date) -lt $limite) {
        $v = Get-TmxEval $Js
        if ($v -like $Curinga) { return $v }
        Start-Sleep -Milliseconds 400
    }
    $v
}

function Wait-TmxTexto {
    param(
        [Parameter(Mandatory)] [string] $Seletor,
        [Parameter(Mandatory)] [string] $Curinga,
        [int] $TimeoutSeconds = 30
    )
    $limite = (Get-Date).AddSeconds($TimeoutSeconds)
    $texto  = ''
    while ((Get-Date) -lt $limite) {
        $texto = Get-TmxAb 'get' 'text' $Seletor
        if ($texto -like $Curinga) { return $texto }
        Start-Sleep -Milliseconds 500
    }
    $texto
}

function Wait-TmxContagem {
    param(
        [Parameter(Mandatory)] [string] $Seletor,
        [int] $Minimo = 1,
        [int] $TimeoutSeconds = 150
    )
    $limite = (Get-Date).AddSeconds($TimeoutSeconds)
    $n = 0
    while ((Get-Date) -lt $limite) {
        $bruto = Get-TmxAb 'get' 'count' $Seletor
        $achado = [regex]::Match("$bruto", '\d+')
        if ($achado.Success) { $n = [int]$achado.Value }
        if ($n -ge $Minimo) { return $n }
        Start-Sleep -Milliseconds 500
    }
    $n
}

function Wait-TmxSeletor {
    param(
        [Parameter(Mandatory)] [string] $Seletor,
        [int] $TimeoutSeconds = 90
    )
    (Wait-TmxContagem -Seletor $Seletor -Minimo 1 -TimeoutSeconds $TimeoutSeconds) -ge 1
}

function Connect-TmxPagina {
    <#
    .SYNOPSIS
        Conecta o agent-browser e so devolve $true quando a pagina responde a
        um seletor da aplicacao (reconecta em laco: conectar cedo demais deixa
        a sessao presa num documento vazio).
    #>
    param(
        [Parameter(Mandatory)] [int] $Porta,
        [int] $TimeoutSeconds = 120
    )
    $limite = (Get-Date).AddSeconds($TimeoutSeconds)
    $ultimo = ''
    while ((Get-Date) -lt $limite) {
        try { Invoke-AB 'connect' "$Porta" | Out-Null } catch { $ultimo = "connect: $($_.Exception.Message)" }
        try {
            $n = Invoke-AB 'get' 'count' '#tab-otimizacoes'
            if ("$n" -match '[1-9]') { return $true }
            $ultimo = "count: $n"
        } catch {
            $ultimo = "count: $($_.Exception.Message)"
        }
        Start-Sleep -Seconds 2
    }
    Write-Host "      ultimo estado do agent-browser: $ultimo" -ForegroundColor DarkYellow
    $false
}

function Wait-TmxOtimLivre {
    <#
    .SYNOPSIS
        Espera a aba sair do estado ocupado (aria-busy = false no #tab-otimizacoes).
    #>
    param([int] $TimeoutSeconds = 180)
    $limite = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $limite) {
        $v = Get-TmxEval "document.getElementById('tab-otimizacoes').getAttribute('aria-busy')"
        if ("$v" -match 'false') { return $true }
        Start-Sleep -Milliseconds 400
    }
    $false
}

function Get-TmxSwitch {
    param([Parameter(Mandatory)] [string] $Id)
    Get-TmxEval "(function(){var b=document.getElementById('tw-$Id');return b?b.getAttribute('aria-checked')+(b.disabled?'|disabled':''):'ausente';})()"
}

function Get-TmxModoMarcado {
    Get-TmxEval "(function(){var b=document.querySelectorAll('.otim-modo[aria-checked=true]');return b.length+':'+(b[0]?b[0].getAttribute('data-modo'):'');})()"
}

function Get-TmxCardsVisiveis {
    Get-TmxEval "[].filter.call(document.querySelectorAll('#tw-categorias .tweak'),function(c){return !c.hidden;}).map(function(c){return c.getAttribute('data-id');}).join(',')"
}

function Invoke-TmxClickJs {
    <#
    .SYNOPSIS
        Clica por JS: os cards ficam embaixo da barra fixa, e um clique real
        num elemento coberto por ela e interceptado.
    #>
    param([Parameter(Mandatory)] [string] $Seletor)
    Get-TmxEval "(function(){var e=document.querySelector('$Seletor');if(!e){return 'ausente';}e.click();return 'ok';})()"
}

function Set-TmxBusca {
    param([string] $Texto)
    Get-TmxEval "(function(){var i=document.getElementById('tw-busca');i.value='$Texto';i.dispatchEvent(new Event('input'));return 'ok';})()" | Out-Null
}

function Invoke-TmxTopo {
    # Volta a rolagem ao topo: um clique real embaixo da barra fixa e interceptado.
    Get-TmxEval "document.querySelector('main').scrollTop=0; 'ok'" | Out-Null
}

Wait-TmxGuiLivre -Porta $Port | Out-Null
try { Invoke-AB 'close' | Out-Null } catch { }

$gui = $null
try {
    Write-Host "Abrindo a GUI em modo de teste (CDP $Port)..." -ForegroundColor Cyan
    $gui = Start-TmxGui -Port $Port -TestMode -TimeoutSeconds 180
    Write-Host "CDP: $($gui.versaoCdp.Browser)"

    $pagina = Wait-TmxGuiPage -Port $Port
    Write-Host "Pagina: $($pagina.url)"

    $conectado = Connect-TmxPagina -Porta $Port -TimeoutSeconds 120
    Assert-Tmx -Nome 'a pagina da aplicacao responde ao seletor' -Condicao $conectado
    if (-not $conectado) { throw 'a pagina nao respondeu a nenhum seletor apos reconectar' }

    Wait-TmxSeletor -Seletor '#st-rp' -TimeoutSeconds 60 | Out-Null
    Close-TmxGuiWelcome
    Get-TmxEval "tmx.i18n.set('pt-BR'); 'ok'" | Out-Null

    # --- 1. a aba abre pelo menu e lista o catalogo -----------------------
    Invoke-AB 'click' 'nav [data-tab=otimizacoes]' | Out-Null
    $visivel = Get-TmxAb 'is' 'visible' '#tab-otimizacoes'
    Assert-Tmx -Nome 'a aba Otimizacoes abre pelo menu' -Condicao ("$visivel" -match 'true|visible|yes') -Detalhe "obtido: '$visivel'"

    Write-Host 'Esperando o catalogo (perfil + estado do sistema levam alguns segundos)...' -ForegroundColor DarkGray
    $quantos = Wait-TmxContagem -Seletor '#tw-categorias .tweak' -Minimo 100 -TimeoutSeconds 300
    if ($quantos -lt 100) {
        Write-Host "      diagnostico: $(Get-TmxAb 'get' 'text' '#tw-categorias')" -ForegroundColor DarkYellow
    }
    Assert-Tmx -Nome 'a lista traz o catalogo inteiro em cards (100+)' -Condicao ($quantos -ge 100) -Detalhe "obtido: $quantos"
    Wait-TmxOtimLivre | Out-Null

    $titulo = "$(Get-TmxAb 'get' 'text' '#tab-otimizacoes .otim-h')".Trim()
    Assert-Tmx -Nome 'titulo "Ajustes de desempenho"' -Condicao ($titulo -eq 'Ajustes de desempenho') -Detalhe "obtido: '$titulo'"

    # --- 2. modos -----------------------------------------------------------
    $nModos = Wait-TmxContagem -Seletor '.otim-modo' -Minimo 4 -TimeoutSeconds 10
    Assert-Tmx -Nome 'os quatro modos aparecem' -Condicao ($nModos -eq 4) -Detalhe "obtido: $nModos"
    $marcado = Get-TmxModoMarcado
    Assert-Tmx -Nome 'exatamente um modo marcado' -Condicao ($marcado -like '1:*') -Detalhe "obtido: '$marcado'"

    Invoke-TmxTopo; Invoke-AB 'click' '#tw-modo-leve' | Out-Null
    $leve = Wait-TmxEval "document.getElementById('tw-modo-leve').getAttribute('aria-checked')" 'true' 120
    Wait-TmxOtimLivre | Out-Null
    Assert-Tmx -Nome 'clicar em Leve marca o modo Leve' -Condicao ($leve -eq 'true') -Detalhe "obtido: '$leve'"

    $sw1 = Get-TmxSwitch 'TST-001'
    Assert-Tmx -Nome 'no Leve, TST-001 (modo leve) vem ligado' -Condicao ($sw1 -eq 'true') -Detalhe "obtido: '$sw1'"
    $sw2 = Get-TmxSwitch 'TST-002'
    Assert-Tmx -Nome 'no Leve, TST-002 (modo moderado) fica desligado e travado' -Condicao ($sw2 -eq 'false|disabled') -Detalhe "obtido: '$sw2'"
    $acima = Get-TmxEval "document.querySelector('.tweak[data-id=TST-002]').className"
    Assert-Tmx -Nome 'TST-002 aparece esmaecido acima do modo' -Condicao ($acima -like '*is-acima*') -Detalhe "obtido: '$acima'"
    $motivo = "$(Get-TmxAb 'get' 'text' '.tweak[data-id=TST-002] .tw-motivo')"
    Assert-Tmx -Nome 'TST-002 diz "Entra no modo Moderado"' -Condicao ($motivo -like '*Entra no modo Moderado*') -Detalhe "obtido: '$motivo'"
    $explica = "$(Get-TmxAb 'get' 'text' '#tw-explica')"
    Assert-Tmx -Nome 'o quadro explica o modo Leve' -Condicao ($explica -like '*O que o modo Leve faz*') -Detalhe "obtido: '$explica'"

    Invoke-TmxTopo; Invoke-AB 'click' '#tw-modo-moderado' | Out-Null
    $mod = Wait-TmxEval "document.getElementById('tw-modo-moderado').getAttribute('aria-checked')" 'true' 120
    Wait-TmxOtimLivre | Out-Null
    Assert-Tmx -Nome 'clicar em Moderado marca o modo Moderado' -Condicao ($mod -eq 'true') -Detalhe "obtido: '$mod'"
    $sw2b = Get-TmxSwitch 'TST-002'
    Assert-Tmx -Nome 'no Moderado, TST-002 vem ligado' -Condicao ($sw2b -eq 'true') -Detalhe "obtido: '$sw2b'"

    # --- 3. folclore nos extras ---------------------------------------------
    $nosExtras = Get-TmxAb 'get' 'count' '#tw-extras .tweak[data-id=TST-003]'
    Assert-Tmx -Nome 'o item de folclore fica na secao Extras' -Condicao ("$nosExtras" -match '1') -Detalhe "obtido: '$nosExtras'"
    $sw3 = Get-TmxSwitch 'TST-003'
    Assert-Tmx -Nome 'o item de folclore chega desligado' -Condicao ($sw3 -like 'false*') -Detalhe "obtido: '$sw3'"
    $aviso = Get-TmxAb 'get' 'attr' '.tweak[data-id=TST-003]' 'title'
    Assert-Tmx -Nome 'o item de folclore avisa que nao ha evidencia de ganho' -Condicao ($aviso -like '*Sem evid*ncia*') -Detalhe "obtido: '$aviso'"
    $selos = Get-TmxAb 'get' 'count' '.tweak[data-id=TST-003] .selo-folclore'
    Assert-Tmx -Nome 'o selo Folclore aparece no item' -Condicao ("$selos" -match '[1-9]') -Detalhe "obtido: '$selos'"

    # --- 4. card didatico ---------------------------------------------------
    $card = "$(Get-TmxEval "document.querySelector('.tweak[data-id=TST-001]').innerText")"
    Assert-Tmx -Nome 'o card traz O que faz, Beneficio e Atencao' -Condicao (($card -like '*O QUE FAZ*' -or $card -like '*O que faz*') -and ($card -like '*enef*cio*') -and ($card -like '*ten*o*')) -Detalhe "obtido: '$($card.Substring(0, [Math]::Min(200, $card.Length)))'"
    $risco = Get-TmxAb 'get' 'count' '.tweak[data-id=TST-001] .selo-risco-baixo'
    Assert-Tmx -Nome 'o card traz o selo de risco' -Condicao ("$risco" -match '[1-9]') -Detalhe "obtido: '$risco'"
    $mais = Get-TmxAb 'get' 'count' '.tweak[data-id=TST-001] details.tw-mais'
    Assert-Tmx -Nome 'o card traz o "Saiba mais"' -Condicao ("$mais" -match '1') -Detalhe "obtido: '$mais'"

    # --- 5. filtros e busca -------------------------------------------------
    Invoke-TmxClickJs '#tw-filtros [data-filtro=jogos]' | Out-Null
    Start-Sleep -Milliseconds 400
    $vis = Get-TmxCardsVisiveis
    Assert-Tmx -Nome 'o filtro Jogos mostra TST-002 e esconde TST-001' -Condicao (($vis -like '*TST-002*') -and ($vis -notlike '*TST-001*')) -Detalhe "obtido: '$($vis.Substring(0, [Math]::Min(160, $vis.Length)))'"
    Invoke-TmxClickJs '#tw-filtros [data-filtro=todos]' | Out-Null

    Set-TmxBusca 'TST-00'
    Start-Sleep -Milliseconds 400
    $vis = Get-TmxCardsVisiveis
    $partes = @($vis -split ',' | Where-Object { $_ })
    Assert-Tmx -Nome 'a busca por "TST-00" deixa so os tweaks de teste' -Condicao (($partes.Count -eq 5) -and (@($partes | Where-Object { $_ -notlike 'TST-*' }).Count -eq 0)) -Detalhe "obtido: '$vis'"
    Set-TmxBusca ''
    Start-Sleep -Milliseconds 300

    $print1 = Join-Path (Initialize-TmxGuiOut) 'otimizacoes.png'
    Invoke-AB 'screenshot' $print1 | Out-Null
    Assert-Tmx -Nome 'screenshot da aba gravado' -Condicao (Test-Path -LiteralPath $print1) -Detalhe $print1

    # --- 6. confirmacao separada do Ultimate --------------------------------
    Invoke-TmxTopo; Invoke-AB 'click' '#tw-modo-ultimate' | Out-Null
    $tUlt = Wait-TmxTexto -Seletor '#modal-title' -Curinga '*Ultimate*' -TimeoutSeconds 15
    Assert-Tmx -Nome 'o Ultimate abre a confirmacao antes de trocar' -Condicao ($tUlt -like '*Ultimate*') -Detalhe "obtido: '$tUlt'"
    $okDis = Get-TmxEval "String(document.getElementById('tw-ult-ok') && document.getElementById('tw-ult-ok').disabled)"
    Assert-Tmx -Nome 'o botao do Ultimate comeca travado' -Condicao ($okDis -eq 'true') -Detalhe "obtido: '$okDis'"
    $lista = "$(Get-TmxAb 'get' 'text' '#tw-ult')"
    Assert-Tmx -Nome 'a confirmacao lista o ajuste de risco alto' -Condicao ($lista -like '*risco alto do Ultimate*') -Detalhe "obtido: '$lista'"

    $print3 = Join-Path (Initialize-TmxGuiOut) 'otimizacoes-ultimate.png'
    Invoke-AB 'screenshot' $print3 | Out-Null

    Invoke-TmxClickJs '#modal-buttons .btn:not(.btn-danger)' | Out-Null
    Start-Sleep -Milliseconds 400
    $aindaMod = Get-TmxModoMarcado
    Assert-Tmx -Nome 'cancelar mantem o modo Moderado' -Condicao ($aindaMod -eq '1:moderado') -Detalhe "obtido: '$aindaMod'"

    Invoke-TmxTopo; Invoke-AB 'click' '#tw-modo-ultimate' | Out-Null
    Wait-TmxSeletor -Seletor '#tw-ult-check' -TimeoutSeconds 15 | Out-Null
    Invoke-AB 'check' '#tw-ult-check' | Out-Null
    $okDis2 = Wait-TmxEval "String(document.getElementById('tw-ult-ok').disabled)" 'false' 10
    Assert-Tmx -Nome 'marcar a caixa libera o botao do Ultimate' -Condicao ($okDis2 -eq 'false') -Detalhe "obtido: '$okDis2'"
    Invoke-AB 'click' '#tw-ult-ok' | Out-Null
    $ult = Wait-TmxEval "document.getElementById('tw-modo-ultimate').getAttribute('aria-checked')" 'true' 120
    Wait-TmxOtimLivre | Out-Null
    Assert-Tmx -Nome 'confirmado, o modo Ultimate fica marcado' -Condicao ($ult -eq 'true') -Detalhe "obtido: '$ult'"
    $sw5 = Get-TmxSwitch 'TST-005'
    Assert-Tmx -Nome 'no Ultimate, o risco alto (TST-005) entra ligado' -Condicao ($sw5 -eq 'true') -Detalhe "obtido: '$sw5'"

    Invoke-TmxTopo; Invoke-AB 'click' '#tw-modo-moderado' | Out-Null
    Wait-TmxEval "document.getElementById('tw-modo-moderado').getAttribute('aria-checked')" 'true' 120 | Out-Null
    Wait-TmxOtimLivre | Out-Null

    # --- 7. idioma ----------------------------------------------------------
    Get-TmxEval "tmx.i18n.set('en'); 'ok'" | Out-Null
    $tituloEn = Wait-TmxTexto -Seletor '#tab-otimizacoes .otim-h' -Curinga 'Performance tweaks*' -TimeoutSeconds 10
    Assert-Tmx -Nome 'em ingles o titulo vira "Performance tweaks"' -Condicao ($tituloEn -like 'Performance tweaks*') -Detalhe "obtido: '$tituloEn'"
    $nomeEn = "$(Get-TmxAb 'get' 'text' '.tweak[data-id=TST-001] .tw-nome')".Trim()
    Assert-Tmx -Nome 'em ingles o nome do tweak vem de i18n.en' -Condicao ($nomeEn -eq 'Test - registry value') -Detalhe "obtido: '$nomeEn'"
    $modoEn = "$(Get-TmxAb 'get' 'text' '#tw-modo-leve .otim-modo-nome')".Trim()
    Assert-Tmx -Nome 'em ingles o modo Leve vira "Light"' -Condicao ($modoEn -eq 'Light') -Detalhe "obtido: '$modoEn'"
    Get-TmxEval "tmx.i18n.set('pt-BR'); 'ok'" | Out-Null
    Wait-TmxTexto -Seletor '#tab-otimizacoes .otim-h' -Curinga 'Ajustes de desempenho*' -TimeoutSeconds 10 | Out-Null

    # --- 8. sessao aberta pelo botao de desenvolvimento ---------------------
    Wait-TmxOtimLivre | Out-Null
    Wait-TmxSeletor -Seletor '#st-session-start' -TimeoutSeconds 60 | Out-Null
    Invoke-AB 'click' '#st-session-start' | Out-Null
    Wait-TmxSeletor -Seletor '#modal-buttons .btn-primary' -TimeoutSeconds 60 | Out-Null
    $modalSessao = Wait-TmxTexto -Seletor '#modal-title' -Curinga '*Ponto de restaura*' -TimeoutSeconds 30
    Assert-Tmx -Nome 'o modal do ponto de restauracao abre' -Condicao ($modalSessao -like '*Ponto de restaura*') -Detalhe "obtido: '$modalSessao'"
    Invoke-AB 'click' '#modal-buttons .btn-primary' | Out-Null

    $rp = Wait-TmxTexto -Seletor '#st-rp' -Curinga '*Ponto #999*' -TimeoutSeconds 60
    Assert-Tmx -Nome 'a sessao abre com o ponto simulado #999' -Condicao ($rp -like '*Ponto #999*') -Detalhe "obtido: '$rp'"

    # --- 9. so TST-001 ligado (nada do catalogo real e tocado) --------------
    Wait-TmxOtimLivre | Out-Null
    Invoke-TmxClickJs '#tw-limpar' | Out-Null
    $zero = Wait-TmxEval "document.getElementById('tw-ligados').getAttribute('data-n')" '0' 60
    Assert-Tmx -Nome 'Limpar selecao zera os ajustes ligados' -Condicao ($zero -eq '0') -Detalhe "obtido: '$zero'"
    $aplDis = Get-TmxEval "String(document.getElementById('tw-aplicar').disabled)"
    Assert-Tmx -Nome 'sem nada ligado o botao Aplicar fica travado' -Condicao ($aplDis -eq 'true') -Detalhe "obtido: '$aplDis'"

    Wait-TmxOtimLivre | Out-Null
    Invoke-TmxClickJs '#tw-TST-001' | Out-Null
    $um = Wait-TmxEval "document.getElementById('tw-ligados').getAttribute('data-n')" '1' 30
    Assert-Tmx -Nome 'ligar TST-001 conta 1 ajuste ligado' -Condicao ($um -eq '1') -Detalhe "obtido: '$um'"
    $resumo = "$(Get-TmxAb 'get' 'text' '#tw-resumo-modo')".Trim()
    Assert-Tmx -Nome 'a barra fixa resume "Modo Moderado . 1 ajuste ligado"' -Condicao ($resumo -like 'Modo Moderado*1 ajuste ligado') -Detalhe "obtido: '$resumo'"
    $botao = "$(Get-TmxAb 'get' 'text' '#tw-aplicar')".Trim()
    Assert-Tmx -Nome 'o botao diz "Aplicar modo Moderado"' -Condicao ($botao -eq 'Aplicar modo Moderado') -Detalhe "obtido: '$botao'"

    # --- 10. previa antes -> depois -----------------------------------------
    Invoke-TmxClickJs '#tw-aplicar' | Out-Null
    $abriuPrevia = Wait-TmxSeletor -Seletor '#tw-barra' -TimeoutSeconds 120
    Assert-Tmx -Nome 'o modal de previa abre' -Condicao $abriuPrevia

    $corpo = "$(Get-TmxAb 'get' 'text' '#modal-body')"
    Assert-Tmx -Nome 'a previa mostra a coluna Antes' -Condicao ($corpo -like '*Antes*') -Detalhe "obtido: '$($corpo.Substring(0, [Math]::Min(160, $corpo.Length)))'"
    Assert-Tmx -Nome 'a previa mostra a coluna Depois' -Condicao ($corpo -like '*Depois*')
    Assert-Tmx -Nome 'a previa lista o alvo de TST-001' -Condicao ($corpo -like '*TST-001*')
    Assert-Tmx -Nome 'o titulo do modal e a previa' -Condicao ((Get-TmxAb 'get' 'text' '#modal-title') -like '*antes*depois*')

    $print2 = Join-Path (Initialize-TmxGuiOut) 'previa.png'
    Invoke-AB 'screenshot' $print2 | Out-Null
    Assert-Tmx -Nome 'screenshot da previa gravado' -Condicao (Test-Path -LiteralPath $print2) -Detalhe $print2

    # --- 11. aplicar ----------------------------------------------------------
    Invoke-AB 'click' '#modal-buttons .btn-primary' | Out-Null
    $viuResultado = [bool](Wait-TmxSeletor -Seletor '#tw-resultado' -TimeoutSeconds 90)
    Assert-Tmx -Nome 'a aplicacao termina (modal de resultado)' -Condicao $viuResultado

    Invoke-TmxClickJs '#modal-buttons .btn' | Out-Null

    $estado = Wait-TmxTexto -Seletor '.tweak[data-id=TST-001] .estado' -Curinga '*aplicado*' -TimeoutSeconds 60
    Assert-Tmx -Nome 'TST-001 passa a mostrar o estado aplicado' -Condicao ($estado -like '*aplicado*') -Detalhe "obtido: '$estado'"
    $selo = Wait-TmxEval "String(document.querySelector('[data-aplicado=moderado]').hidden)" 'false' 15
    Assert-Tmx -Nome 'o modo Moderado fica marcado como aplicado' -Condicao ($selo -eq 'false') -Detalhe "obtido: '$selo'"

    # --- 12. desfazer por item ----------------------------------------------
    Wait-TmxOtimLivre | Out-Null
    Invoke-TmxClickJs '.tweak[data-id=TST-001] .tw-undo' | Out-Null
    $revertido = Wait-TmxTexto -Seletor '.tweak[data-id=TST-001] .estado' -Curinga '*revertido*' -TimeoutSeconds 90
    Assert-Tmx -Nome 'Desfazer do item deixa o estado revertido' -Condicao ($revertido -like '*revertido*') -Detalhe "obtido: '$revertido'"

    Invoke-AB 'screenshot' $print1 | Out-Null
    Write-Host "Prints: $print1 | $print3 | $print2"

} catch {
    $script:Falhas++
    Write-Host "FAIL  execucao: $($_.Exception.Message)" -ForegroundColor Red
} finally {
    Write-Host 'Fechando a GUI...' -ForegroundColor Cyan
    $limpo = Stop-TmxGui -Port $Port
    Assert-Tmx -Nome 'porta CDP liberada no fim' -Condicao ([bool]$limpo)
    Remove-Item -LiteralPath 'HKCU:\Software\TweakMaxing_Tests\Gui' -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
if ($script:Falhas -gt 0) {
    Write-Host "RESULTADO: $script:Falhas verificacao(oes) falharam." -ForegroundColor Red
    exit 1
}
Write-Host 'RESULTADO: todas as verificacoes passaram.' -ForegroundColor Green
exit 0
