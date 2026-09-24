# functions/tweaks/V2DefenderRealtime.ps1
# SEC-001: protecao em tempo real do Defender - controle 'info'.
#
# Este arquivo NUNCA chama nada que desligue a Protecao em Tempo Real por
# script (nem Set-MpPreference -DisableRealtimeMonitoring, nem equivalente).
# A Protecao contra Adulteracao do Windows bloqueia essa mudanca vinda de
# fora da propria interface do Defender - inclusive de um processo elevado -
# entao tentar seria so gerar um erro sem efeito. O que existe aqui:
#   - Get-TmxDefenderRealtimeStatus: LEITURA do estado (RTP + Adulteracao).
#   - Set-/Test-/Undo-TmxDefenderExclusionAlternative: a alternativa segura,
#     reversivel - exclusao de pastas do Defender (reaproveita
#     Add-/Remove-/Get-TmxDefenderExclusionPath[s] de DefenderExclusion.ps1,
#     que ja sao genericas, nao especificas do CS2).
#   - Open-TmxDefenderManualSettings: abre a tela de configuracoes do
#     Defender para quem quiser desligar manualmente.

function Get-TmxDefenderRealtimeStatus {
    <#
    .SYNOPSIS
        Estado ATUAL (somente leitura) da Protecao em Tempo Real e da
        Protecao contra Adulteracao. Nunca escreve nada.
    #>
    [CmdletBinding()]
    param($Tweak, $Profile)

    try {
        $st = Get-TmxV2DefenderComputerStatus
        $rtp      = [bool]$st.RealTimeProtectionEnabled
        $adultera = [bool]$st.IsTamperProtected
        [pscustomobject]@{
            protecaoTempoRealAtiva   = $rtp
            protecaoAdulteracaoAtiva = $adultera
            detalhe                  = "Protecao em tempo real: $(if ($rtp) { 'ativa' } else { 'inativa' }); Protecao contra Adulteracao: $(if ($adultera) { 'ativa' } else { 'inativa' })"
        }
    } catch {
        [pscustomobject]@{
            protecaoTempoRealAtiva   = $null
            protecaoAdulteracaoAtiva = $null
            detalhe                  = "nao foi possivel ler o estado do Defender: $($_.Exception.Message)"
        }
    }
}

function Open-TmxDefenderManualSettings {
    <#
    .SYNOPSIS
        Abre a tela de configuracoes do Windows Defender (windowsdefender://threatsettings)
        para o passo manual. So abre a tela; nao muda nada.
    #>
    [CmdletBinding()]
    param($Tweak, $Profile)

    try {
        $uri = Start-TmxV2DefenderSettingsUri
        [pscustomobject]@{
            ok      = $true
            detalhe = "Configuracoes do Windows Defender abertas ($uri). Desligar a Protecao em Tempo Real, se ainda quiser, e um passo manual la dentro."
        }
    } catch {
        [pscustomobject]@{ ok = $false; detalhe = $_.Exception.Message }
    }
}

function Get-TmxV2ExclusaoPastasParametro {
    param($Parametros)
    @(Get-TmxActionProp -Action $Parametros -Nome 'pastas' -Padrao @()) | Where-Object { "$_" }
}

function Test-TmxDefenderExclusionAlternative {
    [CmdletBinding()]
    param($Tweak, $Profile, $Parametros)

    $pastas = @(Get-TmxV2ExclusaoPastasParametro -Parametros $Parametros)
    if ($pastas.Count -eq 0) {
        return [pscustomobject]@{ aplicado = $null; atual = $null; esperado = $null; detalhe = 'nenhuma pasta informada' }
    }

    $atuais    = @(Get-TmxDefenderExclusions)
    $faltando  = @($pastas | Where-Object { $p = $_; -not (@($atuais | Where-Object { $_ -ieq $p })) })
    [pscustomobject]@{
        aplicado = ($faltando.Count -eq 0)
        atual    = ($atuais -join '; ')
        esperado = ($pastas -join '; ')
        detalhe  = "$($pastas.Count - $faltando.Count)/$($pastas.Count) pasta(s) excluida(s)"
    }
}

function Set-TmxDefenderExclusionAlternative {
    [CmdletBinding()]
    param($Tweak, $Profile, $Parametros)

    $pastas = @(Get-TmxV2ExclusaoPastasParametro -Parametros $Parametros)
    if ($pastas.Count -eq 0) {
        return [pscustomobject]@{ ok = $true; naoAplicavel = $true; detalhe = 'nenhuma pasta informada' }
    }

    $existentes = @(Get-TmxDefenderExclusions)
    $novas = @($pastas | Where-Object { $p = $_; -not (@($existentes | Where-Object { $_ -ieq $p })) })
    if ($novas.Count -eq 0) {
        return [pscustomobject]@{ ok = $true; naoAplicavel = $true; detalhe = 'todas as pastas informadas ja estao excluidas' }
    }

    $rec = New-TmxCmdletRecord -TweakId "$($Tweak.id)" -Funcao 'Set-TmxDefenderExclusionAlternative' -Alvo 'exclusoes do Defender (alternativa segura)' `
            -Estado @{ pastasAdicionadas = $novas } `
            -ValorAnterior 'sem exclusao para estas pastas' -ValorNovo ($novas -join '; ')

    try {
        foreach ($p in $novas) { Add-TmxDefenderExclusionPath -Path $p }
        Complete-TmxStateRecord -Record $rec -Ok $true | Out-Null
        [pscustomobject]@{ ok = $true; detalhe = "$($novas.Count) pasta(s) excluida(s) da Protecao em Tempo Real"; registro = $rec }
    } catch {
        Complete-TmxStateRecord -Record $rec -Ok $false -Erro $_.Exception.Message | Out-Null
        [pscustomobject]@{ ok = $false; detalhe = $_.Exception.Message; registro = $rec }
    }
}

function Undo-TmxDefenderExclusionAlternative {
    [CmdletBinding()]
    param($Estado)

    if (-not $Estado -or -not $Estado.pastasAdicionadas) { throw 'sem pastas no estado; nada a restaurar' }
    $pastas = @($Estado.pastasAdicionadas)
    foreach ($p in $pastas) { Remove-TmxDefenderExclusionPath -Path "$p" }
    "exclusoes removidas: $($pastas -join '; ')"
}
