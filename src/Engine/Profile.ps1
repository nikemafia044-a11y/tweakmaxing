# Engine/Profile.ps1
# Perfil de hardware/SO usado pelas condicoes do catalogo e pelo plano.
# Porta reduzida do CS2Tuner (Profile/Get-OsProfile.ps1, Get-NetworkProfile.ps1,
# Get-StorageProfile.ps1, Get-MemoryProfile.ps1, Get-GpuProfile.ps1, Get-TunerProfile.ps1):
# mantem so os campos usados pelas condicoes/plano do TweakMaxing e descarta
# polling de mouse, offenders, display e input (fora de escopo do Engine).
#
# Cada secao e coletada isoladamente: uma falhar nao derruba as outras -
# Get-TmxProfile sempre retorna todas as secoes (com campos $null quando a
# coleta falha ou exige elevacao que nao temos).

function Get-TmxDeviceGuardStatus {
    # VirtualizationBasedSecurityStatus: 0 desligado, 1 habilitado sem rodar, 2 rodando.
    try {
        $dg = Get-CimInstance -Namespace 'root\Microsoft\Windows\DeviceGuard' -ClassName Win32_DeviceGuard -ErrorAction Stop
        return [pscustomobject]@{ vbsAtivo = ([int]$dg.VirtualizationBasedSecurityStatus -eq 2) }
    } catch {
        $h = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' -Name Enabled -ErrorAction SilentlyContinue).Enabled
        return [pscustomobject]@{ vbsAtivo = if ($null -ne $h) { ([int]$h -eq 1) } else { $null } }
    }
}

function Get-TmxBcdSettings {
    # bcdedit exige elevacao; sem ela: disponivel = $false e os demais campos $null.
    if (-not (Test-TmxElevation)) {
        return [pscustomobject]@{ disponivel = $false; numproc = $null; useplatformclock = $null; disabledynamictick = $null }
    }
    try {
        $out = (& bcdedit.exe /enum '{current}' 2>&1) -join "`n"
        $get = { param($k) if ($out -match "(?im)^\s*$k\s+(\S+)") { $matches[1] } else { $null } }
        [pscustomobject]@{
            disponivel         = $true
            numproc            = & $get 'numproc'
            useplatformclock   = & $get 'useplatformclock'
            disabledynamictick = & $get 'disabledynamictick'
        }
    } catch {
        [pscustomobject]@{ disponivel = $false; numproc = $null; useplatformclock = $null; disabledynamictick = $null }
    }
}

function Get-TmxOsSection {
    [CmdletBinding()]
    param()
    try {
        $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
        $build = [int]$cv.CurrentBuildNumber
        $nome  = if ($build -ge 22000) { 'Windows 11' } else { 'Windows 10' }

        $chassis = Get-TmxChassisInfo
        $virt    = Get-TmxVirtualizationInfo
        $dg      = Get-TmxDeviceGuardStatus

        [pscustomobject]@{
            build    = $build
            nome     = $nome
            versao   = "$($cv.DisplayVersion)"
            isLaptop = $chassis.isLaptop
            isVM     = $virt.isVM
            elevado  = (Test-TmxElevation)
            vbsAtivo = $dg.vbsAtivo
            bcd      = Get-TmxBcdSettings
        }
    } catch {
        Write-TmxLog -Level WARN -Message "Falha ao coletar perfil de SO: $($_.Exception.Message)"
        [pscustomobject]@{ build = $null; nome = $null; versao = $null; isLaptop = $null; isVM = $null; elevado = $null; vbsAtivo = $null
                           bcd = [pscustomobject]@{ disponivel = $null; numproc = $null; useplatformclock = $null; disabledynamictick = $null } }
    }
}

function Get-TmxAdapterSummary {
    param([Parameter(Mandatory)] $Adapter)
    $tipo = if ("$($Adapter.PhysicalMediaType)" -match '802\.11|Wireless|WiFi' -or "$($Adapter.MediaType)" -match '802\.11') { 'WiFi' }
            elseif ("$($Adapter.PhysicalMediaType)" -match '802\.3' -or "$($Adapter.MediaType)" -eq '802.3') { 'Ethernet' }
            else { 'Outro' }
    [pscustomobject]@{
        nome      = "$($Adapter.Name)"
        tipo      = $tipo
        descricao = "$($Adapter.InterfaceDescription)"
    }
}

