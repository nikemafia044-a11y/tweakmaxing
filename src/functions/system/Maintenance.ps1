# functions/system/Maintenance.ps1
# Backend das acoes de "Privacidade e dados" em Configuracoes: limpar cache do
# app, abrir a pasta de logs e excluir backups (runs) antigos.

# ---------------------------------------------------------------------------
# app.clearCache
# ---------------------------------------------------------------------------

function Get-TmxOldUiFolders {
    <#
    .SYNOPSIS
        Subpastas de <home>\ui cujo nome nao e a versao atual.
    #>
    [CmdletBinding()]
    param()
    $base = Join-Path (Get-TmxHomePath) 'ui'
    if (-not (Test-Path -LiteralPath $base)) { return @() }

    $atual = Get-TmxCurrentVersion
    @(Get-ChildItem -LiteralPath $base -Directory -ErrorAction SilentlyContinue |
        Where-Object { "$($_.Name)" -cne "$atual" } |
        ForEach-Object { $_.FullName })
}

function Invoke-TmxClearAppCache {
    <#
    .SYNOPSIS
        Apaga os icones em cache (<home>\icons) e as pastas <home>\ui\<versao>
        que nao sao a versao atual.
    .OUTPUTS
        { removidos: [caminhos] }
    #>
    [CmdletBinding()]
    param()

    $removidos = New-Object 'System.Collections.Generic.List[string]'

    $iconsDir = Get-TmxAppIconCacheDir
    if (Test-Path -LiteralPath $iconsDir) {
        foreach ($f in @(Get-ChildItem -LiteralPath $iconsDir -File -ErrorAction SilentlyContinue)) {
            try {
                Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop -WhatIf:$false
                $removidos.Add($f.FullName)
            } catch {
                Write-TmxLog -Level WARN -Message "Nao foi possivel remover '$($f.FullName)': $($_.Exception.Message)"
            }
        }
    }

    foreach ($pasta in @(Get-TmxOldUiFolders)) {
        try {
            Remove-Item -LiteralPath $pasta -Recurse -Force -ErrorAction Stop -WhatIf:$false
            $removidos.Add($pasta)
        } catch {
            Write-TmxLog -Level WARN -Message "Nao foi possivel remover '$pasta': $($_.Exception.Message)"
        }
    }

    @{ removidos = $removidos.ToArray() }
}

# ---------------------------------------------------------------------------
# app.openLogs
# ---------------------------------------------------------------------------

function Get-TmxLogsFolderPath {
    [CmdletBinding()]
    param()
    if ($null -ne $sync -and "$($sync.logDir)") { return "$($sync.logDir)" }
    Join-Path (Get-TmxHomePath) 'logs'
}

function Open-TmxLogsFolder {
    <#
    .SYNOPSIS
        Abre a pasta de logs no Explorer (nao abre nada em modo de teste).
    .OUTPUTS
        { caminho, aberto, simulado }
    #>
    [CmdletBinding()]
    param()

    $pasta = Get-TmxLogsFolderPath
    if (-not (Test-Path -LiteralPath $pasta)) { New-Item -ItemType Directory -Path $pasta -Force | Out-Null }

    if ($null -ne $sync -and $sync.testMode) {
        return @{ caminho = $pasta; aberto = $false; simulado = $true }
    }

    $ok = Open-TmxFolderSafe -Path $pasta
    @{ caminho = $pasta; aberto = [bool]$ok; simulado = $false }
}

# ---------------------------------------------------------------------------
# app.oldBackups / app.deleteOldBackups
# ---------------------------------------------------------------------------

function Get-TmxOldBackupRuns {
    <#
    .SYNOPSIS
        Execucoes em <home>\runs com mais de 30 dias, exceto a mais recente.
    #>
    [CmdletBinding()]
    param()

    $raiz = Get-TmxRunsRoot
    if (-not (Test-Path -LiteralPath $raiz)) { return @() }

    $limite = (Get-Date).AddDays(-30)
    $dirs = @(Get-ChildItem -LiteralPath $raiz -Directory -ErrorAction SilentlyContinue | Sort-Object CreationTimeUtc -Descending)
    if ($dirs.Count -le 1) { return @() }

    @($dirs | Select-Object -Skip 1 | Where-Object { $_.CreationTimeUtc -lt $limite } | ForEach-Object { $_.FullName })
}

function Remove-TmxOldBackupRuns {
    <#
    .SYNOPSIS
        Apaga as execucoes devolvidas por Get-TmxOldBackupRuns. Exige
        Confirmado=$true (o front lista quantas execucoes antes de chamar).
    .OUTPUTS
        { removidos: [caminhos] }
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [bool] $Confirmado)

    if (-not $Confirmado) { throw 'confirmacao pendente: exclusao de backups antigos exige confirmado:true' }

    $alvos = @(Get-TmxOldBackupRuns)
    $removidos = New-Object 'System.Collections.Generic.List[string]'
    foreach ($p in $alvos) {
        try {
            Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction Stop -WhatIf:$false
            $removidos.Add($p)
        } catch {
            Write-TmxLog -Level WARN -Message "Nao foi possivel remover o backup antigo '$p': $($_.Exception.Message)"
        }
    }

    @{ removidos = $removidos.ToArray() }
}
