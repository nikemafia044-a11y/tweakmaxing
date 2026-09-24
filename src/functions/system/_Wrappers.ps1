# functions/system/_Wrappers.ps1
# Fronteira do item de menu "Sistema" com o mundo externo: CIM, registro,
# Get-PhysicalDisk, servicos, lixeira, HTTP (checagem de atualizacao), P/Invoke
# de ponto de restauracao e o dialogo nativo "Salvar como".
#
# Mesma regra das outras abas: cada chamada externa mora numa funcao fina,
# nunca lanca (devolve $null/colecao vazia/{ok:false} em vez de propagar a
# excecao), para que os testes possam mockar so este arquivo e exercitar de
# verdade a logica que fica em volta (Hardware.ps1, Cleanup.ps1,
# RestorePoints.ps1, AppUpdate.ps1, Maintenance.ps1).

# ---------------------------------------------------------------------------
# JSON de lista (round-trip seguro em disco)
# ---------------------------------------------------------------------------

function ConvertTo-TmxJsonArray {
    <#
    .SYNOPSIS
        ConvertTo-Json que SEMPRE produz um array JSON ('[]', '[{...}]',
        '[{...},{...}]'), mesmo com 0 ou 1 item.
    .DESCRIPTION
        ConvertTo-Json (Windows PowerShell 5.1, sem -AsArray) serializa um
        array de 1 item como um OBJETO JSON solto (sem colchetes) e um array
        de 0 itens como nada (pipeline vazio) - os dois quebrariam o
        round-trip de uma lista persistida em disco (Save-TmxRestoreFakeList).
        Usada so para colecoes pequenas (listas de pontos de restauracao);
        para o restante do app (respostas da ponte) o problema nao existe
        porque o objeto raiz e sempre um hashtable, nunca um array solto.
    #>
    [CmdletBinding()]
    param($Items, [int] $Depth = 6)

    $arr = @($Items)
    if ($arr.Count -eq 0) { return '[]' }
    if ($arr.Count -eq 1) { return ('[' + ($arr[0] | ConvertTo-Json -Depth $Depth) + ']') }
    ($arr | ConvertTo-Json -Depth $Depth)
}

# ---------------------------------------------------------------------------
# CIM / registro
# ---------------------------------------------------------------------------

function Get-TmxCimSafe {
    <#
    .SYNOPSIS
        Get-CimInstance que nunca lanca. Devolve sempre um array (vazio em
        caso de falha).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $ClassName,
        [string] $Namespace = 'root\cimv2',
        [string] $Filter,
        [int] $TimeoutSec = 10
    )
    # WMI travado nao pode prender o Painel: OperationTimeoutSec encerra a consulta.
    try {
        $params = @{ ClassName = $ClassName; Namespace = $Namespace; OperationTimeoutSec = $TimeoutSec; ErrorAction = 'Stop' }
        if ($Filter) { $params.Filter = $Filter }
        @(Get-CimInstance @params)
    } catch {
        Write-TmxLog -Level WARN -Message "Get-CimInstance falhou para '$ClassName': $($_.Exception.Message)"
        @()
    }
}

function Get-TmxItemPropertySafe {
    <#
    .SYNOPSIS
        Valor de UMA propriedade do registro, ou $null se a chave/valor nao
        existir. Preserva o tipo original (int64 para QWORD, byte[] para
        Binary) - quem chama decide como converter.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Name
    )
    try {
        $obj = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop
        $v = $obj.$Name
        # Virgula: sem ela um byte[] (Binary) ou string[] (MultiString) sai
        # desenrolado no pipeline e chega a quem chama como object[].
        if ($v -is [array]) { , $v } else { $v }
    } catch {
        $null
    }
}

function Test-TmxRegistryValueExists {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Name
    )
    try {
        $obj = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop
        $null -ne $obj.$Name
    } catch {
        $false
    }
}

