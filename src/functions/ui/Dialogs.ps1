# functions/ui/Dialogs.ps1
# Dialogos WPF nativos (sem WebView2): sao usados exatamente quando a janela
# principal ainda nao existe ou nao pode ser usada - runtime ausente, confirmacao
# de pulo do ponto de restauracao, erro fatal.
#
# Tudo aqui roda na thread da UI. De outra thread, chame por
# $sync.window.Dispatcher.Invoke({ ... }).

function Initialize-TmxWpf {
    <#
    .SYNOPSIS
        Garante os assemblies do WPF carregados (idempotente).
    #>
    [CmdletBinding()]
    param()
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml -ErrorAction Stop
}

function New-TmxDialogWindow {
    <#
    .SYNOPSIS
        Janela base dos dialogos: titulo, painel vertical e tema escuro.
    .OUTPUTS
        [pscustomobject] @{ janela; painel }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Titulo,
        [double] $Largura = 470
    )

    Initialize-TmxWpf

    $janela = New-Object System.Windows.Window
    $janela.Title                 = $Titulo
    $janela.Width                 = $Largura
    $janela.SizeToContent         = [System.Windows.SizeToContent]::Height
    $janela.ResizeMode            = [System.Windows.ResizeMode]::NoResize
    $janela.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterScreen
    $janela.ShowInTaskbar         = $false
    $janela.Background            = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(27, 29, 39))
    $janela.Foreground            = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(232, 232, 239))

    $painel = New-Object System.Windows.Controls.StackPanel
    $painel.Margin = New-Object System.Windows.Thickness 18
    $janela.Content = $painel

    [pscustomobject]@{ janela = $janela; painel = $painel }
}

function New-TmxDialogButton {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Rotulo,
        [switch] $Primario
    )
    $b = New-Object System.Windows.Controls.Button
    $b.Content   = $Rotulo
    $b.MinWidth  = 96
    $b.Padding   = New-Object System.Windows.Thickness 12, 6, 12, 6
    $b.Margin    = New-Object System.Windows.Thickness 8, 0, 0, 0
    $b.BorderThickness = New-Object System.Windows.Thickness 0
    if ($Primario) {
        $b.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(79, 140, 255))
        $b.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Colors]::White)
    } else {
        $b.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(45, 48, 62))
        $b.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(232, 232, 239))
    }
    $b
}

function Show-TmxDialog {
    <#
    .SYNOPSIS
        Dialogo modal de texto com botoes; devolve o rotulo escolhido.
    .OUTPUTS
        O rotulo do botao clicado, ou $null se a janela foi fechada no X.
    .EXAMPLE
        Show-TmxDialog -Titulo 'WebView2 ausente' -Texto '...' -Botoes 'Instalar','Fechar'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]   $Titulo,
        [Parameter(Mandatory)] [string]   $Texto,
        [string[]] $Botoes = @('OK'),
        $Owner
    )

    $ctx = New-TmxDialogWindow -Titulo $Titulo
    $janela = $ctx.janela
    if ($Owner) {
        $janela.Owner = $Owner
        $janela.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterOwner
    }

    $texto = New-Object System.Windows.Controls.TextBlock
    $texto.Text         = $Texto
    $texto.TextWrapping = [System.Windows.TextWrapping]::Wrap
    $texto.Margin       = New-Object System.Windows.Thickness 0, 0, 0, 18
    $texto.FontSize     = 13
    [void]$ctx.painel.Children.Add($texto)

    $linha = New-Object System.Windows.Controls.StackPanel
    $linha.Orientation         = [System.Windows.Controls.Orientation]::Horizontal
    $linha.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Right
    [void]$ctx.painel.Children.Add($linha)

    # Hashtable compartilhado: o handler roda em outro escopo e nao pode
    # atribuir direto numa variavel local desta funcao.
    $estado = @{ escolha = $null }
    $primeiro = $true
    foreach ($rotulo in $Botoes) {
        $botao = New-TmxDialogButton -Rotulo $rotulo -Primario:$primeiro
        $primeiro = $false
        $botao.Tag = $rotulo
        $botao.add_Click({
            param($remetente, $evento)
            $estado.escolha = "$($remetente.Tag)"
            $janela.DialogResult = $true
        }.GetNewClosure())
        [void]$linha.Children.Add($botao)
    }

    [void]$janela.ShowDialog()
    $estado.escolha
}

