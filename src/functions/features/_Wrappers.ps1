# functions/features/_Wrappers.ps1
# Fronteira da aba "Configurar" com o mundo externo.
#
# Mesmas regras do functions/tweaks/_Wrappers.ps1: todo executavel e todo
# cmdlet que mexe no sistema passa por um wrapper fino, argumentos sempre em
# array, nada de Write-Host. Os testes mockam o wrapper, nunca o comando real.
#
# Wrappers que JA existem e sao reusados aqui (nao duplicar):
#   Invoke-TmxDism, Invoke-TmxNetsh, Invoke-TmxWinget, Invoke-TmxProcess,
#   Start-TmxUrl, Remove-TmxItemPath, Test-TmxItemPath, Get-TmxActiveNetAdapter,
#   Get-TmxDnsServerAddress, Set-TmxDnsServerAddress, Set-TmxRegistry,
#   Get-/Enable-/Disable-TmxWindowsFeature, Invoke-TmxBcdedit, Get-TmxBcdValue.

# ---------------------------------------------------------------------------
# Executaveis
# ---------------------------------------------------------------------------

function Invoke-TmxRegsvr32 {
    <#
    .SYNOPSIS
        Reregistra uma DLL do system32 em modo silencioso (/s).
    .NOTES
        Sem /s o regsvr32 abre uma caixa de dialogo por DLL - 36 janelas
        modais no meio de um job e a janela travada atras delas.
    #>
    param([Parameter(Mandatory)] [string] $Dll)
    $caminho = Join-Path (Join-Path $env:SystemRoot 'system32') $Dll
    $out = & regsvr32.exe '/s' $caminho 2>&1
    [pscustomobject]@{ saida = (@($out) -join "`n"); codigo = $LASTEXITCODE }
}

function Invoke-TmxSfc {
    param([Parameter(Mandatory)] [string[]] $Arguments)
    $out = & sfc.exe @Arguments 2>&1
    [pscustomobject]@{ saida = (@($out) -join "`n"); codigo = $LASTEXITCODE }
}

function Invoke-TmxW32tm {
    param([Parameter(Mandatory)] [string[]] $Arguments)
    $out = & w32tm.exe @Arguments 2>&1
    [pscustomobject]@{ saida = (@($out) -join "`n"); codigo = $LASTEXITCODE }
}

function Invoke-TmxWuauclt {
    param([Parameter(Mandatory)] [string[]] $Arguments)
    $out = & wuauclt.exe @Arguments 2>&1
    [pscustomobject]@{ saida = (@($out) -join "`n"); codigo = $LASTEXITCODE }
}

function Invoke-TmxUsoClient {
    param([Parameter(Mandatory)] [string[]] $Arguments)
    $out = & UsoClient.exe @Arguments 2>&1
    [pscustomobject]@{ saida = (@($out) -join "`n"); codigo = $LASTEXITCODE }
}

# ---------------------------------------------------------------------------
# Servicos
# ---------------------------------------------------------------------------

function Stop-TmxWindowsService {
    <#
    .SYNOPSIS
        Para um servico. Nunca lanca: um servico ausente/ja parado nao e erro
        numa acao de manutencao.
    .OUTPUTS
        { ok, detalhe }
    #>
    param([Parameter(Mandatory)] [string] $Nome)
    try {
        Stop-Service -Name $Nome -Force -ErrorAction Stop
        [pscustomobject]@{ ok = $true; detalhe = "$Nome parado" }
    } catch {
        [pscustomobject]@{ ok = $false; detalhe = "$Nome : $($_.Exception.Message)" }
    }
}

function Start-TmxWindowsService {
    param([Parameter(Mandatory)] [string] $Nome)
    try {
        Start-Service -Name $Nome -ErrorAction Stop
        [pscustomobject]@{ ok = $true; detalhe = "$Nome iniciado" }
    } catch {
        [pscustomobject]@{ ok = $false; detalhe = "$Nome : $($_.Exception.Message)" }
    }
}

function Set-TmxWindowsServiceStartup {
    param(
        [Parameter(Mandatory)] [string] $Nome,
        [Parameter(Mandatory)] [ValidateSet('Automatic', 'Manual', 'Disabled')] [string] $Tipo
    )
    try {
        Set-Service -Name $Nome -StartupType $Tipo -ErrorAction Stop
        [pscustomobject]@{ ok = $true; detalhe = "$Nome -> $Tipo" }
    } catch {
        [pscustomobject]@{ ok = $false; detalhe = "$Nome : $($_.Exception.Message)" }
    }
}

function Clear-TmxBitsTransfers {
    <#
    .SYNOPSIS
        Apaga todos os trabalhos do BITS (fila do Windows Update).
    #>
    param()
    try {
        Get-BitsTransfer -AllUsers -ErrorAction Stop | Remove-BitsTransfer -ErrorAction Stop
        [pscustomobject]@{ ok = $true; detalhe = 'fila do BITS esvaziada' }
    } catch {
        [pscustomobject]@{ ok = $false; detalhe = $_.Exception.Message }
    }
}

