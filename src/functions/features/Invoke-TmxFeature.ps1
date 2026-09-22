# functions/features/Invoke-TmxFeature.ps1
# Recursos do Windows (DISM) da aba "Configurar".
#
# Ideia central: um recurso opcional NAO e um caminho paralelo de aplicacao.
# Cada entrada de src/config/feature.json vira um TWEAK TRANSITORIO (mesmo
# schema do catalogo de producao, mas montado em memoria) e e aplicado pelo
# mesmo Invoke-TmxPlan. Assim o registro cai no state.json da sessao e o
# Undo-TweakMaxing reverte um recurso exatamente como reverte um tweak.
#
# Ids REC-0NN sao estaveis: saem da ORDEM em que as entradas elegiveis
# aparecem no feature.json. Reordenar o JSON muda id - por isso o conversor
# da Task 6 preserva a ordem de origem.

$script:TmxFeatureTestePath  = 'HKCU:\Software\TweakMaxing_Tests\Features'
$script:TmxFeatureBcdOpcao   = 'bootmenupolicy'
$script:TmxRegBackupTarefa   = 'AutoRegBackup'
$script:TmxRegBackupChave    = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Configuration Manager'

# Entradas de feature.json que NAO vem de DISM: a acao real e uma funcao
# nomeada com o trio Set-/Undo-/Test-Tmx<X> definido mais abaixo neste arquivo.
# 'desligarWinutilId' marca a entrada gemea "- Disable" que e absorvida pelo
# toggleDesligar (o WinUtil trata as duas como botoes independentes).
$script:TmxFeatureFuncoes = @{
    'WPFFeatureRegBackup' = @{
        funcao        = 'Set-TmxRegBackupTask'
        ligar         = @{ modo = 'ligar' }
        desligar      = @{ modo = 'desligar' }
        estadoLigado  = 'presente'
        nome          = 'Backup diario do registro (00:30)'
        descricao     = 'Reativa o backup automatico do registro que a Microsoft desligou no Windows 10 1803: grava EnablePeriodicBackup e cria a tarefa agendada AutoRegBackup.'
        porque        = 'Com EnablePeriodicBackup desligado a pasta RegBack fica vazia e a recuperacao offline do registro perde a copia que ela espera encontrar.'
        evidencia     = 'Verificavel na propria maquina: a chave Configuration Manager passa a ter EnablePeriodicBackup=1 e a tarefa AutoRegBackup aparece no Agendador de Tarefas.'
        requerReboot  = $false
    }
    'WPFFeatureEnableLegacyRecovery' = @{
        funcao            = 'Set-TmxLegacyRecovery'
        ligar             = @{ modo = 'legacy' }
        desligar          = @{ modo = 'standard' }
        estadoLigado      = 'legacy'
        desligarWinutilId = 'WPFFeatureDisableLegacyRecovery'
        nome              = 'Menu de recuperacao legado (F8)'
        descricao         = 'Volta a tela de Opcoes Avancadas de Inicializacao acessivel pelo F8 durante o boot (bcdedit /set bootmenupolicy legacy).'
        porque            = 'Com bootmenupolicy standard o F8 nao abre nada e o unico caminho para o modo de seguranca passa por um Windows que ainda inicia.'
        evidencia         = 'bcdedit /enum {current} mostra o valor de bootmenupolicy antes e depois; o valor anterior fica no state.json para reversao.'
        requerReboot      = $true
    }
}

# ---------------------------------------------------------------------------
# Leitura do feature.json
# ---------------------------------------------------------------------------

function Get-TmxFeatureConfigDir {
    <#
    .SYNOPSIS
        Pasta src/config. Nunca usa $PSScriptRoot: dentro da runspace do pool
        as funcoes chegam como texto e $PSScriptRoot e $null.
    #>
    [CmdletBinding()]
    param()

    if ($null -ne $sync -and $sync.webRoot) {
        $dir = Join-Path (Split-Path $sync.webRoot -Parent) 'config'
        if (Test-Path -LiteralPath $dir) { return $dir }
    }
    $null
}

