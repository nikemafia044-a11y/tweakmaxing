# functions/microwin/Invoke-TmxMicroWinBuild.ps1
# O build do MicroWin: ISO de origem -> ISO enxuta, passo a passo.
#
# Ordem fixa (e a ordem que os testes conferem):
#   montar ISO -> copiar arvore -> desmontar ISO -> (esd -> wim) ->
#   montar imagem -> remover appx -> remover pacotes -> autounattend ->
#   desmontar gravando -> oscdimg -> conferir o arquivo.
#
# Duas garantias que nao se negociam:
#   1. a ISO de origem NUNCA e alterada (montagem somente-leitura, trabalho
#      sempre na copia);
#   2. qualquer falha com a imagem montada termina em Dismount -Discard. Sem
#      isso a montagem fica pendurada no DISM e a proxima tentativa nem
#      comeca ("a imagem ja esta montada em outro diretorio").
#
# A pasta de trabalho NAO e apagada no erro: e o unico lugar onde da para
# entender o que aconteceu. A interface mostra o caminho dela no modal.

function New-TmxMicroWinStep {
    <#
    .SYNOPSIS
        Um item de 'passos[]': { nome, ok, detalhe }.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Nome,
        [bool] $Ok = $true,
        [string] $Detalhe = ''
    )
    [pscustomobject]@{ nome = "$Nome"; ok = [bool]$Ok; detalhe = "$Detalhe" }
}

function Get-TmxMicroWinWorkRoot {
    <#
    .SYNOPSIS
        %LOCALAPPDATA%\TweakMaxing\microwin (ou TWEAKMAXING_HOME\microwin nos testes).
    #>
    [CmdletBinding()]
    param()
    Join-Path (Get-TmxHomePath) 'microwin'
}

function New-TmxMicroWinWorkDir {
    <#
    .SYNOPSIS
        Cria <raiz>\<yyyyMMdd-HHmmss>\ com contents, mount e scratch.
    .OUTPUTS
        [pscustomobject] @{ raiz; contents; mount; scratch }
    #>
    [CmdletBinding()]
    param()

    $raiz = Join-Path (Get-TmxMicroWinWorkRoot) ('{0:yyyyMMdd-HHmmss}' -f (Get-Date))
    $pastas = [pscustomobject]@{
        raiz     = $raiz
        contents = (Join-Path $raiz 'contents')
        mount    = (Join-Path $raiz 'mount')
        scratch  = (Join-Path $raiz 'scratch')
    }
    foreach ($p in @($pastas.raiz, $pastas.contents, $pastas.mount, $pastas.scratch)) {
        New-Item -ItemType Directory -Path $p -Force | Out-Null
    }
    $pastas
}

function Clear-TmxMicroWinWorkDirs {
    <#
    .SYNOPSIS
        Apaga pastas de trabalho antigas do MicroWin.
    .PARAMETER ManterUltimas
        Quantas pastas mais recentes preservar (0 = nenhuma).
    .OUTPUTS
        @{ ok; pasta; removidas; mantidas; erros[] }
    .NOTES
        Cada build deixa para tras uma copia da ISO inteira (varios GB) quando
        falha. Antes de apagar, qualquer autounattend.xml que tenha escapado e
        zerado por Remove-TmxUnattendFile - um Remove-Item recursivo sozinho
        deixaria a senha no disco.

        Os nomes das pastas sao yyyyMMdd-HHmmss, entao ordenar por nome
        decrescente ja e ordenar da mais nova para a mais velha.
    #>
    [CmdletBinding()]
    param([int] $ManterUltimas = 0)

    $raiz = Get-TmxMicroWinWorkRoot
    $erros = New-Object 'System.Collections.Generic.List[string]'

    if (-not (Test-Path -LiteralPath $raiz -PathType Container)) {
        return @{ ok = $true; pasta = "$raiz"; removidas = 0; mantidas = 0; erros = @() }
    }

    $pastas = @(Get-ChildItem -LiteralPath $raiz -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending)
    $manter = @()
    if ($ManterUltimas -gt 0) {
        $manter = @(@($pastas | Select-Object -First $ManterUltimas) | ForEach-Object { "$($_.Name)" })
    }

    $removidas = 0
    foreach ($p in $pastas) {
        if ($manter -contains "$($p.Name)") { continue }

        foreach ($xml in @(Get-ChildItem -LiteralPath $p.FullName -Recurse -Force -Filter 'autounattend.xml' -File -ErrorAction SilentlyContinue)) {
            Remove-TmxUnattendFile -Path $xml.FullName | Out-Null
        }
        try {
            Remove-Item -LiteralPath $p.FullName -Recurse -Force -ErrorAction Stop
            $removidas++
        } catch {
            $erros.Add("$($p.Name): $($_.Exception.Message)")
        }
    }

    Write-TmxLog -Level INFO -Message 'MicroWin: pastas de trabalho limpas' -Data @{
        raiz = "$raiz"; removidas = $removidas; mantidas = @($manter).Count; erros = $erros.Count
    }

    @{
        ok        = [bool]($erros.Count -eq 0)
        pasta     = "$raiz"
        removidas = $removidas
        mantidas  = @($manter).Count
        erros     = $erros.ToArray()
    }
}

