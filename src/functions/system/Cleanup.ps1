# functions/system/Cleanup.ps1
# Backend de cleanup.scan e cleanup.run: temp-usuario, temp-sistema, wu-cache,
# miniaturas, lixeira e prefetch.
#
# Modo de teste: Get-TmxCleanupRoots aponta os cinco itens baseados em pasta
# para raizes falsas dentro da home de teste (nunca %TEMP%/%WINDIR% reais); a
# lixeira tambem vira uma pasta falsa nesse modo, ja que Clear-RecycleBin nao
# tem como ser redirecionado.

function Get-TmxCleanupItemIds {
    [CmdletBinding()]
    param()
    @('temp-usuario', 'temp-sistema', 'wu-cache', 'miniaturas', 'lixeira', 'prefetch')
}

function Get-TmxCleanupRoots {
    <#
    .SYNOPSIS
        Pasta real (ou raiz falsa, em modo de teste) de cada item de limpeza
        baseado em pasta. Nao inclui 'lixeira' (tratada a parte: nao e uma
        pasta comum, e Invoke-TmxCleanupLixeira decide a raiz falsa dela).
    #>
    [CmdletBinding()]
    param()

    if ($null -ne $sync -and $sync.testMode) {
        $base = Join-Path (Get-TmxHomePath) 'cleanup-fake'
        return [ordered]@{
            'temp-usuario' = Join-Path $base 'temp-usuario'
            'temp-sistema' = Join-Path $base 'temp-sistema'
            'wu-cache'     = Join-Path $base 'wu-cache'
            'miniaturas'   = Join-Path $base 'miniaturas'
            'prefetch'     = Join-Path $base 'prefetch'
        }
    }

    [ordered]@{
        'temp-usuario' = "$env:TEMP"
        'temp-sistema' = (Join-Path $env:WINDIR 'Temp')
        'wu-cache'     = (Join-Path $env:WINDIR 'SoftwareDistribution\Download')
        'miniaturas'   = (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Explorer')
        'prefetch'     = (Join-Path $env:WINDIR 'Prefetch')
    }
}

function Get-TmxCleanupLixeiraFakeRoot {
    [CmdletBinding()]
    param()
    Join-Path (Join-Path (Get-TmxHomePath) 'cleanup-fake') 'lixeira'
}

function Get-TmxCleanupFolderStats {
    <#
    .SYNOPSIS
        { bytes, arquivos } de $Path (recursivo opcional), sem apagar nada.
        Pasta ausente ou erro de enumeracao vira {0,0} (nunca lanca).
    #>
    [CmdletBinding()]
    param(
        [string] $Path,
        [string] $Filter = '*',
        [switch] $Recurse
    )
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return @{ bytes = 0L; arquivos = 0 } }

    $params = @{ LiteralPath = $Path; File = $true; Filter = $Filter; ErrorAction = 'SilentlyContinue' }
    if ($Recurse) { $params.Recurse = $true }

    $arquivos = @(Get-ChildItem @params)
    $soma = ($arquivos | Measure-Object -Property Length -Sum).Sum
    if (-not $soma) { $soma = 0L }

    @{ bytes = [int64]$soma; arquivos = $arquivos.Count }
}

function Get-TmxCleanupScan {
    <#
    .SYNOPSIS
        { itens: [{ id, bytes, arquivos, avisos }] } para os seis itens do
        catalogo de limpeza. So mede - nada e apagado.
    #>
    [CmdletBinding()]
    param()

    $roots = Get-TmxCleanupRoots
    $itens = New-Object 'System.Collections.Generic.List[object]'

    foreach ($id in 'temp-usuario', 'temp-sistema', 'wu-cache', 'prefetch') {
        $s = Get-TmxCleanupFolderStats -Path $roots[$id] -Filter '*' -Recurse
        $itens.Add(@{ id = $id; bytes = $s.bytes; arquivos = $s.arquivos; avisos = @() })
    }

    $sMini = Get-TmxCleanupFolderStats -Path $roots['miniaturas'] -Filter 'thumbcache_*.db'
    $itens.Add(@{ id = 'miniaturas'; bytes = $sMini.bytes; arquivos = $sMini.arquivos; avisos = @() })

    if ($null -ne $sync -and $sync.testMode) {
        $sLix = Get-TmxCleanupFolderStats -Path (Get-TmxCleanupLixeiraFakeRoot) -Filter '*' -Recurse
        $itens.Add(@{ id = 'lixeira'; bytes = $sLix.bytes; arquivos = $sLix.arquivos; avisos = @() })
    } else {
        $rb = Get-TmxRecycleBinSizeSafe
        $itens.Add(@{ id = 'lixeira'; bytes = [int64]$rb.bytes; arquivos = [int]$rb.itens; avisos = @() })
    }

    @{ itens = $itens.ToArray() }
}

