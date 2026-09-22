# functions/bridge/Actions.Features.ps1
# Acoes da ponte para a aba "Configurar": recursos do Windows (DISM),
# correcoes de manutencao, paineis legados e DNS.
#
# REGRA DE RUNSPACE (a mesma da aba Ajustes): tudo que toca o Engine ou o Core
# roda DENTRO de um job. O estado de execucao ($script:TmxRun,
# $script:TmxStateRecords) vive na unica runspace do pool e a thread da janela
# nao o enxerga. A runspace da janela so faz pre-validacao lendo $sync.
#
# Estado compartilhado: $sync.features = @{ catalog; carregadoEm }

# ---------------------------------------------------------------------------
# Catalogo de correcoes
# ---------------------------------------------------------------------------

function Get-TmxFixCatalog {
    <#
    .SYNOPSIS
        As correcoes de manutencao, em pt-BR, com o aviso do que cada uma faz.
    .OUTPUTS
        Array de { id, nome, descricao, aviso[], requerSessao, opcaoAgressiva }.
    .NOTES
        'requerSessao' e verdadeiro so onde ha escrita de registro passando por
        Set-TmxRegistry: e essa escrita que precisa de uma execucao ativa para
        gravar o valor anterior no state.json. As demais correcoes sao resets
        sem estado anterior para guardar.
    #>
    [CmdletBinding()]
    param([nullable[bool]] $IncluirTeste)

    if ($null -eq $IncluirTeste) { $IncluirTeste = [bool]($null -ne $sync -and $sync.testMode) }

    $lista = New-Object 'System.Collections.Generic.List[object]'

    $lista.Add([pscustomobject]@{
        id             = 'FIX-NET'
        nome           = 'Resetar a rede'
        descricao      = 'Devolve a pilha de rede ao padrao quando a internet some sem motivo aparente.'
        aviso          = @('netsh winsock reset', 'netsh int ip reset', 'Exige reiniciar o computador para valer.')
        requerSessao   = $false
        opcaoAgressiva = $false
    })
    $lista.Add([pscustomobject]@{
        id             = 'FIX-WINGET'
        nome           = 'Reinstalar o winget'
        descricao      = 'Reinstala o gerenciador de pacotes do Windows quando ele some ou passa a falhar em tudo.'
        aviso          = @('Instala/atualiza o modulo Microsoft.WinGet.Client', 'Refaz a deteccao do winget')
        requerSessao   = $false
        opcaoAgressiva = $false
    })
    $lista.Add([pscustomobject]@{
        id             = 'FIX-UPDATE'
        nome           = 'Reconstruir o Windows Update'
        descricao      = 'Para os servicos, limpa a fila e reregistra os componentes do Windows Update.'
        aviso          = @(
            'Para BITS, wuauserv, appidsvc e cryptsvc',
            'Apaga a fila do BITS (qmgr*.dat) e o WindowsUpdate.log',
            'Modo agressivo: renomeia SoftwareDistribution e catroot2 (perde o historico de atualizacoes)',
            'Reregistra as DLLs do BITS e do Windows Update',
            'Remove as configuracoes de cliente WSUS (registradas para reversao)',
            'netsh winsock reset e limpeza dos trabalhos do BITS',
            'Religa os servicos e forca uma nova procura por atualizacoes'
        )
        requerSessao   = $true
        opcaoAgressiva = $true
    })
    $lista.Add([pscustomobject]@{
        id             = 'FIX-REPAIR'
        nome           = 'Verificar a integridade do sistema'
        descricao      = 'Repara a imagem de componentes e depois os arquivos protegidos do Windows.'
        aviso          = @('DISM /Online /Cleanup-Image /RestoreHealth', 'sfc /scannow', 'Pode levar varios minutos.')
        requerSessao   = $false
        opcaoAgressiva = $false
    })
    $lista.Add([pscustomobject]@{
        id             = 'FIX-NTP'
        nome           = 'Trocar o servidor de horario'
        descricao      = 'Troca time.windows.com por pool.ntp.org e sincroniza o relogio.'
        aviso          = @(
            'Grava NtpServer = pool.ntp.org,0x8 (o valor anterior vai para o state.json)',
            'w32tm /config /syncfromflags:manual /update',
            'w32tm /resync'
        )
        requerSessao   = $true
        opcaoAgressiva = $false
    })
    $lista.Add([pscustomobject]@{
        id             = 'FIX-AUTOLOGON'
        nome           = 'AutoLogon (Sysinternals)'
        descricao      = 'Abre a pagina oficial do Autologon. O TweakMaxing nao baixa nem executa o binario por voce.'
        aviso          = @('Abre https://learn.microsoft.com/sysinternals/downloads/autologon no navegador padrao', 'Nada e alterado no sistema.')
        requerSessao   = $false
        opcaoAgressiva = $false
    })

    if ($IncluirTeste) {
        $lista.Add([pscustomobject]@{
            id             = 'FIX-TST'
            nome           = 'Teste - correcao sintetica'
            descricao      = 'Correcao de teste: nao toca em nada, so devolve um passo concluido.'
            aviso          = @('Nenhuma alteracao no sistema.')
            requerSessao   = $false
            opcaoAgressiva = $false
        })
    }

    # .ToArray(): @() sobre List generica vazia falha no PS 5.1
    $lista.ToArray()
}

