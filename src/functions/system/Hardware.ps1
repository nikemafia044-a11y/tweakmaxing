# functions/system/Hardware.ps1
# Backend de system.info (painel): CPU, GPU (com VRAM), RAM (tipo/velocidade),
# disco do sistema, SO, chassi, HAGS e recomendacoes.
#
# Cada secao e coletada isoladamente com o proprio try/catch: uma falhar nunca
# derruba as outras, e todo campo pode voltar $null (nunca lanca). Reaproveita
# o que o Engine/Profile.ps1 e o Core/Guard.ps1 ja coletam (Get-TmxGpuSection,
# Get-TmxHagsAtivo, Get-TmxChassisInfo, Get-TmxOsBuild) para nao duplicar
# deteccao de fabricante/chassi/HAGS.

# ---------------------------------------------------------------------------
# CPU
# ---------------------------------------------------------------------------

function Get-TmxCpuInfo {
    [CmdletBinding()]
    param()
    try {
        $cpu = @(Get-TmxCimSafe -ClassName 'Win32_Processor') | Select-Object -First 1
        if (-not $cpu) { return @{ modelo = $null; nucleos = $null } }
        @{ modelo = ("$($cpu.Name)").Trim(); nucleos = [int]$cpu.NumberOfCores }
    } catch {
        Write-TmxLog -Level WARN -Message "Falha ao coletar CPU: $($_.Exception.Message)"
        @{ modelo = $null; nucleos = $null }
    }
}

# ---------------------------------------------------------------------------
# GPU (com VRAM via HardwareInformation.qwMemorySize, fallback AdapterRAM)
# ---------------------------------------------------------------------------

function Get-TmxGpuVramBytes {
    <#
    .SYNOPSIS
        VRAM em bytes lida de HKLM\...\Class\{4d36e968-...}\000N, casando
        DriverDesc com o nome da GPU. $null quando nao encontrada.
    .DESCRIPTION
        O valor HardwareInformation.qwMemorySize pode vir como QWORD (int64
        direto) ou como Binary (byte[] de 8 bytes, little-endian) - depende
        do driver. Os dois casos sao tratados aqui.
    #>
    [CmdletBinding()]
    param([string] $Modelo)

    if (-not $Modelo) { return $null }

    $classe = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
    if (-not (Test-Path -LiteralPath $classe)) { return $null }

    foreach ($nome in @(Get-TmxRegistryChildNamesSafe -Path $classe)) {
        if ($nome -notmatch '^\d{4}$') { continue }
        $sub  = Join-Path $classe $nome
        $desc = Get-TmxItemPropertySafe -Path $sub -Name 'DriverDesc'
        if (-not $desc) { continue }
        if ("$desc" -ne "$Modelo") { continue }

        $raw = Get-TmxItemPropertySafe -Path $sub -Name 'HardwareInformation.qwMemorySize'
        if ($null -eq $raw) { continue }

        if ($raw -is [byte[]]) {
            if ($raw.Length -ge 8) { return [int64][BitConverter]::ToUInt64($raw, 0) }
            continue
        }
        try { return [int64]$raw } catch { continue }
    }
    $null
}

function Get-TmxGpuInfo {
    [CmdletBinding()]
    param()
    try {
        $perfil    = Get-TmxGpuSection
        $vcs       = @(Get-TmxCimSafe -ClassName 'Win32_VideoController')
        $principal = @($vcs | Where-Object { ("$($_.Name)" -replace '\s+', ' ').Trim() -eq "$($perfil.modelo)" }) |
            Select-Object -First 1
        if (-not $principal) { $principal = @($vcs) | Select-Object -First 1 }

        $vramBytes = Get-TmxGpuVramBytes -Modelo $perfil.modelo
        if (-not $vramBytes -and $principal -and $principal.AdapterRAM) { $vramBytes = [int64]$principal.AdapterRAM }

        $vramGB = $null
        if ($vramBytes) { $vramGB = [math]::Round($vramBytes / 1GB, 1) }

        @{ modelo = $perfil.modelo; vramGB = $vramGB; fabricante = $perfil.vendor }
    } catch {
        Write-TmxLog -Level WARN -Message "Falha ao coletar GPU: $($_.Exception.Message)"
        @{ modelo = $null; vramGB = $null; fabricante = $null }
    }
}

# ---------------------------------------------------------------------------
# RAM
# ---------------------------------------------------------------------------

