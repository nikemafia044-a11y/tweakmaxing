# tests/gui/_GuiHelpers.ps1
# Sobe a janela real com a porta CDP aberta e conversa com ela pelo agent-browser.
#
# Nao e Pester: o teste de GUI abre um processo, espera uma porta e tira print.
# Falhar aqui tem que deixar a maquina limpa, entao todo Start tem um Stop no
# finally e o PID vai para tests/gui/out/gui.pid (tests/gui/out/ e gitignorado).

$script:TmxGuiOutDir  = Join-Path $PSScriptRoot 'out'
$script:TmxRepoRoot   = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$script:TmxAbTimeoutSeconds = 30

function Get-TmxGuiPidFile {
    <#
    .SYNOPSIS
        Arquivo de PID DESTA porta (out\gui-<porta>.pid).
    .DESCRIPTION
        Um unico gui.pid era global: dois testes de GUI em portas diferentes
        rodando junto se matavam. Tudo aqui e por porta - arquivo de PID,
        varredura de processo e checagem de socket.
    #>
    param([Parameter(Mandatory)] [int] $Port)
    Join-Path $script:TmxGuiOutDir ("gui-{0}.pid" -f $Port)
}

function Initialize-TmxGuiOut {
    if (-not (Test-Path -LiteralPath $script:TmxGuiOutDir)) {
        New-Item -ItemType Directory -Path $script:TmxGuiOutDir -Force | Out-Null
    }
    $script:TmxGuiOutDir
}

function Stop-TmxProcessTree {
    <#
    .SYNOPSIS
        Mata um processo e todos os filhos dele (taskkill /T).
    #>
    param([Parameter(Mandatory)] [int] $ProcessId)
    if ($ProcessId -le 0) { return }
    & taskkill.exe /PID $ProcessId /T /F 2>&1 | Out-Null
}

function Test-TmxPortOpen {
    param([Parameter(Mandatory)] [int] $Port)
    # So LISTENING: um socket em TIME_WAIT ainda aparece no netstat e faria o
    # teardown parecer sujo por varios minutos.
    $linhas = @(& netstat.exe -ano | Select-String -Pattern ":$Port\s" | Select-String -SimpleMatch 'LISTENING')
    $linhas.Count -gt 0
}

function Clear-TmxGuiLeftovers {
    <#
    .SYNOPSIS
        Derruba a GUI de teste DESTA porta e o WebView2 orfao dela.
    .DESCRIPTION
        Nada e morto por nome: so o PID registrado para esta porta e os
        processos cuja linha de comando cita exatamente esta porta
        (-DebugPort <porta> no runner, --remote-debugging-port=<porta> no
        WebView2). Um teste de GUI em outra porta continua de pe.
    #>
    param([Parameter(Mandatory)] [int] $Port)

    Initialize-TmxGuiOut | Out-Null

    $arquivoPid = Get-TmxGuiPidFile -Port $Port
    if (Test-Path -LiteralPath $arquivoPid) {
        $anterior = 0
        [int]::TryParse((Get-Content -LiteralPath $arquivoPid -Raw).Trim(), [ref]$anterior) | Out-Null
        if ($anterior -gt 0) { Stop-TmxProcessTree -ProcessId $anterior }
        Remove-Item -LiteralPath $arquivoPid -Force -ErrorAction SilentlyContinue
    }

    # Sobrevivente sem arquivo de PID (a rodada anterior morreu no meio): um
    # msedgewebview2 vivo segura a porta CDP e o proximo Start falha sem
    # explicacao. As duas marcas abaixo carregam a porta, entao nunca acertam
    # outra instancia.
    $marcas = @("-DebugPort $Port", "--remote-debugging-port=$Port")
    foreach ($nome in @('msedgewebview2.exe', 'powershell.exe')) {
        foreach ($p in @(Get-CimInstance Win32_Process -Filter "Name='$nome'" -ErrorAction SilentlyContinue)) {
            $linha = "$($p.CommandLine)"
            if (-not $linha) { continue }
            if ([int]$p.ProcessId -eq $PID) { continue }
            foreach ($marca in $marcas) {
                if ($linha -like "*$marca*") { Stop-TmxProcessTree -ProcessId ([int]$p.ProcessId); break }
            }
        }
    }

    $fim = (Get-Date).AddSeconds(10)
    while ((Test-TmxPortOpen -Port $Port) -and (Get-Date) -lt $fim) { Start-Sleep -Milliseconds 300 }
}