function Get-TmxFeatureConfigEntries {
    <#
    .SYNOPSIS
        As entradas cruas de src/config/feature.json ($sync.configs quando ja
        carregado, senao o arquivo do disco), na ordem de origem.
    #>
    [CmdletBinding()]
    param([string] $Path)

    if (-not $Path) {
        $cfg = $null
        if ($null -ne $sync) { $cfg = $sync.configs }
        # ContainsKey: $cfg.feature numa hashtable sem a chave devolve $null sem erro,
        # mas com StrictMode ligado quebraria; a checagem explicita serve aos dois.
        if ($null -ne $cfg -and $cfg -is [System.Collections.IDictionary] -and $cfg.Contains('feature')) {
            $doc = $cfg['feature']
            if ($null -ne $doc) { return @($doc.recursos | Where-Object { $_ }) }
        }
        $dir = Get-TmxFeatureConfigDir
        if ($dir) { $Path = Join-Path $dir 'feature.json' }
    }

    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) {
        throw "feature.json nao encontrado (procurado em: '$Path')"
    }
    $doc = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    @($doc.recursos | Where-Object { $_ })
}

# ---------------------------------------------------------------------------
# Conversao para tweak transitorio
# ---------------------------------------------------------------------------

function New-TmxFeatureTweak {
    <#
    .SYNOPSIS
        Monta o tweak transitorio de UM recurso.
    .DESCRIPTION
        O objeto sai com o mesmo schema do catalogo de producao (passa por
        Test-TmxCatalog com as funcoes carregadas) mais quatro campos extras
        que so a aba Configurar le: winutilId, recursos[], estadoLigado e
        parcialNota.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Id,
        [Parameter(Mandatory)] [string] $Nome,
        [string]   $Descricao,
        [string]   $WinutilId,
        [string[]] $Recursos = @(),
        $Funcao,
        [string]   $Porque,
        [string]   $Evidencia,
        [string]   $Reversivel = 'total',
        [bool]     $RequerReboot = $true,
        [string]   $ParcialNota,
        [string]   $EstadoLigado,
        $Acoes,
        $ToggleDesligar
    )

    if ($null -eq $Acoes) {
        $Acoes = @(foreach ($n in $Recursos) { @{ tipo = 'feature'; nome = "$n"; estado = 'Enabled' } })
    }
    if ($null -eq $ToggleDesligar) {
        # Ordem inversa ao ligar: um recurso que depende de outro (WSL sobre
        # VirtualMachinePlatform) tem que sair de cima para baixo.
        $inverso = @($Recursos)
        [array]::Reverse($inverso)
        $ToggleDesligar = @(foreach ($n in $inverso) { @{ tipo = 'feature'; nome = "$n"; estado = 'Disabled' } })
    }

    [pscustomobject]@{
        id                       = $Id
        nome                     = $Nome
        descricao                = "$Descricao"
        categoria                = 'Recursos'
        tier                     = 'MEDIDO'
        risco                    = 'baixo'
        presets                  = @()
        controle                 = 'toggle'
        opcoes                   = @()
        grupo                    = $null
        reversivel               = $Reversivel
        requerReboot             = $RequerReboot
        requerConsentimentoExtra = $false
        consentimento            = @{ titulo = $null; tradeoff = $null; frase = $null }
        condicoes                = @{ requer = @(); bloqueiaSe = @() }
        porque                   = "$Porque"
        evidencia                = "$Evidencia"
        folclore                 = $null
        instrucoes               = $null
        posAplicar               = $null
        acoes                    = @($Acoes)
        toggleDesligar           = @($ToggleDesligar)

        # extras da aba Configurar (ignorados pelo Engine)
        winutilId                = "$WinutilId"
        recursos                 = @($Recursos)
        funcao                   = $Funcao
        estadoLigado             = $EstadoLigado
        parcialNota              = $ParcialNota
    }
}