function Send-TmxMicroWinProgress {
    <#
    .SYNOPSIS
        Progresso para o job da ponte e para o -Progress do chamador.
    #>
    [CmdletBinding()]
    param(
        [int] $Pct,
        [string] $Status,
        [scriptblock] $Progress
    )

    try { Send-TmxJobProgress -Pct $Pct -Status $Status } catch { Write-Verbose "progresso nao publicado: $($_.Exception.Message)" }
    if ($null -ne $Progress) {
        try { & $Progress $Pct $Status } catch { Write-Verbose "callback de progresso falhou: $($_.Exception.Message)" }
    }
}

function Invoke-TmxMicroWinBuild {
    <#
    .SYNOPSIS
        Gera uma ISO enxuta do Windows a partir de uma ISO oficial.
    .PARAMETER IsoPath
        A ISO de origem. Somente lida - nunca alterada.
    .PARAMETER EdicaoIndex
        Indice da edicao dentro de install.wim/esd (1 = primeira).
    .PARAMETER AppxRemover
        Pedacos de nome de appx provisionado a remover.
    .PARAMETER PacotesRemover
        Pedacos de nome de pacote do Windows a remover (caixa avancada).
    .PARAMETER Usuario / Senha
        Conta local de administrador criada pelo autounattend.xml. So
        obrigatorios com -ContaLocal $true (o padrao).
    .PARAMETER Destino
        PASTA onde o .iso final e gravado.
    .PARAMETER ContaLocal
        $true (padrao): grava o autounattend.xml com a conta local.
    .PARAMETER RemoverOneDrive / RemoverEdge / RemoverDefender
        Removem o componente da IMAGEM (appx, pastas e pacotes offline).
    .PARAMETER DesativarTelemetria
        Politicas de telemetria nos hives SOFTWARE/SYSTEM offline (reg load).
    .PARAMETER IncluirDrivers
        Export-WindowsDriver -Online numa pasta de trabalho e
        Add-WindowsDriver -Recurse na imagem.
    .PARAMETER Progress
        Scriptblock opcional chamado como & $Progress <pct> <status>.
    .OUTPUTS
        @{ ok; cancelado; mensagem; arquivo; tamanhoGB; pastaTrabalho; passos = @({nome,ok,detalhe}) }
    .NOTES
        Cancelamento (microwin.cancel): cooperativo, conferido entre um passo e
        outro ($sync.microwinCancelar). Cancelado, o build descarta a imagem
        montada (-Discard), solta a ISO e APAGA a pasta de trabalho.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]   $IsoPath,
        [int]      $EdicaoIndex = 1,
        [string[]] $AppxRemover = @(),
        [string[]] $PacotesRemover = @(),
        [string]   $Usuario = '',
        [string]   $Senha = '',
        [Parameter(Mandatory)] [string]   $Destino,
        [bool]     $ContaLocal = $true,
        [bool]     $RemoverOneDrive = $false,
        [bool]     $RemoverEdge = $false,
        [bool]     $DesativarTelemetria = $false,
        [bool]     $IncluirDrivers = $false,
        [bool]     $RemoverDefender = $false,
        [scriptblock] $Progress
    )

    $passos    = New-Object 'System.Collections.Generic.List[object]'
    $testMode  = [bool]($null -ne $sync -and $sync.testMode)

    function ConvertTo-TmxMicroWinResult {
        param([bool] $Ok, [string] $Mensagem, [string] $Arquivo, $TamanhoGB, [string] $PastaTrabalho, [bool] $Cancelado = $false)
        @{
            ok            = [bool]$Ok
            cancelado     = [bool]$Cancelado
            mensagem      = "$Mensagem"
            arquivo       = $Arquivo
            tamanhoGB     = $(if ($null -eq $TamanhoGB) { 0.0 } else { [double]$TamanhoGB })
            pastaTrabalho = $PastaTrabalho
            passos        = $passos.ToArray()
        }
    }

    # --- pre-checagens ------------------------------------------------------

    if ($ContaLocal -and -not "$Usuario") {
        return (ConvertTo-TmxMicroWinResult -Ok $false -Mensagem 'informe o usuario da conta local')
    }

    $oscdimg = Get-TmxOscdimgPath
    if (-not $oscdimg) {
        return (ConvertTo-TmxMicroWinResult -Ok $false -Mensagem 'oscdimg.exe nao encontrado: instale o Windows ADK (Deployment Tools)')
    }

    $raizTrabalho = Get-TmxMicroWinWorkRoot
    $livreGB = Get-TmxFreeSpaceGB -Drive $raizTrabalho
    $necessarioGB = Get-TmxMicroWinSpaceNeededGB -IsoPath $IsoPath
    if ($livreGB -ge 0 -and $livreGB -lt $necessarioGB) {
        return (ConvertTo-TmxMicroWinResult -Ok $false -Mensagem ("espaco livre insuficiente: {0} GB (o MicroWin precisa de {1} GB: tamanho da ISO x 3 + 5 GB)" -f $livreGB, $necessarioGB))
    }

    if (-not $testMode -and -not (Test-TmxElevation)) {
        return (ConvertTo-TmxMicroWinResult -Ok $false -Mensagem 'o MicroWin precisa de privilegios de administrador (montar imagem e usar o DISM)')
    }

    # -PathType Leaf: uma PASTA chamada 'algo.iso' passaria no Test-Path solto e
    # so quebraria la na frente, no Mount-DiskImage.
    if (-not (Test-Path -LiteralPath $IsoPath -PathType Leaf)) {
        return (ConvertTo-TmxMicroWinResult -Ok $false -Mensagem "ISO nao encontrada: $IsoPath")
    }
    if (-not (Test-Path -LiteralPath $Destino -PathType Container)) {
        return (ConvertTo-TmxMicroWinResult -Ok $false -Mensagem "pasta de destino nao encontrada: $Destino")
    }

    Write-TmxLog -Level INFO -Message 'MicroWin: build iniciado' -Data @{
        iso = "$IsoPath"; edicao = [int]$EdicaoIndex; usuario = "$Usuario"; destino = "$Destino"
        appx = @($AppxRemover).Count; pacotes = @($PacotesRemover).Count
    }

    $pastas = New-TmxMicroWinWorkDir
    $arquivoFinal = Join-Path $Destino ('microwin-{0:yyyyMMdd-HHmmss}.iso' -f (Get-Date))

    $isoMontada    = $false
    $imagemMontada = $false

    # O resultado e montado DEPOIS do try/catch/finally, e nao com um 'return'
    # la dentro: o finally ainda acrescenta passos (desmontar-emergencia) e um
    # 'return (ConvertTo-...)' congelaria a lista antes deles.
    $estado = @{ ok = $false; cancelado = $false; mensagem = ''; arquivo = $null; tamanho = 0.0 }
    $arquivoXml = Join-Path "$($pastas.contents)" 'autounattend.xml'

    try {
        # --- 1. montar a ISO de origem -------------------------------------
        Invoke-TmxMicroWinCheckpoint -Pct 5 -Status 'Montando a ISO de origem...' -Progress $Progress
        $montagem = Mount-TmxIso -IsoPath $IsoPath
        if (-not $montagem.ok) { throw "montar-iso: $($montagem.mensagem)" }
        $isoMontada = $true
        $passos.Add((New-TmxMicroWinStep -Nome 'montar-iso' -Ok $true -Detalhe "$($montagem.mensagem)"))

        # --- 2. copiar a arvore --------------------------------------------
        Invoke-TmxMicroWinCheckpoint -Pct 15 -Status 'Copiando os arquivos da ISO (pode levar varios minutos)...' -Progress $Progress
        $copia = $null
        try {
            $copia = Copy-TmxIsoTree -Source "$($montagem.raiz)" -Destination "$($pastas.contents)"
        } catch {
            throw "copiar-arquivos: $($_.Exception.Message)"
        }
        # O somente-leitura do volume UDF acompanha a copia; se nao sair, o
        # install.wim nao pode ser regravado e a falha apareceria varios passos
        # adiante com "acesso negado". Melhor parar aqui.
        if (-not (Set-TmxPathWritable -Path "$($pastas.contents)")) {
            throw "copiar-arquivos: nao foi possivel remover o somente-leitura da copia em $($pastas.contents)"
        }
        $passos.Add((New-TmxMicroWinStep -Nome 'copiar-arquivos' -Ok $true -Detalhe "robocopy codigo $($copia.codigo)"))

        # --- 3. desmontar a ISO (nada mais e lido dela) --------------------
        Invoke-TmxMicroWinCheckpoint -Pct 35 -Status 'Desmontando a ISO de origem...' -Progress $Progress
        Dismount-TmxIso -IsoPath $IsoPath | Out-Null
        $isoMontada = $false
        $passos.Add((New-TmxMicroWinStep -Nome 'desmontar-iso' -Ok $true -Detalhe 'ISO de origem liberada'))

        # --- 4. esd -> wim, quando preciso ---------------------------------
        $imagem = Get-TmxInstallImagePath -Raiz "$($pastas.contents)"
        if ($null -eq $imagem) { throw 'montar-imagem: sources\install.wim (ou install.esd) nao existe na copia' }

        $caminhoWim = "$($imagem.caminho)"
        $indice     = [int]$EdicaoIndex
        if ("$($imagem.formato)" -eq 'esd') {
            Invoke-TmxMicroWinCheckpoint -Pct 40 -Status 'Convertendo install.esd em install.wim...' -Progress $Progress
            $destinoWim = Join-Path (Split-Path -Parent $caminhoWim) 'install.wim'
            try {
                Export-TmxWindowsImageWrapper -SourceImagePath $caminhoWim -SourceIndex $indice `
                    -DestinationImagePath $destinoWim -CompressionType 'Max' | Out-Null
            } catch {
                throw "converter-esd: $($_.Exception.Message)"
            }
            Remove-Item -LiteralPath $caminhoWim -Force -ErrorAction SilentlyContinue
            $caminhoWim = $destinoWim
            # O export reescreve a edicao escolhida como indice 1 do wim novo.
            $indice = 1
            $passos.Add((New-TmxMicroWinStep -Nome 'converter-esd' -Ok $true -Detalhe 'install.esd exportado como install.wim'))
        }

        # --- 4b. drivers deste PC (antes de montar: leitura do sistema vivo) -
        $pastaDrivers = Join-Path "$($pastas.raiz)" 'drivers'
        if ($IncluirDrivers) {
            Invoke-TmxMicroWinCheckpoint -Pct 42 -Status 'Exportando os drivers deste PC...' -Progress $Progress
            $nDrivers = 0
            try {
                New-Item -ItemType Directory -Path $pastaDrivers -Force | Out-Null
                $nDrivers = @(Export-TmxWindowsDriverWrapper -Destination $pastaDrivers).Count
            } catch {
                throw "exportar-drivers: $($_.Exception.Message)"
            }
            $passos.Add((New-TmxMicroWinStep -Nome 'exportar-drivers' -Ok $true -Detalhe ("{0} driver(s) exportado(s)" -f $nDrivers)))
        }

        # --- 5. montar a imagem --------------------------------------------
        Invoke-TmxMicroWinCheckpoint -Pct 45 -Status 'Montando a imagem do Windows...' -Progress $Progress
        try {
            Mount-TmxWindowsImageWrapper -ImagePath $caminhoWim -Index $indice -Path "$($pastas.mount)" -ScratchDirectory "$($pastas.scratch)" | Out-Null
        } catch {
            throw "montar-imagem: $($_.Exception.Message)"
        }
        $imagemMontada = $true
        $passos.Add((New-TmxMicroWinStep -Nome 'montar-imagem' -Ok $true -Detalhe "indice $indice"))

        # --- 6. appx --------------------------------------------------------
        Invoke-TmxMicroWinCheckpoint -Pct 60 -Status 'Removendo os aplicativos escolhidos...' -Progress $Progress
        $rAppx = $null
        try {
            $rAppx = Remove-TmxIsoAppx -Path "$($pastas.mount)" -Nomes $AppxRemover
        } catch {
            throw "remover-appx: $($_.Exception.Message)"
        }
        $passos.Add((New-TmxMicroWinStep -Nome 'remover-appx' -Ok $true -Detalhe (
            "{0} removido(s), {1} ausente(s) nesta edicao" -f @($rAppx.removidos).Count, @($rAppx.ignorados).Count)))

        # --- 7. pacotes -----------------------------------------------------
        Invoke-TmxMicroWinCheckpoint -Pct 66 -Status 'Removendo os pacotes escolhidos...' -Progress $Progress
        $rPac = $null
        try {
            $rPac = Remove-TmxIsoPackages -Path "$($pastas.mount)" -Nomes $PacotesRemover
        } catch {
            throw "remover-pacotes: $($_.Exception.Message)"
        }
        $passos.Add((New-TmxMicroWinStep -Nome 'remover-pacotes' -Ok $true -Detalhe (
            "{0} removido(s), {1} ausente(s) nesta edicao" -f @($rPac.removidos).Count, @($rPac.ignorados).Count)))

        # --- 7b. OneDrive, Edge, Defender, telemetria e drivers -------------
        # Cada opcao e um passo proprio: a falha diz qual delas quebrou, e a
        # imagem e descartada como em qualquer outro passo.
        if ($RemoverOneDrive) {
            Invoke-TmxMicroWinCheckpoint -Pct 70 -Status 'Removendo o OneDrive da imagem...' -Progress $Progress
            try { $r = Remove-TmxMicroWinOneDrive -MountPath "$($pastas.mount)" } catch { throw "remover-onedrive: $($_.Exception.Message)" }
            $passos.Add((New-TmxMicroWinStep -Nome 'remover-onedrive' -Ok $true -Detalhe "$($r.detalhe)"))
        }
        if ($RemoverEdge) {
            Invoke-TmxMicroWinCheckpoint -Pct 72 -Status 'Removendo o Microsoft Edge da imagem...' -Progress $Progress
            try { $r = Remove-TmxMicroWinEdge -MountPath "$($pastas.mount)" } catch { throw "remover-edge: $($_.Exception.Message)" }
            $passos.Add((New-TmxMicroWinStep -Nome 'remover-edge' -Ok $true -Detalhe "$($r.detalhe)"))
        }
        if ($RemoverDefender) {
            Invoke-TmxMicroWinCheckpoint -Pct 74 -Status 'Removendo o Windows Defender da imagem...' -Progress $Progress
            try { $r = Remove-TmxMicroWinDefender -MountPath "$($pastas.mount)" } catch { throw "remover-defender: $($_.Exception.Message)" }
            $passos.Add((New-TmxMicroWinStep -Nome 'remover-defender' -Ok $true -Detalhe "$($r.detalhe)"))
        }
        if ($DesativarTelemetria) {
            Invoke-TmxMicroWinCheckpoint -Pct 76 -Status 'Desativando a telemetria (registro offline)...' -Progress $Progress
            try { $r = Set-TmxMicroWinTelemetryOff -MountPath "$($pastas.mount)" } catch { throw "telemetria: $($_.Exception.Message)" }
            $passos.Add((New-TmxMicroWinStep -Nome 'telemetria' -Ok $true -Detalhe "$($r.detalhe)"))
        }
        if ($IncluirDrivers) {
            Invoke-TmxMicroWinCheckpoint -Pct 78 -Status 'Adicionando os drivers na imagem...' -Progress $Progress
            try {
                Add-TmxWindowsDriverWrapper -Path "$($pastas.mount)" -Driver $pastaDrivers | Out-Null
            } catch {
                throw "adicionar-drivers: $($_.Exception.Message)"
            }
            $passos.Add((New-TmxMicroWinStep -Nome 'adicionar-drivers' -Ok $true -Detalhe 'drivers exportados adicionados (Add-WindowsDriver -Recurse)'))
        }

        # --- 8. autounattend.xml na raiz da ISO -----------------------------
        if ($ContaLocal) {
            Invoke-TmxMicroWinCheckpoint -Pct 80 -Status 'Gravando o autounattend.xml...' -Progress $Progress
            try {
                $xml = New-TmxUnattend -Usuario $Usuario -Senha $Senha -Idioma 'pt-BR'
                Set-Content -LiteralPath $arquivoXml -Value $xml -Encoding UTF8 -Force
            } catch {
                throw "autounattend: $($_.Exception.Message)"
            }
            $passos.Add((New-TmxMicroWinStep -Nome 'autounattend' -Ok $true -Detalhe 'conta local e idioma pt-BR'))
        }

        # --- 9. desmontar gravando ------------------------------------------
        Invoke-TmxMicroWinCheckpoint -Pct 85 -Status 'Gravando as mudancas na imagem (demora)...' -Progress $Progress
        try {
            Dismount-TmxWindowsImageWrapper -Path "$($pastas.mount)" -Save | Out-Null
        } catch {
            throw "gravar-imagem: $($_.Exception.Message)"
        }
        $imagemMontada = $false
        $passos.Add((New-TmxMicroWinStep -Nome 'gravar-imagem' -Ok $true -Detalhe 'imagem desmontada com as mudancas'))

        # --- 10. oscdimg -----------------------------------------------------
        Invoke-TmxMicroWinCheckpoint -Pct 95 -Status 'Gerando o arquivo .iso...' -Progress $Progress
        $iso = New-TmxIso -Origem "$($pastas.contents)" -Destino $arquivoFinal
        if (-not $iso.ok) { throw "gerar-iso: $($iso.mensagem)" }
        $passos.Add((New-TmxMicroWinStep -Nome 'gerar-iso' -Ok $true -Detalhe "oscdimg codigo $($iso.codigo)"))

        # --- 11. conferir ----------------------------------------------------
        if (-not (Test-Path -LiteralPath $arquivoFinal)) { throw 'verificar: a ISO final nao foi encontrada no destino' }
        $tamanho = Get-TmxFileSizeGB -Path $arquivoFinal
        $passos.Add((New-TmxMicroWinStep -Nome 'verificar' -Ok $true -Detalhe ("{0} GB" -f $tamanho)))

        Write-TmxLog -Level INFO -Message 'MicroWin: build concluido' -Data @{ arquivo = "$arquivoFinal"; tamanhoGB = $tamanho }

        $estado.ok       = $true
        $estado.mensagem = 'ISO gerada com sucesso'
        $estado.arquivo  = $arquivoFinal
        $estado.tamanho  = $tamanho

    } catch {
        $mensagem = "$($_.Exception.Message)"
        # Prefixo com o nome do passo, e so dos passos conhecidos: um
        # '^([a-z-]+):' generico transformaria "acesso negado: ..." num passo
        # chamado 'acesso'.
        $nomePasso = 'falha'
        if ($mensagem -match '^(montar-iso|copiar-arquivos|desmontar-iso|converter-esd|exportar-drivers|montar-imagem|remover-appx|remover-pacotes|remover-onedrive|remover-edge|remover-defender|telemetria|adicionar-drivers|autounattend|gravar-imagem|gerar-iso|verificar|cancelado):\s*(.*)$') {
            $nomePasso = $Matches[1]
            $mensagem  = $Matches[2]
        }
        $passos.Add((New-TmxMicroWinStep -Nome $nomePasso -Ok $false -Detalhe $mensagem))
        if ($nomePasso -eq 'cancelado') {
            $estado.cancelado = $true
            Write-TmxLog -Level WARN -Message 'MicroWin: build cancelado pelo usuario' -Data @{ pasta = "$($pastas.raiz)" }
        } else {
            Write-TmxLog -Level ERROR -Message 'MicroWin: build falhou' -Data @{ passo = $nomePasso; erro = $mensagem; pasta = "$($pastas.raiz)" }
        }

        $estado.ok       = $false
        $estado.mensagem = $mensagem

    } finally {
        # Limpeza de emergencia, na ordem: descartar a imagem montada (com
        # /Cleanup-Mountpoints como segunda tentativa), soltar a ISO e apagar o
        # autounattend.xml - que carrega a SENHA em texto puro e nao pode
        # sobreviver ao build nem quando ele falha.
        if ($imagemMontada) {
            $descartou = $false
            try {
                Dismount-TmxWindowsImageWrapper -Path "$($pastas.mount)" -Discard | Out-Null
                $descartou = $true
            } catch {
                Write-TmxLog -Level WARN -Message 'MicroWin: nao foi possivel descartar a imagem montada' -Data @{ erro = "$($_.Exception.Message)" }
            }

            if (-not $descartou) {
                # Uma montagem orfa trava TODA tentativa seguinte ("a imagem ja
                # esta montada em outro diretorio"), entao vale insistir com o
                # proprio DISM antes de desistir.
                try {
                    $limpeza = Invoke-TmxDismCleanupMountpoints
                    if ([int]$limpeza.codigo -eq 0) { $descartou = $true }
                } catch {
                    Write-TmxLog -Level WARN -Message 'MicroWin: /Cleanup-Mountpoints falhou' -Data @{ erro = "$($_.Exception.Message)" }
                }
            }

            if ($descartou) {
                $imagemMontada = $false
            } else {
                $passos.Add((New-TmxMicroWinStep -Nome 'desmontar-emergencia' -Ok $false -Detalhe (
                    "A imagem continua montada em $($pastas.mount). Feche programas e janelas que estejam usando essa pasta e rode, " +
                    "como administrador: dism.exe /Cleanup-Mountpoints")))
                Write-TmxLog -Level ERROR -Message 'MicroWin: imagem continua montada' -Data @{ pasta = "$($pastas.mount)" }
            }
        }

        if ($isoMontada) {
            Dismount-TmxIso -IsoPath $IsoPath | Out-Null
            $isoMontada = $false
        }

        Remove-TmxUnattendFile -Path $arquivoXml | Out-Null
    }

    # Sucesso: a pasta 'contents' e uma copia inteira do Windows (varios GB) e
    # ja nao serve para nada - some com ela e deixa so a raiz do trabalho, que
    # e o que a interface mostra. Na falha ela FICA, para diagnostico (sem o
    # autounattend.xml, ja apagado acima).
    if ($estado.ok) {
        Send-TmxMicroWinProgress -Pct 98 -Status 'Limpando a pasta de trabalho...' -Progress $Progress
        $limpou = $true
        try {
            if (Test-Path -LiteralPath "$($pastas.contents)") {
                Remove-Item -LiteralPath "$($pastas.contents)" -Recurse -Force -ErrorAction Stop
            }
            Remove-Item -LiteralPath "$($pastas.mount)" -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath "$($pastas.scratch)" -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath (Join-Path "$($pastas.raiz)" 'drivers') -Recurse -Force -ErrorAction SilentlyContinue
        } catch {
            $limpou = $false
            Write-TmxLog -Level WARN -Message 'MicroWin: pasta de trabalho nao pode ser apagada' -Data @{ erro = "$($_.Exception.Message)" }
        }
        $passos.Add((New-TmxMicroWinStep -Nome 'limpar-trabalho' -Ok $limpou -Detalhe $(
            if ($limpou) { 'copia temporaria e autounattend.xml removidos' }
            else { "apague a mao: $($pastas.raiz)" })))
    }

    # Cancelado (microwin.cancel): a imagem ja foi descartada no finally; a
    # pasta de trabalho inteira some (quem cancelou nao quer diagnostico) e uma
    # ISO pela metade no destino tambem.
    if ($estado.cancelado) {
        Send-TmxMicroWinProgress -Pct 98 -Status 'Apagando a pasta de trabalho...' -Progress $Progress
        $limpou = $true
        if (-not $imagemMontada) {
            try {
                if (Test-Path -LiteralPath "$($pastas.raiz)") {
                    Remove-Item -LiteralPath "$($pastas.raiz)" -Recurse -Force -ErrorAction Stop
                }
            } catch {
                $limpou = $false
                Write-TmxLog -Level WARN -Message 'MicroWin: pasta de trabalho do build cancelado nao pode ser apagada' -Data @{ erro = "$($_.Exception.Message)" }
            }
        } else {
            # Imagem presa no DISM: apagar a pasta de montagem por cima dela
            # corromperia o registro de montagens. Fica para o Cleanup-Mountpoints.
            $limpou = $false
        }
        if (Test-Path -LiteralPath $arquivoFinal) { Remove-Item -LiteralPath $arquivoFinal -Force -ErrorAction SilentlyContinue }
        $passos.Add((New-TmxMicroWinStep -Nome 'limpar-trabalho' -Ok $limpou -Detalhe $(
            if ($limpou) { 'pasta de trabalho apagada' } else { "apague a mao: $($pastas.raiz)" })))
    }

    Send-TmxMicroWinProgress -Pct 100 -Status $(if ($estado.ok) { 'Concluido' } elseif ($estado.cancelado) { 'Cancelado' } else { 'Interrompido' }) -Progress $Progress

    ConvertTo-TmxMicroWinResult -Ok $estado.ok -Mensagem "$($estado.mensagem)" `
        -Arquivo $estado.arquivo -TamanhoGB $estado.tamanho -PastaTrabalho "$($pastas.raiz)" -Cancelado ([bool]$estado.cancelado)
}
