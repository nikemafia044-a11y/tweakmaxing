<#
.SYNOPSIS
    Teste de GUI da aba Ajustes: catalogo, preset, previa, aplicar e desfazer.
.DESCRIPTION
    Nao e Pester. Sobe a Start-TmxDev.ps1 com -TestMode -DebugPort, conecta o
    agent-browser e exercita a Task 10 pela janela real:
      1. a aba Ajustes abre e lista o catalogo inteiro;
      2. o item de FOLCLORE (TST-003) chega desmarcado e com o aviso de que
         nao ha evidencia de ganho;
      3. o preset Desktop marca TST-001;
      4. com a sessao aberta, "Aplicar selecionados" mostra a previa
         antes->depois, aplica e o item passa a mostrar o estado 'aplicado';
      5. "Desfazer" do proprio item volta o estado para 'revertido'.

    SEGURANCA: no modo de teste a ponte recusa qualquer id fora de TST-*, e
    mesmo assim o teste limpa a selecao antes de aplicar - nada do catalogo
    real e tocado nesta maquina.

    Deixa prints em tests/gui/out/ajustes.png e tests/gui/out/previa.png.
    Sai com 1 se algo falhar, e sempre fecha a GUI.
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
        Espera uma GUI de teste anterior DESTA porta terminar.
    .DESCRIPTION
        O arquivo de PID e por porta (out\gui-<porta>.pid), entao suites em
        portas diferentes nao se esperam nem se derrubam; o que nao pode e
        comecar por cima de uma execucao anterior da propria suite.
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

function Wait-TmxTexto {
    <#
    .SYNOPSIS
        Espera o texto de um seletor casar com um curinga. Devolve o ultimo lido.
    #>
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
    <#
    .SYNOPSIS
        Espera 'get count <seletor>' chegar a pelo menos $Minimo. Devolve o ultimo valor.
    #>
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
    <#
    .SYNOPSIS
        Espera um seletor existir no DOM. Devolve $true quando aparece.
    .DESCRIPTION
        'agent-browser wait' tem prazo proprio (25 s) e lanca ao estourar, o que
        derruba o teste inteiro por um atraso de arranque. Contar o seletor e
        mais previsivel e deixa o prazo com quem chama.
    #>
    param(
        [Parameter(Mandatory)] [string] $Seletor,
        [int] $TimeoutSeconds = 90
    )
    (Wait-TmxContagem -Seletor $Seletor -Minimo 1 -TimeoutSeconds $TimeoutSeconds) -ge 1
}

function Connect-TmxPagina {
    <#
    .SYNOPSIS
        Conecta o agent-browser e so devolve $true quando a pagina de fato
        responde a um seletor da aplicacao.
    .DESCRIPTION
        O alvo CDP aparece com a URL certa antes de o documento existir, e o
        agent-browser nao reavalia o alvo depois de conectado: conectar cedo
        demais deixa a sessao presa num documento vazio e todo seletor 'some'.
        Reconectar em laco e o unico jeito confiavel de sair desse estado.
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
            $n = Invoke-AB 'get' 'count' '#tab-ajustes'
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

function Wait-TmxAjustesLivre {
    <#
    .SYNOPSIS
        Espera a aba Ajustes sair do estado ocupado (aria-busy = false).
    .DESCRIPTION
        Todo trabalho da aba passa por ocupar(), que marca aria-busy no
        #tab-ajustes e desabilita os botoes. Clicar antes disso faz o proximo
        Start-TmxJob esbarrar em 'ja existe um trabalho em andamento'.
    #>
    param([int] $TimeoutSeconds = 180)

    $limite = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $limite) {
        $v = Get-TmxAb 'eval' "document.getElementById('tab-ajustes').getAttribute('aria-busy')"
        if ("$v" -match 'false') { return $true }
        Start-Sleep -Milliseconds 400
    }
    $false
}

