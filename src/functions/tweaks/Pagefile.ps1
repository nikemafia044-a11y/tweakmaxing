# functions/tweaks/Pagefile.ps1
# JOG-043 (origem CS2Tuner STO-004): arquivo de paginacao com tamanho fixo.
# Porta de Tweaks/Storage.ps1 (STO-004). O pagefile NUNCA e desativado: com
# tamanhoMB <= 0 a funcao se recusa a aplicar.
#
# tamanhoMB vem de $Parametros.tamanhoMB (Actions.ps1 'funcao' passa
# -Parametros = acao.parametros do catalogo). Test-TmxPagefile nao recebe
# -Parametros (contrato Test-Tmx<X> -Tweak -Profile), entao le o mesmo valor
# direto da acao 'funcao' correspondente dentro de $Tweak.acoes.

function Get-TmxPagefileState {
    $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    $pf = @(Get-CimInstance -ClassName Win32_PageFileSetting -ErrorAction SilentlyContinue)
    [pscustomobject]@{
        automatico = [bool]$cs.AutomaticManagedPagefile
        arquivos   = @($pf | ForEach-Object { [pscustomobject]@{ nome = "$($_.Name)"; inicial = [int]$_.InitialSize; maximo = [int]$_.MaximumSize } })
    }
}

function Set-TmxPagefileState {
    param([bool] $Automatico, $Arquivos)
    $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    $cs | Set-CimInstance -Property @{ AutomaticManagedPagefile = $Automatico } -ErrorAction Stop
    if ($Automatico) { return }
    Get-CimInstance -ClassName Win32_PageFileSetting -ErrorAction SilentlyContinue | Remove-CimInstance -ErrorAction SilentlyContinue
    foreach ($a in @($Arquivos)) {
        New-CimInstance -ClassName Win32_PageFileSetting -Property @{ Name = "$($a.nome)"; InitialSize = [uint32]$a.inicial; MaximumSize = [uint32]$a.maximo } -ErrorAction Stop | Out-Null
    }
}

function Get-TmxPagefileParametrosDoTweak {
    # Le parametros.tamanhoMB direto da acao 'funcao' -> Set-TmxPagefile dentro
    # do proprio tweak (usado por Test-TmxPagefile, que nao recebe -Parametros).
    param($Tweak)
    foreach ($a in @($Tweak.acoes)) {
        if ($null -eq $a) { continue }
        if ("$($a.tipo)" -eq 'funcao' -and "$($a.nome)" -eq 'Set-TmxPagefile') { return $a.parametros }
    }
    $null
}

function Test-TmxPagefile {
    [CmdletBinding()]
    param($Tweak, $Profile)

    $par = Get-TmxPagefileParametrosDoTweak -Tweak $Tweak
    $alvoMB = [int](Get-TmxActionProp -Action $par -Nome 'tamanhoMB' -Padrao 0)
    $st = Get-TmxPagefileState
    $resumo = "auto=$($st.automatico); $(@($st.arquivos | ForEach-Object { "$($_.nome) $($_.inicial)-$($_.maximo)" }) -join ', ')"

    if ($alvoMB -le 0) {
        return [pscustomobject]@{ aplicado = $null; atual = $resumo; esperado = $null; detalhe = 'tamanho alvo desconhecido (parametros.tamanhoMB ausente no catalogo)' }
    }

    $ok = (-not $st.automatico) -and ($st.arquivos.Count -eq 1) -and ($st.arquivos[0].inicial -eq $alvoMB) -and ($st.arquivos[0].maximo -eq $alvoMB)
    [pscustomobject]@{ aplicado = $ok; atual = $resumo; esperado = "fixo $alvoMB MB"; detalhe = 'pagefile' }
}

function Set-TmxPagefile {
    [CmdletBinding()]
    param($Tweak, $Profile, $Parametros)

    $alvoMB = [int](Get-TmxActionProp -Action $Parametros -Nome 'tamanhoMB' -Padrao 0)
    if ($alvoMB -le 0) { return [pscustomobject]@{ ok = $false; detalhe = 'tamanho invalido: o pagefile nunca e desativado' } }

    $antes = Get-TmxPagefileState
    $arquivo = "$env:SystemDrive\pagefile.sys"
    $rec = New-TmxCmdletRecord -TweakId "$($Tweak.id)" -Funcao 'Set-TmxPagefile' -Alvo 'arquivo de paginacao' `
            -Estado @{ automatico = $antes.automatico; arquivos = @($antes.arquivos) } `
            -ValorAnterior "auto=$($antes.automatico)" -ValorNovo "$arquivo fixo $alvoMB MB"
    try {
        Set-TmxPagefileState -Automatico $false -Arquivos @([pscustomobject]@{ nome = $arquivo; inicial = $alvoMB; maximo = $alvoMB })
        Complete-TmxStateRecord -Record $rec -Ok $true | Out-Null
        [pscustomobject]@{ ok = $true; detalhe = "pagefile fixo em $alvoMB MB ($arquivo); efetivo apos reboot"; registro = $rec }
    } catch {
        Complete-TmxStateRecord -Record $rec -Ok $false -Erro $_.Exception.Message | Out-Null
        [pscustomobject]@{ ok = $false; detalhe = $_.Exception.Message; registro = $rec }
    }
}

function Undo-TmxPagefile {
    [CmdletBinding()]
    param($Estado)

    if (-not $Estado) { throw 'sem estado: nao da para saber o pagefile anterior' }
    Set-TmxPagefileState -Automatico ([bool]$Estado.automatico) -Arquivos @($Estado.arquivos)
    "pagefile restaurado (automatico=$($Estado.automatico)); efetivo apos reboot"
}
