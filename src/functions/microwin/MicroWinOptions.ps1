# functions/microwin/MicroWinOptions.ps1
# Opcoes do build do MicroWin (spec v2, secao 11) e o cancelamento:
#   - removerOneDrive / removerEdge / removerDefender: appx, pastas e pacotes
#     da IMAGEM montada (nunca do Windows em uso);
#   - desativarTelemetria: reg load dos hives SOFTWARE e SYSTEM da imagem,
#     politicas de telemetria, reg unload;
#   - incluirDrivers: Export-WindowsDriver -Online + Add-WindowsDriver -Recurse;
#   - espaco necessario = tamanho da ISO x 3 + 5 GB;
#   - microwin.cancel: cooperativo, via $sync.microwinCancelar.
#
# Tudo que toca processo externo ou cmdlet do DISM passa por um wrapper
# pequeno (Invoke-TmxRegExe, Invoke-TmxTakeOwnership, Export-/Add-
# TmxWindowsDriverWrapper) para os testes mockarem.

# ---------------------------------------------------------------------------
# Espaco e cancelamento
# ---------------------------------------------------------------------------

function Get-TmxMicroWinSpaceNeededGB {
    <#
    .SYNOPSIS
        GB livres que o build precisa: tamanho da ISO x 3 + 5, arredondado
        para cima. Sem ISO (ou ilegivel), o minimo fixo de 20 GB.
    #>
    [CmdletBinding()]
    param([string] $IsoPath)

    $minimo = Get-TmxMicroWinEspacoMinimoGB
    if (-not $IsoPath) { return $minimo }
    try {
        if (-not (Test-Path -LiteralPath $IsoPath -PathType Leaf)) { return $minimo }
        # Arredonda antes (2 casas): um arquivo de poucos bytes nao vira 1 GB a mais.
        $gb = [math]::Round([double](Get-Item -LiteralPath $IsoPath -ErrorAction Stop).Length / 1GB, 2)
        return [int][math]::Ceiling(($gb * 3) + 5)
    } catch {
        return $minimo
    }
}

function Test-TmxMicroWinCancelRequested {
    <#
    .SYNOPSIS
        $true quando microwin.cancel pediu para parar o build em andamento.
    #>
    [CmdletBinding()]
    param()
    [bool]($null -ne $sync -and $sync.microwinCancelar -eq $true)
}

function Invoke-TmxMicroWinCheckpoint {
    <#
    .SYNOPSIS
        Ponto de parada entre passos: lanca 'cancelado: ...' se o build foi
        cancelado; senao publica o progresso do passo que vai comecar.
    #>
    [CmdletBinding()]
    param(
        [int] $Pct,
        [string] $Status,
        [scriptblock] $Progress
    )
    if (Test-TmxMicroWinCancelRequested) { throw 'cancelado: build cancelado pelo usuario' }
    Send-TmxMicroWinProgress -Pct $Pct -Status $Status -Progress $Progress
}

# ---------------------------------------------------------------------------
# Wrappers
# ---------------------------------------------------------------------------

function Invoke-TmxRegExe {
    <#
    .SYNOPSIS
        reg.exe com argumentos em array. Devolve { codigo; saida }.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string[]] $Arguments)
    $out = & reg.exe @Arguments 2>&1
    [pscustomobject]@{ codigo = [int]$LASTEXITCODE; saida = (@($out) | ForEach-Object { "$_" }) -join "`n" }
}

function Invoke-TmxTakeOwnership {
    <#
    .SYNOPSIS
        takeown + icacls (Administradores com controle total) num caminho da
        imagem montada. Os arquivos offline pertencem ao TrustedInstaller e
        nem um administrador apaga sem isso.
    .NOTES
        O /D do takeown espera a letra do "sim" no idioma do Windows (S no
        pt-BR, Y no ingles...).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)

    $sim = 'Y'
    switch ([System.Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName) {
        'pt' { $sim = 'S' }
        'es' { $sim = 'S' }
        'fr' { $sim = 'O' }
        'de' { $sim = 'J' }
        'it' { $sim = 'S' }
    }

    $argsTake = @('/F', $Path, '/A')
    if (Test-Path -LiteralPath $Path -PathType Container) { $argsTake += @('/R', '/D', $sim) }
    $o1 = & takeown.exe @argsTake 2>&1
    $c1 = [int]$LASTEXITCODE

    $argsAcl = @($Path, '/grant', '*S-1-5-32-544:F', '/C', '/Q')
    if (Test-Path -LiteralPath $Path -PathType Container) { $argsAcl += '/T' }
    $o2 = & icacls.exe @argsAcl 2>&1
    $c2 = [int]$LASTEXITCODE

    [pscustomobject]@{ codigo = [math]::Max($c1, $c2); saida = ((@($o1) + @($o2)) | ForEach-Object { "$_" }) -join "`n" }
}

