# functions/tweaks/UltimatePerformance.ps1
# ENE-004 / ENE-005: plano de energia Desempenho Maximo.
#
# Porte de Tweaks/Power.ps1 do CS2Tuner. O plano nao e "criado": o Windows traz
# um modelo embutido (GUID fixo abaixo) que se duplica com powercfg /duplicatescheme.
# Por isso ativar e desativar sao operacoes simetricas e completamente reversiveis.

$script:TmxUltimateSourceGuid = 'e9a42b02-d5df-448d-aa00-03f14749eb61'
$script:TmxUltimateRegex      = '(?i)ultimate|desempenho m[aa]ximo|m[aa]ximo desempenho'

function Get-TmxPowerSchemeList {
    <#
    .SYNOPSIS
        Esquemas de energia existentes: [{ guid, nome, ativo }].
    #>
    $r = Invoke-TmxPowercfg @('/list')
    $lista = New-Object 'System.Collections.Generic.List[object]'
    if ($r.codigo -ne 0) { return , $lista.ToArray() }
    foreach ($linha in ("$($r.saida)" -split "`n")) {
        $m = [regex]::Match($linha, '([0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12})\s*\(([^)]*)\)\s*(\*?)')
        if (-not $m.Success) { continue }
        $lista.Add([pscustomobject]@{
            guid  = $m.Groups[1].Value
            nome  = $m.Groups[2].Value.Trim()
            ativo = ($m.Groups[3].Value -eq '*')
        })
    }
    , $lista.ToArray()
}

function Get-TmxUltimateDuplicates {
    # Esquemas de Desempenho Maximo que existem de fato na maquina (o modelo
    # embutido nao aparece em /list ate ser duplicado).
    $todos = Get-TmxPowerSchemeList
    , @($todos | Where-Object { "$($_.nome)" -match $script:TmxUltimateRegex })
}

# ---------------------------------------------------------------------------
# ENE-004: ativar
# ---------------------------------------------------------------------------

function Test-TmxUltimatePowerPlan {
    [CmdletBinding()]
    param($Tweak, $Profile)

    $s = Get-TmxActivePowerScheme
    if (-not $s) {
        return [pscustomobject]@{ aplicado = $null; atual = $null; esperado = 'Desempenho maximo'; detalhe = 'esquema ativo nao identificado' }
    }
    $ok = ("$($s.nome)" -match $script:TmxUltimateRegex) -or ("$($s.guid)" -ieq $script:TmxUltimateSourceGuid)
    [pscustomobject]@{
        aplicado = $ok
        atual    = "$($s.nome)"
        esperado = 'Desempenho maximo'
        detalhe  = "plano ativo: $($s.nome)"
    }
}

function Set-TmxUltimatePowerPlan {
    [CmdletBinding()]
    param($Tweak, $Profile, $Parametros)

    $ativo = Get-TmxActivePowerScheme
    if (-not $ativo) {
        return [pscustomobject]@{ ok = $false; detalhe = 'esquema de energia ativo nao identificado' }
    }

    $rec = New-TmxCmdletRecord -TweakId "$($Tweak.id)" -Funcao 'Set-TmxUltimatePowerPlan' -Alvo 'plano de energia ativo' `
            -Estado @{ esquemaAnterior = "$($ativo.guid)"; nomeAnterior = "$($ativo.nome)"; esquemaCriado = $null } `
            -ValorAnterior "$($ativo.nome)" -ValorNovo 'Desempenho maximo'

    $dup  = Invoke-TmxPowercfg @('/duplicatescheme', $script:TmxUltimateSourceGuid)
    $novo = [regex]::Match("$($dup.saida)", '[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}').Value
    if ($dup.codigo -ne 0 -or -not $novo) {
        Complete-TmxStateRecord -Record $rec -Ok $false -Erro "duplicatescheme falhou: $($dup.saida)" | Out-Null
        return [pscustomobject]@{ ok = $false; detalhe = "nao foi possivel duplicar o esquema: $($dup.saida)"; registro = $rec }
    }

    # Persiste o GUID criado ANTES de ativar: se o processo morrer aqui, o undo
    # ainda sabe qual esquema apagar.
    $rec.detalhe.estado.esquemaCriado = $novo
    Save-TmxState

    $act = Invoke-TmxPowercfg @('/setactive', $novo)
    $ok  = ($act.codigo -eq 0)
    $erro = $null
    if (-not $ok) { $erro = "setactive falhou: $($act.saida)" }
    Complete-TmxStateRecord -Record $rec -Ok $ok -Erro $erro | Out-Null

    [pscustomobject]@{
        ok      = $ok
        detalhe = $(if ($ok) { "'$($ativo.nome)' -> Desempenho maximo ($novo)" } else { $erro })
        registro = $rec
    }
}

