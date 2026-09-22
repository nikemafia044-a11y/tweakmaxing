# functions/tweaks/_Wrappers.ps1
# Fronteira unica entre as funcoes nomeadas e o mundo externo.
#
# Regras:
#   - Todo executavel (icacls, dism, netsh, winget, cleanmgr, reg, setup.exe...)
#     e todo cmdlet que mexe no sistema passa por um wrapper fino daqui. Os
#     testes mockam o wrapper, nunca o comando real.
#   - Argumentos SEMPRE como array. Nunca concatenamos string em linha de
#     comando: e assim que caminho com espaco vira injecao de argumento.
#   - Nada de Write-Host. Quem precisa falar com o usuario devolve 'detalhe'.
#
# Wrappers de registro/servico/appx/feature/powercfg ja existem em
# Engine/Actions.ps1 e sao reusados aqui (Set-TmxRegistry, Get-TmxServiceState,
# Set-TmxServiceState, Get-TmxAppx, Remove-TmxAppx, Install-TmxStoreApp,
# Get-/Enable-/Disable-TmxWindowsFeature, Invoke-TmxPowercfg).

# ---------------------------------------------------------------------------
# Executaveis
# ---------------------------------------------------------------------------

function Invoke-TmxIcacls {
    param([Parameter(Mandatory)] [string[]] $Arguments)
    $out = & icacls.exe @Arguments 2>&1
    [pscustomobject]@{ saida = (@($out) -join "`n"); codigo = $LASTEXITCODE }
}

function Invoke-TmxDism {
    param([Parameter(Mandatory)] [string[]] $Arguments)
    $out = & dism.exe @Arguments 2>&1
    [pscustomobject]@{ saida = (@($out) -join "`n"); codigo = $LASTEXITCODE }
}

function Invoke-TmxNetsh {
    param([Parameter(Mandatory)] [string[]] $Arguments)
    $out = & netsh.exe @Arguments 2>&1
    [pscustomobject]@{ saida = (@($out) -join "`n"); codigo = $LASTEXITCODE }
}

function Invoke-TmxWinget {
    param([Parameter(Mandatory)] [string[]] $Arguments)
    $out = & winget.exe @Arguments 2>&1
    [pscustomobject]@{ saida = (@($out) -join "`n"); codigo = $LASTEXITCODE }
}

function Invoke-TmxCleanmgr {
    param([Parameter(Mandatory)] [string[]] $Arguments)
    $out = & cleanmgr.exe @Arguments 2>&1
    [pscustomobject]@{ saida = (@($out) -join "`n"); codigo = $LASTEXITCODE }
}

function Invoke-TmxIpconfig {
    param([Parameter(Mandatory)] [string[]] $Arguments)
    $out = & ipconfig.exe @Arguments 2>&1
    [pscustomobject]@{ saida = (@($out) -join "`n"); codigo = $LASTEXITCODE }
}

function Invoke-TmxRegImport {
    # Reimporta um .reg exportado por Backup-TmxRegistryHive.
    param([Parameter(Mandatory)] [string] $Arquivo)
    $out = & reg.exe import $Arquivo 2>&1
    [pscustomobject]@{ saida = (@($out) -join "`n"); codigo = $LASTEXITCODE }
}

function Invoke-TmxProcess {
    <#
    .SYNOPSIS
        Executa um programa arbitrario (setup.exe do Edge, OneDriveSetup.exe...)
        e espera terminar. Argumentos como array, sempre.
    #>
    param(
        [Parameter(Mandatory)] [string] $FilePath,
        [string[]] $ArgumentList = @(),
        [switch] $NaoEsperar
    )
    $p = if ($ArgumentList.Count -gt 0) {
        Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -PassThru -Wait:(-not $NaoEsperar) -ErrorAction Stop
    } else {
        Start-Process -FilePath $FilePath -PassThru -Wait:(-not $NaoEsperar) -ErrorAction Stop
    }
    $codigo = $null
    if ($p -and -not $NaoEsperar) { $codigo = $p.ExitCode }
    [pscustomobject]@{ codigo = $codigo }
}

