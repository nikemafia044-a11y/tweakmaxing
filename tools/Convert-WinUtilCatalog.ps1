<#
.SYNOPSIS
    Converte o catalogo do WinUtil (MIT, Chris Titus Tech) para o schema do TweakMaxing.

.DESCRIPTION
    Le reference/winutil/config/{tweaks,applications,feature,appx,dns}.json e a camada
    editorial em src/config/overlay/ e gera src/config/{tweaks,applications,feature,appx,dns}.json.

    O conversor NUNCA copia script do WinUtil para o catalogo. Todo InvokeScript
    precisa de um destino nomeado (Set-Tmx<X>) declarado no overlay, ou o overlay
    precisa marcar 'ignorarScripts: true' junto com 'motivoIgnorarScripts'. Assim
    nada no catalogo e texto executavel.

    Saida: UTF-8 sem BOM, indentacao de 2 espacos, fim de linha LF, ordem de chaves
    estavel. Rodar duas vezes produz bytes identicos.

.PARAMETER Reference
    Diretorio do clone do WinUtil (o que contem config/ e functions/).

.PARAMETER Out
    Diretorio de saida (normalmente src/config).

.PARAMETER Overlay
    Arquivo de overlay dos tweaks. Padrao: <Out>/overlay/tweaks.overrides.json.

.PARAMETER OverlayApplications
    Arquivo de overlay dos aplicativos (opcional). Padrao: <Out>/overlay/applications.overrides.json.

.PARAMETER SomenteDefinicoes
    Define as funcoes auxiliares e retorna sem converter nada. Existe para os
    testes poderem exercitar o serializador e a conversao de valor isoladamente
    (dot-source do script com este switch). Nao use em linha de comando.

.EXAMPLE
    .\tools\Convert-WinUtilCatalog.ps1 -Reference reference\winutil -Out src\config
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Reference,
    [Parameter(Mandatory)] [string] $Out,
    [string] $Overlay,
    [string] $OverlayApplications,
    [switch] $SomenteDefinicoes
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Leitura tolerante de propriedades
# ---------------------------------------------------------------------------

function Get-TmxConvProp {
    # Propriedade opcional de um pscustomobject/hashtable. Escalares apenas:
    # para listas use Get-TmxConvArray (array vazio some no pipeline do PS 5.1).
    param($Obj, [Parameter(Mandatory)] [string] $Nome, $Padrao = $null)
    if ($null -eq $Obj) { return $Padrao }
    if ($Obj -is [System.Collections.IDictionary]) {
        if (-not $Obj.Contains($Nome)) { return $Padrao }
        $v = $Obj[$Nome]
        if ($null -eq $v) { return $Padrao }
        return $v
    }
    $p = $Obj.PSObject.Properties[$Nome]
    if ($null -eq $p -or $null -eq $p.Value) { return $Padrao }
    $p.Value
}

function Get-TmxConvArray {
    # Sempre devolve um array de verdade (',' evita que o array vazio evapore).
    param($Obj, [Parameter(Mandatory)] [string] $Nome)
    if ($null -eq $Obj) { return , @() }
    $v = $null
    if ($Obj -is [System.Collections.IDictionary]) {
        if (-not $Obj.Contains($Nome)) { return , @() }
        $v = $Obj[$Nome]
    } else {
        $p = $Obj.PSObject.Properties[$Nome]
        if ($null -eq $p) { return , @() }
        $v = $p.Value
    }
    if ($null -eq $v) { return , @() }
    , ([object[]]@($v))
}

function Test-TmxConvHasProp {
    param($Obj, [Parameter(Mandatory)] [string] $Nome)
    if ($null -eq $Obj) { return $false }
    if ($Obj -is [System.Collections.IDictionary]) { return $Obj.Contains($Nome) }
    return ($null -ne $Obj.PSObject.Properties[$Nome])
}

# ---------------------------------------------------------------------------
# Serializador JSON proprio
# ---------------------------------------------------------------------------

