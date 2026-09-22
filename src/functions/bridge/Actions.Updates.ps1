# functions/bridge/Actions.Updates.ps1
# Acoes da ponte para a aba "Atualizacoes": tres politicas de Windows Update
# (grupo exclusivo "windows-update", radio) lidas direto de
# src/config/tweaks.updates.json - nao depende do catalogo geral de Ajustes
# (mantido por outra tarefa em Actions.Tweaks.ps1).
#
# REGRA DE RUNSPACE (mesma das outras abas): tudo que toca o Engine ou o Core
# roda DENTRO de um job. A thread da janela so faz pre-validacao (sessao,
# elevacao, id valido) lendo $sync.
#
# Modo de teste: nenhuma acao aqui toca HKLM nem servico real. O tweak
# escolhido e reescrito (ConvertTo-TmxUpdateTestTweak) para gravar sob
# HKCU:\Software\TweakMaxing_Tests\Updates e as acoes de servico (so existem
# em UPD-002) sao descartadas - documentado tambem no cabecalho de
# WindowsUpdate.ps1. $script:TmxUpdateTestRoot e definido em
# functions/tweaks/WindowsUpdate.ps1 (carregado antes desta pasta) - mesma
# raiz que Get-TmxUpdateDefaultRegistryRoot usa para as funcoes Test-.

# ---------------------------------------------------------------------------
# Catalogo (direto do arquivo, nao do catalogo geral)
# ---------------------------------------------------------------------------

function Get-TmxUpdateConfigDir {
    <#
    .SYNOPSIS
        Pasta src/config. Nunca depende de $PSScriptRoot: dentro de uma
        runspace do pool as funcoes chegam como texto e $PSScriptRoot e $null.
    #>
    [CmdletBinding()]
    param()

    if ($null -ne $sync -and $sync.webRoot) {
        $dir = Join-Path (Split-Path $sync.webRoot -Parent) 'config'
        if (Test-Path -LiteralPath $dir) { return $dir }
    }
    $null
}

function Get-TmxUpdatePolicyCatalog {
    <#
    .SYNOPSIS
        Os tres tweaks UPD-* de tweaks.updates.json, em ordem de id.
    .PARAMETER Path
        Arquivo alternativo (testes). Sem ele: $sync.configs['tweaks.updates']
        quando ja carregado, senao o arquivo do disco.
    #>
    [CmdletBinding()]
    param([string] $Path)

    if (-not $Path) {
        $cfg = $null
        if ($null -ne $sync) { $cfg = $sync.configs }
        if ($null -ne $cfg -and $cfg -is [System.Collections.IDictionary] -and $cfg.Contains('tweaks.updates')) {
            $doc = $cfg['tweaks.updates']
            if ($null -ne $doc) { return @($doc.tweaks | Where-Object { $_ } | Sort-Object id) }
        }
        $dir = Get-TmxUpdateConfigDir
        if ($dir) { $Path = Join-Path $dir 'tweaks.updates.json' }
    }

    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) {
        throw "tweaks.updates.json nao encontrado (procurado em: '$Path')"
    }
    $doc = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    @($doc.tweaks | Where-Object { $_ } | Sort-Object id)
}

function Get-TmxUpdateById {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Id)
    @(Get-TmxUpdatePolicyCatalog | Where-Object { "$($_.id)" -ieq $Id }) | Select-Object -First 1
}

# ---------------------------------------------------------------------------
# Reescrita para o modo de teste
# ---------------------------------------------------------------------------

