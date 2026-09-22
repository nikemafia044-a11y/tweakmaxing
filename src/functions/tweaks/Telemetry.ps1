# functions/tweaks/Telemetry.ps1
# PRI-006: a parte da telemetria que nao cabe em acao declarativa.
#
# As chaves de registro e os servicos DiagTrack/WerSvc sao acoes do catalogo,
# aplicadas pelo engine. Aqui ficam so os tres pontos com estado proprio:
#   - Defender SubmitSamplesConsent (valor anterior via Get-MpPreference)
#   - POWERSHELL_TELEMETRY_OPTOUT (variavel de maquina)
#   - remocao de Siuf\Rules\PeriodInNanoSeconds (via Set-TmxRegistry -Remove)

$script:TmxSiufPath = 'HKCU:\Software\Microsoft\Siuf\Rules'
$script:TmxSiufName = 'PeriodInNanoSeconds'

function Test-TmxTelemetry {
    [CmdletBinding()]
    param($Tweak, $Profile)

    $consent = $null
    try { $consent = (Get-TmxDefenderPreference).SubmitSamplesConsent } catch { $consent = $null }
    $optout = Get-TmxMachineEnvVar -Nome 'POWERSHELL_TELEMETRY_OPTOUT'

    if ($null -eq $consent) {
        return [pscustomobject]@{
            aplicado = $null
            atual    = "optout=$optout"
            esperado = 'SubmitSamplesConsent=2, POWERSHELL_TELEMETRY_OPTOUT=1'
            detalhe  = 'Get-MpPreference indisponivel (Defender ausente ou sem permissao)'
        }
    }

    $ok = ([int]$consent -eq 2) -and ("$optout" -eq '1')
    [pscustomobject]@{
        aplicado = $ok
        atual    = "SubmitSamplesConsent=$consent, POWERSHELL_TELEMETRY_OPTOUT=$optout"
        esperado = 'SubmitSamplesConsent=2, POWERSHELL_TELEMETRY_OPTOUT=1'
        detalhe  = "amostras ao Defender: $consent; telemetria do PowerShell: $optout"
    }
}

function Set-TmxTelemetry {
    [CmdletBinding()]
    param($Tweak, $Profile, $Parametros)

    $consentAnterior = $null
    try { $consentAnterior = (Get-TmxDefenderPreference).SubmitSamplesConsent } catch { $consentAnterior = $null }
    $optoutAnterior = Get-TmxMachineEnvVar -Nome 'POWERSHELL_TELEMETRY_OPTOUT'

    $rec = New-TmxCmdletRecord -TweakId "$($Tweak.id)" -Funcao 'Set-TmxTelemetry' -Alvo 'telemetria do Defender e do PowerShell' `
            -Estado @{ submitSamplesConsent = $consentAnterior; powershellTelemetryOptout = $optoutAnterior } `
            -ValorAnterior "SubmitSamplesConsent=$consentAnterior; POWERSHELL_TELEMETRY_OPTOUT=$optoutAnterior" `
            -ValorNovo 'SubmitSamplesConsent=2; POWERSHELL_TELEMETRY_OPTOUT=1'

    $registros = New-Object 'System.Collections.Generic.List[object]'
    $registros.Add($rec)
    $avisos = New-Object 'System.Collections.Generic.List[string]'

    try {
        if ($null -ne $consentAnterior) {
            Set-TmxDefenderSubmitSamples -Valor 2
        } else {
            $avisos.Add('Defender indisponivel: SubmitSamplesConsent nao alterado')
        }
        Set-TmxMachineEnvVar -Nome 'POWERSHELL_TELEMETRY_OPTOUT' -Valor '1'
        Complete-TmxStateRecord -Record $rec -Ok $true | Out-Null
    } catch {
        Complete-TmxStateRecord -Record $rec -Ok $false -Erro $_.Exception.Message | Out-Null
        return [pscustomobject]@{ ok = $false; detalhe = $_.Exception.Message; registros = $registros.ToArray() }
    }

    # Remocao do periodo de coleta do Feedback Hub: o Core captura o valor anterior.
    $recSiuf = Set-TmxRegistry -Path $script:TmxSiufPath -Name $script:TmxSiufName -Remove -TweakId "$($Tweak.id)" -PassThru
    if ($recSiuf) { $registros.Add($recSiuf) }

    $detalhe = 'telemetria reduzida'
    if ($avisos.Count -gt 0) { $detalhe = "$detalhe ($($avisos.ToArray() -join '; '))" }
    [pscustomobject]@{ ok = $true; detalhe = $detalhe; registros = $registros.ToArray() }
}

function Undo-TmxTelemetry {
    [CmdletBinding()]
    param($Estado)

    $partes = New-Object 'System.Collections.Generic.List[string]'

    $consent = $null
    if ($Estado) { $consent = $Estado.submitSamplesConsent }
    if ($null -ne $consent) {
        Set-TmxDefenderSubmitSamples -Valor ([int]$consent)
        $partes.Add("SubmitSamplesConsent restaurado para $consent")
    }

    $optout = $null
    if ($Estado) { $optout = $Estado.powershellTelemetryOptout }
    Set-TmxMachineEnvVar -Nome 'POWERSHELL_TELEMETRY_OPTOUT' -Valor "$optout"
    $partes.Add("POWERSHELL_TELEMETRY_OPTOUT restaurado para '$optout'")

    $partes.ToArray() -join '; '
}
