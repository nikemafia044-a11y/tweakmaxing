# functions/system/RestorePoints.ps1
# Backend de restore.list / restore.create / restore.delete / restore.restore.
#
# list e create reusam o que Core/RestorePoint.ps1 ja tem (Get-TmxRestorePoints,
# New-TmxRestorePoint - que ja cuida do throttle de 24h via
# SystemRestorePointCreationFrequency, restaurando o valor original no seu
# proprio finally). delete e restore sao novos: SRRemoveRestorePoint
# (P/Invoke) e SystemRestore.Restore (WMI), via os wrappers de _Wrappers.ps1.
#
# Modo de teste: as quatro acoes operam sobre uma lista falsa persistida em
# JSON dentro da home de teste - nunca tocam Get-ComputerRestorePoint,
# Checkpoint-Computer, SRRemoveRestorePoint nem SystemRestore.Restore de
# verdade.

function Get-TmxRestoreFakeListPath {
    [CmdletBinding()]
    param()
    Join-Path (Get-TmxHomePath) 'restore-points-fake.json'
}

function Get-TmxRestoreFakeList {
    [CmdletBinding()]
    param()
    $p = Get-TmxRestoreFakeListPath
    if (-not (Test-Path -LiteralPath $p)) { return @() }
    try {
        # Atribuir antes do @(): no PS 5.1 ConvertFrom-Json emite o array
        # JSON como UM objeto (object[]), e @(pipeline) o embrulharia de novo.
        $doc = Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json
        @($doc)
    } catch {
        Write-TmxLog -Level WARN -Message "Lista falsa de pontos de restauracao ilegivel: $($_.Exception.Message)"
        @()
    }
}

function Save-TmxRestoreFakeList {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Lista)
    $p = Get-TmxRestoreFakeListPath
    $pasta = Split-Path $p -Parent
    if (-not (Test-Path -LiteralPath $pasta)) { New-Item -ItemType Directory -Path $pasta -Force | Out-Null }
    $tmp = "$p.tmp"
    (ConvertTo-TmxJsonArray -Items $Lista -Depth 6) | Set-Content -LiteralPath $tmp -Encoding UTF8 -WhatIf:$false
    Move-Item -LiteralPath $tmp -Destination $p -Force
}

function Get-TmxRestoreList {
    <#
    .SYNOPSIS
        Pontos de restauracao, mais recente primeiro: { sequencia, nome, data }.
    #>
    [CmdletBinding()]
    param()

    if ($null -ne $sync -and $sync.testMode) {
        return @(@(Get-TmxRestoreFakeList) | Sort-Object { [int]$_.sequencia } -Descending)
    }

    @(@(Get-TmxRestorePoints) | ForEach-Object {
        $data = $null
        try { $data = ([datetime]$_.CreationTime).ToString('o') } catch { $data = $null }
        @{ sequencia = [int]$_.SequenceNumber; nome = "$($_.Description)"; data = $data }
    } | Sort-Object { [int]$_.sequencia } -Descending)
}

function New-TmxRestoreCreate {
    <#
    .SYNOPSIS
        Cria um ponto de restauracao (ou simula, em modo de teste).
    .PARAMETER Nome
        Descricao do ponto. Sem valor: "TweakMaxing aaaa-MM-dd HH:mm".
    #>
    [CmdletBinding()]
    param([string] $Nome)

    if (-not $Nome) { $Nome = 'TweakMaxing {0:yyyy-MM-dd HH:mm}' -f (Get-Date) }

    if ($null -ne $sync -and $sync.testMode) {
        $lista = @(Get-TmxRestoreFakeList)
        $proxima = 1
        if ($lista.Count -gt 0) { $proxima = ([int](($lista | Measure-Object -Property sequencia -Maximum).Maximum)) + 1 }
        $novo = @{ sequencia = $proxima; nome = $Nome; data = (Get-Date).ToString('o') }
        $lista += $novo
        Save-TmxRestoreFakeList -Lista $lista
        return @{ ok = $true; sequencia = $proxima; nome = $Nome; simulado = $true }
    }

    $r = New-TmxRestorePoint -Description $Nome
    if (-not $r.ok) {
        throw "nao foi possivel criar o ponto de restauracao (etapa: $($r.etapa)): $($r.erro)"
    }
    @{ ok = $true; sequencia = [int]$r.sequenceNumber; nome = $Nome; simulado = $false }
}

function Remove-TmxRestorePointById {
    <#
    .SYNOPSIS
        Exclui um ponto de restauracao pela sequencia (ou simula).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [int] $Sequencia)

    if ($null -ne $sync -and $sync.testMode) {
        $lista = @(Get-TmxRestoreFakeList)
        $restante = @($lista | Where-Object { [int]$_.sequencia -ne $Sequencia })
        if ($restante.Count -eq $lista.Count) { throw "ponto de restauracao nao encontrado: $Sequencia" }
        Save-TmxRestoreFakeList -Lista $restante
        return @{ ok = $true; sequencia = $Sequencia; simulado = $true }
    }

    $r = Remove-TmxRestorePointNative -Sequence $Sequencia
    if (-not $r.ok) {
        throw "nao foi possivel excluir o ponto de restauracao $Sequencia (codigo $($r.codigo))"
    }
    @{ ok = $true; sequencia = $Sequencia; simulado = $false }
}

function Invoke-TmxRestoreRestore {
    <#
    .SYNOPSIS
        Inicia a restauracao do sistema para o ponto informado (ou simula).
        Nunca reinicia sozinho - so agenda a restauracao para o proximo boot.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [int]  $Sequencia,
        [Parameter(Mandatory)] [bool] $Confirmado
    )

    if (-not $Confirmado) { throw 'confirmacao pendente: restaurar o sistema exige confirmado:true' }

    if ($null -ne $sync -and $sync.testMode) {
        $lista = @(Get-TmxRestoreFakeList)
        $achado = @($lista | Where-Object { [int]$_.sequencia -eq $Sequencia })
        if ($achado.Count -eq 0) { throw "ponto de restauracao nao encontrado: $Sequencia" }
        return @{ ok = $true; sequencia = $Sequencia; simulado = $true }
    }

    $r = Invoke-TmxSystemRestoreWmi -Sequence $Sequencia
    if (-not $r.ok) { throw "nao foi possivel iniciar a restauracao do sistema: $($r.erro)" }
    @{ ok = $true; sequencia = $Sequencia; simulado = $false }
}