function Invoke-TmxFixById {
    <#
    .SYNOPSIS
        Roda a correcao de um id do catalogo. Ids fora do catalogo lancam.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Id,
        [switch] $Aggressive
    )

    switch ("$Id") {
        'FIX-NET'       { return (Invoke-TmxFixNetwork) }
        'FIX-WINGET'    { return (Invoke-TmxFixWinget) }
        'FIX-UPDATE'    { return (Invoke-TmxFixUpdate -Aggressive:$Aggressive) }
        'FIX-REPAIR'    { return (Invoke-TmxFixSystemRepair) }
        'FIX-NTP'       { return (Invoke-TmxFixNtp) }
        'FIX-AUTOLOGON' { return (Invoke-TmxFixAutoLogon) }
        'FIX-TST' {
            if ($null -eq $sync -or -not $sync.testMode) { throw 'FIX-TST so existe no modo de teste' }
            Send-TmxFixProgress -Pct 50 -Status 'Correcao de teste...'
            $passo = New-TmxFixStep -Nome 'no-op' -Ok $true -Saida 'nada foi alterado'
            Send-TmxFixProgress -Pct 100 -Status 'Concluido'
            return (New-TmxFixResult -Passos @($passo) -Detalhe 'correcao de teste concluida')
        }
        default { throw "correcao desconhecida: '$Id'" }
    }
}

function ConvertTo-TmxFixPayload {
    # Resultado de uma correcao -> JSON enxuto da interface.
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Resultado, [string] $Id)

    @{
        id      = "$Id"
        ok      = [bool]$Resultado.ok
        detalhe = "$($Resultado.detalhe)"
        passos  = @(@($Resultado.passos) | ForEach-Object {
            @{ nome = "$($_.nome)"; ok = [bool]$_.ok; saida = "$($_.saida)" }
        })
    }
}

# ---------------------------------------------------------------------------
# Estado compartilhado e aplicacao por plano transitorio
# ---------------------------------------------------------------------------

function Get-TmxFeatureUiState {
    <#
    .SYNOPSIS
        O bloco $sync.features, criado na primeira chamada.
    #>
    [CmdletBinding()]
    param()

    if ($null -eq $sync) { throw 'Get-TmxFeatureUiState: $sync nao existe (bootstrap nao rodou).' }
    if ($null -eq $sync.features) {
        $sync.features = @{ catalog = $null; carregadoEm = $null }
    }
    $sync.features
}

