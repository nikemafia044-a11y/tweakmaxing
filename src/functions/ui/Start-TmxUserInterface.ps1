# functions/ui/Start-TmxUserInterface.ps1
# A janela: WPF hospedando um WebView2 que carrega src/web.
#
# Roda numa runspace STA propria (ver scripts/main.ps1). Tudo que demora sai
# daqui para o pool de jobs, senao a janela congela.
#
# Duas armadilhas ja pagas no spike e preservadas aqui:
#   - Task.ContinueWith com scriptblock do PowerShell derruba o processo; a
#     espera pelo ambiente acontece no evento Loaded, na thread da UI.
#   - WebView2Loader.dll e resolvida pelo PATH do processo, nao pelo Add-Type.

function New-TmxWindowIcon {
    <#
    .SYNOPSIS
        Icone 32x32 desenhado em runtime ("TM" sobre retangulo arredondado).
    .DESCRIPTION
        Evita carregar asset externo: o .ps1 compilado e um arquivo so.
        Puramente cosmetico - qualquer falha devolve $null.
    #>
    [CmdletBinding()]
    param()

    try {
        $lado   = 32
        $visual = New-Object System.Windows.Media.DrawingVisual
        $ctx    = $visual.RenderOpen()

        $fundo  = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(79, 140, 255))
        $rect   = New-Object System.Windows.Rect 0, 0, $lado, $lado
        $ctx.DrawRoundedRectangle($fundo, $null, $rect, 7, 7)

        $tipo = New-Object System.Windows.Media.Typeface(
            (New-Object System.Windows.Media.FontFamily 'Segoe UI'),
            [System.Windows.FontStyles]::Normal,
            [System.Windows.FontWeights]::Bold,
            [System.Windows.FontStretches]::Normal)

        $texto = New-Object System.Windows.Media.FormattedText(
            'TM',
            [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Windows.FlowDirection]::LeftToRight,
            $tipo,
            14.0,
            (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Colors]::White)),
            1.0)

        $ponto = New-Object System.Windows.Point (($lado - $texto.Width) / 2), (($lado - $texto.Height) / 2)
        $ctx.DrawText($texto, $ponto)
        $ctx.Close()

        $bmp = New-Object System.Windows.Media.Imaging.RenderTargetBitmap(
            $lado, $lado, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
        $bmp.Render($visual)
        $bmp.Freeze()
        $bmp
    } catch {
        Write-Verbose "Icone nao pode ser desenhado: $($_.Exception.Message)"
        $null
    }
}

function Install-TmxWebView2Runtime {
    <#
    .SYNOPSIS
        Instala o runtime do WebView2 via winget e devolve a versao resultante.
    #>
    [CmdletBinding()]
    param()
    try {
        Start-Process -FilePath 'winget' -Wait -ArgumentList @(
            'install', 'Microsoft.EdgeWebView2Runtime',
            '--accept-package-agreements', '--accept-source-agreements'
        )
    } catch {
        Write-TmxLog -Level WARN -Message "winget nao pode instalar o runtime do WebView2: $($_.Exception.Message)"
    }
    Test-TmxWebView2Runtime
}

