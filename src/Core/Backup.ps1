# Core/Backup.ps1
# Pasta da execucao, state.json (fonte da verdade para rollback) e exports de seguranca.
#
# Layout: %LOCALAPPDATA%\TweakMaxing\runs\<runId>\
#   state.json        - registros de tudo que foi alterado (valor anterior incluso)
#   events.jsonl      - log estruturado
#   transcript.log    - transcript da sessao
#   regbackup\*.reg   - exports de ramos do registro ANTES de qualquer escrita
#   power-scheme.pow  - esquema de energia ativo
#   net-adapters.json - adaptadores e propriedades avancadas
#
# A variavel de ambiente TWEAKMAXING_HOME sobrescreve a raiz (usada pelos testes).

$script:TmxRun          = $null
$script:TmxStateRecords = $null

function Get-TmxHomePath {
    if ($env:TWEAKMAXING_HOME) { return $env:TWEAKMAXING_HOME }
    Join-Path $env:LOCALAPPDATA 'TweakMaxing'
}

function Get-TmxRunsRoot {
    Join-Path (Get-TmxHomePath) 'runs'
}

function New-TmxRun {
    <#
    .SYNOPSIS
        Cria a pasta da execucao, zera o estado em memoria e inicia o logger.
    #>
    [CmdletBinding()]
    param(
        [string] $RunsRoot = (Get-TmxRunsRoot)
    )

    $runId   = '{0:yyyyMMdd-HHmmss}-{1:x4}' -f (Get-Date), (Get-Random -Maximum 65535)
    $runPath = Join-Path $RunsRoot $runId
    $regPath = Join-Path $runPath 'regbackup'

    New-Item -ItemType Directory -Path $runPath -Force | Out-Null
    New-Item -ItemType Directory -Path $regPath -Force | Out-Null

    $script:TmxStateRecords = New-Object 'System.Collections.Generic.List[object]'
    $script:TmxRun = [pscustomobject]@{
        RunId         = $runId
        RunPath       = $runPath
        StatePath     = (Join-Path $runPath 'state.json')
        RegBackupPath = $regPath
        ReportPath    = (Join-Path $runPath 'relatorio.html')
        CriadoEm      = (Get-Date)
    }

    Initialize-TmxLogger -RunPath $runPath -RunId $runId | Out-Null
    Save-TmxState
    Write-TmxLog -Level INFO -Message 'Nova execucao criada' -Data @{ runId = $runId; caminho = $runPath }

    $script:TmxRun
}

function Get-TmxRun {
    $script:TmxRun
}

function Add-TmxStateRecord {
    <#
    .SYNOPSIS
        Anexa um registro ao estado e persiste imediatamente em disco.
    .NOTES
        O objeto e adicionado por referencia: quem chamou pode atualizar
        status/erro depois e chamar Save-TmxState para persistir.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Record
    )
    if ($null -eq $script:TmxStateRecords) {
        $script:TmxStateRecords = New-Object 'System.Collections.Generic.List[object]'
    }
    $script:TmxStateRecords.Add($Record)
    Save-TmxState
    $Record
}

function New-TmxStateRecord {
    <#
    .SYNOPSIS
        Cria um registro de estado com status 'aplicando' e persiste ANTES da escrita.
        Handlers de qualquer tipo usam isto; Set-TmxRegistry tem o seu proprio.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $TweakId,
        [Parameter(Mandatory)] [string] $Tipo,
        [Parameter(Mandatory)] [string] $Alvo,
        $Detalhe = @{},
        $ValorAnterior = $null,
        $ValorNovo = $null,
        [string] $ReversaoTipo = 'restaurarValorAnterior',
        [bool] $ExistiaAntes = $true
    )
    $rec = [pscustomobject]@{
        tweakId       = $TweakId
        tipo          = $Tipo
        alvo          = $Alvo
        detalhe       = $Detalhe
        valorAnterior = $ValorAnterior
        tipoAnterior  = $null
        existiaAntes  = $ExistiaAntes
        valorNovo     = $ValorNovo
        reversao      = @{ tipo = $ReversaoTipo }
        status        = 'aplicando'
        aplicadoEm    = $null
        erro          = $null
    }
    Add-TmxStateRecord -Record $rec | Out-Null
    $rec
}

function Complete-TmxStateRecord {
    # Fecha um registro: aplicado ou falha. Persiste.
    param(
        [Parameter(Mandatory)] $Record,
        [Parameter(Mandatory)] [bool] $Ok,
        [string] $Erro
    )
    if ($Ok) {
        $Record.status     = 'aplicado'
        $Record.aplicadoEm = (Get-Date).ToString('o')
    } else {
        $Record.status = 'falha'
        $Record.erro   = $Erro
    }
    Save-TmxState
    $Record
}

function Get-TmxState {
    # Emite os registros no pipeline (vazio -> nada). Quem precisa de array usa @(Get-TmxState).
    if ($null -eq $script:TmxStateRecords) { return }
    $script:TmxStateRecords.ToArray()
}

function Save-TmxState {
    [CmdletBinding()]
    param()
    if (-not $script:TmxRun) { return }

    # .ToArray() em atribuicao DIRETA: @() sobre List generica vazia falha no PS 5.1,
    # e um array vazio saindo de "if {}" como expressao e desenrolado para $null pelo pipeline.
    $registros = New-Object 'object[]' 0
    if ($null -ne $script:TmxStateRecords) { $registros = $script:TmxStateRecords.ToArray() }

    $payload = [ordered]@{
        runId      = $script:TmxRun.RunId
        criadoEm   = $script:TmxRun.CriadoEm.ToString('o')
        computador = $env:COMPUTERNAME
        registros  = $registros
    }
    $json = $payload | ConvertTo-Json -Depth 12
    # -WhatIf:$false: o state.json e a garantia de reversao; nunca pode ser pulado.
    Set-Content -LiteralPath $script:TmxRun.StatePath -Value $json -Encoding UTF8 -WhatIf:$false
}

