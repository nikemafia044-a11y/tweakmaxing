# functions/bridge/Actions.System.ps1
# Acoes da ponte para o item de menu "Sistema": configuracoes persistentes,
# hardware (Painel), limpeza, pontos de restauracao, verificacao de
# atualizacao do proprio app, manutencao de dados e exportar/importar
# selecao de aplicativos + os dois dialogos nativos genericos (shell.saveFile
# / shell.openFile).
#
# A logica de cada area mora em src/functions/system/*.ps1 (Settings,
# Hardware, OptimizationStatus, Cleanup, RestorePoints, AppUpdate,
# Maintenance); este arquivo so registra o nome da acao e faz a
# pre-validacao sincrona de payload antes de despachar (mesmo padrao de
# Actions.Tweaks.ps1/Actions.Updates.ps1: confirmacao e forma do payload sao
# conferidas ANTES de existir job, para o erro chegar na hora certa).
#
# apps.export/apps.import moram aqui (nao em Actions.Install.ps1) por pedido
# explicito da tarefa que criou este arquivo.

function Register-TmxSystemActions {
    <#
    .SYNOPSIS
        Registra settings.*, system.info, system.optimizationStatus,
        cleanup.*, restore.*, app.checkUpdate, app.clearCache, app.openLogs, app.paths,
        app.oldBackups, app.deleteOldBackups, apps.export, apps.import,
        shell.saveFile e shell.openFile.
    #>
    [CmdletBinding()]
    param()

    # -------------------------------------------------------------------
    # Configuracoes persistentes
    # -------------------------------------------------------------------

    Register-TmxBridgeAction -Name 'settings.get' -Handler {
        param($payload)
        Get-TmxSettings
    }

    Register-TmxBridgeAction -Name 'settings.set' -Handler {
        param($payload)
        Set-TmxSettings -Payload $payload
    }

    Register-TmxBridgeAction -Name 'settings.windowsName' -Handler {
        param($payload)
        @{ nome = (Get-TmxWindowsDisplayName) }
    }

    # -------------------------------------------------------------------
    # Painel: hardware e status de otimizacao
    # -------------------------------------------------------------------

    Register-TmxBridgeAction -Name 'system.info' -Async -Handler {
        param($payload)
        Send-TmxJobProgress -Pct 20 -Status 'Lendo hardware...'
        $info = Get-TmxSystemInfo
        Send-TmxJobProgress -Pct 95 -Status 'Concluido'
        $info
    }

    Register-TmxBridgeAction -Name 'system.optimizationStatus' -Async -Handler {
        param($payload)
        Get-TmxOptimizationStatus
    }

    # -------------------------------------------------------------------
    # Limpeza
    # -------------------------------------------------------------------

    Register-TmxBridgeAction -Name 'cleanup.scan' -Async -Handler {
        param($payload)
        Send-TmxJobProgress -Pct 30 -Status 'Medindo arquivos...'
        $r = Get-TmxCleanupScan
        Send-TmxJobProgress -Pct 95 -Status 'Concluido'
        $r
    }

    Register-TmxBridgeAction -Name 'cleanup.run' -Async -Handler {
        param($payload)
        $ids = @(@($payload.ids) | ForEach-Object { "$_" } | Where-Object { $_ })
        Send-TmxJobProgress -Pct 10 -Status 'Limpando...'
        $r = Invoke-TmxCleanupRun -Ids $ids
        Send-TmxJobProgress -Pct 95 -Status 'Concluido'
        $r
    }

    # -------------------------------------------------------------------
    # Pontos de restauracao
    # -------------------------------------------------------------------

    Register-TmxBridgeAction -Name 'restore.list' -Async -Handler {
        param($payload)
        @{ pontos = @(Get-TmxRestoreList) }
    }

    # Sincronas de registro (como plan.apply/updates.apply): o trabalho vai
    # para o pool, mas a forma do payload (sequencia, confirmado) e conferida
    # ANTES de existir job.
    Register-TmxBridgeAction -Name 'restore.create' -Handler {
        param($payload)
        $nome = $null
        if ($payload -and $payload.nome) { $nome = "$($payload.nome)" }

        $jobId = Start-TmxJob -Name 'restore.create' -Payload @{ nome = $nome } -Handler {
            param($p)
            Send-TmxJobProgress -Pct 20 -Status 'Criando o ponto de restauracao...'
            $r = New-TmxRestoreCreate -Nome "$($p.nome)"
            Send-TmxJobProgress -Pct 95 -Status 'Concluido'
            @{ resultado = $r; pontos = @(Get-TmxRestoreList) }
        }
        @{ jobId = $jobId }
    }

    Register-TmxBridgeAction -Name 'restore.delete' -Handler {
        param($payload)
        $sequencia = 0
        try { $sequencia = [int]$payload.sequencia } catch { throw 'sequencia invalida' }
        if ($sequencia -le 0) { throw 'sequencia obrigatoria' }

        $jobId = Start-TmxJob -Name 'restore.delete' -Payload @{ sequencia = $sequencia } -Handler {
            param($p)
            Send-TmxJobProgress -Pct 30 -Status "Excluindo o ponto $($p.sequencia)..."
            $r = Remove-TmxRestorePointById -Sequencia ([int]$p.sequencia)
            Send-TmxJobProgress -Pct 95 -Status 'Concluido'
            @{ resultado = $r; pontos = @(Get-TmxRestoreList) }
        }
        @{ jobId = $jobId }
    }

    Register-TmxBridgeAction -Name 'restore.restore' -Handler {
        param($payload)
        $sequencia = 0
        try { $sequencia = [int]$payload.sequencia } catch { throw 'sequencia invalida' }
        if ($sequencia -le 0) { throw 'sequencia obrigatoria' }
        if ($payload.confirmado -ne $true) { throw 'confirmacao pendente: restaurar o sistema exige confirmado:true' }

        $jobId = Start-TmxJob -Name 'restore.restore' -Payload @{ sequencia = $sequencia; confirmado = $true } -Handler {
            param($p)
            Send-TmxJobProgress -Pct 20 -Status "Iniciando a restauracao do ponto $($p.sequencia)..."
            $r = Invoke-TmxRestoreRestore -Sequencia ([int]$p.sequencia) -Confirmado ([bool]$p.confirmado)
            Send-TmxJobProgress -Pct 95 -Status 'Restauracao agendada; reinicie o computador para concluir'
            @{ resultado = $r }
        }
        @{ jobId = $jobId }
    }

    # -------------------------------------------------------------------
    # Atualizacao do proprio TweakMaxing e manutencao de dados
    # -------------------------------------------------------------------

    Register-TmxBridgeAction -Name 'app.checkUpdate' -Async -Handler {
        param($payload)
        Get-TmxAppUpdateStatus
    }

    Register-TmxBridgeAction -Name 'app.clearCache' -Async -Handler {
        param($payload)
        Invoke-TmxClearAppCache
    }

    Register-TmxBridgeAction -Name 'app.openLogs' -Handler {
        param($payload)
        Open-TmxLogsFolder
    }

    Register-TmxBridgeAction -Name 'app.paths' -Handler {
        param($payload)
        Get-TmxAppPaths
    }

    Register-TmxBridgeAction -Name 'app.oldBackups' -Async -Handler {
        param($payload)
        @{ pastas = @(Get-TmxOldBackupRuns) }
    }

    Register-TmxBridgeAction -Name 'app.deleteOldBackups' -Handler {
        param($payload)
        if ($payload.confirmado -ne $true) { throw 'confirmacao pendente: exclusao de backups antigos exige confirmado:true' }

        $jobId = Start-TmxJob -Name 'app.deleteOldBackups' -Payload @{} -Handler {
            param($p)
            Send-TmxJobProgress -Pct 30 -Status 'Excluindo backups antigos...'
            $r = Remove-TmxOldBackupRuns -Confirmado $true
            Send-TmxJobProgress -Pct 95 -Status 'Concluido'
            $r
        }
        @{ jobId = $jobId }
    }

    # -------------------------------------------------------------------
    # Exportar/importar a selecao de aplicativos
    # -------------------------------------------------------------------

    Register-TmxBridgeAction -Name 'apps.export' -Handler {
        param($payload)
        $idsPedidos = @(@($payload.ids) | ForEach-Object { "$_" } | Where-Object { $_ })
        $catalogo = Get-TmxAppCatalog

        $validos = New-Object 'System.Collections.Generic.List[string]'
        foreach ($id in $idsPedidos) {
            if (@($catalogo | Where-Object { "$($_.id)" -ieq $id }).Count -gt 0) { $validos.Add($id) }
        }

        @{ apps = @($validos.ToArray() | Select-Object -Unique); geradoEm = (Get-Date).ToString('o') }
    }

    Register-TmxBridgeAction -Name 'apps.import' -Handler {
        param($payload)
        $conteudo = "$($payload.conteudo)"
        if (-not $conteudo) { throw 'conteudo vazio' }

        $doc = $null
        try { $doc = $conteudo | ConvertFrom-Json -ErrorAction Stop } catch { throw 'arquivo de importacao invalido: JSON malformado' }

        $bruto = @()
        if ($doc -is [System.Array]) {
            $bruto = @($doc)
        } elseif ($doc -and ($doc.PSObject.Properties.Name -contains 'apps')) {
            $bruto = @($doc.apps)
        } else {
            throw 'arquivo de importacao invalido: esperado uma lista ou { apps: [...] }'
        }

        $idsPedidos = @($bruto | ForEach-Object { "$_" } | Where-Object { $_ } | Select-Object -Unique)

        $catalogo = Get-TmxAppCatalog
        $idsCatalogo = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        foreach ($a in $catalogo) { [void]$idsCatalogo.Add("$($a.id)") }

        $conhecidos = New-Object 'System.Collections.Generic.List[string]'
        $desconhecidos = New-Object 'System.Collections.Generic.List[string]'
        foreach ($id in $idsPedidos) {
            if ($idsCatalogo.Contains($id)) { $conhecidos.Add($id) } else { $desconhecidos.Add($id) }
        }

        @{ ids = $conhecidos.ToArray(); desconhecidos = $desconhecidos.ToArray() }
    }

    # -------------------------------------------------------------------
    # Dialogos nativos genericos (mesmo padrao de microwin.pickIso: nada
    # abre em modo de teste, o payload informa o caminho/conteudo simulado)
    # -------------------------------------------------------------------

    Register-TmxBridgeAction -Name 'shell.saveFile' -Handler {
        param($payload)
        $conteudo = "$($payload.conteudo)"
        $nomeSugerido = "$($payload.nomeSugerido)"
        if (-not $nomeSugerido) { $nomeSugerido = 'tweakmaxing-export.json' }

        if ($null -ne $sync -and $sync.testMode) {
            $simulado = "$($payload.simular)"
            if (-not $simulado) { return @{ caminho = $null; cancelado = $true; simulado = $true } }
            Set-Content -LiteralPath $simulado -Value $conteudo -Encoding UTF8 -WhatIf:$false
            return @{ caminho = $simulado; cancelado = $false; simulado = $true }
        }

        $caminho = Show-TmxSaveFileDialog -NomeSugerido $nomeSugerido `
            -Filtro 'JSON (*.json)|*.json|Todos os arquivos (*.*)|*.*' -Titulo 'Salvar arquivo'
        if (-not $caminho) { return @{ caminho = $null; cancelado = $true; simulado = $false } }

        Set-Content -LiteralPath $caminho -Value $conteudo -Encoding UTF8 -WhatIf:$false
        @{ caminho = $caminho; cancelado = $false; simulado = $false }
    }

    Register-TmxBridgeAction -Name 'shell.openFile' -Handler {
        param($payload)

        if ($null -ne $sync -and $sync.testMode) {
            $simuladoCaminho  = "$($payload.simularCaminho)"
            $simuladoConteudo = "$($payload.simularConteudo)"
            if (-not $simuladoCaminho) { return @{ caminho = $null; conteudo = $null; cancelado = $true; simulado = $true } }
            return @{ caminho = $simuladoCaminho; conteudo = $simuladoConteudo; cancelado = $false; simulado = $true }
        }

        $filtro = "$($payload.filtro)"
        if (-not $filtro) { $filtro = 'Todos os arquivos (*.*)|*.*' }

        $caminho = Show-TmxOpenFileDialog -Filtro $filtro -Titulo 'Escolher arquivo'
        if (-not $caminho) { return @{ caminho = $null; conteudo = $null; cancelado = $true; simulado = $false } }

        $conteudo = $null
        try { $conteudo = Get-Content -LiteralPath $caminho -Raw -Encoding UTF8 }
        catch { throw "nao foi possivel ler o arquivo escolhido: $($_.Exception.Message)" }

        @{ caminho = $caminho; conteudo = $conteudo; cancelado = $false; simulado = $false }
    }
}
