# Engine/Plan.ps1
# Monta o plano de aplicacao: avalia tier, controle, condicoes e preset de cada
# tweak do catalogo contra o perfil coletado. Porta adaptada de
# CS2Tuner Engine/Resolve-TweakPlan.ps1 (Resolve-TweakPlan / Get-TunerPlanSummary /
# Set-TunerPlanSelection / Set-TunerPlanConsent) para o schema do TweakMaxing.
#
# Status de cada item:
#   bloqueado    - alguma condicao (requer/bloqueiaSe) nao foi satisfeita. Avaliado
#                  ANTES de tier/reversibilidade: um FOLCLORE ou irreversivel que nem
#                  atende seu proprio 'requer' fica bloqueado, nao folclore/irreversivel.
#   folclore     - tier FOLCLORE (e condicoes ok): nunca selecionado automaticamente,
#                  mas o usuario PODE ligar a mao
#   irreversivel - reversivel = 'nenhuma' (e condicoes ok): nao selecionado por padrao,
#                  exige confirmacao para ligar
#   manual       - controle = info: vai para o guia, nao e selecionavel
#   foraDoPreset - preset atual nao inclui o tweak (ou preset notebook excluindo
#                  algo cujo bloqueiaSe e verdadeiro contra um perfil sintetico de
#                  notebook, mesmo fora de um notebook real - ver Test-TmxNotebookBloqueiaSeIsLaptop)
#   opcional     - elegivel mas presets = [] (opt-in explicito do usuario por ID), ou
#                  (presets por modo, Task T2) tweak sem 'modo' automatico (ausente ou
#                  'extras': entra so por ID, nunca num modo)
#   planejado    - elegivel para o preset atual e selecionado
#
# Presets por modo (Task T2, catalogo v2): 'leve', 'moderado', 'avancado' e 'ultimate'
# sao presets CUMULATIVOS (leve C moderado C avancado C ultimate), resolvidos pelo campo
# 'modo' do tweak em vez do array 'presets[]' usado pelos presets antigos (desktop/
# notebook/minimo, que continuam funcionando exatamente como antes). 'extras' NUNCA e
# um preset selecionavel: um tweak com modo 'extras' (ou sem 'modo') fica 'opcional' em
# qualquer preset de modo, disponivel so por selecao manual do ID.

$script:TmxPresetNomes = @('desktop', 'notebook', 'minimo')
$script:TmxModoOrdem   = @('leve', 'moderado', 'avancado', 'ultimate')

function Get-TmxModoCumulativo {
    <#
    .SYNOPSIS
        Devolve os modos incluidos num preset de modo cumulativo (ex.: 'avancado'
        -> leve, moderado, avancado). Array vazio se $Modo nao for um modo valido.
    #>
    param([string] $Modo)
    $idx = [array]::IndexOf($script:TmxModoOrdem, $Modo)
    if ($idx -lt 0) { return @() }
    , ($script:TmxModoOrdem[0..$idx])
}

