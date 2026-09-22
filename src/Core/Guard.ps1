# Core/Guard.ps1
# Guardas de execucao: elevacao, versao do SO, espaco em disco, reboot pendente,
# tipo de chassi (notebook) e deteccao de VM.
#
# Assert-TmxGuards nao encerra o processo - retorna um objeto com
# bloqueios/avisos e o orquestrador decide. Nada aqui escreve no host.

function Test-TmxElevation {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-TmxElevation {
    <#
    .SYNOPSIS
        Relanca o script atual com privilegios elevados, preservando parametros.
    .OUTPUTS
        $true se um novo processo foi disparado (o chamador deve encerrar).
        $false se ja estava elevado.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $ScriptPath,
        [hashtable] $BoundParameters = @{}
    )

    if (Test-TmxElevation) { return $false }

    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $ScriptPath))
    foreach ($kv in $BoundParameters.GetEnumerator()) {
        $v = $kv.Value
        if ($v -is [switch]) {
            if ($v.IsPresent) { $argList += ('-{0}' -f $kv.Key) }
        } elseif ($v -is [bool]) {
            $argList += ('-{0}:${1}' -f $kv.Key, $v.ToString().ToLower())
        } else {
            $argList += ('-{0}' -f $kv.Key)
            $argList += ('"{0}"' -f $v)
        }
    }

    $hostExe = (Get-Process -Id $PID).Path
    Write-TmxLog -Level INFO -Message 'Relancando com privilegios elevados' -Data @{ exe = $hostExe; args = ($argList -join ' ') }
    Start-Process -FilePath $hostExe -Verb RunAs -ArgumentList $argList
    $true
}

function Get-TmxOsBuild {
    try {
        [int](Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name CurrentBuildNumber -ErrorAction Stop).CurrentBuildNumber
    } catch {
        [Environment]::OSVersion.Version.Build
    }
}

function Test-TmxPendingReboot {
    <#
    .SYNOPSIS
        Verifica os marcadores classicos de reinicializacao pendente.
    #>
    # bloqueantes: sinais fortes (servicing / Windows Update).
    # informativas: PendingFileRenameOperations e ruidoso (qualquer instalador
    # recente deixa rastro) - vira aviso, nao bloqueio.
    $bloqueantes  = @()
    $informativas = @()

    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') {
        $bloqueantes += 'Component Based Servicing'
    }
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') {
        $bloqueantes += 'Windows Update'
    }
    $sm = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
    if ($sm -and $sm.PendingFileRenameOperations) {
        $informativas += 'PendingFileRenameOperations'
    }

    [pscustomobject]@{
        pending      = (($bloqueantes.Count + $informativas.Count) -gt 0)
        razoes       = @($bloqueantes + $informativas)
        bloqueantes  = @($bloqueantes)
        informativas = @($informativas)
    }
}

function Get-TmxChassisInfo {
    # Tipos de chassi que indicam portatil (SMBIOS System Enclosure).
    $laptopTypes = @(8, 9, 10, 11, 12, 14, 18, 21, 30, 31, 32)
    try {
        $enc   = Get-CimInstance -ClassName Win32_SystemEnclosure -ErrorAction Stop
        $types = @($enc | ForEach-Object { $_.ChassisTypes } | ForEach-Object { [int]$_ })
        $isLaptop = [bool]($types | Where-Object { $laptopTypes -contains $_ } | Select-Object -First 1)
        [pscustomobject]@{ chassisTypes = $types; isLaptop = $isLaptop }
    } catch {
        [pscustomobject]@{ chassisTypes = @(); isLaptop = $false }
    }
}

function Get-TmxVirtualizationInfo {
    $marcadores = 'VirtualBox|VMware|KVM|QEMU|Xen|Virtual Machine|Hyper-V|Parallels|Bochs|innotek'
    try {
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        $isVM = ("$($cs.Model)" -match $marcadores) -or ("$($cs.Manufacturer)" -match $marcadores)
        [pscustomobject]@{ isVM = [bool]$isVM; modelo = $cs.Model; fabricante = $cs.Manufacturer }
    } catch {
        [pscustomobject]@{ isVM = $false; modelo = $null; fabricante = $null }
    }
}

function Assert-TmxGuards {
    <#
    .SYNOPSIS
        Avalia todas as guardas e retorna { ok, bloqueios[], avisos[], contexto }.
    .PARAMETER AllowUnelevated
        Trata falta de elevacao como aviso (util para -DryRun / -ProfileOnly).
    #>
    [CmdletBinding()]
    param(
        [int]    $MinBuild  = 18363,
        [double] $MinFreeGB = 2,
        [switch] $AllowUnelevated
    )

    $bloqueios = New-Object 'System.Collections.Generic.List[string]'
    $avisos    = New-Object 'System.Collections.Generic.List[string]'

    # Elevacao
    $elevado = Test-TmxElevation
    if (-not $elevado) {
        if ($AllowUnelevated) { $avisos.Add('Executando sem privilegios de administrador (modo limitado).') }
        else                  { $bloqueios.Add('E necessario executar como Administrador.') }
    }

    # Versao do Windows
    $build = Get-TmxOsBuild
    if ($build -lt $MinBuild) {
        $bloqueios.Add("Build do Windows ($build) abaixo do minimo suportado ($MinBuild).")
    }

    # Espaco em disco
    $sysDrive = $env:SystemDrive
    $freeGB   = $null
    try {
        $disk   = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$sysDrive'" -ErrorAction Stop
        $freeGB = [math]::Round($disk.FreeSpace / 1GB, 1)
        if ($freeGB -lt $MinFreeGB) {
            $bloqueios.Add("Espaco livre em $sysDrive ($freeGB GB) abaixo do minimo ($MinFreeGB GB).")
        }
    } catch {
        $avisos.Add('Nao foi possivel medir o espaco livre no disco de sistema.')
    }

    # Reboot pendente
    $reboot = Test-TmxPendingReboot
    if ($reboot.bloqueantes.Count -gt 0) {
        $bloqueios.Add("Ha uma reinicializacao pendente ($($reboot.bloqueantes -join ', ')). Reinicie antes de continuar.")
    } elseif ($reboot.informativas.Count -gt 0) {
        $avisos.Add("Ha operacoes de arquivo pendentes para o proximo reboot ($($reboot.informativas -join ', ')). Recomenda-se reiniciar antes.")
    }

    # Chassi e virtualizacao
    $chassis = Get-TmxChassisInfo
    $virt    = Get-TmxVirtualizationInfo
    if ($virt.isVM) {
        $avisos.Add('Maquina virtual detectada - varios tweaks nao se aplicam e os ganhos nao sao representativos.')
    }
    if ($chassis.isLaptop) {
        $avisos.Add('Notebook detectado - tweaks que prejudicam gestao termica/bateria serao bloqueados.')
    }

    $result = [pscustomobject]@{
        ok        = ($bloqueios.Count -eq 0)
        # .ToArray(): @() sobre List generica vazia falha no PS 5.1
        bloqueios = $bloqueios.ToArray()
        avisos    = $avisos.ToArray()
        contexto  = [pscustomobject]@{
            elevado     = $elevado
            build       = $build
            isLaptop    = $chassis.isLaptop
            isVM        = $virt.isVM
            systemDrive = $sysDrive
            freeGB      = $freeGB
        }
    }

    Write-TmxLog -Level INFO -Message 'Guardas avaliadas' -Data @{ ok = $result.ok; bloqueios = $result.bloqueios; avisos = $result.avisos }
    $result
}
