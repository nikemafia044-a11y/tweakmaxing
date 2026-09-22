# functions/install/Install-TmxChoco.ps1
# Instalacao do Chocolatey via script oficial (porta de
# reference/winutil/functions/private/Install-WinUtilChoco.ps1). So deve ser
# chamada depois que a UI mostrou o modal de consentimento explicando o
# download - Invoke-TmxChocoBootstrap nao pergunta nada sozinho.

function Install-TmxChoco {
    <#
    .SYNOPSIS
        Instala o Chocolatey se ainda nao estiver presente.
    .OUTPUTS
        [pscustomobject] @{ ok; detalhe }. Nunca lanca.
    #>
    [CmdletBinding()]
    param()

    try {
        $antes = Test-TmxPackageManager
        if ($antes.choco.disponivel) {
            return [pscustomobject]@{ ok = $true; detalhe = 'Chocolatey ja esta disponivel' }
        }

        $r = Invoke-TmxChocoBootstrap
        [pscustomobject]@{ ok = [bool]$r.ok; detalhe = "$($r.detalhe)" }
    } catch {
        [pscustomobject]@{ ok = $false; detalhe = $_.Exception.Message }
    }
}
