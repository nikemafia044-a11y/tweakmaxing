# functions/system/AppUpdate.ps1
# Backend de app.checkUpdate: GET releases/latest do repositorio (mesma fonte
# que o resto do app usa: $sync.repo/$sync.version, preenchidos por
# scripts/start.ps1 a partir do arquivo REPO/VERSION - ver Compile.ps1) e
# comparacao de versao.
#
# Nao confundir com Actions.Updates.ps1 (politicas de Windows Update,
# UPD-001..003): este arquivo e sobre a propria atualizacao do TweakMaxing.

function Get-TmxRepoSlug {
    <#
    .SYNOPSIS
        'usuario/repositorio' do TweakMaxing: $sync.repo quando definido
        (dev via TMX_DEV_REPO, compilado via REPO/Compile.ps1), senao um
        padrao inofensivo.
    #>
    [CmdletBinding()]
    param()
    if ($null -ne $sync -and "$($sync.repo)") { return "$($sync.repo)" }
    'TweakMaxing/TweakMaxing'
}

function Get-TmxCurrentVersion {
    [CmdletBinding()]
    param()
    if ($null -ne $sync -and "$($sync.version)") { return "$($sync.version)" }
    '0.0.0-dev'
}

function Compare-TmxVersion {
    <#
    .SYNOPSIS
        Compara duas versoes (com ou sem 'v', com ou sem sufixo '-dev' etc.).
    .OUTPUTS
        -1 se $A < $B, 0 se iguais, 1 se $A > $B.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $A,
        [Parameter(Mandatory)] [string] $B
    )

    $na = ($A.TrimStart('v', 'V')) -replace '-.*$', ''
    $nb = ($B.TrimStart('v', 'V')) -replace '-.*$', ''

    try {
        $va = [version]$na
        $vb = [version]$nb
        return $va.CompareTo($vb)
    } catch {
        [string]::Compare($na, $nb, [System.StringComparison]::OrdinalIgnoreCase)
    }
}

function Get-TmxAppUpdateStatus {
    <#
    .SYNOPSIS
        { atual, ultima, novaDisponivel, url }. Modo de teste: sem rede -
        devolve o estado simulado "ja na ultima versao".
    #>
    [CmdletBinding()]
    param()

    $atual = Get-TmxCurrentVersion

    if ($null -ne $sync -and $sync.testMode) {
        return @{ atual = $atual; ultima = $atual; novaDisponivel = $false; url = ''; simulado = $true }
    }

    $repo = Get-TmxRepoSlug
    $uri  = "https://api.github.com/repos/$repo/releases/latest"
    $r    = Invoke-TmxHttpGetSafe -Uri $uri -TimeoutSeconds 8

    if (-not $r.ok) {
        return @{ atual = $atual; ultima = $null; novaDisponivel = $false; url = ''; erro = "$($r.erro)" }
    }

    $doc = $null
    try { $doc = $r.content | ConvertFrom-Json -ErrorAction Stop } catch { $doc = $null }
    if (-not $doc) {
        return @{ atual = $atual; ultima = $null; novaDisponivel = $false; url = ''; erro = 'resposta do GitHub invalida' }
    }

    $tag    = "$($doc.tag_name)"
    $ultima = $tag.TrimStart('v', 'V')

    $novaDisponivel = $false
    if ($ultima) {
        try { $novaDisponivel = ((Compare-TmxVersion -A $ultima -B $atual) -gt 0) } catch { $novaDisponivel = $false }
    }

    @{ atual = $atual; ultima = $ultima; novaDisponivel = [bool]$novaDisponivel; url = "$($doc.html_url)" }
}
