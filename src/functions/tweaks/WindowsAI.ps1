# functions/tweaks/WindowsAI.ps1
# APM-004: remover e desativar os componentes de IA do Windows.
#
# Tres coisas diferentes com estados diferentes:
#   - pacotes Appx (Copilot, CoreAI, OfficeHub) -> volta por Store, quando ha StoreId
#   - servico WSAIFabricSvc                     -> volta pelo tipo de inicio anterior
#   - recurso opcional Recall                   -> volta por Enable-WindowsOptionalFeature
# Reversibilidade PARCIAL, e o consentimento diz por que.

$script:TmxAiPacotes = @(
    @{ pacote = 'Microsoft.Copilot';               storeId = '9NHT9RB2F4HD' },
    @{ pacote = 'MicrosoftWindows.Client.CoreAI';  storeId = $null },
    @{ pacote = 'Microsoft.MicrosoftOfficeHub';    storeId = '9WZDNCRD29V9' }
)
$script:TmxAiServico = 'WSAIFabricSvc'
$script:TmxAiRecurso = 'Recall'

function Test-TmxWindowsAI {
    [CmdletBinding()]
    param($Tweak, $Profile)

    $presentes = New-Object 'System.Collections.Generic.List[string]'
    foreach ($p in $script:TmxAiPacotes) {
        foreach ($pkg in @(Get-TmxAppx -Pacote $p.pacote -TodosUsuarios)) {
            if ($pkg) { $presentes.Add("$($pkg.PackageFullName)") }
        }
    }

    $servico = $null
    try { $servico = (Get-TmxServiceState -Nome $script:TmxAiServico).startType } catch { $servico = $null }

    $lista = $presentes.ToArray()
    $servicoOk = ($null -eq $servico) -or ("$servico" -ieq 'Disabled')
    [pscustomobject]@{
        aplicado = (($lista.Count -eq 0) -and $servicoOk)
        atual    = "pacotes=$($lista.Count); $($script:TmxAiServico)=$servico"
        esperado = "pacotes=0; $($script:TmxAiServico)=Disabled"
        detalhe  = $(if ($lista.Count -gt 0) { "ainda instalados: $($lista -join ', ')" } else { 'nenhum pacote de IA instalado' })
    }
}

function Set-TmxWindowsAI {
    [CmdletBinding()]
    param($Tweak, $Profile, $Parametros)

    $removidos = New-Object 'System.Collections.Generic.List[object]'
    foreach ($p in $script:TmxAiPacotes) {
        foreach ($pkg in @(Get-TmxAppx -Pacote $p.pacote -TodosUsuarios)) {
            if ($pkg) {
                $removidos.Add([pscustomobject]@{
                    pacote          = $p.pacote
                    storeId         = $p.storeId
                    packageFullName = "$($pkg.PackageFullName)"
                })
            }
        }
    }

    $servicoAntes = $null
    try { $servicoAntes = (Get-TmxServiceState -Nome $script:TmxAiServico).startType } catch { $servicoAntes = $null }
    $recursoAntes = $null
    try { $recursoAntes = Get-TmxWindowsFeature -Nome $script:TmxAiRecurso } catch { $recursoAntes = $null }

    $estado = @{
        pacotes         = @($removidos | ForEach-Object { @{ pacote = $_.pacote; storeId = $_.storeId; packageFullName = $_.packageFullName } })
        servico         = $script:TmxAiServico
        servicoAnterior = $servicoAntes
        recurso         = $script:TmxAiRecurso
        recursoAnterior = $recursoAntes
    }

    $rec = New-TmxCmdletRecord -TweakId "$($Tweak.id)" -Funcao 'Set-TmxWindowsAI' -Alvo 'componentes de IA do Windows' `
            -Estado $estado `
            -ValorAnterior "pacotes=$($removidos.Count); servico=$servicoAntes; recurso=$recursoAntes" `
            -ValorNovo 'pacotes=0; servico=Disabled; recurso=Disabled'

    $avisos = New-Object 'System.Collections.Generic.List[string]'
    try {
        foreach ($r in $removidos) {
            Remove-TmxAppx -PackageFullName $r.packageFullName -TodosUsuarios
        }
        foreach ($p in $script:TmxAiPacotes) {
            try { Remove-TmxProvisionedAppx -Nome $p.pacote }
            catch { $avisos.Add("provisionamento de $($p.pacote): $($_.Exception.Message)") }
        }

        if ($null -ne $servicoAntes) {
            try { Set-TmxServiceState -Nome $script:TmxAiServico -StartType 'Disabled' }
            catch { $avisos.Add("servico $($script:TmxAiServico): $($_.Exception.Message)") }
        }

        if ("$recursoAntes" -ieq 'Enabled') {
            try { Disable-TmxWindowsFeature -Nome $script:TmxAiRecurso }
            catch { $avisos.Add("recurso $($script:TmxAiRecurso): $($_.Exception.Message)") }
        }

        Complete-TmxStateRecord -Record $rec -Ok $true | Out-Null
        $detalhe = "$($removidos.Count) pacote(s) de IA removido(s)"
        if ($avisos.Count -gt 0) { $detalhe = "$detalhe (avisos: $($avisos.ToArray() -join '; '))" }
        [pscustomobject]@{ ok = $true; detalhe = $detalhe; registro = $rec }
    } catch {
        Complete-TmxStateRecord -Record $rec -Ok $false -Erro $_.Exception.Message | Out-Null
        [pscustomobject]@{ ok = $false; detalhe = $_.Exception.Message; registro = $rec }
    }
}

function Undo-TmxWindowsAI {
    [CmdletBinding()]
    param($Estado)

    $partes = New-Object 'System.Collections.Generic.List[string]'

    foreach ($p in @($Estado.pacotes)) {
        if ($null -eq $p) { continue }
        $storeId = "$($p.storeId)"
        if (-not $storeId) {
            $partes.Add("$($p.pacote): sem StoreId conhecido, reinstale manualmente")
            continue
        }
        $codigo = Install-TmxStoreApp -StoreId $storeId
        if ($codigo -ne 0) { $partes.Add("$($p.pacote): winget saiu com $codigo") }
        else               { $partes.Add("$($p.pacote) reinstalado ($storeId)") }
    }

    if ($Estado -and $Estado.servicoAnterior) {
        Set-TmxServiceState -Nome "$($Estado.servico)" -StartType "$($Estado.servicoAnterior)"
        $partes.Add("$($Estado.servico) restaurado para $($Estado.servicoAnterior)")
    }

    if ($Estado -and "$($Estado.recursoAnterior)" -ieq 'Enabled') {
        Enable-TmxWindowsFeature -Nome "$($Estado.recurso)"
        $partes.Add("recurso $($Estado.recurso) reativado")
    }

    if ($partes.Count -eq 0) { return 'nada a reverter em Windows AI' }
    $partes.ToArray() -join '; '
}