function Get-TmxFeatureCatalogCached {
    <#
    .SYNOPSIS
        O catalogo de recursos em cache (montado na primeira chamada).
    #>
    [CmdletBinding()]
    param([switch] $Recarregar)

    $st = Get-TmxFeatureUiState
    if ($Recarregar -or $null -eq $st.catalog) {
        $st.catalog     = Get-TmxFeatureCatalog
        $st.carregadoEm = (Get-Date).ToString('o')
    }
    @($st.catalog)
}

function Get-TmxFeatureById {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Id)
    @(Get-TmxFeatureCatalogCached | Where-Object { "$($_.id)" -ieq $Id }) | Select-Object -First 1
}

function Get-TmxFeatureRunRecords {
    <#
    .SYNOPSIS
        Registros do state.json da sessao atual (vazio quando nao ha sessao).
    .NOTES
        Le do ARQUIVO, nao de $script:TmxStateRecords: assim a mesma funcao
        serve a thread da janela e a runspace do pool.
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

function Get-TmxFeatureUndoIds {
    <#
    .SYNOPSIS
        Ids que tem algo revertivel na execucao atual.
    #>
    [CmdletBinding()]
    param()

    $ids = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($r in @(Get-TmxFeatureRunRecords)) {
        if ($null -eq $r) { continue }
        if ("$($r.status)" -cnotin @('aplicado', 'falha', 'aplicando')) { continue }
        [void]$ids.Add("$($r.tweakId)")
    }
    # ,$ids: um HashSet devolvido "pelado" sai desenrolado pelo pipeline e o
    # chamador recebe as strings, nao o conjunto.
    , $ids
}

function Invoke-TmxTransientTweak {
    <#
    .SYNOPSIS
        Aplica UM tweak montado em memoria pelo mesmo Invoke-TmxPlan que aplica
        o catalogo de producao.
    .DESCRIPTION
        E o que garante que um recurso do Windows ou uma troca de DNS deixem
        registro no state.json e sejam revertiveis por Undo-TweakMaxing, em vez
        de virarem um caminho de escrita paralelo sem rastro.
    .PARAMETER Profile
        O perfil coletado. As acoes usadas aqui (feature, funcao, registry) nao
        leem o perfil - quem le sao as condicoes, avaliadas no Resolve-TmxPlan,
        que um tweak transitorio nao percorre. Por isso o padrao e @{}: coletar
        o perfil inteiro custaria segundos por clique sem mudar nada.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Tweak,
        $Profile = @{}
    )

    $plano = [pscustomobject]@{
        preset   = 'manual'
        geradoEm = (Get-Date).ToString('o')
        itens    = @([pscustomobject]@{
            id          = "$($Tweak.id)"
            nome        = "$($Tweak.nome)"
            selecionado = $true
            consentido  = $true
            tweak       = $Tweak
        })
        resumo   = $null
    }
    Invoke-TmxPlan -Plan $plano -Profile $Profile
}

function ConvertTo-TmxTransientResult {
    # Resultado do Invoke-TmxPlan -> JSON enxuto da interface.
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Resultado)

    @{
        itens = @(@($Resultado.itens) | ForEach-Object {
            @{
                id           = "$($_.id)"
                nome         = "$($_.nome)"
                status       = "$($_.status)"
                detalhe      = "$($_.detalhe)"
                antes        = "$($_.antes)"
                depois       = "$($_.depois)"
                registros    = [int]$_.registros
                requerReboot = [bool]$_.requerReboot
                avisos       = @(@($_.avisos) | ForEach-Object { "$_" })
            }
        })
        aplicados    = [int]$Resultado.aplicados
        jaAplicados  = [int]$Resultado.jaAplicados
        falhas       = [int]$Resultado.falhas
        pulados      = [int]$Resultado.pulados
        requerReboot = [bool]$Resultado.requerReboot
    }
}

# ---------------------------------------------------------------------------
# Pre-validacoes sincronas
# ---------------------------------------------------------------------------