function Get-TmxFeatureTestTweak {
    <#
    .SYNOPSIS
        REC-TST: recurso sintetico do modo de teste. Nao chama DISM - grava um
        DWord em HKCU:\Software\TweakMaxing_Tests\Features.
    #>
    [CmdletBinding()]
    param()

    New-TmxFeatureTweak -Id 'REC-TST' -Nome 'Teste - recurso sintetico' `
        -Descricao 'Recurso de teste: grava Recurso=1 na chave de testes em vez de chamar o DISM.' `
        -WinutilId 'TMXFeatureTeste' -RequerReboot $false `
        -Porque 'Exercita o caminho recurso -> tweak transitorio -> Invoke-TmxPlan -> state.json sem tocar em nenhum recurso opcional real.' `
        -Evidencia 'O efeito e lido de volta da propria chave de testes: nao ha promessa de desempenho.' `
        -Acoes @(@{ tipo = 'registry'; path = $script:TmxFeatureTestePath; name = 'Recurso'; value = 1; valueType = 'DWord' }) `
        -ToggleDesligar @(@{ tipo = 'registry'; path = $script:TmxFeatureTestePath; name = 'Recurso'; value = 0; valueType = 'DWord' })
}

function Get-TmxFeatureCatalog {
    <#
    .SYNOPSIS
        Os recursos do Windows como tweaks transitorios, em ordem de arquivo.
    .PARAMETER Path
        feature.json alternativo (testes). Sem ele: $sync.configs ou src/config.
    .PARAMETER IncluirTeste
        Acrescenta REC-TST. O padrao segue $sync.testMode.
    .OUTPUTS
        Array de tweaks (ver New-TmxFeatureTweak).
    #>
    [CmdletBinding()]
    param(
        [string] $Path,
        [nullable[bool]] $IncluirTeste
    )

    if ($null -eq $IncluirTeste) {
        $IncluirTeste = [bool]($null -ne $sync -and $sync.testMode)
    }

    $entradas = @(Get-TmxFeatureConfigEntries -Path $Path)

    # ids das entradas "- Disable" absorvidas por um toggleDesligar.
    $absorvidos = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($chave in @($script:TmxFeatureFuncoes.Keys)) {
        $d = "$($script:TmxFeatureFuncoes[$chave].desligarWinutilId)"
        if ($d) { [void]$absorvidos.Add($d) }
    }

    $lista = New-Object 'System.Collections.Generic.List[object]'
    $n = 0

    foreach ($e in $entradas) {
        $wid = "$($e.id)"
        if ($absorvidos.Contains($wid)) { continue }

        $recursos = @(@($e.feature) | Where-Object { "$_" })
        $custom   = $script:TmxFeatureFuncoes[$wid]

        if ($null -eq $custom -and ($recursos.Count -eq 0 -or "$($e.controle)" -ne 'toggle')) { continue }

        $n++
        $id = 'REC-{0:D3}' -f $n

        if ($null -ne $custom) {
            $fn = "$($custom.funcao)"
            $lista.Add((New-TmxFeatureTweak -Id $id -Nome "$($custom.nome)" -Descricao "$($custom.descricao)" `
                -WinutilId $wid -Funcao $fn -EstadoLigado "$($custom.estadoLigado)" `
                -Porque "$($custom.porque)" -Evidencia "$($custom.evidencia)" `
                -RequerReboot ([bool]$custom.requerReboot) `
                -Acoes @(@{ tipo = 'funcao'; nome = $fn; parametros = $custom.ligar }) `
                -ToggleDesligar @(@{ tipo = 'funcao'; nome = $fn; parametros = $custom.desligar })))
            continue
        }

        # Entradas cujo InvokeScript do WinUtil tinha passos ALEM do DISM: o
        # TweakMaxing aplica so a parte DISM, entao a reversao e parcial e a
        # evidencia tem que dizer isso em voz alta.
        $parcial = $null
        $rev     = 'total'
        if ($wid -ieq 'WPFFeaturenfs') {
            $parcial = 'O WinUtil tambem ajusta AnonymousUID/AnonymousGID e roda nfsadmin client config; o TweakMaxing liga apenas os recursos do DISM e deixa a configuracao do cliente NFS com o padrao do Windows.'
            $rev     = 'parcial'
        }

        $nome = ConvertTo-TmxFeatureNomePtBr -Nome "$($e.nome)"
        $desc = ConvertTo-TmxFeatureDescricaoPtBr -WinutilId $wid -Padrao "$($e.descricao)"
        $lista.Add((New-TmxFeatureTweak -Id $id -Nome $nome -Descricao $desc `
            -WinutilId $wid -Recursos $recursos -Reversivel $rev -ParcialNota $parcial `
            -Porque "Liga os recursos opcionais do Windows: $($recursos -join ', ')." `
            -Evidencia "Estado lido do proprio Windows por Get-WindowsOptionalFeature; o valor anterior de cada recurso vai para o state.json antes da mudanca.$(if ($parcial) { ' ' + $parcial })"))
    }

    if ($IncluirTeste) { $lista.Add((Get-TmxFeatureTestTweak)) }

    # .ToArray(): @() sobre List generica vazia falha no PS 5.1
    $lista.ToArray()
}

function ConvertTo-TmxFeatureNomePtBr {
    <#
    .SYNOPSIS
        Rotulo pt-BR do recurso. O feature.json veio do WinUtil em ingles e com
        o sufixo "- Enable", que num interruptor nao faz sentido.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string] $Nome)

    $limpo = ($Nome -replace '\s*-\s*(Enable|Disable)\s*$', '').Trim()
    switch -Regex ($limpo) {
        '^\.NET Framework'          { return '.NET Framework (versoes 2, 3 e 4)' }
        '^Hyper-V'                  { return 'Hyper-V' }
        '^Legacy Media Components'  { return 'Componentes de midia legados (WMP, DirectPlay)' }
        '^Windows Subsystem for'    { return 'Subsistema do Windows para Linux (WSL)' }
        '^Network File System'      { return 'Sistema de arquivos de rede (NFS)' }
        '^Windows Sandbox'          { return 'Windows Sandbox' }
        default                     { return $limpo }
    }
}