function Get-TmxNetworkSection {
    [CmdletBinding()]
    param()
    try {
        $fisicos = @(Get-NetAdapter -ErrorAction Stop | Where-Object { -not $_.Virtual -and $_.HardwareInterface })

        $rota = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
                Sort-Object RouteMetric, InterfaceMetric | Select-Object -First 1

        $ativo = $null
        if ($rota) { $ativo = $fisicos | Where-Object { $_.InterfaceIndex -eq $rota.InterfaceIndex } | Select-Object -First 1 }
        if (-not $ativo) { $ativo = $fisicos | Where-Object { "$($_.Status)" -eq 'Up' } | Select-Object -First 1 }
        if (-not $ativo) { throw 'Nenhum adaptador fisico ativo encontrado' }

        [pscustomobject]@{ adaptadorAtivo = (Get-TmxAdapterSummary -Adapter $ativo) }
    } catch {
        Write-TmxLog -Level WARN -Message "Falha ao coletar perfil de rede: $($_.Exception.Message)"
        [pscustomobject]@{ adaptadorAtivo = $null }
    }
}

function Get-TmxTrimStatus {
    try {
        $out = (& fsutil.exe behavior query DisableDeleteNotify 2>&1) -join "`n"
        if ($out -match 'NTFS DisableDeleteNotify\s*=\s*(\d)') { return ($matches[1] -eq '0') }
        if ($out -match 'DisableDeleteNotify\s*=\s*(\d)')      { return ($matches[1] -eq '0') }
        $null
    } catch { $null }
}

function Get-TmxSystemDiskSection {
    [CmdletBinding()]
    param()

    $letra = "$env:SystemDrive".TrimEnd(':')
    $tipo = 'Desconhecido'; $midia = $null

    try {
        $part = Get-Partition -DriveLetter $letra -ErrorAction Stop
        $disk = $part | Get-Disk -ErrorAction Stop
        $numero = [int]$disk.Number
        $bus = $null
        $pd = Get-PhysicalDisk -ErrorAction SilentlyContinue | Where-Object { "$($_.DeviceId)" -eq "$numero" } | Select-Object -First 1
        if ($pd) { $bus = "$($pd.BusType)"; $midia = "$($pd.MediaType)" }
        $tipo = if ($bus -eq 'NVMe') { 'NVMe' }
                elseif ($midia -eq 'SSD') { 'SSD' }
                elseif ($midia -eq 'HDD') { 'HDD' }
                elseif ($disk.Model -match 'NVMe') { 'NVMe' }
                else { 'Desconhecido' }
    } catch {
        Write-TmxLog -Level WARN -Message "Nao foi possivel mapear o disco de ${letra}: $($_.Exception.Message)"
    }

    $ld = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='${letra}:'" -ErrorAction SilentlyContinue
    $livreGB = if ($ld) { [math]::Round($ld.FreeSpace / 1GB, 1) } else { $null }
    $pct     = if ($ld -and $ld.Size -gt 0) { [math]::Round($ld.FreeSpace / $ld.Size * 100, 1) } else { $null }

    [pscustomobject]@{
        tipo           = $tipo
        midia          = $midia
        trimAtivo      = if ($tipo -in @('NVMe', 'SSD')) { Get-TmxTrimStatus } else { $null }
        espacoLivrePct = $pct
        livreGB        = $livreGB
    }
}

