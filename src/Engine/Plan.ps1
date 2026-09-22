# Engine/Plan.ps1
# Monta o plano de aplicacao: avalia tier, controle, condicoes e preset de cada
# tweak do catalogo contra o perfil coletado. Porta adaptada de
# CS2Tuner Engine/Resolve-TweakPlan.ps1 (Resolve-TweakPlan / Get-TunerPlanSummary /
# Set-TunerPlanSelection / Set-TunerPlanConsent) para o schema do TweakMaxing.
#
# Status de cada item:
#   planejado    - elegivel para o preset atual e selecionado
#   opcional     - elegivel mas presets = [] (opt-in explicito do usuario por ID)
#   manual       - controle = info: vai para o guia, nao e selecionavel
#   bloqueado    - alguma condicao (requer/bloqueiaSe) nao foi satisfeita
#   foraDoPreset - preset atual nao inclui o tweak (ou preset notebook excluindo
#                  algo marcado bloqueiaSe os.isLaptop == true, mesmo fora de um notebook real)
#   folclore     - tier FOLCLORE: nunca selecionado automaticamente, mas o usuario PODE ligar a mao
#   irreversivel - reversivel = 'nenhuma': nao selecionado por padrao, exige confirmacao para ligar

$script:TmxPresetNomes = @('desktop', 'notebook', 'minimo')

function Get-TmxPresets {
    <#
    .SYNOPSIS
        Le src/config/preset.json (nome/descricao de cada preset).
    #>
    [CmdletBinding()]
    param(
        [string] $Path = (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'src\config\preset.json')
    )
    if (-not (Test-Path -LiteralPath $Path)) { throw "preset.json nao encontrado: $Path" }
    Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Test-TmxNotebookBloqueiaSeIsLaptop {
    <#
    .SYNOPSIS
        Verdadeiro se algum condicoes.bloqueiaSe do tweak e textualmente
        "os.isLaptop == true", independente do perfil atual.
    #>
    param($Tweak)
    foreach ($expr in @($Tweak.condicoes.bloqueiaSe)) {
        try {
            $c = ConvertFrom-TmxCondition -Expression $expr
        } catch {
            continue
        }
        if ($c.caminho -eq 'os.isLaptop' -and $c.operador -eq '==' -and "$($c.valor)" -ieq 'true') {
            return $true
        }
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
        [ValidateSet('desktop', 'notebook', 'minimo')]
        [string] $Preset = 'desktop',
        [switch] $IncludeState
    )

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

        # 3. Condicoes (avaliadas antes do preset: o usuario ve por que algo esta bloqueado mesmo fora do preset).
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
            if ($temTestAplicado) { $item.estadoAtual = (Test-TmxTweakApplied -Tweak $t -Profile $Profile).aplicado }
            $itens.Add($item); continue
        }

        # 4. Controle info: vai para o guia manual, nao e selecionavel.
        if ($t.controle -eq 'info') {
            $item.status = 'manual'
            $item.alternavel = $false
            $motivos.Add('controle info: instrucoes manuais, nao e aplicado automaticamente')
            $item.motivos = $motivos.ToArray()
            if ($temTestAplicado) { $item.estadoAtual = (Test-TmxTweakApplied -Tweak $t -Profile $Profile).aplicado }
            $itens.Add($item); continue
        }

        # 5. Preset notebook: exclui explicitamente qualquer tweak marcado bloqueiaSe
        #    os.isLaptop == true, mesmo quando o perfil atual nao e um notebook real -
        #    o preset 'notebook' e para notebooks, entao esses itens nunca entram nele.
        if ($Preset -eq 'notebook' -and (Test-TmxNotebookBloqueiaSeIsLaptop -Tweak $t)) {
            $item.status = 'foraDoPreset'
            $item.alternavel = $true
            $motivos.Add('excluido do preset notebook: prejudica notebooks (bloqueiaSe os.isLaptop == true), independente do perfil atual')
            $item.motivos = $motivos.ToArray()
            if ($temTestAplicado) { $item.estadoAtual = (Test-TmxTweakApplied -Tweak $t -Profile $Profile).aplicado }
            $itens.Add($item); continue
        }

        # 6. Presets e tier.
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
            if ($temTestAplicado) { $item.estadoAtual = (Test-TmxTweakApplied -Tweak $t -Profile $Profile).aplicado }
            $itens.Add($item); continue
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
