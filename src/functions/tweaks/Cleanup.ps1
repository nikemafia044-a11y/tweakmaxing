# functions/tweaks/Cleanup.ps1
# MAN-003 e MAN-004: limpeza de disco e arquivos temporarios.
#
# Sao os dois unicos tweaks com reversivel = 'nenhuma'. Arquivo apagado nao volta,
# e nos dizemos isso em vez de fingir que ha undo: Undo-* lanca com a mensagem
# 'acao irreversivel' e Test-* devolve aplicado = $null (nao da para verificar o
# que nao deixou rastro).
#
# O registro de estado e criado mesmo assim: ele e a trilha de auditoria do que
# foi executado e quando.

function Test-TmxDiskCleanup {
    [CmdletBinding()]
    param($Tweak, $Profile)
    [pscustomobject]@{
        aplicado = $null
        atual    = $null
        esperado = $null
        detalhe  = 'limpeza de disco nao deixa estado verificavel: acao irreversivel, sem aplicado/nao aplicado'
    }
}

function Set-TmxDiskCleanup {
    [CmdletBinding()]
    param($Tweak, $Profile, $Parametros)

    $rec = New-TmxCmdletRecord -TweakId "$($Tweak.id)" -Funcao 'Set-TmxDiskCleanup' -Alvo 'limpeza de disco em C:' `
            -Estado @{ irreversivel = $true; executadoEm = (Get-Date).ToString('o') } `
            -ValorAnterior $null -ValorNovo 'limpeza executada'

    try {
        $r1 = Invoke-TmxCleanmgr @('/d', 'C:', '/VERYLOWDISK')
        if ($r1.codigo -ne 0) { throw "cleanmgr falhou ($($r1.codigo)): $($r1.saida)" }

        $r2 = Invoke-TmxDism @('/online', '/Cleanup-Image', '/StartComponentCleanup', '/ResetBase')
        if ($r2.codigo -ne 0) { throw "DISM /StartComponentCleanup falhou ($($r2.codigo)): $($r2.saida)" }

        Complete-TmxStateRecord -Record $rec -Ok $true | Out-Null
        [pscustomobject]@{ ok = $true; detalhe = 'limpeza de disco e do repositorio de componentes concluida'; registro = $rec }
    } catch {
        Complete-TmxStateRecord -Record $rec -Ok $false -Erro $_.Exception.Message | Out-Null
        [pscustomobject]@{ ok = $false; detalhe = $_.Exception.Message; registro = $rec }
    }
}

function Undo-TmxDiskCleanup {
    [CmdletBinding()]
    param($Estado)
    throw 'acao irreversivel: a limpeza de disco apagou arquivos e versoes antigas de componentes, e nao ha backup para restaurar'
}

function Test-TmxTempFiles {
    [CmdletBinding()]
    param($Tweak, $Profile)
    [pscustomobject]@{
        aplicado = $null
        atual    = $null
        esperado = $null
        detalhe  = 'as pastas TEMP voltam a encher sozinhas: nao ha estado verificavel, e a acao e irreversivel'
    }
}

function Set-TmxTempFiles {
    [CmdletBinding()]
    param($Tweak, $Profile, $Parametros)

    $pastas = @(
        (Join-Path $env:Temp '*'),
        (Join-Path $env:SystemRoot 'Temp\*')
    )

    $rec = New-TmxCmdletRecord -TweakId "$($Tweak.id)" -Funcao 'Set-TmxTempFiles' -Alvo 'pastas TEMP' `
            -Estado @{ irreversivel = $true; pastas = $pastas; executadoEm = (Get-Date).ToString('o') } `
            -ValorAnterior $null -ValorNovo 'pastas TEMP esvaziadas'

    try {
        foreach ($p in $pastas) {
            # -Silencioso de proposito: sempre ha arquivo em uso em TEMP, inclusive
            # os desta propria execucao. Isso nao e falha da acao.
            Remove-TmxItemPath -Path $p -Recursivo -Silencioso
        }
        Complete-TmxStateRecord -Record $rec -Ok $true | Out-Null
        [pscustomobject]@{ ok = $true; detalhe = 'pastas TEMP esvaziadas (arquivos em uso foram ignorados)'; registro = $rec }
    } catch {
        Complete-TmxStateRecord -Record $rec -Ok $false -Erro $_.Exception.Message | Out-Null
        [pscustomobject]@{ ok = $false; detalhe = $_.Exception.Message; registro = $rec }
    }
}

function Undo-TmxTempFiles {
    [CmdletBinding()]
    param($Estado)
    throw 'acao irreversivel: os arquivos temporarios foram apagados e nao ha backup para restaurar'
}