function Wait-TmxMarcado {
    <#
    .SYNOPSIS
        Espera 'is checked <seletor>' virar verdadeiro. Devolve o ultimo lido.
    #>
    param(
        [Parameter(Mandatory)] [string] $Seletor,
        [int] $TimeoutSeconds = 60
    )
    $limite = (Get-Date).AddSeconds($TimeoutSeconds)
    $v = ''
    while ((Get-Date) -lt $limite) {
        $v = Get-TmxAb 'is' 'checked' $Seletor
        if ("$v" -match 'true|checked|yes') { return $v }
        Start-Sleep -Milliseconds 500
    }
    $v
}

Wait-TmxGuiLivre -Porta $Port | Out-Null

# O agent-browser deixa um daemon vivo entre invocacoes, e ele pode continuar
# preso na sessao CDP de uma GUI que ja morreu - nesse estado o 'connect'
# devolve sucesso mas todo seletor 'some'. Fechar tudo antes de subir a janela
# nova e o que garante uma sessao limpa.
try { Invoke-AB 'close' | Out-Null } catch { }

$gui = $null
try {
    Write-Host "Abrindo a GUI em modo de teste (CDP $Port)..." -ForegroundColor Cyan
    $gui = Start-TmxGui -Port $Port -TestMode
    Write-Host "CDP: $($gui.versaoCdp.Browser)"

    $pagina = Wait-TmxGuiPage -Port $Port
    Write-Host "Pagina: $($pagina.url)"

    $conectado = Connect-TmxPagina -Porta $Port -TimeoutSeconds 120
    Assert-Tmx -Nome 'a pagina da aplicacao responde ao seletor' -Condicao $conectado
    if (-not $conectado) { throw 'a pagina nao respondeu a nenhum seletor apos reconectar' }

    # --- 1. a aba abre e lista o catalogo -----------------------------------
    $visivel = Invoke-AB 'is' 'visible' '#tab-ajustes'
    Assert-Tmx -Nome 'a aba Ajustes abre por padrao' -Condicao ("$visivel" -match 'true|visible|yes') -Detalhe "obtido: '$visivel'"

    # O catalogo nasce de Get-TmxProfile + Resolve-TmxPlan -IncludeState, que leem
    # o sistema inteiro: uns 15 s com a maquina livre, bem mais com outras suites
    # rodando em paralelo. Por isso o prazo generoso.
    Write-Host 'Esperando o catalogo (perfil + estado do sistema levam alguns segundos)...' -ForegroundColor DarkGray
    $quantos = Wait-TmxContagem -Seletor '.tweak' -Minimo 100 -TimeoutSeconds 300
    if ($quantos -lt 100) {
        Write-Host "      diagnostico: $(Get-TmxAb 'get' 'text' '#tw-categorias')" -ForegroundColor DarkYellow
    }
    Assert-Tmx -Nome 'a lista traz o catalogo inteiro (100+ ajustes)' -Condicao ($quantos -ge 100) -Detalhe "obtido: $quantos"

    # --- 2. folclore desmarcado e avisado -----------------------------------
    $marcado3 = Get-TmxAb 'is' 'checked' '#tw-TST-003'
    Assert-Tmx -Nome 'o item de folclore chega desmarcado' -Condicao ("$marcado3" -notmatch 'true|checked|yes') -Detalhe "obtido: '$marcado3'"

    # 'get attr' leva o SELETOR antes do nome do atributo.
    $aviso = Get-TmxAb 'get' 'attr' '.tweak[data-id=TST-003]' 'title'
    Assert-Tmx -Nome 'o item de folclore avisa que nao ha evidencia de ganho' -Condicao ($aviso -like '*Sem evid*ncia*') -Detalhe "obtido: '$aviso'"

    $selos = Get-TmxAb 'get' 'count' '.tweak[data-id=TST-003] .selo-folclore'
    Assert-Tmx -Nome 'o selo FOLCLORE aparece no item' -Condicao ("$selos" -match '[1-9]') -Detalhe "obtido: '$selos'"

    # --- 3. preset Desktop marca o tweak de teste ---------------------------
    # Desmarcar antes: TST-001 ja nasce marcado (o preset inicial e o desktop),
    # entao sem isto a verificacao passaria sem o preset ter feito nada.
    Wait-TmxAjustesLivre | Out-Null
    $antes = Get-TmxAb 'get' 'text' '#tw-contadores'
    $quantosSel = 0
    $m = [regex]::Match("$antes", '^\s*(\d+)')
    if ($m.Success) { $quantosSel = [int]$m.Groups[1].Value }

    Invoke-AB 'uncheck' '#tw-TST-001' | Out-Null
    $menosUm = Wait-TmxTexto -Seletor '#tw-contadores' -Curinga "$($quantosSel - 1) selecionados*" -TimeoutSeconds 30
    Assert-Tmx -Nome 'desmarcar TST-001 atualiza os contadores' -Condicao ($menosUm -like "$($quantosSel - 1) selecionados*") -Detalhe "obtido: '$menosUm'"

    Invoke-AB 'click' '#tw-preset-desktop' | Out-Null
    $marcado1 = Wait-TmxMarcado -Seletor '#tw-TST-001' -TimeoutSeconds 120
    Assert-Tmx -Nome 'o preset Desktop marca TST-001' -Condicao ("$marcado1" -match 'true|checked|yes') -Detalhe "obtido: '$marcado1'"
    Wait-TmxAjustesLivre | Out-Null

    $print1 = Join-Path (Initialize-TmxGuiOut) 'ajustes.png'
    Invoke-AB 'screenshot' $print1 | Out-Null
    Assert-Tmx -Nome 'screenshot da aba gravado' -Condicao (Test-Path -LiteralPath $print1) -Detalhe $print1

    # --- 4. sessao aberta pelo botao de desenvolvimento ---------------------
    # A aba precisa estar ociosa: a ponte roda um trabalho por vez, e abrir a
    # sessao com o job do preset ainda vivo daria 'ja existe um trabalho em andamento'.
    Wait-TmxAjustesLivre | Out-Null
    Wait-TmxSeletor -Seletor '#st-session-start' -TimeoutSeconds 60 | Out-Null
    Invoke-AB 'click' '#st-session-start' | Out-Null
    Wait-TmxSeletor -Seletor '#modal-buttons .btn-primary' -TimeoutSeconds 60 | Out-Null
    $modalSessao = Wait-TmxTexto -Seletor '#modal-title' -Curinga '*Ponto de restaura*' -TimeoutSeconds 30
    Assert-Tmx -Nome 'o modal do ponto de restauracao abre' -Condicao ($modalSessao -like '*Ponto de restaura*') -Detalhe "obtido: '$modalSessao'"
    Invoke-AB 'click' '#modal-buttons .btn-primary' | Out-Null

    $rp = Wait-TmxTexto -Seletor '#st-rp' -Curinga '*Ponto #999*' -TimeoutSeconds 60
    Assert-Tmx -Nome 'a sessao abre com o ponto simulado #999' -Condicao ($rp -like '*Ponto #999*') -Detalhe "obtido: '$rp'"

    # --- 5. so TST-001 selecionado (nada do catalogo real e tocado) ---------
    Wait-TmxAjustesLivre | Out-Null
    Invoke-AB 'click' '#tw-limpar' | Out-Null
    $zerado = Wait-TmxTexto -Seletor '#tw-contadores' -Curinga '0 selecionados*' -TimeoutSeconds 60
    Assert-Tmx -Nome 'Limpar selecao zera os selecionados' -Condicao ($zerado -like '0 selecionados*') -Detalhe "obtido: '$zerado'"

    Invoke-AB 'check' '#tw-TST-001' | Out-Null
    $um = Wait-TmxTexto -Seletor '#tw-contadores' -Curinga '1 selecionados*' -TimeoutSeconds 30
    Assert-Tmx -Nome 'apenas TST-001 fica selecionado' -Condicao ($um -like '1 selecionados*') -Detalhe "obtido: '$um'"

    # --- 6. previa antes -> depois ------------------------------------------
    # O #modal-body guarda o conteudo do modal ANTERIOR enquanto o proximo nao
    # abre (modal.close() so marca hidden), entao a espera e por uma marca que
    # so existe na previa - a barra de progresso - e nao por '#modal-body'.
    Wait-TmxAjustesLivre | Out-Null
    Invoke-AB 'click' '#tw-aplicar' | Out-Null
    $abriuPrevia = Wait-TmxSeletor -Seletor '#tw-barra' -TimeoutSeconds 120
    Assert-Tmx -Nome 'o modal de previa abre' -Condicao $abriuPrevia

    $corpo = Get-TmxAb 'get' 'text' '#modal-body'
    Assert-Tmx -Nome 'a previa mostra a coluna Antes' -Condicao ($corpo -like '*Antes*') -Detalhe "obtido: '$($corpo.Substring(0, [Math]::Min(160, $corpo.Length)))'"
    Assert-Tmx -Nome 'a previa mostra a coluna Depois' -Condicao ($corpo -like '*Depois*')
    Assert-Tmx -Nome 'a previa lista o alvo de TST-001' -Condicao ($corpo -like '*TST-001*')
    Assert-Tmx -Nome 'o titulo do modal e a previa' -Condicao ((Get-TmxAb 'get' 'text' '#modal-title') -like '*antes*depois*')

    $print2 = Join-Path (Initialize-TmxGuiOut) 'previa.png'
    Invoke-AB 'screenshot' $print2 | Out-Null
    Assert-Tmx -Nome 'screenshot da previa gravado' -Condicao (Test-Path -LiteralPath $print2) -Detalhe $print2

    # --- 7. aplicar ---------------------------------------------------------
    Invoke-AB 'click' '#modal-buttons .btn-primary' | Out-Null

    $viuJob       = $false
    $viuResultado = $false
    $limite = (Get-Date).AddSeconds(90)
    while ((Get-Date) -lt $limite) {
        $job = Get-TmxAb 'get' 'text' '#st-job'
        if ($job -like '*Conclu*') { $viuJob = $true }
        $res = Get-TmxAb 'get' 'count' '#tw-resultado'
        if ("$res" -match '[1-9]') { $viuResultado = $true; break }
        Start-Sleep -Milliseconds 400
    }
    # O #st-job volta para "Ocioso" 4 s depois do job.done, entao o modal de
    # resultado (que fica aberto) tambem vale como prova de que terminou.
    Assert-Tmx -Nome 'a aplicacao termina (job Concluido / modal de resultado)' `
        -Condicao ($viuJob -or $viuResultado) -Detalhe "st-job='$viuJob' resultado='$viuResultado'"

    Invoke-AB 'click' '#modal-buttons .btn' | Out-Null

    $estado = Wait-TmxTexto -Seletor '.tweak[data-id=TST-001] .estado' -Curinga '*aplicado*' -TimeoutSeconds 60
    Assert-Tmx -Nome 'TST-001 passa a mostrar o estado aplicado' -Condicao ($estado -like '*aplicado*') -Detalhe "obtido: '$estado'"

    # --- 8. desfazer por item ------------------------------------------------
    Invoke-AB 'click' '.tweak[data-id=TST-001] .tw-undo' | Out-Null
    $revertido = Wait-TmxTexto -Seletor '.tweak[data-id=TST-001] .estado' -Curinga '*revertido*' -TimeoutSeconds 90
    Assert-Tmx -Nome 'Desfazer do item deixa o estado revertido' -Condicao ($revertido -like '*revertido*') -Detalhe "obtido: '$revertido'"

    Invoke-AB 'screenshot' $print1 | Out-Null
    Write-Host "Prints: $print1 | $print2"

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
