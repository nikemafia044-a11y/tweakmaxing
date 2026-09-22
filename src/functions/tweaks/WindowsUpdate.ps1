# functions/tweaks/WindowsUpdate.ps1
# UPD-001/002/003: politicas de Windows Update (aba "Atualizacoes").
#
# O servico do Windows Update NUNCA e desativado por nenhuma das tres: elas so
# alternam o StartupType entre Manual e Automatic, nunca Disabled (ver
# Assert-TmxUpdateServicesNeverDisabled, chamada pelos testes contra o
# catalogo real).
#
# UPD-002 e puramente declarativo (registry + service no catalogo; o Engine
# cuida de tudo). UPD-001 (Padrao) e UPD-003 (Adiar) precisam de funcao porque:
#  - Padrao REMOVE um conjunto de valores (Set-TmxRegistry -Remove) e tambem
#    mexe em servico - uma unica acao 'service' nao expressa "restaura ao que
#    era antes desta sessao" para tres servicos de uma vez.
#  - Adiar grava datas calculadas em tempo de execucao (agora + N dias), que
#    o catalogo estatico (JSON) nao pode expressar.
#
# Toda funcao aqui aceita -RegistryRoot (default HKLM:\SOFTWARE, ou a raiz de
# teste quando $sync.testMode - ver Get-TmxUpdateDefaultRegistryRoot) para que
# os testes redirecionem para HKCU:\Software\TweakMaxing_Tests\Updates. Quando
# chamada pelo Engine (tipo 'funcao'), a raiz tambem pode chegar via
# Parametros.registryRoot - e o que a ponte usa no modo de teste (ver
# Actions.Updates.ps1) para as funcoes Set-. As funcoes Test- NAO recebem
# Parametros do despacho generico do Engine (Test-TmxAction chama
# "& $teste -Tweak $Tweak -Profile $Profile", nunca com -Parametros) - sem o
# fallback de Get-TmxUpdateDefaultRegistryRoot, a pos-verificacao de
# Invoke-TmxPlan sempre leria HKLM:\SOFTWARE mesmo depois de Set- escrever na
# raiz de teste, e reportaria 'falha' para uma escrita que na verdade deu certo.

$script:TmxUpdateTestRoot = 'HKCU:\Software\TweakMaxing_Tests\Updates'

$script:TmxUpdatePolicySubPath   = 'Policies\Microsoft\Windows\WindowsUpdate'
$script:TmxUpdateAuSubPath       = 'Policies\Microsoft\Windows\WindowsUpdate\AU'
$script:TmxUpdateDriverSubPath   = 'Policies\Microsoft\Windows\DriverSearching'
$script:TmxUpdateMetadataSubPath = 'Policies\Microsoft\Windows\Device Metadata'
$script:TmxUpdatePauseSubPath    = 'Microsoft\WindowsUpdate\UX\Settings'

$script:TmxUpdatePolicyValueNames   = @('ExcludeWUDriversInQualityUpdate', 'DeferFeatureUpdates', 'DeferFeatureUpdatesPeriodInDays', 'DeferQualityUpdates', 'DeferQualityUpdatesPeriodInDays')
$script:TmxUpdateAuValueNames       = @('AUOptions', 'NoAutoRebootWithLoggedOnUsers', 'AUPowerManagement', 'NoAutoUpdate')
$script:TmxUpdateDriverValueNames   = @('DontSearchWindowsUpdate', 'DontPromptForWindowsUpdate', 'DriverUpdateWizardWuSearchEnabled')
$script:TmxUpdateMetadataValueNames = @('PreventDeviceMetadataFromNetwork')
$script:TmxUpdatePauseValueNames    = @('PauseUpdatesExpiryTime', 'PauseFeatureUpdatesEndTime', 'PauseQualityUpdatesEndTime', 'PauseFeatureUpdatesStartTime', 'PauseQualityUpdatesStartTime', 'PauseUpdatesStartTime')

