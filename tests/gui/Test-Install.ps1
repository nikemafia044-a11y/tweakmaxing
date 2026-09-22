<#
.SYNOPSIS
    Teste de fumaca da aba Instalar: abre a janela real e conversa por CDP.
.DESCRIPTION
    Nao e Pester. Sobe a GUI com -TestMode -DebugPort 9334 (porta reservada
    para esta aba - a 9333 e da Task 8/shell e pode estar em uso por outro
    agente), clica na aba Instalar, confere o catalogo renderizado (>= 200
    apps), o filtro de busca, a selecao de apps e o painel de gerenciadores.
    Deixa um print em tests/gui/out/instalar.png.

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

function Wait-TmxOutroTestePid {
    <#
    .SYNOPSIS
        Espera ate 3 minutos se tests/gui/out/gui.pid apontar para um
        processo vivo (outro agente rodando o teste de fumaca na 9333).
    #>
    param([int] $TimeoutSeconds = 180)

    Initialize-TmxGuiOut | Out-Null
    if (-not (Test-Path -LiteralPath $script:TmxGuiPidFile)) { return }

    $pidAnterior = 0
    [int]::TryParse((Get-Content -LiteralPath $script:TmxGuiPidFile -Raw).Trim(), [ref]$pidAnterior) | Out-Null
    if ($pidAnterior -le 0) { return }

    $proc = Get-Process -Id $pidAnterior -ErrorAction SilentlyContinue
    if (-not $proc) { return }

    Write-Host "Outro teste de GUI (PID $pidAnterior) parece ativo; esperando ate $TimeoutSeconds s..." -ForegroundColor Cyan
    $limite = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $limite) {
        $proc = Get-Process -Id $pidAnterior -ErrorAction SilentlyContinue
        if (-not $proc) { return }
        Start-Sleep -Seconds 2
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

    Invoke-AB 'click' 'nav [data-tab=instalar]' | Out-Null
    Invoke-AB 'wait' '#app-categorias details.categoria' | Out-Null

    # O catalogo tem 236 apps; renderiza tudo de uma vez (sem paginacao).
    $limite = (Get-Date).AddSeconds(20)
    $total = '0'
    while ((Get-Date) -lt $limite) {
        $total = "$(Invoke-AB 'get' 'count' '.app')".Trim()
        $n = 0
        if ([int]::TryParse($total, [ref]$n) -and $n -ge 200) { break }
        Start-Sleep -Milliseconds 300
    }
    $totalNum = 0
    [int]::TryParse($total, [ref]$totalNum) | Out-Null
    Assert-Tmx -Nome 'catalogo renderiza pelo menos 200 apps (.app)' -Condicao ($totalNum -ge 200) -Detalhe "obtido: '$total'"

    Invoke-AB 'fill' '#app-busca' 'firefox' | Out-Null
    Start-Sleep -Milliseconds 400
    $filtrado = "$(Invoke-AB 'get' 'count' '.app')".Trim()
    $filtradoNum = 999
    [int]::TryParse($filtrado, [ref]$filtradoNum) | Out-Null
    Assert-Tmx -Nome 'busca "firefox" deixa no maximo 5 apps visiveis (.app)' -Condicao ($filtradoNum -le 5) -Detalhe "obtido: '$filtrado'"

    Invoke-AB 'scrollintoview' '#app-firefox' | Out-Null
    Invoke-AB 'check' '#app-firefox' | Out-Null
    Invoke-AB 'scrollintoview' '#app-firefoxesr' | Out-Null
    Invoke-AB 'check' '#app-firefoxesr' | Out-Null
    Start-Sleep -Milliseconds 200
    $selecionados = Invoke-AB 'get' 'text' '#app-selecionados'
    Assert-Tmx -Nome '#app-selecionados mostra 2 apos marcar 2 caixas' -Condicao ("$selecionados".Trim() -eq '2') -Detalhe "obtido: '$selecionados'"

    # Limpa a busca antes de conferir o painel de gerenciadores (nao depende
    # do filtro, mas deixa a tela num estado previsivel para o print).
    Invoke-AB 'fill' '#app-busca' '' | Out-Null

    $wingetOk = "$(Invoke-AB 'get' 'count' '#app-gerenciadores .gm:first-child .ok')".Trim()
    Assert-Tmx -Nome 'painel de gerenciadores mostra winget disponivel (esta maquina tem winget)' `
        -Condicao ($wingetOk -eq '1') -Detalhe "obtido: '$wingetOk'"

    $print = Join-Path (Initialize-TmxGuiOut) 'instalar.png'
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
