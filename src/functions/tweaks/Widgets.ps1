# functions/tweaks/Widgets.ps1
# APM-001: remocao dos pacotes de Widgets. Reversibilidade PARCIAL: a volta e
# reinstalacao pela Store (Install-TmxStoreApp), nao restauracao de backup.

$script:TmxWidgetPacotes = @('Microsoft.WidgetsPlatformRuntime', 'MicrosoftWindows.Client.WebExperience')
$script:TmxWidgetStoreId = '9MSSGKG348SP'

function Test-TmxWidgets {
    [CmdletBinding()]
    param($Tweak, $Profile)

    $presentes = New-Object 'System.Collections.Generic.List[string]'
    foreach ($p in $script:TmxWidgetPacotes) {
        foreach ($pkg in @(Get-TmxAppx -Pacote $p -TodosUsuarios)) {
            if ($pkg) { $presentes.Add("$($pkg.PackageFullName)") }
        }
    }
    $lista = $presentes.ToArray()
    [pscustomobject]@{
        aplicado = ($lista.Count -eq 0)
        atual    = ($lista -join ', ')
        esperado = 'nenhum pacote de Widgets instalado'
        detalhe  = "$($lista.Count) pacote(s) de Widgets presente(s)"
    }
}

function Set-TmxWidgets {
    [CmdletBinding()]
    param($Tweak, $Profile, $Parametros)

    $alvos = New-Object 'System.Collections.Generic.List[object]'
    foreach ($p in $script:TmxWidgetPacotes) {
        foreach ($pkg in @(Get-TmxAppx -Pacote $p -TodosUsuarios)) {
            if ($pkg) { $alvos.Add([pscustomobject]@{ pacote = $p; packageFullName = "$($pkg.PackageFullName)" }) }
        }
    }

    if ($alvos.Count -eq 0) {
        return [pscustomobject]@{ ok = $true; naoAplicavel = $true; detalhe = 'nenhum pacote de Widgets instalado' }
    }

    $nomes = @($alvos | ForEach-Object { $_.packageFullName })
    $rec = New-TmxCmdletRecord -TweakId "$($Tweak.id)" -Funcao 'Set-TmxWidgets' -Alvo 'pacotes de Widgets' `
            -Estado @{ pacotes = $nomes; storeId = $script:TmxWidgetStoreId } `
            -ValorAnterior ($nomes -join ', ') -ValorNovo $null

    try {
        # O processo dos Widgets segura os proprios arquivos; sem parar antes, a remocao falha.
        Stop-TmxProcessByName -Nome @('Widgets', 'WidgetService')
        foreach ($a in $alvos) {
            Remove-TmxAppx -PackageFullName $a.packageFullName -TodosUsuarios
        }
        foreach ($p in $script:TmxWidgetPacotes) {
            try { Remove-TmxProvisionedAppx -Nome $p }
            catch { Write-TmxLog -Level WARN -Message "provisionamento de '$p' nao removido: $($_.Exception.Message)" }
        }
        Restart-TmxExplorer
        Complete-TmxStateRecord -Record $rec -Ok $true | Out-Null
        [pscustomobject]@{ ok = $true; detalhe = "$($alvos.Count) pacote(s) de Widgets removido(s)"; registro = $rec }
    } catch {
        Complete-TmxStateRecord -Record $rec -Ok $false -Erro $_.Exception.Message | Out-Null
        [pscustomobject]@{ ok = $false; detalhe = $_.Exception.Message; registro = $rec }
    }
}

function Undo-TmxWidgets {
    [CmdletBinding()]
    param($Estado)

    $storeId = $script:TmxWidgetStoreId
    if ($Estado -and $Estado.storeId) { $storeId = "$($Estado.storeId)" }

    $codigo = Install-TmxStoreApp -StoreId $storeId
    if ($codigo -ne 0) { throw "reinstalacao dos Widgets falhou (winget saiu com $codigo)" }
    "Widgets reinstalados pela Microsoft Store ($storeId)"
}
