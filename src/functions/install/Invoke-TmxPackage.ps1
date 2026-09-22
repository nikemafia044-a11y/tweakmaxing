# functions/install/Invoke-TmxPackage.ps1
# Instala/desinstala/atualiza uma lista de pacotes e devolve um resultado por
# pacote. Mapa de codigos de saida do winget replicado de
# reference/winutil/functions/private/Install-WinUtilProgramWinget.ps1 (e o
# de choco, de Install-WinUtilProgramChoco.ps1).

function Invoke-TmxPackage {
    <#
    .SYNOPSIS
        Roda winget (e, em -Manager auto, choco como reserva) para uma lista
        de programas.
    .PARAMETER Programs
        Ids literais do gerenciador escolhido - exceto com -Catalog, onde sao
        ids do catalogo do TweakMaxing (resolvidos para os ids de winget/choco
        antes de rodar). "all" com -Action Upgrade atualiza tudo.
    .PARAMETER Manager
        winget | choco | auto. Em auto, winget roda primeiro; so cai para
        choco quando winget estiver ausente OU o resultado for falha com um
        codigo nao mapeado, e so quando o pacote tiver um id de choco (via
        -Catalog, ou o proprio id literal quando -Catalog nao foi passado).
    .PARAMETER Catalog
        Ver -Programs.
    .OUTPUTS
        Um [pscustomobject] por pacote: { pacote, gerenciador, acao, codigo, resultado, detalhe }.
        resultado e 'ok' | 'pulado' | 'falha'.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateSet('Install', 'Uninstall', 'Upgrade')] [string] $Action,
        [Parameter(Mandatory)] [string[]] $Programs,
        [ValidateSet('winget', 'choco', 'auto')] [string] $Manager = 'auto',
        [switch] $Catalog
    )

    # APPINSTALLER_CLI_ERROR_ADMIN_CONTEXT_ACTION_PROHIBITED: o winget recusa
    # agir sobre um pacote instalado no escopo do usuario enquanto roda
    # elevado - nao e falha, e um "pulado" explicado.
    $adminContextProhibited = -1978335107

    $wingetPulado = @{
        -1978335135 = 'ja instalado'
        -1978335189 = 'sem atualizacao disponivel'
    }
    $wingetRebootOk = @{
        3010        = 'instalado; reinicio necessario para concluir'
        1641        = 'instalado; o instalador iniciou o reinicio'
        -1978334967 = 'instalado; reinicio necessario para concluir'
        -1978334965 = 'instalado; o instalador iniciou o reinicio'
    }
    $chocoRebootOk = @{
        1641 = 'instalado; o instalador iniciou o reinicio'
        3010 = 'instalado; reinicio necessario para concluir'
    }

    $catalogo = $null
    if ($Catalog) { $catalogo = Get-TmxAppCatalog }

    $verbo = switch ($Action) {
        'Install'   { 'install' }
        'Uninstall' { 'uninstall' }
        'Upgrade'   { 'upgrade' }
    }

    $emitirProgresso = [bool](Get-Command -Name Send-TmxJobProgress -ErrorAction SilentlyContinue) `
        -and ($null -ne $sync) -and ($null -ne $sync.activeJob)

    $programasValidos = @($Programs | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $total   = $programasValidos.Count
    $indice  = 0
    $resultados = New-Object System.Collections.Generic.List[object]

    foreach ($programa in $programasValidos) {
        $indice++

        $upgradeAll = ($Action -eq 'Upgrade' -and $programa -eq 'all')
        $wingetId = $programa
        $chocoId  = $programa

        if ($Catalog -and -not $upgradeAll) {
            $entrada = @($catalogo | Where-Object { "$($_.id)" -ieq $programa }) | Select-Object -First 1
            if (-not $entrada) { throw "app desconhecido no catalogo: $programa" }
            $wingetId = "$($entrada.winget)"
            $chocoId  = "$($entrada.choco)"
        }

        if ($emitirProgresso) {
            $pct = if ($total -gt 0) { [int]((($indice - 1) / $total) * 100) } else { 0 }
            Send-TmxJobProgress -Pct $pct -Status "$Action $programa ($indice/$total)"
        }

        $gerenciadorUsado = $null
        $codigo           = $null
        $resultadoTxt     = $null
        $detalhe          = $null

        if ($Manager -ne 'choco') {
            $caminhoWinget = Get-TmxCommandPath -Name 'winget'
            $gerenciadorUsado = 'winget'

            if (-not $caminhoWinget) {
                $codigo       = -1
                $resultadoTxt = 'falha'
                $detalhe      = 'winget nao esta disponivel'
            } else {
                $origem   = 'winget'
                $idEfetivo = $wingetId
                if (-not $upgradeAll -and "$idEfetivo".StartsWith('msstore:', [System.StringComparison]::OrdinalIgnoreCase)) {
                    $origem    = 'msstore'
                    $idEfetivo = $idEfetivo.Substring('msstore:'.Length)
                }

                $argumentos = switch ($Action) {
                    'Uninstall' { @('uninstall', '--id', $idEfetivo, '--source', $origem, '--silent') }
                    'Upgrade' {
                        if ($upgradeAll) {
                            @('upgrade', '--all', '--accept-package-agreements', '--accept-source-agreements', '--include-unknown', '--silent')
                        } else {
                            @('upgrade', '--id', $idEfetivo, '--accept-package-agreements', '--accept-source-agreements', '--source', $origem, '--include-unknown', '--silent')
                        }
                    }
                    default { @('install', '--id', $idEfetivo, '--accept-package-agreements', '--accept-source-agreements', '--source', $origem, '--silent') }
                }

                $proc   = Invoke-TmxWingetProcess -Arguments $argumentos
                $codigo = $proc.codigo

                if ($codigo -eq 0) {
                    $resultadoTxt = 'ok'; $detalhe = 'codigo de saida 0'
                } elseif ($wingetRebootOk.ContainsKey($codigo)) {
                    $resultadoTxt = 'ok'; $detalhe = $wingetRebootOk[$codigo]
                } elseif ($wingetPulado.ContainsKey($codigo)) {
                    $resultadoTxt = 'pulado'; $detalhe = $wingetPulado[$codigo]
                } elseif ($codigo -eq $adminContextProhibited) {
                    $resultadoTxt = 'pulado'
                    $detalhe = switch ($Action) {
                        'Install'   { 'ja instalado para o usuario atual; o TweakMaxing elevado nao pode altera-lo' }
                        'Upgrade'   { 'nao atualizado; instalado para o usuario atual e o TweakMaxing elevado nao pode modifica-lo' }
                        'Uninstall' { 'continua instalado para o usuario atual; o TweakMaxing elevado nao pode desinstala-lo' }
                    }
                } else {
                    $resultadoTxt = 'falha'
                    $detalhe = "winget devolveu 0x{0:X8}. Veja https://learn.microsoft.com/windows/package-manager/winget/returnCodes" -f $codigo
                }
            }
        }

        $deveTentarChoco = $false
        if ($Manager -eq 'choco') {
            $deveTentarChoco = $true
        } elseif ($Manager -eq 'auto' -and $resultadoTxt -eq 'falha' -and -not [string]::IsNullOrWhiteSpace($chocoId)) {
            $deveTentarChoco = $true
        }

        if ($deveTentarChoco) {
            $caminhoChoco = Get-TmxCommandPath -Name 'choco'
            $gerenciadorUsado = 'choco'

            if (-not $caminhoChoco) {
                $codigo       = -1
                $resultadoTxt = 'falha'
                $detalhe      = 'choco ausente: nao ha como instalar/atualizar/desinstalar por ele'
            } else {
                $idChocoEfetivo = if ($upgradeAll) { 'all' } else { $chocoId }
                $argsChoco = @($verbo, $idChocoEfetivo, '-y')
                $procC  = Invoke-TmxChocoProcess -Arguments $argsChoco
                $codigo = $procC.codigo

                if ($codigo -eq 0) {
                    $resultadoTxt = 'ok'; $detalhe = 'codigo de saida 0'
                } elseif ($chocoRebootOk.ContainsKey($codigo)) {
                    $resultadoTxt = 'ok'; $detalhe = $chocoRebootOk[$codigo]
                } else {
                    $resultadoTxt = 'falha'; $detalhe = "choco devolveu codigo $codigo"
                }
            }
        }

        $resultados.Add([pscustomobject]@{
            pacote      = $programa
            gerenciador = $gerenciadorUsado
            acao        = $Action
            codigo      = $codigo
            resultado   = $resultadoTxt
            detalhe     = $detalhe
        })
    }

    if ($emitirProgresso) { Send-TmxJobProgress -Pct 100 -Status "$Action concluido" }

    # A virgula evita que um resultado de 1 pacote so seja desenrolado no
    # pipeline (PS enumera array na saida; com 1 item vira objeto solto e
    # $r.Count fica $null do lado de quem chama).
    ,$resultados.ToArray()
}
