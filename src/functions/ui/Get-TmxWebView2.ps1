# functions/ui/Get-TmxWebView2.ps1
# Onde estao as DLLs do WebView2 e os arquivos da interface.
#
# Dois modos:
#   dev      - $sync.sdkDir (packages/webview2) e $sync.webRoot (src/web).
#   compilado- $sync.embedded.webview2 / $sync.embedded.web (base64/texto
#              embutidos no .ps1 unico) extraidos para %LOCALAPPDATA%.
#
# Extracao por versao: %LOCALAPPDATA%\TweakMaxing\lib\<versao>\ e ...\ui\<versao>\.
# Reescrever a cada abertura seria desperdicio e quebraria uma DLL em uso, entao
# arquivo de mesmo tamanho e considerado igual.

function Get-TmxUiHomePath {
    <#
    .SYNOPSIS
        Raiz de dados da interface ($sync.home quando definido).
    #>
    [CmdletBinding()]
    param()
    if ($null -ne $sync -and $sync.home) { return "$($sync.home)" }
    Join-Path $env:LOCALAPPDATA 'TweakMaxing'
}

function Get-TmxUiVersion {
    [CmdletBinding()]
    param()
    if ($null -ne $sync -and $sync.version) { return "$($sync.version)" }
    '0.0.0'
}

function Get-TmxWebView2Sdk {
    <#
    .SYNOPSIS
        Devolve a pasta com Core.dll, Wpf.dll e WebView2Loader.dll.
    .DESCRIPTION
        Compilado: grava os tres arquivos de $sync.embedded.webview2 (nome ->
        base64) em <home>\lib\<versao>. Dev: devolve $sync.sdkDir como esta.
    #>
    [CmdletBinding()]
    param()

    if ($null -eq $sync) { throw 'Get-TmxWebView2Sdk: $sync nao existe (bootstrap nao rodou).' }

    $embedded = $null
    if ($null -ne $sync.embedded) { $embedded = $sync.embedded.webview2 }

    if ($null -ne $embedded) {
        $destino = Join-Path (Join-Path (Get-TmxUiHomePath) 'lib') (Get-TmxUiVersion)
        New-Item -ItemType Directory -Path $destino -Force | Out-Null

        foreach ($nome in @($embedded.Keys)) {
            $bytes = [Convert]::FromBase64String("$($embedded[$nome])")
            $alvo  = Join-Path $destino $nome
            if (Test-Path -LiteralPath $alvo) {
                $atual = (Get-Item -LiteralPath $alvo).Length
                if ($atual -eq $bytes.Length) { continue }
            }
            [IO.File]::WriteAllBytes($alvo, $bytes)
        }
        return $destino
    }

    if ($sync.sdkDir -and (Test-Path -LiteralPath "$($sync.sdkDir)")) {
        return "$($sync.sdkDir)"
    }

    throw 'SDK do WebView2 nao encontrado. Rode tools\Get-WebView2Sdk.ps1 (dev) ou use o TweakMaxing.ps1 compilado.'
}

function Test-TmxWebView2Runtime {
    <#
    .SYNOPSIS
        Versao do runtime do WebView2 instalado, ou $null se nao houver.
    .NOTES
        Exige que Core.dll ja tenha sido carregada com Add-Type.
    #>
    [CmdletBinding()]
    param()
    try {
        $v = [Microsoft.Web.WebView2.Core.CoreWebView2Environment]::GetAvailableBrowserVersionString()
        if ([string]::IsNullOrWhiteSpace($v)) { return $null }
        "$v"
    } catch {
        Write-Verbose "Runtime do WebView2 indisponivel: $($_.Exception.Message)"
        $null
    }
}

function Get-TmxWebRoot {
    <#
    .SYNOPSIS
        Pasta servida como https://app.tweakmaxing/.
    #>
    [CmdletBinding()]
    param()

    if ($null -eq $sync) { throw 'Get-TmxWebRoot: $sync nao existe (bootstrap nao rodou).' }

    if ($sync.webRoot -and (Test-Path -LiteralPath "$($sync.webRoot)")) {
        return "$($sync.webRoot)"
    }

    $embedded = $null
    if ($null -ne $sync.embedded) { $embedded = $sync.embedded.web }
    if ($null -eq $embedded) {
        throw 'Arquivos da interface nao encontrados (nem $sync.webRoot nem $sync.embedded.web).'
    }

    $destino = Join-Path (Join-Path (Get-TmxUiHomePath) 'ui') (Get-TmxUiVersion)
    New-Item -ItemType Directory -Path $destino -Force | Out-Null

    foreach ($nome in @($embedded.Keys)) {
        $alvo = Join-Path $destino $nome
        $pai  = Split-Path $alvo -Parent
        if (-not (Test-Path -LiteralPath $pai)) { New-Item -ItemType Directory -Path $pai -Force | Out-Null }
        # UTF8 sem BOM: o WebView2 le os arquivos como texto servido por HTTP.
        [IO.File]::WriteAllText($alvo, "$($embedded[$nome])", (New-Object System.Text.UTF8Encoding($false)))
    }
    $destino
}