function Remove-TmxCleanupFolderContents {
    <#
    .SYNOPSIS
        Apaga os arquivos de $Path que batem $Filter. Arquivo em uso e pulado
        (contado, nao interrompe os demais).
    .OUTPUTS
        { bytes, arquivos, pulados, avisos }
    #>
    [CmdletBinding()]
    param(
        [string] $Path,
        [string] $Filter = '*',
        [switch] $Recurse
    )
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) {
        return @{ bytes = 0L; arquivos = 0; pulados = 0; avisos = @() }
    }

    $params = @{ LiteralPath = $Path; File = $true; Filter = $Filter; ErrorAction = 'SilentlyContinue' }
    if ($Recurse) { $params.Recurse = $true }

    $bytes    = 0L
    $arquivos = 0
    $pulados  = 0
    $avisos   = New-Object 'System.Collections.Generic.List[string]'

    foreach ($f in @(Get-ChildItem @params)) {
        $r = Remove-TmxFileSafe -Path $f.FullName
        if ($r.ok) {
            $bytes += [int64]$r.bytes
            $arquivos++
        } else {
            $pulados++
            $avisos.Add("$($f.Name): em uso ou sem permissao")
        }
    }

    @{ bytes = $bytes; arquivos = $arquivos; pulados = $pulados; avisos = $avisos.ToArray() }
}

function Invoke-TmxCleanupLixeira {
    <#
    .SYNOPSIS
        Esvazia a Lixeira (ou a pasta falsa, em modo de teste). bytes/arquivos
        sao medidos ANTES de esvaziar - Clear-RecycleBin nao devolve tamanho.
    #>
    [CmdletBinding()]
    param()

    if ($null -ne $sync -and $sync.testMode) {
        return (Remove-TmxCleanupFolderContents -Path (Get-TmxCleanupLixeiraFakeRoot) -Filter '*' -Recurse)
    }

    $antes = Get-TmxRecycleBinSizeSafe
    $ok = Invoke-TmxClearRecycleBinSafe
    if (-not $ok) {
        return @{ bytes = 0L; arquivos = 0; pulados = [int]$antes.itens; avisos = @('nao foi possivel esvaziar a Lixeira') }
    }
    @{ bytes = [int64]$antes.bytes; arquivos = [int]$antes.itens; pulados = 0; avisos = @() }
}

function Invoke-TmxCleanupRun {
    <#
    .SYNOPSIS
        Apaga os itens pedidos. wuauserv e parado ANTES de mexer em
        'wu-cache' (so quando esse item foi pedido) e SEMPRE religado no
        finally, mesmo que algum item falhe no meio.
    .OUTPUTS
        { liberado, porItem, pulados }
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string[]] $Ids)

    $idsLimpos = @(@($Ids) | ForEach-Object { "$_" } | Where-Object { $_ })
    if ($idsLimpos.Count -eq 0) { throw 'nenhum item de limpeza selecionado' }

    $conhecidos = Get-TmxCleanupItemIds
    $invalidos = @($idsLimpos | Where-Object { $_ -cnotin $conhecidos })
    if ($invalidos.Count -gt 0) { throw "item(ns) de limpeza desconhecido(s): $($invalidos -join ', ')" }

    $roots = Get-TmxCleanupRoots
    $porItem = [ordered]@{}
    $totalPulados = 0
    $liberadoTotal = 0L
    $wuParadoPorNos = $false

    try {
        # Modo de teste: wu-cache aponta para a raiz falsa, entao o servico
        # real nunca e tocado.
        $emTeste = ($null -ne $sync -and $sync.testMode)
        if ($idsLimpos -contains 'wu-cache' -and -not $emTeste) {
            $wuParadoPorNos = Stop-TmxServiceSafe -Name 'wuauserv'
        }

        foreach ($id in $idsLimpos) {
            $r = switch ($id) {
                'miniaturas' { Remove-TmxCleanupFolderContents -Path $roots['miniaturas'] -Filter 'thumbcache_*.db' }
                'lixeira'    { Invoke-TmxCleanupLixeira }
                default      { Remove-TmxCleanupFolderContents -Path $roots[$id] -Filter '*' -Recurse }
            }
            $porItem[$id]   = [int64]$r.bytes
            $liberadoTotal += [int64]$r.bytes
            $totalPulados  += [int]$r.pulados
        }
    } finally {
        if ($wuParadoPorNos) { Start-TmxServiceSafe -Name 'wuauserv' | Out-Null }
    }

    try {
        Set-TmxSettings -Payload @{ lastCleanup = (Get-Date).ToString('o'); lastCleanupFreed = $liberadoTotal } | Out-Null
    } catch {
        Write-TmxLog -Level WARN -Message "Nao foi possivel gravar lastCleanup/lastCleanupFreed: $($_.Exception.Message)"
    }

    @{ liberado = $liberadoTotal; porItem = $porItem; pulados = $totalPulados }
}
