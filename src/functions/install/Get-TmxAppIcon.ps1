# functions/install/Get-TmxAppIcon.ps1
# Logo de um aplicativo do catalogo para a aba Instalar.
#
# Ordem: cache em disco -> icone do .exe ja instalado (registro de
# desinstalacao) -> icone do site oficial (so quando ha rede permitida).
# Qualquer falha num app so devolve $null (fica com as iniciais no front-end);
# nada aqui derruba o lote inteiro.
#
# Todo acesso externo (registro de desinstalacao, ExtractAssociatedIcon,
# download HTTP) passa por um wrapper fino e mockavel, no mesmo espirito de
# functions/install/_Wrappers.ps1.

function Get-TmxAppIconCacheDir {
    <#
    .SYNOPSIS
        Pasta onde os icones baixados/gerados ficam em cache: <home>\icons.
    .DESCRIPTION
        Mesma raiz que Get-TmxRunsRoot usa para as execucoes
        (Get-TmxHomePath, Core/Backup.ps1): respeita $env:TWEAKMAXING_HOME
        quando definido (e o que os testes usam), senao
        %LOCALAPPDATA%\TweakMaxing. Cria a pasta se nao existir.
    #>
    [CmdletBinding()]
    param()
    $dir = Join-Path (Get-TmxHomePath) 'icons'
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $dir
}

function Get-TmxUninstallEntries {
    <#
    .SYNOPSIS
        Wrapper: le as entradas de Desinstalar de HKLM, HKLM WOW6432Node e
        HKCU. Devolve { DisplayName; DisplayIcon } para cada uma. Nunca lanca.
    #>
    [CmdletBinding()]
    param()

    $caminhos = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    $itens = New-Object 'System.Collections.Generic.List[object]'
    foreach ($caminho in $caminhos) {
        try {
            foreach ($chave in @(Get-ItemProperty -Path $caminho -ErrorAction SilentlyContinue)) {
                $nome = "$($chave.DisplayName)"
                if ([string]::IsNullOrWhiteSpace($nome)) { continue }
                $itens.Add([pscustomobject]@{
                    DisplayName = $nome
                    DisplayIcon = "$($chave.DisplayIcon)"
                })
            }
        } catch {
            Write-Verbose "Falha ao ler '$caminho': $($_.Exception.Message)"
        }
    }
    # A virgula evita que uma lista de 1 item so seja desenrolada no pipeline.
    , ($itens.ToArray())
}

function Get-TmxExeIconBitmap {
    <#
    .SYNOPSIS
        Wrapper: extrai o icone associado a um .exe (ou carrega um .ico) como
        System.Drawing.Bitmap. $null em qualquer falha; nunca lanca.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)

    if (-not (Test-Path -LiteralPath $Path)) { return $null }

    try {
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
        $extensao = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
        $icone = $null
        if ($extensao -eq '.ico') {
            $icone = New-Object System.Drawing.Icon($Path)
        } else {
            $icone = [System.Drawing.Icon]::ExtractAssociatedIcon($Path)
        }
        if ($null -eq $icone) { return $null }
        try {
            $icone.ToBitmap()
        } finally {
            $icone.Dispose()
        }
    } catch {
        Write-Verbose "Falha ao extrair icone de '$Path': $($_.Exception.Message)"
        $null
    }
}

function Test-TmxIconUrlHttps {
    <#
    .SYNOPSIS
        $true so quando a URL comeca com https:// (case-insensitive).
    #>
    [CmdletBinding()]
    param([string] $Url)
    # -match (sem 'c'): os operadores de comparacao do PowerShell ja ignoram
    # maiusculas/minusculas por padrao.
    [bool]("$Url" -match '^https://')
}