function ConvertTo-TmxFeatureDescricaoPtBr {
    <#
    .SYNOPSIS
        Descricao pt-BR do recurso, com a do feature.json como reserva.
    .NOTES
        As descricoes do feature.json vieram do WinUtil em ingles e o arquivo
        e gerado pelo conversor da Task 6 - traduzir la seria perdido na
        proxima geracao. A traducao mora aqui, indexada pelo id de origem, e
        um id desconhecido cai no texto original em vez de ficar sem nada.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $WinutilId,
        [string] $Padrao
    )

    switch ($WinutilId) {
        'WPFFeaturesdotnet'     { return 'Plataforma de desenvolvimento da Microsoft. Alguns programas antigos so rodam com as versoes 2, 3 e 4 do .NET Framework instaladas.' }
        'WPFFeatureshyperv'     { return 'Virtualizacao da propria Microsoft: cria e gerencia maquinas virtuais. Ocupa o hipervisor da maquina e pode conflitar com outros virtualizadores.' }
        'WPFFeatureslegacymedia' { return 'Componentes de midia de versoes antigas do Windows: Windows Media Player, DirectPlay e o pacote de componentes legados.' }
        'WPFFeaturewsl'         { return 'Roda programas de Linux direto no Windows, sem maquina virtual separada nem dual boot. Liga tambem a Plataforma de Maquina Virtual.' }
        'WPFFeaturenfs'         { return 'Cliente do sistema de arquivos de rede NFS, usado para montar pastas compartilhadas por servidores Unix e Linux.' }
        'WPFFeaturesSandbox'    { return 'Ambiente descartavel e isolado para abrir um programa suspeito sem risco para o sistema: tudo some quando a janela fecha.' }
        default                 { return "$Padrao" }
    }
}

# ---------------------------------------------------------------------------
# Estado atual
# ---------------------------------------------------------------------------

function Get-TmxFeatureState {
    <#
    .SYNOPSIS
        'Enabled' / 'Disabled' de UM recurso opcional do Windows.
    .OUTPUTS
        'Enabled', 'Disabled' ou 'desconhecido' (recurso inexistente nesta edicao).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Nome)

    try {
        Get-TmxWindowsFeature -Nome $Nome
    } catch {
        Write-TmxLog -Level WARN -Message "Recurso '$Nome' nao pode ser lido: $($_.Exception.Message)"
        'desconhecido'
    }
}

