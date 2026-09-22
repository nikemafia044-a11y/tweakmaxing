<#
.SYNOPSIS
    Teste de fumaca da casca da GUI: abre a janela real e conversa por CDP.
.DESCRIPTION
    Nao e Pester. Sobe a Start-TmxDev.ps1 com -TestMode -DebugPort, conecta o
    agent-browser e confere o que a Task 8 promete: cabecalho, versao, cinco
    abas navegaveis e barra de status. Deixa um print em tests/gui/out/shell.png.

    Sai com 1 se qualquer verificacao falhar. Sempre fecha a GUI.
.EXAMPLE
    .\tests\gui\Test-Shell.ps1
.EXAMPLE
    .\tests\gui\Test-Shell.ps1 -Port 9444
#>
[CmdletBinding()]
param(
    [int] $Port = 9333
)

. (Join-Path $PSScriptRoot '_GuiHelpers.ps1')

$raizRepo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$versaoEsperada = (Get-Content -LiteralPath (Join-Path $raizRepo 'VERSION') -Raw).Trim()

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

$abas = @(
    @{ chave = 'instalar';    rotulo = 'Instalar' }
    @{ chave = 'ajustes';     rotulo = 'Ajustes' }
    @{ chave = 'configurar';  rotulo = 'Configurar' }
    @{ chave = 'atualizacoes'; rotulo = 'Atualizacoes' }
    @{ chave = 'microwin';    rotulo = 'MicroWin' }
)

$gui = $null
try {
    Write-Host "Abrindo a GUI em modo de teste (CDP $Port)..." -ForegroundColor Cyan
    $gui = Start-TmxGui -Port $Port -TestMode
    Write-Host "CDP: $($gui.versaoCdp.Browser)"

    # Conectar antes da navegacao prende o agent-browser num about:blank.
    $pagina = Wait-TmxGuiPage -Port $Port
    Write-Host "Pagina: $($pagina.url)"

    Invoke-AB 'connect' "$Port" | Out-Null
    Invoke-AB 'wait' '#st-rp' | Out-Null

    $logo = Invoke-AB 'get' 'text' 'header .logo'
    Assert-Tmx -Nome 'cabecalho mostra TweakMaxing' -Condicao ($logo -like '*TweakMaxing*') -Detalhe "obtido: '$logo'"

    $versao = ''
    $fim = (Get-Date).AddSeconds(15)
    while ((Get-Date) -lt $fim) {
        $versao = Invoke-AB 'get' 'text' '#versao'
        if ($versao -eq $versaoEsperada) { break }
        Start-Sleep -Milliseconds 500
    }
    Assert-Tmx -Nome "#versao = $versaoEsperada (veio da ponte)" -Condicao ($versao -eq $versaoEsperada) -Detalhe "obtido: '$versao'"

    $quantas = Invoke-AB 'get' 'count' 'nav [data-tab]'
    Assert-Tmx -Nome 'nav tem 5 abas' -Condicao ("$quantas".Trim() -eq '5') -Detalhe "obtido: '$quantas'"

    foreach ($aba in $abas) {
        Invoke-AB 'click' ("nav [data-tab={0}]" -f $aba.chave) | Out-Null
        $visivel = Invoke-AB 'is' 'visible' ("#tab-{0}" -f $aba.chave)
        Assert-Tmx -Nome ("aba {0} abre #tab-{1}" -f $aba.rotulo, $aba.chave) `
                   -Condicao ("$visivel" -match 'true|visible|yes') -Detalhe "obtido: '$visivel'"
    }

    $rp = Invoke-AB 'get' 'text' '#st-rp'
    Assert-Tmx -Nome 'status diz que nao ha ponto de restauracao' -Condicao ($rp -like '*Nenhum ponto*') -Detalhe "obtido: '$rp'"

    $job = Invoke-AB 'get' 'text' '#st-job'
    Assert-Tmx -Nome 'status do trabalho comeca ocioso' -Condicao ($job -like '*Ocioso*') -Detalhe "obtido: '$job'"

    # Volta para a aba padrao antes do print.
    Invoke-AB 'click' 'nav [data-tab=ajustes]' | Out-Null
    $print = Join-Path (Initialize-TmxGuiOut) 'shell.png'
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
