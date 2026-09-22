<#
.SYNOPSIS
    Roda o TweakMaxing direto do repositorio, sem compilar.
.DESCRIPTION
    Faz o que o TweakMaxing.ps1 compilado faz sozinho:
      1. dot-source de src/Core, src/Engine e src/functions/** NA MESMA ORDEM do
         .psm1 (e preciso ser dot-source, e nao Import-Module: start.ps1,
         main.ps1 e as runspaces esperam as funcoes na sessao, nao num modulo);
      2. versao/repo via variaveis de ambiente, ja que os marcadores #{version}
         e #{repo} do start.ps1 so sao substituidos pelo Compile.ps1;
      3. scripts/start.ps1 - que publica $global:sync (por isso main.ps1 e as
         funcoes conseguem enxerga-lo);
      4. src/config/*.json em $sync.configs, $sync.webRoot = src/web e
         $sync.sdkDir = packages/webview2 (baixado se faltar);
      5. scripts/main.ps1 com os mesmos parametros.
.EXAMPLE
    .\Start-TmxDev.ps1
.EXAMPLE
    .\Start-TmxDev.ps1 -TestMode -DebugPort 9333 -NoElevate
.EXAMPLE
    .\Start-TmxDev.ps1 -Headless -Preset desktop -DryRun -NoElevate
#>
param(
    [switch] $Headless,
    [ValidateSet('desktop', 'notebook', 'minimo', '')]
    [string] $Preset,
    [switch] $DryRun,
    [string] $Undo,
    [int]    $DebugPort,
    [switch] $TestMode,
    [switch] $NoElevate
)

$ErrorActionPreference = 'Stop'
$raiz = $PSScriptRoot

# --- 1. Funcoes -------------------------------------------------------------
$ordemCore   = 'Logger', 'Backup', 'Registry', 'Rollback', 'RestorePoint', 'Guard'
$ordemEngine = 'Condition', 'Profile', 'Catalog', 'Plan', 'Actions', 'Apply', 'Preview'
$pastasFunc  = 'tweaks', 'install', 'features', 'session', 'bridge', 'ui'

foreach ($nome in $ordemCore) {
    $caminho = Join-Path $raiz "src\Core\$nome.ps1"
    if (-not (Test-Path -LiteralPath $caminho)) { throw "Core\$nome.ps1 nao encontrado." }
    . $caminho
}

$carregados = New-Object 'System.Collections.Generic.List[string]'
$dirEngine  = Join-Path $raiz 'src\Engine'
foreach ($nome in $ordemEngine) {
    $caminho = Join-Path $dirEngine "$nome.ps1"
    if (Test-Path -LiteralPath $caminho) { . $caminho; $carregados.Add("$nome.ps1") }
}
if (Test-Path -LiteralPath $dirEngine) {
    foreach ($arquivo in (Get-ChildItem -LiteralPath $dirEngine -Filter '*.ps1' -File | Sort-Object Name)) {
        if (-not $carregados.Contains($arquivo.Name)) { . $arquivo.FullName }
    }
}

foreach ($pasta in $pastasFunc) {
    $dir = Join-Path $raiz "src\functions\$pasta"
    if (-not (Test-Path -LiteralPath $dir)) { continue }
    foreach ($arquivo in (Get-ChildItem -LiteralPath $dir -Filter '*.ps1' -File | Sort-Object Name)) {
        . $arquivo.FullName
    }
}

# --- 2. Versao e repositorio ------------------------------------------------
$arquivoVersao = Join-Path $raiz 'VERSION'
$env:TMX_DEV_VERSION = if (Test-Path -LiteralPath $arquivoVersao) {
    (Get-Content -LiteralPath $arquivoVersao -Raw).Trim()
} else {
    '0.0.0-dev'
}
if (-not $env:TMX_DEV_REPO) { $env:TMX_DEV_REPO = 'TweakMaxing/TweakMaxing' }

# --- 3. Bootstrap -----------------------------------------------------------
& (Join-Path $raiz 'scripts\start.ps1') @PSBoundParameters | Out-Null

if ($null -eq $global:sync) {
    # start.ps1 relancou elevado ou recusou o host.
    return
}
$sync = $global:sync

# --- 4. Recursos de desenvolvimento ----------------------------------------
$dirConfig = Join-Path $raiz 'src\config'
if (Test-Path -LiteralPath $dirConfig) {
    foreach ($arquivo in (Get-ChildItem -LiteralPath $dirConfig -Filter '*.json' -File | Sort-Object Name)) {
        try {
            $sync.configs[$arquivo.BaseName] = Get-Content -LiteralPath $arquivo.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        } catch {
            Write-Warning "config '$($arquivo.Name)' invalido: $($_.Exception.Message)"
        }
    }
}

$sync.webRoot = Join-Path $raiz 'src\web'
$sync.sdkDir  = Join-Path $raiz 'packages\webview2'

if (-not (Test-Path -LiteralPath (Join-Path $sync.sdkDir 'Microsoft.Web.WebView2.Wpf.dll'))) {
    Write-Host 'SDK do WebView2 ausente; baixando...' -ForegroundColor Cyan
    & (Join-Path $raiz 'tools\Get-WebView2Sdk.ps1')
}

# --- 5. Orquestrador --------------------------------------------------------
& (Join-Path $raiz 'scripts\main.ps1') @PSBoundParameters

$codigo = 0
if ($null -ne $global:TmxExitCode) { $codigo = [int]$global:TmxExitCode }
exit $codigo
