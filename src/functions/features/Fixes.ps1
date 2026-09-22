# functions/features/Fixes.ps1
# Correcoes de manutencao da aba "Configurar".
#
# Diferenca importante para os tweaks: uma correcao NAO e reversivel por
# desenho - resetar a pilha de rede ou reconstruir a fila do Windows Update
# nao tem "estado anterior" para guardar. Por isso nada aqui cria registro de
# estado, COM UMA EXCECAO: escritas de registro passam por Set-TmxRegistry,
# que registra o valor anterior sozinho. Essas correcoes exigem sessao ativa.
#
# Contrato comum: { ok, detalhe, passos[] { nome, ok, saida } }.

function New-TmxFixStep {
    <#
    .SYNOPSIS
        Um passo do relatorio de uma correcao.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Nome,
        [bool]   $Ok = $true,
        [string] $Saida = ''
    )
    [pscustomobject]@{ nome = $Nome; ok = $Ok; saida = "$Saida" }
}

function New-TmxFixResult {
    <#
    .SYNOPSIS
        Fecha uma correcao: ok=$true so quando nenhum passo falhou.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Passos,
        [string] $Detalhe
    )
    $arr    = @($Passos)
    $falhas = @($arr | Where-Object { -not $_.ok })
    $ok     = ($falhas.Count -eq 0)
    if (-not $Detalhe) {
        $Detalhe = if ($ok) { "$($arr.Count) passo(s) concluido(s)" } else { "$($falhas.Count) de $($arr.Count) passo(s) falharam" }
    }
    [pscustomobject]@{ ok = $ok; detalhe = $Detalhe; passos = $arr }
}

function Send-TmxFixProgress {
    # Progresso opcional: fora de um job o Send-TmxJobProgress e inofensivo.
    param([int] $Pct, [string] $Status)
    if (Get-Command -Name 'Send-TmxJobProgress' -ErrorAction SilentlyContinue) {
        Send-TmxJobProgress -Pct $Pct -Status $Status
    }
}

# ---------------------------------------------------------------------------
# Rede
# ---------------------------------------------------------------------------

function Invoke-TmxFixNetwork {
    <#
    .SYNOPSIS
        Reset da pilha de rede: netsh winsock reset + netsh int ip reset.
    .NOTES
        Porta de reference/winutil/functions/public/Invoke-WPFFixesNetwork.ps1.
        Exige reinicio para valer; nao ha reversao (e o proprio reset ao padrao).
    #>
    [CmdletBinding()]
    param()

    $passos = New-Object 'System.Collections.Generic.List[object]'

    Send-TmxFixProgress -Pct 20 -Status 'Resetando o Winsock...'
    $r1 = Invoke-TmxNetsh @('winsock', 'reset')
    $passos.Add((New-TmxFixStep -Nome 'netsh winsock reset' -Ok ($r1.codigo -eq 0) -Saida "$($r1.saida)"))

    Send-TmxFixProgress -Pct 70 -Status 'Resetando a pilha IP...'
    $r2 = Invoke-TmxNetsh @('int', 'ip', 'reset')
    $passos.Add((New-TmxFixStep -Nome 'netsh int ip reset' -Ok ($r2.codigo -eq 0) -Saida "$($r2.saida)"))

    Send-TmxFixProgress -Pct 100 -Status 'Concluido'
    New-TmxFixResult -Passos $passos.ToArray() -Detalhe 'Configuracao de rede resetada. Reinicie o computador para concluir.'
}

# ---------------------------------------------------------------------------
# winget
# ---------------------------------------------------------------------------

