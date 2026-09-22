# Engine/Condition.ps1
# Mini-avaliador de condicoes contra o objeto de perfil. Sem Invoke-Expression.
#
# Gramatica:  <caminho> <operador> [<valor>] [:: <motivo>]
#   caminho   : os.build, storage.discoSistema.tipo, network.adaptadorAtivo.tipo ...
#   operador  : == != >= <= > < contains exists
#   valor     : numero | true | false | null | texto (com ou sem aspas)
#   motivo    : texto livre exibido ao usuario quando a condicao decide algo
#
# Semantica:
#   - Comparacao numerica quando os dois lados sao numeros; senao texto, sem
#     diferenciar maiusculas (ordinal para < >, o que faz datas yyyy-MM-dd funcionarem).
#   - contains: array -> contem o item; texto -> substring.
#   - exists: caminho resolve para algo diferente de $null.
#   - Caminho ausente/$null em comparacao -> resultado $null ("indeterminado"),
#     exceto "== null" / "!= null".

$script:TmxConditionRegex = '^\s*(?<path>[A-Za-z_][\w]*(?:\.[A-Za-z_][\w]*)*)\s+(?<op>==|!=|>=|<=|>|<|contains|exists)(?:\s+(?<value>.*?))?\s*$'

function ConvertFrom-TmxCondition {
    <#
    .SYNOPSIS
        Faz o parse de uma expressao. Lanca se invalida.
    #>
    param([Parameter(Mandatory)] [string] $Expression)

    $expr = $Expression
    $motivo = $null
    $sep = $expr.IndexOf('::')
    if ($sep -ge 0) {
        $motivo = $expr.Substring($sep + 2).Trim()
        $expr   = $expr.Substring(0, $sep)
    }

    $m = [regex]::Match($expr, $script:TmxConditionRegex)
    if (-not $m.Success) { throw "Condicao invalida: '$Expression'" }

    $op    = $m.Groups['op'].Value
    $value = if ($m.Groups['value'].Success) { $m.Groups['value'].Value.Trim() } else { $null }

    if ($op -eq 'exists' -and $value) { throw "'exists' nao aceita valor: '$Expression'" }
    if ($op -ne 'exists' -and ($null -eq $value -or $value -eq '')) { throw "Operador '$op' exige um valor: '$Expression'" }

    if ($value -and $value.Length -ge 2 -and (($value[0] -eq '"' -and $value[-1] -eq '"') -or ($value[0] -eq "'" -and $value[-1] -eq "'"))) {
        $value = $value.Substring(1, $value.Length - 2)
    }

    [pscustomobject]@{ expressao = $Expression; caminho = $m.Groups['path'].Value; operador = $op; valor = $value; motivo = $motivo }
}

function Resolve-TmxProfilePath {
    <#
    .SYNOPSIS
        Navega "a.b.c" no objeto. Retorna { encontrado, valor }.
    #>
    param(
        [Parameter(Mandatory)] $Object,
        [Parameter(Mandatory)] [string] $Path
    )
    $cur = $Object
    foreach ($seg in ($Path -split '\.')) {
        if ($null -eq $cur) { return [pscustomobject]@{ encontrado = $false; valor = $null } }
        $prop = $null
        if ($cur -is [System.Collections.IDictionary]) {
            if (-not $cur.Contains($seg)) { return [pscustomobject]@{ encontrado = $false; valor = $null } }
            $cur = $cur[$seg]
        } else {
            $prop = $cur.PSObject.Properties[$seg]
            if ($null -eq $prop) { return [pscustomobject]@{ encontrado = $false; valor = $null } }
            $cur = $prop.Value
        }
    }
    [pscustomobject]@{ encontrado = $true; valor = $cur }
}

function ConvertTo-TmxConditionLiteral {
    # Converte o texto do valor no tipo apropriado.
    param([string] $Text)
    if ($null -eq $Text) { return $null }
    switch -Regex ($Text) {
        '^(?i)null$'  { return [pscustomobject]@{ tipo = 'null'; valor = $null } }
        '^(?i)true$'  { return [pscustomobject]@{ tipo = 'bool'; valor = $true } }
        '^(?i)false$' { return [pscustomobject]@{ tipo = 'bool'; valor = $false } }
        '^-?\d+(\.\d+)?$' { return [pscustomobject]@{ tipo = 'num'; valor = [double]$Text } }
        '^0x[0-9a-fA-F]+$' { return [pscustomobject]@{ tipo = 'num'; valor = [double][Convert]::ToInt64($Text.Substring(2), 16) } }
        default       { return [pscustomobject]@{ tipo = 'str'; valor = $Text } }
    }
}