function Import-TmxState {
    <#
    .SYNOPSIS
        Le os registros de um state.json. Nao depende do estado em memoria.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $StatePath
    )
    if (-not (Test-Path -LiteralPath $StatePath)) {
        throw "state.json nao encontrado em: $StatePath"
    }
    $data = Get-Content -LiteralPath $StatePath -Raw -Encoding UTF8 | ConvertFrom-Json
    # Emite no pipeline; caller usa @(Import-TmxState ...) quando precisa de array.
    $data.registros | Where-Object { $null -ne $_ }
}

# ---------------------------------------------------------------------------
# Exports de seguranca
# ---------------------------------------------------------------------------

function ConvertTo-TmxRegExportPath {
    <#
    .SYNOPSIS
        Converte caminho PowerShell (HKLM:\...) para o formato do reg.exe (HKEY_LOCAL_MACHINE\...).
    #>
    param([Parameter(Mandatory)] [string] $Path)

    $p = $Path.Trim()
    $map = [ordered]@{
        '^HKLM:\\' = 'HKEY_LOCAL_MACHINE\'
        '^HKCU:\\' = 'HKEY_CURRENT_USER\'
        '^HKCR:\\' = 'HKEY_CLASSES_ROOT\'
        '^HKU:\\'  = 'HKEY_USERS\'
        '^HKCC:\\' = 'HKEY_CURRENT_CONFIG\'
        '^HKLM\\'  = 'HKEY_LOCAL_MACHINE\'
        '^HKCU\\'  = 'HKEY_CURRENT_USER\'
    }
    foreach ($pattern in $map.Keys) {
        if ($p -match $pattern) { return ($p -replace $pattern, $map[$pattern]) }
    }
    $p
}

function Backup-TmxRegistryHive {
    <#
    .SYNOPSIS
        Exporta um ramo do registro para .reg na pasta da execucao.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [string] $OutputDir
    )

    if (-not $OutputDir) {
        if (-not $script:TmxRun) { throw 'Nenhuma execucao ativa. Chame New-TmxRun primeiro.' }
        $OutputDir = $script:TmxRun.RegBackupPath
    }
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

    $regPath  = ConvertTo-TmxRegExportPath -Path $Path
    $safeName = ($regPath -replace '[\\/:*?"<>|]', '_')
    $file     = Join-Path $OutputDir "$safeName.reg"

    $output = & reg.exe export $regPath $file /y 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-TmxLog -Level WARN -Message "Falha ao exportar ramo: $regPath" -Data @{ saida = "$output" }
        return $null
    }

    Write-TmxLog -Level INFO -Message "Ramo exportado: $regPath" -Data @{ arquivo = $file }
    $file
}

function Backup-TmxPowerScheme {
    <#
    .SYNOPSIS
        Exporta o esquema de energia ativo (.pow).
    #>
    [CmdletBinding()]
    param([string] $OutputDir)

    if (-not $OutputDir) {
        if (-not $script:TmxRun) { throw 'Nenhuma execucao ativa. Chame New-TmxRun primeiro.' }
        $OutputDir = $script:TmxRun.RunPath
    }

    $file = Join-Path $OutputDir 'power-scheme.pow'
    try {
        $active = (& powercfg /getactivescheme 2>&1) -join ' '
        $guid   = [regex]::Match($active, '[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}').Value
        if (-not $guid) { throw "GUID do esquema ativo nao identificado: $active" }

        if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file -Force }
        & powercfg /export $file $guid 2>&1 | Out-Null

        if (-not (Test-Path -LiteralPath $file)) { throw 'powercfg /export nao gerou o arquivo' }

        Write-TmxLog -Level INFO -Message 'Esquema de energia exportado' -Data @{ guid = $guid; arquivo = $file }
        return [pscustomobject]@{ guid = $guid; arquivo = $file }
    } catch {
        Write-TmxLog -Level WARN -Message "Falha ao exportar esquema de energia: $($_.Exception.Message)"
        return $null
    }
}

function Backup-TmxNetworkAdapters {
    <#
    .SYNOPSIS
        Salva adaptadores de rede e suas propriedades avancadas em JSON.
    #>
    [CmdletBinding()]
    param([string] $OutputDir)

    if (-not $OutputDir) {
        if (-not $script:TmxRun) { throw 'Nenhuma execucao ativa. Chame New-TmxRun primeiro.' }
        $OutputDir = $script:TmxRun.RunPath
    }

    $file = Join-Path $OutputDir 'net-adapters.json'
    try {
        $adapters = @(Get-NetAdapter -ErrorAction Stop | ForEach-Object {
            $name = $_.Name
            [pscustomobject]@{
                nome                  = $name
                descricao             = $_.InterfaceDescription
                status                = "$($_.Status)"
                velocidadeLink        = $_.LinkSpeed
                mac                   = $_.MacAddress
                propriedadesAvancadas = @(
                    Get-NetAdapterAdvancedProperty -Name $name -ErrorAction SilentlyContinue |
                        Select-Object DisplayName, DisplayValue, RegistryKeyword, @{ n = 'RegistryValue'; e = { @($_.RegistryValue) -join ',' } }
                )
            }
        })
        $adapters | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $file -Encoding UTF8
        Write-TmxLog -Level INFO -Message 'Adaptadores de rede salvos' -Data @{ quantidade = $adapters.Count; arquivo = $file }
        return $file
    } catch {
        Write-TmxLog -Level WARN -Message "Falha ao salvar adaptadores de rede: $($_.Exception.Message)"
        return $null
    }
}
