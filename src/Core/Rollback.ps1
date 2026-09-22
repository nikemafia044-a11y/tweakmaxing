# Core/Rollback.ps1
# Undo-TweakMaxing: reverte uma execucao a partir do state.json em ordem inversa.
#
# Nao depende de nada em memoria - le o arquivo e reverte item a item.
# Funciona mesmo se o processo original tiver morrido no meio da aplicacao.
# Falha em um item nao interrompe os demais.

function ConvertTo-TmxTypedValue {
    # Reconverte um valor vindo do JSON para o tipo esperado pelo registro.
    param(
        $Value,
        [string] $Kind
    )
    switch ($Kind) {
        'DWord'       {
            # O provider pode devolver DWord alto como 4294967295; para gravar precisa ir como int32 negativo.
            $v = [int64]$Value
            if ($v -gt [int]::MaxValue) { $v = $v - 4294967296 }
            return [int]$v
        }
        'QWord'       { return [int64]$Value }
        'Binary'      { return [byte[]]@($Value) }
        'MultiString' { return [string[]]@($Value) }
        default       { return [string]$Value }
    }
}

function Undo-TmxRegistryRecord {
    # Reverte um unico registro do tipo 'registry'. Retorna descricao do que fez.
    param([Parameter(Mandatory)] $Record)

    $path    = $Record.detalhe.path
    $name    = $Record.detalhe.name
    $tipoRev = $Record.reversao.tipo

    switch ($tipoRev) {
        'restaurarValorAnterior' {
            if (-not (Test-Path -LiteralPath $path)) {
                New-Item -Path $path -Force -ErrorAction Stop | Out-Null
            }
            $kind = if ($Record.tipoAnterior) { $Record.tipoAnterior } else { 'DWord' }
            $val  = ConvertTo-TmxTypedValue -Value $Record.valorAnterior -Kind $kind
            New-ItemProperty -LiteralPath $path -Name $name -Value $val -PropertyType $kind -Force -ErrorAction Stop | Out-Null
            return "valor restaurado para [$($Record.valorAnterior)] ($kind)"
        }

        'removerValor' {
            if (Test-Path -LiteralPath $path) {
                Remove-ItemProperty -LiteralPath $path -Name $name -ErrorAction SilentlyContinue
            }
            return "valor '$name' removido"
        }

        'removerChaveCriada' {
            if (-not (Test-Path -LiteralPath $path)) {
                return "chave '$path' ja nao existe"
            }
            Remove-ItemProperty -LiteralPath $path -Name $name -ErrorAction SilentlyContinue

            $key         = Get-Item -LiteralPath $path
            $temValores  = @($key.GetValueNames() | Where-Object { $_ -ne '' }).Count -gt 0
            $temSubchave = @(Get-ChildItem -LiteralPath $path -ErrorAction SilentlyContinue).Count -gt 0

            if (-not $temValores -and -not $temSubchave) {
                Remove-Item -LiteralPath $path -Force -Recurse -ErrorAction Stop
                return "valor removido e chave criada '$path' apagada"
            }
            return "valor removido; chave '$path' mantida (nao estava vazia)"
        }

        default {
            throw "estrategia de reversao desconhecida: $tipoRev"
        }
    }
}

function Undo-TmxPowercfgRecord {
    param([Parameter(Mandatory)] $Record)
    $d = $Record.detalhe
    if ($null -eq $Record.valorAnterior) { throw 'valor anterior desconhecido; restaure o esquema exportado (power-scheme.pow) com powercfg /import' }
    $r = Invoke-TmxPowercfg @('/setacvalueindex', "$($d.esquema)", "$($d.subgrupo)", "$($d.configuracao)", "$($Record.valorAnterior)")
    if ($r.codigo -ne 0) { throw "powercfg /setacvalueindex retornou $($r.codigo): $($r.saida)" }
    $ativo = Get-TmxActivePowerScheme
    if ($ativo -and $ativo.guid -ieq "$($d.esquema)") { Invoke-TmxPowercfg @('/setactive', "$($d.esquema)") | Out-Null }
    "indice AC restaurado para $($Record.valorAnterior) em $($Record.alvo)"
}

function Undo-TmxServiceRecord {
    param([Parameter(Mandatory)] $Record)
    $ant = $Record.valorAnterior
    if (-not $ant -or -not $ant.startType) { throw 'estado anterior do servico desconhecido' }
    $iniciar = ("$($ant.status)" -eq 'Running')
    Set-TmxServiceState -Nome $Record.detalhe.nome -StartType "$($ant.startType)" -Iniciar:$iniciar
    "servico $($Record.detalhe.nome): inicio=$($ant.startType), status=$($ant.status)"
}

function Undo-TmxNetAdapterRecord {
    param([Parameter(Mandatory)] $Record)
    if ($null -eq $Record.valorAnterior) { throw 'valor anterior desconhecido; veja net-adapters.json' }
    Set-TmxAdapterAdvanced -Name $Record.detalhe.adaptador -Keyword $Record.detalhe.chave -Value "$($Record.valorAnterior)"
    "$($Record.detalhe.chave) restaurado para $($Record.valorAnterior) em '$($Record.detalhe.adaptador)'"
}

function Undo-TmxCmdletRecord {
    param([Parameter(Mandatory)] $Record)
    $funcao = "$($Record.detalhe.funcao)"
    $undo = 'Undo-' + ($funcao -replace '^[A-Za-z]+-', '')
    if (-not (Get-Command $undo -ErrorAction SilentlyContinue)) { throw "funcao de reversao '$undo' nao encontrada" }
    & $undo -Estado $Record.detalhe.estado
}

