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

# _GuiHelpers.ps1 agora isola tudo por porta (PID em out\gui-<porta>.pid,
# varredura de processo orfao filtrada pela porta na linha de comando) -
# Start-TmxGui/Clear-TmxGuiLeftovers ja cuidam de nao derrubar um teste de
# GUI concorrente noutra porta, entao nao ha mais o que esperar aqui.

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

    # Logos: pelo menos um .app-icone (iniciais ou imagem) por linha renderizada.
    $totalIcones = "$(Invoke-AB 'get' 'count' '.app-icone')".Trim()
    $totalIconesNum = 0
    [int]::TryParse($totalIcones, [ref]$totalIconesNum) | Out-Null
    Assert-Tmx -Nome 'pelo menos um .app-icone presente' -Condicao ($totalIconesNum -ge 1) -Detalhe "obtido: '$totalIcones'"

    Invoke-AB 'errors' '--clear' | Out-Null
    Invoke-AB 'scrollintoview' '#app-firefox' | Out-Null
    Invoke-AB 'scroll' 'down' '1200' | Out-Null
    Start-Sleep -Milliseconds 500
    Invoke-AB 'scroll' 'down' '1200' | Out-Null
    Start-Sleep -Milliseconds 1000
    $erros = "$(Invoke-AB 'errors')".Trim()
    Assert-Tmx -Nome 'nenhum erro de JS depois de rolar a lista (icones lazy)' -Condicao ([string]::IsNullOrWhiteSpace($erros) -or $erros -match '(?i)no errors|nenhum erro') -Detalhe "obtido: '$erros'"

    # Icone real (nao so iniciais) num app de fato instalado nesta maquina, se
    # houver um: casa DisplayName do registro de Desinstalar (igual ou "nome +
    # espaco", mesma regra do back-end) contra o catalogo. So roda se achar
    # candidato - "se viavel", como o pedido de revisao descreve.
    $raizRepo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $catalogoApps = @((Get-Content -LiteralPath (Join-Path $raizRepo 'src\config\applications.json') -Raw -Encoding UTF8 | ConvertFrom-Json).aplicativos)
    $nomesInstalados = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    ) | ForEach-Object {
        Get-ItemProperty -Path $_ -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -and $_.DisplayIcon } |
            Select-Object -ExpandProperty DisplayName
    }
    $candidato = $null
    foreach ($app in $catalogoApps) {
        $nomeApp = "$($app.nome)"
        if (-not $nomeApp) { continue }
        $bate = @($nomesInstalados | Where-Object { $_ -ieq $nomeApp -or $_.StartsWith("$nomeApp ", [System.StringComparison]::OrdinalIgnoreCase) })
        if ($bate.Count -gt 0) { $candidato = $app.id; break }
    }

    if ($candidato) {
        Write-Host "Candidato a icone real (app instalado nesta maquina): $candidato"
        Invoke-AB 'scrollintoview' "#app-$candidato" | Out-Null

        $limiteIcone = (Get-Date).AddSeconds(20)
        $temImagem = '0'
        while ((Get-Date) -lt $limiteIcone) {
            $temImagem = "$(Invoke-AB 'get' 'count' "[data-id=$candidato] .app-icone img")".Trim()
            if ($temImagem -eq '1') { break }
            Start-Sleep -Milliseconds 500
        }
        Assert-Tmx -Nome "icone real (<img>) aparece para '$candidato' (instalado nesta maquina) dentro de 20s" `
            -Condicao ($temImagem -eq '1') -Detalhe "obtido: '$temImagem'"
    } else {
        Write-Host 'Nenhum app do catalogo bate com um instalado nesta maquina - pulando o teste de icone real.' -ForegroundColor DarkYellow
    }

    Invoke-AB 'fill' '#app-busca' 'firefox' | Out-Null
    Start-Sleep -Milliseconds 400
    $filtrado = "$(Invoke-AB 'get' 'count' '.app')".Trim()
    $filtradoNum = 999
    [int]::TryParse($filtrado, [ref]$filtradoNum) | Out-Null
    # Esperado = apps do catalogo cujo nome ou descricao contem "firefox" (a busca
    # olha os dois). Um numero fixo quebrava a cada descricao nova que cita o Firefox.
    $catApps = @((Get-Content -LiteralPath (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'src\config\applications.json') -Raw -Encoding UTF8 | ConvertFrom-Json).aplicativos)
    $esperado = @($catApps | Where-Object { "$($_.nome) $($_.descricao)" -match 'firefox' }).Count
    Assert-Tmx -Nome 'busca "firefox" mostra exatamente os apps que citam firefox no nome ou descricao' -Condicao ($filtradoNum -eq $esperado -and $esperado -ge 2 -and $esperado -lt $totalNum) -Detalhe "obtido: '$filtrado', esperado: $esperado"

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