function Test-TmxUiNavegacaoPermitida {
    <#
    .SYNOPSIS
        $true so para o host virtual da propria interface
        (https://app.tweakmaxing/...). Qualquer outra coisa e recusada.
    .DESCRIPTION
        Comparacao pelo objeto [uri], nao por -like em texto: 'https://
        app.tweakmaxing.exemplo.com/x' e 'https://app.tweakmaxing@mau.com/x'
        passariam num prefixo textual ingenuo e nao sao o nosso host.
        about:blank entra na lista porque o WebView2 o usa como pagina
        inicial antes do primeiro Navigate.
    .OUTPUTS
        [bool]
    #>
    [CmdletBinding()]
    param([string] $Uri)

    if (-not $Uri) { return $false }
    if ($Uri -ieq 'about:blank') { return $true }
    try {
        $u = [uri]$Uri
    } catch {
        return $false
    }
    # IsAbsoluteUri explicito: '/index.html' converte SEM lancar (vira uma Uri
    # relativa) e, numa Uri relativa, .Scheme/.Host lancam no getter. O
    # PowerShell engole essa excecao e devolve $null, o que daria o resultado
    # certo por acidente; aqui a recusa e deliberada.
    if (-not $u.IsAbsoluteUri) { return $false }
    ($u.Scheme -ieq 'https' -and $u.Host -ieq 'app.tweakmaxing')
}

function Start-TmxUserInterface {
    <#
    .SYNOPSIS
        Abre a janela principal e bloqueia ate ela fechar.
    .OUTPUTS
        0 quando a janela abriu e fechou normalmente; 1 quando nao foi possivel abrir.
    #>
    [CmdletBinding()]
    param()

    $lib = Get-TmxWebView2Sdk

    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml
    Get-ChildItem -LiteralPath $lib -Filter '*.dll' -File | Unblock-File -ErrorAction SilentlyContinue
    Add-Type -Path (Join-Path $lib 'Microsoft.Web.WebView2.Core.dll')
    Add-Type -Path (Join-Path $lib 'Microsoft.Web.WebView2.Wpf.dll')
    # Core.dll carrega WebView2Loader.dll por nome: sem o PATH ela nao e achada.
    if ($env:PATH -notlike "$lib;*") { $env:PATH = "$lib;" + $env:PATH }

    $runtime = Test-TmxWebView2Runtime
    if (-not $runtime) {
        $escolha = Show-TmxDialog -Titulo 'WebView2 ausente' -Botoes 'Instalar', 'Fechar' -Texto (
            'O TweakMaxing precisa do runtime do WebView2 (vem com o Microsoft Edge). Instalar agora via winget?')
        if ($escolha -ne 'Instalar') {
            Write-TmxLog -Level WARN -Message 'Runtime do WebView2 ausente e instalacao recusada'
            return 1
        }
        $runtime = Install-TmxWebView2Runtime
        if (-not $runtime) {
            Show-TmxDialog -Titulo 'WebView2 ausente' -Botoes 'Fechar' -Texto (
                'A instalacao do runtime do WebView2 nao pode ser concluida. Instale o Microsoft Edge WebView2 Runtime e abra o TweakMaxing de novo.') | Out-Null
            return 1
        }
    }

    $webRoot = Get-TmxWebRoot
    $versao  = Get-TmxUiVersion

    # So quando pedido: com a porta aberta, qualquer processo local fala CDP
    # com a janela. E o que os testes de GUI usam.
    if ($sync.debugPort) {
        $env:WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS = "--remote-debugging-port=$($sync.debugPort)"
    }

    Register-TmxShellActions
    Register-TmxSessionActions
    Register-TmxInstallActions
    Register-TmxTweakActions
    Register-TmxFeatureActions
    Register-TmxUpdateActions
    Register-TmxMicroWinActions
    Register-TmxSystemActions

    $titulo = "TweakMaxing $versao"
    if ($sync.testMode) { $titulo = "$titulo [modo de teste]" }

    # WindowStyle=None: a barra de titulo do Windows some, e quem desenha
    # minimizar/maximizar/fechar e o HTML (#titlebar, ver app.css/app.js e as
    # acoes window.* de Actions.Shell.ps1). WindowChrome com CaptionHeight=0
    # devolve so a borda redimensionavel (ResizeBorderThickness) - sem ele,
    # WindowStyle=None tambem tira o redimensionar pelas bordas.
    [xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        xmlns:shell="clr-namespace:System.Windows.Shell;assembly=PresentationFramework"
        Title="$([System.Security.SecurityElement]::Escape($titulo))"
        Width="1200" Height="760"
        MinWidth="900" MinHeight="600"
        Background="#0C0D0F"
        WindowStyle="None"
        ResizeMode="CanResize"
        WindowStartupLocation="CenterScreen">
    <shell:WindowChrome.WindowChrome>
        <shell:WindowChrome CaptionHeight="0" ResizeBorderThickness="6" GlassFrameThickness="0" CornerRadius="0" />
    </shell:WindowChrome.WindowChrome>
    <Grid x:Name="Root" />
</Window>
"@

    $janela = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
    $grade  = $janela.FindName('Root')

    $icone = New-TmxWindowIcon
    if ($icone) { $janela.Icon = $icone }

    $wv = New-Object Microsoft.Web.WebView2.Wpf.WebView2
    [void]$grade.Children.Add($wv)

    $sync.window  = $janela
    $sync.webview = $wv

    $pastaDados = Join-Path (Get-TmxUiHomePath) 'webview2-data'
    New-Item -ItemType Directory -Path $pastaDados -Force | Out-Null
    $tarefaAmbiente = [Microsoft.Web.WebView2.Core.CoreWebView2Environment]::CreateAsync($null, $pastaDados, $null)

    $janela.add_Loaded({
        # Esperar aqui (thread da UI) em vez de ContinuarWith: um ContinueWith
        # com scriptblock do PowerShell mata o processo sem rastro.
        $tarefaAmbiente.Wait()
        $null = $wv.EnsureCoreWebView2Async($tarefaAmbiente.Result)
    }.GetNewClosure())

    $wv.add_CoreWebView2InitializationCompleted({
        param($remetente, $evento)

        if (-not $evento.IsSuccess) {
            Write-TmxLog -Level ERROR -Message 'WebView2 nao inicializou' -Data @{ erro = "$($evento.InitializationException)" }
            return
        }

        $core = $wv.CoreWebView2
        $core.Settings.AreDefaultContextMenusEnabled = [bool]$sync.debugPort
        $core.Settings.AreDevToolsEnabled            = [bool]$sync.debugPort
        $core.Settings.IsStatusBarEnabled            = $false
        $core.Settings.IsZoomControlEnabled          = $false

        # Deixa o CSS 'app-region: drag' de #titlebar arrastar a janela sem
        # passar pela ponte. Propriedade nova (pode faltar no SDK 1.0.3240.44
        # dependendo do runtime do Edge instalado na maquina) - quando falha,
        # window.drag (mousedown -> DragMove na thread da UI) cobre o arrasto.
        try {
            $core.Settings.IsNonClientRegionSupportEnabled = $true
        } catch {
            Write-TmxLog -Level WARN -Message 'IsNonClientRegionSupportEnabled indisponivel: usando so o fallback window.drag' -Data @{ erro = $_.Exception.Message }
        }

        # Host virtual em vez de file://: o file:// fica com origem opaca e
        # quebra fetch/modulos; e o mapeamento e somente-leitura da pasta.
        $core.SetVirtualHostNameToFolderMapping(
            'app.tweakmaxing', $webRoot,
            [Microsoft.Web.WebView2.Core.CoreWebView2HostResourceAccessKind]::Allow)

        # A janela so navega para o host virtual. Um link externo que escape
        # da UI (ou um <a href> injetado por conteudo de catalogo) levaria a
        # pagina inteira para fora de app.tweakmaxing - e com ela a ponte
        # window.chrome.webview, que passaria a existir para uma origem
        # remota. Aqui a navegacao e simplesmente cancelada.
        $core.add_NavigationStarting({
            param($remetenteNav, $eventoNav)
            $destino = "$($eventoNav.Uri)"
            if (-not (Test-TmxUiNavegacaoPermitida -Uri $destino)) {
                $eventoNav.Cancel = $true
                Write-TmxLog -Level WARN -Message 'Navegacao bloqueada na janela' -Data @{ uri = $destino }
            }
        }.GetNewClosure())

        # window.open / target=_blank: o WebView2 abriria uma segunda janela
        # SEM nenhuma das restricoes acima. Handled = $true mata essa janela -
        # e nada e aberto no lugar.
        #
        # Decisao de produto: abrir o destino no navegador padrao daqui seria
        # transformar qualquer window.open da pagina (inclusive um vindo de
        # texto de catalogo) em Start-Process sem passar por nenhuma revisao.
        # Link externo da interface tem UM caminho, explicito e auditavel: a
        # acao shell.openUrl da ponte, que so aceita https. Aqui fica so o
        # registro de que alguem tentou.
        $core.add_NewWindowRequested({
            param($remetenteNw, $eventoNw)
            $eventoNw.Handled = $true
            Write-TmxLog -Level WARN -Message 'Nova janela recusada (use shell.openUrl)' -Data @{ uri = "$($eventoNw.Uri)" }
        }.GetNewClosure())

        $core.add_WebMessageReceived({
            param($remetente2, $evento2)
            # $sync.webview e nao a variavel $wv: GetNewClosure() copia apenas o
            # escopo LOCAL, e neste handler aninhado $wv ja mora no escopo do
            # closure de fora - chega aqui como $null.
            try {
                $resposta = Invoke-TmxBridgeRequest -Json $evento2.WebMessageAsJson
                if ($resposta -and $sync.webview) { $sync.webview.CoreWebView2.PostWebMessageAsJson($resposta) }
            } catch {
                Write-TmxLog -Level ERROR -Message "Falha ao tratar mensagem da UI: $($_.Exception.Message)"
            }
        }.GetNewClosure())

        $core.Navigate('https://app.tweakmaxing/index.html')
    }.GetNewClosure())

    Write-TmxLog -Level INFO -Message 'UI iniciada' -Data @{ versao = $versao; runtime = $runtime; testMode = [bool]$sync.testMode; debugPort = $sync.debugPort }

    [void]$janela.ShowDialog()

    $sync.webview = $null
    $sync.window  = $null
    Write-TmxLog -Level INFO -Message 'UI encerrada'
    0
}