function Read-TmxLimitedStream {
    <#
    .SYNOPSIS
        Le um stream ate o fim, ou devolve $null assim que passa de MaxBytes
        (pelo Content-Length declarado, ou - quando ele nao veio/mentiu -
        pela contagem de bytes lidos de verdade).
    .DESCRIPTION
        Isolado do resto de Get-TmxHttpDownloadBytes de proposito: e so
        leitura de stream, sem HttpWebRequest nenhum, entao os testes
        exercitam o corte de tamanho com um MemoryStream comum, sem precisar
        de rede nem de servidor local.
    .PARAMETER ContentLength
        -1 quando desconhecido (nenhum corte antecipado; so a contagem real
        durante a leitura decide).
    .OUTPUTS
        [byte[]] ou $null. Nunca lanca (um Stream que lanca no Read()
        tambem vira $null).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Stream,
        [int]  $MaxBytes      = 524288,
        [long] $ContentLength = -1
    )

    if ($ContentLength -ge 0 -and $ContentLength -gt $MaxBytes) { return $null }

    $buffer  = New-Object byte[] 8192
    $destino = New-Object System.IO.MemoryStream
    try {
        $total = 0
        while ($true) {
            $lidos = $Stream.Read($buffer, 0, $buffer.Length)
            if ($lidos -le 0) { break }
            $total += $lidos
            if ($total -gt $MaxBytes) { return $null }
            $destino.Write($buffer, 0, $lidos)
        }
        $destino.ToArray()
    } catch {
        Write-Verbose "Falha ao ler stream: $($_.Exception.Message)"
        $null
    } finally {
        $destino.Dispose()
    }
}

function Get-TmxHttpDownloadBytes {
    <#
    .SYNOPSIS
        Baixa bytes de uma URL com tempo limite e limite de tamanho. Sem
        checagem de esquema (isso e Test-TmxIconUrlHttps, chamado por quem
        usa este helper).
    .OUTPUTS
        [byte[]] ou $null (falha de rede, tempo esgotado, ou corpo maior que
        MaxBytes). Nunca lanca.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Url,
        [int] $TimeoutMs = 5000,
        [int] $MaxBytes = 524288
    )

    $resposta = $null
    try {
        $pedido = [System.Net.HttpWebRequest]::Create($Url)
        $pedido.Timeout    = $TimeoutMs
        $pedido.Method     = 'GET'
        $pedido.UserAgent  = 'TweakMaxing'
        $resposta = $pedido.GetResponse()

        Read-TmxLimitedStream -Stream $resposta.GetResponseStream() -MaxBytes $MaxBytes -ContentLength $resposta.ContentLength
    } catch {
        Write-Verbose "Falha ao baixar '$Url': $($_.Exception.Message)"
        $null
    } finally {
        if ($null -ne $resposta) { try { $resposta.Close() } catch { } }
    }
}