function Get-TmxRamInfo {
    [CmdletBinding()]
    param()
    try {
        $dimms = @(Get-TmxCimSafe -ClassName 'Win32_PhysicalMemory')
        if ($dimms.Count -eq 0) {
            return @{ totalGB = $null; tipo = $null; velocidadeNominal = $null; velocidadeConfigurada = $null }
        }

        $totalBytes = ($dimms | Measure-Object -Property Capacity -Sum).Sum
        $totalGB    = if ($totalBytes) { [math]::Round($totalBytes / 1GB, 0) } else { $null }

        # Primeiro modulo como representativo: aproximacao documentada - uma
        # maquina com pentes de velocidades/tipos diferentes (incomum, e o
        # BIOS normalmente nivela pelo mais lento) reportaria so o do primeiro.
        $primeiro   = $dimms[0]
        $tipoCodigo = 0
        try { $tipoCodigo = [int]$primeiro.SMBIOSMemoryType } catch { $tipoCodigo = 0 }
        $tipo = switch ($tipoCodigo) {
            24      { 'DDR3' }
            26      { 'DDR4' }
            34      { 'DDR5' }
            default { '?' }
        }

        $nominal      = $null
        $configurada  = $null
        if ($primeiro.Speed)                 { $nominal     = [int]$primeiro.Speed }
        if ($primeiro.ConfiguredClockSpeed)   { $configurada = [int]$primeiro.ConfiguredClockSpeed }

        @{ totalGB = $totalGB; tipo = $tipo; velocidadeNominal = $nominal; velocidadeConfigurada = $configurada }
    } catch {
        Write-TmxLog -Level WARN -Message "Falha ao coletar RAM: $($_.Exception.Message)"
        @{ totalGB = $null; tipo = $null; velocidadeNominal = $null; velocidadeConfigurada = $null }
    }
}

# ---------------------------------------------------------------------------
# Disco do sistema (particao C:)
# ---------------------------------------------------------------------------

function Get-TmxDiskInfo {
    [CmdletBinding()]
    param()
    try {
        $letra = "$env:SystemDrive".TrimEnd(':')
        $part  = Get-TmxPartitionSafe -DriveLetter $letra
        if (-not $part) { return @{ tamanhoGB = $null; tipo = $null; modelo = $null } }

        $disk = Get-TmxDiskFromPartitionSafe -Partition $part
        if (-not $disk) { return @{ tamanhoGB = $null; tipo = $null; modelo = $null } }

        $numero = [int]$disk.Number
        $pd = @(Get-TmxPhysicalDisksSafe | Where-Object { "$($_.DeviceId)" -eq "$numero" }) | Select-Object -First 1

        $tipo = 'Desconhecido'
        if ($pd) {
            if ("$($pd.BusType)" -eq 'NVMe')        { $tipo = 'NVMe' }
            elseif ("$($pd.MediaType)" -eq 'SSD')    { $tipo = 'SSD' }
            elseif ("$($pd.MediaType)" -eq 'HDD')    { $tipo = 'HDD' }
        }
        if ($tipo -eq 'Desconhecido' -and "$($disk.Model)" -match 'NVMe') { $tipo = 'NVMe' }

        $modelo = if ($pd -and "$($pd.FriendlyName)") { "$($pd.FriendlyName)" } else { "$($disk.Model)".Trim() }
        $tamanhoGB = if ($disk.Size) { [math]::Round($disk.Size / 1GB, 0) } else { $null }

        @{ tamanhoGB = $tamanhoGB; tipo = $tipo; modelo = $modelo }
    } catch {
        Write-TmxLog -Level WARN -Message "Falha ao coletar disco do sistema: $($_.Exception.Message)"
        @{ tamanhoGB = $null; tipo = $null; modelo = $null }
    }
}

# ---------------------------------------------------------------------------
# Sistema operacional
# ---------------------------------------------------------------------------

function Get-TmxOsInfo {
    [CmdletBinding()]
    param()
    try {
        $os     = @(Get-TmxCimSafe -ClassName 'Win32_OperatingSystem') | Select-Object -First 1
        $edicao = $null
        if ($os -and "$($os.Caption)") { $edicao = ("$($os.Caption)" -replace '^Microsoft\s+', '').Trim() }

        $displayVersionRaw = Get-TmxItemPropertySafe -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name 'DisplayVersion'
        $displayVersion = if ($displayVersionRaw) { "$displayVersionRaw" } else { $null }

        $build = $null
        try { $build = Get-TmxOsBuild } catch { $build = $null }

        @{ edicao = $edicao; displayVersion = $displayVersion; build = $build }
    } catch {
        Write-TmxLog -Level WARN -Message "Falha ao coletar SO: $($_.Exception.Message)"
        @{ edicao = $null; displayVersion = $null; build = $null }
    }
}

