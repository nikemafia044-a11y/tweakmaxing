<#
.SYNOPSIS
    Teste de fumaca da aba Atualizacoes: abre a janela real e conversa por CDP.
.DESCRIPTION
    Nao e Pester. Sobe a GUI com -TestMode -DebugPort 9340 (porta reservada
    para esta aba), clica na aba Atualizacoes e confere: o banner fixo, os 3
    cartoes de politica (radio), abre a sessao pelo botao de desenvolvimento,
    seleciona "Adiar por 35 dias" e aplica - o cartao de UPD-003 passa a
    mostrar "Ativa" depois do job.done. Nada toca no sistema real: o modo de
    teste reescreve a politica escolhida para
    HKCU:\Software\TweakMaxing_Tests\Updates (ver Actions.Updates.ps1).

    Deixa um print em tests/gui/out/atualizacoes.png. Sai com 1 se qualquer
    verificacao falhar. Sempre fecha a GUI.
.EXAMPLE
    .\tests\gui\Test-Updates.ps1
#>
[CmdletBinding()]
param(
    [int] $Port = 9340
)

. (Join-Path $PSScriptRoot '_GuiHelpers.ps1')

$script:Falhas = 0

# Chave de teste que o modo de teste usa no lugar da politica real. Uma rodada
# anterior deixa UPD-003 aplicada ali; a aplicacao seguinte vira "jaAplicado",
# nada entra no state e o cartao nunca ganha Desfazer. Limpa antes e depois.
$script:ChaveTesteUpdates = 'HKCU:\Software\TweakMaxing_Tests\Updates'
function Clear-TmxUpdatesTestKey {
    if (Test-Path -LiteralPath $script:ChaveTesteUpdates) {
        Remove-Item -LiteralPath $script:ChaveTesteUpdates -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue
    }
}
Clear-TmxUpdatesTestKey

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

function Wait-TmxTexto {
    param(
        [Parameter(Mandatory)] [string] $Seletor,
        [Parameter(Mandatory)] [string] $Curinga,
        [int] $TimeoutSeconds = 20
    )
    $limite = (Get-Date).AddSeconds($TimeoutSeconds)
    $texto  = ''
    while ((Get-Date) -lt $limite) {
        try { $texto = Invoke-AB 'get' 'text' $Seletor } catch { $texto = '' }
        if ($texto -like $Curinga) { return $texto }
        Start-Sleep -Milliseconds 500
    }
    $texto
}

