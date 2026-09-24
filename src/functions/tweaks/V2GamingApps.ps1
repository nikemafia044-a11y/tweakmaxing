# functions/tweaks/V2GamingApps.ps1
# APM-007: remover os apps de jogos pre-instalados da Microsoft.
#
# Contrato de parametros (T6 / UI): { usaGamePass: bool }. Quando true, os
# quatro pacotes que o Game Pass para PC precisa (GamingApp, Game Bar, Xbox
# Identity Provider, Xbox TCUI) sao preservados; os demais sempre saem.
#
# Reversibilidade PARCIAL: volta pela Microsoft Store (storeId), quando
# conhecido - primeiro tenta o catalogo appx.json (Get-TmxV2AppxCatalog, de
# V2BloatwareChooser.ps1), depois um mapa de fallback local (o Xbox App
# legado e alguns pacotes de jogos nao estao em appx.json).

$script:TmxGamingAppxPacotes = @(
    'Microsoft.XboxApp',
    'Microsoft.GamingApp',
    'Microsoft.XboxGamingOverlay',
    'Microsoft.XboxIdentityProvider',
    'Microsoft.XboxSpeechToTextOverlay',
    'Microsoft.Xbox.TCUI',
    'Microsoft.MicrosoftSolitaireCollection'
)

# Os 4 pacotes que o Game Pass para PC depende para funcionar (documentado pela Microsoft).
$script:TmxGamingAppxGamePassKeep = @(
    'Microsoft.GamingApp',
    'Microsoft.XboxGamingOverlay',
    'Microsoft.XboxIdentityProvider',
    'Microsoft.Xbox.TCUI'
)

# Fallback quando o pacote nao esta em src/config/appx.json (ou nao tem storeId la).
$script:TmxGamingAppxStoreIds = @{
    'Microsoft.GamingApp'                    = '9MV0B5HZVK9Z'
    'Microsoft.XboxGamingOverlay'             = '9NZKPSTSNW4P'
    'Microsoft.XboxIdentityProvider'          = '9WZDNCRD1HKW'
    'Microsoft.MicrosoftSolitaireCollection'  = '9WZDNCRFHWD2'
}

function Resolve-TmxV2GamingStoreId {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Pacote)

    $entry = @(Get-TmxV2AppxCatalog) | Where-Object { "$($_.pacote)" -ieq $Pacote } | Select-Object -First 1
    if ($entry -and "$($entry.storeId)") { return "$($entry.storeId)" }
    if ($script:TmxGamingAppxStoreIds.ContainsKey($Pacote)) { return $script:TmxGamingAppxStoreIds[$Pacote] }
    $null
}

function Get-TmxV2GamingAppxManterLista {
    # Pacotes preservados dado usaGamePass.
    param($Parametros)
    $usaGamePass = [bool](Get-TmxActionProp -Action $Parametros -Nome 'usaGamePass' -Padrao $false)
    if ($usaGamePass) { return $script:TmxGamingAppxGamePassKeep }
    @()
}

function Get-TmxV2GamingAppxInstalado {
    <#
    .SYNOPSIS
        Pacotes de jogos da Microsoft instalados que NAO estao na lista de
        preservados por usaGamePass.
    #>
    [CmdletBinding()]
    param($Parametros)

    $manter = @(Get-TmxV2GamingAppxManterLista -Parametros $Parametros)
    $out = New-Object 'System.Collections.Generic.List[object]'
    foreach ($pacote in $script:TmxGamingAppxPacotes) {
        if ($manter -contains $pacote) { continue }
        foreach ($pkg in @(Get-TmxAppx -Pacote $pacote -TodosUsuarios)) {
            if ($pkg) {
                $out.Add([pscustomobject]@{
                    pacote          = $pacote
                    packageFullName = "$($pkg.PackageFullName)"
                    storeId         = Resolve-TmxV2GamingStoreId -Pacote $pacote
                })
            }
        }
    }
    $out.ToArray()
}

