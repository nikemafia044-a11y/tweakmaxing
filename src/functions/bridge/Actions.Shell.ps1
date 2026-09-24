# functions/bridge/Actions.Shell.ps1
# Acoes da casca: o minimo que a janela precisa para existir e se descrever,
# mais os comandos da barra de titulo propria (WindowStyle=None: nao ha mais
# minimizar/maximizar/fechar do Windows, quem desenha isso e o HTML).
# As abas registram as suas nas tasks seguintes.

function Register-TmxShellActions {
    <#
    .SYNOPSIS
        Registra shell.ping, shell.version, shell.openUrl, log.tail,
        shell.async.echo e window.minimize/maximizeToggle/close/drag/state.
        As acoes session.* moram em Actions.Session.ps1.
    .DESCRIPTION
        As acoes window.* mexem direto no objeto WPF ($sync.window) e por
        isso sao SINCRONAS (sem -Async): o WebMessageReceived do WebView2 ja
        roda na thread da UI, e uma acao -Async rodaria no pool de
        runspaces - de outra thread, tocar em WindowState/DragMove()/Close()
        e invalido. Quando $sync.window nao existe (testes de unidade, sem
        janela real) elas nao tocam em nada e devolvem um estado inofensivo -
        e assim que continuam seguras de rodar em Bridge.Tests.ps1.
    #>
    [CmdletBinding()]
    param()

    Register-TmxBridgeAction -Name 'shell.ping' -Handler {
        param($payload)
        @{ pong = $true; ts = (Get-Date).ToString('o') }
    }

    Register-TmxBridgeAction -Name 'shell.version' -Handler {
        param($payload)
        @{
            version  = "$($sync.version)"
            testMode = [bool]$sync.testMode
            elevado  = [bool](Test-TmxElevation)
            # 'usuario/repositorio': mesma fonte que scripts/start.ps1 grava em
            # $sync.repo (REPO/Compile.ps1) - o link "Novidades" da barra
            # lateral monta https://github.com/<repo>/releases com isto, sem
            # precisar de Actions.System.ps1 (Get-TmxRepoSlug).
            repo     = "$($sync.repo)"
        }
    }

    Register-TmxBridgeAction -Name 'shell.openUrl' -Handler {
        param($payload)
        $url = "$($payload.url)"
        # Lista de permissao, nao de bloqueio: file:, http:, javascript: e
        # qualquer esquema novo caem aqui sem precisar ser previstos.
        if ($url -notmatch '^https://') { throw 'apenas URLs https' }
        Start-Process $url
        @{ aberto = $true; url = $url }
    }

    Register-TmxBridgeAction -Name 'log.tail' -Handler {
        param($payload)
        $n = 100
        if ($payload -and $payload.n) { $n = [int]$payload.n }
        if ($n -lt 1)    { $n = 1 }
        if ($n -gt 2000) { $n = 2000 }

        $caminho = $sync.logPath
        if (-not $caminho -or -not (Test-Path -LiteralPath $caminho)) {
            return @{ caminho = $caminho; linhas = @() }
        }
        # [string]$_: as linhas do Get-Content carregam PSPath/PSDrive/PSProvider
        # como NoteProperty, e ConvertTo-Json -Depth 12 desce por esse grafo
        # (provider -> drive -> provider...) ate travar o processo.
        $linhas = @(@(Get-Content -LiteralPath $caminho -Tail $n -ErrorAction SilentlyContinue) | ForEach-Object { [string]$_ })
        @{ caminho = $caminho; linhas = $linhas }
    }

    # So para exercitar o caminho assincrono (ponte + pool + eventos) nos testes.
    Register-TmxBridgeAction -Name 'shell.async.echo' -Async -Handler {
        param($payload)
        $ms = 200
        if ($payload -and $payload.ms) { $ms = [int]$payload.ms }
        if ($ms -lt 0)     { $ms = 0 }
        if ($ms -gt 60000) { $ms = 60000 }
        Send-TmxJobProgress -Pct 50 -Status 'ecoando'
        Start-Sleep -Milliseconds $ms
        @{ echo = $payload; ms = $ms }
    }

    Register-TmxBridgeAction -Name 'window.minimize' -Handler {
        param($payload)
        if ($null -ne $sync -and $sync.window) {
            $sync.window.WindowState = [System.Windows.WindowState]::Minimized
        }
        @{ ok = $true }
    }

    Register-TmxBridgeAction -Name 'window.maximizeToggle' -Handler {
        param($payload)
        $maximizado = $false
        if ($null -ne $sync -and $sync.window) {
            $janela = $sync.window
            if ($janela.WindowState -eq [System.Windows.WindowState]::Maximized) {
                $janela.WindowState = [System.Windows.WindowState]::Normal
                $maximizado = $false
            } else {
                $janela.WindowState = [System.Windows.WindowState]::Maximized
                $maximizado = $true
            }
        }
        @{ maximized = [bool]$maximizado }
    }

    Register-TmxBridgeAction -Name 'window.close' -Handler {
        param($payload)
        if ($null -ne $sync -and $sync.window) { $sync.window.Close() }
        @{ ok = $true }
    }

    Register-TmxBridgeAction -Name 'window.drag' -Handler {
        param($payload)
        # Fallback do arrasto quando CSS app-region/IsNonClientRegionSupportEnabled
        # nao pegam neste SDK: DragMove() so e valido com o botao esquerdo
        # do mouse ainda pressionado - a viagem JS->ponte->PS as vezes chega
        # tarde demais e ele lanca InvalidOperationException. Falha ali e
        # silenciosa: o usuario so nao arrasta por essa tentativa.
        if ($null -ne $sync -and $sync.window) {
            try { $sync.window.DragMove() } catch { Write-Verbose "DragMove: $($_.Exception.Message)" }
        }
        @{ ok = $true }
    }

    Register-TmxBridgeAction -Name 'window.state' -Handler {
        param($payload)
        $maximizado = $false
        if ($null -ne $sync -and $sync.window) {
            $maximizado = ($sync.window.WindowState -eq [System.Windows.WindowState]::Maximized)
        }
        @{ maximized = [bool]$maximizado }
    }
}