function ConvertTo-TmxUpdateTestTweak {
    <#
    .SYNOPSIS
        Copia do tweak que nao toca no sistema real: acoes 'registry' tem o
        prefixo HKLM:\SOFTWARE trocado por $TestRoot, acoes 'service' somem, e
        uma acao 'funcao' ganha parametros.registryRoot = $TestRoot.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Tweak, [Parameter(Mandatory)] [string] $TestRoot)

    $prefixo = 'HKLM:\SOFTWARE'
    $acoesNovas = New-Object 'System.Collections.Generic.List[object]'

    foreach ($a in @($Tweak.acoes)) {
        if ($null -eq $a) { continue }
        switch ("$($a.tipo)") {
            'service' {
                # dropada de proposito: o modo de teste nunca muda servico real.
                continue
            }
            'registry' {
                $caminho = "$($a.path)"
                if ($caminho -like "$prefixo*") { $caminho = $TestRoot + $caminho.Substring($prefixo.Length) }

                $copia = [ordered]@{
                    tipo      = 'registry'
                    path      = $caminho
                    name      = "$($a.name)"
                    valueType = "$(Get-TmxActionProp -Action $a -Nome 'valueType' -Padrao 'DWord')"
                }
                if ([bool](Get-TmxActionProp -Action $a -Nome 'remove' -Padrao $false)) {
                    $copia.remove = $true
                } else {
                    $copia.value = $a.value
                }
                $acoesNovas.Add([pscustomobject]$copia)
            }
            'funcao' {
                $params = @{}
                $paramObj = Get-TmxActionProp -Action $a -Nome 'parametros' -Padrao $null
                if ($paramObj) {
                    foreach ($p in $paramObj.PSObject.Properties) { $params[$p.Name] = $p.Value }
                }
                $params['registryRoot'] = $TestRoot
                $acoesNovas.Add([pscustomobject]@{ tipo = 'funcao'; nome = "$($a.nome)"; parametros = $params })
            }
            default { $acoesNovas.Add($a) }
        }
    }

    $copiaTweak = $Tweak.PSObject.Copy()
    $copiaTweak | Add-Member -NotePropertyName acoes -NotePropertyValue @($acoesNovas.ToArray()) -Force
    $copiaTweak
}

# ---------------------------------------------------------------------------
# Estado da sessao atual e payloads da interface
# ---------------------------------------------------------------------------

function Get-TmxUpdateRunRecords {
    <#
    .SYNOPSIS
        Registros do state.json da sessao atual (vazio quando nao ha sessao).
    #>
    [CmdletBinding()]
    param()

    $caminho = $null
    if ($null -ne $sync -and $null -ne $sync.session) { $caminho = "$($sync.session.statePath)" }
    if (-not $caminho -or -not (Test-Path -LiteralPath $caminho)) { return @() }
    try {
        @(Import-TmxState -StatePath $caminho)
    } catch {
        Write-TmxLog -Level WARN -Message "state.json da sessao nao pode ser lido: $($_.Exception.Message)"
        @()
    }
}

function Get-TmxUpdateAppliedIdsInRun {
    <#
    .SYNOPSIS
        Ids UPD-* que tem registro aplicado/falha/aplicando na execucao atual
        (logo, revertivel e/ou precisa ser desfeito antes de trocar de politica).
    #>
    [CmdletBinding()]
    param()

    $ids = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($r in @(Get-TmxUpdateRunRecords)) {
        if ($null -eq $r) { continue }
        if ("$($r.status)" -cnotin @('aplicado', 'falha', 'aplicando')) { continue }
        [void]$ids.Add("$($r.tweakId)")
    }
    # ,$ids: um HashSet devolvido "pelado" sai desenrolado pelo pipeline.
    , $ids
}

function Get-TmxUpdateChaveList {
    <#
    .SYNOPSIS
        Lista humana do que UM tweak UPD-* muda (chaves de registro e
        servicos), lida das proprias acoes do catalogo.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Tweak)

    $lista = New-Object 'System.Collections.Generic.List[string]'
    foreach ($a in @($Tweak.acoes)) {
        if ($null -eq $a) { continue }
        switch ("$($a.tipo)") {
            'registry' {
                if ([bool](Get-TmxActionProp -Action $a -Nome 'remove' -Padrao $false)) {
                    $lista.Add("$($a.name) (removido)")
                } else {
                    $lista.Add("$($a.name) = $($a.value)")
                }
            }
            'service' {
                $lista.Add("servico $($a.nome): $($a.tipoInicio)")
            }
            'funcao' {
                switch ("$($a.nome)") {
                    'Set-TmxUpdatePolicyDefault' {
                        foreach ($n in $script:TmxUpdatePolicyValueNames)   { $lista.Add("$n (removido)") }
                        foreach ($n in $script:TmxUpdateAuValueNames)      { $lista.Add("$n (removido)") }
                        foreach ($n in $script:TmxUpdateDriverValueNames)  { $lista.Add("$n (removido)") }
                        foreach ($n in $script:TmxUpdateMetadataValueNames){ $lista.Add("$n (removido)") }
                        foreach ($n in $script:TmxUpdatePauseValueNames)   { $lista.Add("$n (removido)") }
                        foreach ($s in $script:TmxUpdateServiceAlvos)      { $lista.Add("servico $($s.nome): $($s.tipoInicio)") }
                    }
                    'Set-TmxUpdatePause' {
                        $dias = 35
                        $paramObj = Get-TmxActionProp -Action $a -Nome 'parametros' -Padrao $null
                        $d = Get-TmxActionProp -Action $paramObj -Nome 'dias' -Padrao $null
                        if ($d) { try { $dias = [int]$d } catch { $dias = 35 } }
                        foreach ($n in $script:TmxUpdatePauseValueNames) { $lista.Add("$n (+$dias dia(s))") }
                    }
                }
            }
        }
    }
    $lista.ToArray()
}