function Test-TmxGamingApps {
    [CmdletBinding()]
    param($Tweak, $Profile, $Parametros)

    $restantes = @(Get-TmxV2GamingAppxInstalado -Parametros $Parametros)
    [pscustomobject]@{
        aplicado = ($restantes.Count -eq 0)
        atual    = (@($restantes | ForEach-Object { $_.pacote }) -join ', ')
        esperado = 'nenhum app de jogos da Microsoft instalado (fora do que o Game Pass precisa)'
        detalhe  = "$($restantes.Count) pacote(s) de jogos ainda instalado(s)"
    }
}

function Set-TmxGamingApps {
    [CmdletBinding()]
    param($Tweak, $Profile, $Parametros)

    $alvos = @(Get-TmxV2GamingAppxInstalado -Parametros $Parametros)
    if ($alvos.Count -eq 0) {
        return [pscustomobject]@{ ok = $true; naoAplicavel = $true; detalhe = 'nenhum app de jogos da Microsoft instalado (fora do que o Game Pass precisa)' }
    }

    $usaGamePass = [bool](Get-TmxActionProp -Action $Parametros -Nome 'usaGamePass' -Padrao $false)
    $rec = New-TmxCmdletRecord -TweakId "$($Tweak.id)" -Funcao 'Set-TmxGamingApps' -Alvo 'apps de jogos da Microsoft' `
            -Estado @{ pacotes = $alvos; usaGamePass = $usaGamePass } `
            -ValorAnterior (@($alvos | ForEach-Object { $_.pacote }) -join ', ') -ValorNovo $null

    $falhas = New-Object 'System.Collections.Generic.List[string]'
    $removidos = 0
    foreach ($a in $alvos) {
        try {
            Remove-TmxAppx -PackageFullName $a.packageFullName -TodosUsuarios
            try { Remove-TmxProvisionedAppx -Nome $a.pacote }
            catch { Write-TmxLog -Level WARN -Message "provisionamento de '$($a.pacote)' nao removido: $($_.Exception.Message)" }
            $removidos++
        } catch {
            if (Test-TmxAppxJaRemovido -Mensagem $_.Exception.Message) { $removidos++ }
            else { $falhas.Add("$($a.pacote): $($_.Exception.Message)") }
        }
    }

    $ok = ($falhas.Count -eq 0)
    if ($ok) { Complete-TmxStateRecord -Record $rec -Ok $true | Out-Null }
    else { Complete-TmxStateRecord -Record $rec -Ok $false -Erro ($falhas.ToArray() -join '; ') | Out-Null }

    [pscustomobject]@{
        ok       = $ok
        detalhe  = $(if ($ok) { "$removidos app(s) de jogos removido(s)$(if ($usaGamePass) { ' (Game Pass preservado)' })" } else { ($falhas.ToArray() -join '; ') })
        registro = $rec
    }
}

function Undo-TmxGamingApps {
    [CmdletBinding()]
    param($Estado)

    if (-not $Estado -or -not $Estado.pacotes) { throw 'sem pacotes no estado; nada a reinstalar' }

    $sucesso = New-Object 'System.Collections.Generic.List[string]'
    $falhas  = New-Object 'System.Collections.Generic.List[string]'

    foreach ($p in @($Estado.pacotes)) {
        $pacote  = "$($p.pacote)"
        $storeId = "$($p.storeId)"
        if (-not $storeId) {
            $falhas.Add("$pacote`: sem storeId conhecido, reinstale manualmente pela Microsoft Store")
            continue
        }
        $codigo = Install-TmxStoreApp -StoreId $storeId
        if ($codigo -ne 0) { $falhas.Add("$pacote`: winget retornou $codigo ao reinstalar '$storeId'") }
        else { $sucesso.Add("$pacote ($storeId)") }
    }

    if ($falhas.Count -gt 0) {
        throw "reinstalados: $($sucesso.ToArray() -join ', '); falhas: $($falhas.ToArray() -join '; ')"
    }
    "reinstalados pela Microsoft Store: $($sucesso.ToArray() -join ', ')"
}