function Undo-TmxUltimatePowerPlan {
    [CmdletBinding()]
    param($Estado)

    if (-not $Estado -or -not $Estado.esquemaAnterior) { throw 'sem esquema anterior no estado; nada a restaurar' }

    $r = Invoke-TmxPowercfg @('/setactive', "$($Estado.esquemaAnterior)")
    if ($r.codigo -ne 0) { throw "setactive $($Estado.esquemaAnterior) falhou: $($r.saida)" }
    if ($Estado.esquemaCriado) {
        Invoke-TmxPowercfg @('/delete', "$($Estado.esquemaCriado)") | Out-Null
    }
    "plano restaurado para '$($Estado.nomeAnterior)'; esquema duplicado removido"
}

# ---------------------------------------------------------------------------
# ENE-005: remover os duplicados
# ---------------------------------------------------------------------------

function Test-TmxRemoveUltimatePowerPlan {
    [CmdletBinding()]
    param($Tweak, $Profile)

    $dups = Get-TmxUltimateDuplicates
    [pscustomobject]@{
        aplicado = ($dups.Count -eq 0)
        atual    = "$($dups.Count) plano(s) de Desempenho Maximo"
        esperado = '0 plano de Desempenho Maximo'
        detalhe  = $(if ($dups.Count -gt 0) { "presentes: $(@($dups | ForEach-Object { $_.nome }) -join ', ')" } else { 'nenhum plano de Desempenho Maximo' })
    }
}

function Set-TmxRemoveUltimatePowerPlan {
    [CmdletBinding()]
    param($Tweak, $Profile, $Parametros)

    $dups = Get-TmxUltimateDuplicates
    if ($dups.Count -eq 0) {
        return [pscustomobject]@{ ok = $true; naoAplicavel = $true; detalhe = 'nenhum plano de Desempenho Maximo para remover' }
    }

    $guids = @($dups | ForEach-Object { @{ guid = "$($_.guid)"; nome = "$($_.nome)" } })
    $rec = New-TmxCmdletRecord -TweakId "$($Tweak.id)" -Funcao 'Set-TmxRemoveUltimatePowerPlan' -Alvo 'planos de Desempenho Maximo' `
            -Estado @{ esquemas = $guids; modelo = $script:TmxUltimateSourceGuid } `
            -ValorAnterior (@($dups | ForEach-Object { "$($_.nome) ($($_.guid))" }) -join '; ') -ValorNovo 'removidos'

    try {
        # Se um dos removidos for o plano ativo, o powercfg troca sozinho para
        # outro esquema; nao forcamos nada para nao escolher pelo usuario.
        foreach ($d in $dups) {
            $r = Invoke-TmxPowercfg @('/delete', "$($d.guid)")
            if ($r.codigo -ne 0) { throw "powercfg /delete $($d.guid) falhou ($($r.codigo)): $($r.saida)" }
        }
        Complete-TmxStateRecord -Record $rec -Ok $true | Out-Null
        [pscustomobject]@{ ok = $true; detalhe = "$($dups.Count) plano(s) de Desempenho Maximo removido(s)"; registro = $rec }
    } catch {
        Complete-TmxStateRecord -Record $rec -Ok $false -Erro $_.Exception.Message | Out-Null
        [pscustomobject]@{ ok = $false; detalhe = $_.Exception.Message; registro = $rec }
    }
}

function Undo-TmxRemoveUltimatePowerPlan {
    [CmdletBinding()]
    param($Estado)

    $modelo = $script:TmxUltimateSourceGuid
    if ($Estado -and $Estado.modelo) { $modelo = "$($Estado.modelo)" }

    $quantos = @($Estado.esquemas).Count
    if ($quantos -eq 0) { return 'nenhum plano havia sido removido; nada a recriar' }

    $criados = New-Object 'System.Collections.Generic.List[string]'
    for ($i = 0; $i -lt $quantos; $i++) {
        $r = Invoke-TmxPowercfg @('/duplicatescheme', $modelo)
        $novo = [regex]::Match("$($r.saida)", '[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}').Value
        if ($r.codigo -ne 0 -or -not $novo) { throw "duplicatescheme falhou: $($r.saida)" }
        $criados.Add($novo)
    }
    "plano(s) de Desempenho Maximo recriado(s): $($criados.ToArray() -join ', ')"
}
