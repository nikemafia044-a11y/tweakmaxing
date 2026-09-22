<#
.SYNOPSIS
    Teste de fumaca da aba Configurar: abre a janela real e conversa por CDP.
.DESCRIPTION
    Nao e Pester. Sobe a GUI com -TestMode -DebugPort 9339 (porta reservada
    para esta aba), clica na aba Configurar e confere as tres colunas: os 14
    paineis legados, os cartoes de correcao, os recursos do Windows com
    interruptor, e o bloco de DNS com os provedores no select.

    O clique em "Painel de Controle" exercita panels.open de ponta a ponta: no
    modo de teste a acao registra a chamada e NAO abre janela nenhuma (senao
    14 janelas do Painel de Controle subiriam por cima do print).

    Deixa um print em tests/gui/out/configurar.png. Sai com 1 se qualquer
    verificacao falhar. Sempre fecha a GUI.
.EXAMPLE
    .\tests\gui\Test-Configure.ps1
#>
[CmdletBinding()]
param(
    [int] $Port = 9339
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
        Espera 'get count <seletor>' chegar a um minimo (a lista de recursos
        chega por job, entao a primeira leitura pode pegar a tela vazia).
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

    Invoke-AB 'click' 'nav [data-tab=configurar]' | Out-Null
    Invoke-AB 'wait' '#cfg-colunas' | Out-Null

    $visivel = "$(Invoke-AB 'is' 'visible' '#tab-configurar')".Trim()
    Assert-Tmx -Nome 'aba Configurar fica visivel' -Condicao ($visivel -match '(?i)true') -Detalhe "obtido: '$visivel'"

    # --- paineis ------------------------------------------------------------
    $paineis = Wait-TmxContagem -Seletor '.painel-btn' -Minimo 14
    Assert-Tmx -Nome 'coluna de paineis tem exatamente 14 botoes (.painel-btn)' `
        -Condicao ((ConvertTo-TmxInt $paineis) -eq 14) -Detalhe "obtido: '$paineis'"

    # --- correcoes ----------------------------------------------------------
    $fixes = Wait-TmxContagem -Seletor '.fix-card' -Minimo 6
    Assert-Tmx -Nome 'coluna de correcoes tem pelo menos 6 cartoes (.fix-card)' `
        -Condicao ((ConvertTo-TmxInt $fixes) -ge 6) -Detalhe "obtido: '$fixes'"

    $botaoUpdate = "$(Invoke-AB 'get' 'count' '#fix-FIX-UPDATE .btn')".Trim()
    Assert-Tmx -Nome 'o cartao do Windows Update traz o botao Executar' `
        -Condicao ((ConvertTo-TmxInt $botaoUpdate) -ge 1) -Detalhe "obtido: '$botaoUpdate'"

    # --- recursos (chegam por job: features.list le o DISM) -----------------
    $recursos = Wait-TmxContagem -Seletor '.feature' -Minimo 6 -TimeoutSeconds 60
    Assert-Tmx -Nome 'coluna de recursos tem pelo menos 6 itens (.feature)' `
        -Condicao ((ConvertTo-TmxInt $recursos) -ge 6) -Detalhe "obtido: '$recursos'"

    $recursoTeste = "$(Invoke-AB 'get' 'count' '#sw-REC-TST')".Trim()
    Assert-Tmx -Nome 'o recurso sintetico REC-TST aparece no modo de teste' `
        -Condicao ((ConvertTo-TmxInt $recursoTeste) -eq 1) -Detalhe "obtido: '$recursoTeste'"

    $switches = "$(Invoke-AB 'get' 'count' '.feature [role=switch]')".Trim()
    Assert-Tmx -Nome 'cada recurso tem um interruptor role=switch' `
        -Condicao ((ConvertTo-TmxInt $switches) -eq (ConvertTo-TmxInt $recursos)) -Detalhe "switches: '$switches' / recursos: '$recursos'"

    # --- DNS ----------------------------------------------------------------
    $opcoes = Wait-TmxContagem -Seletor '#dns-select option' -Minimo 8
    Assert-Tmx -Nome 'o select de DNS traz pelo menos 8 opcoes' `
        -Condicao ((ConvertTo-TmxInt $opcoes) -ge 8) -Detalhe "obtido: '$opcoes'"

    $dhcp = "$(Invoke-AB 'get' 'text' '#dns-select option:first-child')".Trim()
    Assert-Tmx -Nome 'a primeira opcao de DNS e o padrao DHCP' `
        -Condicao ($dhcp -match '(?i)dhcp') -Detalhe "obtido: '$dhcp'"

    $benchmark = "$(Invoke-AB 'get' 'count' '#dns-benchmark')".Trim()
    Assert-Tmx -Nome 'o botao "Testar latencia" existe' `
        -Condicao ((ConvertTo-TmxInt $benchmark) -eq 1) -Detalhe "obtido: '$benchmark'"

    # --- panels.open de ponta a ponta ---------------------------------------
    # No modo de teste a acao devolve simulado=true e nao abre janela alguma;
    # o toast e a prova de que a chamada chegou ao PowerShell e voltou.
    Invoke-AB 'scrollintoview' '#painel-PAN-CONTROL' | Out-Null
    Invoke-AB 'click' '#painel-PAN-CONTROL' | Out-Null

    $limite = (Get-Date).AddSeconds(15)
    $toast = ''
    while ((Get-Date) -lt $limite) {
        $toast = "$(Invoke-AB 'get' 'text' '#toasts')".Trim()
        if ($toast -match '(?i)simulada') { break }
        Start-Sleep -Milliseconds 400
    }
    Assert-Tmx -Nome 'panels.open responde e no modo de teste nao abre o painel de verdade' `
        -Condicao ($toast -match '(?i)simulada') -Detalhe "toast: '$toast'"

    # O mesmo caminho pela ponte, agora lendo o payload (simulado=true).
    $eco = "$(Invoke-AB 'eval' "window.tmx.bridge.call('panels.open',{id:'PAN-NETWORK'}).then(function(r){return JSON.stringify(r);})")".Trim()
    # O eval devolve a string JSON ja escapada pelo CDP, entao as aspas chegam
    # como \" - o padrao aceita as duas formas.
    Assert-Tmx -Nome 'panels.open devolve simulado=true pela ponte' `
        -Condicao ($eco -match '\\?"simulado\\?"\s*:\s*true') -Detalhe "obtido: '$eco'"

    $ruim = "$(Invoke-AB 'eval' "window.tmx.bridge.call('panels.open',{id:'PAN-NAO-EXISTE'}).then(function(){return 'ABRIU';},function(e){return 'RECUSOU: '+e.message;})")".Trim()
    Assert-Tmx -Nome 'panels.open recusa um id fora da tabela fixa' `
        -Condicao ($ruim -match '(?i)recusou') -Detalhe "obtido: '$ruim'"

    # --- print --------------------------------------------------------------
    $print = Join-Path (Initialize-TmxGuiOut) 'configurar.png'
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