function Get-TmxFeatureCurrentState {
    <#
    .SYNOPSIS
        Estado do TWEAK inteiro: ligado so quando todas as partes estao ligadas.
    .OUTPUTS
        'Enabled', 'Disabled' ou 'desconhecido'.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Tweak)

    $recursos = @($Tweak.recursos)
    if ($recursos.Count -gt 0) {
        $estados = @(foreach ($n in $recursos) { Get-TmxFeatureState -Nome "$n" })
        if (@($estados | Where-Object { $_ -eq 'desconhecido' }).Count -gt 0) { return 'desconhecido' }
        if (@($estados | Where-Object { $_ -ne 'Enabled' }).Count -gt 0) { return 'Disabled' }
        return 'Enabled'
    }

    $fn = "$($Tweak.funcao)"
    if ($fn) {
        $teste = $fn -replace '^Set-', 'Test-'
        if (Get-Command -Name $teste -CommandType Function -ErrorAction SilentlyContinue) {
            try {
                $r = & $teste -Tweak $Tweak -Profile $null
                $atual = "$(Get-TmxActionProp -Action $r -Nome 'atual' -Padrao '')"
                if (-not $atual) { return 'desconhecido' }
                if ($atual -ieq "$($Tweak.estadoLigado)") { return 'Enabled' }
                return 'Disabled'
            } catch {
                Write-TmxLog -Level WARN -Message "Estado de '$($Tweak.id)' nao pode ser lido: $($_.Exception.Message)"
                return 'desconhecido'
            }
        }
        return 'desconhecido'
    }

    # REC-TST e qualquer outro tweak sem DISM/funcao: pergunta ao Engine.
    try {
        $r = Test-TmxTweakApplied -Tweak $Tweak -Profile @{}
        if ($r.aplicado -eq $true)  { return 'Enabled' }
        if ($r.aplicado -eq $false) { return 'Disabled' }
        'desconhecido'
    } catch {
        'desconhecido'
    }
}

# ---------------------------------------------------------------------------
# Trio Set-/Test-/Undo- : menu de recuperacao legado (F8)
# ---------------------------------------------------------------------------

function Get-TmxLegacyRecoveryModo {
    param($Parametros)
    $m = "$(Get-TmxActionProp -Action $Parametros -Nome 'modo' -Padrao '')"
    if ($m -cnotin @('legacy', 'standard')) { throw "parametro 'modo' invalido em Set-TmxLegacyRecovery: '$m' (esperado legacy ou standard)" }
    $m
}

function Test-TmxLegacyRecovery {
    <#
    .SYNOPSIS
        Valor atual de bootmenupolicy em {current}.
    .NOTES
        'aplicado' fica $null de proposito: a verificacao do Engine nao recebe
        os 'parametros' da acao, entao nao ha como saber se o alvo era legacy
        ou standard. Quem precisa do estado para a interface le 'atual' (e o
        que Get-TmxFeatureCurrentState faz, comparando com estadoLigado).
    #>
    [CmdletBinding()]
    param($Tweak, $Profile)

    try {
        $atual = Get-TmxBcdValue -Opcao $script:TmxFeatureBcdOpcao
    } catch {
        return [pscustomobject]@{ aplicado = $null; atual = $null; esperado = 'legacy/standard'; detalhe = "bcdedit nao pode ser lido: $($_.Exception.Message)" }
    }
    # Sem o valor no BCD o Windows se comporta como 'standard' desde o 8.
    if (-not $atual) { $atual = 'standard' }
    [pscustomobject]@{
        aplicado = $null
        atual    = "$atual"
        esperado = 'legacy/standard'
        detalhe  = "bootmenupolicy = $atual"
    }
}

