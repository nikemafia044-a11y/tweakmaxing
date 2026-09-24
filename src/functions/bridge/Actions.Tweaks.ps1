# functions/bridge/Actions.Tweaks.ps1
# Acoes da aba "Ajustes": catalogo com selos de evidencia, preset, previa
# antes->depois, aplicacao e reversao (por item e por sessao).
#
# REGRA DE RUNSPACE: tudo que toca o Engine ou o Core roda DENTRO de um job.
# O estado de execucao ($script:TmxRun, $script:TmxStateRecords) vive na unica
# runspace do pool e a thread da janela nao o enxerga. A runspace da janela so
# mexe na SELECAO/CONSENTIMENTO do plano em cache ($sync.tweaks.plan), que e um
# objeto compartilhado, e le $sync.session para as pre-validacoes.
#
# Estado compartilhado:
#   $sync.tweaks = @{ catalog; profile; plan; preset; carregadoEm }

# ---------------------------------------------------------------------------
# Catalogo de teste
# ---------------------------------------------------------------------------

# Tweaks sinteticos usados pelos testes (Pester e GUI). Todos escrevem em
# HKCU:\Software\TweakMaxing_Tests\Gui, fora de qualquer area real do sistema,
# e passam pelo Test-TmxCatalog como qualquer tweak do catalogo de producao.
$script:TmxTweakTestJson = @'
{
  "tweaks": [
    {
      "id": "TST-001",
      "origem": { "winutil": null, "link": "https://example.invalid/tweakmaxing/tst-001" },
      "nome": "Teste - valor de registro",
      "descricao": "Tweak sintetico do modo de teste: grava um valor DWord na chave de testes do TweakMaxing.",
      "categoria": "Teste",
      "tier": "MEDIDO",
      "risco": "baixo",
      "presets": ["desktop", "notebook", "minimo"],
      "modo": "leve",
      "categoriasV2": ["geral", "desempenho"],
      "oQueFaz": "Grava o valor Valor=1 na chave de testes do TweakMaxing.",
      "beneficio": "Exercita o caminho de aplicacao e reversao sem tocar no sistema real.",
      "atencao": "Nenhuma.",
      "i18n": { "en": { "nome": "Test - registry value", "oQueFaz": "Writes Valor=1 to the TweakMaxing test key.", "beneficio": "Exercises the apply and undo path without touching the real system.", "atencao": "None." } },
      "controle": "checkbox",
      "opcoes": [],
      "grupo": null,
      "reversivel": "total",
      "requerReboot": false,
      "requerConsentimentoExtra": false,
      "consentimento": { "titulo": null, "tradeoff": null, "frase": null },
      "condicoes": { "requer": [], "bloqueiaSe": [] },
      "porque": "Escreve Valor=1 em HKCU:\\Software\\TweakMaxing_Tests\\Gui para exercitar o caminho de aplicacao e reversao sem tocar no sistema real.",
      "evidencia": "O efeito e verificavel lendo a propria chave: nao ha promessa de desempenho, e um alvo de teste.",
      "folclore": null,
      "instrucoes": null,
      "posAplicar": null,
      "acoes": [
        { "tipo": "registry", "path": "HKCU:\\Software\\TweakMaxing_Tests\\Gui", "name": "Valor", "value": 1, "valueType": "DWord" }
      ]
    },
    {
      "id": "TST-002",
      "origem": { "winutil": null, "link": "https://example.invalid/tweakmaxing/tst-002" },
      "nome": "Teste - chave liga/desliga",
      "descricao": "Tweak sintetico com controle de alternancia: ligar grava 1, desligar grava 0.",
      "categoria": "Teste",
      "tier": "MEDIDO",
      "risco": "baixo",
      "presets": [],
      "modo": "moderado",
      "categoriasV2": ["jogos"],
      "oQueFaz": "Liga (1) ou desliga (0) o valor Toggle na chave de testes.",
      "beneficio": "Exercita o liga/desliga de ponta a ponta.",
      "atencao": "Nenhuma.",
      "i18n": { "en": { "nome": "Test - on/off switch", "oQueFaz": "Turns the Toggle value on (1) or off (0) in the test key.", "beneficio": "Exercises on/off end to end.", "atencao": "None." } },
      "controle": "toggle",
      "opcoes": [],
      "grupo": null,
      "reversivel": "total",
      "requerReboot": false,
      "requerConsentimentoExtra": false,
      "consentimento": { "titulo": null, "tradeoff": null, "frase": null },
      "condicoes": { "requer": [], "bloqueiaSe": [] },
      "porque": "Escreve Toggle=1 (ligado) ou Toggle=0 (desligado) na chave de testes, exercitando toggleDesligar de ponta a ponta.",
      "evidencia": "O estado e lido de volta da propria chave a cada verificacao: e um alvo de teste, sem efeito no sistema.",
      "folclore": null,
      "instrucoes": null,
      "posAplicar": null,
      "acoes": [
        { "tipo": "registry", "path": "HKCU:\\Software\\TweakMaxing_Tests\\Gui", "name": "Toggle", "value": 1, "valueType": "DWord" }
      ],
      "toggleDesligar": [
        { "tipo": "registry", "path": "HKCU:\\Software\\TweakMaxing_Tests\\Gui", "name": "Toggle", "value": 0, "valueType": "DWord" }
      ]
    },
    {
      "id": "TST-003",
      "origem": { "winutil": null, "link": "https://example.invalid/tweakmaxing/tst-003" },
      "nome": "Teste - folclore",
      "descricao": "Tweak sintetico de tier FOLCLORE: nunca entra em preset e so e ligado a mao.",
      "categoria": "Teste",
      "tier": "FOLCLORE",
      "risco": "medio",
      "presets": [],
      "modo": "extras",
      "categoriasV2": ["desempenho"],
      "controle": "checkbox",
      "opcoes": [],
      "grupo": null,
      "reversivel": "total",
      "requerReboot": false,
      "requerConsentimentoExtra": false,
      "consentimento": { "titulo": null, "tradeoff": null, "frase": null },
      "condicoes": { "requer": [], "bloqueiaSe": [] },
      "porque": "Mantido apenas para exercitar a secao anti-folclore da interface.",
      "evidencia": "Nao ha medicao que sustente qualquer ganho: o item existe para testar o selo FOLCLORE e o aviso da interface.",
      "folclore": {
        "oQueE": "Um ajuste de teste que promete um sistema mais rapido gravando um valor qualquer no registro.",
        "porqueCircula": "Promessas simples com um valor de registro unico sao faceis de repetir e de copiar entre listas.",
        "porqueNaoRecomendamos": "Nao existe medicao controlada que mostre efeito; o valor nem e lido pelo Windows."
      },
      "instrucoes": null,
      "posAplicar": null,
      "acoes": [
        { "tipo": "registry", "path": "HKCU:\\Software\\TweakMaxing_Tests\\Gui", "name": "Folclore", "value": 1, "valueType": "DWord" }
      ]
    },
    {
      "id": "TST-004",
      "origem": { "winutil": null, "link": "https://example.invalid/tweakmaxing/tst-004" },
      "nome": "Teste - acao irreversivel",
      "descricao": "Tweak sintetico marcado como irreversivel: exige a frase de consentimento antes de ser aplicado.",
      "categoria": "Teste",
      "tier": "TECNICO",
      "risco": "alto",
      "presets": [],
      "modo": "extras",
      "categoriasV2": ["geral"],
      "controle": "checkbox",
      "opcoes": [],
      "grupo": null,
      "reversivel": "nenhuma",
      "requerReboot": false,
      "requerConsentimentoExtra": true,
      "consentimento": {
        "titulo": "Acao irreversivel de teste",
        "tradeoff": "Serve so para exercitar a porta de consentimento: nada no sistema real e alterado.",
        "frase": "ACEITO ACAO IRREVERSIVEL"
      },
      "condicoes": { "requer": [], "bloqueiaSe": [] },
      "porque": "Escreve Irreversivel=1 na chave de testes e declara reversivel=nenhuma para exercitar a porta de consentimento.",
      "evidencia": "Alvo de teste: o valor fica na chave de testes e a interface exige a frase exata antes de aplicar.",
      "folclore": null,
      "instrucoes": null,
      "posAplicar": null,
      "acoes": [
        { "tipo": "registry", "path": "HKCU:\\Software\\TweakMaxing_Tests\\Gui", "name": "Irreversivel", "value": 1, "valueType": "DWord" }
      ]
    },
    {
      "id": "TST-005",
      "origem": { "winutil": null, "link": "https://example.invalid/tweakmaxing/tst-005" },
      "nome": "Teste - risco alto do Ultimate",
      "descricao": "Tweak sintetico do modo Ultimate: risco alto, reversivel, exige a frase de consentimento.",
      "categoria": "Teste",
      "tier": "TECNICO",
      "risco": "alto",
      "presets": [],
      "modo": "ultimate",
      "categoriasV2": ["desempenho", "jogos"],
      "oQueFaz": "Grava UltimateAlto=1 na chave de testes do TweakMaxing.",
      "beneficio": "Exercita a confirmacao separada do modo Ultimate.",
      "atencao": "Risco alto de teste: pede a frase de consentimento antes de aplicar.",
      "i18n": { "en": { "nome": "Test - Ultimate high risk", "oQueFaz": "Writes UltimateAlto=1 to the TweakMaxing test key.", "beneficio": "Exercises the separate Ultimate confirmation.", "atencao": "Test high risk: asks for the consent phrase before applying." } },
      "controle": "checkbox",
      "opcoes": [],
      "grupo": null,
      "reversivel": "total",
      "requerReboot": true,
      "requerConsentimentoExtra": true,
      "consentimento": {
        "titulo": "Risco alto de teste",
        "tradeoff": "Serve so para exercitar a confirmacao do Ultimate: nada no sistema real e alterado.",
        "frase": "ACEITO O RISCO"
      },
      "condicoes": { "requer": [], "bloqueiaSe": [] },
      "porque": "Escreve UltimateAlto=1 na chave de testes para exercitar o modo Ultimate e a porta de consentimento.",
      "evidencia": "Alvo de teste: o valor fica na chave de testes, sem efeito no sistema.",
      "folclore": null,
      "instrucoes": null,
      "posAplicar": null,
      "acoes": [
        { "tipo": "registry", "path": "HKCU:\\Software\\TweakMaxing_Tests\\Gui", "name": "UltimateAlto", "value": 1, "valueType": "DWord" }
      ]
    }
  ]
}
'@