function Read-TmxDialogText {
    <#
    .SYNOPSIS
        Dialogo modal com uma caixa de texto; devolve o texto ou $null.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Titulo,
        [Parameter(Mandatory)] [string] $Texto,
        [string] $Rotulo = 'Confirmar',
        $Owner
    )

    $ctx = New-TmxDialogWindow -Titulo $Titulo
    $janela = $ctx.janela
    if ($Owner) {
        $janela.Owner = $Owner
        $janela.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterOwner
    }

    $texto = New-Object System.Windows.Controls.TextBlock
    $texto.Text         = $Texto
    $texto.TextWrapping = [System.Windows.TextWrapping]::Wrap
    $texto.Margin       = New-Object System.Windows.Thickness 0, 0, 0, 12
    $texto.FontSize     = 13
    [void]$ctx.painel.Children.Add($texto)

    $caixa = New-Object System.Windows.Controls.TextBox
    $caixa.FontSize   = 14
    $caixa.Padding    = New-Object System.Windows.Thickness 6
    $caixa.Margin     = New-Object System.Windows.Thickness 0, 0, 0, 18
    $caixa.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(18, 19, 26))
    $caixa.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(232, 232, 239))
    $caixa.BorderBrush = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(79, 140, 255))
    [void]$ctx.painel.Children.Add($caixa)

    $linha = New-Object System.Windows.Controls.StackPanel
    $linha.Orientation         = [System.Windows.Controls.Orientation]::Horizontal
    $linha.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Right
    [void]$ctx.painel.Children.Add($linha)

    $estado = @{ texto = $null }

    $cancelar = New-TmxDialogButton -Rotulo 'Cancelar'
    $cancelar.add_Click({ $janela.DialogResult = $false }.GetNewClosure())

    $confirmar = New-TmxDialogButton -Rotulo $Rotulo -Primario
    $confirmar.add_Click({
        $estado.texto = "$($caixa.Text)"
        $janela.DialogResult = $true
    }.GetNewClosure())

    [void]$linha.Children.Add($cancelar)
    [void]$linha.Children.Add($confirmar)

    $janela.add_Loaded({ $caixa.Focus() }.GetNewClosure())

    [void]$janela.ShowDialog()
    $estado.texto
}

function Confirm-TmxSkipRestorePointDialog {
    <#
    .SYNOPSIS
        Pede a frase exata que autoriza pular o ponto de restauracao.
    .DESCRIPTION
        Passada como -ConfirmSkip para Invoke-TmxRestorePointStage. A comparacao
        e sensivel a maiusculas (-ceq) de proposito: pular o ponto e a unica
        porta de saida do compromisso de reversibilidade.
    .OUTPUTS
        $true somente se o texto digitado for exatamente a frase.
    #>
    [CmdletBinding()]
    param($Owner)

    $frase = Get-TmxSkipPhrase
    $digitado = Read-TmxDialogText -Owner $Owner `
        -Titulo 'Pular o ponto de restauracao' `
        -Texto  ("Sem ponto de restauracao voce perde a rede de seguranca do proprio Windows. " +
                 "Os tweaks continuam reversiveis pelo Undo-TweakMaxing, mas nada mais protege " +
                 "o sistema se algo externo der errado.`n`nPara confirmar, digite exatamente:`n`n$frase") `
        -Rotulo 'Pular mesmo assim'

    ($digitado -ceq $frase)
}