function Invoke-TmxFixWinget {
    <#
    .SYNOPSIS
        Reinstala/repara o winget pelo modulo Microsoft.WinGet.Client.
    .NOTES
        O WinUtil chama 'choco install winget'; aqui reusamos Install-TmxWinget
        -Force, que ja e o caminho testado da aba Instalar.
    #>
    [CmdletBinding()]
    param()

    Send-TmxFixProgress -Pct 30 -Status 'Reinstalando o winget...'
    $r = Install-TmxWinget -Force
    $passo = New-TmxFixStep -Nome 'Install-TmxWinget -Force' -Ok ([bool]$r.ok) -Saida "$($r.detalhe)"
    Send-TmxFixProgress -Pct 100 -Status 'Concluido'
    New-TmxFixResult -Passos @($passo) -Detalhe "$($r.detalhe)"
}

# ---------------------------------------------------------------------------
# Windows Update
# ---------------------------------------------------------------------------

$script:TmxFixUpdateServicos = @('BITS', 'wuauserv', 'appidsvc', 'cryptsvc')

$script:TmxFixUpdateDlls = @(
    'atl.dll', 'urlmon.dll', 'mshtml.dll', 'shdocvw.dll', 'browseui.dll',
    'jscript.dll', 'vbscript.dll', 'scrrun.dll', 'msxml.dll', 'msxml3.dll',
    'msxml6.dll', 'actxprxy.dll', 'softpub.dll', 'wintrust.dll', 'dssenh.dll',
    'rsaenh.dll', 'gpkcsp.dll', 'sccbase.dll', 'slbcsp.dll', 'cryptdlg.dll',
    'oleaut32.dll', 'ole32.dll', 'shell32.dll', 'initpki.dll', 'wuapi.dll',
    'wuaueng.dll', 'wuaueng1.dll', 'wucltui.dll', 'wups.dll', 'wups2.dll',
    'wuweb.dll', 'qmgr.dll', 'qmgrprxy.dll', 'wucltux.dll', 'muweb.dll', 'wuwebv.dll'
)

# Valores do cliente WSUS. Removidos por Set-TmxRegistry (com registro do
# valor anterior), nao por Remove-ItemProperty direto: e o unico jeito de o
# Undo-TweakMaxing conseguir recolocar a maquina num dominio WSUS.
$script:TmxFixUpdateWsusValores = @('AccountDomainSid', 'PingID', 'SusClientId')