function Get-TmxUpdateAtivo {
    <#
    .SYNOPSIS
        'ativo' de UM tweak UPD-*, na raiz certa (HKCU de teste quando
        $sync.testMode, senao HKLM real).
    .NOTES
        Nao usa Test-TmxTweakApplied para os tweaks tipo 'funcao' (UPD-001/
        UPD-003): o despacho 'funcao' do Engine chama a funcao Test-Tmx<X> so
        com -Tweak -Profile, nunca com -Parametros - entao ela nunca saberia
        qual raiz usar no modo de teste. Aqui a funcao de teste e chamada
        direto, com -RegistryRoot explicito (mesmo padrao usado por
        Get-TmxFeatureCurrentState para o Legacy Recovery).
        Para UPD-002 (registry/service puros) Test-TmxTweakApplied funciona
        normalmente: essas acoes leem o path direto do proprio objeto, que ja
        vem reescrito para a raiz de teste quando for o caso.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Tweak)

    $raiz = Get-TmxUpdateDefaultRegistryRoot

    $primeiraAcao = @($Tweak.acoes) | Select-Object -First 1
    if ($primeiraAcao -and "$($primeiraAcao.tipo)" -eq 'funcao') {
        $fn = "$($primeiraAcao.nome)"
        $teste = $fn -replace '^Set-', 'Test-'
        if (-not (Get-Command -Name $teste -CommandType Function -ErrorAction SilentlyContinue)) { return $false }
        try {
            $r = & $teste -Tweak $Tweak -Profile $null -RegistryRoot $raiz
            return [bool]($r -and $r.aplicado -eq $true)
        } catch {
            return $false
        }
    }

    $alvo = $Tweak
    if ($null -ne $sync -and $sync.testMode) { $alvo = ConvertTo-TmxUpdateTestTweak -Tweak $Tweak -TestRoot $script:TmxUpdateTestRoot }
    try {
        $r = Test-TmxTweakApplied -Tweak $alvo -Profile $null
        [bool]($r -and $r.aplicado -eq $true)
    } catch {
        $false
    }
}

function Get-TmxUpdateListPayload {
    <#
    .SYNOPSIS
        As tres politicas + estado atual (Get-TmxUpdateAtivo) + o que tem
        undo na execucao atual.
    .NOTES
        So roda dentro de um job: le o registro/servico de verdade e pode demorar.
    #>
    [CmdletBinding()]
    param()

    $catalogo = @(Get-TmxUpdatePolicyCatalog)
    $comUndo  = Get-TmxUpdateAppliedIdsInRun
    $lista    = New-Object 'System.Collections.Generic.List[object]'

    foreach ($t in $catalogo) {
        $ativo = Get-TmxUpdateAtivo -Tweak $t

        $lista.Add(@{
            id        = "$($t.id)"
            nome      = "$($t.nome)"
            descricao = "$($t.descricao)"
            porque    = "$($t.porque)"
            evidencia = "$($t.evidencia)"
            chaves    = @(Get-TmxUpdateChaveList -Tweak $t)
            ativo     = $ativo
            temUndo   = $comUndo.Contains("$($t.id)")
        })
    }

    @{ itens = $lista.ToArray(); grupo = 'windows-update'; carregadoEm = (Get-Date).ToString('o') }
}

# ---------------------------------------------------------------------------
# Pre-validacoes sincronas
# ---------------------------------------------------------------------------

function Assert-TmxUpdateSession {
    [CmdletBinding()]
    param()
    if ($null -eq $sync -or $null -eq $sync.session -or -not $sync.session.pronto) {
        throw 'sessao sem ponto de restauracao: abra a sessao antes de aplicar'
    }
}

function Assert-TmxUpdateElevation {
    <#
    .SYNOPSIS
        Fora do modo de teste, aplicar exige elevacao: UPD-002 escreve em
        HKLM e muda StartupType de servico, o que falha silenciosamente (ou
        com um erro obscuro no meio do job) sem privilegios de administrador.
        No modo de teste tudo e reescrito para HKCU, entao a checagem nao
        se aplica.
    #>
    [CmdletBinding()]
    param()
    if ($null -ne $sync -and $sync.testMode) { return }
    if (-not (Test-TmxElevation)) {
        throw 'o TweakMaxing precisa ser executado como administrador para aplicar uma politica de Windows Update'
    }
}

