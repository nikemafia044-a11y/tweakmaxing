# functions/system/Settings.ps1
# <home>\settings.json: leitura com defaults, escrita atomica so para uma
# lista permitida de chaves, e o nome de exibicao efetivo.
#
# 'Constantes' (chaves permitidas, defaults) sao FUNCOES, nunca $script:var:
# um $script:Tmx* so atravessa para a runspace do pool (Start-TmxJob) se
# entrar na lista de permissao de Start-TmxJob.ps1 - uma funcao '-Tmx' e
# copiada automaticamente, sem precisar tocar naquele arquivo (que outra
# tarefa esta editando em paralelo).

function Get-TmxSettingsAllowedKeys {
    <#
    .SYNOPSIS
        Chaves que settings.set aceita. Qualquer outra e recusada.
    #>
    [CmdletBinding()]
    param()
    @('language', 'displayName', 'sidebarCollapsed', 'appliedMode', 'appliedModeAt', 'lastCleanup', 'lastCleanupFreed')
}

function Get-TmxSettingsDefaults {
    [CmdletBinding()]
    param()
    [ordered]@{
        language         = ''
        displayName      = ''
        sidebarCollapsed = $false
        appliedMode      = ''
        appliedModeAt    = $null
        lastCleanup      = $null
        lastCleanupFreed = 0
    }
}

function Get-TmxSettingsPath {
    [CmdletBinding()]
    param()
    Join-Path (Get-TmxHomePath) 'settings.json'
}

function Get-TmxSettingsRaw {
    <#
    .SYNOPSIS
        O que esta em disco, como hashtable simples. {} quando o arquivo nao
        existe ou esta corrompido (nunca lanca).
    #>
    [CmdletBinding()]
    param()
    $caminho = Get-TmxSettingsPath
    if (-not (Test-Path -LiteralPath $caminho)) { return @{} }
    try {
        $doc = Get-Content -LiteralPath $caminho -Raw -Encoding UTF8 | ConvertFrom-Json
        $h = @{}
        if ($doc) {
            foreach ($p in $doc.PSObject.Properties) { $h[$p.Name] = $p.Value }
        }
        $h
    } catch {
        Write-TmxLog -Level WARN -Message "settings.json ilegivel, usando padroes: $($_.Exception.Message)"
        @{}
    }
}

function Save-TmxSettingsRaw {
    <#
    .SYNOPSIS
        Escrita atomica: grava num arquivo temporario e so troca o nome no
        fim - nunca existe um settings.json parcialmente escrito no caminho
        final (uma leitura concorrente sempre ve a versao anterior inteira ou
        a nova inteira).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Settings)

    $caminho = Get-TmxSettingsPath
    $pasta   = Split-Path $caminho -Parent
    if (-not (Test-Path -LiteralPath $pasta)) { New-Item -ItemType Directory -Path $pasta -Force | Out-Null }

    $tmp = "$caminho.tmp"
    ($Settings | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $tmp -Encoding UTF8 -WhatIf:$false
    Move-Item -LiteralPath $tmp -Destination $caminho -Force
}

function Get-TmxSettings {
    <#
    .SYNOPSIS
        Todas as configuracoes, com defaults preenchidos, mais
        'displayNameEfetivo' (displayName ou $env:USERNAME quando vazio).
    #>
    [CmdletBinding()]
    param()

    $defaults = Get-TmxSettingsDefaults
    $raw      = Get-TmxSettingsRaw

    $out = [ordered]@{}
    foreach ($k in $defaults.Keys) {
        $out[$k] = if ($raw.ContainsKey($k) -and $null -ne $raw[$k]) { $raw[$k] } else { $defaults[$k] }
    }

    $out['displayNameEfetivo'] = if ("$($out['displayName'])") { "$($out['displayName'])" } else { "$env:USERNAME" }
    $out
}

