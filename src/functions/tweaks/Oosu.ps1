# functions/tweaks/Oosu.ps1
# PRI-008: O&O ShutUp10++.
#
# Decisao de projeto: NAO baixamos nem executamos binario de terceiro em nome do
# usuario. O WinUtil busca o executavel e o roda; aqui o botao apenas abre a
# pagina oficial no navegador. Quem decide baixar, verificar e executar e o usuario.
#
# Consequencia: nao ha estado, nao ha registro e nao ha o que reverter ou verificar.

$script:TmxOosuUrl = 'https://www.oo-software.com/en/shutup10'

function Test-TmxOosu {
    [CmdletBinding()]
    param($Tweak, $Profile)
    [pscustomobject]@{
        aplicado = $null
        atual    = $null
        esperado = $null
        detalhe  = 'abrir uma pagina nao muda o sistema: nao ha estado para verificar'
    }
}

function Set-TmxOosu {
    [CmdletBinding()]
    param($Tweak, $Profile, $Parametros)

    try {
        $url = Start-TmxUrl -Url $script:TmxOosuUrl
        [pscustomobject]@{ ok = $true; detalhe = "pagina oficial aberta: $url" }
    } catch {
        [pscustomobject]@{ ok = $false; detalhe = $_.Exception.Message }
    }
}

function Undo-TmxOosu {
    [CmdletBinding()]
    param($Estado)
    'nada a reverter: o TweakMaxing apenas abriu a pagina oficial, sem alterar o sistema'
}
