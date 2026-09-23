<#
.SYNOPSIS
    Bootstrap do TweakMaxing: guardas do host, elevacao e estado compartilhado.
.DESCRIPTION
    Este arquivo e a cabeca do TweakMaxing.ps1 compilado e tambem o que o
    Start-TmxDev.ps1 executa no modo de desenvolvimento. Ele NAO chama funcoes
    do TweakMaxing: no arquivo compilado as funcoes vem DEPOIS deste trecho.
    Tudo que depende delas mora em scripts/main.ps1.

    Saida: $global:sync (hashtable sincronizado) pronto para main.ps1. Quando a
    execucao foi delegada a um processo elevado, $global:sync fica $null e o
    main.ps1 se encerra sozinho.
.PARAMETER Headless
    Sem janela: usa -Preset/-Undo e escreve no console.
.PARAMETER DryRun
    Simula (nada e alterado). Com -Headless dispensa elevacao.
.PARAMETER Undo
    RunId a reverter, ou 'latest'.
.PARAMETER DebugPort
    Abre a porta CDP do WebView2 (usada pelos testes de GUI).
.PARAMETER TestMode
    Raiz isolada em <temp>\TweakMaxing_Tests e catalogo/ponto de restauracao de teste.
.PARAMETER NoElevate
    Nao relanca elevado (o chamador sabe o que esta fazendo).
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
# Marcador informativo, para quem abrir o arquivo saber que ele e o artefato
# compilado (o Compile.ps1 confere que ele continua aqui). Nenhuma decisao de
# execucao depende dele: sob 'iex' nao da para ler o proprio texto.
#TMX-COMPILED

# O Start-TmxDev.ps1 ja roda com 'Stop'; o artefato compilado comeca por este
# arquivo e herdaria o 'Continue' do host. Um erro nao-terminante engolido no
# meio de uma aplicacao de tweaks e exatamente o que nao pode acontecer, e uma
# diferenca de comportamento entre dev e compilado invalidaria os testes.
$ErrorActionPreference = 'Stop'

$script:TmxVersion = '#{version}'
$script:TmxRepo    = '#{repo}'

# Em desenvolvimento os marcadores acima nao foram substituidos pelo Compile.ps1;
# o Start-TmxDev.ps1 informa os valores reais por variavel de ambiente.
if ($script:TmxVersion -like '#{*') {
    $script:TmxVersion = if ($env:TMX_DEV_VERSION) { $env:TMX_DEV_VERSION } else { '0.0.0-dev' }
}
if ($script:TmxRepo -like '#{*') {
    $script:TmxRepo = if ($env:TMX_DEV_REPO) { $env:TMX_DEV_REPO } else { 'TweakMaxing/TweakMaxing' }
}

$global:sync   = $null
# Marcador explicito de "nao continue": o Start-TmxDev.ps1 faz dot-source deste
# arquivo, e um 'return' aqui devolve o controle para ele em vez de encerrar.
$global:TmxBootstrapAbortado = $true

# ---------------------------------------------------------------------------
# 1. Modo de linguagem
# ---------------------------------------------------------------------------
# Em ConstrainedLanguage nada aqui funciona (nem [Hashtable]::Synchronized).
# Melhor dizer isso de frente do que falhar em cascata mais adiante.
if ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') {
    Write-Host 'O TweakMaxing precisa de FullLanguage. Este PowerShell esta em modo restrito (AppLocker/WDAC).' -ForegroundColor Red
    return 1
}

# ---------------------------------------------------------------------------
# 2. Elevacao
# ---------------------------------------------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

# -Headless -DryRun nao escreve nada: pode rodar como usuario comum.
$precisaElevar = (-not $isAdmin) -and (-not $NoElevate) -and (-not ($Headless -and $DryRun))

