# functions/install/Test-TmxPackageManager.ps1
# Detecta winget e choco: disponibilidade, versao e caminho. Nunca lanca -
# a aba Instalar precisa poder desenhar o painel de gerenciadores mesmo
# quando um deles (ou os dois) estao ausentes.

function Test-TmxPackageManager {
    <#
    .SYNOPSIS
        { winget = @{ disponivel; versao; caminho; dica }; choco = @{ disponivel; versao; caminho } }
    .DESCRIPTION
        winget: `winget --version` via Invoke-TmxWingetProcess. Quando
        ausente, tambem confere Get-AppxPackage Microsoft.DesktopAppInstaller
        para diferenciar "nao instalado" de "instalado mas nao respondeu" (o
        pacote da Store pode estar la sem o binario estar no PATH ainda).
        choco: `choco --version` via Invoke-TmxChocoProcess.

        As duas chamadas usam -TimeoutSeconds 60 (nao os 900 do padrao):
        apps.managers e sincrono na ponte, e "--version" nunca deveria
        demorar - se estourar 60s e porque o processo travou de verdade.
    #>
    [CmdletBinding()]
    param()

    $winget = [ordered]@{ disponivel = $false; versao = $null; caminho = $null; dica = $null }
    try {
        $caminhoWinget = Get-TmxCommandPath -Name 'winget'
        if ($caminhoWinget) {
            $r = Invoke-TmxWingetProcess -Arguments @('--version') -TimeoutSeconds 60
            if ($r.codigo -eq 0) {
                $winget.disponivel = $true
                $winget.versao     = "$($r.saida)".Trim()
                $winget.caminho    = $caminhoWinget
            }
        }
    } catch {
        # nunca lanca: painel de gerenciadores tem que aparecer mesmo com erro
    }

    if (-not $winget.disponivel) {
        try {
            $appx = Get-AppxPackage -Name 'Microsoft.DesktopAppInstaller' -ErrorAction SilentlyContinue
            if ($appx) {
                $winget.dica = 'Microsoft.DesktopAppInstaller presente, mas o winget nao respondeu (abra uma vez pelo menu Iniciar ou reinicie a sessao).'
            }
        } catch {
            # dica e so cosmetica
        }
    }

    $choco = [ordered]@{ disponivel = $false; versao = $null; caminho = $null }
    try {
        $caminhoChoco = Get-TmxCommandPath -Name 'choco'
        if ($caminhoChoco) {
            $r2 = Invoke-TmxChocoProcess -Arguments @('--version') -TimeoutSeconds 60
            if ($r2.codigo -eq 0) {
                $choco.disponivel = $true
                $choco.versao     = "$($r2.saida)".Trim()
                $choco.caminho    = $caminhoChoco
            }
        }
    } catch {
        # idem
    }

    [pscustomobject]@{
        winget = [pscustomobject]$winget
        choco  = [pscustomobject]$choco
    }
}