function Invoke-TmxFixUpdate {
    <#
    .SYNOPSIS
        Reconstroi a fila do Windows Update (porta de Invoke-WPFFixesUpdate).
    .DESCRIPTION
        Passos, nesta ordem:
          1. parar-servicos       BITS, wuauserv, appidsvc, cryptsvc
          2. remover-qmgr         qmgr*.dat (fila do BITS)
          3. renomear-softwaredistribution   SO com -Aggressive
          4. remover-log          %SystemRoot%\WindowsUpdate.log
          5. reregistrar-dlls     regsvr32 /s nas DLLs de BITS/WU
          6. remover-wsus         valores de cliente WSUS (via Set-TmxRegistry)
          7. winsock-reset
          8. limpar-bits          apaga os trabalhos do BITS
          9. iniciar-servicos     startup Manual + start
         10. forcar-deteccao      wuauclt /resetauthorization /detectnow + UsoClient StartScan
    .PARAMETER Aggressive
        Acrescenta o passo 3 (renomeia DataStore e catroot2). E o passo caro e
        o unico que pode custar o historico de atualizacoes.
    .PARAMETER RegistryPath
        Chave do cliente WSUS. Existe para os testes apontarem para HKCU.
    #>
    [CmdletBinding()]
    param(
        [switch] $Aggressive,
        [string] $RegistryPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate'
    )

    $passos = New-Object 'System.Collections.Generic.List[object]'

    # 1. parar servicos
    Send-TmxFixProgress -Pct 5 -Status 'Parando os servicos do Windows Update...'
    $det = New-Object 'System.Collections.Generic.List[string]'
    $okServicos = $true
    foreach ($s in $script:TmxFixUpdateServicos) {
        $r = Stop-TmxWindowsService -Nome $s
        $det.Add("$($r.detalhe)")
        if (-not $r.ok) { $okServicos = $false }
    }
    $passos.Add((New-TmxFixStep -Nome 'parar-servicos' -Ok $okServicos -Saida ($det.ToArray() -join '; ')))

    # 2. qmgr*.dat
    Send-TmxFixProgress -Pct 15 -Status 'Removendo a fila do BITS (qmgr*.dat)...'
    $qmgr = Join-Path "$env:ALLUSERSPROFILE" 'Application Data\Microsoft\Network\Downloader\qmgr*.dat'
    $r = Remove-TmxFilePattern -Padrao $qmgr
    $passos.Add((New-TmxFixStep -Nome 'remover-qmgr' -Ok ([bool]$r.ok) -Saida "$($r.detalhe)"))

    # 3. renomear SoftwareDistribution/catroot2 (so agressivo)
    if ($Aggressive) {
        Send-TmxFixProgress -Pct 25 -Status 'Renomeando SoftwareDistribution e catroot2...'
        $det = New-Object 'System.Collections.Generic.List[string]'
        $okRename = $true
        foreach ($alvo in @(
            @{ path = (Join-Path "$env:SystemRoot" 'SoftwareDistribution\DataStore'); novo = 'DataStore.bak' },
            @{ path = (Join-Path "$env:SystemRoot" 'SoftwareDistribution\Download');  novo = 'Download.bak' },
            @{ path = (Join-Path "$env:SystemRoot" 'System32\catroot2');              novo = 'catroot2.bak' }
        )) {
            $rr = Rename-TmxPathItem -Path $alvo.path -NovoNome $alvo.novo
            $det.Add("$($rr.detalhe)")
            if (-not $rr.ok) { $okRename = $false }
        }
        $passos.Add((New-TmxFixStep -Nome 'renomear-softwaredistribution' -Ok $okRename -Saida ($det.ToArray() -join '; ')))
    }

    # 4. WindowsUpdate.log
    Send-TmxFixProgress -Pct 35 -Status 'Removendo o WindowsUpdate.log antigo...'
    $r = Remove-TmxFilePattern -Padrao (Join-Path "$env:SystemRoot" 'WindowsUpdate.log')
    $passos.Add((New-TmxFixStep -Nome 'remover-log' -Ok ([bool]$r.ok) -Saida "$($r.detalhe)"))

    # 5. DLLs
    Send-TmxFixProgress -Pct 45 -Status 'Reregistrando as DLLs do BITS e do Windows Update...'
    $falhasDll = New-Object 'System.Collections.Generic.List[string]'
    foreach ($dll in $script:TmxFixUpdateDlls) {
        $rr = Invoke-TmxRegsvr32 -Dll $dll
        if ($rr.codigo -ne 0) { $falhasDll.Add($dll) }
    }
    $passos.Add((New-TmxFixStep -Nome 'reregistrar-dlls' -Ok $true `
        -Saida "$($script:TmxFixUpdateDlls.Count) DLL(s); sem registro: $(if ($falhasDll.Count -gt 0) { $falhasDll.ToArray() -join ', ' } else { 'nenhuma' })"))

    # 6. cliente WSUS (registro -> tem reversao)
    Send-TmxFixProgress -Pct 60 -Status 'Removendo as configuracoes de cliente WSUS...'
    $det = New-Object 'System.Collections.Generic.List[string]'
    $okWsus = $true
    foreach ($nome in $script:TmxFixUpdateWsusValores) {
        try {
            $rec = Set-TmxRegistry -Path $RegistryPath -Name $nome -Remove -TweakId 'FIX-UPDATE' -PassThru
            $st = "$($rec.status)"
            $det.Add("$nome : $st")
            if ($st -eq 'falha') { $okWsus = $false }
        } catch {
            $det.Add("$nome : $($_.Exception.Message)")
            $okWsus = $false
        }
    }
    $passos.Add((New-TmxFixStep -Nome 'remover-wsus' -Ok $okWsus -Saida ($det.ToArray() -join '; ')))

    # 7. winsock
    Send-TmxFixProgress -Pct 70 -Status 'Resetando o Winsock...'
    $r = Invoke-TmxNetsh @('winsock', 'reset')
    $passos.Add((New-TmxFixStep -Nome 'winsock-reset' -Ok ($r.codigo -eq 0) -Saida "$($r.saida)"))

    # 8. BITS
    Send-TmxFixProgress -Pct 78 -Status 'Apagando os trabalhos do BITS...'
    $r = Clear-TmxBitsTransfers
    $passos.Add((New-TmxFixStep -Nome 'limpar-bits' -Ok ([bool]$r.ok) -Saida "$($r.detalhe)"))

    # 9. religar servicos
    Send-TmxFixProgress -Pct 88 -Status 'Religando os servicos do Windows Update...'
    $det = New-Object 'System.Collections.Generic.List[string]'
    $okUp = $true
    foreach ($s in $script:TmxFixUpdateServicos) {
        $r1 = Set-TmxWindowsServiceStartup -Nome $s -Tipo 'Manual'
        $r2 = Start-TmxWindowsService -Nome $s
        $det.Add("$($r1.detalhe) / $($r2.detalhe)")
        if (-not $r2.ok) { $okUp = $false }
    }
    $passos.Add((New-TmxFixStep -Nome 'iniciar-servicos' -Ok $okUp -Saida ($det.ToArray() -join '; ')))

    # 10. forcar deteccao
    Send-TmxFixProgress -Pct 96 -Status 'Forcando a procura por atualizacoes...'
    $r1 = Invoke-TmxWuauclt @('/resetauthorization', '/detectnow')
    $r2 = Invoke-TmxUsoClient @('StartScan')
    $passos.Add((New-TmxFixStep -Nome 'forcar-deteccao' -Ok $true -Saida "wuauclt: $($r1.codigo); UsoClient: $($r2.codigo)"))

    Send-TmxFixProgress -Pct 100 -Status 'Concluido'
    New-TmxFixResult -Passos $passos.ToArray() -Detalhe 'Windows Update reconstruido. Reinicie o computador antes de procurar atualizacoes.'
}

# ---------------------------------------------------------------------------
# Verificacao de integridade do sistema
# ---------------------------------------------------------------------------

function Invoke-TmxFixSystemRepair {
    <#
    .SYNOPSIS
        DISM /RestoreHealth e depois sfc /scannow.
    .NOTES
        Nesta ordem de proposito: o sfc repara arquivos usando a imagem de
        componentes, entao consertar a imagem primeiro evita um sfc que
        encontra corrupcao e nao consegue corrigir. Leva varios minutos.
    #>
    [CmdletBinding()]
    param()

    $passos = New-Object 'System.Collections.Generic.List[object]'

    Send-TmxFixProgress -Pct 5 -Status 'DISM: reparando a imagem do Windows (pode levar varios minutos)...'
    $r1 = Invoke-TmxDism @('/Online', '/Cleanup-Image', '/RestoreHealth')
    # 3010 = reparado, precisa reiniciar.
    $ok1 = ($r1.codigo -eq 0 -or $r1.codigo -eq 3010)
    $passos.Add((New-TmxFixStep -Nome 'dism-restorehealth' -Ok $ok1 -Saida "codigo $($r1.codigo)`n$($r1.saida)"))

    Send-TmxFixProgress -Pct 55 -Status 'SFC: verificando os arquivos protegidos do sistema...'
    $r2 = Invoke-TmxSfc @('/scannow')
    $passos.Add((New-TmxFixStep -Nome 'sfc-scannow' -Ok ($r2.codigo -eq 0) -Saida "codigo $($r2.codigo)`n$($r2.saida)"))

    Send-TmxFixProgress -Pct 100 -Status 'Concluido'
    New-TmxFixResult -Passos $passos.ToArray()
}

# ---------------------------------------------------------------------------
# NTP
# ---------------------------------------------------------------------------

function Invoke-TmxFixNtp {
    <#
    .SYNOPSIS
        Troca o servidor de horario padrao (time.windows.com) por pool.ntp.org.
    .DESCRIPTION
        O registro e escrito ANTES do w32tm /config de proposito: o proprio
        w32tm grava NtpServer, entao ler o valor depois dele ja devolveria o
        valor novo e a reversao perderia o servidor original.
    .PARAMETER RegistryPath
        Chave dos parametros do W32Time. Existe para os testes apontarem para HKCU.
    #>
    [CmdletBinding()]
    param(
        [string] $Servidor = 'pool.ntp.org',
        [string] $RegistryPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters'
    )

    $passos = New-Object 'System.Collections.Generic.List[object]'
    $valor  = "$Servidor,0x8"

    Send-TmxFixProgress -Pct 15 -Status 'Guardando o servidor de horario atual...'
    try {
        $rec = Set-TmxRegistry -Path $RegistryPath -Name 'NtpServer' -Value $valor -Type 'String' -TweakId 'FIX-NTP' -PassThru
        $anterior = if ($rec -and $rec.existiaAntes) { "$($rec.valorAnterior)" } else { '<ausente>' }
        $passos.Add((New-TmxFixStep -Nome 'registrar-ntpserver' -Ok ("$($rec.status)" -eq 'aplicado') -Saida "NtpServer: $anterior -> $valor"))
    } catch {
        $passos.Add((New-TmxFixStep -Nome 'registrar-ntpserver' -Ok $false -Saida $_.Exception.Message))
    }

    Send-TmxFixProgress -Pct 50 -Status 'Configurando o w32time...'
    $r1 = Invoke-TmxW32tm @('/config', "/manualpeerlist:$valor", '/syncfromflags:manual', '/update')
    $passos.Add((New-TmxFixStep -Nome 'w32tm-config' -Ok ($r1.codigo -eq 0) -Saida "$($r1.saida)"))

    Send-TmxFixProgress -Pct 80 -Status 'Sincronizando o relogio...'
    $r2 = Invoke-TmxW32tm @('/resync')
    # O /resync falha quando o servico esta parado ou a rede caiu; nao invalida
    # a troca do servidor, que e o objetivo da correcao.
    $passos.Add((New-TmxFixStep -Nome 'w32tm-resync' -Ok ($r2.codigo -eq 0) -Saida "$($r2.saida)"))

    Send-TmxFixProgress -Pct 100 -Status 'Concluido'
    New-TmxFixResult -Passos $passos.ToArray() -Detalhe "Servidor de horario: $Servidor"
}

# ---------------------------------------------------------------------------
# AutoLogon
# ---------------------------------------------------------------------------

function Invoke-TmxFixAutoLogon {
    <#
    .SYNOPSIS
        Abre a pagina oficial do Autologon (Sysinternals) no navegador.
    .NOTES
        O WinUtil baixa e executa Autologon.exe de live.sysinternals.com. O
        TweakMaxing nao baixa nem executa binario de terceiro: abrimos a pagina
        da Microsoft e quem decide baixar e o usuario.
    #>
    [CmdletBinding()]
    param()

    $url = 'https://learn.microsoft.com/sysinternals/downloads/autologon'
    try {
        Start-TmxUrl -Url $url | Out-Null
        $passo = New-TmxFixStep -Nome 'abrir-pagina-autologon' -Ok $true -Saida $url
    } catch {
        $passo = New-TmxFixStep -Nome 'abrir-pagina-autologon' -Ok $false -Saida $_.Exception.Message
    }
    New-TmxFixResult -Passos @($passo) -Detalhe 'O TweakMaxing nao baixa executaveis: a pagina oficial do Autologon foi aberta no navegador.'
}
