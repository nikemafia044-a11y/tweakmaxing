# functions/bridge/Actions.Shell.ps1
# Acoes da casca: o minimo que a janela precisa para existir e se descrever.
# As abas registram as suas nas tasks seguintes.

function Register-TmxShellActions {
    <#
    .SYNOPSIS
        Registra shell.ping, shell.version, shell.openUrl, log.tail e
        shell.async.echo. As acoes session.* moram em Actions.Session.ps1.
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
}