$script:TmxUpdateServiceAlvos = @(
    @{ nome = 'BITS';     tipoInicio = 'Manual' }
    @{ nome = 'wuauserv'; tipoInicio = 'Manual' }
    @{ nome = 'UsoSvc';   tipoInicio = 'Automatic' }
)

function Get-TmxUpdateDefaultRegistryRoot {
    <#
    .SYNOPSIS
        Raiz padrao quando ninguem passou -RegistryRoot: a raiz de teste
        quando $sync.testMode, senao HKLM:\SOFTWARE.
    .NOTES
        So as funcoes Test- usam isto (as Set- resolvem a raiz via
        Resolve-TmxUpdateRegistryRoot, que ve Parametros.registryRoot).
    #>
    [CmdletBinding()]
    param()
    if ($null -ne $sync -and $sync.testMode) { return $script:TmxUpdateTestRoot }
    'HKLM:\SOFTWARE'
}

function Resolve-TmxUpdateRegistryRoot {
    <#
    .SYNOPSIS
        Raiz efetiva do registro: -RegistryRoot explicito (quando diferente do
        default) vence; senao Parametros.registryRoot (injetado pela ponte no
        modo de teste); senao o default recebido.
    #>
    param($Parametros, [string] $RegistryRoot)

    if ($RegistryRoot -and $RegistryRoot -ne 'HKLM:\SOFTWARE') { return $RegistryRoot }
    $viaParam = "$(Get-TmxActionProp -Action $Parametros -Nome 'registryRoot' -Padrao '')"
    if ($viaParam) { return $viaParam }
    if ($RegistryRoot) { return $RegistryRoot }
    'HKLM:\SOFTWARE'
}

function Get-TmxUpdatePolicyValueList {
    <#
    .SYNOPSIS
        Os valores de politica de UPD-002 mais NoAutoUpdate (AU), como
        {path, name}, sob a raiz dada.
    #>
    param([Parameter(Mandatory)] [string] $RegistryRoot)

    $pol = Join-Path $RegistryRoot $script:TmxUpdatePolicySubPath
    $au  = Join-Path $RegistryRoot $script:TmxUpdateAuSubPath
    $drv = Join-Path $RegistryRoot $script:TmxUpdateDriverSubPath
    $met = Join-Path $RegistryRoot $script:TmxUpdateMetadataSubPath

    $lista = New-Object 'System.Collections.Generic.List[object]'
    foreach ($n in $script:TmxUpdatePolicyValueNames)   { $lista.Add(@{ path = $pol; name = $n }) }
    foreach ($n in $script:TmxUpdateAuValueNames)       { $lista.Add(@{ path = $au;  name = $n }) }
    foreach ($n in $script:TmxUpdateDriverValueNames)   { $lista.Add(@{ path = $drv; name = $n }) }
    foreach ($n in $script:TmxUpdateMetadataValueNames) { $lista.Add(@{ path = $met; name = $n }) }
    $lista.ToArray()
}

function Get-TmxUpdatePauseValueList {
    <#
    .SYNOPSIS
        Os 6 valores de pausa (UX\Settings), como {path, name}, sob a raiz dada.
    #>
    param([Parameter(Mandatory)] [string] $RegistryRoot)

    $p = Join-Path $RegistryRoot $script:TmxUpdatePauseSubPath
    $lista = New-Object 'System.Collections.Generic.List[object]'
    foreach ($n in $script:TmxUpdatePauseValueNames) { $lista.Add(@{ path = $p; name = $n }) }
    $lista.ToArray()
}

function Assert-TmxUpdateServicesNeverDisabled {
    <#
    .SYNOPSIS
        Trava de seguranca: nenhuma acao 'service' de wuauserv/UsoSvc/BITS em
        qualquer tweak UPD-* pode ter tipoInicio='Disabled'. Usada pelos testes
        contra o catalogo real E contra catalogos forjados.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Catalogo)

    $alvos = @('wuauserv', 'UsoSvc', 'BITS')
    foreach ($t in @($Catalogo)) {
        if ("$($t.id)" -cnotmatch '^UPD-\d{3}$') { continue }
        foreach ($a in @($t.acoes)) {
            if ("$($a.tipo)" -ne 'service') { continue }
            if (("$($a.nome)" -in $alvos) -and ("$($a.tipoInicio)" -eq 'Disabled')) {
                throw "$($t.id): servico '$($a.nome)' marcado como Disabled - o Windows Update nunca pode ser desativado por este catalogo"
            }
        }
    }
}

