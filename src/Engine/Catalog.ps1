# Engine/Catalog.ps1
# Carrega e valida o catalogo de tweaks (JSON). Porta reduzida/adaptada de
# CS2Tuner Engine/Resolve-TweakPlan.ps1 (Get-TunerTweakCatalog + Test-TunerTweakCatalog)
# para o schema do TweakMaxing descrito em docs/specs/2026-09-22-tweakmaxing-design.md.
#
# Regras de validacao: ver Test-TmxCatalog abaixo.

$script:TmxTiers      = @('MEDIDO', 'TECNICO', 'FOLCLORE')
$script:TmxRiscos     = @('baixo', 'medio', 'alto')
$script:TmxPresets    = @('desktop', 'notebook', 'minimo')
$script:TmxControles  = @('checkbox', 'toggle', 'combobox', 'button', 'info', 'radio')
$script:TmxReversiveis = @('total', 'parcial', 'nenhuma')
$script:TmxAcaoTipos  = @('registry', 'service', 'scheduledTask', 'appx', 'powercfg', 'netadapter', 'bcdedit', 'feature', 'funcao')

# Task T2 (modos/catalogo v2): 'modo' e 'categoriasV2' sao opcionais no schema,
# mas quando presentes precisam estar nesses conjuntos fechados. 'extras' e um
# modo valido (item fora dos 4 presets cumulativos, so opt-in manual) mas NUNCA
# vira um preset selecionavel em -Preset (ver Engine/Plan.ps1).
$script:TmxModos         = @('leve', 'moderado', 'avancado', 'ultimate', 'extras')
$script:TmxModosPreset   = @('leve', 'moderado', 'avancado', 'ultimate')
$script:TmxCategoriasV2  = @('geral', 'aparencia', 'desempenho', 'privacidade', 'jogos', 'rede', 'gpu')

function Get-TmxCatalog {
    <#
    .SYNOPSIS
        Carrega o catalogo de tweaks a partir de um diretorio (todo tweaks*.json,
        ordenado por nome, arrays .tweaks concatenados), de um arquivo unico ou
        de documentos JA parseados em memoria.
    .PARAMETER Path
        Diretorio ou arquivo. Default: <repo>/src/config.
    .PARAMETER Documents
        Documentos ja parseados (cada um com .tweaks), na ordem em que devem ser
        concatenados. E por aqui que o TweakMaxing.ps1 compilado carrega o
        catalogo: la nao existe src/config no disco, so $sync.configs.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    param(
        [Parameter(ParameterSetName = 'Path', Position = 0)]
        [string] $Path,

        [Parameter(Mandatory, ParameterSetName = 'Documents')]
        $Documents
    )

    $tweaks = New-Object 'System.Collections.Generic.List[object]'

    if ($PSCmdlet.ParameterSetName -eq 'Documents') {
        foreach ($documento in @($Documents)) {
            if ($null -eq $documento) { continue }
            foreach ($t in @($documento.tweaks)) {
                if ($null -ne $t) { $tweaks.Add($t) }
            }
        }
        if ($tweaks.Count -eq 0) {
            throw 'Catalogo vazio: nenhum tweak encontrado nos documentos informados.'
        }
        # .ToArray(): @() sobre List generica vazia falha no PS 5.1
        return $tweaks.ToArray()
    }

    if (-not $Path) {
        # Sem -Path: <repo>/src/config. No artefato compilado $PSScriptRoot
        # aponta para a pasta do proprio .ps1 e nao ha src/config nenhum - de
        # la o catalogo entra por -Documents, nunca por este caminho.
        $raizRepo = if ($PSScriptRoot) { Split-Path (Split-Path $PSScriptRoot -Parent) -Parent } else { $null }
        if (-not $raizRepo) { throw 'Catalogo nao encontrado: informe -Path ou -Documents.' }
        $Path = Join-Path $raizRepo 'src\config'
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Catalogo nao encontrado: '$Path' nao existe."
    }

    $item = Get-Item -LiteralPath $Path
    $arquivos = if ($item.PSIsContainer) {
        @(Get-ChildItem -LiteralPath $Path -Filter 'tweaks*.json' -File | Sort-Object Name)
    } else {
        @($item)
    }

    if ($arquivos.Count -eq 0) {
        throw "Catalogo nao encontrado: nenhum arquivo 'tweaks*.json' em '$Path'."
    }

    foreach ($arquivo in $arquivos) {
        try {
            $doc = Get-Content -LiteralPath $arquivo.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        } catch {
            throw "Falha ao ler catalogo '$($arquivo.FullName)': $($_.Exception.Message)"
        }
        foreach ($t in @($doc.tweaks)) {
            if ($null -ne $t) { $tweaks.Add($t) }
        }
    }

    if ($tweaks.Count -eq 0) {
        throw "Catalogo vazio: nenhum tweak encontrado em '$Path'."
    }

    # .ToArray(): @() sobre List generica vazia falha no PS 5.1
    $tweaks.ToArray()
}