function Invoke-TmxIconDownload {
    <#
    .SYNOPSIS
        Wrapper de download de icone/pagina: so https, TLS 1.2, 5s de tempo
        limite por padrao, no maximo 512 KB. $null em qualquer falha ou
        recusa; nunca lanca.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Url,
        [int] $TimeoutMs = 5000,
        [int] $MaxBytes = 524288
    )

    if (-not (Test-TmxIconUrlHttps -Url $Url)) { return $null }

    try {
        [System.Net.ServicePointManager]::SecurityProtocol = `
            [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
    } catch {
        Write-Verbose "Nao foi possivel forcar TLS 1.2: $($_.Exception.Message)"
    }

    Get-TmxHttpDownloadBytes -Url $Url -TimeoutMs $TimeoutMs -MaxBytes $MaxBytes
}

function ConvertTo-TmxIconAbsoluteUrl {
    <#
    .SYNOPSIS
        Resolve um href relativo (de <link href=...>) contra a URL da pagina.
        $null se nao der para montar uma URI valida.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Base,
        [Parameter(Mandatory)] [string] $Href
    )
    try {
        $baseUri = New-Object System.Uri($Base)
        (New-Object System.Uri($baseUri, $Href)).AbsoluteUri
    } catch {
        $null
    }
}

function Find-TmxHtmlIconHref {
    <#
    .SYNOPSIS
        Primeiro href de <link rel="icon"|"shortcut icon"|"apple-touch-icon">
        no HTML dado (rel e href podem vir em qualquer ordem no atributo).
        $null se nao achar nenhum.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Html)

    $padraoRelPrimeiro = '<link[^>]*\srel\s*=\s*["'']?(?:shortcut icon|icon|apple-touch-icon)["'']?[^>]*\shref\s*=\s*["'']([^"''>]+)["'']'
    $m = [regex]::Match($Html, $padraoRelPrimeiro, 'IgnoreCase')
    if ($m.Success) { return $m.Groups[1].Value }

    $padraoHrefPrimeiro = '<link[^>]*\shref\s*=\s*["'']([^"''>]+)["''][^>]*\srel\s*=\s*["'']?(?:shortcut icon|icon|apple-touch-icon)["'']?'
    $m = [regex]::Match($Html, $padraoHrefPrimeiro, 'IgnoreCase')
    if ($m.Success) { return $m.Groups[1].Value }

    $null
}

function ConvertFrom-TmxIconImageBytes {
    <#
    .SYNOPSIS
        Decodifica bytes de imagem (ico/png/jpg/gif/bmp) para um
        System.Drawing.Bitmap. $null para svg/formato desconhecido/invalido.
    #>
    [CmdletBinding()]
    param([byte[]] $Bytes)

    if ($null -eq $Bytes -or $Bytes.Length -lt 8) { return $null }

    # svg e texto (xml), nao um formato que System.Drawing decodifica: sniff
    # rapido no inicio dos bytes antes de tentar Image.FromStream.
    $tamanhoAmostra = [Math]::Min(200, $Bytes.Length)
    $amostra = [System.Text.Encoding]::ASCII.GetString($Bytes, 0, $tamanhoAmostra)
    if ($amostra -match '<\?xml|<svg') { return $null }

    try {
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    } catch {
        return $null
    }

    $fluxo = New-Object System.IO.MemoryStream(, $Bytes)
    try {
        $imagem = [System.Drawing.Image]::FromStream($fluxo)
        try {
            New-Object System.Drawing.Bitmap($imagem)
        } finally {
            $imagem.Dispose()
        }
    } catch {
        Write-Verbose "Falha ao decodificar imagem: $($_.Exception.Message)"
        $null
    } finally {
        $fluxo.Dispose()
    }
}

function ConvertTo-TmxIconPngBytes {
    <#
    .SYNOPSIS
        Redimensiona um Bitmap para 64x64 (alta qualidade) e devolve os bytes
        PNG. Sempre descarta o Bitmap de entrada. $null em qualquer falha.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Bitmap)

    try {
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop

        $destino  = New-Object System.Drawing.Bitmap(64, 64)
        $graficos = [System.Drawing.Graphics]::FromImage($destino)
        try {
            $graficos.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graficos.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
            $graficos.PixelOffsetMode   = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $graficos.DrawImage($Bitmap, 0, 0, 64, 64)
        } finally {
            $graficos.Dispose()
        }

        $fluxo = New-Object System.IO.MemoryStream
        try {
            $destino.Save($fluxo, [System.Drawing.Imaging.ImageFormat]::Png)
            $fluxo.ToArray()
        } finally {
            $fluxo.Dispose()
            $destino.Dispose()
        }
    } catch {
        Write-Verbose "Falha ao converter icone para PNG 64x64: $($_.Exception.Message)"
        $null
    } finally {
        try { $Bitmap.Dispose() } catch { }
    }
}

function Test-TmxAppNameMatchesDisplayName {
    <#
    .SYNOPSIS
        $true quando DisplayName e igual (sem diferenciar maiusculas) ao nome
        do app, ou comeca com "<nome> " (ex.: 'Git' casa 'Git', nao casa
        'GitHub Desktop').
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Nome,
        [Parameter(Mandatory)] [string] $DisplayName
    )
    if ([string]::IsNullOrWhiteSpace($Nome) -or [string]::IsNullOrWhiteSpace($DisplayName)) { return $false }
    if ($DisplayName -ieq $Nome) { return $true }
    $DisplayName.StartsWith("$Nome ", [System.StringComparison]::OrdinalIgnoreCase)
}

function ConvertTo-TmxIconExecutablePath {
    <#
    .SYNOPSIS
        DisplayIcon do registro (pode vir com aspas e/ou sufixo ',N' de
        indice de recurso) -> caminho de arquivo limpo.
    #>
    [CmdletBinding()]
    param([string] $DisplayIcon)

    $caminho = "$DisplayIcon".Trim()
    if (-not $caminho) { return $null }
    $caminho = $caminho.Trim('"')
    $caminho = $caminho -replace ',-?\d+\s*$', ''
    $caminho = $caminho.Trim().Trim('"')
    if (-not $caminho) { return $null }
    $caminho
}

function Get-TmxAppIconFromExe {
    <#
    .SYNOPSIS
        Tenta casar o app com uma entrada de Desinstalar e extrair o icone do
        executavel instalado. $null se nao achar nada usavel.
    .PARAMETER Entradas
        Lista ja lida de Get-TmxUninstallEntries, para quem processa varios
        apps de uma vez (a ponte apps.icons le UMA vez por lote em vez de
        varrer o registro inteiro de novo para cada id - Get-TmxUninstallEntries
        sozinho ja leva ~200ms nesta maquina, e um lote pode ter ate 40 ids).
        Quando omitido, le na hora (uso direto/testes).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Nome,
        $Entradas
    )

    if ([string]::IsNullOrWhiteSpace($Nome)) { return $null }

    # SEM @() aqui: Get-TmxUninstallEntries ja devolve um array protegido
    # (virgula na frente, ver o proprio arquivo) - envolver com @() de novo
    # quebra o caso de ZERO entradas (vira um array de 1 item cujo unico
    # elemento e um array vazio, em vez de um array vazio de verdade).
    $entradas = $Entradas
    if ($null -eq $entradas) { $entradas = Get-TmxUninstallEntries }
    $casada = $null
    foreach ($entrada in $entradas) {
        if (Test-TmxAppNameMatchesDisplayName -Nome $Nome -DisplayName "$($entrada.DisplayName)") {
            $casada = $entrada
            break
        }
    }
    if ($null -eq $casada) { return $null }

    $caminhoExe = ConvertTo-TmxIconExecutablePath -DisplayIcon "$($casada.DisplayIcon)"
    if (-not $caminhoExe) { return $null }

    $extensao = [System.IO.Path]::GetExtension($caminhoExe).ToLowerInvariant()
    if ($extensao -ne '.exe' -and $extensao -ne '.ico') { return $null }
    if (-not (Test-Path -LiteralPath $caminhoExe)) { return $null }

    Get-TmxExeIconBitmap -Path $caminhoExe
}

function Get-TmxAppIconFromSite {
    <#
    .SYNOPSIS
        Tenta baixar o icone do site oficial: icon do catalogo (se https) ->
        favicon.ico do host de link -> <link rel=icon> da propria pagina.
        $null se nada funcionar.
    #>
    [CmdletBinding()]
    param(
        [string] $IconCatalogo,
        [string] $Link
    )

    $candidatas = New-Object 'System.Collections.Generic.List[string]'
    if (Test-TmxIconUrlHttps -Url $IconCatalogo) { $candidatas.Add($IconCatalogo) }

    $hostLink = $null
    if ("$Link" -match '^https?://([^/]+)') { $hostLink = $Matches[1] }
    if ($hostLink) { $candidatas.Add("https://$hostLink/favicon.ico") }

    foreach ($url in $candidatas) {
        $bytes = Invoke-TmxIconDownload -Url $url
        if ($bytes -and $bytes.Length -gt 0) { return $bytes }
    }

    if (Test-TmxIconUrlHttps -Url $Link) {
        $htmlBytes = Invoke-TmxIconDownload -Url $Link
        if ($htmlBytes -and $htmlBytes.Length -gt 0) {
            $html = [System.Text.Encoding]::UTF8.GetString($htmlBytes)
            $href = Find-TmxHtmlIconHref -Html $html
            if ($href) {
                $resolvida = ConvertTo-TmxIconAbsoluteUrl -Base $Link -Href $href
                if (Test-TmxIconUrlHttps -Url $resolvida) {
                    $bytes = Invoke-TmxIconDownload -Url $resolvida
                    if ($bytes -and $bytes.Length -gt 0) { return $bytes }
                }
            }
        }
    }

    $null
}

function Get-TmxAppIcon {
    <#
    .SYNOPSIS
        Logo de um app do catalogo: { id; src='data:image/png;base64,...';
        origem='cache'|'exe'|'site' }, ou $null quando nao ha icone.
    .PARAMETER App
        Objeto com pelo menos id/nome; idealmente tambem link e icon (como
        vem do catalogo/apps.catalog).
    .PARAMETER Offline
        Pula a busca no site (so cache + exe). $sync.testMode tambem
        desliga a busca no site, mesmo sem -Offline.
    .PARAMETER UninstallEntries
        Lista ja lida de Get-TmxUninstallEntries, repassada para
        Get-TmxAppIconFromExe. Quem resolve varios apps de uma vez (a ponte
        apps.icons) le o registro de desinstalar UMA vez e passa aqui, em vez
        de deixar cada chamada varrer tudo de novo.
    .DESCRIPTION
        Nunca lanca: qualquer falha vira $null + Write-TmxLog WARN. Uma
        chamada com icone achado grava/atualiza o cache em disco.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $App,
        [switch] $Offline,
        $UninstallEntries
    )

    $id = "$($App.id)"
    if ([string]::IsNullOrWhiteSpace($id)) { return $null }

    try {
        $arquivoCache = Join-Path (Get-TmxAppIconCacheDir) "$id.png"

        if (Test-Path -LiteralPath $arquivoCache) {
            try {
                $bytesCache = [System.IO.File]::ReadAllBytes($arquivoCache)
                if ($bytesCache.Length -gt 0) {
                    return [pscustomobject]@{
                        id     = $id
                        src    = ('data:image/png;base64,' + [Convert]::ToBase64String($bytesCache))
                        origem = 'cache'
                    }
                }
            } catch {
                Write-TmxLog -Level WARN -Message "Icone em cache ilegivel para '$id'" -Data @{ erro = $_.Exception.Message }
            }
        }

        $nome = "$($App.nome)"

        $bitmapExe = $null
        try {
            $bitmapExe = Get-TmxAppIconFromExe -Nome $nome -Entradas $UninstallEntries
        } catch {
            Write-TmxLog -Level WARN -Message "Falha ao buscar icone do executavel para '$id'" -Data @{ erro = $_.Exception.Message }
        }
        if ($bitmapExe) {
            $pngExe = ConvertTo-TmxIconPngBytes -Bitmap $bitmapExe
            if ($pngExe) {
                [System.IO.File]::WriteAllBytes($arquivoCache, $pngExe)
                return [pscustomobject]@{
                    id     = $id
                    src    = ('data:image/png;base64,' + [Convert]::ToBase64String($pngExe))
                    origem = 'exe'
                }
            }
        }

        $semRede = [bool]$Offline
        if (-not $semRede -and $null -ne $sync -and $sync.testMode) { $semRede = $true }

        if (-not $semRede) {
            $bytesSite = $null
            try {
                $bytesSite = Get-TmxAppIconFromSite -IconCatalogo "$($App.icon)" -Link "$($App.link)"
            } catch {
                Write-TmxLog -Level WARN -Message "Falha ao buscar icone do site para '$id'" -Data @{ erro = $_.Exception.Message }
            }
            if ($bytesSite) {
                $bitmapSite = ConvertFrom-TmxIconImageBytes -Bytes $bytesSite
                if ($bitmapSite) {
                    $pngSite = ConvertTo-TmxIconPngBytes -Bitmap $bitmapSite
                    if ($pngSite) {
                        [System.IO.File]::WriteAllBytes($arquivoCache, $pngSite)
                        return [pscustomobject]@{
                            id     = $id
                            src    = ('data:image/png;base64,' + [Convert]::ToBase64String($pngSite))
                            origem = 'site'
                        }
                    }
                }
            }
        }

        $null
    } catch {
        if (Get-Command -Name Write-TmxLog -ErrorAction SilentlyContinue) {
            Write-TmxLog -Level WARN -Message "Falha ao obter icone para '$id'" -Data @{ erro = $_.Exception.Message }
        }
        $null
    }
}