# ---------------------------------------------------------------------------
# Trio: UPD-001 - politica padrao (remove adiamentos/pausa, normaliza servicos)
# ---------------------------------------------------------------------------

function Test-TmxUpdatePolicyDefault {
    <#
    .SYNOPSIS
        'aplicado' quando nenhum valor de politica/pausa (UPD-002 + pausa) existe mais.
    #>
    [CmdletBinding()]
    param($Tweak, $Profile, [string] $RegistryRoot)

    if (-not $RegistryRoot) { $RegistryRoot = Get-TmxUpdateDefaultRegistryRoot }

    $valores = @(Get-TmxUpdatePolicyValueList -RegistryRoot $RegistryRoot) + @(Get-TmxUpdatePauseValueList -RegistryRoot $RegistryRoot)
    $presentes = New-Object 'System.Collections.Generic.List[string]'
    foreach ($v in $valores) {
        $atual = Get-TmxRegistryValue -Path $v.path -Name $v.name
        if ($null -ne $atual) { $presentes.Add("$($v.path)::$($v.name)") }
    }

    $atualTexto = if ($presentes.Count -eq 0) { '<nenhuma politica/pausa presente>' } else { ($presentes.ToArray() -join '; ') }
    [pscustomobject]@{
        aplicado = ($presentes.Count -eq 0)
        atual    = $atualTexto
        esperado = '<nenhuma politica de adiamento/pausa>'
        detalhe  = "$($presentes.Count) de $($valores.Count) valor(es) ainda presentes"
    }
}

