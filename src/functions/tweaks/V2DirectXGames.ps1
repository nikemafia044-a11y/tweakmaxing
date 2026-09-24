# functions/tweaks/V2DirectXGames.ps1
# JOG-048: otimizacao para jogos em janela.
#
# HKCU\Software\Microsoft\DirectX\UserGpuPreferences\DirectXUserGlobalSettings e
# uma STRING no formato "Chave1=Valor1;Chave2=Valor2;...". E a mesma chave que
# paineis de GPU usam para configuracoes globais do runtime DirectX. Este
# ajuste MESCLA SwapEffectUpgradeEnable=1 no que ja existir, sem apagar outros
# pares, e o Desfazer restaura a string exata anterior (ou apaga o valor, se
# ele nao existia antes).
#
# Raiz de registro sempre resolvivel (explicita > Parametros.path >
# $sync.testMode ? raiz de teste : raiz real), mesmo padrao usado em
# WindowsUpdate.ps1 - assim o modo de teste nunca toca
# HKCU\Software\Microsoft\DirectX de verdade.

$script:TmxDirectXRealPath = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
$script:TmxDirectXTestPath = 'HKCU:\Software\TweakMaxing_Tests\JOG048'
$script:TmxDirectXValueName = 'DirectXUserGlobalSettings'

function Get-TmxDirectXDefaultPath {
    <#
    .SYNOPSIS
        Raiz padrao quando ninguem passou -Path: a raiz de teste quando
        $sync.testMode, senao a chave real do DirectX.
    #>
    [CmdletBinding()]
    param()
    if ($null -ne $sync -and $sync.testMode) { return $script:TmxDirectXTestPath }
    $script:TmxDirectXRealPath
}

function Resolve-TmxDirectXPath {
    <#
    .SYNOPSIS
        Raiz efetiva: -Path explicito vence; senao Parametros.path (o Engine
        passa 'parametros' da acao do catalogo); senao Get-TmxDirectXDefaultPath.
    #>
    [CmdletBinding()]
    param($Parametros, [string] $Path)

    if ($Path) { return $Path }
    $viaParam = "$(Get-TmxActionProp -Action $Parametros -Nome 'path' -Padrao '')"
    if ($viaParam) { return $viaParam }
    Get-TmxDirectXDefaultPath
}

function ConvertFrom-TmxDirectXSettings {
    <#
    .SYNOPSIS
        Faz o parse de "Chave1=Valor1;Chave2=Valor2;" num [ordered] (ordem
        preservada, comparacao de chave sem diferenciar maiusculas). String
        vazia/$null vira dicionario vazio. Pares sem '=' sao ignorados.
    #>
    [CmdletBinding()]
    param([AllowNull()] [AllowEmptyString()] [string] $Texto)

    $out = [ordered]@{}
    if ([string]::IsNullOrEmpty($Texto)) { return $out }
    foreach ($parte in ($Texto -split ';')) {
        if (-not $parte) { continue }
        $idx = $parte.IndexOf('=')
        if ($idx -lt 0) { continue }
        $chave = $parte.Substring(0, $idx)
        $valor = $parte.Substring($idx + 1)
        if (-not $chave) { continue }
        $out[$chave] = $valor
    }
    $out
}

function ConvertTo-TmxDirectXSettings {
    <#
    .SYNOPSIS
        Serializa de volta para "Chave1=Valor1;Chave2=Valor2;" na ordem do dicionario.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Pares)

    $sb = New-Object System.Text.StringBuilder
    foreach ($chave in $Pares.Keys) {
        [void]$sb.Append("$chave=$($Pares[$chave]);")
    }
    $sb.ToString()
}

function Test-TmxDirectXWindowedGames {
    [CmdletBinding()]
    param($Tweak, $Profile, $Parametros)

    $path  = Resolve-TmxDirectXPath -Parametros $Parametros
    $atual = Get-TmxV2RegistryStringValue -Path $path -Name $script:TmxDirectXValueName
    $pares = ConvertFrom-TmxDirectXSettings -Texto $atual

    $ok = ($pares.Contains('SwapEffectUpgradeEnable') -and "$($pares['SwapEffectUpgradeEnable'])" -eq '1')
    [pscustomobject]@{
        aplicado = $ok
        atual    = $(if ($null -eq $atual) { '<ausente>' } else { $atual })
        esperado = 'SwapEffectUpgradeEnable=1 presente na string'
        detalhe  = "$($script:TmxDirectXValueName): $(if ($null -eq $atual) { '<ausente>' } else { $atual })"
    }
}

function Set-TmxDirectXWindowedGames {
    [CmdletBinding()]
    param($Tweak, $Profile, $Parametros)

    $path  = Resolve-TmxDirectXPath -Parametros $Parametros
    $name  = $script:TmxDirectXValueName
    $antigo = Get-TmxV2RegistryStringValue -Path $path -Name $name
    $existiaAntes = ($null -ne $antigo)

    $pares = ConvertFrom-TmxDirectXSettings -Texto $antigo
    if ($pares.Contains('SwapEffectUpgradeEnable') -and "$($pares['SwapEffectUpgradeEnable'])" -eq '1') {
        return [pscustomobject]@{ ok = $true; naoAplicavel = $true; detalhe = 'SwapEffectUpgradeEnable ja esta em 1' }
    }
    $pares['SwapEffectUpgradeEnable'] = '1'
    $novo = ConvertTo-TmxDirectXSettings -Pares $pares

    $rec = New-TmxCmdletRecord -TweakId "$($Tweak.id)" -Funcao 'Set-TmxDirectXWindowedGames' `
            -Alvo "$path\$name" `
            -Estado @{ path = $path; name = $name; valorAnterior = $antigo; existiaAntes = $existiaAntes } `
            -ValorAnterior $(if ($existiaAntes) { $antigo } else { '<ausente>' }) -ValorNovo $novo

    try {
        Set-TmxV2RegistryStringValue -Path $path -Name $name -Value $novo
        Complete-TmxStateRecord -Record $rec -Ok $true | Out-Null
        [pscustomobject]@{ ok = $true; detalhe = "SwapEffectUpgradeEnable=1 mesclado em $name"; registro = $rec }
    } catch {
        Complete-TmxStateRecord -Record $rec -Ok $false -Erro $_.Exception.Message | Out-Null
        [pscustomobject]@{ ok = $false; detalhe = $_.Exception.Message; registro = $rec }
    }
}

function Undo-TmxDirectXWindowedGames {
    [CmdletBinding()]
    param($Estado)

    if (-not $Estado -or -not "$($Estado.path)") { throw 'sem path no estado; nada a restaurar' }
    $path = "$($Estado.path)"
    $name = "$($Estado.name)"
    if (-not $name) { $name = $script:TmxDirectXValueName }

    if ([bool]$Estado.existiaAntes) {
        Set-TmxV2RegistryStringValue -Path $path -Name $name -Value "$($Estado.valorAnterior)"
        "valor restaurado: $($Estado.valorAnterior)"
    } else {
        Remove-TmxV2RegistryValue -Path $path -Name $name
        "$name removido (nao existia antes)"
    }
}