function Get-TmxTweakTestCatalog {
    <#
    .SYNOPSIS
        Os tweaks TST-* injetados no catalogo quando $sync.testMode esta ligado.
    #>
    [CmdletBinding()]
    param()
    (ConvertFrom-Json $script:TmxTweakTestJson).tweaks
}

# ---------------------------------------------------------------------------
# Fontes de dados (catalogo, presets, estado da sessao)
# ---------------------------------------------------------------------------

function Get-TmxTweakCatalogSource {
    <#
    .SYNOPSIS
        Tweaks do catalogo de producao: todo documento 'tweaks*' de
        $sync.configs quando ja carregado (dev runner e artefato compilado),
        senao os tweaks*.json do disco.
    #>
    [CmdletBinding()]
    param()

    $documentos = New-Object 'System.Collections.Generic.List[object]'
    foreach ($nome in @(Get-TmxConfigDocumentName -Pattern 'tweaks*')) {
        $doc = Get-TmxConfigDocument -Name $nome
        if ($null -ne $doc) { $documentos.Add($doc) }
    }

    if ($documentos.Count -gt 0) {
        return (Get-TmxCatalog -Documents $documentos.ToArray())
    }

    # Sem $sync e sem webRoot (modulo importado direto): caminho padrao do disco.
    @(Get-TmxCatalog)
}

function Get-TmxTweakCatalogForUi {
    <#
    .SYNOPSIS
        Catalogo que a aba Ajustes enxerga: producao + os TST-* do modo de teste.
        Valida com Test-TmxCatalog e lanca com as 5 primeiras mensagens.
    #>
    [CmdletBinding()]
    param()

    $lista = New-Object 'System.Collections.Generic.List[object]'
    foreach ($t in @(Get-TmxTweakCatalogSource)) { $lista.Add($t) }

    if ($null -ne $sync -and $sync.testMode) {
        foreach ($t in @(Get-TmxTweakTestCatalog)) { $lista.Add($t) }
    }

    $catalogo = $lista.ToArray()

    $v = Test-TmxCatalog -Catalog $catalogo
    if (-not $v.ok) {
        $primeiros = @($v.erros | Select-Object -First 5)
        throw "catalogo invalido ($($v.erros.Count) erro(s)): $($primeiros -join ' | ')"
    }

    $catalogo
}

function Get-TmxTweakPresetList {
    <#
    .SYNOPSIS
        preset.json (nome/descricao de cada preset), pelo cache ou pelo disco.
    #>
    [CmdletBinding()]
    param()

    $doc = Get-TmxConfigDocument -Name 'preset'
    if ($null -ne $doc) { return $doc }
    Get-TmxPresets
}

function Get-TmxTweakRunRecords {
    <#
    .SYNOPSIS
        Registros do state.json da sessao atual (vazio quando nao ha sessao).
    .NOTES
        Le do ARQUIVO, nao de $script:TmxStateRecords: assim a mesma funcao
        serve a qualquer runspace, e o Save-TmxState persiste a cada escrita.
    #>
    [CmdletBinding()]
    param()

    $caminho = $null
    if ($null -ne $sync -and $null -ne $sync.session) { $caminho = "$($sync.session.statePath)" }
    if (-not $caminho -or -not (Test-Path -LiteralPath $caminho)) { return @() }

    try {
        @(Import-TmxState -StatePath $caminho)
    } catch {
        Write-TmxLog -Level WARN -Message "Nao foi possivel ler o state.json da sessao: $($_.Exception.Message)"
        @()
    }
}

# ---------------------------------------------------------------------------
# Plano em cache e payload da interface
# ---------------------------------------------------------------------------