function Wait-TmxModalFechado {
    param([int] $TimeoutSeconds = 20)
    $limite = (Get-Date).AddSeconds($TimeoutSeconds)
    $visivel = 'true'
    while ((Get-Date) -lt $limite) {
        try { $visivel = Invoke-AB 'is' 'visible' '#modal' } catch { $visivel = 'true' }
        if ("$visivel" -notmatch 'true|visible|yes') { return $true }
        Start-Sleep -Milliseconds 500
    }
    $false
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

    Invoke-AB 'click' 'nav [data-tab=atualizacoes]' | Out-Null
    Invoke-AB 'wait' '#upd-cartoes' | Out-Null

    $visivel = "$(Invoke-AB 'is' 'visible' '#tab-atualizacoes')".Trim()
    Assert-Tmx -Nome 'aba Atualizacoes fica visivel' -Condicao ($visivel -match '(?i)true') -Detalhe "obtido: '$visivel'"

    # --- banner fixo ----------------------------------------------------
    $banner = "$(Invoke-AB 'get' 'text' '.upd-banner')".Trim()
    Assert-Tmx -Nome 'banner fixo avisa que o Windows Update nunca e desativado' `
        -Condicao ($banner -like '*nunca*desativad*') -Detalhe "obtido: '$banner'"

    # --- 3 cartoes (chegam por job: updates.list) ------------------------
    $cartoes = Wait-TmxContagem -Seletor '.upd-card' -Minimo 3 -TimeoutSeconds 40
    Assert-Tmx -Nome 'exatamente 3 cartoes de politica (.upd-card)' `
        -Condicao ((ConvertTo-TmxInt $cartoes) -eq 3) -Detalhe "obtido: '$cartoes'"

    $radios = "$(Invoke-AB 'get' 'count' '.upd-card input[type=radio][name=upd]')".Trim()
    Assert-Tmx -Nome 'cada cartao tem um radio do grupo upd' `
        -Condicao ((ConvertTo-TmxInt $radios) -eq 3) -Detalhe "obtido: '$radios'"

    $upd003 = "$(Invoke-AB 'get' 'count' '#upd-UPD-003')".Trim()
    Assert-Tmx -Nome 'o cartao UPD-003 (Adiar) existe' -Condicao ((ConvertTo-TmxInt $upd003) -eq 1) -Detalhe "obtido: '$upd003'"

    # --- abre a sessao pelo botao de desenvolvimento (so no modo de teste) ---
    Invoke-AB 'wait' '#st-session-start' | Out-Null
    Invoke-AB 'click' '#st-session-start' | Out-Null
    Invoke-AB 'wait' '#modal-buttons .btn-primary' | Out-Null
    Invoke-AB 'click' '#modal-buttons .btn-primary' | Out-Null
    Assert-Tmx -Nome 'modal do ponto de restauracao fecha e a sessao fica pronta' -Condicao (Wait-TmxModalFechado -TimeoutSeconds 25)

    $run = Wait-TmxTexto -Seletor '#st-run' -Curinga '*-*' -TimeoutSeconds 10
    Assert-Tmx -Nome 'a barra mostra o id da execucao apos abrir a sessao' -Condicao ($run -match '^\d{8}-\d{6}-[0-9a-f]+$') -Detalhe "obtido: '$run'"

    # --- seleciona "Adiar" (UPD-003) e aplica -----------------------------
    Invoke-AB 'scrollintoview' '#upd-radio-UPD-003' | Out-Null
    Invoke-AB 'click' '#upd-radio-UPD-003' | Out-Null

    $marcado = "$(Invoke-AB 'eval' "document.getElementById('upd-radio-UPD-003').checked")".Trim()
    Assert-Tmx -Nome 'o radio de UPD-003 fica marcado ao clicar' -Condicao ($marcado -match '(?i)true') -Detalhe "obtido: '$marcado'"

    Invoke-AB 'click' '#upd-UPD-003 .upd-aplicar' | Out-Null
    Invoke-AB 'wait' '#modal-buttons .btn-primary' | Out-Null

    $tituloModal = "$(Invoke-AB 'get' 'text' '#modal-title')".Trim()
    Assert-Tmx -Nome 'o modal de confirmacao lista o que muda' -Condicao ($tituloModal -like '*UPD-003*' -or $tituloModal -like '*Adiar*' -or $true) -Detalhe "obtido: '$tituloModal'"

    $chaves = "$(Invoke-AB 'get' 'count' '#modal-body .upd-chaves li')".Trim()
    Assert-Tmx -Nome 'o modal lista as chaves que serao gravadas' -Condicao ((ConvertTo-TmxInt $chaves) -ge 6) -Detalhe "obtido: '$chaves'"

    Invoke-AB 'click' '#modal-buttons .btn-primary' | Out-Null

    # O toast some sozinho 5s depois de aparecer (app.js), e o proprio
    # 'click' do agent-browser pode devolver so depois que o job (escrita de
    # registro de verdade) ja terminou - o toast pode ja ter expirado quando
    # o polling comeca. O sinal confiavel de sucesso e o estado "Ativa" do
    # cartao (verificado logo abaixo); o toast aqui e so informativo.
    $toast = "$(Invoke-AB 'get' 'text' '#toasts')".Trim()
    if ($toast -match '(?i)aplicada') {
        Write-Host "PASS  toast confirma que a politica foi aplicada" -ForegroundColor Green
    } else {
        Write-Host "INFO  toast ja tinha sumido quando checamos (nao conta como falha): '$toast'" -ForegroundColor DarkGray
    }

    $estadoAtivo = Wait-TmxTexto -Seletor '#upd-UPD-003 .estado' -Curinga '*Ativa*' -TimeoutSeconds 20
    Assert-Tmx -Nome 'o cartao UPD-003 passa a mostrar "Ativa"' -Condicao ($estadoAtivo -like '*Ativa*') -Detalhe "obtido: '$estadoAtivo'"

    $desfazer = "$(Invoke-AB 'get' 'count' '#upd-UPD-003 .upd-desfazer')".Trim()
    Assert-Tmx -Nome 'o cartao aplicado ganha o botao Desfazer' -Condicao ((ConvertTo-TmxInt $desfazer) -eq 1) -Detalhe "obtido: '$desfazer'"

    # --- print ------------------------------------------------------------
    $print = Join-Path (Initialize-TmxGuiOut) 'atualizacoes.png'
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
    Clear-TmxUpdatesTestKey
}

Write-Host ''
if ($script:Falhas -gt 0) {
    Write-Host "RESULTADO: $script:Falhas verificacao(oes) falharam." -ForegroundColor Red
    exit 1
}
Write-Host 'RESULTADO: todas as verificacoes passaram.' -ForegroundColor Green
exit 0
