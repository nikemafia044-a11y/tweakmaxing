# functions/microwin/_Wrappers.ps1
# Fronteira do MicroWin com o mundo externo: oscdimg, Mount-DiskImage, o DISM
# do PowerShell (Get-/Mount-/Dismount-WindowsImage, *ProvisionedAppxPackage,
# *WindowsPackage), robocopy e espaco em disco.
#
# Mesma regra das outras abas: argumentos sempre em array, nunca 'cmd /c',
# nada de Write-Host, e cada chamada externa mora numa funcao fina para que os
# testes mockem o wrapper e exercitem de verdade a logica que esta em volta.
#
# NADA aqui altera a ISO de origem: ela e montada somente para leitura e o
# trabalho acontece numa copia dentro da pasta de trabalho.

# ---------------------------------------------------------------------------
# oscdimg (Windows ADK - Deployment Tools)
# ---------------------------------------------------------------------------

function Get-TmxOscdimgPath {
    <#
    .SYNOPSIS
        Caminho do oscdimg.exe, ou $null quando o ADK nao esta instalado.
    .DESCRIPTION
        Procura, nesta ordem:
          1. o caminho canonico do ADK (amd64\Oscdimg) em Program Files (x86)
             e em Program Files;
          2. os Links do winget (o pacote Microsoft.OSCDIMG cai la);
          3. o PATH.
        Nao instala nada: quem decide o que fazer com a ausencia e a acao da
        ponte (microwin.check), que devolve a mensagem com o link do ADK.
    #>
    [CmdletBinding()]
    param()

    $relativo = 'Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe'
    $candidatos = New-Object 'System.Collections.Generic.List[string]'
    foreach ($raiz in @(${env:ProgramFiles(x86)}, $env:ProgramFiles)) {
        if ($raiz) { $candidatos.Add((Join-Path $raiz $relativo)) }
    }
    if ($env:LOCALAPPDATA) { $candidatos.Add((Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\oscdimg.exe')) }
    if ($env:ProgramFiles) { $candidatos.Add((Join-Path $env:ProgramFiles 'WinGet\Links\oscdimg.exe')) }

    foreach ($c in $candidatos.ToArray()) {
        if ($c -and (Test-Path -LiteralPath $c)) { return "$c" }
    }

    $noPath = Get-Command -Name 'oscdimg.exe' -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($noPath) { return "$($noPath.Source)" }

    $null
}

function Invoke-TmxOscdimg {
    <#
    .SYNOPSIS
        Roda o oscdimg com os argumentos dados (array, nunca linha unica).
    .OUTPUTS
        [pscustomobject] @{ codigo; saida }
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string[]] $Arguments)

    $exe = Get-TmxOscdimgPath
    if (-not $exe) { throw 'oscdimg.exe nao encontrado: instale o Windows ADK (Deployment Tools)' }

    $out = & $exe @Arguments 2>&1
    [pscustomobject]@{ codigo = $LASTEXITCODE; saida = (@($out) -join "`n") }
}

# ---------------------------------------------------------------------------
# Imagem de disco (ISO)
# ---------------------------------------------------------------------------

function Mount-TmxDiskImageWrapper {
    <#
    .SYNOPSIS
        Monta um .iso e devolve a letra do volume resultante.
    .OUTPUTS
        A letra (ex.: 'F'), ou $null se o volume nao apareceu.
    .NOTES
        -Access ReadOnly de proposito: a ISO de origem nunca e alterada.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)

    $imagem = Mount-DiskImage -ImagePath $Path -Access ReadOnly -PassThru -ErrorAction Stop
    $volume = $imagem | Get-Volume -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $volume) {
        # O volume as vezes demora um instante para ser publicado.
        Start-Sleep -Milliseconds 800
        $volume = Get-DiskImage -ImagePath $Path -ErrorAction SilentlyContinue |
            Get-Volume -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    if ($null -eq $volume) { return $null }
    "$($volume.DriveLetter)"
}

