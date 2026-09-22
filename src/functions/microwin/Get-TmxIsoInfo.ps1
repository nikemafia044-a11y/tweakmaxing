# functions/microwin/Get-TmxIsoInfo.ps1
# Leitura das edicoes de uma ISO do Windows.
#
# Somente leitura: monta, le sources\install.wim (ou install.esd), desmonta. A
# ISO de origem nao e tocada - nem aqui nem no build.

function ConvertTo-TmxImageArchitecture {
    <#
    .SYNOPSIS
        Traduz o codigo numerico de arquitetura do DISM para texto.
    .NOTES
        Get-WindowsImage SEM -Index nao traz Architecture; com -Index traz.
        Codigo desconhecido volta como texto do proprio numero, nunca vazio.
    #>
    [CmdletBinding()]
    param($Valor)

    if ($null -eq $Valor -or "$Valor" -eq '') { return '' }
    switch ("$Valor") {
        '0'  { return 'x86' }
        '5'  { return 'ARM' }
        '6'  { return 'ia64' }
        '9'  { return 'x64' }
        '12' { return 'ARM64' }
        default { return "$Valor" }
    }
}

function ConvertTo-TmxIsoEdition {
    <#
    .SYNOPSIS
        Um objeto do Get-WindowsImage vira { index, nome, versao, arquitetura }.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Imagem)

    $nome = "$($Imagem.ImageName)"
    if (-not $nome) { $nome = "$($Imagem.ImageDescription)" }
    if (-not $nome) { $nome = "Edicao $($Imagem.ImageIndex)" }

    $versao = "$($Imagem.Version)"
    if (-not $versao) { $versao = "$($Imagem.ImageVersion)" }

    [pscustomobject]@{
        index        = [int]$Imagem.ImageIndex
        nome         = $nome
        versao       = $versao
        arquitetura  = (ConvertTo-TmxImageArchitecture -Valor $Imagem.Architecture)
    }
}

function Get-TmxIsoInfo {
    <#
    .SYNOPSIS
        Edicoes e tamanho de uma ISO do Windows, sem alterar nada nela.
    .OUTPUTS
        @{ ok; mensagem; edicoes = @({ index, nome, versao, arquitetura }); tamanhoGB }
    .NOTES
        O desmontar mora no finally: se a leitura do WIM explodir no meio, a
        ISO nao pode ficar montada na maquina do usuario.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $IsoPath)

    $vazio = @()
    $tamanho = Get-TmxFileSizeGB -Path $IsoPath

    if (-not (Test-Path -LiteralPath $IsoPath)) {
        return @{ ok = $false; mensagem = "ISO nao encontrada: $IsoPath"; edicoes = $vazio; tamanhoGB = 0.0 }
    }
    if ("$IsoPath" -notmatch '\.iso$') {
        return @{ ok = $false; mensagem = 'o arquivo precisa terminar em .iso'; edicoes = $vazio; tamanhoGB = $tamanho }
    }

    $montagem = Mount-TmxIso -IsoPath $IsoPath
    if (-not $montagem.ok) {
        return @{ ok = $false; mensagem = "$($montagem.mensagem)"; edicoes = $vazio; tamanhoGB = $tamanho }
    }

    $edicoes  = New-Object 'System.Collections.Generic.List[object]'
    $erro     = $null
    try {
        $imagem = Get-TmxInstallImagePath -Raiz $montagem.raiz
        if ($null -eq $imagem) {
            $erro = 'sources\install.wim (ou install.esd) nao existe nesta ISO'
        } else {
            foreach ($i in @(Get-TmxWindowsImageWrapper -ImagePath $imagem.caminho)) {
                $edicoes.Add((ConvertTo-TmxIsoEdition -Imagem $i))
            }
        }
    } catch {
        $erro = "nao foi possivel ler as edicoes: $($_.Exception.Message)"
    } finally {
        Dismount-TmxIso -IsoPath $IsoPath | Out-Null
    }

    if ($erro) {
        return @{ ok = $false; mensagem = $erro; edicoes = $vazio; tamanhoGB = $tamanho }
    }
    if ($edicoes.Count -eq 0) {
        return @{ ok = $false; mensagem = 'nenhuma edicao encontrada na imagem'; edicoes = $vazio; tamanhoGB = $tamanho }
    }

    @{
        ok        = $true
        mensagem  = "$($edicoes.Count) edicao(oes) encontrada(s)"
        # .ToArray(): @() sobre List generica vazia falha no PS 5.1.
        edicoes   = $edicoes.ToArray()
        tamanhoGB = $tamanho
    }
}
