# functions/tweaks/V2GpuPanelGuide.ps1
# JOG-049: guia manual do painel da GPU. controle 'info' - NENHUMA mudanca de
# sistema. So detecta o fabricante e devolve o roteiro (passo a passo) ja
# escrito no campo 'guia' do catalogo (src/config/tweaks.v2.json), com
# NVIDIA/AMD/Intel em pt e en.
#
# Sem trio Set-/Undo-/Test-Tmx<X>: nao ha nada para aplicar nem reverter.

function Get-TmxGpuVendorDetectado {
    <#
    .SYNOPSIS
        'NVIDIA' | 'AMD' | 'Intel' | 'Outro' | 'Desconhecido'.
    .DESCRIPTION
        Prioriza $Profile.gpu.vendor (ja calculado por Get-TmxGpuSection,
        Engine/Profile.ps1). Sem perfil (ou sem gpu.vendor), consulta
        Win32_VideoController pelo wrapper e aplica a mesma classificacao por
        texto usada la, para o guia funcionar mesmo fora do fluxo do Engine.
    #>
    [CmdletBinding()]
    param($Profile)

    if ($Profile -and $Profile.gpu -and "$($Profile.gpu.vendor)") {
        return "$($Profile.gpu.vendor)"
    }

    try {
        $vcs = @(Get-TmxV2VideoControllers)
        $principal = $vcs | Select-Object -First 1
        if (-not $principal) { return 'Desconhecido' }
        $desc = "$($principal.AdapterCompatibility) $($principal.Name)"
        switch -Regex ($desc) {
            'NVIDIA'                  { return 'NVIDIA' }
            'AMD|Advanced Micro|ATI ' { return 'AMD' }
            'Intel'                   { return 'Intel' }
            default                   { return 'Outro' }
        }
    } catch {
        return 'Desconhecido'
    }
}

function Get-TmxGpuPanelGuia {
    <#
    .SYNOPSIS
        Resolve o fabricante e devolve os passos do guia (na estrutura crua
        {pt:[...], en:[...]}) para esse fabricante, a partir de $Tweak.guia
        (o campo do catalogo). $null em 'guia' quando o fabricante nao tem
        roteiro especifico (ex.: 'Outro'/'Desconhecido').
    #>
    [CmdletBinding()]
    param($Tweak, $Profile)

    $vendor = Get-TmxGpuVendorDetectado -Profile $Profile
    $guiaCatalogo = $null
    if ($Tweak) { $guiaCatalogo = Get-TmxActionProp -Action $Tweak -Nome 'guia' -Padrao $null }

    $passos = $null
    if ($guiaCatalogo) { $passos = Get-TmxActionProp -Action $guiaCatalogo -Nome $vendor -Padrao $null }

    [pscustomobject]@{
        vendor     = $vendor
        encontrado = [bool]$passos
        guia       = $passos
        detalhe    = $(if ($passos) { "guia disponivel para $vendor" } else { "sem guia especifico para '$vendor'" })
    }
}

function Get-TmxGpuPanelGuiaPassos {
    <#
    .SYNOPSIS
        Os passos (array de strings) de um bloco {pt, en} no idioma pedido,
        caindo em pt-BR quando faltar traducao - mesma regra de i18n do catalogo.
    #>
    [CmdletBinding()]
    param($Guia, [string] $Idioma = 'pt')

    if (-not $Guia) { return @() }
    $chave = if ("$Idioma" -eq 'en') { 'en' } else { 'pt' }
    $passos = Get-TmxActionProp -Action $Guia -Nome $chave -Padrao $null
    if (-not $passos) { $passos = Get-TmxActionProp -Action $Guia -Nome 'pt' -Padrao @() }
    @($passos)
}
