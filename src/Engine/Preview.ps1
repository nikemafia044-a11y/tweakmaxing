# Engine/Preview.ps1
# "Antes -> depois" por ACAO, sem tocar em nada. Alimenta a tela de confirmacao.
#
# Get-TmxPlanPreview -Plan -Profile [-Ids] ->
#   [{ tweakId, nome, tipo, alvo, antes, depois, reversao }]

function Get-TmxActionTarget {
    # Texto curto que identifica o alvo de uma acao.
    param([Parameter(Mandatory)] $Action)
    switch ("$($Action.tipo)") {
        'registry'      { "$($Action.path)::$($Action.name)" }
        'service'       { "servico $($Action.nome)" }
        'scheduledTask' { "tarefa $($Action.caminho)$($Action.nome)" }
        'appx'          { "appx $($Action.pacote)" }
        'powercfg'      { if ($Action.descricao) { "$($Action.descricao)" } else { "$($Action.subgrupo)/$($Action.configuracao)" } }
        'netadapter'    { "adaptador :: $(@($Action.chaves) -join '/')" }
        'bcdedit'       { "BCD {current} $($Action.opcao)" }
        'feature'       { "recurso $($Action.nome)" }
        'funcao'        { "$($Action.nome)" }
        default         { "$($Action.tipo)" }
    }
}

function Get-TmxActionGoal {
    <#
    .SYNOPSIS
        Valor-alvo de uma acao, como texto. Para 'funcao' usa o `esperado` que
        Test-Tmx<X> devolveu (ja calculado em $Verificacao); sem isso, o nome do tweak.
    #>
    param(
        [Parameter(Mandatory)] $Action,
        [Parameter(Mandatory)] $Tweak,
        $Verificacao
    )
    switch ("$($Action.tipo)") {
        'registry' {
            if ([bool](Get-TmxActionProp -Action $Action -Nome 'remove' -Padrao $false)) { '<removido>' }
            else { ConvertTo-TmxDisplayValue $Action.value }
        }
        'service'       { "$($Action.tipoInicio)$(if ([bool](Get-TmxActionProp -Action $Action -Nome 'parar' -Padrao $false)) { '/Stopped' })" }
        'scheduledTask' { "$($Action.estado)" }
        'appx'          { "<removido: $($Action.pacote)>" }
        'powercfg'      { "$($Action.valor)" }
        'netadapter'    { "$($Action.valorRegistro)" }
        'bcdedit'       { if ("$($Action.acao)" -eq 'set') { "$($Action.valor)" } else { '<removido>' } }
        'feature'       { "$($Action.estado)" }
        'funcao' {
            $esp = $null
            if ($Verificacao) { $esp = $Verificacao.esperado }
            if ($null -ne $esp -and "$esp" -ne '') { "$esp" } else { "$($Tweak.nome)" }
        }
        default { "$($Tweak.nome)" }
    }
}

function Get-TmxPlanPreview {
    <#
    .SYNOPSIS
        Lista, por acao dos tweaks selecionados, o estado atual e o estado alvo.
    .NOTES
        So leitura: nenhum registro de estado e criado.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Plan,
        [Parameter(Mandatory)] $Profile,
        [string[]] $Ids
    )

    $selecionados = @($Plan.itens | Where-Object { $_.selecionado })
    if ($Ids) { $selecionados = @($selecionados | Where-Object { $Ids -contains "$($_.id)" }) }
    $selecionados = @($selecionados | Sort-Object id)

    $linhas = New-Object 'System.Collections.Generic.List[object]'

    foreach ($item in $selecionados) {
        $t = $item.tweak
        foreach ($a in @($t.acoes)) {
            $chk = Test-TmxAction -Action $a -Tweak $t -Profile $Profile

            $antes = '<ausente>'
            if ($null -ne $chk.atual -and "$($chk.atual)" -ne '') { $antes = "$($chk.atual)" }

            $linhas.Add([pscustomobject]@{
                tweakId  = "$($t.id)"
                nome     = "$($t.nome)"
                tipo     = "$($a.tipo)"
                alvo     = (Get-TmxActionTarget -Action $a)
                antes    = $antes
                depois   = (Get-TmxActionGoal -Action $a -Tweak $t -Verificacao $chk)
                reversao = "$($t.reversivel)"
            })
        }
    }

    $linhas.ToArray()
}