function Get-TmxTweakState {
    <#
    .SYNOPSIS
        O bloco $sync.tweaks, criado na primeira chamada.
    #>
    [CmdletBinding()]
    param()

    if ($null -eq $sync) { throw 'Get-TmxTweakState: $sync nao existe (bootstrap nao rodou).' }
    if ($null -eq $sync.tweaks) {
        $sync.tweaks = @{
            catalog     = $null
            profile     = $null
            plan        = $null
            preset      = 'desktop'
            carregadoEm = $null
        }
    }
    $sync.tweaks
}

function Get-TmxTweakUiPresetNames {
    <#
    .SYNOPSIS
        Presets aceitos pela aba Otimizacoes: os antigos (desktop, notebook,
        minimo) e os modos cumulativos da v2 (leve, moderado, avancado,
        ultimate). 'extras' nunca e um preset.
    #>
    [CmdletBinding()]
    param()
    , @('desktop', 'notebook', 'minimo', 'leve', 'moderado', 'avancado', 'ultimate')
}

function Get-TmxTweakUiModeNames {
    <#
    .SYNOPSIS
        Os quatro modos cumulativos da v2, na ordem (leve C moderado C avancado C ultimate).
    #>
    [CmdletBinding()]
    param()
    , @('leve', 'moderado', 'avancado', 'ultimate')
}

function Update-TmxTweakPlan {
    <#
    .SYNOPSIS
        Garante catalogo e perfil em cache e (re)resolve o plano para o preset.
    .NOTES
        So roda dentro de um job: Get-TmxProfile e Test-TmxTweakApplied leem o
        sistema e podem demorar segundos.
    #>
    [CmdletBinding()]
    param([string] $Preset)

    $st = Get-TmxTweakState

    if (-not $Preset) { $Preset = "$($st.preset)" }
    if ($Preset -cnotin (Get-TmxTweakUiPresetNames)) { $Preset = 'desktop' }

    if ($null -eq $st.catalog) { $st.catalog = Get-TmxTweakCatalogForUi }
    if ($null -eq $st.profile) { $st.profile = Get-TmxProfile }

    $st.plan        = Resolve-TmxPlan -Catalog $st.catalog -Profile $st.profile -Preset $Preset -IncludeState
    $st.preset      = $Preset
    $st.carregadoEm = (Get-Date).ToString('o')
    $st
}

function Get-TmxTweakCategoryRank {
    <#
    .SYNOPSIS
        0 para as categorias comuns, 1 para as de 'Jogos / ...' (que vao no fim).
    #>
    [CmdletBinding()]
    param([string] $Nome)
    if ("$Nome" -like 'Jogos*') { return 1 }
    0
}

function ConvertTo-TmxUiTweak {
    <#
    .SYNOPSIS
        Item do plano -> objeto enxuto para o JSON da interface.
    .DESCRIPTION
        O item do plano carrega o tweak inteiro (acoes, condicoes avaliadas);
        nada disso vai para a janela: o payload leva so o que a tela desenha.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Item,
        $Registros
    )

    $t = $Item.tweak

    $opcoes = New-Object 'System.Collections.Generic.List[object]'
    foreach ($o in @($t.opcoes)) {
        if ($null -eq $o) { continue }
        $opcoes.Add(@{ valor = "$($o.valor)"; rotulo = "$($o.rotulo)" })
    }

    $folclore = $null
    if ($t.folclore) {
        $folclore = @{
            oQueE                 = "$($t.folclore.oQueE)"
            porqueCircula         = "$($t.folclore.porqueCircula)"
            porqueNaoRecomendamos = "$($t.folclore.porqueNaoRecomendamos)"
        }
    }

    # Campos da v2 (modo, filtros e textos didaticos). Um tweak sem 'modo' e
    # tratado como 'extras' (nunca entra num modo, ver Engine/Plan.ps1).
    $modo = ''
    if ($t.PSObject.Properties['modo'] -and $null -ne $t.modo) { $modo = "$($t.modo)" }
    if (-not $modo) { $modo = 'extras' }

    $categoriasV2 = New-Object 'System.Collections.Generic.List[string]'
    if ($t.PSObject.Properties['categoriasV2'] -and $null -ne $t.categoriasV2) {
        foreach ($cv2 in @($t.categoriasV2)) { if ("$cv2") { $categoriasV2.Add("$cv2") } }
    }

    $textoV2 = @{}
    foreach ($campo in 'oQueFaz', 'beneficio', 'atencao') {
        $valor = ''
        if ($t.PSObject.Properties[$campo] -and $null -ne $t.$campo) { $valor = "$($t.$campo)" }
        $textoV2[$campo] = $valor
    }

    # i18n.en: so os campos de texto que a tela desenha, sempre como string.
    $en = @{}
    if ($t.PSObject.Properties['i18n'] -and $null -ne $t.i18n -and $t.i18n.PSObject.Properties['en'] -and $null -ne $t.i18n.en) {
        foreach ($campo in 'nome', 'descricao', 'oQueFaz', 'beneficio', 'atencao') {
            $prop = $t.i18n.en.PSObject.Properties[$campo]
            if ($null -ne $prop -and "$($prop.Value)") { $en[$campo] = "$($prop.Value)" }
        }
    }

    $temUndo = $false
    foreach ($rec in @($Registros)) {
        if ("$($rec.tweakId)" -ieq "$($t.id)" -and "$($rec.status)" -in @('aplicado', 'falha')) {
            $temUndo = $true
            break
        }
    }

    @{
        id                       = "$($t.id)"
        nome                     = "$($t.nome)"
        descricao                = "$($t.descricao)"
        categoria                = "$($t.categoria)"
        tier                     = "$($t.tier)"
        risco                    = "$($t.risco)"
        reversivel               = "$($t.reversivel)"
        controle                 = "$($t.controle)"
        opcoes                   = $opcoes.ToArray()
        opcaoSelecionada         = "$($t.opcaoSelecionada)"
        grupo                    = "$($t.grupo)"
        status                   = "$($Item.status)"
        selecionado              = [bool]$Item.selecionado
        alternavel               = [bool]$Item.alternavel
        consentido               = [bool]$Item.consentido
        exigeConfirmacao         = [bool]$Item.exigeConfirmacao
        motivos                  = @(@($Item.motivos) | ForEach-Object { "$_" })
        estadoAtual              = $Item.estadoAtual
        requerReboot             = [bool]$t.requerReboot
        requerConsentimentoExtra = [bool]$t.requerConsentimentoExtra
        consentimento            = @{
            titulo   = "$($t.consentimento.titulo)"
            tradeoff = "$($t.consentimento.tradeoff)"
            frase    = (Get-TmxTweakConsentPhrase -Tweak $t)
        }
        porque                   = "$($t.porque)"
        evidencia                = "$($t.evidencia)"
        folclore                 = $folclore
        instrucoes               = "$($t.instrucoes)"
        origem                   = @{ link = "$($t.origem.link)" }
        temUndo                  = $temUndo
        modo                     = $modo
        categoriasV2             = $categoriasV2.ToArray()
        oQueFaz                  = $textoV2['oQueFaz']
        beneficio                = $textoV2['beneficio']
        atencao                  = $textoV2['atencao']
        i18n                     = @{ en = $en }
    }
}

