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
        Conta local de administrador criada pelo autounattend.xml.
    .PARAMETER Destino
        PASTA onde o .iso final e gravado.
    .PARAMETER Progress
        Scriptblock opcional chamado como & $Progress <pct> <status>.
    .OUTPUTS
        @{ ok; mensagem; arquivo; tamanhoGB; pastaTrabalho; passos = @({nome,ok,detalhe}) }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]   $IsoPath,
        [int]      $EdicaoIndex = 1,
        [string[]] $AppxRemover = @(),
        [string[]] $PacotesRemover = @(),
        [Parameter(Mandatory)] [string]   $Usuario,
        [string]   $Senha = '',
        [Parameter(Mandatory)] [string]   $Destino,
        [scriptblock] $Progress
    )

    $passos    = New-Object 'System.Collections.Generic.List[object]'
    $testMode  = [bool]($null -ne $sync -and $sync.testMode)

    function ConvertTo-TmxMicroWinResult {
        param([bool] $Ok, [string] $Mensagem, [string] $Arquivo, $TamanhoGB, [string] $PastaTrabalho)
        @{
            ok            = [bool]$Ok
            mensagem      = "$Mensagem"
            arquivo       = $Arquivo
            tamanhoGB     = $(if ($null -eq $TamanhoGB) { 0.0 } else { [double]$TamanhoGB })
            pastaTrabalho = $PastaTrabalho
            passos        = $passos.ToArray()
        }
    }

    # --- pre-checagens ------------------------------------------------------

    $oscdimg = Get-TmxOscdimgPath
    if (-not $oscdimg) {
        return (ConvertTo-TmxMicroWinResult -Ok $false -Mensagem 'oscdimg.exe nao encontrado: instale o Windows ADK (Deployment Tools)')
    }

    $raizTrabalho = Get-TmxMicroWinWorkRoot
    $livreGB = Get-TmxFreeSpaceGB -Drive $raizTrabalho
    if ($livreGB -ge 0 -and $livreGB -lt 20) {
        return (ConvertTo-TmxMicroWinResult -Ok $false -Mensagem ("espaco livre insuficiente: {0} GB (o MicroWin precisa de pelo menos 20 GB)" -f $livreGB))
    }

    if (-not $testMode -and -not (Test-TmxElevation)) {
        return (ConvertTo-TmxMicroWinResult -Ok $false -Mensagem 'o MicroWin precisa de privilegios de administrador (montar imagem e usar o DISM)')
    }

    if (-not (Test-Path -LiteralPath $IsoPath)) {
        return (ConvertTo-TmxMicroWinResult -Ok $false -Mensagem "ISO nao encontrada: $IsoPath")
    }
    if (-not (Test-Path -LiteralPath $Destino)) {
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

    try {
        # --- 1. montar a ISO de origem -------------------------------------
        Send-TmxMicroWinProgress -Pct 5 -Status 'Montando a ISO de origem...' -Progress $Progress
        $montagem = Mount-TmxIso -IsoPath $IsoPath
        if (-not $montagem.ok) { throw "montar-iso: $($montagem.mensagem)" }
        $isoMontada = $true
        $passos.Add((New-TmxMicroWinStep -Nome 'montar-iso' -Ok $true -Detalhe "$($montagem.mensagem)"))

        # --- 2. copiar a arvore --------------------------------------------
        Send-TmxMicroWinProgress -Pct 15 -Status 'Copiando os arquivos da ISO (pode levar varios minutos)...' -Progress $Progress
        $codigo = Copy-TmxIsoTree -Source "$($montagem.raiz)" -Destination "$($pastas.contents)"
        if ([int]$codigo -ge 8) { throw "copiar-arquivos: robocopy terminou com codigo $codigo" }
        Set-TmxPathWritable -Path "$($pastas.contents)" | Out-Null
        $passos.Add((New-TmxMicroWinStep -Nome 'copiar-arquivos' -Ok $true -Detalhe "robocopy codigo $codigo"))

        # --- 3. desmontar a ISO (nada mais e lido dela) --------------------
        Send-TmxMicroWinProgress -Pct 35 -Status 'Desmontando a ISO de origem...' -Progress $Progress
        Dismount-TmxIso -IsoPath $IsoPath | Out-Null
        $isoMontada = $false
        $passos.Add((New-TmxMicroWinStep -Nome 'desmontar-iso' -Ok $true -Detalhe 'ISO de origem liberada'))

        # --- 4. esd -> wim, quando preciso ---------------------------------
        $imagem = Get-TmxInstallImagePath -Raiz "$($pastas.contents)"
        if ($null -eq $imagem) { throw 'montar-imagem: sources\install.wim (ou install.esd) nao existe na copia' }

        $caminhoWim = "$($imagem.caminho)"
        $indice     = [int]$EdicaoIndex
        if ("$($imagem.formato)" -eq 'esd') {
            Send-TmxMicroWinProgress -Pct 40 -Status 'Convertendo install.esd em install.wim...' -Progress $Progress
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

        # --- 5. montar a imagem --------------------------------------------
        Send-TmxMicroWinProgress -Pct 45 -Status 'Montando a imagem do Windows...' -Progress $Progress
        try {
            Mount-TmxWindowsImageWrapper -ImagePath $caminhoWim -Index $indice -Path "$($pastas.mount)" -ScratchDirectory "$($pastas.scratch)" | Out-Null
        } catch {
            throw "montar-imagem: $($_.Exception.Message)"
        }
        $imagemMontada = $true
        $passos.Add((New-TmxMicroWinStep -Nome 'montar-imagem' -Ok $true -Detalhe "indice $indice"))

        # --- 6. appx --------------------------------------------------------
        Send-TmxMicroWinProgress -Pct 60 -Status 'Removendo os aplicativos escolhidos...' -Progress $Progress
        $rAppx = $null
        try {
            $rAppx = Remove-TmxIsoAppx -Path "$($pastas.mount)" -Nomes $AppxRemover
        } catch {
            throw "remover-appx: $($_.Exception.Message)"
        }
        $passos.Add((New-TmxMicroWinStep -Nome 'remover-appx' -Ok $true -Detalhe (
            "{0} removido(s), {1} ausente(s) nesta edicao" -f @($rAppx.removidos).Count, @($rAppx.ignorados).Count)))

        # --- 7. pacotes -----------------------------------------------------
        Send-TmxMicroWinProgress -Pct 70 -Status 'Removendo os pacotes escolhidos...' -Progress $Progress
        $rPac = $null
        try {
            $rPac = Remove-TmxIsoPackages -Path "$($pastas.mount)" -Nomes $PacotesRemover
        } catch {
            throw "remover-pacotes: $($_.Exception.Message)"
        }
        $passos.Add((New-TmxMicroWinStep -Nome 'remover-pacotes' -Ok $true -Detalhe (
            "{0} removido(s), {1} ausente(s) nesta edicao" -f @($rPac.removidos).Count, @($rPac.ignorados).Count)))

        # --- 8. autounattend.xml na raiz da ISO -----------------------------
        Send-TmxMicroWinProgress -Pct 75 -Status 'Gravando o autounattend.xml...' -Progress $Progress
        try {
            $xml = New-TmxUnattend -Usuario $Usuario -Senha $Senha -Idioma 'pt-BR'
            $arquivoXml = Join-Path "$($pastas.contents)" 'autounattend.xml'
            Set-Content -LiteralPath $arquivoXml -Value $xml -Encoding UTF8 -Force
        } catch {
            throw "autounattend: $($_.Exception.Message)"
        }
        $passos.Add((New-TmxMicroWinStep -Nome 'autounattend' -Ok $true -Detalhe 'conta local e idioma pt-BR'))

        # --- 9. desmontar gravando ------------------------------------------
        Send-TmxMicroWinProgress -Pct 85 -Status 'Gravando as mudancas na imagem (demora)...' -Progress $Progress
        try {
            Dismount-TmxWindowsImageWrapper -Path "$($pastas.mount)" -Save | Out-Null
        } catch {
            throw "gravar-imagem: $($_.Exception.Message)"
        }
        $imagemMontada = $false
        $passos.Add((New-TmxMicroWinStep -Nome 'gravar-imagem' -Ok $true -Detalhe 'imagem desmontada com as mudancas'))

        # --- 10. oscdimg -----------------------------------------------------
        Send-TmxMicroWinProgress -Pct 95 -Status 'Gerando o arquivo .iso...' -Progress $Progress
        $iso = New-TmxIso -Origem "$($pastas.contents)" -Destino $arquivoFinal
        if (-not $iso.ok) { throw "gerar-iso: $($iso.mensagem)" }
        $passos.Add((New-TmxMicroWinStep -Nome 'gerar-iso' -Ok $true -Detalhe "oscdimg codigo $($iso.codigo)"))

        # --- 11. conferir ----------------------------------------------------
        if (-not (Test-Path -LiteralPath $arquivoFinal)) { throw 'verificar: a ISO final nao foi encontrada no destino' }
        $tamanho = Get-TmxFileSizeGB -Path $arquivoFinal
        $passos.Add((New-TmxMicroWinStep -Nome 'verificar' -Ok $true -Detalhe ("{0} GB" -f $tamanho)))

        Send-TmxMicroWinProgress -Pct 100 -Status 'Concluido' -Progress $Progress
        Write-TmxLog -Level INFO -Message 'MicroWin: build concluido' -Data @{ arquivo = "$arquivoFinal"; tamanhoGB = $tamanho }

        return (ConvertTo-TmxMicroWinResult -Ok $true -Mensagem 'ISO gerada com sucesso' -Arquivo $arquivoFinal -TamanhoGB $tamanho -PastaTrabalho "$($pastas.raiz)")

    } catch {
        $mensagem = "$($_.Exception.Message)"
        # Prefixo com o nome do passo, e so dos passos conhecidos: um
        # '^([a-z-]+):' generico transformaria "acesso negado: ..." num passo
        # chamado 'acesso'.
        $nomePasso = 'falha'
        if ($mensagem -match '^(montar-iso|copiar-arquivos|desmontar-iso|converter-esd|montar-imagem|remover-appx|remover-pacotes|autounattend|gravar-imagem|gerar-iso|verificar):\s*(.*)$') {
            $nomePasso = $Matches[1]
            $mensagem  = $Matches[2]
        }
        $passos.Add((New-TmxMicroWinStep -Nome $nomePasso -Ok $false -Detalhe $mensagem))
        Write-TmxLog -Level ERROR -Message 'MicroWin: build falhou' -Data @{ passo = $nomePasso; erro = $mensagem; pasta = "$($pastas.raiz)" }
        return (ConvertTo-TmxMicroWinResult -Ok $false -Mensagem $mensagem -PastaTrabalho "$($pastas.raiz)")

    } finally {
        # Limpeza de emergencia: descartar a imagem montada e soltar a ISO.
        # A pasta de trabalho fica de proposito (diagnostico).
        if ($imagemMontada) {
            try {
                Dismount-TmxWindowsImageWrapper -Path "$($pastas.mount)" -Discard | Out-Null
            } catch {
                Write-TmxLog -Level WARN -Message 'MicroWin: nao foi possivel descartar a imagem montada' -Data @{ erro = "$($_.Exception.Message)" }
            }
        }
        if ($isoMontada) {
            Dismount-TmxIso -IsoPath $IsoPath | Out-Null
        }
    }
}