function Test-TmxStringField {
    <#
    .SYNOPSIS
        Percorre recursivamente um objeto/array/string procurando padroes de
        execucao dinamica proibidos em qualquer campo de texto do catalogo.
    .OUTPUTS
        Array de strings encontradas que batem o padrao proibido (vazio se limpo).
    #>
    param($Value)

    $padrao = '(?i)(Invoke-Expression|\biex\s|\[scriptblock\]|ScriptBlock\]::Create)'
    $achados = New-Object 'System.Collections.Generic.List[string]'

    function script:Walk($v) {
        if ($null -eq $v) { return }
        if ($v -is [string]) {
            if ($v -match $padrao) { $achados.Add($v) }
            return
        }
        if ($v -is [System.Collections.IDictionary]) {
            # Hashtable/IDictionary primeiro, ANTES do IEnumerable generico: "foreach ($x in
            # $hashtableVazia)" no PowerShell 5.1 nao itera zero vezes como o .GetEnumerator()
            # direto faria - ele "desenrola" a colecao vazia de volta para o proprio objeto,
            # entregando $x = a mesma hashtable. Sem este caso especial, Walk($x) chamaria
            # Walk na MESMA hashtable de novo, e de novo, e de novo - recursao infinita /
            # estouro de pilha em qualquer acao com "parametros": {} (comum em tipo 'funcao').
            foreach ($chave in @($v.Keys)) { Walk $v[$chave] }
            return
        }
        if ($v -is [System.Collections.IEnumerable] -and -not ($v -is [string])) {
            foreach ($x in $v) { Walk $x }
            return
        }
        if ($v -is [pscustomobject]) {
            foreach ($p in $v.PSObject.Properties) { Walk $p.Value }
            return
        }
    }
    Walk $Value
    $achados.ToArray()
}

function Test-TmxAcaoList {
    <#
    .SYNOPSIS
        Valida uma lista de acoes (tipo no conjunto fechado + trio Set-/Undo-/Test-Tmx<X>
        para 'funcao'). Usado para acoes[] do proprio tweak, opcoes[].acoes[] (combobox) e
        toggleDesligar[] (acoes de desligar de um toggle, geradas pelo conversor da Task 6).
    .PARAMETER Erros
        Lista mutavel (System.Collections.Generic.List[string]) onde os erros sao acumulados.
    #>
    param(
        [Parameter(Mandatory)] [string] $Id,
        $Acoes,
        [Parameter(Mandatory)] [string] $Origem,
        [Parameter(Mandatory)] $Erros
    )
    foreach ($a in @($Acoes)) {
        if ($null -eq $a) { continue }
        if ("$($a.tipo)" -cnotin $script:TmxAcaoTipos) { $Erros.Add("$Id`: $Origem.tipo invalido '$($a.tipo)'") }
        if ($a.tipo -eq 'funcao') {
            $nome = "$($a.nome)"
            if ($nome -notmatch '^Set-Tmx[A-Za-z0-9]+$') {
                $Erros.Add("$Id`: $Origem.nome de funcao invalido '$nome' (esperado Set-Tmx<X>)")
            } else {
                $sufixo = $nome.Substring('Set-Tmx'.Length)
                if (-not (Get-Command -Name $nome -ErrorAction SilentlyContinue)) {
                    $Erros.Add("$Id`: funcao '$nome' nao encontrada (Get-Command)")
                }
                if (-not (Get-Command -Name "Undo-Tmx$sufixo" -ErrorAction SilentlyContinue)) {
                    $Erros.Add("$Id`: funcao 'Undo-Tmx$sufixo' nao encontrada (par obrigatorio de '$nome')")
                }
                if (-not (Get-Command -Name "Test-Tmx$sufixo" -ErrorAction SilentlyContinue)) {
                    $Erros.Add("$Id`: funcao 'Test-Tmx$sufixo' nao encontrada (par obrigatorio de '$nome')")
                }
            }
        }
    }
}