function Get-TmxTweakCatalogPayload {
    <#
    .SYNOPSIS
        O que catalog.get / preset.apply devolvem: presets, preset atual, resumo
        e as categorias com seus itens.
    .NOTES
        Ordem das categorias: as comuns primeiro (alfabetica), depois as de
        'Jogos / ...' (tambem alfabetica) - elas sao um bloco a parte do catalogo.
    #>
    [CmdletBinding()]
    param()

    $st = Get-TmxTweakState
    if ($null -eq $st.plan) { throw 'catalogo ainda nao foi carregado' }

    $registros = Get-TmxTweakRunRecords

    $porCategoria = [ordered]@{}
    foreach ($item in @($st.plan.itens)) {
        $cat = "$($item.categoria)"
        if (-not $cat) { $cat = 'Outros' }
        if (-not $porCategoria.Contains($cat)) {
            $porCategoria[$cat] = New-Object 'System.Collections.Generic.List[object]'
        }
        $porCategoria[$cat].Add((ConvertTo-TmxUiTweak -Item $item -Registros $registros))
    }

    $nomes = @(@($porCategoria.Keys) | Sort-Object @{ Expression = { Get-TmxTweakCategoryRank -Nome $_ } }, @{ Expression = { $_ } })

    $categorias = New-Object 'System.Collections.Generic.List[object]'
    foreach ($nome in $nomes) {
        $categorias.Add(@{ nome = "$nome"; itens = $porCategoria[$nome].ToArray() })
    }

    @{
        presets    = (Get-TmxTweakPresetList)
        preset     = "$($st.preset)"
        resumo     = $st.plan.resumo
        categorias = $categorias.ToArray()
    }
}

# ---------------------------------------------------------------------------
# Consentimento, variantes de tweak e pre-validacao
# ---------------------------------------------------------------------------

function Get-TmxTweakConsentPhrase {
    <#
    .SYNOPSIS
        Frase exigida para um tweak. Um irreversivel sem frase propria cai na
        frase padrao - nunca fica sem porta de consentimento.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Tweak)

    $frase = "$($Tweak.consentimento.frase)"
    if (-not $frase -and "$($Tweak.reversivel)" -eq 'nenhuma') { $frase = 'ACEITO ACAO IRREVERSIVEL' }
    $frase
}

function Get-TmxTweakPlanItem {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Id)

    $st = Get-TmxTweakState
    if ($null -eq $st.plan) { return $null }
    @($st.plan.itens | Where-Object { "$($_.id)" -ieq $Id }) | Select-Object -First 1
}

function Get-TmxTweakEffectiveActions {
    <#
    .SYNOPSIS
        Acoes que serao de fato aplicadas: as do tweak, ou as da opcao escolhida
        quando o controle e combobox.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Tweak)

    if ("$($Tweak.controle)" -eq 'combobox') {
        $valor = "$($Tweak.opcaoSelecionada)"
        if ($valor) {
            $op = @($Tweak.opcoes | Where-Object { "$($_.valor)" -ceq $valor }) | Select-Object -First 1
            if ($op) { return @($op.acoes) }
        }
    }
    @($Tweak.acoes)
}

function New-TmxTweakVariant {
    <#
    .SYNOPSIS
        Copia do tweak com outro conjunto de acoes (opcao de combobox, desligar
        de um toggle). Mantem o id para que o state.json e o Undo continuem
        apontando para o mesmo ajuste.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Tweak,
        $Acoes
    )

    $copia = $Tweak.PSObject.Copy()
    $copia | Add-Member -NotePropertyName acoes -NotePropertyValue @($Acoes) -Force
    $copia
}

function New-TmxTweakSingleItemPlan {
    <#
    .SYNOPSIS
        Plano de um item so, para aplicar um tweak (ou uma variante dele) pelo
        mesmo Invoke-TmxPlan que aplica o plano inteiro.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Item,
        $Tweak,
        [bool] $Consentido
    )

    if ($null -eq $Tweak) { $Tweak = $Item.tweak }

    $novo = [pscustomobject]@{
        id               = "$($Item.id)"
        nome             = "$($Item.nome)"
        categoria        = "$($Item.categoria)"
        tier             = "$($Item.tier)"
        risco            = "$($Item.risco)"
        reversivel       = "$($Item.reversivel)"
        controle         = "$($Item.controle)"
        status           = "$($Item.status)"
        selecionado      = $true
        alternavel       = [bool]$Item.alternavel
        consentido       = $Consentido
        exigeConfirmacao = [bool]$Item.exigeConfirmacao
        motivos          = @()
        condicoes        = @()
        estadoAtual      = $Item.estadoAtual
        tweak            = $Tweak
    }

    [pscustomobject]@{
        preset   = "$((Get-TmxTweakState).preset)"
        geradoEm = (Get-Date).ToString('o')
        itens    = @($novo)
        resumo   = $null
    }
}

function New-TmxTweakEffectivePlan {
    <#
    .SYNOPSIS
        Plano transitorio com um item por id, ja com as ACOES EFETIVAS (as da
        opcao escolhida, quando o controle e combobox).
    .DESCRIPTION
        A previa precisa mostrar o que sera de fato gravado: Get-TmxPlanPreview
        le $tweak.acoes, que num combobox esta vazio - as acoes moram em
        opcoes[].acoes. Este plano fecha essa diferenca.
    #>
    [CmdletBinding()]
    param([string[]] $Ids)

    $itens = New-Object 'System.Collections.Generic.List[object]'
    foreach ($id in @($Ids)) {
        $item = Get-TmxTweakPlanItem -Id "$id"
        if ($null -eq $item) { continue }
        $acoes = Get-TmxTweakEffectiveActions -Tweak $item.tweak
        $tw    = New-TmxTweakVariant -Tweak $item.tweak -Acoes $acoes
        $umSo  = New-TmxTweakSingleItemPlan -Item $item -Tweak $tw -Consentido ([bool]$item.consentido)
        foreach ($x in @($umSo.itens)) { $itens.Add($x) }
    }

    [pscustomobject]@{
        preset   = "$((Get-TmxTweakState).preset)"
        geradoEm = (Get-Date).ToString('o')
        itens    = $itens.ToArray()
        resumo   = $null
    }
}