function Get-TmxRegistryChildNamesSafe {
    <#
    .SYNOPSIS
        Nomes das subchaves imediatas de $Path (ex.: '0000', '0001', ...).
        Nunca lanca; array vazio quando a chave nao existe.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)
    # SilentlyContinue e nao Stop: em Control\Class\{...} a subchave
    # 'Properties' nega acesso a usuario comum, e com Stop essa unica negacao
    # derrubava a enumeracao inteira (VRAM caia no AdapterRAM de 32 bits = 4 GB).
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    @(Get-ChildItem -LiteralPath $Path -ErrorAction SilentlyContinue | ForEach-Object { $_.PSChildName })
}

# ---------------------------------------------------------------------------
# Disco
# ---------------------------------------------------------------------------

function Get-TmxPhysicalDisksSafe {
    [CmdletBinding()]
    param()
    try { @(Get-PhysicalDisk -ErrorAction Stop) } catch { @() }
}

function Get-TmxPartitionSafe {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $DriveLetter)
    try { Get-Partition -DriveLetter $DriveLetter -ErrorAction Stop } catch { $null }
}

function Get-TmxDiskFromPartitionSafe {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Partition)
    try { $Partition | Get-Disk -ErrorAction Stop } catch { $null }
}

# ---------------------------------------------------------------------------
# Servicos (usado por cleanup.run no item wu-cache)
# ---------------------------------------------------------------------------

function Stop-TmxServiceSafe {
    <#
    .SYNOPSIS
        Para um servico. Devolve $true so quando ESTE chamado parou o servico
        (para que quem chamou saiba se precisa religar depois); $false quando
        o servico ja estava parado, nao existe, ou a parada falhou.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Name)
    try {
        $svc = Get-Service -Name $Name -ErrorAction Stop
        if ($svc.Status -eq 'Stopped') { return $false }
        Stop-Service -Name $Name -Force -ErrorAction Stop
        $true
    } catch {
        Write-TmxLog -Level WARN -Message "Nao foi possivel parar o servico '$Name': $($_.Exception.Message)"
        $false
    }
}

function Start-TmxServiceSafe {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Name)
    try {
        Start-Service -Name $Name -ErrorAction Stop
        $true
    } catch {
        Write-TmxLog -Level WARN -Message "Nao foi possivel iniciar o servico '$Name': $($_.Exception.Message)"
        $false
    }
}

# ---------------------------------------------------------------------------
# Arquivos (limpeza)
# ---------------------------------------------------------------------------

function Remove-TmxFileSafe {
    <#
    .SYNOPSIS
        Apaga UM arquivo. Nunca lanca: { ok, locked, bytes }. 'locked' cobre
        qualquer falha na exclusao (arquivo em uso, permissao negada, etc.) -
        quem chama so precisa contar como pulado.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)
    try {
        $item = Get-Item -LiteralPath $Path -ErrorAction Stop
        $tamanho = [int64]$item.Length
        Remove-Item -LiteralPath $Path -Force -ErrorAction Stop -WhatIf:$false
        @{ ok = $true; locked = $false; bytes = $tamanho }
    } catch {
        @{ ok = $false; locked = $true; bytes = 0L; erro = $_.Exception.Message }
    }
}

function Get-TmxRecycleBinSizeSafe {
    <#
    .SYNOPSIS
        Tamanho total e numero de itens na Lixeira, somando os arquivos reais
        dentro de $Recycle.Bin\<SID> em cada unidade fixa. Nunca lanca.
    .DESCRIPTION
        Cada item apagado vira um par $Ixxxx (metadado, poucos bytes) e
        $Rxxxx (conteudo) dentro de $Recycle.Bin - o total soma os dois; o
        numero de itens conta so os $R* (o conteudo de fato). Exige acesso de
        leitura as pastas $Recycle.Bin\<SID> de outros usuarios quando a
        maquina tem mais de uma conta - normalmente disponivel so elevado.
    #>
    [CmdletBinding()]
    param()
    try {
        $bytes = 0L
        $itens = 0
        foreach ($unidade in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
            $bin = Join-Path "$($unidade.Root)" '$Recycle.Bin'
            if (-not (Test-Path -LiteralPath $bin)) { continue }
            $arquivos = @(Get-ChildItem -LiteralPath $bin -Recurse -File -Force -ErrorAction SilentlyContinue |
                Where-Object { "$($_.Name)" -ne 'desktop.ini' })
            foreach ($f in $arquivos) {
                $bytes += [int64]$f.Length
                if ("$($f.Name)".StartsWith('$R')) { $itens++ }
            }
        }
        @{ bytes = [int64]$bytes; itens = [int]$itens }
    } catch {
        Write-TmxLog -Level WARN -Message "Falha ao medir a Lixeira: $($_.Exception.Message)"
        @{ bytes = 0L; itens = 0 }
    }
}