function Start-TmxUrl {
    <#
    .SYNOPSIS
        Abre uma URL no navegador padrao. So aceita https: nunca abrimos
        caminho local nem esquema arbitrario por este caminho.
    #>
    param([Parameter(Mandatory)] [string] $Url)
    if ($Url -notmatch '^https://') { throw "URL recusada (so https e permitido): '$Url'" }
    Start-Process -FilePath $Url -ErrorAction Stop | Out-Null
    $Url
}

# ---------------------------------------------------------------------------
# Processos e shell
# ---------------------------------------------------------------------------

function Stop-TmxProcessByName {
    param([Parameter(Mandatory)] [string[]] $Nome)
    foreach ($n in $Nome) {
        Get-Process -Name $n -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
}

function Restart-TmxExplorer {
    # O explorer.exe volta sozinho quando morto (o shell e reiniciado pelo Winlogon).
    Stop-TmxProcessByName -Nome @('explorer')
}

function Get-TmxPhysicalMemoryKB {
    [int64]((Get-CimInstance -ClassName Win32_PhysicalMemory -ErrorAction Stop | Measure-Object -Property Capacity -Sum).Sum / 1KB)
}

function Get-TmxLocalUserSid {
    param([string] $Nome = $env:UserName)
    (Get-LocalUser -Name $Nome -ErrorAction Stop).Sid.Value
}

# ---------------------------------------------------------------------------
# Sistema de arquivos
# ---------------------------------------------------------------------------

function Test-TmxItemPath {
    param([Parameter(Mandatory)] [string] $Path)
    Test-Path -LiteralPath $Path
}

function New-TmxDirectory {
    param([Parameter(Mandatory)] [string] $Path)
    New-Item -ItemType Directory -Path $Path -Force -ErrorAction Stop | Out-Null
    $Path
}

function New-TmxEmptyFile {
    <#
    .SYNOPSIS
        Cria um arquivo vazio, criando os diretorios do caminho se preciso.
    .NOTES
        Nao sobrescreve: New-Item -Force sobre arquivo TRUNCA o que existir. O
        unico uso hoje e o arquivo isca que destrava o desinstalador do Edge,
        dentro de SystemApps; truncar um binario de sistema por engano seria um
        estrago que nenhum undo desfaz.
    #>
    param([Parameter(Mandatory)] [string] $Path)
    if (Test-Path -LiteralPath $Path) { return $Path }
    New-Item -ItemType File -Path $Path -Force -ErrorAction Stop | Out-Null
    $Path
}

function Remove-TmxItemPath {
    <#
    .SYNOPSIS
        Remove arquivo ou pasta. -Silencioso para alvos que quase sempre tem
        arquivo em uso (as pastas TEMP, por exemplo).
    #>
    param(
        [Parameter(Mandatory)] [string] $Path,
        [switch] $Recursivo,
        [switch] $Silencioso
    )
    $ea = 'Stop'
    if ($Silencioso) { $ea = 'SilentlyContinue' }
    Remove-Item -Path $Path -Recurse:$Recursivo -Force -ErrorAction $ea
}

function Copy-TmxItemPath {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Destino
    )
    Copy-Item -LiteralPath $Path -Destination $Destino -Force -ErrorAction Stop
    $Destino
}

function Get-TmxFileText {
    param([Parameter(Mandatory)] [string] $Path)
    Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
}

function Add-TmxFileText {
    <#
    .SYNOPSIS
        Anexa texto a um arquivo em ASCII.
    .NOTES
        -Encoding ASCII e explicito de proposito. O unico consumidor e o arquivo
        hosts, que o resolvedor do Windows le como texto de byte unico: anexar em
        UTF-16 (o default de Add-Content em algumas configuracoes) ou deixar um
        BOM no meio do arquivo corrompe o hosts inteiro, nao so a linha nova.
    #>
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Texto
    )
    Add-Content -LiteralPath $Path -Value $Texto -Encoding ASCII -ErrorAction Stop
}

function Invoke-TmxWebRequestText {
    param([Parameter(Mandatory)] [string] $Uri)
    if ($Uri -notmatch '^https://') { throw "Download recusado (so https e permitido): '$Uri'" }
    Invoke-RestMethod -Uri $Uri -ErrorAction Stop
}

# ---------------------------------------------------------------------------
# Registro (leitura) e variaveis de ambiente de maquina
# ---------------------------------------------------------------------------