function ConvertTo-TmxTweakParams {
    <#
    .SYNOPSIS
        Valida e normaliza os parametros que a tela manda para um ajuste de
        acao 'funcao' que pergunta algo antes de rodar.
    .DESCRIPTION
        So dois ajustes aceitam parametros vindos da interface:
          APM-006 (remover bloatware)     -> { manter: string[] }
          APM-007 (apps de jogos da MS)   -> { usaGamePass: bool }
        Qualquer outro id e recusado: a janela nao reescreve acoes arbitrarias.
    .OUTPUTS
        [pscustomobject] com os parametros normalizados.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Id,
        $Parametros
    )

    switch -Exact ($Id.ToUpperInvariant()) {
        'APM-006' {
            $manter = New-Object 'System.Collections.Generic.List[string]'
            $bruto = $null
            if ($null -ne $Parametros) { $bruto = Get-TmxActionProp -Action $Parametros -Nome 'manter' -Padrao @() }
            foreach ($m in @($bruto)) {
                $s = "$m".Trim()
                if (-not $s) { continue }
                if ($s -notmatch '^[A-Za-z0-9._-]{1,200}$') { throw "APM-006: item invalido em 'manter': '$s'" }
                $manter.Add($s)
            }
            return [pscustomobject]@{ manter = $manter.ToArray() }
        }
        'APM-007' {
            $usa = $false
            if ($null -ne $Parametros) { $usa = [bool](Get-TmxActionProp -Action $Parametros -Nome 'usaGamePass' -Padrao $false) }
            return [pscustomobject]@{ usaGamePass = $usa }
        }
        default { throw "$Id nao aceita parametros" }
    }
}

function Set-TmxTweakItemParams {
    <#
    .SYNOPSIS
        Troca os 'parametros' das acoes 'funcao' de um item do plano, numa
        COPIA do tweak (o objeto do catalogo em cache nao e alterado).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Item,
        [Parameter(Mandatory)] $Parametros
    )

    $acoes = New-Object 'System.Collections.Generic.List[object]'
    foreach ($a in @($Item.tweak.acoes)) {
        if ($null -eq $a) { continue }
        if ("$($a.tipo)" -eq 'funcao') {
            $c = $a.PSObject.Copy()
            $c | Add-Member -NotePropertyName parametros -NotePropertyValue $Parametros -Force
            $acoes.Add($c)
        } else {
            $acoes.Add($a)
        }
    }
    $Item.tweak = New-TmxTweakVariant -Tweak $Item.tweak -Acoes $acoes.ToArray()
    $Item
}

function Get-TmxTweakBloatwareList {
    <#
    .SYNOPSIS
        Lista para a pergunta do APM-006: os appx do catalogo appx.json, com
        'instalado' quando for possivel ler (fora do modo de teste).
    .NOTES
        No modo de teste o sistema nao e consultado: 'instalado' vem $null e a
        tela mostra o catalogo inteiro.
    #>
    [CmdletBinding()]
    param()

    $instalados = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $consultou = $false
    if (-not ($null -ne $sync -and $sync.testMode)) {
        try {
            foreach ($x in @(Get-TmxV2BloatwareInstalado -Parametros ([pscustomobject]@{ manter = @() }))) {
                if ($x) { [void]$instalados.Add("$($x.id)") }
            }
            $consultou = $true
        } catch {
            Write-TmxLog -Level WARN -Message "Nao foi possivel listar os appx instalados: $($_.Exception.Message)"
        }
    }

    $lista = New-Object 'System.Collections.Generic.List[object]'
    foreach ($app in @(Get-TmxV2AppxCatalog)) {
        if ($null -eq $app) { continue }
        $inst = $null
        if ($consultou) { $inst = $instalados.Contains("$($app.id)") }
        $lista.Add(@{
            id        = "$($app.id)"
            nome      = "$($app.nome)"
            descricao = "$($app.descricao)"
            pacote    = "$($app.pacote)"
            instalado = $inst
        })
    }
    , $lista.ToArray()
}

function Assert-TmxTweakTestModeIds {
    <#
    .SYNOPSIS
        Trava de seguranca do modo de teste: a suite roda na maquina real, entao
        nada fora dos tweaks sinteticos TST-* pode ser aplicado.
    #>
    [CmdletBinding()]
    param([string[]] $Ids)

    if ($null -eq $sync -or -not $sync.testMode) { return }
    foreach ($id in @($Ids)) {
        if ("$id" -notlike 'TST-*') { throw 'modo de teste: apenas tweaks TST-*' }
    }
}

function Test-TmxTweakSessionPronta {
    <#
    .SYNOPSIS
        A sessao esta pronta (pasta da execucao + ponto de restauracao)?
    .DESCRIPTION
        Mesma condicao de Assert-TmxTweakSession, sem lancar: serve a quem
        precisa DECIDIR no meio de um laco (Invoke-TmxTweakApplyIds) em vez
        de abortar o job inteiro.
    .OUTPUTS
        [bool]
    #>
    [CmdletBinding()]
    param()
    [bool]($null -ne $sync -and $null -ne $sync.session -and $sync.session.pronto)
}

function Assert-TmxTweakSession {
    <#
    .SYNOPSIS
        Nada e aplicado sem sessao pronta (pasta da execucao + ponto de restauracao).
    #>
    [CmdletBinding()]
    param()

    if (-not (Test-TmxTweakSessionPronta)) {
        throw 'sessao sem ponto de restauracao: abra a sessao antes de aplicar'
    }
}

function Assert-TmxTweakApplyReady {
    <#
    .SYNOPSIS
        Pre-validacao sincrona de plan.apply: sessao, ids existentes, ids
        selecionados e consentimento dado. Lanca com a lista de ids culpados.
    #>
    [CmdletBinding()]
    param([string[]] $Ids)

    # A sessao vem PRIMEIRO: e a guarda de reversibilidade, e a mensagem que a
    # interface mostra quando nada foi aberto ainda precisa ser sobre ela.
    Assert-TmxTweakSession

    $st = Get-TmxTweakState
    if ($null -eq $st.plan) { throw 'catalogo ainda nao foi carregado' }

    if (@($Ids).Count -eq 0) { throw 'nenhum ajuste selecionado' }
    Assert-TmxTweakTestModeIds -Ids $Ids

    $ausentes        = New-Object 'System.Collections.Generic.List[string]'
    $naoSelecionados = New-Object 'System.Collections.Generic.List[string]'
    $semConsentir    = New-Object 'System.Collections.Generic.List[string]'

    foreach ($id in @($Ids)) {
        $item = Get-TmxTweakPlanItem -Id "$id"
        if ($null -eq $item) { $ausentes.Add("$id"); continue }
        if (-not $item.selecionado) { $naoSelecionados.Add("$id"); continue }
        if ($item.tweak.requerConsentimentoExtra -and -not $item.consentido) { $semConsentir.Add("$id") }
    }

    if ($ausentes.Count -gt 0)        { throw "ids fora do catalogo: $($ausentes.ToArray() -join ', ')" }
    if ($naoSelecionados.Count -gt 0) { throw "ids nao selecionados: $($naoSelecionados.ToArray() -join ', ')" }
    if ($semConsentir.Count -gt 0)    { throw "consentimento pendente: $($semConsentir.ToArray() -join ', ')" }
}

# ---------------------------------------------------------------------------
# Aplicacao e reversao (corpo dos jobs)
# ---------------------------------------------------------------------------