function Write-TmxRollbackReport {
    # UI: imprime o resumo da reversao. Separado do valor de retorno.
    param([Parameter(Mandatory)] $Summary)

    Write-Host ''
    Write-Host '  Reversao TweakMaxing' -ForegroundColor Cyan
    Write-Host ("  Estado: {0}" -f $Summary.statePath) -ForegroundColor DarkGray

    if ($Summary.total -eq 0) {
        Write-Host '  Nada a reverter.' -ForegroundColor Yellow
    }

    foreach ($item in $Summary.itens) {
        $cor = switch ($item.resultado) {
            'revertido' { 'Green' }
            'simulado'  { 'Yellow' }
            'pulado'    { 'Yellow' }
            default     { 'Red' }
        }
        Write-Host ("   [{0,-9}] {1}" -f $item.resultado, $item.alvo) -ForegroundColor $cor
        if ($item.detalhe) {
            Write-Host ("               {0}" -f $item.detalhe) -ForegroundColor DarkGray
        }
    }

    Write-Host ("  Total: {0} | Revertidos: {1} | Falhas: {2} | Pulados: {3}" -f `
        $Summary.total, $Summary.revertidos, $Summary.falhas, $Summary.pulados) -ForegroundColor White
    Write-Host ''
}

function Undo-TweakMaxing {
    <#
    .SYNOPSIS
        Reverte os tweaks de uma execucao do TweakMaxing.
    .EXAMPLE
        Undo-TweakMaxing -Latest
    .EXAMPLE
        Undo-TweakMaxing -RunId 20250909-120000-1a2b
    .EXAMPLE
        Undo-TweakMaxing -StatePath 'C:\...\state.json' -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = 'Latest')]
    param(
        [Parameter(ParameterSetName = 'ById', Mandatory)]
        [string] $RunId,

        [Parameter(ParameterSetName = 'Latest')]
        [switch] $Latest,

        [Parameter(ParameterSetName = 'Path', Mandatory)]
        [string] $StatePath,

        [string] $RunsRoot = (Get-TmxRunsRoot)
    )

    # --- Resolver o state.json ----------------------------------------------
    $resolvedStatePath = switch ($PSCmdlet.ParameterSetName) {
        'Path' { $StatePath }
        'ById' { Join-Path (Join-Path $RunsRoot $RunId) 'state.json' }
        default {
            # CreationTimeUtc tem precisao sub-segundo; o nome (yyyyMMdd-HHmmss-xxxx)
            # empata quando varias execucoes nascem no mesmo segundo.
            $ultima = Get-ChildItem -LiteralPath $RunsRoot -Directory -ErrorAction SilentlyContinue |
                      Sort-Object CreationTimeUtc, Name -Descending | Select-Object -First 1
            if (-not $ultima) { throw "Nenhuma execucao encontrada em: $RunsRoot" }
            Join-Path $ultima.FullName 'state.json'
        }
    }

    $registros = @(Import-TmxState -StatePath $resolvedStatePath)
    Write-TmxLog -Level INFO -Message 'Iniciando reversao' -Data @{ state = $resolvedStatePath; registros = $registros.Count }

    # So revertemos o que chegou a tocar o sistema. 'falha' entra porque a
    # escrita pode ter sido parcial; reverter e seguro (restaura o anterior).
    $aplicaveis = @($registros | Where-Object { $_.status -in @('aplicado', 'falha', 'aplicando') })
    [array]::Reverse($aplicaveis)

    $resultados = New-Object 'System.Collections.Generic.List[object]'

    foreach ($rec in $aplicaveis) {
        $r = [pscustomobject]@{
            tweakId   = $rec.tweakId
            tipo      = $rec.tipo
            alvo      = $rec.alvo
            resultado = $null
            detalhe   = $null
        }

        if (-not $PSCmdlet.ShouldProcess($rec.alvo, 'reverter')) {
            $r.resultado = 'simulado'
            $resultados.Add($r)
            continue
        }

        try {
            switch ($rec.tipo) {
                'registry'   { $r.detalhe = Undo-TmxRegistryRecord   -Record $rec; $r.resultado = 'revertido' }
                'powercfg'   { $r.detalhe = Undo-TmxPowercfgRecord   -Record $rec; $r.resultado = 'revertido' }
                'service'    { $r.detalhe = Undo-TmxServiceRecord    -Record $rec; $r.resultado = 'revertido' }
                'netadapter' { $r.detalhe = Undo-TmxNetAdapterRecord -Record $rec; $r.resultado = 'revertido' }
                'cmdlet'     { $r.detalhe = Undo-TmxCmdletRecord     -Record $rec; $r.resultado = 'revertido' }
                'bcdedit'    { $r.detalhe = Undo-TmxBcdeditRecord    -Record $rec; $r.resultado = 'revertido' }
                default {
                    $r.detalhe   = "tipo '$($rec.tipo)' ainda sem reversao automatica"
                    $r.resultado = 'pulado'
                }
            }
        } catch {
            $r.resultado = 'falha'
            $r.detalhe   = $_.Exception.Message
        }

        $resultados.Add($r)
        Write-TmxLog -Level INFO -Message "Reversao [$($r.resultado)] $($rec.alvo)" -Data @{ tweak = $rec.tweakId; detalhe = $r.detalhe }
    }

    $summary = [pscustomobject]@{
        statePath  = $resolvedStatePath
        total      = $resultados.Count
        revertidos = @($resultados | Where-Object { $_.resultado -eq 'revertido' }).Count
        falhas     = @($resultados | Where-Object { $_.resultado -eq 'falha' }).Count
        pulados    = @($resultados | Where-Object { $_.resultado -in @('pulado', 'simulado') }).Count
        itens      = $resultados
    }

    Write-TmxRollbackReport -Summary $summary
    $summary
}