# ---------------------------------------------------------------------------
# HAGS (Hardware-accelerated GPU Scheduling)
# ---------------------------------------------------------------------------

function Get-TmxHagsInfo {
    <#
    .SYNOPSIS
        { suportado, ligado }. 'ligado' vem de Get-TmxHagsAtivo (ja existente
        no Engine/Profile.ps1). 'suportado' e melhor esforco: o valor
        HwSchMode existir (o driver ja expoe a opcao) OU o build do Windows
        ser >= 19041 (2004), quando o recurso passou a existir no shell -
        sem checar a versao do WDDM do driver, que exigiria uma fonte a mais
        (aproximacao documentada).
    #>
    [CmdletBinding()]
    param()
    try {
        $ligado = Get-TmxHagsAtivo
        $existeValor = Test-TmxRegistryValueExists -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name 'HwSchMode'

        $build = 0
        try { $build = Get-TmxOsBuild } catch { $build = 0 }

        @{ suportado = [bool]($existeValor -or ($build -ge 19041)); ligado = $ligado }
    } catch {
        Write-TmxLog -Level WARN -Message "Falha ao avaliar HAGS: $($_.Exception.Message)"
        @{ suportado = $null; ligado = $null }
    }
}

# ---------------------------------------------------------------------------
# Recomendacoes (chaves de i18n, nunca texto)
# ---------------------------------------------------------------------------

function Get-TmxHardwareRecomendacoes {
    <#
    .SYNOPSIS
        Ate 3 recomendacoes, cada uma { tipo, chave, guia }, geradas por
        regra a partir do hardware coletado. 'chave'/'guia' sao chaves de
        i18n (painel.rec.*) - o texto mora no front-end (src/web).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Ram,
        [Parameter(Mandatory)] $Hags,
        [Parameter(Mandatory)] [string] $Chassi
    )

    $recs = New-Object 'System.Collections.Generic.List[object]'

    if ($null -ne $Ram.velocidadeNominal -and $null -ne $Ram.velocidadeConfigurada) {
        if ([int]$Ram.velocidadeConfigurada -lt [int]$Ram.velocidadeNominal) {
            $recs.Add(@{ tipo = 'bios'; chave = 'painel.rec.xmp'; guia = 'painel.rec.xmp.guia' })
        }
    }

    if ($Hags.suportado -eq $true -and $Hags.ligado -ne $true) {
        $recs.Add(@{ tipo = 'app'; chave = 'painel.rec.hags'; guia = 'painel.rec.hags.guia' })
    }

    if ($Chassi -eq 'desktop') {
        $recs.Add(@{ tipo = 'app'; chave = 'painel.rec.powerplan.desktop'; guia = 'painel.rec.powerplan.desktop.guia' })
    } elseif ($Chassi -eq 'notebook') {
        $recs.Add(@{ tipo = 'app'; chave = 'painel.rec.powerplan.notebook'; guia = 'painel.rec.powerplan.notebook.guia' })
    }

    @($recs | Select-Object -First 3)
}

# ---------------------------------------------------------------------------
# Montagem final (system.info)
# ---------------------------------------------------------------------------

function Get-TmxSystemInfo {
    <#
    .SYNOPSIS
        Payload completo de system.info. Nunca lanca: cada secao ja e segura
        por conta propria.
    #>
    [CmdletBinding()]
    param()

    $cpu   = Get-TmxCpuInfo
    $gpu   = Get-TmxGpuInfo
    $ram   = Get-TmxRamInfo
    $disco = Get-TmxDiskInfo
    $os    = Get-TmxOsInfo

    $chassi = 'desktop'
    try {
        $chassisInfo = Get-TmxChassisInfo
        if ($chassisInfo -and $chassisInfo.isLaptop) { $chassi = 'notebook' }
    } catch {
        Write-TmxLog -Level WARN -Message "Falha ao coletar chassi: $($_.Exception.Message)"
    }

    $hags = Get-TmxHagsInfo
    $recomendacoes = @(Get-TmxHardwareRecomendacoes -Ram $ram -Hags $hags -Chassi $chassi)

    @{
        cpu           = $cpu
        gpu           = $gpu
        ram           = $ram
        disco         = $disco
        os            = $os
        chassi        = $chassi
        hagsSuportado = $hags.suportado
        hagsLigado    = $hags.ligado
        recomendacoes = $recomendacoes
    }
}