function Dismount-TmxDiskImageWrapper {
    <#
    .SYNOPSIS
        Desmonta um .iso. Nunca lanca: desmontar o que nao esta montado nao e erro.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)

    try {
        Dismount-DiskImage -ImagePath $Path -ErrorAction Stop | Out-Null
        $true
    } catch {
        Write-Verbose "Dismount-DiskImage falhou para '$Path': $($_.Exception.Message)"
        $false
    }
}

# ---------------------------------------------------------------------------
# Imagem do Windows (WIM/ESD)
# ---------------------------------------------------------------------------

function Get-TmxWindowsImageWrapper {
    <#
    .SYNOPSIS
        Get-WindowsImage do arquivo inteiro (sem -Index) ou de uma edicao.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $ImagePath,
        [int] $Index
    )
    if ($PSBoundParameters.ContainsKey('Index') -and $Index -gt 0) {
        return (Get-WindowsImage -ImagePath $ImagePath -Index $Index -ErrorAction Stop)
    }
    Get-WindowsImage -ImagePath $ImagePath -ErrorAction Stop
}

function Mount-TmxWindowsImageWrapper {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $ImagePath,
        [Parameter(Mandatory)] [int]    $Index,
        [Parameter(Mandatory)] [string] $Path,
        [string] $ScratchDirectory
    )
    $p = @{ ImagePath = $ImagePath; Index = $Index; Path = $Path; ErrorAction = 'Stop' }
    if ($ScratchDirectory) { $p.ScratchDirectory = $ScratchDirectory }
    Mount-WindowsImage @p
}

function Dismount-TmxWindowsImageWrapper {
    <#
    .SYNOPSIS
        Desmonta a imagem gravando (-Save) ou descartando (-Discard) as mudancas.
    .NOTES
        Exatamente um dos dois e obrigatorio: um Dismount sem escolha explicita
        deixaria ao acaso a diferenca entre "gerou a ISO" e "jogou fora o
        trabalho", e o caminho de erro do build depende de descartar de verdade.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [switch] $Save,
        [switch] $Discard
    )
    if ($Save -and $Discard)           { throw 'Dismount-TmxWindowsImageWrapper: -Save e -Discard sao exclusivos' }
    if (-not $Save -and -not $Discard) { throw 'Dismount-TmxWindowsImageWrapper: informe -Save ou -Discard' }

    if ($Save) { return (Dismount-WindowsImage -Path $Path -Save -ErrorAction Stop) }
    Dismount-WindowsImage -Path $Path -Discard -ErrorAction Stop
}