function Export-TmxWindowsDriverWrapper {
    <#
    .SYNOPSIS
        Export-WindowsDriver -Online: copia os drivers de terceiros deste PC.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Destination)
    Export-WindowsDriver -Online -Destination $Destination -ErrorAction Stop
}

function Add-TmxWindowsDriverWrapper {
    <#
    .SYNOPSIS
        Add-WindowsDriver -Recurse na imagem montada.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Driver
    )
    Add-WindowsDriver -Path $Path -Driver $Driver -Recurse -ErrorAction Stop
}

# ---------------------------------------------------------------------------
# Ajudantes da imagem offline
# ---------------------------------------------------------------------------

function Remove-TmxOfflinePath {
    <#
    .SYNOPSIS
        Apaga um arquivo ou pasta DENTRO da imagem montada. $true se apagou,
        $false se nao existia. Lanca se existia e nao saiu.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)

    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    Invoke-TmxTakeOwnership -Path $Path | Out-Null
    Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
    $true
}

function Invoke-TmxOfflineHive {
    <#
    .SYNOPSIS
        reg load de um hive da imagem em HKLM\<Nome>, roda a acao e SEMPRE
        faz reg unload (senao o -Save do Dismount falha com o hive preso).
    .PARAMETER Acao
        Scriptblock chamado como & $Acao 'HKLM\<Nome>'.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $HivePath,
        [Parameter(Mandatory)] [string] $Nome,
        [Parameter(Mandatory)] [scriptblock] $Acao
    )

    if (-not (Test-Path -LiteralPath $HivePath -PathType Leaf)) { throw "hive nao encontrado na imagem: $HivePath" }
    $chave = "HKLM\$Nome"

    $load = Invoke-TmxRegExe -Arguments @('load', $chave, $HivePath)
    if ($load.codigo -ne 0) { throw "reg load $HivePath falhou: $($load.saida)" }

    try {
        & $Acao $chave
    } finally {
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
        $unload = Invoke-TmxRegExe -Arguments @('unload', $chave)
        $tentativa = 1
        while ($unload.codigo -ne 0 -and $tentativa -lt 3) {
            Start-Sleep -Milliseconds 800
            $unload = Invoke-TmxRegExe -Arguments @('unload', $chave)
            $tentativa++
        }
        if ($unload.codigo -ne 0) { throw "reg unload $chave falhou: $($unload.saida)" }
    }
}

function Set-TmxOfflineRegDword {
    <#
    .SYNOPSIS
        reg add de um DWORD num hive offline carregado. Lanca se falhar.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Chave,
        [Parameter(Mandatory)] [string] $Nome,
        [Parameter(Mandatory)] [int]    $Valor
    )
    $r = Invoke-TmxRegExe -Arguments @('add', $Chave, '/v', $Nome, '/t', 'REG_DWORD', '/d', "$Valor", '/f')
    if ($r.codigo -ne 0) { throw "reg add $Chave\$Nome falhou: $($r.saida)" }
}

# ---------------------------------------------------------------------------
# Opcoes
# ---------------------------------------------------------------------------

function Remove-TmxMicroWinOneDrive {
    <#
    .SYNOPSIS
        Tira o OneDrive da imagem: appx (se houver), o OneDriveSetup.exe e a
        entrada Run do usuario padrao que instala o OneDrive no primeiro logon.
    .OUTPUTS
        [pscustomobject] @{ removidos[]; detalhe }
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $MountPath)

    $removidos = New-Object 'System.Collections.Generic.List[string]'
    $rAppx = Remove-TmxIsoAppx -Path $MountPath -Nomes @('OneDrive')
    foreach ($a in @($rAppx.removidos)) { $removidos.Add("appx:$a") }

    foreach ($rel in @('Windows\System32\OneDriveSetup.exe', 'Windows\SysWOW64\OneDriveSetup.exe')) {
        if (Remove-TmxOfflinePath -Path (Join-Path $MountPath $rel)) { $removidos.Add($rel) }
    }

    $ntuser = Join-Path $MountPath 'Users\Default\NTUSER.DAT'
    if (Test-Path -LiteralPath $ntuser -PathType Leaf) {
        Invoke-TmxOfflineHive -HivePath $ntuser -Nome 'TMX_NTUSER' -Acao {
            param($raiz)
            # Ausente nao e erro: builds mais novas ja nao tem a entrada.
            $r = Invoke-TmxRegExe -Arguments @('delete', "$raiz\Software\Microsoft\Windows\CurrentVersion\Run", '/v', 'OneDriveSetup', '/f')
            if ($r.codigo -eq 0) { $removidos.Add('Run\OneDriveSetup') }
        }
    }

    [pscustomobject]@{ removidos = $removidos.ToArray(); detalhe = ('{0} item(ns) removido(s)' -f $removidos.Count) }
}

