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

function Test-TmxIconUrlPrivateHost {
    <#
    .SYNOPSIS
        Guarda leve contra SSRF: recusa quando o host da URL e um IP LITERAL
        (nao um dominio) dentro de faixa privada/loopback/link-local/reservada
        (0.0.0.0/8, 10/8, 172.16/12, 192.168/16, 127/8, 169.254/16; em IPv6:
        ::1, fe80::/10, fc00::/7 - e o mapeamento IPv4 dentro de IPv6,
        ::ffff:a.b.c.d, reaplicando as mesmas faixas de IPv4).
    .DESCRIPTION
        So olha o literal escrito na URL - nao resolve DNS. Protege contra o
        caso obvio (icon do catalogo ou favicon.ico apontando direto pra um IP
        interno), nao contra DNS rebinding (um dominio que resolve pra IP
        privado so na hora do download real).
    #>
    [CmdletBinding()]
    param([string] $Url)
    try {
        $uri = New-Object System.Uri($Url)
        $ip = $null
        if (-not [System.Net.IPAddress]::TryParse($uri.Host, [ref]$ip)) { return $false }

        # ::ffff:a.b.c.d e o mesmo IPv4 disfarcado dentro de um literal IPv6 -
        # sem isso, ::ffff:127.0.0.1 passaria batido pelas checagens de IPv4
        # abaixo (AddressFamily seria InterNetworkV6, nao InterNetwork).
        if ($ip.IsIPv4MappedToIPv6) { $ip = $ip.MapToIPv4() }

        if ([System.Net.IPAddress]::IsLoopback($ip)) { return $true }

        if ($ip.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork) {
            $b = $ip.GetAddressBytes()
            if ($b[0] -eq 0) { return $true }   # 0.0.0.0/8 ("esta rede", usado como curinga por alguns servicos)
            if ($b[0] -eq 10) { return $true }
            if ($b[0] -eq 172 -and $b[1] -ge 16 -and $b[1] -le 31) { return $true }
            if ($b[0] -eq 192 -and $b[1] -eq 168) { return $true }
            if ($b[0] -eq 169 -and $b[1] -eq 254) { return $true }
            return $false
        }
        if ($ip.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetworkV6) {
            if ($ip.Equals([System.Net.IPAddress]::IPv6Loopback)) { return $true }
            $b6 = $ip.GetAddressBytes()
            # fe80::/10 (link-local): primeiro byte 0xFE, dois bits mais altos do segundo byte = '10'.
            if ($b6[0] -eq 0xFE -and ($b6[1] -band 0xC0) -eq 0x80) { return $true }
            # fc00::/7 (unique local, o "10/8" do IPv6): primeiro byte 0xFC ou 0xFD.
            if (($b6[0] -band 0xFE) -eq 0xFC) { return $true }
            return $false
        }
        $false
    } catch {
        $false
    }
}

function Test-TmxIconUrlAllowed {
    <#
    .SYNOPSIS
        https + nao aponta pra um IP privado/loopback literal. Usado antes de
        QUALQUER requisicao de verdade, inclusive a cada salto de redirect.
    #>
    [CmdletBinding()]
    param([string] $Url)
    (Test-TmxIconUrlHttps -Url $Url) -and -not (Test-TmxIconUrlPrivateHost -Url $Url)
}

function Test-TmxAppIconIdSafe {
    <#
    .SYNOPSIS
        Id de app seguro para virar nome de arquivo de cache: so
        [A-Za-z0-9_.-], sem '..' (nada de atravessar pasta).
    #>
    [CmdletBinding()]
    param([string] $Id)
    if ([string]::IsNullOrWhiteSpace($Id)) { return $false }
    if ($Id.Contains('..')) { return $false }
    [bool]($Id -cmatch '^[A-Za-z0-9_.-]+$')
}

