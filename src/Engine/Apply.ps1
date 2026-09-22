# Engine/Apply.ps1
# Orquestracao: backups obrigatorios -> acoes em ordem -> pos-verificacao.
#
# Status por item:
#   aplicado / aplicadoNaoVerificado / jaAplicado / naoAplicavel / naoSuportado /
#   falha / simulado / semConsentimento
#
# Regras duras:
#   M1 - se o export .reg de um ramo que EXISTE falhar, o tweak nao e aplicado.
#   Falha em um tweak nao interrompe os demais.
#   Nada aqui escreve no host (so Write-Progress e Write-TmxLog).

$script:TmxPowerBackupFeito = $false
$script:TmxNetBackupFeito   = $false
$script:TmxBcdBackupFeito   = $false

function Invoke-TmxBackupForTweak {
    <#
    .SYNOPSIS
        Exports de seguranca antes de tocar em qualquer coisa deste tweak.
    .NOTES
        M1: Backup-TmxRegistryHive devolvendo $null para um ramo existente e
        erro fatal do tweak - lanca para que o chamador marque 'falha'.

        powercfg/netadapter sao diferentes: o valor anterior de cada acao ja vai
        para o state.json, entao um export que falha vira aviso e nao bloqueio.
        A flag de "feito" so e marcada quando o arquivo realmente saiu, para que
        o proximo tweak tente de novo em vez de seguir sem backup nenhum.
    .OUTPUTS
        Os avisos acumulados (array vazio quando tudo saiu).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Tweak)

    $acoes  = @($Tweak.acoes)
    $avisos = New-Object 'System.Collections.Generic.List[string]'

    $paths = @($acoes | Where-Object { "$($_.tipo)" -eq 'registry' -and $_.path } |
                ForEach-Object { "$($_.path)" } | Select-Object -Unique)
    foreach ($p in $paths) {
        if (Test-Path -LiteralPath $p) {
            $arquivo = Backup-TmxRegistryHive -Path $p
            if (-not $arquivo) { throw "backup .reg falhou: $p" }
        }
    }

    if (@($acoes | Where-Object { "$($_.tipo)" -eq 'powercfg' }).Count -gt 0 -and -not $script:TmxPowerBackupFeito) {
        if (Backup-TmxPowerScheme) {
            $script:TmxPowerBackupFeito = $true
        } else {
            $aviso = 'export do esquema de energia (.pow) falhou; o valor anterior de cada acao continua no state.json'
            Write-TmxLog -Level WARN -Message "$aviso [$($Tweak.id)]"
            $avisos.Add($aviso)
        }
    }
    if (@($acoes | Where-Object { "$($_.tipo)" -eq 'netadapter' }).Count -gt 0 -and -not $script:TmxNetBackupFeito) {
        if (Backup-TmxNetworkAdapters) {
            $script:TmxNetBackupFeito = $true
        } else {
            $aviso = 'export dos adaptadores (net-adapters.json) falhou; o valor anterior de cada acao continua no state.json'
            Write-TmxLog -Level WARN -Message "$aviso [$($Tweak.id)]"
            $avisos.Add($aviso)
        }
    }
    if (@($acoes | Where-Object { "$($_.tipo)" -eq 'bcdedit' }).Count -gt 0 -and -not $script:TmxBcdBackupFeito) {
        Backup-TmxBcd | Out-Null
        $script:TmxBcdBackupFeito = $true
    }

    $avisos.ToArray()
}

function Invoke-TmxPostApply {
    # posAplicar: avisa o Windows que algo mudou. Falhar aqui nunca invalida o tweak.
    param([Parameter(Mandatory)] $Tweak)
    $pos = "$($Tweak.posAplicar)"
    if (-not $pos) { return }
    try {
        switch ($pos) {
            'SystemParametersInfo' {
                if (Get-Command -Name 'Update-TmxMouseSettings' -ErrorAction SilentlyContinue) { Update-TmxMouseSettings | Out-Null }
            }
            'SettingChange' {
                if (Get-Command -Name 'Send-TmxSettingChange' -ErrorAction SilentlyContinue) { Send-TmxSettingChange | Out-Null }
            }
        }
    } catch {
        Write-TmxLog -Level WARN -Message "posAplicar '$pos' falhou ($($Tweak.id)): $($_.Exception.Message)"
    }
}