function Invoke-TmxClearRecycleBinSafe {
    [CmdletBinding()]
    param()
    try {
        Clear-RecycleBin -Force -ErrorAction Stop -WhatIf:$false
        $true
    } catch {
        Write-TmxLog -Level WARN -Message "Falha ao esvaziar a Lixeira: $($_.Exception.Message)"
        $false
    }
}

# ---------------------------------------------------------------------------
# HTTP (app.checkUpdate)
# ---------------------------------------------------------------------------

function Invoke-TmxHttpGetSafe {
    <#
    .SYNOPSIS
        GET simples com TLS 1.2 forcado e tempo limite curto. Nunca lanca.
    .OUTPUTS
        { ok; statusCode; content; erro }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Uri,
        [int] $TimeoutSeconds = 8
    )
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $resp = Invoke-WebRequest -Uri $Uri -UseBasicParsing -TimeoutSec $TimeoutSeconds `
            -Headers @{ 'User-Agent' = 'TweakMaxing' } -ErrorAction Stop
        @{ ok = $true; statusCode = [int]$resp.StatusCode; content = "$($resp.Content)"; erro = $null }
    } catch {
        @{ ok = $false; statusCode = 0; content = $null; erro = $_.Exception.Message }
    }
}

# ---------------------------------------------------------------------------
# Conta do Windows (settings.windowsName)
# ---------------------------------------------------------------------------

function Get-TmxWindowsUserAccountSafe {
    <#
    .SYNOPSIS
        Win32_UserAccount do usuario atual (Name = $env:USERNAME), ou $null.
    #>
    [CmdletBinding()]
    param()
    try {
        $usuario = "$env:USERNAME" -replace "'", "''"
        $computador = "$env:COMPUTERNAME" -replace "'", "''"
        $conta = Get-CimInstance -ClassName Win32_UserAccount `
            -Filter "Name='$usuario' AND Domain='$computador'" -OperationTimeoutSec 10 -ErrorAction Stop |
            Select-Object -First 1
        if (-not $conta) {
            $conta = Get-CimInstance -ClassName Win32_UserAccount -Filter "Name='$usuario'" -OperationTimeoutSec 10 -ErrorAction Stop |
                Select-Object -First 1
        }
        $conta
    } catch {
        $null
    }
}

# ---------------------------------------------------------------------------
# Ponto de restauracao: P/Invoke (SRRemoveRestorePoint) e WMI (Restore)
# ---------------------------------------------------------------------------

function Get-TmxRestoreNativeSource {
    <#
    .SYNOPSIS
        Fonte C# do P/Invoke de srclient.dll. Funcao (nao $script:) para que
        o texto atravesse para a runspace do pool sem precisar entrar na
        lista de permissao de Start-TmxJob.ps1 - qualquer funcao cujo nome
        bate '-Tmx' e copiada automaticamente.
    #>
    [CmdletBinding()]
    param()
    @'
using System;
using System.Runtime.InteropServices;

namespace TweakMaxing
{
    public static class RestorePointNative
    {
        [DllImport("srclient.dll", CharSet = CharSet.Auto)]
        public static extern int SRRemoveRestorePoint(int index);
    }
}
'@
}