function Assert-TmxFeatureSession {
    [CmdletBinding()]
    param()
    if ($null -eq $sync -or $null -eq $sync.session -or -not $sync.session.pronto) {
        throw 'sessao sem ponto de restauracao: abra a sessao antes de aplicar'
    }
}

function Assert-TmxFeatureTestMode {
    <#
    .SYNOPSIS
        Trava do modo de teste: a suite roda na maquina real, entao so o
        recurso sintetico REC-TST pode ser aplicado de verdade.
    #>
    [CmdletBinding()]
    param([string] $Id)
    if ($null -eq $sync -or -not $sync.testMode) { return }
    if ("$Id" -cne 'REC-TST') { throw 'modo de teste: apenas o recurso REC-TST' }
}

function Assert-TmxFixTestMode {
    [CmdletBinding()]
    param([string] $Id)
    if ($null -eq $sync -or -not $sync.testMode) { return }
    if ("$Id" -cne 'FIX-TST') { throw 'modo de teste: apenas a correcao FIX-TST' }
}

function Assert-TmxDnsTestMode {
    [CmdletBinding()]
    param()
    if ($null -eq $sync -or -not $sync.testMode) { return }
    throw 'modo de teste: trocar o DNS da maquina real e recusado'
}

# ---------------------------------------------------------------------------
# Payloads da interface
# ---------------------------------------------------------------------------

function Get-TmxFeatureListPayload {
    <#
    .SYNOPSIS
        Recursos + estado atual + o que ja tem reversao na execucao atual.
    .NOTES
        So roda dentro de um job: Get-WindowsOptionalFeature le o sistema e
        demora segundos por recurso.
    #>
    [CmdletBinding()]
    param()

    $catalogo = @(Get-TmxFeatureCatalogCached -Recarregar)
    $comUndo  = Get-TmxFeatureUndoIds
    $total    = [math]::Max($catalogo.Count, 1)
    $lista    = New-Object 'System.Collections.Generic.List[object]'
    $i = 0

    foreach ($t in $catalogo) {
        $i++
        Send-TmxJobProgress -Pct ([int](10 + ($i - 1) / $total * 85)) -Status "Lendo $($t.nome)..."
        $lista.Add(@{
            id           = "$($t.id)"
            nome         = "$($t.nome)"
            descricao    = "$($t.descricao)"
            estado       = (Get-TmxFeatureCurrentState -Tweak $t)
            requerReboot = [bool]$t.requerReboot
            reversivel   = "$($t.reversivel)"
            nota         = "$($t.parcialNota)"
            recursos     = @(@($t.recursos) | ForEach-Object { "$_" })
            temUndo      = $comUndo.Contains("$($t.id)")
        })
    }

    @{ recursos = $lista.ToArray(); carregadoEm = (Get-Date).ToString('o') }
}

function Get-TmxDnsListPayload {
    [CmdletBinding()]
    param()

    @{
        provedores = @(Get-TmxDnsCatalog | ForEach-Object {
            @{
                id         = "$($_.id)"
                nome       = "$($_.nome)"
                primario   = "$($_.primario)"
                secundario = "$($_.secundario)"
                benchmark  = [bool]$_.benchmark
            }
        })
        # Where-Object { $_ } depois do ForEach: @($null) tem UM elemento no PS
        # 5.1, entao uma lista vazia de IPv6 viraria [""] no JSON e a interface
        # mostraria um servidor a mais, em branco.
        atual = @(Get-TmxDnsCurrent | ForEach-Object {
            @{
                indice = [int]$_.indice
                nome   = "$($_.nome)"
                v4     = @(@($_.v4) | ForEach-Object { "$_" } | Where-Object { $_ })
                v6     = @(@($_.v6) | ForEach-Object { "$_" } | Where-Object { $_ })
            }
        })
    }
}

# ---------------------------------------------------------------------------
# Registro das acoes da ponte
# ---------------------------------------------------------------------------

