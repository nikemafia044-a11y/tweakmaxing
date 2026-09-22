# functions/tweaks/SvcHostSplit.ps1
# SIS-001 (FOLCLORE): SvcHostSplitThresholdInKB. Elevar o limiar ate a memoria
# instalada faz o Windows agrupar servicos em menos processos svchost.exe.
#
# Continua no catalogo porque o WinUtil o aplica, mas so roda se o usuario marcar.
# A escrita passa por Set-TmxRegistry, entao quem reverte e o Undo-TmxRegistryRecord
# do Core: esta funcao devolve o registro dele, sem criar um registro 'cmdlet'.

$script:TmxSvcHostPath = 'HKLM:\SYSTEM\CurrentControlSet\Control'
$script:TmxSvcHostName = 'SvcHostSplitThresholdInKB'

function Test-TmxSvcHostSplit {
    [CmdletBinding()]
    param($Tweak, $Profile)

    $atual = Get-TmxRegistryValue -Path $script:TmxSvcHostPath -Name $script:TmxSvcHostName
    $esperado = $null
    try { $esperado = Get-TmxPhysicalMemoryKB } catch { $esperado = $null }

    if ($null -eq $atual -or $null -eq $esperado) {
        return [pscustomobject]@{ aplicado = $null; atual = $atual; esperado = $esperado; detalhe = 'memoria ou valor atual indisponivel' }
    }
    [pscustomobject]@{
        aplicado = ([int64]$atual -ge [int64]$esperado)
        atual    = [int64]$atual
        esperado = [int64]$esperado
        detalhe  = "$($script:TmxSvcHostName) = $atual (memoria instalada: $esperado KB)"
    }
}

function Set-TmxSvcHostSplit {
    [CmdletBinding()]
    param($Tweak, $Profile, $Parametros)

    try {
        $kb = Get-TmxPhysicalMemoryKB
    } catch {
        return [pscustomobject]@{ ok = $false; detalhe = "memoria fisica nao pode ser lida: $($_.Exception.Message)" }
    }
    if ($null -eq $kb -or $kb -le 0) {
        return [pscustomobject]@{ ok = $false; detalhe = 'memoria fisica reportada como zero' }
    }

    # DWord e int32 com sinal: acima de 2 TB de RAM o valor nao cabe. Trava em vez
    # de gravar um numero negativo.
    if ($kb -gt [int]::MaxValue) {
        return [pscustomobject]@{ ok = $false; detalhe = "memoria ($kb KB) excede o limite de um DWord" }
    }

    $rec = Set-TmxRegistry -Path $script:TmxSvcHostPath -Name $script:TmxSvcHostName `
            -Value ([int]$kb) -Type 'DWord' -TweakId "$($Tweak.id)" -PassThru
    $ok = ("$($rec.status)" -eq 'aplicado')
    [pscustomobject]@{
        ok      = $ok
        detalhe = $(if ($ok) { "$($script:TmxSvcHostName) = $kb" } else { "$($rec.erro)" })
        registro = $rec
    }
}

function Undo-TmxSvcHostSplit {
    [CmdletBinding()]
    param($Estado)

    # Caminho normal: o registro 'registry' criado por Set-TmxRegistry ja e revertido
    # pelo Core. Este Undo existe para o par obrigatorio Set/Undo/Test e para uso
    # direto com um estado explicito.
    if (-not $Estado) { throw 'sem estado para restaurar SvcHostSplitThresholdInKB (a reversao normal e feita pelo registro de tipo registry)' }

    $anterior = $Estado.anterior
    if ($null -eq $anterior) {
        Set-TmxRegistry -Path $script:TmxSvcHostPath -Name $script:TmxSvcHostName -Remove -TweakId 'undo' | Out-Null
        return "$($script:TmxSvcHostName) removido"
    }
    Set-TmxRegistry -Path $script:TmxSvcHostPath -Name $script:TmxSvcHostName -Value ([int]$anterior) -Type 'DWord' -TweakId 'undo' | Out-Null
    "$($script:TmxSvcHostName) restaurado para $anterior"
}