function Initialize-TmxRestoreNativeTypes {
    <#
    .SYNOPSIS
        Compila o tipo TweakMaxing.RestorePointNative (uma vez por sessao).
        Nunca lanca.
    #>
    [CmdletBinding()]
    param()
    if (([System.Management.Automation.PSTypeName] 'TweakMaxing.RestorePointNative').Type) { return $true }
    try {
        Add-Type -TypeDefinition (Get-TmxRestoreNativeSource) -ErrorAction Stop
        $true
    } catch {
        Write-TmxLog -Level WARN -Message "Falha ao compilar o P/Invoke de restauracao: $($_.Exception.Message)"
        $false
    }
}

function Remove-TmxRestorePointNative {
    <#
    .SYNOPSIS
        Wrapper de SRRemoveRestorePoint(index). codigo 0 = sucesso.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [int] $Sequence)
    if (-not (Initialize-TmxRestoreNativeTypes)) { return @{ ok = $false; codigo = -1 } }
    try {
        $codigo = [TweakMaxing.RestorePointNative]::SRRemoveRestorePoint($Sequence)
        @{ ok = ($codigo -eq 0); codigo = [int]$codigo }
    } catch {
        Write-TmxLog -Level WARN -Message "SRRemoveRestorePoint falhou: $($_.Exception.Message)"
        @{ ok = $false; codigo = -1 }
    }
}

function Invoke-TmxSystemRestoreWmi {
    <#
    .SYNOPSIS
        Wrapper de root\default:SystemRestore.Restore(SequenceNumber). Nao
        reinicia o computador - so agenda a restauracao para o proximo boot.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [int] $Sequence)
    try {
        $resultado = Invoke-CimMethod -Namespace 'root\default' -ClassName 'SystemRestore' `
            -MethodName 'Restore' -Arguments @{ SequenceNumber = $Sequence } -OperationTimeoutSec 60 -ErrorAction Stop
        $rc = [int]$resultado.ReturnValue
        $erro = $null
        if ($rc -ne 0) { $erro = "codigo de retorno $rc" }
        @{ ok = ($rc -eq 0); codigo = $rc; erro = $erro }
    } catch {
        @{ ok = $false; codigo = -1; erro = $_.Exception.Message }
    }
}

# ---------------------------------------------------------------------------
# Pasta (app.openLogs) e dialogo nativo "Salvar como" (shell.saveFile)
# ---------------------------------------------------------------------------

function Open-TmxFolderSafe {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)
    try {
        Start-Process -FilePath 'explorer.exe' -ArgumentList @("`"$Path`"") | Out-Null
        $true
    } catch {
        Write-TmxLog -Level WARN -Message "Nao foi possivel abrir a pasta '$Path': $($_.Exception.Message)"
        $false
    }
}

function Show-TmxSaveFileDialog {
    <#
    .SYNOPSIS
        Dialogo nativo "Salvar como"; devolve o caminho escolhido, ou $null
        se cancelado.
    .DESCRIPTION
        Mesmo padrao de Show-TmxOpenFileDialog (functions/ui/Dialogs.ps1):
        Microsoft.Win32.SaveFileDialog (WPF), rodando via Dispatcher quando ja
        existe janela; direto (mesma thread) quando nao existe (testes, modo
        sem UI). Definida aqui (nao em ui/Dialogs.ps1) porque shell.saveFile
        pertence a este arquivo de acoes.
    #>
    [CmdletBinding()]
    param(
        [string] $NomeSugerido = '',
        [string] $Filtro = 'Todos os arquivos (*.*)|*.*',
        [string] $Titulo = 'Salvar como'
    )

    Initialize-TmxWpf

    $salvar = {
        $dlg = New-Object Microsoft.Win32.SaveFileDialog
        $dlg.FileName = $NomeSugerido
        $dlg.Filter   = $Filtro
        $dlg.Title    = $Titulo
        if ($dlg.ShowDialog()) { return "$($dlg.FileName)" }
        $null
    }.GetNewClosure()

    if ($null -ne $sync -and $null -ne $sync.window) {
        return $sync.window.Dispatcher.Invoke([Func[object]] $salvar)
    }
    & $salvar
}