function Get-TmxRegistryValue {
    # Valor atual, ou $null se a chave/valor nao existir. Nunca lanca.
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Name
    )
    try {
        $p = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop
        if ($null -eq $p) { return $null }
        if (-not ($p.PSObject.Properties.Name -contains $Name)) { return $null }
        return $p.$Name
    } catch {
        return $null
    }
}

function Get-TmxMachineEnvVar {
    param([Parameter(Mandatory)] [string] $Nome)
    [Environment]::GetEnvironmentVariable($Nome, 'Machine')
}

function Set-TmxMachineEnvVar {
    param(
        [Parameter(Mandatory)] [string] $Nome,
        [AllowNull()] [AllowEmptyString()] [string] $Valor
    )
    [Environment]::SetEnvironmentVariable($Nome, $Valor, 'Machine')
}

# ---------------------------------------------------------------------------
# Defender / BitLocker
# ---------------------------------------------------------------------------

function Get-TmxDefenderPreference {
    Get-MpPreference -ErrorAction Stop
}

function Set-TmxDefenderSubmitSamples {
    param([Parameter(Mandatory)] [int] $Valor)
    Set-MpPreference -SubmitSamplesConsent $Valor -ErrorAction Stop
}

function Get-TmxBitLockerStatus {
    param([Parameter(Mandatory)] [string] $MountPoint)
    Get-BitLockerVolume -MountPoint $MountPoint -ErrorAction Stop
}

function Disable-TmxBitLockerVolume {
    param([Parameter(Mandatory)] [string] $MountPoint)
    Disable-BitLocker -MountPoint $MountPoint -ErrorAction Stop | Out-Null
}

function Enable-TmxBitLockerVolume {
    param([Parameter(Mandatory)] [string] $MountPoint)
    Enable-BitLocker -MountPoint $MountPoint -TpmProtector -SkipHardwareTest -ErrorAction Stop | Out-Null
}

# ---------------------------------------------------------------------------
# Rede
# ---------------------------------------------------------------------------

function Get-TmxNetAdapterBindingState {
    param([Parameter(Mandatory)] [string] $ComponentID)
    Get-NetAdapterBinding -ComponentID $ComponentID -ErrorAction Stop
}

function Set-TmxNetAdapterBindingState {
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $ComponentID,
        [Parameter(Mandatory)] [bool] $Habilitado
    )
    if ($Habilitado) { Enable-NetAdapterBinding  -Name $Name -ComponentID $ComponentID -ErrorAction Stop }
    else             { Disable-NetAdapterBinding -Name $Name -ComponentID $ComponentID -ErrorAction Stop }
}

function Get-TmxActiveNetAdapter {
    # Adaptadores realmente conectados. Sem eles, nao ha o que configurar.
    Get-NetAdapter -ErrorAction Stop | Where-Object { "$($_.Status)" -eq 'Up' }
}

function Get-TmxDnsServerAddress {
    param(
        [Parameter(Mandatory)] [int] $InterfaceIndex,
        [int] $Familia = 2
    )
    Get-DnsClientServerAddress -InterfaceIndex $InterfaceIndex -AddressFamily $Familia -ErrorAction Stop
}

function Set-TmxDnsServerAddress {
    param(
        [Parameter(Mandatory)] [int] $InterfaceIndex,
        [string[]] $Servidores = @(),
        [switch] $Reset
    )
    if ($Reset) {
        Set-DnsClientServerAddress -InterfaceIndex $InterfaceIndex -ResetServerAddresses -ErrorAction Stop
    } else {
        Set-DnsClientServerAddress -InterfaceIndex $InterfaceIndex -ServerAddresses $Servidores -ErrorAction Stop
    }
}

# ---------------------------------------------------------------------------
# Caminhos de terceiros que precisam ser resolvidos ao vivo
# ---------------------------------------------------------------------------

function Get-TmxEdgeSetupPath {
    # setup.exe da versao instalada do Edge, ou $null se o Edge nao estiver la.
    $padrao = Join-Path "$($env:ProgramFiles) (x86)" 'Microsoft\Edge\Application\*\Installer\setup.exe'
    $achado = Get-Item -Path $padrao -ErrorAction SilentlyContinue | Sort-Object FullName | Select-Object -Last 1
    if ($achado) { return $achado.FullName }
    $null
}

function Get-TmxHostsPath {
    Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
}