function Register-TmxFeatureActions {
    <#
    .SYNOPSIS
        Registra features.*, fixes.*, panels.* e dns.* .
    #>
    [CmdletBinding()]
    param()

    # --- recursos do Windows -------------------------------------------------

    Register-TmxBridgeAction -Name 'features.list' -Async -Handler {
        param($payload)
        Send-TmxJobProgress -Pct 5 -Status 'Lendo o catalogo de recursos...'
        Get-TmxFeatureListPayload
    }

    # Sincrona de proposito, apesar de o trabalho ir para o pool: sessao, id e
    # trava de modo de teste TEM que ser conferidos antes de existir job - com
    # -Async a resposta imediata ja teria dito ok:true.
    Register-TmxBridgeAction -Name 'features.apply' -Handler {
        param($payload)

        $id = "$($payload.id)"
        if (-not $id) { throw 'id obrigatorio' }
        $ligado = [bool]$payload.ligado

        Assert-TmxFeatureSession
        Assert-TmxFeatureTestMode -Id $id

        $t = Get-TmxFeatureById -Id $id
        if ($null -eq $t) { throw "recurso desconhecido: $id" }
        if (-not $ligado -and @($t.toggleDesligar).Count -eq 0) { throw "$id nao tem acao de desligar" }

        $jobId = Start-TmxJob -Name 'features.apply' -Payload @{ id = $id; ligado = $ligado } -Handler {
            param($p)

            $t = Get-TmxFeatureById -Id "$($p.id)"
            if ($null -eq $t) { throw "recurso desconhecido: $($p.id)" }

            $acoes = if ($p.ligado) { @($t.acoes) } else { @($t.toggleDesligar) }
            $variante = $t.PSObject.Copy()
            $variante | Add-Member -NotePropertyName acoes -NotePropertyValue @($acoes) -Force

            Send-TmxJobProgress -Pct 15 -Status "$(if ($p.ligado) { 'Ativando' } else { 'Desativando' }) $($t.nome)..."
            $r = Invoke-TmxTransientTweak -Tweak $variante

            Send-TmxJobProgress -Pct 85 -Status 'Relendo o estado do sistema...'
            $lista = Get-TmxFeatureListPayload
            Send-TmxJobProgress -Pct 100 -Status 'Concluido'

            @{
                id        = "$($p.id)"
                ligado    = [bool]$p.ligado
                resultado = (ConvertTo-TmxTransientResult -Resultado $r)
                catalogo  = $lista
            }
        }

        @{ jobId = $jobId }
    }

    Register-TmxBridgeAction -Name 'features.undo' -Handler {
        param($payload)

        $id = "$($payload.id)"
        if (-not $id) { throw 'id obrigatorio' }
        if ($null -eq $sync.session -or -not $sync.session.runId) { throw 'nenhuma execucao ativa para reverter' }

        $jobId = Start-TmxJob -Name 'features.undo' -Payload @{ id = $id; runId = "$($sync.session.runId)" } -Handler {
            param($p)
            Send-TmxJobProgress -Pct 20 -Status "Revertendo $($p.id)..."
            $resumo = Undo-TweakMaxing -RunId "$($p.runId)" -TweakId "$($p.id)" -Quiet
            Send-TmxJobProgress -Pct 80 -Status 'Relendo o estado do sistema...'
            @{
                id     = "$($p.id)"
                resumo = @{
                    total      = [int]$resumo.total
                    revertidos = [int]$resumo.revertidos
                    falhas     = [int]$resumo.falhas
                    pulados    = [int]$resumo.pulados
                }
                catalogo = (Get-TmxFeatureListPayload)
            }
        }

        @{ jobId = $jobId }
    }

    # --- correcoes -----------------------------------------------------------

    Register-TmxBridgeAction -Name 'fixes.list' -Handler {
        param($payload)
        @{
            correcoes = @(Get-TmxFixCatalog | ForEach-Object {
                @{
                    id             = "$($_.id)"
                    nome           = "$($_.nome)"
                    descricao      = "$($_.descricao)"
                    aviso          = @(@($_.aviso) | ForEach-Object { "$_" })
                    requerSessao   = [bool]$_.requerSessao
                    opcaoAgressiva = [bool]$_.opcaoAgressiva
                }
            })
        }
    }

    Register-TmxBridgeAction -Name 'fixes.run' -Handler {
        param($payload)

        $id = "$($payload.id)"
        if (-not $id) { throw 'id obrigatorio' }
        $agressivo = [bool]$payload.aggressive

        $fix = @(Get-TmxFixCatalog | Where-Object { "$($_.id)" -ieq $id }) | Select-Object -First 1
        if ($null -eq $fix) { throw "correcao desconhecida: $id" }

        Assert-TmxFixTestMode -Id $id
        if ($fix.requerSessao) { Assert-TmxFeatureSession }

        $jobId = Start-TmxJob -Name 'fixes.run' -Payload @{ id = "$($fix.id)"; aggressive = $agressivo } -Handler {
            param($p)
            Send-TmxJobProgress -Pct 2 -Status "Executando $($p.id)..."
            $r = Invoke-TmxFixById -Id "$($p.id)" -Aggressive:([bool]$p.aggressive)
            ConvertTo-TmxFixPayload -Resultado $r -Id "$($p.id)"
        }

        @{ jobId = $jobId }
    }

    # --- paineis -------------------------------------------------------------

    Register-TmxBridgeAction -Name 'panels.list' -Handler {
        param($payload)
        @{ paineis = @(Get-TmxPanelCatalog | ForEach-Object { @{ id = "$($_.id)"; nome = "$($_.nome)"; comando = "$($_.comando)" } }) }
    }

    Register-TmxBridgeAction -Name 'panels.open' -Handler {
        param($payload)
        $r = Open-TmxPanel -Id "$($payload.id)"
        @{ ok = $true; id = "$($r.id)"; nome = "$($r.nome)"; simulado = [bool]$r.simulado }
    }

    # --- DNS -----------------------------------------------------------------

    Register-TmxBridgeAction -Name 'dns.list' -Handler {
        param($payload)
        Get-TmxDnsListPayload
    }

    Register-TmxBridgeAction -Name 'dns.apply' -Handler {
        param($payload)

        $provedor = "$($payload.provedor)"
        if (-not $provedor) { throw 'provedor obrigatorio' }

        Assert-TmxDnsTestMode
        Assert-TmxFeatureSession

        if ($provedor -cne 'dhcp') {
            $conhecido = @(Get-TmxDnsCatalog | Where-Object { "$($_.id)" -ieq $provedor }) | Select-Object -First 1
            if ($null -eq $conhecido) { throw "provedor de DNS desconhecido: $provedor" }
        }

        $jobId = Start-TmxJob -Name 'dns.apply' -Payload @{ provedor = $provedor } -Handler {
            param($p)
            Send-TmxJobProgress -Pct 20 -Status "Aplicando DNS: $($p.provedor)..."
            $tweak = New-TmxDnsTweak -Provedor "$($p.provedor)"
            $r = Invoke-TmxTransientTweak -Tweak $tweak
            Send-TmxJobProgress -Pct 85 -Status 'Relendo os adaptadores...'
            @{
                provedor  = "$($p.provedor)"
                resultado = (ConvertTo-TmxTransientResult -Resultado $r)
                dns       = (Get-TmxDnsListPayload)
            }
        }

        @{ jobId = $jobId }
    }

    Register-TmxBridgeAction -Name 'dns.benchmark' -Async -Handler {
        param($payload)
        Send-TmxJobProgress -Pct 2 -Status 'Medindo a latencia dos provedores...'
        $r = @(Get-TmxDnsBenchmark)
        @{
            itens = @($r | ForEach-Object {
                @{
                    id       = "$($_.id)"
                    nome     = "$($_.nome)"
                    servidor = "$($_.servidor)"
                    medioMs  = $_.medioMs
                    falhas   = [int]$_.falhas
                    amostras = [int]$_.amostras
                }
            })
        }
    }
}
