<#
.SYNOPSIS
    Gera o artefato unico TweakMaxing.ps1 (funcoes + JSONs + web + modelo do
    MicroWin + DLLs do WebView2 em base64).
.DESCRIPTION
    Modelado em reference/winutil/Compile.ps1 (MIT), com tres diferencas que
    importam:

      1. Nada passa por ConvertTo-Json. No PS 5.1 o ConvertTo-Json escapa todo
         caractere fora do ASCII como \uXXXX e reindenta o documento - o JSON
         que chegaria ao usuario nao seria o JSON do repositorio. Aqui o texto
         de cada arquivo entra VERBATIM dentro de @'...'@ e e parseado em
         tempo de execucao com ConvertFrom-Json.
      2. O arquivo sai em UTF-8 COM BOM. Os JSONs e o HTML/JS sao em portugues,
         com acento; sem BOM o parser do PowerShell 5.1 leria tudo como ANSI.
         (Os fontes .ps1 do repositorio continuam ASCII puro e sem BOM - ver
         tests/Encoding.Tests.ps1.)
      3. O param() do scripts/main.ps1 e REMOVIDO: no artefato tudo e um unico
         script, e um 'param' fora do inicio e erro de sintaxe. Os parametros
         ja existem, vindos do param() do scripts/start.ps1.

    Ordem do arquivo gerado (a mesma do Start-TmxDev.ps1, e ela importa):

      cabecalho -> scripts/start.ps1 -> src/Core -> src/Engine ->
      src/functions/** -> $sync.configs -> $sync.embedded -> scripts/main.ps1

    Os blocos de dados vem DEPOIS do start.ps1 porque e ele quem cria $sync -
    e quando ele decide relancar elevado ele faz 'return', encerrando o script
    antes de qualquer um desses blocos.
.PARAMETER Run
    Executa o artefato recem-gerado.
.PARAMETER SkipSdk
    Nao baixa o SDK do WebView2 quando packages\webview2 estiver ausente. O
    artefato sai SEM as DLLs; nesse caso Get-TmxWebView2Sdk falha com
    'SDK do WebView2 nao encontrado...' e a GUI nao abre (o modo headless,
    que nao usa WebView2, continua funcionando).
.PARAMETER Out
    Caminho do arquivo gerado. Padrao: <repo>\TweakMaxing.ps1.
.PARAMETER Repo
    'usuario/repositorio' para o cabecalho e para a URL de elevacao. Padrao: o
    conteudo do arquivo REPO.
.EXAMPLE
    .\Compile.ps1
.EXAMPLE
    .\Compile.ps1 -Run
.EXAMPLE
    .\Compile.ps1 -SkipSdk -Out C:\temp\TweakMaxing.ps1
#>
[CmdletBinding()]
param(
    [switch] $Run,
    [switch] $SkipSdk,
    [string] $Out,
    [string] $Repo
)

$ErrorActionPreference = 'Stop'

$tmxRaiz = $PSScriptRoot
if (-not $tmxRaiz) { $tmxRaiz = (Get-Location).Path }

# ---------------------------------------------------------------------------
# Auxiliares
# ---------------------------------------------------------------------------

function Get-TmxAssetText {
    <#
    .SYNOPSIS
        Texto de um arquivo, lido como UTF-8, sem BOM e sem qualquer
        normalizacao de fim de linha.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return [System.Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
    }
    [System.Text.Encoding]::UTF8.GetString($bytes)
}

function Assert-TmxHereStringSafe {
    <#
    .SYNOPSIS
        Recusa conteudo que fecharia sozinho a here-string @'...'@ que vai
        embrulha-lo.
    .DESCRIPTION
        Uma linha que COMECA com '@ encerra a here-string literal do
        PowerShell. Se isso passasse batido, o artefato compilaria com o
        restante do arquivo virando codigo - por isso aqui e falha de
        compilacao, com nome do arquivo e numero da linha.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Text,
        [Parameter(Mandatory)] [string] $Origem
    )

    $n = 0
    foreach ($linha in ($Text -split "`r?`n")) {
        $n++
        if ($linha -match "^'@") {
            throw ("{0}:{1}: a linha comeca com ""'@"" e fecharia a here-string do artefato. " -f $Origem, $n) +
                  'Quebre a linha ou recue o texto antes de compilar.'
        }
    }
}

function New-TmxHereString {
    <#
    .SYNOPSIS
        Embrulha um texto em @'...'@ (literal: nada e interpolado la dentro).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string] $Text)
    "@'" + "`r`n" + $Text + "`r`n" + "'@"
}

function Remove-TmxParamBlock {
    <#
    .SYNOPSIS
        Devolve o texto do script sem o bloco param() de nivel de script.
    .DESCRIPTION
        Pela AST, nao por regex: o param() do main.ps1 tem atributos,
        ValidateSet e comentarios no meio.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Text,
        [Parameter(Mandatory)] [string] $Origem
    )

    $tokens = $null
    $erros  = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$tokens, [ref]$erros)
    if ($erros -and @($erros).Count -gt 0) {
        throw "$Origem nao e um script valido: $(@($erros)[0].Message)"
    }
    if ($null -eq $ast.ParamBlock) { return $Text }

    $inicio = $ast.ParamBlock.Extent.StartOffset
    $fim    = $ast.ParamBlock.Extent.EndOffset
    $Text.Substring(0, $inicio) + $Text.Substring($fim)
}

function Get-TmxScriptChunk {
    <#
    .SYNOPSIS
        Texto de um .ps1 do repositorio, com CRLF normalizado e terminando em
        uma linha em branco (dois arquivos colados nao podem virar uma linha
        so).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)

    $texto = Get-TmxAssetText -Path $Path
    $texto = ($texto -replace "`r`n", "`n") -replace "`n", "`r`n"
    $texto.TrimEnd("`r", "`n") + "`r`n"
}

# ---------------------------------------------------------------------------
# 1. Versao, repositorio, commit
# ---------------------------------------------------------------------------

$arquivoVersao = Join-Path $tmxRaiz 'VERSION'
if (-not (Test-Path -LiteralPath $arquivoVersao)) { throw "VERSION nao encontrado em $tmxRaiz." }
$versao = (Get-TmxAssetText -Path $arquivoVersao).Trim()
if (-not $versao) { throw 'VERSION esta vazio.' }

if (-not $Repo) {
    $arquivoRepo = Join-Path $tmxRaiz 'REPO'
    if (-not (Test-Path -LiteralPath $arquivoRepo)) { throw "REPO nao encontrado em $tmxRaiz (ou use -Repo)." }
    foreach ($linha in ((Get-TmxAssetText -Path $arquivoRepo) -split "`r?`n")) {
        $l = "$linha".Trim()
        if (-not $l -or $l.StartsWith('#')) { continue }
        $Repo = $l
        break
    }
}
if ($Repo -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') {
    throw "Repositorio invalido: '$Repo' (esperado 'usuario/repositorio')."
}
if ($Repo -like 'SEU_USUARIO/*') {
    Write-Warning "REPO ainda tem o placeholder '$Repo': a URL de elevacao do artefato nao vai existir."
}

$commit = 'sem-git'
# EAP 'Continue' so aqui: com 'Stop', o stderr de um executavel nativo (git
# ausente, pasta fora de repositorio) vira erro terminante e derruba a
# compilacao - e ficar sem o sha curto nao e motivo para isso.
$eapAnterior = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    $saidaGit = & git -C $tmxRaiz rev-parse --short HEAD 2>$null
    if ($LASTEXITCODE -eq 0 -and "$saidaGit".Trim()) { $commit = "$saidaGit".Trim() }
} catch {
    Write-Verbose "git indisponivel: $($_.Exception.Message)"
} finally {
    $ErrorActionPreference = $eapAnterior
}

$data = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')

if (-not $Out) { $Out = Join-Path $tmxRaiz 'TweakMaxing.ps1' }
# Absoluto ANTES de qualquer escrita: [IO.File] resolve caminho relativo contra
# o diretorio do processo .NET, que nao acompanha o Set-Location do PowerShell -
# um '-Out saida.ps1' iria parar em outro lugar.
if (-not [IO.Path]::IsPathRooted($Out)) { $Out = Join-Path (Get-Location).ProviderPath $Out }
$pastaSaida = Split-Path -Parent $Out
if ($pastaSaida -and -not (Test-Path -LiteralPath $pastaSaida)) {
    New-Item -ItemType Directory -Path $pastaSaida -Force | Out-Null
}

Write-Host "TweakMaxing $versao  ($Repo @ $commit)" -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# 2. SDK do WebView2
# ---------------------------------------------------------------------------

$sdkDir  = Join-Path $tmxRaiz 'packages\webview2'
$sdkDlls = 'Microsoft.Web.WebView2.Core.dll', 'Microsoft.Web.WebView2.Wpf.dll', 'WebView2Loader.dll'

$sdkCompleto = $true
foreach ($dll in $sdkDlls) {
    if (-not (Test-Path -LiteralPath (Join-Path $sdkDir $dll))) { $sdkCompleto = $false }
}

if (-not $sdkCompleto) {
    if ($SkipSdk) {
        Write-Warning 'packages\webview2 ausente e -SkipSdk pedido: o artefato NAO vai conter as DLLs do WebView2 (a GUI nao abre; o modo headless continua valendo).'
    } else {
        Write-Host 'SDK do WebView2 ausente; baixando...' -ForegroundColor Cyan
        & (Join-Path $tmxRaiz 'tools\Get-WebView2Sdk.ps1')
        $sdkCompleto = $true
        foreach ($dll in $sdkDlls) {
            if (-not (Test-Path -LiteralPath (Join-Path $sdkDir $dll))) { $sdkCompleto = $false }
        }
        if (-not $sdkCompleto) { throw 'tools\Get-WebView2Sdk.ps1 rodou mas as tres DLLs continuam ausentes.' }
    }
}

$versaoSdk = '1.0.3240.44'
$arquivoVersaoSdk = Join-Path $sdkDir 'VERSION.txt'
if (Test-Path -LiteralPath $arquivoVersaoSdk) {
    $v = (Get-TmxAssetText -Path $arquivoVersaoSdk).Trim()
    if ($v) { $versaoSdk = $v }
}

# ---------------------------------------------------------------------------
# 3. Montagem
# ---------------------------------------------------------------------------

$sb = New-Object System.Text.StringBuilder

# --- Cabecalho --------------------------------------------------------------
$cabecalho = @"
<#
    TweakMaxing v$versao - arquivo unico gerado por Compile.ps1.
    Nao edite aqui: toda alteracao vive no repositorio.

    Licenca MIT. Obra derivada do WinUtil (c) 2022 CT Tech Group LLC (MIT) -
    nao afiliado. Inclui Microsoft.Web.WebView2 $versaoSdk (BSD-3) embutida em
    base64; veja THIRD-PARTY-NOTICES.md no repositorio.

    Fonte: https://github.com/$Repo
    Compilado em $data a partir do commit $commit.
    SHA256 publicado em SHA256SUMS.txt.
#>
"@
[void]$sb.AppendLine($cabecalho)
[void]$sb.AppendLine()

# --- scripts/start.ps1 ------------------------------------------------------
$start = Get-TmxScriptChunk -Path (Join-Path $tmxRaiz 'scripts\start.ps1')
$start = $start.Replace('#{version}', $versao).Replace('#{repo}', $Repo)
if ($start -notmatch '#TMX-COMPILED') { throw 'scripts\start.ps1 perdeu o marcador #TMX-COMPILED.' }
# So os dois marcadores de substituicao: o '#{*' do -like que detecta o modo de
# desenvolvimento continua no texto de proposito.
if ($start -match '#\{(version|repo)\}') { throw 'scripts\start.ps1 tem marcador #{...} nao substituido.' }
[void]$sb.AppendLine($start)

# --- Funcoes (mesma ordem do Start-TmxDev.ps1) ------------------------------
[void]$sb.AppendLine('# =========================================================================')
[void]$sb.AppendLine('# TMX-FUNCOES')
[void]$sb.AppendLine('# =========================================================================')

$ordemCore   = 'Logger', 'Backup', 'Registry', 'Rollback', 'RestorePoint', 'Guard'
$ordemEngine = 'Condition', 'Profile', 'Catalog', 'Plan', 'Actions', 'Apply', 'Preview'
$pastasFunc  = 'tweaks', 'install', 'features', 'microwin', 'session', 'bridge', 'ui'

$fontes = New-Object 'System.Collections.Generic.List[string]'

foreach ($nome in $ordemCore) {
    $caminho = Join-Path $tmxRaiz "src\Core\$nome.ps1"
    if (-not (Test-Path -LiteralPath $caminho)) { throw "Core\$nome.ps1 nao encontrado." }
    $fontes.Add($caminho)
}

$dirEngine = Join-Path $tmxRaiz 'src\Engine'
$jaVisto = New-Object 'System.Collections.Generic.List[string]'
foreach ($nome in $ordemEngine) {
    $caminho = Join-Path $dirEngine "$nome.ps1"
    if (Test-Path -LiteralPath $caminho) { $fontes.Add($caminho); $jaVisto.Add("$nome.ps1") }
}
foreach ($arquivo in (Get-ChildItem -LiteralPath $dirEngine -Filter '*.ps1' -File | Sort-Object Name)) {
    if (-not $jaVisto.Contains($arquivo.Name)) { $fontes.Add($arquivo.FullName) }
}

foreach ($pasta in $pastasFunc) {
    $dir = Join-Path $tmxRaiz "src\functions\$pasta"
    if (-not (Test-Path -LiteralPath $dir)) { continue }
    foreach ($arquivo in (Get-ChildItem -LiteralPath $dir -Filter '*.ps1' -File | Sort-Object Name)) {
        $fontes.Add($arquivo.FullName)
    }
}

foreach ($caminho in $fontes.ToArray()) {
    $relativo = $caminho.Substring($tmxRaiz.Length).TrimStart('\')
    [void]$sb.AppendLine("# --- $relativo " + ('-' * [Math]::Max(1, 60 - $relativo.Length)))
    [void]$sb.AppendLine((Get-TmxScriptChunk -Path $caminho))
}

# --- src/config/*.json ------------------------------------------------------
[void]$sb.AppendLine('# =========================================================================')
[void]$sb.AppendLine('# TMX-DADOS: catalogos (src/config/*.json), verbatim')
[void]$sb.AppendLine('# =========================================================================')

$dirConfig = Join-Path $tmxRaiz 'src\config'
$arquivosConfig = @(Get-ChildItem -LiteralPath $dirConfig -Filter '*.json' -File | Sort-Object Name)
if ($arquivosConfig.Count -eq 0) { throw "Nenhum .json em $dirConfig." }

foreach ($arquivo in $arquivosConfig) {
    $texto = Get-TmxAssetText -Path $arquivo.FullName
    Assert-TmxHereStringSafe -Text $texto -Origem "src\config\$($arquivo.Name)"
    # Conferencia de sanidade: um JSON quebrado tem que falhar AQUI, nao na
    # maquina de quem baixou o artefato.
    $null = $texto | ConvertFrom-Json
    [void]$sb.AppendLine("`$sync.configs['$($arquivo.BaseName)'] = " + (New-TmxHereString -Text $texto) + ' | ConvertFrom-Json')
    [void]$sb.AppendLine()
}

# --- src/web ----------------------------------------------------------------
[void]$sb.AppendLine('# =========================================================================')
[void]$sb.AppendLine('# TMX-DADOS: interface (src/web), extraida em <home>\ui\<versao>')
[void]$sb.AppendLine('# =========================================================================')
[void]$sb.AppendLine('$sync.embedded.web = @{}')

$dirWeb = Join-Path $tmxRaiz 'src\web'
$arquivosWeb = @(Get-ChildItem -LiteralPath $dirWeb -File -Recurse | Sort-Object FullName)
if ($arquivosWeb.Count -eq 0) { throw "Nenhum arquivo em $dirWeb." }

foreach ($arquivo in $arquivosWeb) {
    $nome  = $arquivo.FullName.Substring($dirWeb.Length).TrimStart('\')

    # Tudo em src/web e embutido como TEXTO. Um binario (icone, fonte) sairia
    # corrompido do outro lado, em silencio: melhor recusar a compilacao e
    # exigir uma decisao (base64, como as DLLs, ou data: URI no CSS).
    $bytesWeb = [System.IO.File]::ReadAllBytes($arquivo.FullName)
    if ($bytesWeb -contains 0) {
        throw "src\web\$nome parece binario (byte 0x00) e nao pode ser embutido como texto."
    }

    $texto = Get-TmxAssetText -Path $arquivo.FullName
    Assert-TmxHereStringSafe -Text $texto -Origem "src\web\$nome"
    [void]$sb.AppendLine("`$sync.embedded.web['$nome'] = " + (New-TmxHereString -Text $texto))
    [void]$sb.AppendLine()
}

# --- Modelo do MicroWin -----------------------------------------------------
$modelo = Join-Path $tmxRaiz 'tools\microwin\autounattend.template.xml'
if (Test-Path -LiteralPath $modelo) {
    $textoModelo = Get-TmxAssetText -Path $modelo
    Assert-TmxHereStringSafe -Text $textoModelo -Origem 'tools\microwin\autounattend.template.xml'
    [void]$sb.AppendLine('# TMX-DADOS: modelo do autounattend.xml (MicroWin)')
    [void]$sb.AppendLine('$sync.embedded.microwinTemplate = ' + (New-TmxHereString -Text $textoModelo))
    [void]$sb.AppendLine()
} else {
    Write-Warning 'tools\microwin\autounattend.template.xml ausente: o artefato nao vai gerar ISO do MicroWin.'
}

# --- DLLs do WebView2 -------------------------------------------------------
if ($sdkCompleto) {
    [void]$sb.AppendLine('# =========================================================================')
    [void]$sb.AppendLine("# TMX-DADOS: Microsoft.Web.WebView2 $versaoSdk (BSD-3), extraida em <home>\lib\<versao>")
    [void]$sb.AppendLine('# =========================================================================')
    [void]$sb.AppendLine('$sync.embedded.webview2 = @{}')
    foreach ($dll in $sdkDlls) {
        $bytes = [System.IO.File]::ReadAllBytes((Join-Path $sdkDir $dll))
        $b64   = [Convert]::ToBase64String($bytes)
        [void]$sb.AppendLine("`$sync.embedded.webview2['$dll'] = '$b64'")
    }
    [void]$sb.AppendLine()
}

# --- scripts/main.ps1 -------------------------------------------------------
[void]$sb.AppendLine('# =========================================================================')
[void]$sb.AppendLine('# TMX-MAIN')
[void]$sb.AppendLine('# =========================================================================')

$main = Get-TmxScriptChunk -Path (Join-Path $tmxRaiz 'scripts\main.ps1')
$main = Remove-TmxParamBlock -Text $main -Origem 'scripts\main.ps1'
[void]$sb.AppendLine($main)

# ---------------------------------------------------------------------------
# 4. Gravacao e conferencias
# ---------------------------------------------------------------------------

# UTF-8 COM BOM: o conteudo embutido tem acento e o PS 5.1 le arquivo sem BOM
# usando a codepage ANSI.
[System.IO.File]::WriteAllText($Out, $sb.ToString(), (New-Object System.Text.UTF8Encoding($true)))

$erros = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile($Out, [ref]$null, [ref]$erros)
if ($erros -and @($erros).Count -gt 0) {
    $primeiros = @($erros | Select-Object -First 3 | ForEach-Object { "linha $($_.Extent.StartLineNumber): $($_.Message)" })
    throw "O artefato gerado nao e um script valido:`n$($primeiros -join "`n")"
}

$item = Get-Item -LiteralPath $Out
$mb   = [Math]::Round($item.Length / 1MB, 2)
$hash = (Get-FileHash -LiteralPath $Out -Algorithm SHA256).Hash

Set-Content -LiteralPath (Join-Path (Split-Path -Parent $item.FullName) 'SHA256SUMS.txt') `
            -Value ("{0}  {1}" -f $hash, $item.Name) -Encoding ASCII

Write-Host ''
Write-Host ("Artefato : {0}" -f $item.FullName)
Write-Host ("Tamanho  : {0:N0} bytes ({1} MB)" -f $item.Length, $mb)
Write-Host ("SHA256   : {0}" -f $hash)
Write-Host ("Conteudo : {0} fontes .ps1, {1} catalogos, {2} arquivos de interface, {3} DLLs" -f `
            $fontes.Count, $arquivosConfig.Count, $arquivosWeb.Count, $(if ($sdkCompleto) { $sdkDlls.Count } else { 0 }))

if ($item.Length -ge 8MB) {
    throw ("O artefato passou de 8 MB ({0} MB). Algo grande entrou no arquivo unico." -f $mb)
}

if ($Run) {
    Write-Host ''
    Write-Host 'Executando o artefato...' -ForegroundColor Cyan
    & $item.FullName
}