function Invoke-TmxPlan {
    <#
    .SYNOPSIS
        Aplica os itens selecionados do plano. -WhatIf simula sem tocar em nada.
    .PARAMETER Ids
        Restringe a execucao a esses ids (os demais selecionados sao ignorados).
    .OUTPUTS
        { preset, executadoEm, itens[], aplicados, jaAplicados, falhas, pulados, requerReboot }
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)] $Plan,
        [Parameter(Mandatory)] $Profile,
        [string[]] $Ids
    )

    $script:TmxPowerBackupFeito = $false
    $script:TmxNetBackupFeito   = $false
    $script:TmxBcdBackupFeito   = $false

    $selecionados = @($Plan.itens | Where-Object { $_.selecionado })
    if ($Ids) { $selecionados = @($selecionados | Where-Object { $Ids -contains "$($_.id)" }) }
    $selecionados = @($selecionados | Sort-Object id)

    $resultados = New-Object 'System.Collections.Generic.List[object]'
    $i = 0

    foreach ($item in $selecionados) {
        $i++
        $t = $item.tweak
        $res = [pscustomobject]@{
            id           = "$($t.id)"
            nome         = "$($t.nome)"
            tier         = "$($t.tier)"
            status       = $null
            detalhe      = $null
            antes        = $null
            depois       = $null
            registros    = 0
            avisos       = @()
            requerReboot = [bool]$t.requerReboot
        }
        Write-Progress -Activity 'Aplicando tweaks' -Status "$($t.id) $($t.nome)" -PercentComplete ([int]($i / $selecionados.Count * 100))

        # consentimento extra e obrigatorio e explicito
        if ($t.requerConsentimentoExtra -and -not $item.consentido) {
            $res.status  = 'semConsentimento'
            $res.detalhe = 'exige consentimento extra que nao foi dado'
            $resultados.Add($res)
            continue
        }

        # pre-check
        $pre = Test-TmxTweakApplied -Tweak $t -Profile $Profile
        $res.antes = $pre.atual
        if ($pre.aplicado -eq $true) {
            $res.status  = 'jaAplicado'
            $res.detalhe = $pre.detalhe
            $resultados.Add($res)
            continue
        }

        if (-not $PSCmdlet.ShouldProcess("$($t.id) $($t.nome)", 'aplicar')) {
            $res.status  = 'simulado'
            $res.detalhe = "seria aplicado ($(@($t.acoes | ForEach-Object { "$($_.tipo)" }) -join ', '))"
            $resultados.Add($res)
            continue
        }

        try {
            $res.avisos = @(Invoke-TmxBackupForTweak -Tweak $t)
        } catch {
            $res.status  = 'falha'
            $res.detalhe = $_.Exception.Message
            Write-TmxLog -Level ERROR -Message "Backup obrigatorio falhou em $($t.id): $($_.Exception.Message)"
            $resultados.Add($res)
            continue
        }

        $registros     = New-Object 'System.Collections.Generic.List[object]'
        $falhas        = @()
        $detalhes      = @()
        $naoAplicaveis = 0
        $naoSuportado  = $false

        foreach ($a in @($t.acoes)) {
            $r = Invoke-TmxAction -Action $a -Tweak $t -Profile $Profile
            foreach ($rec in @($r.registros)) { if ($rec) { $registros.Add($rec) } }

            if ($r.naoSuportado) { $naoSuportado = $true; $detalhes += "$($r.detalhe)"; break }
            if ($r.naoAplicavel) { $naoAplicaveis++; $detalhes += "$($r.detalhe)"; continue }
            if (-not $r.ok)      { $falhas += "$($a.tipo): $($r.detalhe)"; break }
            $detalhes += "$($r.detalhe)"
        }

        $res.registros = $registros.Count

        if ($falhas.Count -gt 0) {
            # Falha parcial: parte das acoes pode ter passado. Reler o estado
            # mostra na UI (e no relatorio) o que de fato ficou no sistema.
            $res.status  = 'falha'
            $res.detalhe = ($falhas -join '; ')
            $posFalha    = Test-TmxTweakApplied -Tweak $t -Profile $Profile
            $res.depois  = $posFalha.atual
        } elseif ($naoSuportado) {
            $res.status  = 'naoSuportado'
            $res.detalhe = ($detalhes -join '; ')
        } elseif ($naoAplicaveis -eq @($t.acoes).Count) {
            $res.status  = 'naoAplicavel'
            $res.detalhe = ($detalhes -join '; ')
        } else {
            Invoke-TmxPostApply -Tweak $t
            $res.detalhe = ($detalhes -join '; ')
            $pos = Test-TmxTweakApplied -Tweak $t -Profile $Profile
            $res.depois = $pos.atual
            if ($pos.aplicado -eq $true) {
                $res.status = 'aplicado'
            } elseif ($pos.aplicado -eq $false) {
                $res.status  = 'falha'
                $res.detalhe = "pos-verificacao falhou: $($pos.detalhe)"
            } else {
                $res.status = 'aplicadoNaoVerificado'
            }
        }

        Write-TmxLog -Level INFO -Message "Tweak $($t.id): $($res.status)" -Data @{ detalhe = "$($res.detalhe)" }
        $resultados.Add($res)
    }
    Write-Progress -Activity 'Aplicando tweaks' -Completed

    $arr = $resultados.ToArray()
    [pscustomobject]@{
        preset       = $Plan.preset
        executadoEm  = (Get-Date).ToString('o')
        itens        = $arr
        aplicados    = @($arr | Where-Object { $_.status -in @('aplicado', 'aplicadoNaoVerificado') }).Count
        jaAplicados  = @($arr | Where-Object { $_.status -eq 'jaAplicado' }).Count
        falhas       = @($arr | Where-Object { $_.status -eq 'falha' }).Count
        pulados      = @($arr | Where-Object { $_.status -in @('semConsentimento', 'naoAplicavel', 'naoSuportado', 'simulado') }).Count
        requerReboot = (@($arr | Where-Object { ($_.status -in @('aplicado', 'aplicadoNaoVerificado')) -and $_.requerReboot }).Count -gt 0)
    }
}
