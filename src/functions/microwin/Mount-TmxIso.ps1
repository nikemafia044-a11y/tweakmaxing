# functions/microwin/Mount-TmxIso.ps1
# Montagem e desmontagem da ISO de origem, sempre somente-leitura.
#
# A ISO que o usuario escolheu NUNCA e alterada: montar, ler/copiar,
# desmontar. Tudo que o MicroWin modifica vive na copia dentro da pasta de
# trabalho.

function Mount-TmxIso {
    <#
    .SYNOPSIS
        Monta um .iso e devolve a raiz do volume (ex.: 'F:\').
    .OUTPUTS
        [pscustomobject] @{ ok; mensagem; letra; raiz }
    .NOTES
        Nao lanca: o chamador transforma ok=$false num passo com detalhe. Em
        caso de falha depois da montagem a ISO e desmontada aqui mesmo, para
        nao deixar um volume pendurado na maquina.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $IsoPath)

    if (-not (Test-Path -LiteralPath $IsoPath)) {
        return [pscustomobject]@{ ok = $false; mensagem = "ISO nao encontrada: $IsoPath"; letra = $null; raiz = $null }
    }

    $letra = $null
    try {
        $letra = Mount-TmxDiskImageWrapper -Path $IsoPath
    } catch {
        return [pscustomobject]@{ ok = $false; mensagem = "nao foi possivel montar a ISO: $($_.Exception.Message)"; letra = $null; raiz = $null }
    }

    if (-not $letra) {
        Dismount-TmxDiskImageWrapper -Path $IsoPath | Out-Null
        return [pscustomobject]@{ ok = $false; mensagem = 'a ISO montou mas nenhum volume apareceu'; letra = $null; raiz = $null }
    }

    [pscustomobject]@{
        ok       = $true
        mensagem = "ISO montada em ${letra}:"
        letra    = "$letra"
        raiz     = "${letra}:\"
    }
}

function Dismount-TmxIso {
    <#
    .SYNOPSIS
        Desmonta a ISO de origem. Nunca lanca.
    .OUTPUTS
        $true quando o Dismount-DiskImage nao reclamou.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $IsoPath)

    Dismount-TmxDiskImageWrapper -Path $IsoPath
}