function Get-TmxPresets {
    <#
    .SYNOPSIS
        Le src/config/preset.json (nome/descricao de cada preset).
    #>
    [CmdletBinding()]
    param([string] $Path)

    if (-not $Path) {
        # No artefato compilado nao existe src/config no disco: de la o
        # documento vem de $sync.configs (ver Get-TmxTweakPresetList).
        $raizRepo = if ($PSScriptRoot) { Split-Path (Split-Path $PSScriptRoot -Parent) -Parent } else { $null }
        if (-not $raizRepo) { throw 'preset.json nao encontrado: informe -Path.' }
        $Path = Join-Path $raizRepo 'src\config\preset.json'
    }
    if (-not (Test-Path -LiteralPath $Path)) { throw "preset.json nao encontrado: $Path" }
    Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Test-TmxNotebookBloqueiaSeIsLaptop {
    <#
    .SYNOPSIS
        Verdadeiro se alguma condicoes.bloqueiaSe do tweak e VERDADEIRA quando avaliada
        contra um perfil sintetico de notebook (os.isLaptop = $true), independente do
        perfil atualmente em maos.
    .NOTES
        Avaliacao semantica via Test-TmxCondition (nao comparacao textual da expressao):
        cobre variantes equivalentes como 'os.isLaptop != false', nao so '== true'.
        Qualquer condicao que nao fale de os.isLaptop resolve para $null (caminho
        ausente no perfil sintetico minimo) e portanto nao entra aqui.
    #>
    param($Tweak)
    $perfilNotebookSintetico = @{ os = @{ isLaptop = $true } }
    foreach ($expr in @($Tweak.condicoes.bloqueiaSe)) {
        try {
            $c = Test-TmxCondition -Expression $expr -Profile $perfilNotebookSintetico
        } catch {
            continue
        }
        if ($c.resultado -eq $true) { return $true }
    }
    $false
}

function Resolve-TmxPlan {
    <#
    .SYNOPSIS
        Monta o plano: avalia tier, controle, condicoes e preset de cada tweak contra o perfil.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Catalog,
        [Parameter(Mandatory)] $Profile,
        [ValidateSet('desktop', 'notebook', 'minimo', 'leve', 'moderado', 'avancado', 'ultimate')]
        [string] $Preset = 'desktop',
        [switch] $IncludeState
    )

    $ehPresetDeModo = $Preset -in $script:TmxModoOrdem
    $modosCumulativos = if ($ehPresetDeModo) { Get-TmxModoCumulativo -Modo $Preset } else { @() }

    $temTestAplicado = [bool]($IncludeState -and (Get-Command -Name 'Test-TmxTweakApplied' -ErrorAction SilentlyContinue))

    $itens = New-Object 'System.Collections.Generic.List[object]'

    foreach ($t in $Catalog) {
        $item = [pscustomobject]@{
            id               = $t.id
            nome             = $t.nome
            categoria        = $t.categoria
            tier             = $t.tier
            risco            = $t.risco
            reversivel       = $t.reversivel
            controle         = $t.controle
            status           = $null
            selecionado      = $false
            alternavel       = $false
            consentido       = $false
            exigeConfirmacao = $false
            motivos          = @()
            condicoes        = @()
            estadoAtual      = $null
            tweak            = $t
        }

        $motivos   = New-Object 'System.Collections.Generic.List[string]'
        $avaliadas = New-Object 'System.Collections.Generic.List[object]'

        # 0. Condicoes PRIMEIRO, antes de tier/reversibilidade: um tweak FOLCLORE ou
        #    irreversivel que nem atende seu proprio 'requer' (ou cai num 'bloqueiaSe')
        #    fica 'bloqueado' - nao 'folclore'/'irreversivel' - porque bloqueado e o
        #    unico status verdadeiramente nao-alternavel (o usuario nem pode tentar ligar).
        $bloqueado = $false
        foreach ($expr in @($t.condicoes.requer)) {
            $c = Test-TmxCondition -Expression $expr -Profile $Profile
            $avaliadas.Add($c)
            if ($c.resultado -ne $true) {
                $bloqueado = $true
                $txt = if ($c.motivo) { $c.motivo } else { "requisito nao atendido: $($c.expressao)" }
                if ($null -eq $c.resultado) { $txt += " (indeterminado: $($c.detalhe))" }
                $motivos.Add($txt)
            }
        }
        foreach ($expr in @($t.condicoes.bloqueiaSe)) {
            $c = Test-TmxCondition -Expression $expr -Profile $Profile
            $avaliadas.Add($c)
            if ($c.resultado -ne $false) {
                $bloqueado = $true
                $txt = if ($c.motivo) { $c.motivo } else { "bloqueado por: $($c.expressao)" }
                if ($null -eq $c.resultado) { $txt += " (indeterminado: $($c.detalhe) - bloqueio conservador)" }
                $motivos.Add($txt)
            }
        }
        $item.condicoes = $avaliadas.ToArray()

        if ($bloqueado) {
            $item.status = 'bloqueado'
            $item.alternavel = $false
            $item.motivos = $motivos.ToArray()
            # -IncludeState nao chama Test-TmxTweakApplied para bloqueado: o item nem e
            # elegivel, entao o estado "aplicado ou nao" e irrelevante para a decisao.
            $itens.Add($item); continue
        }

        # 1. Folclore: nunca selecionado automaticamente, mas o usuario pode ligar a mao.
        if ($t.tier -eq 'FOLCLORE') {
            $item.status = 'folclore'
            $item.alternavel = $true
            $motivos.Add('tier FOLCLORE: sem sustentacao empirica; disponivel na secao anti-folclore, pode ser ligado manualmente')
            $item.motivos = $motivos.ToArray()
            if ($temTestAplicado) { $item.estadoAtual = (Test-TmxTweakApplied -Tweak $t -Profile $Profile).aplicado }
            $itens.Add($item); continue
        }

        # 2. Irreversivel: nao selecionado por padrao, exige confirmacao explicita.
        if ("$($t.reversivel)" -eq 'nenhuma') {
            $item.status = 'irreversivel'
            $item.alternavel = $true
            $item.exigeConfirmacao = $true
            $motivos.Add('reversivel = nenhuma: recusado por padrao, exige confirmacao explicita para ligar')
            $item.motivos = $motivos.ToArray()
            if ($temTestAplicado) { $item.estadoAtual = (Test-TmxTweakApplied -Tweak $t -Profile $Profile).aplicado }
            $itens.Add($item); continue
        }

        # 3. Controle info: vai para o guia manual, nao e selecionavel.
        if ($t.controle -eq 'info') {
            $item.status = 'manual'
            $item.alternavel = $false
            $motivos.Add('controle info: instrucoes manuais, nao e aplicado automaticamente')
            $item.motivos = $motivos.ToArray()
            # -IncludeState nao chama Test-TmxTweakApplied para manual: nunca e aplicado
            # automaticamente, entao nao ha "estado aplicado" gerenciado pelo Engine.
            $itens.Add($item); continue
        }

        # 4. Preset notebook: exclui qualquer tweak cujo bloqueiaSe seja verdadeiro contra
        #    um perfil sintetico de notebook, mesmo quando o perfil atual nao e um
        #    notebook real - o preset 'notebook' e para notebooks, entao esses itens
        #    nunca entram nele. Ver Test-TmxNotebookBloqueiaSeIsLaptop (avaliacao
        #    semantica via Test-TmxCondition, cobre 'os.isLaptop != false' etc, nao so '== true').
        if ($Preset -eq 'notebook' -and (Test-TmxNotebookBloqueiaSeIsLaptop -Tweak $t)) {
            $item.status = 'foraDoPreset'
            $item.alternavel = $true
            $motivos.Add('excluido do preset notebook: a condicao bloqueiaSe do tweak seria verdadeira num notebook real, independente do perfil atual')
            $item.motivos = $motivos.ToArray()
            # -IncludeState nao chama Test-TmxTweakApplied para foraDoPreset: fora do
            # preset atual, o estado aplicado nao influencia a decisao do usuario aqui.
            $itens.Add($item); continue
        }

        # 5. Presets e tier.
        if ($ehPresetDeModo) {
            # Presets por modo (Task T2): cumulativo via campo 'modo', nao 'presets[]'.
            # Sem 'modo' (ausente/null) ou modo 'extras': nunca entra automaticamente
            # num modo, so por selecao manual do ID (mesmo tratamento de presets=[]).
            $modoDoTweak = "$($t.modo)"
            if (-not $modoDoTweak -or $modoDoTweak -cnotin $script:TmxModoOrdem) {
                $item.status = 'opcional'
                $item.alternavel = $true
                $motivos.Add("nao entra em modo automatico (modo '$modoDoTweak'); ative por ID se quiser")
                $item.motivos = $motivos.ToArray()
                if ($temTestAplicado) { $item.estadoAtual = (Test-TmxTweakApplied -Tweak $t -Profile $Profile).aplicado }
                $itens.Add($item); continue
            }
            if ($modoDoTweak -cnotin $modosCumulativos) {
                $item.status = 'foraDoPreset'
                $item.alternavel = $true
                $motivos.Add("fora do preset '$Preset' (modo do tweak: '$modoDoTweak')")
                $item.motivos = $motivos.ToArray()
                $itens.Add($item); continue
            }
        } else {
            $presetsDoTweak = @($t.presets)
            if ($presetsDoTweak.Count -eq 0) {
                $item.status = 'opcional'
                $item.alternavel = $true
                $motivos.Add('nao entra em preset automatico; ative por ID se quiser')
                $item.motivos = $motivos.ToArray()
                if ($temTestAplicado) { $item.estadoAtual = (Test-TmxTweakApplied -Tweak $t -Profile $Profile).aplicado }
                $itens.Add($item); continue
            }
            if ($Preset -notin $presetsDoTweak) {
                $item.status = 'foraDoPreset'
                $item.alternavel = $true
                $motivos.Add("fora do preset '$Preset' (disponivel em: $($presetsDoTweak -join ', '))")
                $item.motivos = $motivos.ToArray()
                # -IncludeState nao chama Test-TmxTweakApplied para foraDoPreset (ver item 4).
                $itens.Add($item); continue
            }
        }

        $item.status = 'planejado'
        $item.selecionado = $true
        $item.alternavel = $true
        $item.motivos = $motivos.ToArray()
        if ($temTestAplicado) { $item.estadoAtual = (Test-TmxTweakApplied -Tweak $t -Profile $Profile).aplicado }
        $itens.Add($item)
    }

    $plano = [pscustomobject]@{
        preset   = $Preset
        geradoEm = (Get-Date).ToString('o')
        itens    = $itens.ToArray()
        resumo   = $null
    }
    $plano.resumo = Get-TmxPlanSummary -Plan $plano
    Write-TmxLog -Level INFO -Message 'Plano resolvido' -Data @{ preset = $Preset; resumo = $plano.resumo }
    $plano
}