function Test-TmxCatalog {
    <#
    .SYNOPSIS
        Valida o schema do catalogo. Retorna { ok, erros[], total }.
    #>
    param([Parameter(Mandatory)] $Catalog)

    $erros = New-Object 'System.Collections.Generic.List[string]'
    # OrdinalIgnoreCase: 'REG-001' e 'reg-001' devem contar como o MESMO id para fins de
    # duplicidade, mesmo que o formato CAT-NNN (abaixo, com -cnotmatch) va rejeitar o
    # segundo por nao estar em maiusculas.
    $ids = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)

    # regex de promessa de ganho percentual (portado do CS2Tuner: proibe "ganho de 30%",
    # "20% mais FPS" etc; permite metricas de fato como "1% low", "85-90% de uso").
    # 'a' com acento montado via [char]0x00E1 (nao como literal): este arquivo nao tem BOM
    # e o parser do PowerShell 5.1 sem BOM le UTF-8 como codepage ANSI, corrompendo o
    # literal acentuado embutido na string do regex (o 'a' acentuado de 'mais rapido'
    # virava dois caracteres Latin-1 e o padrao parava de casar).
    $promessa = '(?i)(ganh|melhor|reduz|aument|cai|queda|mais r[a' + [char]0x00E1 + ']pid|menos lat)\w*.{0,25}?\d+\s*%|\d+\s*%\s*(de ganho|a mais|a menos|mais|menos|melhor)'

    foreach ($t in $Catalog) {
        $id = "$($t.id)"
        if (-not $id) { $erros.Add('tweak sem id'); continue }
        # -cnotmatch (case-sensitive): '-notmatch' sozinho e case-INsensitive, entao
        # '[A-Z]{3}' aceitaria 'reg-001' tambem - o formato exige maiusculas de verdade.
        if ($id -cnotmatch '^[A-Z]{3}-\d{3}$') { $erros.Add("$id`: id fora do formato CAT-NNN") }
        if (-not $ids.Add($id)) { $erros.Add("$id`: id duplicado") }

        foreach ($campo in 'nome', 'categoria', 'tier', 'risco', 'porque', 'evidencia') {
            if (-not "$($t.$campo)") { $erros.Add("$id`: campo '$campo' vazio") }
        }
        foreach ($campo in 'presets', 'reversivel', 'requerReboot', 'requerConsentimentoExtra', 'condicoes', 'controle', 'acoes') {
            if ($null -eq $t.PSObject.Properties[$campo]) { $erros.Add("$id`: campo '$campo' ausente") }
        }

        # Task T2: 'modo', 'categoriasV2' e 'i18n' sao opcionais - se ausentes ou
        # null, nao ha erro. Se presentes, o formato/enum precisa ser valido.
        if ($t.PSObject.Properties['modo'] -and $null -ne $t.modo) {
            if ("$($t.modo)" -cnotin $script:TmxModos) { $erros.Add("$id`: modo invalido '$($t.modo)'") }
        }
        if ($t.PSObject.Properties['categoriasV2'] -and $null -ne $t.categoriasV2) {
            foreach ($cv2 in @($t.categoriasV2)) {
                if ("$cv2" -cnotin $script:TmxCategoriasV2) { $erros.Add("$id`: categoriasV2 invalido '$cv2'") }
            }
        }
        if ($t.PSObject.Properties['i18n'] -and $null -ne $t.i18n -and $t.i18n.PSObject.Properties['en'] -and $null -ne $t.i18n.en) {
            foreach ($campoEn in 'oQueFaz', 'beneficio', 'atencao') {
                $propEn = $t.i18n.en.PSObject.Properties[$campoEn]
                if ($null -ne $propEn -and -not "$($propEn.Value)") { $erros.Add("$id`: i18n.en.$campoEn vazio") }
            }
        }

        # -cnotin (case-sensitive): os conjuntos fechados usam grafia exata (MEDIDO, nao
        # medido/Medido); '-notin' sozinho compara sem diferenciar maiusculas de minusculas
        # e deixaria passar variantes de caixa que nao existem no schema.
        if ($t.tier -cnotin $script:TmxTiers)   { $erros.Add("$id`: tier invalido '$($t.tier)'") }
        if ($t.risco -cnotin $script:TmxRiscos) { $erros.Add("$id`: risco invalido '$($t.risco)'") }
        foreach ($p in @($t.presets)) { if ($p -cnotin $script:TmxPresets) { $erros.Add("$id`: preset invalido '$p'") } }
        if ($t.controle -and $t.controle -cnotin $script:TmxControles) { $erros.Add("$id`: controle invalido '$($t.controle)'") }
        if ($t.reversivel -and $t.reversivel -cnotin $script:TmxReversiveis) { $erros.Add("$id`: reversivel invalido '$($t.reversivel)'") }

        # acoes[]: controle 'info' pode ter acoes vazias, mas exige instrucoes.
        $acoes = @($t.acoes)
        if ($t.controle -eq 'info') {
            if (-not "$($t.instrucoes)") { $erros.Add("$id`: controle 'info' exige 'instrucoes'") }
        }
        Test-TmxAcaoList -Id $id -Acoes $acoes -Origem 'acoes[]' -Erros $erros

        # toggleDesligar[]: acoes de desligar de um toggle (gerado pelo conversor da Task 6),
        # mesmas regras de acoes[] quando presente.
        if ($null -ne $t.PSObject.Properties['toggleDesligar']) {
            Test-TmxAcaoList -Id $id -Acoes $t.toggleDesligar -Origem 'toggleDesligar[]' -Erros $erros
        }

        if ($t.tier -eq 'FOLCLORE') {
            if (@($t.presets).Count -gt 0) { $erros.Add("$id`: FOLCLORE nao pode ter presets") }
            if (-not $t.folclore -or -not "$($t.folclore.porqueNaoRecomendamos)") { $erros.Add("$id`: FOLCLORE exige bloco 'folclore' com porqueNaoRecomendamos") }
        }

        if ("$($t.reversivel)" -eq 'nenhuma') {
            if ($t.requerConsentimentoExtra -ne $true) { $erros.Add("$id`: reversivel 'nenhuma' exige requerConsentimentoExtra=true") }
            if (@($t.presets).Count -gt 0) { $erros.Add("$id`: reversivel 'nenhuma' nao pode ter presets") }
        }

        if ($t.requerConsentimentoExtra -eq $true) {
            if (-not "$($t.consentimento.frase)") { $erros.Add("$id`: requerConsentimentoExtra exige 'consentimento.frase'") }
        }

        if ($t.controle -eq 'combobox') {
            $opcoes = @($t.opcoes)
            if ($opcoes.Count -lt 2) {
                $erros.Add("$id`: combobox exige ao menos 2 'opcoes'")
            } else {
                foreach ($o in $opcoes) {
                    foreach ($campo in 'valor', 'rotulo', 'acoes') {
                        if ($null -eq $o.PSObject.Properties[$campo]) { $erros.Add("$id`: opcoes[] falta campo '$campo'") }
                    }
                    Test-TmxAcaoList -Id $id -Acoes $o.acoes -Origem 'opcoes[].acoes[]' -Erros $erros
                }
            }
        }

        if ($t.controle -eq 'radio') {
            if (-not "$($t.grupo)") { $erros.Add("$id`: controle 'radio' exige 'grupo' nao vazio") }
        }

        # varredura de scriptblock/iex em qualquer campo de texto (recursiva).
        $achadosPerigo = Test-TmxStringField -Value $t
        foreach ($ach in $achadosPerigo) { $erros.Add("$id`: campo de texto contem padrao proibido (Invoke-Expression/iex/scriptblock): '$ach'") }

        if ($t.tier -ne 'FOLCLORE') {
            if ($t.evidencia -match $promessa -or $t.porque -match $promessa) {
                $erros.Add("$id`: percentual usado como promessa de ganho - nao inventar numeros")
            }
        }

        foreach ($lista in 'requer', 'bloqueiaSe') {
            foreach ($expr in @($t.condicoes.$lista)) {
                try { ConvertFrom-TmxCondition -Expression $expr | Out-Null } catch { $erros.Add("$id`: $($_.Exception.Message)") }
            }
        }
    }

    [pscustomobject]@{ ok = ($erros.Count -eq 0); erros = $erros.ToArray(); total = @($Catalog).Count }
}