function Set-TmxLegacyRecovery {
    <#
    .SYNOPSIS
        bcdedit /set {current} bootmenupolicy <legacy|standard>, guardando o
        valor anterior para reversao.
    #>
    [CmdletBinding()]
    param($Tweak, $Profile, $Parametros)

    $modo  = Get-TmxLegacyRecoveryModo -Parametros $Parametros
    $antes = Get-TmxBcdValue -Opcao $script:TmxFeatureBcdOpcao
    if (-not $antes) { $antes = 'standard' }

    if ("$antes" -ieq $modo) {
        return [pscustomobject]@{ ok = $true; naoAplicavel = $true; detalhe = "bootmenupolicy ja esta $antes" }
    }

    Backup-TmxBcd | Out-Null

    $rec = New-TmxCmdletRecord -TweakId "$($Tweak.id)" -Funcao 'Set-TmxLegacyRecovery' `
            -Alvo "BCD {current} $($script:TmxFeatureBcdOpcao)" `
            -Estado @{ anterior = "$antes" } -ValorAnterior "$antes" -ValorNovo $modo

    $r = Invoke-TmxBcdedit @('/set', '{current}', $script:TmxFeatureBcdOpcao, $modo)
    $ok = ($r.codigo -eq 0)
    Complete-TmxStateRecord -Record $rec -Ok $ok -Erro $(if (-not $ok) { "bcdedit: $($r.saida)" }) | Out-Null

    [pscustomobject]@{
        ok      = $ok
        detalhe = $(if ($ok) { "bootmenupolicy: $antes -> $modo" } else { "bcdedit falhou ($($r.codigo)): $($r.saida)" })
        registro = $rec
    }
}

function Undo-TmxLegacyRecovery {
    [CmdletBinding()]
    param($Estado)

    if (-not $Estado -or -not "$($Estado.anterior)") { throw 'sem estado: nao da para saber qual era o bootmenupolicy' }
    $anterior = "$($Estado.anterior)"
    $r = Invoke-TmxBcdedit @('/set', '{current}', $script:TmxFeatureBcdOpcao, $anterior)
    if ($r.codigo -ne 0) { throw "bcdedit falhou ($($r.codigo)): $($r.saida)" }
    "bootmenupolicy restaurado para $anterior"
}

# ---------------------------------------------------------------------------
# Trio Set-/Test-/Undo- : backup diario do registro
# ---------------------------------------------------------------------------

function Get-TmxRegBackupModo {
    param($Parametros)
    $m = "$(Get-TmxActionProp -Action $Parametros -Nome 'modo' -Padrao 'ligar')"
    if ($m -cnotin @('ligar', 'desligar')) { throw "parametro 'modo' invalido em Set-TmxRegBackupTask: '$m'" }
    $m
}

function Get-TmxRegBackupChave {
    param($Parametros)
    $p = "$(Get-TmxActionProp -Action $Parametros -Nome 'caminhoRegistro' -Padrao '')"
    if ($p) { return $p }
    $script:TmxRegBackupChave
}

function Test-TmxRegBackupTask {
    <#
    .SYNOPSIS
        'presente' quando a tarefa AutoRegBackup existe, 'ausente' quando nao.
    #>
    [CmdletBinding()]
    param($Tweak, $Profile)

    try {
        $existe = Test-TmxScheduledTaskExists -Nome $script:TmxRegBackupTarefa
    } catch {
        return [pscustomobject]@{ aplicado = $null; atual = $null; esperado = 'presente'; detalhe = "agendador nao pode ser lido: $($_.Exception.Message)" }
    }
    [pscustomobject]@{
        aplicado = $null
        atual    = $(if ($existe) { 'presente' } else { 'ausente' })
        esperado = 'presente/ausente'
        detalhe  = "tarefa $($script:TmxRegBackupTarefa): $(if ($existe) { 'presente' } else { 'ausente' })"
    }
}