# ---------------------------------------------------------------------------
# Sistema de arquivos (os alvos do reparo do Windows Update)
# ---------------------------------------------------------------------------

function Remove-TmxFilePattern {
    <#
    .SYNOPSIS
        Apaga arquivos por padrao (qmgr*.dat). Silencioso: arquivo em uso ou
        ausente nao invalida o passo.
    #>
    param([Parameter(Mandatory)] [string] $Padrao)
    Remove-Item -Path $Padrao -Force -ErrorAction SilentlyContinue
    [pscustomobject]@{ ok = $true; detalhe = "removido (se existia): $Padrao" }
}

function Rename-TmxPathItem {
    <#
    .SYNOPSIS
        Renomeia uma pasta (SoftwareDistribution\DataStore -> DataStore.bak).
        Devolve ok=$false com o motivo quando o caminho nao existe ou esta em uso.
    #>
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $NovoNome
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{ ok = $true; detalhe = "$Path nao existe; nada a renomear" }
    }
    try {
        Rename-Item -LiteralPath $Path -NewName $NovoNome -Force -ErrorAction Stop
        [pscustomobject]@{ ok = $true; detalhe = "$Path -> $NovoNome" }
    } catch {
        [pscustomobject]@{ ok = $false; detalhe = "$Path : $($_.Exception.Message)" }
    }
}

# ---------------------------------------------------------------------------
# Tarefas agendadas (a tarefa diaria de backup do registro)
# ---------------------------------------------------------------------------

function Test-TmxScheduledTaskExists {
    param(
        [Parameter(Mandatory)] [string] $Nome,
        [string] $Caminho = '\'
    )
    $t = Get-ScheduledTask -TaskName $Nome -TaskPath $Caminho -ErrorAction SilentlyContinue
    [bool]$t
}

function Register-TmxScheduledTaskWrapper {
    <#
    .SYNOPSIS
        Cria (ou substitui) uma tarefa agendada diaria que roda um executavel.
    #>
    param(
        [Parameter(Mandatory)] [string] $Nome,
        [Parameter(Mandatory)] [string] $Executar,
        [string[]] $Argumentos = @(),
        [string]   $Hora = '00:30',
        [string]   $Descricao = '',
        [string]   $Usuario = 'System'
    )
    $acao = if ($Argumentos.Count -gt 0) {
        New-ScheduledTaskAction -Execute $Executar -Argument ($Argumentos -join ' ')
    } else {
        New-ScheduledTaskAction -Execute $Executar
    }
    $gatilho = New-ScheduledTaskTrigger -Daily -At $Hora
    Register-ScheduledTask -TaskName $Nome -Action $acao -Trigger $gatilho `
        -Description $Descricao -User $Usuario -Force -ErrorAction Stop | Out-Null
    $Nome
}

function Unregister-TmxScheduledTaskWrapper {
    param(
        [Parameter(Mandatory)] [string] $Nome,
        [string] $Caminho = '\'
    )
    Unregister-ScheduledTask -TaskName $Nome -TaskPath $Caminho -Confirm:$false -ErrorAction Stop | Out-Null
    $Nome
}

# ---------------------------------------------------------------------------
# Paineis legados
# ---------------------------------------------------------------------------

function Start-TmxPanelProcess {
    <#
    .SYNOPSIS
        Abre um painel do Windows (control, *.cpl, *.msc, shell:::{GUID}).
    .NOTES
        Recebe SEMPRE um comando da tabela fixa de Get-TmxPanelCatalog - nunca
        texto vindo da interface. Quem valida o id e Open-TmxPanel.
    #>
    param([Parameter(Mandatory)] [string] $Comando)
    Start-Process -FilePath $Comando -ErrorAction Stop | Out-Null
    $Comando
}

# ---------------------------------------------------------------------------
# DNS: medicao
# ---------------------------------------------------------------------------

function Measure-TmxDnsQuery {
    <#
    .SYNOPSIS
        Tempo (ms) de UMA consulta DNS a um servidor especifico.
    .OUTPUTS
        O tempo em milissegundos, ou $null quando a consulta falhou/expirou.
    #>
    param(
        [Parameter(Mandatory)] [string] $Servidor,
        [string] $Nome = 'www.microsoft.com'
    )
    $relogio = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        Resolve-DnsName -Name $Nome -Server $Servidor -Type A -DnsOnly `
            -QuickTimeout -ErrorAction Stop | Out-Null
        $relogio.Stop()
        [int]$relogio.ElapsedMilliseconds
    } catch {
        $relogio.Stop()
        $null
    }
}