# ---------------------------------------------------------------------------
# Registro das acoes da ponte
# ---------------------------------------------------------------------------

function Register-TmxUpdateActions {
    <#
    .SYNOPSIS
        Registra updates.list, updates.apply e updates.undo.
    #>
    [CmdletBinding()]
    param()

    Register-TmxBridgeAction -Name 'updates.list' -Async -Handler {
        param($payload)
        Send-TmxJobProgress -Pct 10 -Status 'Lendo as politicas de atualizacao...'
        Get-TmxUpdateListPayload
    }

    # Sincrona de proposito, apesar de o trabalho ir para o pool: sessao, id e
    # elevacao TEM que ser conferidos antes de existir job - mesmo padrao de
    # plan.apply/features.apply.
    Register-TmxBridgeAction -Name 'updates.apply' -Handler {
        param($payload)

        $id = "$($payload.id)"
        if (-not $id) { throw 'id obrigatorio' }
        if ($id -cnotmatch '^UPD-\d{3}$') { throw "id fora do catalogo de atualizacoes: $id" }

        $tweak = Get-TmxUpdateById -Id $id
        if ($null -eq $tweak) { throw "id fora do catalogo de atualizacoes: $id" }

        Assert-TmxUpdateSession
        Assert-TmxUpdateElevation

        $jobId = Start-TmxJob -Name 'updates.apply' -Payload @{ id = $id } -Handler {
            param($p)

            $t = Get-TmxUpdateById -Id "$($p.id)"
            if ($null -eq $t) { throw "id fora do catalogo de atualizacoes: $($p.id)" }

            if ($null -ne $sync -and $sync.testMode) {
                $t = ConvertTo-TmxUpdateTestTweak -Tweak $t -TestRoot $script:TmxUpdateTestRoot
            }

            # grupo windows-update e exclusivo: antes de aplicar a escolhida,
            # desfaz qualquer outra politica do grupo com registro nesta execucao.
            $aplicados = Get-TmxUpdateAppliedIdsInRun
            $outrosIds = @(Get-TmxUpdatePolicyCatalog | Where-Object { "$($_.id)" -cne "$($p.id)" } | ForEach-Object { "$($_.id)" })
            foreach ($outroId in $outrosIds) {
                if ($aplicados.Contains($outroId) -and $null -ne $sync.session -and "$($sync.session.runId)") {
                    Send-TmxJobProgress -Pct 10 -Status "Revertendo $outroId..."
                    Undo-TweakMaxing -RunId "$($sync.session.runId)" -TweakId $outroId -Quiet | Out-Null
                }
            }

            Send-TmxJobProgress -Pct 40 -Status "Aplicando $($t.nome)..."
            $r = Invoke-TmxTransientTweak -Tweak $t

            Send-TmxJobProgress -Pct 85 -Status 'Relendo o estado...'
            $lista = Get-TmxUpdateListPayload
            Send-TmxJobProgress -Pct 100 -Status 'Concluido'

            @{
                resultado = (ConvertTo-TmxTransientResult -Resultado $r)
                lista     = $lista
            }
        }

        @{ jobId = $jobId }
    }

    Register-TmxBridgeAction -Name 'updates.undo' -Handler {
        param($payload)

        $id = "$($payload.id)"
        if (-not $id) { throw 'id obrigatorio' }
        if ($null -eq $sync.session -or -not $sync.session.runId) { throw 'nenhuma execucao ativa para reverter' }

        $jobId = Start-TmxJob -Name 'updates.undo' -Payload @{ id = $id; runId = "$($sync.session.runId)" } -Handler {
            param($p)
            Send-TmxJobProgress -Pct 20 -Status "Revertendo $($p.id)..."
            $resumo = Undo-TweakMaxing -RunId "$($p.runId)" -TweakId "$($p.id)" -Quiet
            Send-TmxJobProgress -Pct 80 -Status 'Relendo o estado...'
            @{
                id     = "$($p.id)"
                resumo = @{
                    total      = [int]$resumo.total
                    revertidos = [int]$resumo.revertidos
                    falhas     = [int]$resumo.falhas
                    pulados    = [int]$resumo.pulados
                }
                lista = (Get-TmxUpdateListPayload)
            }
        }

        @{ jobId = $jobId }
    }
}