function Remove-TmxMicroWinEdge {
    <#
    .SYNOPSIS
        Tira o Microsoft Edge da imagem: appx e as pastas Edge, EdgeUpdate e
        EdgeCore. O EdgeWebView FICA: apps do proprio Windows dependem dele.
    .OUTPUTS
        [pscustomobject] @{ removidos[]; detalhe }
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $MountPath)

    $removidos = New-Object 'System.Collections.Generic.List[string]'
    $rAppx = Remove-TmxIsoAppx -Path $MountPath -Nomes @('MicrosoftEdge')
    foreach ($a in @($rAppx.removidos)) { $removidos.Add("appx:$a") }

    foreach ($rel in @('Program Files (x86)\Microsoft\Edge', 'Program Files (x86)\Microsoft\EdgeUpdate', 'Program Files (x86)\Microsoft\EdgeCore')) {
        if (Remove-TmxOfflinePath -Path (Join-Path $MountPath $rel)) { $removidos.Add($rel) }
    }

    [pscustomobject]@{ removidos = $removidos.ToArray(); detalhe = ('{0} item(ns) removido(s); EdgeWebView mantido' -f $removidos.Count) }
}

function Remove-TmxMicroWinDefender {
    <#
    .SYNOPSIS
        Tira o Windows Defender da imagem: pacotes Windows-Defender e o appx
        da Seguranca do Windows (SecHealthUI). O PC instalado fica sem
        antivirus - a tela avisa em vermelho e pede confirmacao.
    .OUTPUTS
        [pscustomobject] @{ removidos[]; detalhe }
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $MountPath)

    $removidos = New-Object 'System.Collections.Generic.List[string]'
    $rPac = Remove-TmxIsoPackages -Path $MountPath -Nomes @('Windows-Defender')
    foreach ($p in @($rPac.removidos)) { $removidos.Add("pacote:$p") }
    $rAppx = Remove-TmxIsoAppx -Path $MountPath -Nomes @('SecHealthUI')
    foreach ($a in @($rAppx.removidos)) { $removidos.Add("appx:$a") }

    [pscustomobject]@{ removidos = $removidos.ToArray(); detalhe = ('{0} item(ns) removido(s)' -f $removidos.Count) }
}

function Get-TmxMicroWinTelemetryValues {
    <#
    .SYNOPSIS
        Os valores gravados por Set-TmxMicroWinTelemetryOff: { hive; chave; nome; valor }.
        'hive' e SOFTWARE ou SYSTEM; 'chave' e relativa a raiz do hive.
    #>
    [CmdletBinding()]
    param()
    @(
        @{ hive = 'SOFTWARE'; chave = 'Policies\Microsoft\Windows\DataCollection'; nome = 'AllowTelemetry'; valor = 0 },
        @{ hive = 'SOFTWARE'; chave = 'Policies\Microsoft\Windows\DataCollection'; nome = 'DoNotShowFeedbackNotifications'; valor = 1 },
        @{ hive = 'SOFTWARE'; chave = 'Policies\Microsoft\Windows\AdvertisingInfo'; nome = 'DisabledByGroupPolicy'; valor = 1 },
        @{ hive = 'SOFTWARE'; chave = 'Policies\Microsoft\Windows\CloudContent'; nome = 'DisableWindowsConsumerFeatures'; valor = 1 },
        @{ hive = 'SYSTEM';   chave = 'ControlSet001\Services\DiagTrack'; nome = 'Start'; valor = 4 },
        @{ hive = 'SYSTEM';   chave = 'ControlSet001\Services\dmwappushservice'; nome = 'Start'; valor = 4 }
    )
}

function Set-TmxMicroWinTelemetryOff {
    <#
    .SYNOPSIS
        Politicas de telemetria nos hives SOFTWARE e SYSTEM da imagem
        (reg load / reg add / reg unload).
    .OUTPUTS
        [pscustomobject] @{ gravados; detalhe }
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $MountPath)

    $valores = @(Get-TmxMicroWinTelemetryValues)
    $gravados = 0
    foreach ($hive in @('SOFTWARE', 'SYSTEM')) {
        $doHive = @($valores | Where-Object { $_.hive -eq $hive })
        if ($doHive.Count -eq 0) { continue }
        $arquivo = Join-Path $MountPath "Windows\System32\config\$hive"
        # Sem GetNewClosure de proposito: o bloco roda dentro de
        # Invoke-TmxOfflineHive, chamado daqui, e enxerga $doHive pelo escopo
        # dinamico - e continua no escopo do modulo (os mocks o alcancam).
        Invoke-TmxOfflineHive -HivePath $arquivo -Nome "TMX_$hive" -Acao {
            param($raiz)
            foreach ($v in $doHive) {
                Set-TmxOfflineRegDword -Chave "$raiz\$($v.chave)" -Nome $v.nome -Valor ([int]$v.valor)
            }
        }
        $gravados += $doHive.Count
    }

    [pscustomobject]@{ gravados = $gravados; detalhe = ('{0} valor(es) de politica gravado(s)' -f $gravados) }
}