if ($precisaElevar) {
    $raiz = Join-Path $env:LOCALAPPDATA 'TweakMaxing'
    New-Item -ItemType Directory -Path $raiz -Force | Out-Null

    # No modo de desenvolvimento quem carrega as funcoes e o Start-TmxDev.ps1;
    # relancar so este arquivo daria um processo elevado sem funcao nenhuma.
    $self = $env:TMX_DEV_ENTRY
    if (-not $self) { $self = $PSCommandPath }
    if (-not $self) {
        # Invocado por 'iex (irm ...)': nao existe arquivo no disco para o
        # processo elevado abrir.
        #
        # E NAO adianta tentar recuperar o proprio texto: sob 'iex', o
        # $MyInvocation.MyCommand.ScriptBlock e o do comando ENVOLVENTE (o
        # 'iex (irm ...)' que o usuario digitou), nao o corpo do artefato. O
        # caminho unico e honesto e baixar o release desta versao - em bytes,
        # com -OutFile, sem passar por string - e elevar apontando para o
        # arquivo.
        if ($script:TmxRepo -like 'SEU_USUARIO/*') {
            Write-Host 'Este TweakMaxing foi compilado com o repositorio de exemplo (REPO nao configurado):' -ForegroundColor Red
            Write-Host 'nao ha release para baixar e elevar. Salve o TweakMaxing.ps1 em disco e rode:' -ForegroundColor Red
            Write-Host '  powershell -ExecutionPolicy Bypass -File .\TweakMaxing.ps1' -ForegroundColor Yellow
            return
        }

        $url  = "https://github.com/$script:TmxRepo/releases/download/v$script:TmxVersion/TweakMaxing.ps1"
        $self = Join-Path $raiz "TweakMaxing-$script:TmxVersion.ps1"
        Write-Host "Baixando o TweakMaxing $script:TmxVersion para elevar..." -ForegroundColor Cyan
        try {
            # TLS 1.2 explicito: o default do PS 5.1 ainda e SSL3/TLS1.0 em
            # maquinas antigas.
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $url -OutFile $self -UseBasicParsing
        } catch {
            Write-Host "Nao foi possivel baixar $url" -ForegroundColor Red
            Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
            Write-Host 'Sem rede (ou sem esse release), salve o TweakMaxing.ps1 em disco e rode:' -ForegroundColor Yellow
            Write-Host '  powershell -ExecutionPolicy Bypass -File .\TweakMaxing.ps1' -ForegroundColor Yellow
            return
        }
        if (-not (Test-Path -LiteralPath $self)) {
            Write-Host "O download terminou sem gerar $self. Salve o TweakMaxing.ps1 em disco e rode com -File." -ForegroundColor Red
            return
        }
    }

    # Os parametros viajam como dados serializados, nunca como texto de comando:
    # nada que o usuario digitou e interpolado no -EncodedCommand.
    $parametros = @{}
    foreach ($p in $PSBoundParameters.GetEnumerator()) {
        if ($p.Value -is [switch]) { $parametros[$p.Key] = [bool]$p.Value }
        else                       { $parametros[$p.Key] = $p.Value }
    }

    $carga = [Convert]::ToBase64String(
        [Text.Encoding]::UTF8.GetBytes(
            [Management.Automation.PSSerializer]::Serialize(@{ ScriptPath = $self; Parameters = $parametros })))

    $boot = '$l=[Management.Automation.PSSerializer]::Deserialize(' +
            '[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(''' + $carga + ''')));' +
            '$p=$l.Parameters;& $l.ScriptPath @p'

    Start-Process powershell -Verb RunAs -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA',
        '-EncodedCommand', [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($boot))
    )
    return
}

# ---------------------------------------------------------------------------
# 3. Estado compartilhado
# ---------------------------------------------------------------------------
# Sincronizado porque a janela, os jobs e a thread principal leem e escrevem
# nele ao mesmo tempo.
$sync = [Hashtable]::Synchronized(@{})

$sync.version   = $script:TmxVersion
$sync.repo      = $script:TmxRepo
$sync.configs   = @{}
$sync.embedded  = @{}
$sync.testMode  = [bool]$TestMode
$sync.debugPort = $DebugPort
$sync.elevado   = $isAdmin

if ($TestMode) {
    # Raiz isolada: nenhum teste escreve em %LOCALAPPDATA%\TweakMaxing.
    $raizTeste = Join-Path ([IO.Path]::GetTempPath()) 'TweakMaxing_Tests'
    $sync.home = Join-Path $raizTeste 'home'
    $env:TWEAKMAXING_HOME = $sync.home
} else {
    $sync.home = Join-Path $env:LOCALAPPDATA 'TweakMaxing'
}

$sync.logDir   = Join-Path $sync.home 'logs'
New-Item -ItemType Directory -Path $sync.logDir -Force | Out-Null

$sync.selected = @{
    tweaks   = New-Object 'System.Collections.Generic.List[string]'
    apps     = New-Object 'System.Collections.Generic.List[string]'
    features = New-Object 'System.Collections.Generic.List[string]'
}

$sync.session       = $null
$sync.bridgeActions = @{}
$sync.activeJob     = $null
$sync.webRoot       = $null   # Start-TmxDev.ps1 (dev) ou o compilado preenchem
$sync.sdkDir        = $null
$sync.webview       = $null
$sync.window        = $null

# HKEY_USERS nao tem PSDrive por padrao e o catalogo tem acao em HKU:\.Default.
# Atencao: um PSDrive vale so para a runspace onde foi criado - a runspace da
# janela e as do pool precisam registrar de novo quando forem tocar em HKU:.
if (-not (Get-PSDrive HKU -ErrorAction SilentlyContinue)) {
    New-PSDrive -PSProvider Registry -Name HKU -Root HKEY_USERS -Scope Global | Out-Null
}

$sync.logPath = Join-Path $sync.logDir ('tweakmaxing_{0:yyyy-MM-dd_HH-mm-ss}.log' -f (Get-Date))
try {
    Start-Transcript -Path $sync.logPath -Append | Out-Null
} catch {
    # Alguns hosts nao suportam transcript; o log JSON por execucao continua.
    Write-Verbose "Transcript indisponivel: $($_.Exception.Message)"
}

$global:sync = $sync
$global:TmxBootstrapAbortado = $false