function Invoke-TmxTweakApplyIds {
    <#
    .SYNOPSIS
        Aplica os ids um a um, reportando progresso entre eles.
    .DESCRIPTION
        Um Invoke-TmxPlan por id (plano de um item so) em vez de um unico
        Invoke-TmxPlan com -Ids: e o que permite emitir job.progress a cada
        tweak e usar as acoes da opcao escolhida em um combobox.

        A sessao e reconferida ANTES DE CADA id, nao so uma vez na entrada
        (Assert-TmxTweakApplyReady, la na ponte). Uma lista longa leva
        minutos, e nesse intervalo a sessao pode acabar - a janela fechou, o
        usuario reverteu tudo, o run foi encerrado. A partir do id em que
        isso for detectado nada mais e aplicado: o restante sai como
        'pulado' com detalhe 'sessao encerrada' e a interface mostra
        exatamente onde a fila parou.
    .OUTPUTS
        { itens[], aplicados, jaAplicados, falhas, pulados, requerReboot }
    #>
    [CmdletBinding()]
    param([string[]] $Ids)

    $st    = Get-TmxTweakState
    $itens = New-Object 'System.Collections.Generic.List[object]'
    $total = @($Ids).Count
    $i     = 0
    $parou = $false

    foreach ($id in @($Ids)) {
        $i++
        $item = Get-TmxTweakPlanItem -Id "$id"
        if ($null -eq $item) { continue }

        if (-not $parou -and -not (Test-TmxTweakSessionPronta)) {
            $parou = $true
            Write-TmxLog -Level WARN -Message 'Sessao encerrada no meio da aplicacao; ids restantes pulados' -Data @{ apartirDe = "$($item.id)" }
        }
        if ($parou) {
            $itens.Add([pscustomobject]@{
                id           = "$($item.id)"
                nome         = "$($item.nome)"
                tier         = "$($item.tier)"
                status       = 'pulado'
                detalhe      = 'sessao encerrada'
                antes        = $null
                depois       = $null
                registros    = 0
                requerReboot = $false
                avisos       = @()
            })
            continue
        }

        Send-TmxJobProgress -Pct ([int](($i - 1) / [math]::Max($total, 1) * 90)) -Status "Aplicando $($item.id) - $($item.nome)"

        $acoes  = Get-TmxTweakEffectiveActions -Tweak $item.tweak
        $tweak  = New-TmxTweakVariant -Tweak $item.tweak -Acoes $acoes
        $plano  = New-TmxTweakSingleItemPlan -Item $item -Tweak $tweak -Consentido ([bool]$item.consentido)
        $r      = Invoke-TmxPlan -Plan $plano -Profile $st.profile

        foreach ($linha in @($r.itens)) { $itens.Add($linha) }
    }

    $arr = $itens.ToArray()
    @{
        itens        = @($arr | ForEach-Object {
            @{
                id           = "$($_.id)"
                nome         = "$($_.nome)"
                tier         = "$($_.tier)"
                status       = "$($_.status)"
                detalhe      = "$($_.detalhe)"
                antes        = "$($_.antes)"
                depois       = "$($_.depois)"
                registros    = [int]$_.registros
                requerReboot = [bool]$_.requerReboot
                avisos       = @(@($_.avisos) | ForEach-Object { "$_" })
            }
        })
        aplicados    = @($arr | Where-Object { "$($_.status)" -in @('aplicado', 'aplicadoNaoVerificado') }).Count
        jaAplicados  = @($arr | Where-Object { "$($_.status)" -eq 'jaAplicado' }).Count
        falhas       = @($arr | Where-Object { "$($_.status)" -eq 'falha' }).Count
        pulados      = @($arr | Where-Object { "$($_.status)" -in @('semConsentimento', 'naoAplicavel', 'naoSuportado', 'simulado', 'pulado') }).Count
        requerReboot = (@($arr | Where-Object { ("$($_.status)" -in @('aplicado', 'aplicadoNaoVerificado')) -and $_.requerReboot }).Count -gt 0)
    }
}

function ConvertTo-TmxUndoSummary {
    <#
    .SYNOPSIS
        Resumo do Undo-TweakMaxing em forma enxuta para o JSON da interface.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Summary)

    # foreach direto, sem @(...): o .itens do Undo-TweakMaxing e uma
    # System.Collections.Generic.List[object], e @() sobre uma List generica
    # lanca ArgumentException ("os tipos de argumento nao correspondem") no PS 5.1.
    $linhas = New-Object 'System.Collections.Generic.List[object]'
    foreach ($it in $Summary.itens) {
        if ($null -eq $it) { continue }
        $linhas.Add(@{
            tweakId   = "$($it.tweakId)"
            tipo      = "$($it.tipo)"
            alvo      = "$($it.alvo)"
            resultado = "$($it.resultado)"
            detalhe   = "$($it.detalhe)"
        })
    }

    @{
        statePath  = "$($Summary.statePath)"
        total      = [int]$Summary.total
        revertidos = [int]$Summary.revertidos
        falhas     = [int]$Summary.falhas
        pulados    = [int]$Summary.pulados
        itens      = $linhas.ToArray()
    }
}

function Get-TmxTweakRunList {
    <#
    .SYNOPSIS
        Execucoes registradas em <home>/runs com state.json, da mais nova para a
        mais antiga.
    #>
    [CmdletBinding()]
    param()

    $raiz = Get-TmxRunsRoot
    if (-not (Test-Path -LiteralPath $raiz)) { return @() }

    $atual = $null
    if ($null -ne $sync -and $null -ne $sync.session) { $atual = "$($sync.session.runId)" }

    $lista = New-Object 'System.Collections.Generic.List[object]'
    $dirs  = @(Get-ChildItem -LiteralPath $raiz -Directory -ErrorAction SilentlyContinue |
               Sort-Object CreationTimeUtc, Name -Descending)

    foreach ($d in $dirs) {
        $state = Join-Path $d.FullName 'state.json'
        if (-not (Test-Path -LiteralPath $state)) { continue }

        $registros = @()
        try { $registros = @(Import-TmxState -StatePath $state) } catch { $registros = @() }

        $lista.Add(@{
            runId      = "$($d.Name)"
            criadoEm   = $d.CreationTimeUtc.ToString('o')
            registros  = $registros.Count
            aplicados  = @($registros | Where-Object { "$($_.status)" -eq 'aplicado' }).Count
            revertidos = @($registros | Where-Object { "$($_.status)" -eq 'revertido' }).Count
            pendentes  = @($registros | Where-Object { "$($_.status)" -in @('aplicando', 'falha') }).Count
            atual      = ($atual -and "$($d.Name)" -ieq $atual)
        })
    }

    $lista.ToArray()
}

# ---------------------------------------------------------------------------
# Registro das acoes da ponte
# ---------------------------------------------------------------------------

