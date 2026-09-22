# functions/microwin/Remove-TmxIsoPackages.ps1
# Remocao de appx provisionados e de pacotes do Windows DENTRO da imagem
# montada (nunca no sistema que esta rodando).
#
# O casamento e por SUBSTRING, sem diferenciar maiusculas: a interface manda
# nomes como 'Microsoft.BingWeather' e a imagem lista
# 'Microsoft.BingWeather_4.53.33420.0_neutral_~_8wekyb3d8bbwe'. Um appx que
# nao existe naquela edicao entra em 'ignorados', nao em 'erros' - a lista de
# escolhas e a mesma para todas as edicoes.

function Test-TmxPackageMatch {
    <#
    .SYNOPSIS
        $true quando o nome do pacote na imagem casa com algum dos pedidos.
    #>
    [CmdletBinding()]
    param(
        [string] $Nome,
        [string[]] $Pedidos
    )

    if (-not $Nome) { return $false }
    foreach ($p in @($Pedidos)) {
        if (-not "$p") { continue }
        if ("$Nome".IndexOf("$p", [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { return $true }
    }
    $false
}

function Remove-TmxIsoAppx {
    <#
    .SYNOPSIS
        Remove da imagem montada os appx provisionados escolhidos.
    .PARAMETER Path
        Pasta onde a imagem do Windows esta montada.
    .PARAMETER Nomes
        Pedacos de nome de pacote (ex.: 'Microsoft.BingWeather').
    .OUTPUTS
        [pscustomobject] @{ removidos; ignorados; erros } - tres arrays de string.
    .NOTES
        Uma falha de remocao PARA o processo (throw): a ISO sairia diferente do
        que a tela prometeu, e isso e pior do que nao gerar ISO nenhuma.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [string[]] $Nomes = @()
    )

    $removidos = New-Object 'System.Collections.Generic.List[string]'
    $ignorados = New-Object 'System.Collections.Generic.List[string]'

    $pedidos = @(@($Nomes) | ForEach-Object { "$_" } | Where-Object { $_ })
    if ($pedidos.Count -eq 0) {
        return [pscustomobject]@{ removidos = @(); ignorados = @(); erros = @() }
    }

    $presentes = @(Get-TmxProvisionedAppxWrapper -Path $Path)
    $alvos = @($presentes | Where-Object { Test-TmxPackageMatch -Nome "$($_.DisplayName)" -Pedidos $pedidos })

    foreach ($pedido in $pedidos) {
        $achou = @($alvos | Where-Object { Test-TmxPackageMatch -Nome "$($_.DisplayName)" -Pedidos @($pedido) })
        if ($achou.Count -eq 0) { $ignorados.Add("$pedido") }
    }

    foreach ($alvo in $alvos) {
        $nome = "$($alvo.PackageName)"
        if (-not $nome) { $nome = "$($alvo.DisplayName)" }
        Remove-TmxProvisionedAppxWrapper -Path $Path -PackageName $nome | Out-Null
        $removidos.Add($nome)
    }

    [pscustomobject]@{
        removidos = $removidos.ToArray()
        ignorados = $ignorados.ToArray()
        erros     = @()
    }
}

function Remove-TmxIsoPackages {
    <#
    .SYNOPSIS
        Remove da imagem montada os pacotes do Windows (capabilities/features)
        escolhidos na caixa avancada.
    .OUTPUTS
        [pscustomobject] @{ removidos; ignorados; erros }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [string[]] $Nomes = @()
    )

    $removidos = New-Object 'System.Collections.Generic.List[string]'
    $ignorados = New-Object 'System.Collections.Generic.List[string]'

    $pedidos = @(@($Nomes) | ForEach-Object { "$_" } | Where-Object { $_ })
    if ($pedidos.Count -eq 0) {
        return [pscustomobject]@{ removidos = @(); ignorados = @(); erros = @() }
    }

    $presentes = @(Get-TmxWindowsPackageWrapper -Path $Path)

    foreach ($pedido in $pedidos) {
        $alvos = @($presentes | Where-Object { Test-TmxPackageMatch -Nome "$($_.PackageName)" -Pedidos @($pedido) })
        if ($alvos.Count -eq 0) {
            $ignorados.Add("$pedido")
            continue
        }
        foreach ($alvo in $alvos) {
            $nome = "$($alvo.PackageName)"
            Remove-TmxWindowsPackageWrapper -Path $Path -PackageName $nome | Out-Null
            $removidos.Add($nome)
        }
    }

    [pscustomobject]@{
        removidos = $removidos.ToArray()
        ignorados = $ignorados.ToArray()
        erros     = @()
    }
}