function Set-TmxRegBackupTask {
    <#
    .SYNOPSIS
        Liga/desliga o backup periodico do registro: dois valores em
        Configuration Manager (via Set-TmxRegistry, que registra o anterior) e
        a tarefa diaria AutoRegBackup.
    #>
    [CmdletBinding()]
    param($Tweak, $Profile, $Parametros)

    $modo    = Get-TmxRegBackupModo -Parametros $Parametros
    $chave   = Get-TmxRegBackupChave -Parametros $Parametros
    $tweakId = "$($Tweak.id)"
    $existia = Test-TmxScheduledTaskExists -Nome $script:TmxRegBackupTarefa

    $registros = New-Object 'System.Collections.Generic.List[object]'
    $partes    = New-Object 'System.Collections.Generic.List[string]'

    $valor = if ($modo -eq 'ligar') { 1 } else { 0 }
    foreach ($par in @(@{ nome = 'EnablePeriodicBackup'; valor = $valor }, @{ nome = 'BackupCount'; valor = $(if ($modo -eq 'ligar') { 2 } else { 0 }) })) {
        $rec = Set-TmxRegistry -Path $chave -Name $par.nome -Value ([int]$par.valor) -Type 'DWord' -TweakId $tweakId -PassThru
        if ($rec) { $registros.Add($rec) }
        $partes.Add("$($par.nome)=$($par.valor)")
    }

    $recTarefa = New-TmxCmdletRecord -TweakId $tweakId -Funcao 'Set-TmxRegBackupTask' `
                    -Alvo "tarefa agendada $($script:TmxRegBackupTarefa)" `
                    -Estado @{ tarefa = $script:TmxRegBackupTarefa; existiaAntes = [bool]$existia } `
                    -ValorAnterior $(if ($existia) { 'presente' } else { 'ausente' }) `
                    -ValorNovo $(if ($modo -eq 'ligar') { 'presente' } else { 'ausente' })
    $registros.Add($recTarefa)

    try {
        if ($modo -eq 'ligar') {
            Register-TmxScheduledTaskWrapper -Nome $script:TmxRegBackupTarefa -Executar 'schtasks' `
                -Argumentos @('/run', '/i', '/tn', '"\Microsoft\Windows\Registry\RegIdleBackup"') `
                -Hora '00:30' -Descricao 'Backup periodico do registro (TweakMaxing)' -Usuario 'System' | Out-Null
            $partes.Add("tarefa $($script:TmxRegBackupTarefa) criada")
        } elseif ($existia) {
            Unregister-TmxScheduledTaskWrapper -Nome $script:TmxRegBackupTarefa | Out-Null
            $partes.Add("tarefa $($script:TmxRegBackupTarefa) removida")
        } else {
            $partes.Add("tarefa $($script:TmxRegBackupTarefa) ja nao existia")
        }
        Complete-TmxStateRecord -Record $recTarefa -Ok $true | Out-Null
        [pscustomobject]@{ ok = $true; detalhe = ($partes.ToArray() -join '; '); registros = $registros.ToArray() }
    } catch {
        Complete-TmxStateRecord -Record $recTarefa -Ok $false -Erro $_.Exception.Message | Out-Null
        [pscustomobject]@{ ok = $false; detalhe = $_.Exception.Message; registros = $registros.ToArray() }
    }
}

function Undo-TmxRegBackupTask {
    [CmdletBinding()]
    param($Estado)

    if (-not $Estado) { throw 'sem estado: nao da para saber se a tarefa existia antes' }
    $nome = "$($Estado.tarefa)"
    if (-not $nome) { $nome = $script:TmxRegBackupTarefa }

    $existiaAntes = [bool]$Estado.existiaAntes
    $existeAgora  = Test-TmxScheduledTaskExists -Nome $nome

    if ($existiaAntes -eq $existeAgora) { return "tarefa $nome ja esta como antes ($(if ($existeAgora) { 'presente' } else { 'ausente' }))" }
    if ($existiaAntes) {
        Register-TmxScheduledTaskWrapper -Nome $nome -Executar 'schtasks' `
            -Argumentos @('/run', '/i', '/tn', '"\Microsoft\Windows\Registry\RegIdleBackup"') `
            -Hora '00:30' -Descricao 'Backup periodico do registro (restaurado pelo TweakMaxing)' -Usuario 'System' | Out-Null
        return "tarefa $nome recriada"
    }
    Unregister-TmxScheduledTaskWrapper -Nome $nome | Out-Null
    "tarefa $nome removida"
}
