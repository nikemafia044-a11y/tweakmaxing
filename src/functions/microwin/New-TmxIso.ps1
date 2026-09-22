# functions/microwin/New-TmxIso.ps1
# Montagem do .iso final com o oscdimg (Windows ADK - Deployment Tools).
#
# A ISO precisa continuar inicializavel nos dois mundos: BIOS legado pelo
# boot\etfsboot.com e UEFI pelo efi\microsoft\boot\efisys.bin. E o que o
# -bootdata com os dois blocos (p0 e pEF) faz. Sem ele a ISO ate se gera, mas
# nenhuma maquina da boot nela.

function New-TmxIsoArgumentList {
    <#
    .SYNOPSIS
        A linha de argumentos do oscdimg, em array.
    .OUTPUTS
        [string[]]
    .NOTES
        Os caminhos vao SEM aspas: com array de argumentos quem cuida das
        aspas e o proprio PowerShell, e acrescentar aspas a mao faria o
        oscdimg receber um caminho comecando por aspas literais.

        A saida e o array puro, SEM o ', $lista' que preserva arrays de um
        elemento so: o chamador escreve '@(New-TmxIsoArgumentList ...)', e com
        a virgula esse @() devolveria um array de UM elemento contendo o array.
        Ao entrar em '[string[]] $Arguments' isso virava um unico argumento
        gigante com tudo junto - o oscdimg receberia a linha inteira como se
        fosse um caminho.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Origem,
        [Parameter(Mandatory)] [string] $Destino
    )

    $etfsboot = Join-Path $Origem 'boot\etfsboot.com'
    $efisys   = Join-Path $Origem 'efi\microsoft\boot\efisys.bin'
    $bootdata = '2#p0,e,b{0}#pEF,e,b{1}' -f $etfsboot, $efisys

    @('-m', '-o', '-u2', '-udfver102', "-bootdata:$bootdata", $Origem, $Destino)
}

function New-TmxIso {
    <#
    .SYNOPSIS
        Gera o .iso final a partir da pasta de conteudo.
    .OUTPUTS
        [pscustomobject] @{ ok; mensagem; arquivo; tamanhoGB; codigo; argumentos }
    .NOTES
        Nao lanca: o chamador vira isso num passo do relatorio.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Origem,
        [Parameter(Mandatory)] [string] $Destino
    )

    $argumentos = @(New-TmxIsoArgumentList -Origem $Origem -Destino $Destino)

    $resultado = $null
    try {
        $resultado = Invoke-TmxOscdimg -Arguments $argumentos
    } catch {
        return [pscustomobject]@{
            ok = $false; mensagem = "$($_.Exception.Message)"; arquivo = $null
            tamanhoGB = 0.0; codigo = -1; argumentos = $argumentos
        }
    }

    $codigo = [int]$resultado.codigo
    if ($codigo -ne 0) {
        return [pscustomobject]@{
            ok = $false; mensagem = "oscdimg terminou com codigo $codigo"; arquivo = $null
            tamanhoGB = 0.0; codigo = $codigo; argumentos = $argumentos
        }
    }

    if (-not (Test-Path -LiteralPath $Destino)) {
        return [pscustomobject]@{
            ok = $false; mensagem = 'o oscdimg terminou sem erro mas o arquivo nao existe'; arquivo = $null
            tamanhoGB = 0.0; codigo = $codigo; argumentos = $argumentos
        }
    }

    [pscustomobject]@{
        ok         = $true
        mensagem   = 'ISO gerada'
        arquivo    = "$Destino"
        tamanhoGB  = (Get-TmxFileSizeGB -Path $Destino)
        codigo     = $codigo
        argumentos = $argumentos
    }
}
