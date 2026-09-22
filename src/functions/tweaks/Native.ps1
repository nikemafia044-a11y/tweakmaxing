# functions/tweaks/Native.ps1
# Tipos nativos (P/Invoke) para aplicar configuracoes imediatamente, sem logoff.
# Porta reduzida de CS2Tuner Profile/Native.ps1 (so o que Tweaks/InputStack.ps1
# usa: SystemParametersInfo para mouse, SendMessageTimeout para WM_SETTINGCHANGE).
# Namespace renomeado de CS2Tuner.Native para TweakMaxing.Native.
#
# Initialize-TmxNativeTypes e idempotente (Add-Type roda uma vez por sessao) e
# nunca lanca: falha de compilacao volta $false, quem chama decide o que fazer.

$script:TmxNativeSource = @'
using System;
using System.Runtime.InteropServices;

namespace TweakMaxing
{
    public static class Native
    {
        public const uint SPI_SETMOUSE        = 0x0004;
        public const uint SPI_SETMOUSESPEED   = 0x0071;
        public const uint SPIF_UPDATEINIFILE  = 0x0001;
        public const uint SPIF_SENDCHANGE     = 0x0002;
        public const uint WM_SETTINGCHANGE    = 0x001A;
        public const uint SMTO_ABORTIFHUNG    = 0x0002;
        public static readonly IntPtr HWND_BROADCAST = new IntPtr(0xffff);

        [DllImport("user32.dll", SetLastError = true, EntryPoint = "SystemParametersInfoW")]
        public static extern bool SystemParametersInfoArray(uint uiAction, uint uiParam, int[] pvParam, uint fWinIni);

        [DllImport("user32.dll", SetLastError = true, EntryPoint = "SystemParametersInfoW")]
        public static extern bool SystemParametersInfoPtr(uint uiAction, uint uiParam, IntPtr pvParam, uint fWinIni);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
    }
}
'@

function Initialize-TmxNativeTypes {
    <#
    .SYNOPSIS
        Compila os tipos nativos (uma vez por sessao). Nunca lanca.
    .OUTPUTS
        $true se os tipos estao disponiveis (ja compilados ou compilados agora),
        $false se a compilacao falhou.
    #>
    [CmdletBinding()]
    param()
    if (([System.Management.Automation.PSTypeName]'TweakMaxing.Native').Type) { return $true }
    try {
        Add-Type -TypeDefinition $script:TmxNativeSource -ErrorAction Stop
        $true
    } catch {
        Write-TmxLog -Level WARN -Message "Falha ao compilar tipos nativos: $($_.Exception.Message)"
        $false
    }
}

function Update-TmxMouseSettings {
    <#
    .SYNOPSIS
        Le HKCU\Control Panel\Mouse e aplica via SystemParametersInfo
        (SPI_SETMOUSE / SPI_SETMOUSESPEED), para efeito imediato sem logoff.
    #>
    [CmdletBinding()]
    param()
    if (-not (Initialize-TmxNativeTypes)) { return $false }

    try {
        $mp = Get-ItemProperty -LiteralPath 'HKCU:\Control Panel\Mouse' -ErrorAction Stop
    } catch {
        Write-TmxLog -Level WARN -Message "Nao foi possivel ler HKCU:\Control Panel\Mouse: $($_.Exception.Message)"
        return $false
    }

    $flags = [TweakMaxing.Native]::SPIF_UPDATEINIFILE -bor [TweakMaxing.Native]::SPIF_SENDCHANGE

    $params = [int[]]@([int]$mp.MouseThreshold1, [int]$mp.MouseThreshold2, [int]$mp.MouseSpeed)
    $ok1 = [TweakMaxing.Native]::SystemParametersInfoArray([TweakMaxing.Native]::SPI_SETMOUSE, 0, $params, $flags)

    $speed = [IntPtr]::new([int]$mp.MouseSensitivity)
    $ok2 = [TweakMaxing.Native]::SystemParametersInfoPtr([TweakMaxing.Native]::SPI_SETMOUSESPEED, 0, $speed, $flags)

    Write-TmxLog -Level INFO -Message 'Configuracoes de mouse aplicadas em tempo real' -Data @{ setmouse = $ok1; setspeed = $ok2 }
    ($ok1 -and $ok2)
}

function Send-TmxSettingChange {
    <#
    .SYNOPSIS
        Broadcast WM_SETTINGCHANGE para o shell reler configuracoes
        (tema, efeitos visuais) sem precisar de logoff.
    #>
    [CmdletBinding()]
    param([string] $Area = $null)
    if (-not (Initialize-TmxNativeTypes)) { return $false }

    $result = [UIntPtr]::Zero
    [TweakMaxing.Native]::SendMessageTimeout([TweakMaxing.Native]::HWND_BROADCAST, [TweakMaxing.Native]::WM_SETTINGCHANGE,
        [UIntPtr]::Zero, $Area, [TweakMaxing.Native]::SMTO_ABORTIFHUNG, 2000, [ref]$result) | Out-Null
    foreach ($a in 'ImmersiveColorSet', 'WindowMetrics', 'Environment') {
        [TweakMaxing.Native]::SendMessageTimeout([TweakMaxing.Native]::HWND_BROADCAST, [TweakMaxing.Native]::WM_SETTINGCHANGE,
            [UIntPtr]::Zero, $a, [TweakMaxing.Native]::SMTO_ABORTIFHUNG, 2000, [ref]$result) | Out-Null
    }
    $true
}
