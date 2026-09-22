<#
.SYNOPSIS
    Baixa e extrai o SDK do WebView2 (net462 + loader x64) para packages/webview2.
.DESCRIPTION
    O pacote NuGet e baixado uma unica vez para packages/webview2.nupkg e tem o
    SHA256 conferido antes de qualquer extracao - divergencia apaga o arquivo e
    lanca. A extracao e idempotente: rodar de novo so reconfere e recopia.

    packages/ esta no .gitignore; nenhuma DLL entra no repositorio.
.EXAMPLE
    .\tools\Get-WebView2Sdk.ps1
.EXAMPLE
    .\tools\Get-WebView2Sdk.ps1 -Force
#>
[CmdletBinding()]
param(
    [string] $Version = '1.0.3240.44',
    [string] $Sha256  = '8a8841b6d78c40010d7340287fd55e1355c717568aca7abcc3a14a86280babf7',
    [switch] $Force
)

$ErrorActionPreference = 'Stop'

$repoRoot    = Split-Path $PSScriptRoot -Parent
$packagesDir = Join-Path $repoRoot 'packages'
$nupkgPath   = Join-Path $packagesDir 'webview2.nupkg'
$destDir     = Join-Path $packagesDir 'webview2'

New-Item -ItemType Directory -Path $packagesDir -Force | Out-Null

if ($Force -and (Test-Path -LiteralPath $nupkgPath)) {
    Remove-Item -LiteralPath $nupkgPath -Force
}

if (-not (Test-Path -LiteralPath $nupkgPath)) {
    $url = "https://www.nuget.org/api/v2/package/Microsoft.Web.WebView2/$Version"
    Write-Host "Baixando $url"
    # TLS 1.2 explicito: o default do PS 5.1 ainda e SSL3/TLS1.0 em maquinas antigas.
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $url -OutFile $nupkgPath -UseBasicParsing
} else {
    Write-Host "Pacote ja presente: $nupkgPath"
}

$hash = (Get-FileHash -LiteralPath $nupkgPath -Algorithm SHA256).Hash
if ($hash -ne $Sha256.ToUpperInvariant()) {
    Remove-Item -LiteralPath $nupkgPath -Force -ErrorAction SilentlyContinue
    throw "SHA256 do pacote nao confere (esperado $Sha256, obtido $hash). Arquivo removido."
}
Write-Host "SHA256 conferido: $hash"

$temp = Join-Path ([IO.Path]::GetTempPath()) ('tmx-wv2-{0}' -f ([guid]::NewGuid().ToString('N')))
New-Item -ItemType Directory -Path $temp -Force | Out-Null
try {
    # Expand-Archive so aceita .zip; o .nupkg e um zip com outra extensao.
    $zipPath = Join-Path $temp 'webview2.zip'
    Copy-Item -LiteralPath $nupkgPath -Destination $zipPath -Force
    Expand-Archive -LiteralPath $zipPath -DestinationPath (Join-Path $temp 'x') -Force

    New-Item -ItemType Directory -Path $destDir -Force | Out-Null

    $itens = @(
        @{ origem = 'lib\net462\Microsoft.Web.WebView2.Core.dll'; destino = 'Microsoft.Web.WebView2.Core.dll' }
        @{ origem = 'lib\net462\Microsoft.Web.WebView2.Wpf.dll';  destino = 'Microsoft.Web.WebView2.Wpf.dll' }
        @{ origem = 'runtimes\win-x64\native\WebView2Loader.dll'; destino = 'WebView2Loader.dll' }
        @{ origem = 'LICENSE.txt';                                destino = 'LICENSE.txt' }
    )

    foreach ($item in $itens) {
        $src = Join-Path (Join-Path $temp 'x') $item.origem
        if (-not (Test-Path -LiteralPath $src)) { throw "Arquivo ausente no pacote: $($item.origem)" }
        $dst = Join-Path $destDir $item.destino
        Copy-Item -LiteralPath $src -Destination $dst -Force
    }

    Unblock-File -Path (Join-Path $destDir '*.dll') -ErrorAction SilentlyContinue

    Set-Content -LiteralPath (Join-Path $destDir 'VERSION.txt') -Value $Version -Encoding ASCII

    foreach ($item in $itens) {
        $dst = Get-Item -LiteralPath (Join-Path $destDir $item.destino)
        Write-Host ('{0,-40} {1,10} bytes' -f $dst.Name, $dst.Length)
    }
    Write-Host "SDK pronto em: $destDir"
} finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
