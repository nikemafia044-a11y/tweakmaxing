# Core/Registry.ps1
# Escrita no registro com captura obrigatoria do valor anterior.
#
# Garantias de Set-TmxRegistry:
#  - Le o valor atual antes de qualquer escrita (ou registra existiaAntes = false).
#  - Persiste o registro de estado em disco ANTES de escrever. Se o processo
#    morrer no meio, o rollback ainda sabe o que restaurar.
#  - Cria o caminho se nao existir e marca isso, para que a reversao apague a chave.
#  - Suporta -WhatIf/-Confirm nativamente.
#  - Retorna um objeto (com -PassThru). Nunca escreve no host.

function Get-TmxRegistryValueKind {
    <#
    .SYNOPSIS
        Retorna o tipo (RegistryValueKind) de um valor, ou $null se nao existir.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Name
    )
    try {
        $key = Get-Item -LiteralPath $Path -ErrorAction Stop
        return $key.GetValueKind($Name).ToString()
    } catch {
        return $null
    }
}

function Set-TmxRegistry {
    <#
    .SYNOPSIS
        Grava um valor no registro capturando o estado anterior para reversao.
    .PARAMETER Path
        Caminho no formato PowerShell, ex.: HKLM:\SYSTEM\CurrentControlSet\...
    .PARAMETER TweakId
        Identificador do tweak (ex.: PWR-002) para rastreio no state.json.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] $Value,
        [ValidateSet('String', 'ExpandString', 'Binary', 'DWord', 'MultiString', 'QWord')]
        [string] $Type = 'DWord',
        [string] $TweakId = '(sem-id)',
        [switch] $PassThru
    )

    # --- 1. Captura do estado atual -----------------------------------------
    $keyExisted = Test-Path -LiteralPath $Path
    $existed    = $false
    $oldValue   = $null
    $oldType    = $null

    if ($keyExisted) {
        $prop = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue
        if ($null -ne $prop -and ($prop.PSObject.Properties.Name -contains $Name)) {
            $existed  = $true
            $oldValue = $prop.$Name
            $oldType  = Get-TmxRegistryValueKind -Path $Path -Name $Name
        }
    }

    # Estrategia de reversao decidida AGORA, com base no que existia.
    $reversao =
        if ($existed)        { @{ tipo = 'restaurarValorAnterior' } }
        elseif ($keyExisted) { @{ tipo = 'removerValor' } }
        else                 { @{ tipo = 'removerChaveCriada' } }

    $record = [pscustomobject]@{
        tweakId       = $TweakId
        tipo          = 'registry'
        alvo          = ('{0}::{1}' -f $Path, $Name)
        detalhe       = @{
            path        = $Path
            name        = $Name
            tipoNovo    = $Type
            chaveCriada = (-not $keyExisted)
        }
        valorAnterior = $oldValue
        tipoAnterior  = $oldType
        existiaAntes  = $existed
        valorNovo     = $Value
        reversao      = $reversao
        status        = 'aplicando'
        aplicadoEm    = $null
        erro          = $null
    }

    # --- 2. ShouldProcess (-WhatIf / -Confirm) -------------------------------
    $descricao =
        if ($existed) { "alterar '$Name' de [$oldValue] para [$Value] ($Type)" }
        else          { "criar '$Name' = [$Value] ($Type)" }

    if (-not $PSCmdlet.ShouldProcess($Path, $descricao)) {
        $record.status = 'whatif'
        if ($PassThru) { return $record }
        return
    }

    # --- 3. Persistir estado ANTES de escrever ------------------------------
    Add-TmxStateRecord -Record $record | Out-Null

    # --- 4. Escrita ----------------------------------------------------------
    try {
        if (-not $keyExisted) {
            New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
        }
        New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType $Type -Force -ErrorAction Stop | Out-Null

        $record.status     = 'aplicado'
        $record.aplicadoEm = (Get-Date).ToString('o')
        Write-TmxLog -Level INFO -Message "Registro aplicado [$TweakId]: $Path::$Name" -Data @{ de = $oldValue; para = $Value; tipo = $Type }
    } catch {
        $record.status = 'falha'
        $record.erro   = $_.Exception.Message
        Write-TmxLog -Level ERROR -Message "Falha no registro [$TweakId]: $Path::$Name - $($_.Exception.Message)"
    } finally {
        Save-TmxState
    }

    if ($PassThru) { return $record }
}
