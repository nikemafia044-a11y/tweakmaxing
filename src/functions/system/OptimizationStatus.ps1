# functions/system/OptimizationStatus.ps1
# Backend de system.optimizationStatus: {disponiveis, ativos} para o cartao
# de status do Painel.
#
# APROXIMACAO DOCUMENTADA: o campo 'modo' do catalogo (leve/moderado/
# avancado/ultimate/extras) e adicionado por outra tarefa (Otimizacoes:
# modos, spec secao 6) que roda em paralelo nesta mesma branch. Enquanto um
# tweak nao tiver 'modo' preenchido, ele conta como "disponivel" sempre que
# nao for FOLCLORE (a aproximacao mais proxima de "modo != extras" possivel
# sem o campo) - assim que 'modo' existir no catalogo, a comparacao abaixo
# passa a refletir a regra real sem precisar mudar este arquivo.

function Get-TmxOptimizationAvailableTweaks {
    <#
    .SYNOPSIS
        Tweaks do catalogo contados como "disponiveis" (modo != extras;
        aproximacao acima enquanto 'modo' nao existir).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Catalog)

    @($Catalog | Where-Object {
        $temModo = ($_.PSObject.Properties.Name -contains 'modo') -and "$($_.modo)"
        if ($temModo) { "$($_.modo)" -cne 'extras' } else { "$($_.tier)" -cne 'FOLCLORE' }
    })
}

function Get-TmxOptimizationStatus {
    <#
    .SYNOPSIS
        { disponiveis, ativos }. 'ativos' reusa a mesma logica de estado do
        catalog.get (Update-TmxTweakPlan / item.estadoAtual, ja calculado por
        Test-TmxTweakApplied) em vez de reimplementar deteccao de estado.
    .DESCRIPTION
        So roda dentro de um job: como catalog.get, chama Update-TmxTweakPlan,
        que le o perfil e testa cada tweak contra o sistema real.
    #>
    [CmdletBinding()]
    param()

    $catalogo = $null
    try {
        $catalogo = @(Get-TmxTweakCatalogForUi)
    } catch {
        Write-TmxLog -Level WARN -Message "system.optimizationStatus: catalogo indisponivel: $($_.Exception.Message)"
        return @{ disponiveis = 0; ativos = 0 }
    }

    $disponiveisTweaks = @(Get-TmxOptimizationAvailableTweaks -Catalog $catalogo)
    $disponiveis = $disponiveisTweaks.Count

    $ativos = 0
    try {
        $st = Update-TmxTweakPlan
        $idsDisponiveis = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        foreach ($t in $disponiveisTweaks) { [void]$idsDisponiveis.Add("$($t.id)") }

        foreach ($item in @($st.plan.itens)) {
            if (-not $idsDisponiveis.Contains("$($item.id)")) { continue }
            if ($item.estadoAtual -eq $true) { $ativos++ }
        }
    } catch {
        Write-TmxLog -Level WARN -Message "system.optimizationStatus: nao foi possivel reler o estado atual: $($_.Exception.Message)"
    }

    @{ disponiveis = $disponiveis; ativos = $ativos }
}