function Set-TmxUpdatePolicyDefault {
    <#
    .SYNOPSIS
        Remove as politicas de adiamento/pausa (Set-TmxRegistry -Remove, valor
        anterior capturado por registro) e normaliza BITS/wuauserv/UsoSvc.
    #>
    [CmdletBinding()]
    param($Tweak, $Profile, $Parametros, [string] $RegistryRoot = 'HKLM:\SOFTWARE')

    $raiz    = Resolve-TmxUpdateRegistryRoot -Parametros $Parametros -RegistryRoot $RegistryRoot
    $tweakId = "$($Tweak.id)"

    $valores   = @(Get-TmxUpdatePolicyValueList -RegistryRoot $raiz) + @(Get-TmxUpdatePauseValueList -RegistryRoot $raiz)
    $registros = New-Object 'System.Collections.Generic.List[object]'
    $regFalhas = New-Object 'System.Collections.Generic.List[string]'

    foreach ($v in $valores) {
        $rec = Set-TmxRegistry -Path $v.path -Name $v.name -Remove -TweakId $tweakId -PassThru
        if ($rec -and "$($rec.status)" -ne 'naoAplicavel') { $registros.Add($rec) }
        if ($rec -and "$($rec.status)" -eq 'falha') { $regFalhas.Add("$($v.name): $($rec.erro)") }
    }

    $antesServicos = New-Object 'System.Collections.Generic.List[object]'
    foreach ($alvo in $script:TmxUpdateServiceAlvos) {
        try {
            $s = Get-TmxServiceState -Nome $alvo.nome
            $antesServicos.Add(@{ nome = $alvo.nome; startType = "$($s.startType)"; status = "$($s.status)" })
        } catch {
            $antesServicos.Add(@{ nome = $alvo.nome; startType = $null; status = $null })
        }
    }

    $anteriorTexto = ($antesServicos.ToArray() | ForEach-Object { "$($_.nome)=$($_.startType)" }) -join '; '
    $novoTexto     = ($script:TmxUpdateServiceAlvos | ForEach-Object { "$($_.nome)=$($_.tipoInicio)" }) -join '; '

    $recServ = New-TmxCmdletRecord -TweakId $tweakId -Funcao 'Set-TmxUpdatePolicyDefault' `
        -Alvo 'servicos do Windows Update (BITS/wuauserv/UsoSvc)' `
        -Estado @{ servicos = $antesServicos.ToArray() } `
        -ValorAnterior $anteriorTexto -ValorNovo $novoTexto
    $registros.Add($recServ)

    $svcFalhas = New-Object 'System.Collections.Generic.List[string]'
    foreach ($alvo in $script:TmxUpdateServiceAlvos) {
        try {
            Set-TmxServiceState -Nome $alvo.nome -StartType $alvo.tipoInicio
        } catch {
            $svcFalhas.Add("$($alvo.nome): $($_.Exception.Message)")
        }
    }

    $todasFalhas = @($regFalhas.ToArray()) + @($svcFalhas.ToArray())
    if ($todasFalhas.Count -eq 0) {
        Complete-TmxStateRecord -Record $recServ -Ok $true | Out-Null
        [pscustomobject]@{
            ok        = $true
            detalhe   = "politica padrao restaurada ($($valores.Count) valor(es) removido(s)); servicos: $novoTexto"
            registros = $registros.ToArray()
        }
    } else {
        Complete-TmxStateRecord -Record $recServ -Ok $false -Erro ($todasFalhas -join '; ') | Out-Null
        [pscustomobject]@{
            ok        = $false
            detalhe   = ($todasFalhas -join '; ')
            registros = $registros.ToArray()
        }
    }
}

function Undo-TmxUpdatePolicyDefault {
    <#
    .SYNOPSIS
        Restaura os servicos a partir do Estado (startType/status capturados
        antes da aplicacao). Os valores de registro removidos voltam sozinhos:
        cada remocao gerou seu proprio registro 'registry' com reversao
        'restaurarValorAnterior', e Undo-TweakMaxing ja os reverte um a um -
        esta funcao NAO mexe em registro nenhum.
    #>
    [CmdletBinding()]
    param($Estado)

    $servicos = @()
    if ($Estado -and $Estado.servicos) { $servicos = @($Estado.servicos) }
    if ($servicos.Count -eq 0) {
        return 'sem estado de servico salvo: nada a restaurar aqui (os valores de registro voltam pelos proprios registros de reversao)'
    }

    $partes = New-Object 'System.Collections.Generic.List[string]'
    foreach ($s in $servicos) {
        $nome = "$($s.nome)"
        $tipo = "$($s.startType)"
        if (-not $nome -or -not $tipo) { continue }
        $iniciar = ("$($s.status)" -eq 'Running')
        Set-TmxServiceState -Nome $nome -StartType $tipo -Iniciar:$iniciar
        $partes.Add("$nome=$tipo")
    }
    "servicos restaurados ($($partes.ToArray() -join ', ')); valores de registro ja revertidos pelos proprios registros da execucao"
}

# ---------------------------------------------------------------------------
# Trio: UPD-003 - pausa temporaria (35 dias por padrao)
# ---------------------------------------------------------------------------

function Test-TmxUpdatePause {
    <#
    .SYNOPSIS
        'aplicado' quando PauseUpdatesExpiryTime existe e esta no futuro.
    #>
    [CmdletBinding()]
    param($Tweak, $Profile, [string] $RegistryRoot)

    if (-not $RegistryRoot) { $RegistryRoot = Get-TmxUpdateDefaultRegistryRoot }

    $p   = Join-Path $RegistryRoot $script:TmxUpdatePauseSubPath
    $val = Get-TmxRegistryValue -Path $p -Name 'PauseUpdatesExpiryTime'

    if (-not $val) {
        return [pscustomobject]@{ aplicado = $false; atual = '<ausente>'; esperado = '<data futura>'; detalhe = 'PauseUpdatesExpiryTime ausente' }
    }

    $dt = [datetime]::MinValue
    $ok = [datetime]::TryParse("$val", [ref]$dt)
    if (-not $ok) {
        return [pscustomobject]@{ aplicado = $null; atual = "$val"; esperado = '<data futura>'; detalhe = 'PauseUpdatesExpiryTime nao e uma data valida' }
    }

    $futura = ($dt.ToUniversalTime() -gt (Get-Date).ToUniversalTime())
    [pscustomobject]@{
        aplicado = $futura
        atual    = "$val"
        esperado = '<data futura>'
        detalhe  = "PauseUpdatesExpiryTime = $val"
    }
}

function Set-TmxUpdatePause {
    <#
    .SYNOPSIS
        Grava as 6 datas de pausa (UX\Settings): expiracao = agora + dias,
        inicio = agora. Tudo via Set-TmxRegistry (registro/reversao automaticos).
    #>
    [CmdletBinding()]
    param($Tweak, $Profile, $Parametros, [string] $RegistryRoot = 'HKLM:\SOFTWARE')

    $raiz    = Resolve-TmxUpdateRegistryRoot -Parametros $Parametros -RegistryRoot $RegistryRoot
    $tweakId = "$($Tweak.id)"

    $dias = 35
    $diasBruto = Get-TmxActionProp -Action $Parametros -Nome 'dias' -Padrao 35
    try { $dias = [int]$diasBruto } catch { $dias = 35 }
    if ($dias -le 0) { $dias = 35 }

    $agora = (Get-Date).ToUniversalTime()
    $fim   = $agora.AddDays($dias)
    $fmt   = 'yyyy-MM-ddTHH:mm:ssZ'
    $agoraTexto = $agora.ToString($fmt)
    $fimTexto   = $fim.ToString($fmt)

    $p = Join-Path $raiz $script:TmxUpdatePauseSubPath
    $valores = @(
        @{ name = 'PauseUpdatesExpiryTime';      value = $fimTexto }
        @{ name = 'PauseFeatureUpdatesEndTime';   value = $fimTexto }
        @{ name = 'PauseQualityUpdatesEndTime';   value = $fimTexto }
        @{ name = 'PauseFeatureUpdatesStartTime'; value = $agoraTexto }
        @{ name = 'PauseQualityUpdatesStartTime'; value = $agoraTexto }
        @{ name = 'PauseUpdatesStartTime';        value = $agoraTexto }
    )

    $registros = New-Object 'System.Collections.Generic.List[object]'
    $falhas    = New-Object 'System.Collections.Generic.List[string]'

    foreach ($v in $valores) {
        try {
            $rec = Set-TmxRegistry -Path $p -Name $v.name -Value $v.value -Type String -TweakId $tweakId -PassThru
            if ($rec) { $registros.Add($rec) }
            if ($rec -and "$($rec.status)" -eq 'falha') { $falhas.Add("$($v.name): $($rec.erro)") }
        } catch {
            $falhas.Add("$($v.name): $($_.Exception.Message)")
        }
    }

    if ($falhas.Count -eq 0) {
        [pscustomobject]@{ ok = $true; detalhe = "atualizacoes pausadas ate $fimTexto ($dias dia(s))"; registros = $registros.ToArray() }
    } else {
        [pscustomobject]@{ ok = $false; detalhe = ($falhas.ToArray() -join '; '); registros = $registros.ToArray() }
    }
}

function Undo-TmxUpdatePause {
    <#
    .SYNOPSIS
        Nao-operacao proposital: Set-TmxUpdatePause so gera registros do tipo
        'registry' (via Set-TmxRegistry), e cada um ja carrega sua propria
        reversao ('restaurarValorAnterior' ou 'removerValor'/'removerChaveCriada').
        Undo-TweakMaxing reverte esses registros diretamente e nunca chega a
        chamar esta funcao pelo despacho de 'cmdlet' - ela existe para
        satisfazer o trio Set-/Undo-/Test- exigido por Test-TmxCatalog.
    #>
    [CmdletBinding()]
    param($Estado)
    'pausa revertida pelos proprios registros de registro da execucao (nada adicional a desfazer)'
}