function Register-TmxTweakActions {
    <#
    .SYNOPSIS
        Registra catalog.get, preset.apply, plan.* , undo.* e runs.list.
    #>
    [CmdletBinding()]
    param()

    # --- catalogo e preset ---------------------------------------------------

    Register-TmxBridgeAction -Name 'catalog.get' -Async -Handler {
        param($payload)
        $preset = $null
        if ($payload -and $payload.preset) { $preset = "$($payload.preset)" }

        Send-TmxJobProgress -Pct 10 -Status 'Lendo o catalogo...'
        Update-TmxTweakPlan -Preset $preset | Out-Null
        Send-TmxJobProgress -Pct 90 -Status 'Montando a lista...'
        Get-TmxTweakCatalogPayload
    }

    Register-TmxBridgeAction -Name 'preset.apply' -Async -Handler {
        param($payload)
        $preset = 'desktop'
        if ($payload -and $payload.preset) { $preset = "$($payload.preset)" }

        Send-TmxJobProgress -Pct 20 -Status "Aplicando o preset $preset..."
        Update-TmxTweakPlan -Preset $preset | Out-Null
        Get-TmxTweakCatalogPayload
    }

    # mode.select {mode}: preset cumulativo da v2 (spec 6). Mesmo efeito de
    # preset.apply, mas so aceita os quatro modos - um nome errado e recusado
    # em vez de cair silenciosamente no preset desktop.
    Register-TmxBridgeAction -Name 'mode.select' -Async -Handler {
        param($payload)
        $modo = ''
        if ($payload -and $payload.mode) { $modo = "$($payload.mode)" }
        if ($modo -cnotin (Get-TmxTweakUiModeNames)) {
            throw "modo invalido: '$modo' (use leve, moderado, avancado ou ultimate)"
        }

        Send-TmxJobProgress -Pct 20 -Status "Selecionando o modo $modo..."
        Update-TmxTweakPlan -Preset $modo | Out-Null
        Get-TmxTweakCatalogPayload
    }

    # --- selecao, consentimento e opcao (sincronas: so mexem no plano) -------

    Register-TmxBridgeAction -Name 'plan.setSelection' -Handler {
        param($payload)
        $st = Get-TmxTweakState
        if ($null -eq $st.plan) { throw 'catalogo ainda nao foi carregado' }

        $id = "$($payload.id)"
        if (-not $id) { throw 'id obrigatorio' }
        $sel = [bool]$payload.selecionado

        $r = Set-TmxPlanSelection -Plan $st.plan -Id $id -Selected $sel
        @{ ok = [bool]$r.ok; mensagem = "$($r.mensagem)"; resumo = $st.plan.resumo }
    }

    Register-TmxBridgeAction -Name 'plan.setConsent' -Handler {
        param($payload)
        $st = Get-TmxTweakState
        if ($null -eq $st.plan) { throw 'catalogo ainda nao foi carregado' }

        $id = "$($payload.id)"
        if (-not $id) { throw 'id obrigatorio' }
        $item = Get-TmxTweakPlanItem -Id $id
        if ($null -eq $item) { return @{ ok = $false; mensagem = "ID '$id' nao existe no plano" } }

        $esperada = Get-TmxTweakConsentPhrase -Tweak $item.tweak
        if (-not $esperada) { return @{ ok = $false; mensagem = 'este ajuste nao exige consentimento extra' } }

        $digitada = ''
        if ($null -ne $payload.frase) { $digitada = "$($payload.frase)" }

        # -cne: sensivel a maiusculas. A frase e a unica porta do consentimento.
        if ($digitada -cne $esperada) { return @{ ok = $false; mensagem = 'frase incorreta' } }

        $r = Set-TmxPlanConsent -Plan $st.plan -Id $id -Consented $true
        @{ ok = [bool]$r.ok; mensagem = "$($r.mensagem)"; resumo = $st.plan.resumo }
    }

    Register-TmxBridgeAction -Name 'plan.setOption' -Handler {
        param($payload)
        $st = Get-TmxTweakState
        if ($null -eq $st.plan) { throw 'catalogo ainda nao foi carregado' }

        $id = "$($payload.id)"
        if (-not $id) { throw 'id obrigatorio' }
        $item = Get-TmxTweakPlanItem -Id $id
        if ($null -eq $item) { return @{ ok = $false; mensagem = "ID '$id' nao existe no plano" } }

        $valor = "$($payload.valor)"
        $op = @($item.tweak.opcoes | Where-Object { "$($_.valor)" -ceq $valor }) | Select-Object -First 1
        if ($null -eq $op) { return @{ ok = $false; mensagem = "opcao '$valor' nao existe em $id" } }

        $item.tweak | Add-Member -NotePropertyName opcaoSelecionada -NotePropertyValue $valor -Force
        @{ ok = $true; mensagem = "$id`: opcao '$($op.rotulo)' escolhida"; valor = $valor }
    }

    # plan.setParams {id, parametros}: as perguntas de APM-006 (o que manter) e
    # APM-007 (usa Game Pass?) antes da previa. Sincrona: so mexe no plano.
    Register-TmxBridgeAction -Name 'plan.setParams' -Handler {
        param($payload)
        $st = Get-TmxTweakState
        if ($null -eq $st.plan) { throw 'catalogo ainda nao foi carregado' }

        $id = "$($payload.id)"
        if (-not $id) { throw 'id obrigatorio' }
        $item = Get-TmxTweakPlanItem -Id $id
        if ($null -eq $item) { return @{ ok = $false; mensagem = "ID '$id' nao existe no plano" } }

        $params = ConvertTo-TmxTweakParams -Id "$($item.id)" -Parametros $payload.parametros
        Set-TmxTweakItemParams -Item $item -Parametros $params | Out-Null
        @{ ok = $true; mensagem = "$($item.id): parametros registrados"; parametros = $params }
    }

    Register-TmxBridgeAction -Name 'tweaks.bloatwareList' -Async -Handler {
        param($payload)
        Send-TmxJobProgress -Pct 30 -Status 'Lendo os aplicativos instalados...'
        @{ apps = (Get-TmxTweakBloatwareList) }
    }

    # --- previa --------------------------------------------------------------

    Register-TmxBridgeAction -Name 'plan.preview' -Async -Handler {
        param($payload)
        $st = Get-TmxTweakState
        if ($null -eq $st.plan) { throw 'catalogo ainda nao foi carregado' }

        $ids = @(@($payload.ids) | ForEach-Object { "$_" } | Where-Object { $_ })
        if ($ids.Count -eq 0) { throw 'nenhum ajuste selecionado' }

        Send-TmxJobProgress -Pct 30 -Status 'Lendo o estado atual...'
        $planoPrevia = New-TmxTweakEffectivePlan -Ids $ids
        $linhas = @(Get-TmxPlanPreview -Plan $planoPrevia -Profile $st.profile -Ids $ids)

        $falta = New-Object 'System.Collections.Generic.List[string]'
        foreach ($id in $ids) {
            $item = Get-TmxTweakPlanItem -Id $id
            if ($null -eq $item) { continue }
            if ($item.tweak.requerConsentimentoExtra -and -not $item.consentido) { $falta.Add("$($item.id)") }
        }

        @{
            itens = @($linhas | ForEach-Object {
                @{
                    tweakId  = "$($_.tweakId)"
                    nome     = "$($_.nome)"
                    tipo     = "$($_.tipo)"
                    alvo     = "$($_.alvo)"
                    antes    = "$($_.antes)"
                    depois   = "$($_.depois)"
                    reversao = "$($_.reversao)"
                }
            })
            faltaConsentimento = $falta.ToArray()
        }
    }

    # --- aplicacao -----------------------------------------------------------

    # Sincrona de proposito, apesar de o trabalho ir para o pool: sessao, ids e
    # consentimento TEM que ser conferidos antes de existir job - com -Async a
    # resposta imediata ja teria dito ok:true. Mesmo padrao do session.start.
    Register-TmxBridgeAction -Name 'plan.apply' -Handler {
        param($payload)

        $ids = @(@($payload.ids) | ForEach-Object { "$_" } | Where-Object { $_ })
        Assert-TmxTweakApplyReady -Ids $ids

        $jobId = Start-TmxJob -Name 'plan.apply' -Payload @{ ids = $ids } -Handler {
            param($p)
            $ids = @($p.ids)
            Send-TmxJobProgress -Pct 5 -Status "Aplicando $($ids.Count) ajuste(s)..."
            $resultado = Invoke-TmxTweakApplyIds -Ids $ids
            Send-TmxJobProgress -Pct 92 -Status 'Relendo o estado do sistema...'
            Update-TmxTweakPlan | Out-Null
            Send-TmxJobProgress -Pct 100 -Status 'Concluido'
            @{ resultado = $resultado; catalogo = (Get-TmxTweakCatalogPayload) }
        }

        @{ jobId = $jobId }
    }

    Register-TmxBridgeAction -Name 'plan.applyToggle' -Handler {
        param($payload)

        $id = "$($payload.id)"
        if (-not $id) { throw 'id obrigatorio' }
        $ligado = [bool]$payload.ligado

        $st = Get-TmxTweakState
        if ($null -eq $st.plan) { throw 'catalogo ainda nao foi carregado' }

        Assert-TmxTweakSession
        Assert-TmxTweakTestModeIds -Ids @($id)

        $item = Get-TmxTweakPlanItem -Id $id
        if ($null -eq $item) { throw "ids fora do catalogo: $id" }
        if (-not $item.alternavel) { throw "$id nao pode ser alternado (status: $($item.status))" }
        if ($item.tweak.requerConsentimentoExtra -and -not $item.consentido) { throw "consentimento pendente: $id" }
        if (-not $ligado -and @($item.tweak.toggleDesligar).Count -eq 0) {
            throw "$id nao tem acao de desligar"
        }

        $jobId = Start-TmxJob -Name 'plan.applyToggle' -Payload @{ id = $id; ligado = $ligado } -Handler {
            param($p)
            $st   = Get-TmxTweakState
            $item = Get-TmxTweakPlanItem -Id "$($p.id)"
            if ($null -eq $item) { throw "ids fora do catalogo: $($p.id)" }

            $acoes = if ($p.ligado) {
                Get-TmxTweakEffectiveActions -Tweak $item.tweak
            } else {
                @($item.tweak.toggleDesligar)
            }

            Send-TmxJobProgress -Pct 20 -Status "$(if ($p.ligado) { 'Ligando' } else { 'Desligando' }) $($item.id)..."
            $tweak = New-TmxTweakVariant -Tweak $item.tweak -Acoes $acoes
            $plano = New-TmxTweakSingleItemPlan -Item $item -Tweak $tweak -Consentido ([bool]$item.consentido)
            $r     = Invoke-TmxPlan -Plan $plano -Profile $st.profile

            Send-TmxJobProgress -Pct 85 -Status 'Relendo o estado do sistema...'
            Update-TmxTweakPlan | Out-Null

            @{
                resultado = @{
                    itens        = @(@($r.itens) | ForEach-Object {
                        @{
                            id           = "$($_.id)"
                            nome         = "$($_.nome)"
                            tier         = "$($_.tier)"
                            status       = "$($_.status)"
                            detalhe      = "$($_.detalhe)"
                            antes        = "$($_.antes)"
                            depois       = "$($_.depois)"
                            registros    = [int]$_.registros
                            requerReboot = [bool]$_.requerReboot
                            avisos       = @(@($_.avisos) | ForEach-Object { "$_" })
                        }
                    })
                    aplicados    = [int]$r.aplicados
                    jaAplicados  = [int]$r.jaAplicados
                    falhas       = [int]$r.falhas
                    pulados      = [int]$r.pulados
                    requerReboot = [bool]$r.requerReboot
                }
                ligado    = [bool]$p.ligado
                catalogo  = (Get-TmxTweakCatalogPayload)
            }
        }

        @{ jobId = $jobId }
    }

    # --- reversao ------------------------------------------------------------

    Register-TmxBridgeAction -Name 'undo.tweak' -Handler {
        param($payload)

        $id = "$($payload.id)"
        if (-not $id) { throw 'id obrigatorio' }
        if ($null -eq $sync.session -or -not $sync.session.runId) { throw 'nenhuma execucao ativa para reverter' }

        $jobId = Start-TmxJob -Name 'undo.tweak' -Payload @{ id = $id; runId = "$($sync.session.runId)" } -Handler {
            param($p)
            Send-TmxJobProgress -Pct 20 -Status "Revertendo $($p.id)..."
            $resumo = Undo-TweakMaxing -RunId "$($p.runId)" -TweakId "$($p.id)" -Quiet
            Send-TmxJobProgress -Pct 80 -Status 'Relendo o estado do sistema...'
            Update-TmxTweakPlan | Out-Null
            @{
                id       = "$($p.id)"
                resumo   = (ConvertTo-TmxUndoSummary -Summary $resumo)
                catalogo = (Get-TmxTweakCatalogPayload)
            }
        }

        @{ jobId = $jobId }
    }

    Register-TmxBridgeAction -Name 'undo.run' -Handler {
        param($payload)

        $runId = ''
        if ($payload -and $payload.runId) { $runId = "$($payload.runId)" }
        if (-not $runId) {
            if ($null -eq $sync.session -or -not $sync.session.runId) { throw 'nenhuma execucao ativa para reverter' }
            $runId = "$($sync.session.runId)"
        }

        $atual = $false
        if ($null -ne $sync.session -and "$($sync.session.runId)" -ieq $runId) { $atual = $true }

        $jobId = Start-TmxJob -Name 'undo.run' -Payload @{ runId = $runId; atual = $atual } -Handler {
            param($p)
            Send-TmxJobProgress -Pct 20 -Status "Revertendo a execucao $($p.runId)..."
            $resumo = Undo-TweakMaxing -RunId "$($p.runId)" -Quiet

            $catalogo = $null
            if ($p.atual -and $null -ne (Get-TmxTweakState).plan) {
                Send-TmxJobProgress -Pct 80 -Status 'Relendo o estado do sistema...'
                Update-TmxTweakPlan | Out-Null
                $catalogo = Get-TmxTweakCatalogPayload
            }

            @{
                runId    = "$($p.runId)"
                atual    = [bool]$p.atual
                resumo   = (ConvertTo-TmxUndoSummary -Summary $resumo)
                catalogo = $catalogo
            }
        }

        @{ jobId = $jobId }
    }

    Register-TmxBridgeAction -Name 'runs.list' -Async -Handler {
        param($payload)
        @{ execucoes = (Get-TmxTweakRunList) }
    }

    Register-TmxBridgeAction -Name 'undo.command' -Handler {
        param($payload)
        $comando = $null
        if ($null -ne $sync.session -and $sync.session.undoCommand) { $comando = "$($sync.session.undoCommand)" }
        @{ comando = $comando }
    }
}