function Test-TmxSettingIsoDate {
    <#
    .SYNOPSIS
        Aceita string vazia/nula (limpa o campo) ou uma data ISO valida.
    #>
    [CmdletBinding()]
    param($Value, [Parameter(Mandatory)] [string] $Campo)

    $s = "$Value"
    if (-not $s) { return @{ ok = $true; valor = $null } }

    $dt = [datetime]::MinValue
    $ok = [datetime]::TryParse(
        $s, [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::RoundtripKind, [ref] $dt)
    if (-not $ok) { return @{ ok = $false; erro = "$Campo precisa ser uma data ISO valida" } }
    @{ ok = $true; valor = $s }
}

function Test-TmxSettingValue {
    <#
    .SYNOPSIS
        Valida/normaliza UM valor para UMA chave permitida.
    .OUTPUTS
        { ok; valor } quando valido, { ok=$false; erro } (pt-BR) quando nao.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Key,
        $Value
    )

    switch ($Key) {
        'language' {
            if ("$Value" -cin @('pt-BR', 'en')) { return @{ ok = $true; valor = "$Value" } }
            return @{ ok = $false; erro = "idioma invalido: use 'pt-BR' ou 'en'" }
        }
        'displayName' {
            $s = "$Value"
            if ($s.Length -gt 40) { return @{ ok = $false; erro = 'nome de exibicao muito longo (maximo 40 caracteres)' } }
            return @{ ok = $true; valor = $s }
        }
        'sidebarCollapsed' {
            if ($Value -is [bool]) { return @{ ok = $true; valor = [bool]$Value } }
            if ("$Value" -cin @('true', 'false')) { return @{ ok = $true; valor = ("$Value" -ceq 'true') } }
            return @{ ok = $false; erro = 'sidebarCollapsed precisa ser verdadeiro ou falso' }
        }
        'appliedMode' {
            if ("$Value" -cin @('leve', 'moderado', 'avancado', 'ultimate', '')) { return @{ ok = $true; valor = "$Value" } }
            return @{ ok = $false; erro = "modo invalido: use 'leve', 'moderado', 'avancado', 'ultimate' ou vazio" }
        }
        'appliedModeAt' { return (Test-TmxSettingIsoDate -Value $Value -Campo 'appliedModeAt') }
        'lastCleanup'   { return (Test-TmxSettingIsoDate -Value $Value -Campo 'lastCleanup') }
        'lastCleanupFreed' {
            try {
                $n = [double]"$Value"
                if ($n -lt 0) { return @{ ok = $false; erro = 'lastCleanupFreed nao pode ser negativo' } }
                return @{ ok = $true; valor = $n }
            } catch {
                return @{ ok = $false; erro = 'lastCleanupFreed precisa ser numero' }
            }
        }
        default {
            @{ ok = $false; erro = "chave de configuracao nao permitida: '$Key'" }
        }
    }
}

function Set-TmxSettings {
    <#
    .SYNOPSIS
        Aplica { chave: valor, ... } contra a lista de permissao. Tudo ou
        nada: se qualquer chave for invalida/desconhecida, nada e gravado.
    .OUTPUTS
        O resultado de Get-TmxSettings (ja com o que acabou de ser salvo).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Payload)

    $permitidas = Get-TmxSettingsAllowedKeys

    $chaves = @()
    if ($Payload -is [System.Collections.IDictionary]) {
        $chaves = @($Payload.Keys)
    } elseif ($Payload -is [pscustomobject]) {
        $chaves = @($Payload.PSObject.Properties.Name)
    }
    if ($chaves.Count -eq 0) { throw 'nenhuma configuracao informada' }

    $validados = [ordered]@{}
    foreach ($k in $chaves) {
        if ("$k" -cnotin $permitidas) { throw "chave de configuracao nao permitida: '$k'" }
        $v = if ($Payload -is [System.Collections.IDictionary]) { $Payload[$k] } else { $Payload.$k }
        $r = Test-TmxSettingValue -Key "$k" -Value $v
        if (-not $r.ok) { throw "$k`: $($r.erro)" }
        $validados["$k"] = $r.valor
    }

    $raw = Get-TmxSettingsRaw
    foreach ($k in $validados.Keys) { $raw[$k] = $validados[$k] }
    Save-TmxSettingsRaw -Settings $raw

    Get-TmxSettings
}

function Get-TmxWindowsDisplayName {
    <#
    .SYNOPSIS
        Nome completo do usuario (Win32_UserAccount.FullName), com fallback
        em $env:USERNAME quando a conta nao e encontrada ou nao tem nome
        completo cadastrado.
    #>
    [CmdletBinding()]
    param()
    $conta = Get-TmxWindowsUserAccountSafe
    if ($conta -and "$($conta.FullName)") { return "$($conta.FullName)" }
    "$env:USERNAME"
}