function ConvertTo-TmxComparable {
    # Normaliza o valor do perfil para comparacao com um literal.
    param($Value, [string] $LiteralTipo)
    if ($null -eq $Value) { return $null }
    switch ($LiteralTipo) {
        'num'  {
            if ($Value -is [bool]) { return $null }
            $s = "$Value"
            if ($s -match '^0x[0-9a-fA-F]+$') { return [double][Convert]::ToInt64($s.Substring(2), 16) }
            $d = 0.0
            if ([double]::TryParse($s, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$d)) { return $d }
            return $null
        }
        'bool' {
            if ($Value -is [bool]) { return $Value }
            if ("$Value" -match '^(?i)(true|1|yes|sim)$')  { return $true }
            if ("$Value" -match '^(?i)(false|0|no|nao)$') { return $false }
            return $null
        }
        default { return "$Value" }
    }
}

function Test-TmxCondition {
    <#
    .SYNOPSIS
        Avalia uma expressao contra o perfil. Nunca lanca por dados; lanca so por sintaxe.
    .OUTPUTS
        { expressao, caminho, operador, valorEsperado, valorAtual, encontrado, resultado ($true/$false/$null), motivo, detalhe }
    #>
    param(
        [Parameter(Mandatory)] [string] $Expression,
        [Parameter(Mandatory)] $Profile
    )

    $c = ConvertFrom-TmxCondition -Expression $Expression
    $r = Resolve-TmxProfilePath -Object $Profile -Path $c.caminho
    $atual = $r.valor

    $out = [pscustomobject]@{
        expressao     = $Expression
        caminho       = $c.caminho
        operador      = $c.operador
        valorEsperado = $c.valor
        valorAtual    = $atual
        encontrado    = $r.encontrado
        resultado     = $null
        motivo        = $c.motivo
        detalhe       = $null
    }

    if ($c.operador -eq 'exists') {
        $out.resultado = ($r.encontrado -and $null -ne $atual)
        $out.detalhe   = if ($out.resultado) { "$($c.caminho) presente" } else { "$($c.caminho) ausente" }
        return $out
    }

    $lit = ConvertTo-TmxConditionLiteral -Text $c.valor

    # null literal: unico caso em que ausencia e uma resposta, nao indeterminacao
    if ($lit.tipo -eq 'null') {
        $isNull = (-not $r.encontrado) -or ($null -eq $atual)
        $out.resultado = switch ($c.operador) { '==' { $isNull } '!=' { -not $isNull } default { $null } }
        $out.detalhe = if ($null -eq $out.resultado) { "operador '$($c.operador)' nao se aplica a null" } else { "$($c.caminho) e " + $(if ($isNull) { 'null' } else { 'nao-null' }) }
        return $out
    }

    if (-not $r.encontrado -or $null -eq $atual) {
        $out.resultado = $null
        $out.detalhe   = "$($c.caminho) ausente no perfil - condicao indeterminada"
        return $out
    }

    # contains
    if ($c.operador -eq 'contains') {
        if ($atual -is [string]) {
            $out.resultado = ($atual.IndexOf("$($lit.valor)", [StringComparison]::OrdinalIgnoreCase) -ge 0)
        } elseif ($atual -is [System.Collections.IEnumerable]) {
            $out.resultado = [bool](@($atual) | Where-Object { "$_" -ieq "$($lit.valor)" } | Select-Object -First 1)
        } else {
            $out.resultado = ("$atual" -ieq "$($lit.valor)")
        }
        $out.detalhe = "$($c.caminho) $(if ($out.resultado) { 'contem' } else { 'nao contem' }) '$($lit.valor)'"
        return $out
    }

    $lhs = ConvertTo-TmxComparable -Value $atual -LiteralTipo $lit.tipo
    if ($null -eq $lhs) {
        $out.resultado = $null
        $out.detalhe   = "valor atual '$atual' nao e comparavel com '$($c.valor)'"
        return $out
    }
    $rhs = $lit.valor

    $out.resultado = switch ($c.operador) {
        '==' { if ($lit.tipo -eq 'str') { "$lhs" -ieq "$rhs" } else { $lhs -eq $rhs } }
        '!=' { if ($lit.tipo -eq 'str') { "$lhs" -ine "$rhs" } else { $lhs -ne $rhs } }
        '>=' { if ($lit.tipo -eq 'str') { [string]::Compare("$lhs", "$rhs", $true) -ge 0 } else { $lhs -ge $rhs } }
        '<=' { if ($lit.tipo -eq 'str') { [string]::Compare("$lhs", "$rhs", $true) -le 0 } else { $lhs -le $rhs } }
        '>'  { if ($lit.tipo -eq 'str') { [string]::Compare("$lhs", "$rhs", $true) -gt 0 } else { $lhs -gt $rhs } }
        '<'  { if ($lit.tipo -eq 'str') { [string]::Compare("$lhs", "$rhs", $true) -lt 0 } else { $lhs -lt $rhs } }
    }
    $out.detalhe = "$($c.caminho) = $atual"
    $out
}