function Start-TmxGui {
    <#
    .SYNOPSIS
        Abre a GUI de desenvolvimento com a porta CDP e espera ela responder.
    .OUTPUTS
        [pscustomobject] @{ processo; porta; versaoCdp }
    #>
    [CmdletBinding()]
    param(
        [int]    $Port = 9333,
        [switch] $TestMode,
        [int]    $TimeoutSeconds = 60
    )

    Clear-TmxGuiLeftovers -Port $Port
    $saida = Initialize-TmxGuiOut

    $argumentos = @(
        '-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass',
        '-File', (Join-Path $script:TmxRepoRoot 'Start-TmxDev.ps1'),
        '-DebugPort', "$Port",
        '-NoElevate'
    )
    if ($TestMode) { $argumentos += '-TestMode' }

    $processo = Start-Process -FilePath 'powershell.exe' -ArgumentList $argumentos -PassThru `
        -RedirectStandardOutput (Join-Path $saida 'gui-stdout.txt') `
        -RedirectStandardError  (Join-Path $saida 'gui-stderr.txt')

    Set-Content -LiteralPath (Get-TmxGuiPidFile -Port $Port) -Value "$($processo.Id)" -Encoding ASCII

    $limite = (Get-Date).AddSeconds($TimeoutSeconds)
    $versao = $null
    while ((Get-Date) -lt $limite) {
        if ($processo.HasExited) {
            $erro = ''
            if (Test-Path -LiteralPath (Join-Path $saida 'gui-stderr.txt')) {
                $erro = (Get-Content -LiteralPath (Join-Path $saida 'gui-stderr.txt') -Raw)
            }
            throw "A GUI encerrou antes de abrir a porta CDP $Port.`n$erro"
        }
        try {
            $resp = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/json/version" -TimeoutSec 3 -ErrorAction Stop
            $versao = $resp
            break
        } catch {
            Start-Sleep -Milliseconds 500
        }
    }

    if (-not $versao) {
        Stop-TmxGui -Port $Port
        throw "A porta CDP $Port nao respondeu em $TimeoutSeconds s."
    }

    [pscustomobject]@{ processo = $processo; porta = $Port; versaoCdp = $versao }
}

function Stop-TmxGui {
    <#
    .SYNOPSIS
        Fecha a GUI de teste e confirma que a porta ficou livre.
    #>
    [CmdletBinding()]
    param([int] $Port = 9333)

    # 'close' e nao 'close --all': --all derrubaria tambem a sessao do
    # agent-browser de um teste de GUI concorrente em outra porta.
    try { Invoke-AB 'close' | Out-Null } catch { }

    Clear-TmxGuiLeftovers -Port $Port

    if (Test-TmxPortOpen -Port $Port) {
        Write-Warning "A porta $Port continua ocupada depois do Stop-TmxGui."
        return $false
    }
    $true
}

function Wait-TmxGuiPage {
    <#
    .SYNOPSIS
        Espera o WebView2 ter um alvo CDP na pagina da aplicacao.
    .DESCRIPTION
        A porta CDP abre antes da navegacao terminar. Conectar cedo demais
        prende o agent-browser num about:blank e todo seletor "some".
    #>
    [CmdletBinding()]
    param(
        [int]    $Port = 9333,
        [string] $UrlLike = '*app.tweakmaxing*',
        [int]    $TimeoutSeconds = 60
    )

    $limite = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $limite) {
        try {
            $alvos = @(Invoke-RestMethod -Uri "http://127.0.0.1:$Port/json" -TimeoutSec 3 -ErrorAction Stop)
            $pagina = @($alvos | Where-Object { $_.type -eq 'page' -and $_.url -like $UrlLike }) | Select-Object -First 1
            if ($pagina) { return $pagina }
        } catch { }
        Start-Sleep -Milliseconds 500
    }
    throw "Nenhuma pagina '$UrlLike' apareceu na porta CDP $Port em $TimeoutSeconds s."
}

function Invoke-AB {
    <#
    .SYNOPSIS
        Chama o agent-browser com limite de 30 s; devolve a saida padrao.
    .DESCRIPTION
        Lanca se o processo sair com codigo != 0 ou estourar o tempo - um
        comando do agent-browser que trava nao pode travar a suite inteira.
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]] $Argumentos
    )

    # O limite fica em variavel de script, nao em parametro: com
    # ValueFromRemainingArguments qualquer parametro extra rouba o primeiro
    # argumento posicional (Invoke-AB 'connect' '9333' virava TimeoutSeconds).
    $TimeoutSeconds = $script:TmxAbTimeoutSeconds

    # O npm instala tres nomes; so o .cmd e executavel direto por
    # Process.Start (o sem extensao e um shell script do Unix).
    $exe = @(Get-Command 'agent-browser.cmd', 'agent-browser' -ErrorAction SilentlyContinue |
             Where-Object { $_.CommandType -eq 'Application' -and $_.Source -like '*.cmd' } |
             Select-Object -First 1)
    if ($exe.Count -eq 0) { throw 'agent-browser.cmd nao esta no PATH (npm i -g agent-browser).' }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = $exe[0].Source
    $psi.UseShellExecute        = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.CreateNoWindow         = $true
    foreach ($a in $Argumentos) { $psi.Arguments += '"' + ($a -replace '"', '\"') + '" ' }

    $p = [System.Diagnostics.Process]::Start($psi)
    # ReadToEnd antes do WaitForExit: um pipe cheio bloqueia o processo filho.
    $saidaTask = $p.StandardOutput.ReadToEndAsync()
    $erroTask  = $p.StandardError.ReadToEndAsync()

    if (-not $p.WaitForExit($TimeoutSeconds * 1000)) {
        try { $p.Kill() } catch { }
        throw "agent-browser $($Argumentos -join ' ') estourou $TimeoutSeconds s."
    }

    # Leitura com prazo: o agent-browser deixa um daemon vivo que herda os
    # mesmos pipes, entao eles podem nunca fechar - .Result travaria para sempre
    # mesmo com o processo de linha de comando ja encerrado.
    $saida = ''
    $erro  = ''
    if ($saidaTask.Wait(5000)) { $saida = $saidaTask.Result }
    if ($erroTask.Wait(2000))  { $erro  = $erroTask.Result }
    if ($p.ExitCode -ne 0) {
        throw "agent-browser $($Argumentos -join ' ') saiu com $($p.ExitCode): $erro"
    }
    "$saida".Trim()
}