function Get-TmxPlanSummary {
    param([Parameter(Mandatory)] $Plan)
    $sel = @($Plan.itens | Where-Object { $_.selecionado })
    [pscustomobject]@{
        total               = @($Plan.itens).Count
        selecionados        = $sel.Count
        planejados          = @($Plan.itens | Where-Object { $_.status -eq 'planejado' }).Count
        opcionais           = @($Plan.itens | Where-Object { $_.status -eq 'opcional' }).Count
        manuais             = @($Plan.itens | Where-Object { $_.status -eq 'manual' }).Count
        bloqueados          = @($Plan.itens | Where-Object { $_.status -eq 'bloqueado' }).Count
        foraDoPreset        = @($Plan.itens | Where-Object { $_.status -eq 'foraDoPreset' }).Count
        folclore            = @($Plan.itens | Where-Object { $_.status -eq 'folclore' }).Count
        irreversiveis       = @($Plan.itens | Where-Object { $_.status -eq 'irreversivel' }).Count
        requerReboot        = @($sel | Where-Object { $_.tweak.requerReboot }).Count
        requerConsentimento = @($sel | Where-Object { $_.tweak.requerConsentimentoExtra }).Count
    }
}

function Set-TmxPlanConsent {
    <#
    .SYNOPSIS
        Marca consentimento extra dado para um item. Sem isto, o Engine nao aplica
        tweaks com requerConsentimentoExtra.
    #>
    param(
        [Parameter(Mandatory)] $Plan,
        [Parameter(Mandatory)] [string] $Id,
        [bool] $Consented = $true
    )
    $item = $Plan.itens | Where-Object { $_.id -ieq $Id } | Select-Object -First 1
    if (-not $item) { return [pscustomobject]@{ ok = $false; mensagem = "ID '$Id' nao existe no plano" } }
    $item.consentido = $Consented
    Write-TmxLog -Level INFO -Message "Consentimento $(if ($Consented) { 'dado' } else { 'retirado' }) para $($item.id)"
    [pscustomobject]@{ ok = $true; mensagem = "$($item.id): consentimento $(if ($Consented) { 'registrado' } else { 'retirado' })" }
}

function Set-TmxPlanSelection {
    <#
    .SYNOPSIS
        Liga/desliga um item por ID. So itens alternaveis (nao bloqueado).
    .OUTPUTS
        { ok, mensagem }
    #>
    param(
        [Parameter(Mandatory)] $Plan,
        [Parameter(Mandatory)] [string] $Id,
        [Parameter(Mandatory)] [bool] $Selected
    )
    $item = $Plan.itens | Where-Object { $_.id -ieq $Id } | Select-Object -First 1
    if (-not $item) { return [pscustomobject]@{ ok = $false; mensagem = "ID '$Id' nao existe no plano" } }
    if (-not $item.alternavel) {
        return [pscustomobject]@{ ok = $false; mensagem = "$($item.id) nao pode ser alternado (status: $($item.status)): $($item.motivos -join '; ')" }
    }
    $item.selecionado = $Selected
    $Plan.resumo = Get-TmxPlanSummary -Plan $Plan
    [pscustomobject]@{ ok = $true; mensagem = "$($item.id) $(if ($Selected) { 'ativado' } else { 'desativado' })" }
}
