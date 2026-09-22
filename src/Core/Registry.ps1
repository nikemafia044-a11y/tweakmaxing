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
        Grava (ou remove, com -Remove) um valor no registro capturando o
        estado anterior para reversao.
    .PARAMETER Path
        Caminho no formato PowerShell, ex.: HKLM:\SYSTEM\CurrentControlSet\...
    .PARAMETER TweakId
        Identificador do tweak (ex.: PWR-002) para rastreio no state.json.
    .PARAMETER Remove
        Remove o valor em vez de escrever (usado por politicas de atualizacao
        que precisam desfazer um valor sem saber o que colocar no lugar).
    #>
    [CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = 'Set')]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory, ParameterSetName = 'Set')] $Value,
        [ValidateSet('String', 'ExpandString', 'Binary', 'DWord', 'MultiString', 'QWord')]
        [string] $Type = 'DWord',
        [string] $TweakId = '(sem-id)',
        [Parameter(ParameterSetName = 'Remove')] [switch] $Remove,
        [switch] $PassThru
    )

    # --- 1. Captura do estado atual (comum aos dois modos) -------------------
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

    if ($PSCmdlet.ParameterSetName -eq 'Remove') {
        # --- Caminho de remocao (-Remove) -------------------------------------
        if (-not $existed) {
            $record = [pscustomobject]@{
                tweakId       = $TweakId
                tipo          = 'registry'
                alvo          = ('{0}::{1}' -f $Path, $Name)
                detalhe       = @{ path = $Path; name = $Name; removido = $true }
                valorAnterior = $null
                tipoAnterior  = $null
                existiaAntes  = $false
                valorNovo     = $null
                reversao      = @{ tipo = 'nenhuma' }
                status        = 'naoAplicavel'
                aplicadoEm    = $null
                erro          = $null
            }
            if ($PassThru) { return $record }
            return
        }

        $record = [pscustomobject]@{
            tweakId       = $TweakId
            tipo          = 'registry'
            alvo          = ('{0}::{1}' -f $Path, $Name)
            detalhe       = @{ path = $Path; name = $Name; removido = $true }
            valorAnterior = $oldValue
            tipoAnterior  = $oldType
            existiaAntes  = $true
            valorNovo     = $null
            reversao      = @{ tipo = 'restaurarValorAnterior' }
            status        = 'aplicando'
            aplicadoEm    = $null
            erro          = $null
        }

        if (-not $PSCmdlet.ShouldProcess($Path, "remover '$Name'")) {
            $record.status = 'whatif'
            if ($PassThru) { return $record }
            return
        }

        # Persiste ANTES de remover: se o processo morrer entre a persistencia
        # e a remocao, o rollback ainda sabe restaurar o valor original.
        Add-TmxStateRecord -Record $record | Out-Null

        try {
            Remove-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop
            $record.status     = 'aplicado'
            $record.aplicadoEm = (Get-Date).ToString('o')
            Write-TmxLog -Level INFO -Message "Valor removido [$TweakId]: $Path::$Name" -Data @{ anterior = $oldValue }
        } catch {
            $record.status = 'falha'
            $record.erro   = $_.Exception.Message
            Write-TmxLog -Level ERROR -Message "Falha ao remover [$TweakId]: $Path::$Name - $($_.Exception.Message)"
        } finally {
            Save-TmxState
        }

        if ($PassThru) { return $record }
        return
    }

    # --- Caminho de escrita (padrao) ------------------------------------------

    # Estrategia de reversao decidida AGORA, com base no que existia.
    $reversao =
        if ($existed)        { @{ tipo = 'restaurarValorAnterior' } }
        elseif ($keyExisted) { @{ tipo = 'removerValor' } }
        else                 { @{ tipo = 'removerChaveCriada' } }

    # M2: se a chave nao existe, identifica o ancestral mais alto que sera
    # criado por esta escrita, para que a reversao apague so os niveis que
    # nos criamos (e pare no primeiro ancestral que ja existia).
    $chaveRaizCriada = $null
    if (-not $keyExisted) {
        $cur  = $Path
        $last = $Path
        while (-not (Test-Path -LiteralPath $cur)) {
            $last   = $cur
            $parent = Split-Path -Path $cur -Parent
            if (-not $parent -or $parent -eq $cur) { break }
            $cur = $parent
        }
        $chaveRaizCriada = $last
    }

    $record = [pscustomobject]@{
        tweakId       = $TweakId
        tipo          = 'registry'
        alvo          = ('{0}::{1}' -f $Path, $Name)
        detalhe       = @{
            path            = $Path
            name            = $Name
            tipoNovo        = $Type
            chaveCriada     = (-not $keyExisted)
            chaveRaizCriada = $chaveRaizCriada
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