function Find-TmxCs2Path {
    <#
    .SYNOPSIS
        Localiza cs2.exe pelas bibliotecas da Steam (libraryfolders.vdf). Nunca lanca;
        retorna $null quando nao encontrado ou quando qualquer passo falha.
    #>
    [CmdletBinding()]
    param()
    try {
        $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -Name SteamPath -ErrorAction SilentlyContinue).SteamPath
        if (-not $steam) { $steam = (Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' -Name InstallPath -ErrorAction SilentlyContinue).InstallPath }
        if (-not $steam) { return $null }

        $libs = @($steam)
        $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
        if (Test-Path $vdf) {
            $txt = Get-Content $vdf -Raw
            foreach ($m in [regex]::Matches($txt, '"path"\s+"([^"]+)"')) {
                $libs += ($m.Groups[1].Value -replace '\\\\', '\')
            }
        }
        foreach ($lib in ($libs | Select-Object -Unique)) {
            $exe = Join-Path $lib 'steamapps\common\Counter-Strike Global Offensive\game\bin\win64\cs2.exe'
            if (Test-Path $exe) { return $exe }
        }
        $null
    } catch {
        $null
    }
}

function Get-TmxStorageSection {
    [CmdletBinding()]
    param()
    try {
        [pscustomobject]@{
            discoSistema = Get-TmxSystemDiskSection
            cs2Path      = Find-TmxCs2Path
        }
    } catch {
        Write-TmxLog -Level WARN -Message "Falha ao coletar perfil de armazenamento: $($_.Exception.Message)"
        [pscustomobject]@{ discoSistema = $null; cs2Path = $null }
    }
}

function Get-TmxMemorySection {
    [CmdletBinding()]
    param()
    try {
        $dimms = @(Get-CimInstance -ClassName Win32_PhysicalMemory -ErrorAction Stop)
        if ($dimms.Count -eq 0) { throw 'Win32_PhysicalMemory nao retornou modulos' }
        $capacidade = [math]::Round((($dimms | Measure-Object -Property Capacity -Sum).Sum) / 1GB, 0)
        [pscustomobject]@{ capacidadeGB = $capacidade }
    } catch {
        Write-TmxLog -Level WARN -Message "Falha ao coletar perfil de memoria: $($_.Exception.Message)"
        [pscustomobject]@{ capacidadeGB = $null }
    }
}

function Get-TmxHagsAtivo {
    # HwSchMode: 2 = ligado, 1 = desligado, ausente = $null (padrao do driver).
    $gd = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -ErrorAction SilentlyContinue
    $mode = $null
    if ($gd -and ($gd.PSObject.Properties.Name -contains 'HwSchMode')) { $mode = [int]$gd.HwSchMode }
    switch ($mode) { 2 { $true } 1 { $false } default { $null } }
}

function Get-TmxGpuSection {
    [CmdletBinding()]
    param()
    try {
        $vcs = @(Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop)

        $adaptadores = foreach ($v in $vcs) {
            $desc = "$($v.AdapterCompatibility) $($v.Name)"
            $vendor = switch -Regex ($desc) {
                'NVIDIA'                  { 'NVIDIA' }
                'AMD|Advanced Micro|ATI ' { 'AMD' }
                'Intel'                   { 'Intel' }
                default                   { 'Outro' }
            }
            $nome = ("$($v.Name)" -replace '\s+', ' ').Trim()
            $integrada = ($nome -match 'Intel\(R\) (UHD|HD|Iris)') -or
                         ($nome -match 'Radeon\(TM\)\s*(Graphics|Vega\s*\d*\s*Graphics)') -or
                         ($nome -match '^AMD Radeon Graphics$') -or
                         ($nome -match '\bGraphics\b' -and $vendor -eq 'AMD' -and $nome -notmatch 'RX')

            $data = $null
            if ($v.DriverDate) { try { $data = ([datetime]$v.DriverDate).ToString('yyyy-MM-dd') } catch { } }

            [pscustomobject]@{
                modelo = $nome
                vendor = $vendor
                pnpId  = "$($v.PNPDeviceID)"
                integrada = [bool]$integrada
                _dataDriver = $data
            }
        }

        $principal = @($adaptadores | Where-Object { -not $_.integrada }) | Select-Object -First 1
        if (-not $principal) { $principal = @($adaptadores) | Select-Object -First 1 }

        $hagsAtivo = Get-TmxHagsAtivo
        $reflexProvavel = ($principal.vendor -eq 'NVIDIA' -and $principal.modelo -match 'GTX (9|1[0-9])\d\d|RTX')

        [pscustomobject]@{
            vendor         = $principal.vendor
            modelo         = $principal.modelo
            dataDriver     = $principal._dataDriver
            hagsAtivo      = $hagsAtivo
            reflexProvavel = [bool]$reflexProvavel
            adaptadores    = @($adaptadores | Select-Object modelo, vendor, pnpId, integrada)
        }
    } catch {
        Write-TmxLog -Level WARN -Message "Falha ao coletar perfil de GPU: $($_.Exception.Message)"
        [pscustomobject]@{ vendor = $null; modelo = $null; dataDriver = $null; hagsAtivo = $null; reflexProvavel = $null; adaptadores = @() }
    }
}

function Get-TmxProfile {
    <#
    .SYNOPSIS
        Monta o perfil usado pelas condicoes/plano do catalogo: os, network,
        storage, memory, gpu. Cada secao e isolada por try/catch - nunca lanca.
    #>
    [CmdletBinding()]
    param()

    $secoes = @{
        os      = { Get-TmxOsSection }
        network = { Get-TmxNetworkSection }
        storage = { Get-TmxStorageSection }
        memory  = { Get-TmxMemorySection }
        gpu     = { Get-TmxGpuSection }
    }

    $perfil = [ordered]@{}
    foreach ($chave in 'os', 'network', 'storage', 'memory', 'gpu') {
        try {
            $perfil[$chave] = & $secoes[$chave]
        } catch {
            Write-TmxLog -Level WARN -Message "Falha ao coletar secao '$chave' do perfil: $($_.Exception.Message)"
            $perfil[$chave] = $null
        }
    }

    [pscustomobject]$perfil
}

function Save-TmxProfile {
    <#
    .SYNOPSIS
        Salva o perfil em JSON. Sem -Path, usa <RunPath>/perfil.json da execucao ativa.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Profile,
        [string] $Path
    )
    if (-not $Path) {
        $run = Get-TmxRun
        if (-not $run) { throw 'Nenhuma execucao ativa e nenhum -Path informado.' }
        $Path = Join-Path $run.RunPath 'perfil.json'
    }
    $Profile | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8 -WhatIf:$false
    Write-TmxLog -Level INFO -Message 'Perfil salvo' -Data @{ arquivo = $Path }
    $Path
}

function Import-TmxProfile {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)
    Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}