function Read-TmxLimitedStream {
    <#
    .SYNOPSIS
        Le um stream ate o fim, ou devolve $null assim que passa de MaxBytes
        (pelo Content-Length declarado, ou - quando ele nao veio/mentiu -
        pela contagem de bytes lidos de verdade) OU do tempo limite total.
    .DESCRIPTION
        Isolado do resto de Invoke-TmxHttpRequestOnce de proposito: e so
        leitura de stream, sem HttpWebRequest nenhum, entao os testes
        exercitam o corte de tamanho (e de tempo) com um MemoryStream comum,
        sem precisar de rede nem de servidor local.
    .PARAMETER ContentLength
        -1 quando desconhecido (nenhum corte antecipado; so a contagem real
        durante a leitura decide).
    .PARAMETER Stopwatch
        Cronometro ja iniciado por quem chama. Junto com TimeoutMs, corta a
        leitura se o tempo TOTAL passar do limite mesmo que cada Read()
        individual volte rapido (defesa contra um servidor que manda poucos
        bytes de vez em quando pra segurar a conexao aberta -
        ReadWriteTimeout do HttpWebRequest sozinho nao pega esse caso).
    .OUTPUTS
        [byte[]] ou $null. Nunca lanca (um Stream que lanca no Read()
        tambem vira $null).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Stream,
        [int]  $MaxBytes      = 524288,
        [long] $ContentLength = -1,
        [System.Diagnostics.Stopwatch] $Stopwatch,
        [int]  $TimeoutMs     = 0
    )

    if ($ContentLength -ge 0 -and $ContentLength -gt $MaxBytes) { return $null }

    $buffer  = New-Object byte[] 8192
    $destino = New-Object System.IO.MemoryStream
    try {
        $total = 0
        while ($true) {
            if ($null -ne $Stopwatch -and $TimeoutMs -gt 0 -and $Stopwatch.ElapsedMilliseconds -gt $TimeoutMs) {
                return $null
            }
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

function Invoke-TmxHttpRequestOnce {
    <#
    .SYNOPSIS
        Wrapper de baixo nivel: UMA requisicao GET, SEM seguir redirect
        automatico. Existe separado de Invoke-TmxIconDownload para os testes
        poderem mockar um 3xx com Location e exercitar a logica de redirect
        manual sem precisar de servidor de verdade.
    .OUTPUTS
        [pscustomobject] @{ statusCode; location; bytes } ou $null (falha de
        rede/tempo esgotado antes de qualquer resposta chegar). 'bytes' e
        $null quando statusCode nao e 2xx, ou quando Read-TmxLimitedStream
        recusou o corpo (tamanho/tempo). Nunca lanca.
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
        $pedido.Timeout           = $TimeoutMs
        $pedido.ReadWriteTimeout  = $TimeoutMs
        $pedido.Method            = 'GET'
        $pedido.UserAgent         = 'TweakMaxing'
        # Redirect e tratado NA MAO por Invoke-TmxIconDownload: cada salto
        # precisa ser revalidado (https + nao aponta pra IP privado) antes de
        # seguir, o que o AllowAutoRedirect nativo nao permite inspecionar.
        $pedido.AllowAutoRedirect = $false

        try {
            $resposta = $pedido.GetResponse()
        } catch [System.Net.WebException] {
            # 4xx/5xx chegam aqui como excecao (com Response preenchido);
            # 3xx NAO lanca com AllowAutoRedirect=false - volta normal do
            # GetResponse() acima, com StatusCode/Headers do redirect.
            if ($_.Exception.Response) { $resposta = $_.Exception.Response } else { return $null }
        }

        $statusCode = [int]$resposta.StatusCode
        $location   = "$($resposta.Headers['Location'])"
        $bytes      = $null

        if ($statusCode -ge 200 -and $statusCode -lt 300) {
            $cronometro = [System.Diagnostics.Stopwatch]::StartNew()
            $bytes = Read-TmxLimitedStream -Stream $resposta.GetResponseStream() -MaxBytes $MaxBytes `
                -ContentLength $resposta.ContentLength -Stopwatch $cronometro -TimeoutMs $TimeoutMs
        }

        [pscustomobject]@{ statusCode = $statusCode; location = $location; bytes = $bytes }
    } catch {
        Write-Verbose "Falha na requisicao '$Url': $($_.Exception.Message)"
        $null
    } finally {
        if ($null -ne $resposta) { try { $resposta.Close() } catch { } }
    }
}

function Invoke-TmxIconDownload {
    <#
    .SYNOPSIS
        Wrapper de download de icone/pagina: so https, sem apontar pra IP
        privado/loopback, TLS 1.2, 5s de tempo limite por padrao, no maximo
        512 KB. $null em qualquer falha ou recusa; nunca lanca.
    .DESCRIPTION
        Redirect (3xx) e seguido NA MAO, no maximo 3 saltos: cada Location e
        resolvido contra a URL atual (pode vir relativo) e revalidado (https
        + nao IP privado) antes de seguir - um redirect https->http, ou pra
        um IP interno, para a cadeia na hora.
    .PARAMETER PrazoMs
        Orcamento TOTAL desta chamada (todos os saltos de redirect somados),
        vindo de quem chama (Get-TmxAppIconFromSite, que por sua vez recebeu
        de Invoke-TmxAppIconBatch). 0 = sem orcamento externo, usa TimeoutMs
        cheio em cada salto (uso direto/testes). Com orcamento: aborta a
        cadeia (sem tentar mais nada) assim que o restante chega a zero, e
        cada salto usa o MENOR entre TimeoutMs e o restante - sem isso, 3
        saltos de 5s cada podiam gastar 15s+ mesmo com um orcamento de lote
        de so 8s.
    .PARAMETER ErroRede
        [ref] opcional: setado como $true quando a causa de nao ter bytes foi
        uma falha de rede/tempo esgotado (DNS, timeout, recusa de conexao) -
        NUNCA quando o servidor respondeu (mesmo com 404) ou quando a
        recusa foi por regra nossa (https/IP privado/redirect demais). Quem
        chama usa isso pra NAO gravar cache negativo numa falha transitoria.
    .PARAMETER OrcamentoEsgotado
        [ref] opcional: setado como $true quando a cadeia foi abortada por
        falta de tempo (PrazoMs), nao por uma resposta de verdade. Mesma
        ideia do ErroRede: orcamento estourado nao e "sem icone", e "nao deu
        tempo de saber".
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Url,
        [int] $TimeoutMs = 5000,
        [int] $MaxBytes = 524288,
        [int] $MaxRedirects = 3,
        [int] $PrazoMs = 0,
        [ref] $ErroRede,
        [ref] $OrcamentoEsgotado
    )

    if (-not (Test-TmxIconUrlAllowed -Url $Url)) { return $null }

    try {
        [System.Net.ServicePointManager]::SecurityProtocol = `
            [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
    } catch {
        Write-Verbose "Nao foi possivel forcar TLS 1.2: $($_.Exception.Message)"
    }

    $cronometro = [System.Diagnostics.Stopwatch]::StartNew()
    $urlAtual = $Url
    $saltos   = 0
    while ($true) {
        $tempoSalto = $TimeoutMs
        if ($PrazoMs -gt 0) {
            $restante = $PrazoMs - $cronometro.ElapsedMilliseconds
            if ($restante -le 0) {
                if ($OrcamentoEsgotado) { $OrcamentoEsgotado.Value = $true }
                return $null
            }
            $tempoSalto = [Math]::Min($TimeoutMs, [int]$restante)
        }

        $r = Invoke-TmxHttpRequestOnce -Url $urlAtual -TimeoutMs $tempoSalto -MaxBytes $MaxBytes
        if ($null -eq $r) {
            # Invoke-TmxHttpRequestOnce so devolve $null quando nenhuma
            # resposta chegou (DNS, timeout, conexao recusada, TLS) - e
            # exatamente a definicao de falha de rede/transitoria aqui.
            if ($ErroRede) { $ErroRede.Value = $true }
            return $null
        }

        if ($r.statusCode -ge 200 -and $r.statusCode -lt 300) { return $r.bytes }

        if ($r.statusCode -ge 300 -and $r.statusCode -lt 400 -and $r.location) {
            $saltos++
            if ($saltos -gt $MaxRedirects) { return $null }
            $proxima = ConvertTo-TmxIconAbsoluteUrl -Base $urlAtual -Href $r.location
            if (-not (Test-TmxIconUrlAllowed -Url $proxima)) { return $null }
            $urlAtual = $proxima
            continue
        }

        return $null
    }
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

function Test-TmxIconImageDimensionsSafe {
    <#
    .SYNOPSIS
        Guarda contra "decompression bomb": recusa imagem com lado maior que
        1024px ou mais de 1.048.576 pixels (1024x1024) - um arquivo pequeno
        (dentro do limite de 512 KB) pode ainda assim descomprimir pra um
        bitmap gigantesco em memoria (ex.: PNG bem comprimido).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Imagem)
    if ($Imagem.Width -gt 1024 -or $Imagem.Height -gt 1024) { return $false }
    ([int64]$Imagem.Width * [int64]$Imagem.Height) -le 1048576
}

function ConvertFrom-TmxIconImageBytes {
    <#
    .SYNOPSIS
        Decodifica bytes de imagem (ico/png/jpg/gif/bmp) para
        @{ Imagem; Fluxo }. $null para svg/formato desconhecido/invalido/
        dimensao grande demais (Test-TmxIconImageDimensionsSafe).
    .DESCRIPTION
        Devolve a Image carregada por Image.FromStream DIRETO (sem copiar
        pra um Bitmap novo) e o MemoryStream que a mantem viva - quem chama
        (ConvertTo-TmxIconPngBytes) desenha direto a partir dela e descarta
        os dois no fim. Nao existe copia intermediaria em tamanho cheio.
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

    $fluxo  = New-Object System.IO.MemoryStream(, $Bytes)
    $imagem = $null
    try {
        $imagem = [System.Drawing.Image]::FromStream($fluxo)

        if (-not (Test-TmxIconImageDimensionsSafe -Imagem $imagem)) {
            if (Get-Command -Name Write-TmxLog -ErrorAction SilentlyContinue) {
                Write-TmxLog -Level WARN -Message "Imagem grande demais para virar icone ($($imagem.Width)x$($imagem.Height))"
            }
            $imagem.Dispose()
            $fluxo.Dispose()
            return $null
        }

        [pscustomobject]@{ Imagem = $imagem; Fluxo = $fluxo }
    } catch {
        Write-Verbose "Falha ao decodificar imagem: $($_.Exception.Message)"
        if ($null -ne $imagem) { try { $imagem.Dispose() } catch { } }
        $fluxo.Dispose()
        $null
    }
}

function ConvertTo-TmxIconPngBytes {
    <#
    .SYNOPSIS
        Redimensiona uma Image para 64x64 (alta qualidade) e devolve os bytes
        PNG. Sempre descarta a Image de entrada (e o FluxoParaDescartar, se
        veio um). $null em qualquer falha.
    .PARAMETER Imagem
        Bitmap (do icone do exe) ou Image (do site, via
        ConvertFrom-TmxIconImageBytes) - desenhada DIRETO no destino 64x64,
        sem copia intermediaria em tamanho cheio. Tambem revalidada aqui por
        Test-TmxIconImageDimensionsSafe (defesa em profundidade: o icone do
        exe nao passa por ConvertFrom-TmxIconImageBytes, entao essa e a
        UNICA guarda de tamanho no caminho do exe).
    .PARAMETER FluxoParaDescartar
        MemoryStream que mantem 'Imagem' viva (quando ela veio de
        ConvertFrom-TmxIconImageBytes). Opcional - o icone do exe e
        autocontido, sem stream pra descartar.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Imagem,
        $FluxoParaDescartar
    )

    try {
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop

        if (-not (Test-TmxIconImageDimensionsSafe -Imagem $Imagem)) {
            if (Get-Command -Name Write-TmxLog -ErrorAction SilentlyContinue) {
                Write-TmxLog -Level WARN -Message "Imagem grande demais para virar icone ($($Imagem.Width)x$($Imagem.Height))"
            }
            return $null
        }

        $destino = New-Object System.Drawing.Bitmap(64, 64)
        try {
            $graficos = [System.Drawing.Graphics]::FromImage($destino)
            try {
                $graficos.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $graficos.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
                $graficos.PixelOffsetMode   = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                # Desenha DIRETO da imagem de origem (Icon.ToBitmap() ou
                # Image.FromStream) pro destino 64x64 - nunca existe um
                # Bitmap intermediario em tamanho cheio.
                $graficos.DrawImage($Imagem, 0, 0, 64, 64)
            } finally {
                $graficos.Dispose()
            }

            $fluxo = New-Object System.IO.MemoryStream
            try {
                $destino.Save($fluxo, [System.Drawing.Imaging.ImageFormat]::Png)
                $fluxo.ToArray()
            } finally {
                $fluxo.Dispose()
            }
        } finally {
            $destino.Dispose()
        }
    } catch {
        Write-Verbose "Falha ao converter icone para PNG 64x64: $($_.Exception.Message)"
        $null
    } finally {
        try { $Imagem.Dispose() } catch { }
        if ($null -ne $FluxoParaDescartar) { try { $FluxoParaDescartar.Dispose() } catch { } }
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
    .PARAMETER PrazoMs
        Orcamento TOTAL desta etapa inteira (todas as tentativas: catalogo,
        favicon, pagina HTML, icone resolvido do HTML - cada uma pode
        envolver ate 3 saltos de redirect). Repassado pra cada
        Invoke-TmxIconDownload como o RESTANTE na hora daquela tentativa
        especifica, nao o valor cheio de novo.
    .PARAMETER ErroRede
        [ref] opcional: $true se QUALQUER tentativa bateu em falha de
        rede/tempo esgotado (nao serve pra decidir "sem icone" - so pra quem
        chama saber que nao foi uma resposta de verdade).
    .PARAMETER OrcamentoEsgotado
        [ref] opcional: $true se o orcamento acabou antes de esgotar todas
        as tentativas possiveis (idem: nao e "sem icone", e "nao deu tempo").
    #>
    [CmdletBinding()]
    param(
        [string] $IconCatalogo,
        [string] $Link,
        [int] $PrazoMs = 20000,
        [ref] $ErroRede,
        [ref] $OrcamentoEsgotado
    )

    $cronometro   = [System.Diagnostics.Stopwatch]::StartNew()
    $teveErroRede = $false
    $teveEsgotado = $false

    # Sem funcao aninhada de proposito (evita depender de escopo dinamico pra
    # enxergar $cronometro/$PrazoMs de dentro dela): cada tentativa repete o
    # mesmo trio "calcula restante -> chama com refs -> acumula sinalizadores"
    # na mao. Mais linhas, zero ambiguidade de escopo.

    $resultado = $null
    $candidatas = New-Object 'System.Collections.Generic.List[string]'
    if (Test-TmxIconUrlHttps -Url $IconCatalogo) { $candidatas.Add($IconCatalogo) }

    $hostLink = $null
    if ("$Link" -match '^https?://([^/]+)') { $hostLink = $Matches[1] }
    if ($hostLink) { $candidatas.Add("https://$hostLink/favicon.ico") }

    foreach ($url in $candidatas) {
        $restante = $PrazoMs - $cronometro.ElapsedMilliseconds
        if ($restante -le 0) { $teveEsgotado = $true; break }
        $erroLocal = $false
        $esgotadoLocal = $false
        $bytes = Invoke-TmxIconDownload -Url $url -PrazoMs ([int]$restante) -ErroRede ([ref]$erroLocal) -OrcamentoEsgotado ([ref]$esgotadoLocal)
        if ($erroLocal) { $teveErroRede = $true }
        if ($esgotadoLocal) { $teveEsgotado = $true }
        if ($bytes -and $bytes.Length -gt 0) { $resultado = $bytes; break }
    }

    if (-not $resultado -and (Test-TmxIconUrlHttps -Url $Link)) {
        $restante = $PrazoMs - $cronometro.ElapsedMilliseconds
        if ($restante -gt 0) {
            $erroLocal = $false
            $esgotadoLocal = $false
            $htmlBytes = Invoke-TmxIconDownload -Url $Link -PrazoMs ([int]$restante) -ErroRede ([ref]$erroLocal) -OrcamentoEsgotado ([ref]$esgotadoLocal)
            if ($erroLocal) { $teveErroRede = $true }
            if ($esgotadoLocal) { $teveEsgotado = $true }

            if ($htmlBytes -and $htmlBytes.Length -gt 0) {
                $html = [System.Text.Encoding]::UTF8.GetString($htmlBytes)
                $href = Find-TmxHtmlIconHref -Html $html
                if ($href) {
                    $resolvida = ConvertTo-TmxIconAbsoluteUrl -Base $Link -Href $href
                    if (Test-TmxIconUrlHttps -Url $resolvida) {
                        $restante = $PrazoMs - $cronometro.ElapsedMilliseconds
                        if ($restante -gt 0) {
                            $erroLocal = $false
                            $esgotadoLocal = $false
                            $bytes = Invoke-TmxIconDownload -Url $resolvida -PrazoMs ([int]$restante) -ErroRede ([ref]$erroLocal) -OrcamentoEsgotado ([ref]$esgotadoLocal)
                            if ($erroLocal) { $teveErroRede = $true }
                            if ($esgotadoLocal) { $teveEsgotado = $true }
                            if ($bytes -and $bytes.Length -gt 0) { $resultado = $bytes }
                        } else {
                            $teveEsgotado = $true
                        }
                    }
                }
            }
        } else {
            $teveEsgotado = $true
        }
    }

    if ($ErroRede) { $ErroRede.Value = $teveErroRede }
    if ($OrcamentoEsgotado) { $OrcamentoEsgotado.Value = $teveEsgotado }
    $resultado
}

function Get-TmxAppIconNegativeCachePath {
    <#
    .SYNOPSIS
        Caminho do marcador "sem icone" de um id: <home>\icons\<id>.none.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Id)
    Join-Path (Get-TmxAppIconCacheDir) "$Id.none"
}

function Test-TmxAppIconNegativeCacheFresh {
    <#
    .SYNOPSIS
        $true quando existe um marcador <id>.none com menos de MaxAgeDays
        (padrao 7) - nesse caso Get-TmxAppIcon pula a busca no site sem
        gastar rede de novo num app que ja se provou sem icone.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Id,
        [int] $MaxAgeDays = 7
    )
    $caminho = Get-TmxAppIconNegativeCachePath -Id $Id
    if (-not (Test-Path -LiteralPath $caminho)) { return $false }
    try {
        $idade = (Get-Date).ToUniversalTime() - (Get-Item -LiteralPath $caminho).LastWriteTimeUtc
        $idade.TotalDays -lt $MaxAgeDays
    } catch {
        $false
    }
}

function Set-TmxAppIconNegativeCache {
    <#
    .SYNOPSIS
        Grava (ou atualiza a data de) o marcador "sem icone" de um id. So
        deve ser chamado depois de uma tentativa DE VERDADE (exe + site, sem
        pular por offline/testMode/orcamento) que nao achou nada - nunca
        quando a busca so nao teve tempo de rodar. Nunca lanca.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Id)
    try {
        [System.IO.File]::WriteAllBytes((Get-TmxAppIconNegativeCachePath -Id $Id), [byte[]]@())
    } catch {
        Write-Verbose "Falha ao gravar cache negativo para '$Id': $($_.Exception.Message)"
    }
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
    .PARAMETER PrazoRestanteMs
        Orcamento (em ms) que a etapa de SITE desta chamada pode gastar -
        repassado direto pra Get-TmxAppIconFromSite. Vem de
        Invoke-TmxAppIconBatch (orcamento do LOTE menos o que ja foi gasto
        nos apps anteriores). Padrao generoso (20s) pra uso direto/testes,
        onde nao ha um orcamento de lote a respeitar.
    .DESCRIPTION
        Nunca lanca: qualquer falha vira $null + Write-TmxLog WARN. Uma
        chamada com icone achado grava/atualiza o cache em disco. Quando o
        id e seguro (Test-TmxAppIconIdSafe) e a etapa de site rodou ATE O FIM
        (sem falha de rede, sem estourar PrazoRestanteMs) sem achar nada,
        grava o cache negativo (Set-TmxAppIconNegativeCache) para nao repetir
        a busca de rede por 7 dias - uma falha de rede transitoria ou um
        orcamento curto demais NUNCA gravam o marcador (senao um problema de
        conexao de 1 minuto bania o icone por 7 dias).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $App,
        [switch] $Offline,
        $UninstallEntries,
        [int] $PrazoRestanteMs = 20000
    )

    $id = "$($App.id)"
    if (-not (Test-TmxAppIconIdSafe -Id $id)) {
        if ($id -and (Get-Command -Name Write-TmxLog -ErrorAction SilentlyContinue)) {
            Write-TmxLog -Level WARN -Message "id de app invalido para icone: '$id'"
        }
        return $null
    }

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
            $pngExe = ConvertTo-TmxIconPngBytes -Imagem $bitmapExe
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

        # Cache negativo fresco: ja sabemos (de uma tentativa recente de
        # verdade) que este app nao tem icone de site - nao gasta rede de
        # novo. So conta como "tentou o site" quando ISSO nao for o motivo
        # de pular (senao regravaria o marcador so por causa dele mesmo).
        $puloPorCacheNegativo = (-not $semRede) -and (Test-TmxAppIconNegativeCacheFresh -Id $id)
        $tentouSite = (-not $semRede) -and (-not $puloPorCacheNegativo)

        if ($tentouSite) {
            $bytesSite = $null
            $erroRedeSite = $false
            $orcamentoEsgotadoSite = $false
            try {
                $bytesSite = Get-TmxAppIconFromSite -IconCatalogo "$($App.icon)" -Link "$($App.link)" `
                    -PrazoMs $PrazoRestanteMs -ErroRede ([ref]$erroRedeSite) -OrcamentoEsgotado ([ref]$orcamentoEsgotadoSite)
            } catch {
                Write-TmxLog -Level WARN -Message "Falha ao buscar icone do site para '$id'" -Data @{ erro = $_.Exception.Message }
                $erroRedeSite = $true
            }
            if ($bytesSite) {
                $decodificado = ConvertFrom-TmxIconImageBytes -Bytes $bytesSite
                if ($decodificado) {
                    $pngSite = ConvertTo-TmxIconPngBytes -Imagem $decodificado.Imagem -FluxoParaDescartar $decodificado.Fluxo
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

            # So marca "sem icone de verdade" quando a etapa de site correu
            # ATE O FIM sem contratempo - uma falha de rede ou um orcamento
            # curto demais nao provam nada sobre o app, so sobre o momento.
            if (-not $erroRedeSite -and -not $orcamentoEsgotadoSite) {
                Set-TmxAppIconNegativeCache -Id $id
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

function Invoke-TmxAppIconBatch {
    <#
    .SYNOPSIS
        Resolve o icone de uma lista de apps respeitando um ORCAMENTO DE
        TEMPO TOTAL (nao por app): usada pela acao de ponte apps.icons.
    .DESCRIPTION
        Um lote pode ter ate 40 apps, e um so pode envolver download de
        site; sem limite, um lote cheio de apps lentos poderia demorar
        minutos e travar o slot de job unico do app inteiro (nenhuma outra
        acao assincrona - instalar, listar instalados, etc. - consegue
        rodar enquanto o lote nao termina).

        O orcamento RESTANTE (nao o total) e repassado pra cada
        Get-TmxAppIcon como -PrazoRestanteMs, que por sua vez capa cada
        download individual (Invoke-TmxIconDownload/Invoke-TmxHttpRequestOnce)
        a esse mesmo restante - sem isso, um unico app lento (ate 3 URLs de
        candidato, cada uma com ate 3 saltos de redirect de 5s) podia gastar
        15s+ sozinho mesmo com um orcamento de lote de so 8s (a checagem
        antiga so olhava o relogio ENTRE apps, nunca durante um app so).

        Ids que nao COUBEREM no orcamento (o relogio ja zerou antes de
        comecar) saem sem icone e SEM cache negativo, e voltam em
        'Pendentes' pra quem chamou tentar de novo depois (Get-TmxAppIcon
        simplesmente nao chega a rodar pra eles, entao nao ha "tentativa de
        verdade" nenhuma a registrar).
    .PARAMETER Apps
        Objetos de app (do catalogo) ja resolvidos - nao ids crus.
    .PARAMETER BudgetMs
        Orcamento total do lote inteiro, nao por app (padrao 8000).
    .OUTPUTS
        [pscustomobject] @{ Icones = [ordered]@{ id -> @{ src; origem } };
        Pendentes = string[] com os ids que nao couberam no orcamento }.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Apps,
        $UninstallEntries,
        [int] $BudgetMs = 8000
    )

    $icones     = [ordered]@{}
    $pendentes  = New-Object 'System.Collections.Generic.List[string]'
    $cronometro = [System.Diagnostics.Stopwatch]::StartNew()

    for ($i = 0; $i -lt $Apps.Count; $i++) {
        $restante = $BudgetMs - $cronometro.ElapsedMilliseconds
        if ($restante -le 0) {
            for ($j = $i; $j -lt $Apps.Count; $j++) { $pendentes.Add("$($Apps[$j].id)") }
            break
        }
        $achado = Get-TmxAppIcon -App $Apps[$i] -UninstallEntries $UninstallEntries -PrazoRestanteMs ([int]$restante)
        if ($achado) { $icones["$($achado.id)"] = @{ src = $achado.src; origem = $achado.origem } }
    }

    [pscustomobject]@{ Icones = $icones; Pendentes = $pendentes.ToArray() }
}
