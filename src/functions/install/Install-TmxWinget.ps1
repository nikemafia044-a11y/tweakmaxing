# functions/install/Install-TmxWinget.ps1
# Reparo/instalacao do winget via modulo Microsoft.WinGet.Client (porta de
# reference/winutil/functions/private/Install-WinUtilWinget.ps1).

function Install-TmxWinget {
    <#
    .SYNOPSIS
        Instala (ou repara, com -Force) o winget.
    .PARAMETER Force
        Roda o reparo mesmo se o winget ja parece disponivel - e o caminho do
        botao "Reparar winget" na UI, onde o usuario ja sabe que algo esta
        quebrado apesar do winget "existir".
    .OUTPUTS
        [pscustomobject] @{ ok; detalhe }. Nunca lanca.
    #>
    [CmdletBinding()]
    param([switch] $Force)

    try {
        $antes = Test-TmxPackageManager
        if (-not $Force -and $antes.winget.disponivel) {
            return [pscustomobject]@{ ok = $true; detalhe = 'winget ja esta disponivel' }
        }

        $instalou = Install-TmxWingetClientModule
        $depois   = Test-TmxPackageManager

        if ($depois.winget.disponivel) {
            $motivo = if ($Force) { 'winget reparado via Microsoft.WinGet.Client' } else { 'winget instalado via Microsoft.WinGet.Client' }
            return [pscustomobject]@{ ok = $true; detalhe = $motivo }
        }

        $detalhe = if ($instalou) {
            'Microsoft.WinGet.Client rodou, mas o winget continua indisponivel'
        } else {
            'nao foi possivel instalar/reparar o modulo Microsoft.WinGet.Client'
        }
        [pscustomobject]@{ ok = $false; detalhe = $detalhe }
    } catch {
        [pscustomobject]@{ ok = $false; detalhe = $_.Exception.Message }
    }
}