function ConvertTo-TmxJsonString {
    param([string] $Texto)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('"')
    foreach ($ch in $Texto.ToCharArray()) {
        $code = [int][char]$ch
        if     ($ch -ceq '"')  { [void]$sb.Append('\"') }
        elseif ($ch -ceq '\')  { [void]$sb.Append('\\') }
        elseif ($code -eq 8)   { [void]$sb.Append('\b') }
        elseif ($code -eq 12)  { [void]$sb.Append('\f') }
        elseif ($code -eq 10)  { [void]$sb.Append('\n') }
        elseif ($code -eq 13)  { [void]$sb.Append('\r') }
        elseif ($code -eq 9)   { [void]$sb.Append('\t') }
        elseif ($code -lt 32)  { [void]$sb.AppendFormat('\u{0:x4}', $code) }
        else                   { [void]$sb.Append($ch) }
    }
    [void]$sb.Append('"')
    $sb.ToString()
}

function ConvertTo-TmxJsonText {
    <#
    .SYNOPSIS
        Serializa com 2 espacos de indentacao, ordem de chaves preservada e acentos
        literais. O ConvertTo-Json do PS 5.1 erra nas tres coisas.
    #>
    param($Valor, [int] $Nivel = 0)

    $ind  = ' ' * (2 * $Nivel)
    $ind2 = ' ' * (2 * ($Nivel + 1))
    $inv  = [System.Globalization.CultureInfo]::InvariantCulture

    if ($null -eq $Valor) { return 'null' }
    if ($Valor -is [bool]) { if ($Valor) { return 'true' } else { return 'false' } }
    if ($Valor -is [string]) { return (ConvertTo-TmxJsonString -Texto $Valor) }
    if ($Valor -is [int] -or $Valor -is [long] -or $Valor -is [int16] -or $Valor -is [byte] -or
        $Valor -is [uint16] -or $Valor -is [uint32] -or $Valor -is [uint64]) {
        return ([int64]$Valor).ToString($inv)
    }
    if ($Valor -is [double] -or $Valor -is [single] -or $Valor -is [decimal]) {
        return ([double]$Valor).ToString('R', $inv)
    }

    if ($Valor -is [System.Collections.IDictionary]) {
        $chaves = @($Valor.Keys)
        if ($chaves.Count -eq 0) { return '{}' }
        $linhas = New-Object 'System.Collections.Generic.List[string]'
        foreach ($k in $chaves) {
            $linhas.Add(('{0}{1}: {2}' -f $ind2, (ConvertTo-TmxJsonString -Texto "$k"),
                (ConvertTo-TmxJsonText -Valor $Valor[$k] -Nivel ($Nivel + 1))))
        }
        return ("{`n" + ($linhas.ToArray() -join ",`n") + "`n$ind}")
    }

    if ($Valor -is [pscustomobject]) {
        $props = @($Valor.PSObject.Properties)
        if ($props.Count -eq 0) { return '{}' }
        $linhas = New-Object 'System.Collections.Generic.List[string]'
        foreach ($p in $props) {
            $linhas.Add(('{0}{1}: {2}' -f $ind2, (ConvertTo-TmxJsonString -Texto $p.Name),
                (ConvertTo-TmxJsonText -Valor $p.Value -Nivel ($Nivel + 1))))
        }
        return ("{`n" + ($linhas.ToArray() -join ",`n") + "`n$ind}")
    }

    if ($Valor -is [System.Collections.IEnumerable]) {
        $itens = @($Valor)
        if ($itens.Count -eq 0) { return '[]' }
        $linhas = New-Object 'System.Collections.Generic.List[string]'
        foreach ($i in $itens) {
            $linhas.Add(('{0}{1}' -f $ind2, (ConvertTo-TmxJsonText -Valor $i -Nivel ($Nivel + 1))))
        }
        return ("[`n" + ($linhas.ToArray() -join ",`n") + "`n$ind]")
    }

    ConvertTo-TmxJsonString -Texto "$Valor"
}

function Save-TmxJsonFile {
    param([Parameter(Mandatory)] [string] $Path, [Parameter(Mandatory)] $Valor)
    $texto = (ConvertTo-TmxJsonText -Valor $Valor -Nivel 0) + "`n"
    $texto = $texto -replace "`r`n", "`n"
    $dir = Split-Path -Path $Path -Parent
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [System.IO.File]::WriteAllText($Path, $texto, (New-Object System.Text.UTF8Encoding($false)))
}

function Read-TmxJsonFile {
    param([Parameter(Mandatory)] [string] $Path)
    if (-not (Test-Path -LiteralPath $Path)) { throw "Arquivo nao encontrado: $Path" }
    Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

# ---------------------------------------------------------------------------
# Acoes: ordem de chaves canonica por tipo
# ---------------------------------------------------------------------------

$script:TmxOrdemAcao = @{
    'registry'      = @('tipo', 'path', 'name', 'value', 'valueType', 'remove')
    'service'       = @('tipo', 'nome', 'tipoInicio', 'parar')
    'scheduledTask' = @('tipo', 'caminho', 'nome', 'estado')
    'appx'          = @('tipo', 'pacote', 'storeId', 'todosUsuarios')
    'powercfg'      = @('tipo', 'subgrupo', 'configuracao', 'valor', 'descricao')
    'netadapter'    = @('tipo', 'adaptador', 'chave', 'valor')
    'bcdedit'       = @('tipo', 'acao', 'opcao', 'valor')
    'feature'       = @('tipo', 'nome', 'estado')
    'funcao'        = @('tipo', 'nome', 'parametros')
}

function ConvertTo-TmxAcaoOrdenada {
    # Normaliza a ordem das chaves de uma acao ja pronta (vinda do overlay).
    param([Parameter(Mandatory)] $Acao)
    $tipo = "$(Get-TmxConvProp -Obj $Acao -Nome 'tipo')"
    if (-not $script:TmxOrdemAcao.ContainsKey($tipo)) {
        throw "Acao com tipo desconhecido no overlay: '$tipo'"
    }
    $o = [ordered]@{}
    foreach ($k in $script:TmxOrdemAcao[$tipo]) {
        if ($k -eq 'tipo') { $o['tipo'] = $tipo; continue }
        if (Test-TmxConvHasProp -Obj $Acao -Nome $k) {
            if ($k -eq 'parametros') {
                $par = [ordered]@{}
                $fonte = Get-TmxConvProp -Obj $Acao -Nome 'parametros' -Padrao $null
                if ($fonte) {
                    foreach ($pp in $fonte.PSObject.Properties) { $par[$pp.Name] = $pp.Value }
                }
                $o['parametros'] = $par
            } else {
                $o[$k] = (Get-TmxConvProp -Obj $Acao -Nome $k)
            }
        }
    }
    $o
}

function New-TmxAcaoRegistry {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Name,
        [string] $ValueType = 'DWord',
        $Value,
        [switch] $Remover
    )
    $o = [ordered]@{ tipo = 'registry'; path = $Path; name = $Name }
    if ($Remover) {
        $o['valueType'] = $ValueType
        $o['remove']    = $true
    } else {
        $o['value']     = $Value
        $o['valueType'] = $ValueType
    }
    $o
}

function ConvertTo-TmxValorRegistro {
    <#
    .SYNOPSIS
        Valor bruto do WinUtil (que e sempre texto) -> numero para DWord/QWord,
        texto para o resto.
    .NOTES
        DWord acima de [int]::MaxValue sai NAO ASSINADO no JSON: '0xffffffff'
        vira 4294967295, nao -1. Duas razoes:
          1. o catalogo tambem e documentacao legivel, e ninguem escreve uma
             mascara de bits cheia como '-1' num arquivo de configuracao;
          2. a conversao para o int32 negativo que o provider de registro exige
             ja acontece no lugar certo: ConvertTo-TmxRegistryValue, em
             Engine/Actions.ps1, subtrai 4294967296 antes de escrever.
        Converter aqui tambem aplicaria o ajuste duas vezes.
    #>
    param($Bruto, [string] $Tipo)
    if ($Tipo -eq 'DWord' -or $Tipo -eq 'QWord') {
        $s = "$Bruto".Trim()
        if ($s -match '^-?\d+$') { return [int64]$s }
        if ($s -match '^0x[0-9a-fA-F]+$') { return [int64][Convert]::ToInt64($s.Substring(2), 16) }
        throw "Valor '$Bruto' nao e numerico para o tipo $Tipo"
    }
    "$Bruto"
}

# ---------------------------------------------------------------------------
# tweaks.json
# ---------------------------------------------------------------------------

function ConvertTo-TmxTweaks {
    param(
        [Parameter(Mandatory)] $Winutil,
        [Parameter(Mandatory)] $Overlay,
        [Parameter(Mandatory)] $MapaStoreId
    )

    # --- O overlay cobre todas as chaves do WinUtil? ------------------------
    $chavesWinutil = @($Winutil.PSObject.Properties.Name)
    $faltando = New-Object 'System.Collections.Generic.List[string]'
    foreach ($k in $chavesWinutil) {
        if (-not (Test-TmxConvHasProp -Obj $Overlay -Nome $k)) { $faltando.Add($k) }
    }
    if ($faltando.Count -gt 0) {
        throw ("Overlay incompleto: {0} chave(s) do WinUtil sem entrada em tweaks.overrides.json:`n  {1}" -f `
            $faltando.Count, ($faltando.ToArray() -join "`n  "))
    }

    $idsVistos = New-Object 'System.Collections.Generic.HashSet[string]'
    $saida     = New-Object 'System.Collections.Generic.List[object]'

    foreach ($nomeWpf in $chavesWinutil) {
        $t = $Winutil.$nomeWpf
        $o = $Overlay.$nomeWpf

        foreach ($obrig in 'id', 'nome', 'descricao', 'categoria', 'tier', 'risco', 'presets',
                           'reversivel', 'requerReboot', 'requerConsentimentoExtra', 'porque', 'evidencia') {
            if (-not (Test-TmxConvHasProp -Obj $o -Nome $obrig)) {
                throw "Overlay '$nomeWpf': campo obrigatorio '$obrig' ausente."
            }
        }

        $id = "$($o.id)"
        if (-not $idsVistos.Add($id)) { throw "Overlay '$nomeWpf': id '$id' duplicado." }

        # --- controle --------------------------------------------------------
        $tipoWinutil = "$(Get-TmxConvProp -Obj $t -Nome 'Type' -Padrao '')"
        $controle = 'checkbox'
        if ($tipoWinutil -eq 'Toggle')   { $controle = 'toggle' }
        if ($tipoWinutil -eq 'Combobox') { $controle = 'combobox' }
        if ($tipoWinutil -eq 'Button')   { $controle = 'button' }
        $controleOverlay = Get-TmxConvProp -Obj $o -Nome 'controle' -Padrao $null
        if ($controleOverlay) { $controle = "$controleOverlay" }
        $ehToggle   = ($controle -eq 'toggle')
        $ehCombobox = ($controle -eq 'combobox')

        $acoes    = New-Object 'System.Collections.Generic.List[object]'
        $acoesOff = New-Object 'System.Collections.Generic.List[object]'

        # --- registry[] ------------------------------------------------------
        # Combobox nao usa o registry[] generico: no WinUtil os valores vivem em
        # 'Values' por item do combo, e aqui o overlay descreve as opcoes inteiras.
        if (-not $ehCombobox) {
            foreach ($r in (Get-TmxConvArray -Obj $t -Nome 'registry')) {
                if ($null -eq $r) { continue }
                $path  = "$($r.Path)"
                $name  = "$($r.Name)"
                $tipo  = "$(Get-TmxConvProp -Obj $r -Nome 'Type' -Padrao 'DWord')"
                $bruto = Get-TmxConvProp -Obj $r -Nome 'Value' -Padrao $null

                if ("$bruto" -eq '<RemoveEntry>') {
                    $acoes.Add((New-TmxAcaoRegistry -Path $path -Name $name -ValueType $tipo -Remover))
                } elseif ($null -ne $bruto -and "$bruto" -ne '') {
                    $acoes.Add((New-TmxAcaoRegistry -Path $path -Name $name -ValueType $tipo `
                        -Value (ConvertTo-TmxValorRegistro -Bruto $bruto -Tipo $tipo)))
                }

                # Toggle: o estado DESLIGADO vem de OriginalValue.
                if ($ehToggle) {
                    $orig = Get-TmxConvProp -Obj $r -Nome 'OriginalValue' -Padrao $null
                    if ("$orig" -eq '<RemoveEntry>') {
                        $acoesOff.Add((New-TmxAcaoRegistry -Path $path -Name $name -ValueType $tipo -Remover))
                    } elseif ($null -ne $orig -and "$orig" -ne '') {
                        $acoesOff.Add((New-TmxAcaoRegistry -Path $path -Name $name -ValueType $tipo `
                            -Value (ConvertTo-TmxValorRegistro -Bruto $orig -Tipo $tipo)))
                    }
                }
            }
        }

        # --- service[] -------------------------------------------------------
        foreach ($s in (Get-TmxConvArray -Obj $t -Nome 'service')) {
            if ($null -eq $s) { continue }
            $acoes.Add([ordered]@{ tipo = 'service'; nome = "$($s.Name)"; tipoInicio = "$($s.StartupType)" })
        }

        # --- ScheduledTask[] -------------------------------------------------
        foreach ($k in (Get-TmxConvArray -Obj $t -Nome 'ScheduledTask')) {
            if ($null -eq $k) { continue }
            $nomeTarefa = "$($k.Name)"
            $caminho    = '\'
            $ultima     = $nomeTarefa.LastIndexOf('\')
            if ($ultima -ge 0) {
                $caminho    = $nomeTarefa.Substring(0, $ultima + 1)
                $nomeTarefa = $nomeTarefa.Substring($ultima + 1)
            }
            $acoes.Add([ordered]@{ tipo = 'scheduledTask'; caminho = $caminho; nome = $nomeTarefa; estado = "$($k.State)" })
        }

        # --- appx[] ----------------------------------------------------------
        foreach ($a in (Get-TmxConvArray -Obj $t -Nome 'appx')) {
            if ($null -eq $a) { continue }
            $pacote  = "$a"
            $storeId = $null
            if ($MapaStoreId.ContainsKey($pacote)) { $storeId = $MapaStoreId[$pacote] }
            $acoes.Add([ordered]@{ tipo = 'appx'; pacote = $pacote; storeId = $storeId; todosUsuarios = $true })
        }

        # --- InvokeScript[] -> funcao nomeada --------------------------------
        $scripts       = Get-TmxConvArray -Obj $t -Nome 'InvokeScript'
        $mapaFuncoes   = Get-TmxConvProp  -Obj $o -Nome 'funcoes' -Padrao $null
        $ignorarScript = [bool](Get-TmxConvProp -Obj $o -Nome 'ignorarScripts' -Padrao $false)
        $motivoIgnorar = Get-TmxConvProp -Obj $o -Nome 'motivoIgnorarScripts' -Padrao $null
        $funcoesVistas = New-Object 'System.Collections.Generic.HashSet[string]'

        if ($ignorarScript -and -not $motivoIgnorar) {
            throw "Overlay '$nomeWpf': 'ignorarScripts' exige 'motivoIgnorarScripts'."
        }

        if ($mapaFuncoes -is [string]) {
            # String unica: vale para o InvokeScript[0] ou, quando nao ha script
            # nenhum (botoes), define a unica acao do tweak.
            $fn = "$mapaFuncoes"
            if ($funcoesVistas.Add($fn)) {
                $acoes.Add([ordered]@{ tipo = 'funcao'; nome = $fn; parametros = [ordered]@{} })
            }
        } elseif ($null -ne $mapaFuncoes) {
            for ($i = 0; $i -lt $scripts.Count; $i++) {
                $fn = Get-TmxConvProp -Obj $mapaFuncoes -Nome "$i" -Padrao $null
                if (-not $fn) {
                    if ($ignorarScript) { continue }
                    throw "Overlay '$nomeWpf': InvokeScript[$i] sem mapeamento em 'funcoes' (e sem 'ignorarScripts')."
                }
                if ($funcoesVistas.Add("$fn")) {
                    $acoes.Add([ordered]@{ tipo = 'funcao'; nome = "$fn"; parametros = [ordered]@{} })
                }
            }
        } elseif ($scripts.Count -gt 0 -and -not $ignorarScript) {
            throw "Overlay '$nomeWpf': o tweak tem $($scripts.Count) InvokeScript e o overlay nao declara 'funcoes' nem 'ignorarScripts'."
        }

        # --- acoesExtras do overlay ------------------------------------------
        foreach ($extra in (Get-TmxConvArray -Obj $o -Nome 'acoesExtras')) {
            if ($null -eq $extra) { continue }
            $acoes.Add((ConvertTo-TmxAcaoOrdenada -Acao $extra))
        }

        # --- opcoes (combobox) -----------------------------------------------
        $opcoes = New-Object 'System.Collections.Generic.List[object]'
        foreach ($op in (Get-TmxConvArray -Obj $o -Nome 'opcoes')) {
            if ($null -eq $op) { continue }
            $acoesOp = New-Object 'System.Collections.Generic.List[object]'
            foreach ($ao in (Get-TmxConvArray -Obj $op -Nome 'acoes')) {
                if ($null -eq $ao) { continue }
                $acoesOp.Add((ConvertTo-TmxAcaoOrdenada -Acao $ao))
            }
            $opcoes.Add([ordered]@{
                valor  = "$($op.valor)"
                rotulo = "$($op.rotulo)"
                acoes  = $acoesOp.ToArray()
            })
        }
        if ($ehCombobox -and $opcoes.Count -lt 2) {
            throw "Overlay '$nomeWpf': combobox exige ao menos 2 'opcoes' no overlay."
        }

        # --- consentimento ----------------------------------------------------
        $cons = Get-TmxConvProp -Obj $o -Nome 'consentimento' -Padrao $null
        $consentimento = [ordered]@{
            titulo   = Get-TmxConvProp -Obj $cons -Nome 'titulo'   -Padrao $null
            tradeoff = Get-TmxConvProp -Obj $cons -Nome 'tradeoff' -Padrao $null
            frase    = Get-TmxConvProp -Obj $cons -Nome 'frase'    -Padrao $null
        }

        # --- condicoes --------------------------------------------------------
        $cond = Get-TmxConvProp -Obj $o -Nome 'condicoes' -Padrao $null
        $condicoes = [ordered]@{
            requer     = (Get-TmxConvArray -Obj $cond -Nome 'requer')
            bloqueiaSe = (Get-TmxConvArray -Obj $cond -Nome 'bloqueiaSe')
        }

        # --- folclore ---------------------------------------------------------
        $folcloreSrc = Get-TmxConvProp -Obj $o -Nome 'folclore' -Padrao $null
        $folclore = $null
        if ($folcloreSrc) {
            $folclore = [ordered]@{
                oQueE                 = "$(Get-TmxConvProp -Obj $folcloreSrc -Nome 'oQueE' -Padrao '')"
                porqueCircula         = "$(Get-TmxConvProp -Obj $folcloreSrc -Nome 'porqueCircula' -Padrao '')"
                porqueNaoRecomendamos = "$(Get-TmxConvProp -Obj $folcloreSrc -Nome 'porqueNaoRecomendamos' -Padrao '')"
            }
            $seQuiser = Get-TmxConvProp -Obj $folcloreSrc -Nome 'seVoceQuiserMesmo' -Padrao $null
            if ($seQuiser) { $folclore['seVoceQuiserMesmo'] = "$seQuiser" }
        }

        # --- modo/categoriasV2/textos didaticos/i18n (Task T2, opcionais) -----
        # Copiados do overlay quando presentes; sem eles o campo fica null/[]
        # (Test-TmxCatalog valida o formato quando presente, mas nao exige).
        $categoriasV2 = Get-TmxConvArray -Obj $o -Nome 'categoriasV2'
        $i18nSrc = Get-TmxConvProp -Obj $o -Nome 'i18n' -Padrao $null
        $i18n = $null
        if ($i18nSrc) {
            $enSrc = Get-TmxConvProp -Obj $i18nSrc -Nome 'en' -Padrao $null
            if ($enSrc) {
                $i18n = [ordered]@{
                    en = [ordered]@{
                        nome      = Get-TmxConvProp -Obj $enSrc -Nome 'nome'      -Padrao $null
                        oQueFaz   = Get-TmxConvProp -Obj $enSrc -Nome 'oQueFaz'   -Padrao $null
                        beneficio = Get-TmxConvProp -Obj $enSrc -Nome 'beneficio' -Padrao $null
                        atencao   = Get-TmxConvProp -Obj $enSrc -Nome 'atencao'   -Padrao $null
                    }
                }
            }
        }

        # --- monta o tweak ----------------------------------------------------
        $tweak = [ordered]@{
            id     = $id
            origem = [ordered]@{
                winutil = $nomeWpf
                link    = Get-TmxConvProp -Obj $t -Nome 'link' -Padrao $null
            }
            nome                     = "$($o.nome)"
            descricao                = "$($o.descricao)"
            categoria                = "$($o.categoria)"
            tier                     = "$($o.tier)"
            risco                    = "$($o.risco)"
            presets                  = (Get-TmxConvArray -Obj $o -Nome 'presets')
            controle                 = $controle
            opcoes                   = $opcoes.ToArray()
            grupo                    = Get-TmxConvProp -Obj $o -Nome 'grupo' -Padrao $null
            reversivel               = "$($o.reversivel)"
            requerReboot             = [bool]$o.requerReboot
            requerConsentimentoExtra = [bool]$o.requerConsentimentoExtra
            consentimento            = $consentimento
            condicoes                = $condicoes
            porque                   = "$($o.porque)"
            evidencia                = "$($o.evidencia)"
            modo                     = Get-TmxConvProp -Obj $o -Nome 'modo' -Padrao $null
            categoriasV2             = $categoriasV2
            oQueFaz                  = Get-TmxConvProp -Obj $o -Nome 'oQueFaz'   -Padrao $null
            beneficio                = Get-TmxConvProp -Obj $o -Nome 'beneficio' -Padrao $null
            atencao                  = Get-TmxConvProp -Obj $o -Nome 'atencao'   -Padrao $null
            i18n                     = $i18n
            folclore                 = $folclore
            instrucoes               = Get-TmxConvProp -Obj $o -Nome 'instrucoes' -Padrao $null
            posAplicar               = Get-TmxConvProp -Obj $o -Nome 'posAplicar' -Padrao $null
        }

        $tweak['acoes'] = $acoes.ToArray()
        if ($ehToggle) {
            # Toggle e controle de dois estados: acoes[] liga, toggleDesligar[] desliga.
            # As acoes de desligar saem de OriginalValue no catalogo do WinUtil. O estado
            # ATUAL nunca vem do catalogo: quem le e o Test do engine, ao vivo.
            # O nome do campo e 'toggleDesligar' porque e esse o campo que
            # Test-TmxCatalog valida (Engine/Catalog.ps1, Test-TmxAcaoList).
            $tweak['toggleDesligar'] = $acoesOff.ToArray()
        }

        $saida.Add($tweak)
    }

    , ($saida.ToArray())
}

# ---------------------------------------------------------------------------
# applications.json
# ---------------------------------------------------------------------------

$script:TmxCategoriaApp = @{
    'Utilities'        = 'Utilitarios'
    'Document'         = 'Documentos'
    'Pro Tools'        = 'Ferramentas Pro'
    'Multimedia Tools' = 'Multimidia'
    'Microsoft Tools'  = 'Ferramentas Microsoft'
    'Games'            = 'Jogos'
    'Browsers'         = 'Navegadores'
    'Development'      = 'Desenvolvimento'
    'Communications'   = 'Comunicacao'
    'Selfhosted Tools' = 'Auto-hospedado'
}

# categoria (pt-BR, ja mapeada acima) -> categoriaV2 (filtro fechado da Task T2:
# navegadores, comunicacao, jogos, desenvolvimento, multimidia, utilitarios).
# 'Ferramentas Pro', 'Ferramentas Microsoft', 'Documentos' e 'Auto-hospedado'
# nao tem filtro proprio no pedido do usuario, entao caem em 'utilitarios'.
$script:TmxCategoriaV2App = @{
    'Navegadores'           = 'navegadores'
    'Comunicacao'           = 'comunicacao'
    'Jogos'                 = 'jogos'
    'Desenvolvimento'       = 'desenvolvimento'
    'Multimidia'            = 'multimidia'
    'Utilitarios'           = 'utilitarios'
    'Ferramentas Pro'       = 'utilitarios'
    'Ferramentas Microsoft' = 'utilitarios'
    'Documentos'            = 'utilitarios'
    'Auto-hospedado'        = 'utilitarios'
}

function ConvertTo-TmxApplications {
    param([Parameter(Mandatory)] $Winutil, $Overlay)

    $saida = New-Object 'System.Collections.Generic.List[object]'
    foreach ($p in $Winutil.PSObject.Properties) {
        $chave = $p.Name
        $v = $p.Value

        $id = $chave
        if ($id -like 'WPFInstall*') { $id = $id.Substring('WPFInstall'.Length) }
        $id = $id.ToLowerInvariant()

        $ov = $null
        if ($Overlay -and (Test-TmxConvHasProp -Obj $Overlay -Nome $chave)) { $ov = $Overlay.$chave }

        $catOriginal = "$(Get-TmxConvProp -Obj $v -Nome 'category' -Padrao '')"
        $categoria = $catOriginal
        if ($script:TmxCategoriaApp.ContainsKey($catOriginal)) { $categoria = $script:TmxCategoriaApp[$catOriginal] }

        $categoriaV2 = 'utilitarios'
        if ($script:TmxCategoriaV2App.ContainsKey($categoria)) { $categoriaV2 = $script:TmxCategoriaV2App[$categoria] }

        $nome = "$(Get-TmxConvProp -Obj $v -Nome 'content' -Padrao $chave)"
        $nomeOv = Get-TmxConvProp -Obj $ov -Nome 'nome' -Padrao $null
        if ($nomeOv) { $nome = "$nomeOv" }

        $descricao = "$(Get-TmxConvProp -Obj $v -Nome 'description' -Padrao '')"
        $descOv = Get-TmxConvProp -Obj $ov -Nome 'descricao' -Padrao $null
        if ($descOv) { $descricao = "$descOv" }

        # i18n.en.descricao (Task T2): por padrao usa a description original do
        # WinUtil (ja em ingles natural, mesma fonte publica de todo o catalogo);
        # o overlay pode sobrescrever com 'i18n.en.descricao' quando quiser um
        # texto proprio (ex.: os 13 apps que nao existem no WinUtil de referencia).
        $descEn = "$(Get-TmxConvProp -Obj $v -Nome 'description' -Padrao '')"
        $i18nOv = Get-TmxConvProp -Obj $ov -Nome 'i18n' -Padrao $null
        if ($i18nOv) {
            $enOv = Get-TmxConvProp -Obj $i18nOv -Nome 'en' -Padrao $null
            $descEnOv = Get-TmxConvProp -Obj $enOv -Nome 'descricao' -Padrao $null
            if ($descEnOv) { $descEn = "$descEnOv" }
        }

        # icon: nao existe no catalogo do WinUtil - padrao null, so o overlay
        # pode preencher (mesma ideia de 'descricao' acima).
        $icon = $null
        $iconOv = Get-TmxConvProp -Obj $ov -Nome 'icon' -Padrao $null
        if ($iconOv) { $icon = "$iconOv" }

        $saida.Add([ordered]@{
            id          = $id
            nome        = $nome
            descricao   = $descricao
            categoria   = $categoria
            categoriaV2 = $categoriaV2
            winget      = Get-TmxConvProp -Obj $v -Nome 'winget' -Padrao $null
            choco       = Get-TmxConvProp -Obj $v -Nome 'choco'  -Padrao $null
            link        = Get-TmxConvProp -Obj $v -Nome 'link'   -Padrao $null
            icon        = $icon
            foss        = [bool](Get-TmxConvProp -Obj $v -Nome 'foss' -Padrao $false)
            i18n        = [ordered]@{ en = [ordered]@{ descricao = $descEn } }
        })
    }
    , ($saida.ToArray())
}

# ---------------------------------------------------------------------------
# feature.json
# ---------------------------------------------------------------------------

$script:TmxCategoriaFeature = @{
    'Features'                              = 'Recursos'
    'Fixes'                                 = 'Correcoes'
    'Legacy Windows Panels'                 = 'Paineis'
    'Powershell Profile Powershell 7+ Only' = 'Perfil PowerShell'
    'Remote Access'                         = 'Remoto'
}

# WinUtil 'function' -> nome alvo no TweakMaxing (implementacao fica com a Task 12).
$script:TmxMapaFuncaoFeature = @{
    'Invoke-WPFFixesNTPPool'           = 'Invoke-TmxFixNtpPool'
    'Invoke-WPFFixesUpdate'            = 'Invoke-TmxFixWindowsUpdate'
    'Invoke-WPFFixesNetwork'           = 'Invoke-TmxFixNetwork'
    'Invoke-WPFFixesWinget'            = 'Invoke-TmxFixWinget'
    'Invoke-WPFSystemRepair'           = 'Invoke-TmxFixSystemRepair'
    'Invoke-WPFPanelAutologin'         = 'Invoke-TmxFixAutologin'
    'Invoke-WPFFeatureInstall'         = 'Invoke-TmxFeatureInstall'
    'Invoke-WinUtilInstallPSProfile'   = 'Invoke-TmxInstallPSProfile'
    'Invoke-WinUtilUninstallPSProfile' = 'Invoke-TmxUninstallPSProfile'
    'Invoke-WPFSSHServer'              = 'Invoke-TmxSSHServer'
}

function ConvertTo-TmxFeatures {
    param([Parameter(Mandatory)] $Winutil)

    $saida = New-Object 'System.Collections.Generic.List[object]'
    foreach ($p in $Winutil.PSObject.Properties) {
        $v = $p.Value
        $catOriginal = "$(Get-TmxConvProp -Obj $v -Nome 'category' -Padrao '')"
        $categoria = $catOriginal
        if ($script:TmxCategoriaFeature.ContainsKey($catOriginal)) { $categoria = $script:TmxCategoriaFeature[$catOriginal] }

        $features = Get-TmxConvArray -Obj $v -Nome 'feature'
        $controle = 'button'
        if ($features.Count -gt 0) { $controle = 'toggle' }

        $fnWinutil = Get-TmxConvProp -Obj $v -Nome 'function' -Padrao $null
        $fnAlvo = $null
        if ($fnWinutil -and $script:TmxMapaFuncaoFeature.ContainsKey("$fnWinutil")) {
            $fnAlvo = $script:TmxMapaFuncaoFeature["$fnWinutil"]
        }

        # 'comando' guarda apenas comandos de uma linha (paineis legados: control,
        # main.cpl, ncpa.cpl...). Script multi-linha nao entra no catalogo: vira
        # implementacao nomeada na Task 12.
        $comando = $null
        $scripts = Get-TmxConvArray -Obj $v -Nome 'InvokeScript'
        if ($scripts.Count -eq 1) {
            $s = "$($scripts[0])".Trim()
            if ($s -and $s -notmatch "[`r`n]") { $comando = $s }
        }

        $saida.Add([ordered]@{
            id            = $p.Name
            nome          = "$(Get-TmxConvProp -Obj $v -Nome 'Content' -Padrao $p.Name)"
            descricao     = "$(Get-TmxConvProp -Obj $v -Nome 'Description' -Padrao '')"
            categoria     = $categoria
            controle      = $controle
            feature       = $features
            funcaoWinUtil = $fnWinutil
            funcao        = $fnAlvo
            comando       = $comando
        })
    }
    , ($saida.ToArray())
}

# ---------------------------------------------------------------------------
# appx.json / dns.json
# ---------------------------------------------------------------------------

function ConvertTo-TmxAppx {
    param([Parameter(Mandatory)] $Winutil)
    $saida = New-Object 'System.Collections.Generic.List[object]'
    foreach ($p in $Winutil.PSObject.Properties) {
        $v = $p.Value
        $saida.Add([ordered]@{
            id        = $p.Name
            nome      = "$(Get-TmxConvProp -Obj $v -Nome 'Content' -Padrao $p.Name)"
            descricao = "$(Get-TmxConvProp -Obj $v -Nome 'Description' -Padrao '')"
            pacote    = "$(Get-TmxConvProp -Obj $v -Nome 'PackageId' -Padrao '')"
            storeId   = Get-TmxConvProp -Obj $v -Nome 'StoreId' -Padrao $null
        })
    }
    , ($saida.ToArray())
}

function ConvertTo-TmxDns {
    param([Parameter(Mandatory)] $Winutil)
    $saida = New-Object 'System.Collections.Generic.List[object]'
    foreach ($p in $Winutil.PSObject.Properties) {
        $v = $p.Value
        $saida.Add([ordered]@{
            id          = $p.Name
            nome        = ($p.Name -replace '_', ' ')
            primario    = Get-TmxConvProp -Obj $v -Nome 'Primary'     -Padrao $null
            secundario  = Get-TmxConvProp -Obj $v -Nome 'Secondary'   -Padrao $null
            primario6   = Get-TmxConvProp -Obj $v -Nome 'Primary6'    -Padrao $null
            secundario6 = Get-TmxConvProp -Obj $v -Nome 'Secondary6'  -Padrao $null
            doh         = Get-TmxConvProp -Obj $v -Nome 'DohTemplate' -Padrao $null
            benchmark   = [bool](Get-TmxConvProp -Obj $v -Nome 'BenchmarkEligible' -Padrao $false)
        })
    }
    , ($saida.ToArray())
}

# ---------------------------------------------------------------------------
# Execucao
# ---------------------------------------------------------------------------

# Ponto de corte para os testes: com -SomenteDefinicoes o script so define as
# funcoes acima e sai, sem ler nem escrever arquivo nenhum.
if ($SomenteDefinicoes) { return }

$refDir = $Reference
if (-not [System.IO.Path]::IsPathRooted($refDir)) { $refDir = Join-Path (Get-Location).Path $refDir }
$outDir = $Out
if (-not [System.IO.Path]::IsPathRooted($outDir)) { $outDir = Join-Path (Get-Location).Path $outDir }

if (-not (Test-Path -LiteralPath $refDir)) {
    throw "Referencia do WinUtil nao encontrada: '$refDir'. Clone o WinUtil em reference/winutil (ou passe -Reference)."
}

$configDir = Join-Path $refDir 'config'
$ausentes = New-Object 'System.Collections.Generic.List[string]'
foreach ($a in 'tweaks.json', 'applications.json', 'feature.json', 'appx.json', 'dns.json') {
    if (-not (Test-Path -LiteralPath (Join-Path $configDir $a))) { $ausentes.Add("config\$a") }
}
if ($ausentes.Count -gt 0) {
    throw ("Referencia do WinUtil incompleta em '$refDir':`n  " + ($ausentes.ToArray() -join "`n  "))
}

if (-not $Overlay) { $Overlay = Join-Path $outDir 'overlay\tweaks.overrides.json' }
if (-not $OverlayApplications) { $OverlayApplications = Join-Path $outDir 'overlay\applications.overrides.json' }
if (-not (Test-Path -LiteralPath $Overlay)) { throw "Overlay de tweaks nao encontrado: '$Overlay'." }

$winTweaks = Read-TmxJsonFile -Path (Join-Path $configDir 'tweaks.json')
$winApps   = Read-TmxJsonFile -Path (Join-Path $configDir 'applications.json')
$winFeat   = Read-TmxJsonFile -Path (Join-Path $configDir 'feature.json')
$winAppx   = Read-TmxJsonFile -Path (Join-Path $configDir 'appx.json')
$winDns    = Read-TmxJsonFile -Path (Join-Path $configDir 'dns.json')

$ovTweaks = Read-TmxJsonFile -Path $Overlay
$ovApps   = $null
if (Test-Path -LiteralPath $OverlayApplications) { $ovApps = Read-TmxJsonFile -Path $OverlayApplications }

# PackageId -> StoreId: e o que da caminho de volta para uma acao appx.
$mapaStoreId = @{}
foreach ($p in $winAppx.PSObject.Properties) {
    $pacoteId = "$(Get-TmxConvProp -Obj $p.Value -Nome 'PackageId' -Padrao '')"
    $storeId  = Get-TmxConvProp -Obj $p.Value -Nome 'StoreId' -Padrao $null
    if ($pacoteId -and $storeId -and -not $mapaStoreId.ContainsKey($pacoteId)) { $mapaStoreId[$pacoteId] = "$storeId" }
}

$tweaks = ConvertTo-TmxTweaks -Winutil $winTweaks -Overlay $ovTweaks -MapaStoreId $mapaStoreId
$apps   = ConvertTo-TmxApplications -Winutil $winApps -Overlay $ovApps
$feats  = ConvertTo-TmxFeatures -Winutil $winFeat
$appxs  = ConvertTo-TmxAppx -Winutil $winAppx
$dnss   = ConvertTo-TmxDns -Winutil $winDns

if (-not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }

Save-TmxJsonFile -Path (Join-Path $outDir 'tweaks.json')       -Valor ([ordered]@{ tweaks      = $tweaks })
Save-TmxJsonFile -Path (Join-Path $outDir 'applications.json') -Valor ([ordered]@{ aplicativos = $apps })
Save-TmxJsonFile -Path (Join-Path $outDir 'feature.json')      -Valor ([ordered]@{ recursos    = $feats })
Save-TmxJsonFile -Path (Join-Path $outDir 'appx.json')         -Valor ([ordered]@{ appx        = $appxs })
Save-TmxJsonFile -Path (Join-Path $outDir 'dns.json')          -Valor ([ordered]@{ dns         = $dnss })

$resumo = [pscustomobject]@{
    tweaks      = $tweaks.Count
    aplicativos = $apps.Count
    recursos    = $feats.Count
    appx        = $appxs.Count
    dns         = $dnss.Count
    saida       = $outDir
}

Write-Output ('Convert-WinUtilCatalog: tweaks={0} aplicativos={1} recursos={2} appx={3} dns={4} -> {5}' -f `
    $resumo.tweaks, $resumo.aplicativos, $resumo.recursos, $resumo.appx, $resumo.dns, $resumo.saida)
$resumo
