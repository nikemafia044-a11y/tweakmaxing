# functions/tweaks/Hibernation.ps1
# ENE-001: hibernacao. O estado anterior vem do registro (HibernateEnabled), nao
# de suposicao: powercfg nao tem "mostre o estado atual" confiavel em todo idioma.

$script:TmxHibernatePath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'

function Test-TmxHibernation {
    [CmdletBinding()]
    param($Tweak, $Profile)

    $v = Get-TmxRegistryValue -Path $script:TmxHibernatePath -Name 'HibernateEnabled'
    if ($null -eq $v) {
        return [pscustomobject]@{ aplicado = $null; atual = $null; esperado = '0'; detalhe = 'HibernateEnabled ausente' }
    }
    [pscustomobject]@{
        aplicado = ([int]$v -eq 0)
        atual    = "$([int]$v)"
        esperado = '0'
        detalhe  = "HibernateEnabled = $([int]$v)"
    }
}

function Set-TmxHibernation {
    [CmdletBinding()]
    param($Tweak, $Profile, $Parametros)

    $antes = Get-TmxRegistryValue -Path $script:TmxHibernatePath -Name 'HibernateEnabled'
    $rec = New-TmxCmdletRecord -TweakId "$($Tweak.id)" -Funcao 'Set-TmxHibernation' -Alvo 'hibernacao do Windows' `
            -Estado @{ hibernateEnabled = $antes } -ValorAnterior $antes -ValorNovo 0

    try {
        $r = Invoke-TmxPowercfg @('/hibernate', 'off')
        if ($r.codigo -ne 0) { throw "powercfg /hibernate off falhou ($($r.codigo)): $($r.saida)" }
        Complete-TmxStateRecord -Record $rec -Ok $true | Out-Null
        [pscustomobject]@{ ok = $true; detalhe = 'hibernacao desativada (hiberfil.sys removido)'; registro = $rec }
    } catch {
        Complete-TmxStateRecord -Record $rec -Ok $false -Erro $_.Exception.Message | Out-Null
        [pscustomobject]@{ ok = $false; detalhe = $_.Exception.Message; registro = $rec }
    }
}

function Undo-TmxHibernation {
    [CmdletBinding()]
    param($Estado)

    $antes = $null
    if ($Estado) { $antes = $Estado.hibernateEnabled }
    $alvo = 'off'
    if ($null -ne $antes -and [int]$antes -ne 0) { $alvo = 'on' }

    $r = Invoke-TmxPowercfg @('/hibernate', $alvo)
    if ($r.codigo -ne 0) { throw "powercfg /hibernate $alvo falhou ($($r.codigo)): $($r.saida)" }
    "hibernacao restaurada para '$alvo'"
}
