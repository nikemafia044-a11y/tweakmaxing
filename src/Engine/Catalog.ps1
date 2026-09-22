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

function Get-TmxCatalog {
    <#
    .SYNOPSIS
        Carrega o catalogo de tweaks a partir de um diretorio (todo tweaks*.json,
        ordenado por nome, arrays .tweaks concatenados) ou de um arquivo unico.
    .PARAMETER Path
        Diretorio ou arquivo. Default: <repo>/src/config.
    #>
    [CmdletBinding()]
    param(
        [string] $Path = (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'src\config')
    )

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

    $tweaks = New-Object 'System.Collections.Generic.List[object]'
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

function Test-TmxCatalog {
    <#
    .SYNOPSIS
        Valida o schema do catalogo. Retorna { ok, erros[], total }.
    #>
    param([Parameter(Mandatory)] $Catalog)

    $erros = New-Object 'System.Collections.Generic.List[string]'
    $ids   = New-Object 'System.Collections.Generic.HashSet[string]'

    # regex de promessa de ganho percentual (portado do CS2Tuner: proibe "ganho de 30%",
    # "20% mais FPS" etc; permite metricas de fato como "1% low", "85-90% de uso").
    $promessa = '(?i)(ganh|melhor|reduz|aument|cai|queda|mais r[aá]pid|menos lat)\w*.{0,25}?\d+\s*%|\d+\s*%\s*(de ganho|a mais|a menos|mais|menos|melhor)'

    foreach ($t in $Catalog) {
        $id = "$($t.id)"
        if (-not $id) { $erros.Add('tweak sem id'); continue }
        if ($id -notmatch '^[A-Z]{3}-\d{3}$') { $erros.Add("$id`: id fora do formato CAT-NNN") }
        if (-not $ids.Add($id)) { $erros.Add("$id`: id duplicado") }

        foreach ($campo in 'nome', 'categoria', 'tier', 'risco', 'porque', 'evidencia') {
            if (-not "$($t.$campo)") { $erros.Add("$id`: campo '$campo' vazio") }
        }
        foreach ($campo in 'presets', 'reversivel', 'requerReboot', 'requerConsentimentoExtra', 'condicoes', 'controle', 'acoes') {
            if ($null -eq $t.PSObject.Properties[$campo]) { $erros.Add("$id`: campo '$campo' ausente") }
        }

        if ($t.tier -notin $script:TmxTiers)   { $erros.Add("$id`: tier invalido '$($t.tier)'") }
        if ($t.risco -notin $script:TmxRiscos) { $erros.Add("$id`: risco invalido '$($t.risco)'") }
        foreach ($p in @($t.presets)) { if ($p -notin $script:TmxPresets) { $erros.Add("$id`: preset invalido '$p'") } }
        if ($t.controle -and $t.controle -notin $script:TmxControles) { $erros.Add("$id`: controle invalido '$($t.controle)'") }
        if ($t.reversivel -and $t.reversivel -notin $script:TmxReversiveis) { $erros.Add("$id`: reversivel invalido '$($t.reversivel)'") }

        # acoes[]: controle 'info' pode ter acoes vazias, mas exige instrucoes.
        $acoes = @($t.acoes)
        if ($t.controle -eq 'info') {
            if (-not "$($t.instrucoes)") { $erros.Add("$id`: controle 'info' exige 'instrucoes'") }
        }
        foreach ($a in $acoes) {
            if ($null -eq $a) { continue }
            if ("$($a.tipo)" -notin $script:TmxAcaoTipos) { $erros.Add("$id`: acoes[].tipo invalido '$($a.tipo)'") }
            if ($a.tipo -eq 'funcao') {
                $nome = "$($a.nome)"
                if ($nome -notmatch '^Set-Tmx[A-Za-z0-9]+$') {
                    $erros.Add("$id`: acoes[].nome de funcao invalido '$nome' (esperado Set-Tmx<X>)")
                } else {
                    $sufixo = $nome.Substring('Set-Tmx'.Length)
                    if (-not (Get-Command -Name $nome -ErrorAction SilentlyContinue)) {
                        $erros.Add("$id`: funcao '$nome' nao encontrada (Get-Command)")
                    }
                    if (-not (Get-Command -Name "Undo-Tmx$sufixo" -ErrorAction SilentlyContinue)) {
                        $erros.Add("$id`: funcao 'Undo-Tmx$sufixo' nao encontrada (par obrigatorio de '$nome')")
                    }
                    if (-not (Get-Command -Name "Test-Tmx$sufixo" -ErrorAction SilentlyContinue)) {
                        $erros.Add("$id`: funcao 'Test-Tmx$sufixo' nao encontrada (par obrigatorio de '$nome')")
                    }
                }
            }
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