function Export-TmxWindowsImageWrapper {
    <#
    .SYNOPSIS
        Exporta uma edicao de um .esd/.wim para um .wim novo (que nasce no indice 1).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $SourceImagePath,
        [Parameter(Mandatory)] [int]    $SourceIndex,
        [Parameter(Mandatory)] [string] $DestinationImagePath,
        [string] $CompressionType = 'Max'
    )
    Export-WindowsImage -SourceImagePath $SourceImagePath -SourceIndex $SourceIndex `
        -DestinationImagePath $DestinationImagePath -CompressionType $CompressionType -ErrorAction Stop
}

# ---------------------------------------------------------------------------
# Pacotes dentro da imagem montada
# ---------------------------------------------------------------------------

function Get-TmxProvisionedAppxWrapper {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)
    Get-ProvisionedAppxPackage -Path $Path -ErrorAction Stop
}

function Remove-TmxProvisionedAppxWrapper {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $PackageName
    )
    Remove-ProvisionedAppxPackage -Path $Path -PackageName $PackageName -ErrorAction Stop
}

function Get-TmxWindowsPackageWrapper {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)
    Get-WindowsPackage -Path $Path -ErrorAction Stop
}

function Remove-TmxWindowsPackageWrapper {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $PackageName
    )
    Remove-WindowsPackage -Path $Path -PackageName $PackageName -ErrorAction Stop
}

# ---------------------------------------------------------------------------
# Arquivos
# ---------------------------------------------------------------------------

function Copy-TmxIsoTree {
    <#
    .SYNOPSIS
        Copia a arvore da ISO montada para a pasta de trabalho (robocopy).
    .OUTPUTS
        O codigo de saida do robocopy. 0..7 e sucesso; 8 ou mais e falha.
    .NOTES
        robocopy e nao Copy-Item: sao milhares de arquivos e um install.wim de
        varios GB. /NFL /NDL /NJH /NJS silenciam a listagem (a saida inteira
        viraria log inutil) e /R:2 /W:2 evitam a espera padrao de 30 s por
        arquivo travado.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Source,
        [Parameter(Mandatory)] [string] $Destination
    )

    $argumentos = @($Source, $Destination, '/E', '/R:2', '/W:2', '/NFL', '/NDL', '/NJH', '/NJS', '/NP')
    & robocopy.exe @argumentos | Out-Null
    [int]$LASTEXITCODE
}

function Set-TmxPathWritable {
    <#
    .SYNOPSIS
        Tira o somente-leitura de uma arvore recem-copiada da ISO. Nunca lanca.
    .DESCRIPTION
        Tudo que sai de um volume UDF montado chega com ReadOnly ligado; sem
        isso a regravacao do install.wim falha com "acesso negado" varios
        passos depois, longe da causa.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)

    try {
        foreach ($item in @(Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue)) {
            if ($item.IsReadOnly) { $item.IsReadOnly = $false }
        }
        $true
    } catch {
        Write-Verbose "Nao foi possivel limpar o somente-leitura de '$Path': $($_.Exception.Message)"
        $false
    }
}

function Get-TmxInstallImagePath {
    <#
    .SYNOPSIS
        Acha sources\install.wim ou sources\install.esd dentro de uma raiz de ISO.
    .OUTPUTS
        [pscustomobject] @{ caminho; formato } - formato e 'wim' ou 'esd'.
        $null quando nenhum dos dois existe.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Raiz)

    foreach ($par in @(
        @{ nome = 'install.wim'; formato = 'wim' },
        @{ nome = 'install.esd'; formato = 'esd' }
    )) {
        $caminho = Join-Path (Join-Path $Raiz 'sources') $par.nome
        if (Test-Path -LiteralPath $caminho) {
            return [pscustomobject]@{ caminho = "$caminho"; formato = "$($par.formato)" }
        }
    }
    $null
}

function Get-TmxFreeSpaceGB {
    <#
    .SYNOPSIS
        Espaco livre (GB, uma casa) da unidade indicada. -1 quando nao da para saber.
    .PARAMETER Drive
        Letra ('C'), letra com dois-pontos ('C:') ou um caminho qualquer.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Drive)

    $letra = "$Drive".Trim()
    if ($letra.Length -gt 1) {
        $qualificador = ''
        try { $qualificador = "$(Split-Path -Qualifier $letra)" } catch { $qualificador = '' }
        if ($qualificador) { $letra = $qualificador }
    }
    $letra = ($letra -replace '[^A-Za-z]', '')
    if (-not $letra) { return -1.0 }
    $letra = $letra.Substring(0, 1).ToUpperInvariant()

    try {
        $filtro = "DeviceID='{0}:'" -f $letra
        $disco = Get-CimInstance -ClassName Win32_LogicalDisk -Filter $filtro -ErrorAction Stop
        if ($null -eq $disco) { return -1.0 }
        return [math]::Round(([double]$disco.FreeSpace / 1GB), 1)
    } catch {
        Write-Verbose "Espaco livre de '$letra' indisponivel: $($_.Exception.Message)"
        return -1.0
    }
}

function Get-TmxFileSizeGB {
    <#
    .SYNOPSIS
        Tamanho de um arquivo em GB (duas casas). 0 quando o arquivo nao existe.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)

    if (-not (Test-Path -LiteralPath $Path)) { return 0.0 }
    try {
        $item = Get-Item -LiteralPath $Path -ErrorAction Stop
        [math]::Round(([double]$item.Length / 1GB), 2)
    } catch {
        0.0
    }
}
