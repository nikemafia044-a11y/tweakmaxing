# functions/tweaks/V2BloatwareChooser.ps1
# APM-006: remover bloatware, escolhendo o que manter.
#
# Contrato de parametros (T6 / UI): { manter: string[] } - lista de 'id' ou
# 'pacote' (campo do catalogo src/config/appx.json) dos aplicativos que NAO
# devem ser removidos. Vazio ou ausente = remove todo o catalogo de appx que
# estiver instalado.
#
# Reversibilidade PARCIAL: a volta e reinstalacao pela Microsoft Store
# (Install-TmxStoreApp), pacote a pacote, por storeId - o mesmo mecanismo
# reusado de Widgets.ps1/appx do Engine. Pacotes sem storeId conhecido no
# catalogo precisam ser reinstalados manualmente.

function Get-TmxV2AppxCatalog {
    <#
    .SYNOPSIS
        Entradas { id, nome, descricao, pacote, storeId } de src/config/appx.json
        (ou de $sync.configs.appx, via Get-TmxConfigDocument).
    #>
    [CmdletBinding()]
    param()
    $doc = Get-TmxConfigDocument -Name 'appx'
    if (-not $doc) { return @() }
    @($doc.appx | Where-Object { $_ -and "$($_.pacote)" })
}

function Get-TmxV2ManterSet {
    # HashSet (sem diferenciar maiusculas) com os 'id'/'pacote' informados em Parametros.manter.
    param($Parametros)
    $set = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($m in @(Get-TmxActionProp -Action $Parametros -Nome 'manter' -Padrao @())) {
        if ("$m") { [void]$set.Add("$m") }
    }
    # Virgula: um HashSet vazio sairia desenrolado como $null.
    , $set
}

function Get-TmxV2BloatwareInstalado {
    <#
    .SYNOPSIS
        Entradas do catalogo de appx que estao instaladas E fora da lista 'manter'.
    #>
    [CmdletBinding()]
    param($Parametros)

    $manterSet = Get-TmxV2ManterSet -Parametros $Parametros
    $out = New-Object 'System.Collections.Generic.List[object]'
    foreach ($app in (Get-TmxV2AppxCatalog)) {
        $id     = "$($app.id)"
        $pacote = "$($app.pacote)"
        if ($manterSet.Contains($id) -or $manterSet.Contains($pacote)) { continue }
        foreach ($pkg in @(Get-TmxAppx -Pacote $pacote)) {
            if ($pkg) {
                $out.Add([pscustomobject]@{
                    id              = $id
                    pacote          = $pacote
                    packageFullName = "$($pkg.PackageFullName)"
                    storeId         = "$($app.storeId)"
                })
            }
        }
    }
    $out.ToArray()
}

function Test-TmxBloatwareChooser {
    [CmdletBinding()]
    param($Tweak, $Profile, $Parametros)

    $restantes = @(Get-TmxV2BloatwareInstalado -Parametros $Parametros)
    [pscustomobject]@{
        aplicado = ($restantes.Count -eq 0)
        atual    = (@($restantes | ForEach-Object { $_.pacote }) -join ', ')
        esperado = 'nenhum aplicativo fora da lista de manter instalado'
        detalhe  = "$($restantes.Count) pacote(s) ainda instalado(s) fora da lista de manter"
    }
}

function Set-TmxBloatwareChooser {
    [CmdletBinding()]
    param($Tweak, $Profile, $Parametros)

    $alvos = @(Get-TmxV2BloatwareInstalado -Parametros $Parametros)
    if ($alvos.Count -eq 0) {
        return [pscustomobject]@{ ok = $true; naoAplicavel = $true; detalhe = 'nenhum aplicativo removivel instalado (fora da lista de manter)' }
    }

    $rec = New-TmxCmdletRecord -TweakId "$($Tweak.id)" -Funcao 'Set-TmxBloatwareChooser' -Alvo 'bloatware escolhido' `
            -Estado @{ pacotes = $alvos } `
            -ValorAnterior (@($alvos | ForEach-Object { $_.pacote }) -join ', ') -ValorNovo $null

    $falhas = New-Object 'System.Collections.Generic.List[string]'
    $removidos = 0
    foreach ($a in $alvos) {
        try {
            Remove-TmxAppx -PackageFullName $a.packageFullName
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
        detalhe  = $(if ($ok) { "$removidos aplicativo(s) removido(s)" } else { ($falhas.ToArray() -join '; ') })
        registro = $rec
    }
}

function Undo-TmxBloatwareChooser {
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
        $msg = "reinstalados: $($sucesso.ToArray() -join ', '); falhas: $($falhas.ToArray() -join '; ')"
        throw $msg
    }
    "reinstalados pela Microsoft Store: $($sucesso.ToArray() -join ', ')"
}
