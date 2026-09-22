# functions/tweaks/GpuMsi.ps1
# JOG-013 (origem CS2Tuner CPU-006): modo MSI + DevicePriority alta para a GPU.
# Porta de Tweaks/CpuScheduling.ps1 (CPU-006).
#
# Seguranca do MSI: so aplica se o driver ja criou a chave
# MessageSignaledInterruptProperties (declarando suporte). Sem ela: naoAplicavel.
# Forcar MSI num dispositivo sem suporte pode deixar o Windows sem video.
# Backup .reg obrigatorio da chave Interrupt Management antes de escrever.
#
# As duas escritas (MSISupported, DevicePriority) passam por Set-TmxRegistry,
# entao os registros de estado sao do tipo 'registry' (nao 'cmdlet') e a
# reversao de fato acontece pelos handlers de registro do Core/Rollback.ps1.
# Undo-TmxGpuMsi so existe para completar o trio Set-/Undo-/Test- exigido pelo
# validador do catalogo (Test-TmxAcaoList em Engine/Catalog.ps1).

# Padrao de producao. Mutavel apenas por Set-TmxEnumRoot (hook de teste), o
# que a tira da lista de constantes copiadas para uma runspace nova
# (New-TmxSessionState): dentro do pool ela chega $null e Get-TmxEnumRoot
# devolve este mesmo padrao.
$script:TmxEnumRootPadrao = 'HKLM:\SYSTEM\CurrentControlSet\Enum'
$script:TmxEnumRoot       = $script:TmxEnumRootPadrao

function Get-TmxEnumRoot {
    <#
    .SYNOPSIS
        Raiz Enum em uso: a redirecionada por Set-TmxEnumRoot, ou o padrao.
    .NOTES
        Nunca leia $script:TmxEnumRoot direto: numa runspace do pool (onde as
        funcoes chegam sem as variaveis de escopo de script mutaveis) ele e
        $null, e um Join-Path com $null lanca.
    #>
    [CmdletBinding()]
    param()
    if ($script:TmxEnumRoot) { return $script:TmxEnumRoot }
    $script:TmxEnumRootPadrao
}

function Set-TmxEnumRoot {
    <#
    .SYNOPSIS
        Hook de teste: redireciona a raiz Enum usada para achar a chave da GPU
        (padrao HKLM:\SYSTEM\CurrentControlSet\Enum).
    .NOTES
        So tem efeito com $env:TWEAKMAXING_TEST_HOOKS -eq '1'. Sem essa variavel
        (o caso normal, fora dos testes), lanca - ninguem deve conseguir
        redirecionar a raiz do registro que Set-TmxGpuMsi escreve fora de um
        ambiente de teste que ligou o hook de proposito.
    #>
    param([Parameter(Mandatory)] [string] $Path)
    if ($env:TWEAKMAXING_TEST_HOOKS -ne '1') { throw 'hook de teste desabilitado' }
    $script:TmxEnumRoot = $Path
}

function Get-TmxGpuDeviceKey {
    <#
    .SYNOPSIS
        Chave do dispositivo da GPU principal (dedicada, com pnpId) sob Enum.
    #>
    param([Parameter(Mandatory)] $Profile)
    $gpu = @($Profile.gpu.adaptadores | Where-Object { -not $_.integrada -and $_.pnpId }) | Select-Object -First 1
    if (-not $gpu) { $gpu = @($Profile.gpu.adaptadores | Where-Object { $_.pnpId }) | Select-Object -First 1 }
    if (-not $gpu) { return $null }
    $key = Join-Path (Get-TmxEnumRoot) $gpu.pnpId
    [pscustomobject]@{
        modelo    = $gpu.modelo
        pnpId     = $gpu.pnpId
        chave     = $key
        interrupt = (Join-Path $key 'Device Parameters\Interrupt Management')
        msi       = (Join-Path $key 'Device Parameters\Interrupt Management\MessageSignaledInterruptProperties')
        affinity  = (Join-Path $key 'Device Parameters\Interrupt Management\Affinity Policy')
    }
}

function Test-TmxGpuMsi {
    [CmdletBinding()]
    param($Tweak, $Profile)

    $d = Get-TmxGpuDeviceKey -Profile $Profile
    if (-not $d) { return [pscustomobject]@{ aplicado = $null; atual = $null; esperado = $null; detalhe = 'GPU sem pnpId no perfil' } }
    if (-not (Test-Path -LiteralPath $d.msi)) {
        return [pscustomobject]@{ aplicado = $null; atual = $null; esperado = $null; detalhe = 'driver nao expoe MessageSignaledInterruptProperties (sem suporte a MSI declarado)' }
    }
    $msi  = (Get-ItemProperty -LiteralPath $d.msi -Name MSISupported -ErrorAction SilentlyContinue).MSISupported
    $prio = (Get-ItemProperty -LiteralPath $d.affinity -Name DevicePriority -ErrorAction SilentlyContinue).DevicePriority
    $ok = ([int]$msi -eq 1) -and ([int]$prio -eq 3)
    [pscustomobject]@{
        aplicado = $ok
        atual    = "MSISupported=$msi; DevicePriority=$prio"
        esperado = 'MSISupported=1; DevicePriority=3'
        detalhe  = "$($d.modelo): MSISupported=$(if ($null -eq $msi) { '<ausente>' } else { $msi }), DevicePriority=$(if ($null -eq $prio) { '<ausente>' } else { $prio })"
    }
}

function Set-TmxGpuMsi {
    [CmdletBinding()]
    param($Tweak, $Profile, $Parametros)

    $d = Get-TmxGpuDeviceKey -Profile $Profile
    if (-not $d) { return [pscustomobject]@{ ok = $false; detalhe = 'GPU sem pnpId no perfil' } }
    if (-not (Test-Path -LiteralPath $d.chave)) { return [pscustomobject]@{ ok = $false; detalhe = "chave do dispositivo nao encontrada: $($d.chave)" } }
    if (-not (Test-Path -LiteralPath $d.msi)) {
        return [pscustomobject]@{ ok = $true; naoAplicavel = $true; detalhe = "$($d.modelo): driver nao declara suporte a MSI (sem MessageSignaledInterruptProperties); nao forcamos" }
    }

    # Backup obrigatorio da chave do dispositivo antes de qualquer escrita.
    $bk = Backup-TmxRegistryHive -Path $d.interrupt
    if (-not $bk) { return [pscustomobject]@{ ok = $false; detalhe = 'backup .reg da chave Interrupt Management falhou; abortado' } }

    $r1 = Set-TmxRegistry -Path $d.msi      -Name 'MSISupported'   -Value 1 -Type DWord -TweakId "$($Tweak.id)" -PassThru
    $r2 = Set-TmxRegistry -Path $d.affinity -Name 'DevicePriority' -Value 3 -Type DWord -TweakId "$($Tweak.id)" -PassThru
    $ok = ($r1.status -eq 'aplicado' -and $r2.status -eq 'aplicado')
    [pscustomobject]@{
        ok        = $ok
        detalhe   = if ($ok) { "$($d.modelo): MSISupported $(if ($r1.existiaAntes) { $r1.valorAnterior } else { '<ausente>' }) -> 1; DevicePriority $(if ($r2.existiaAntes) { $r2.valorAnterior } else { '<ausente>' }) -> 3 (efetivo apos reboot)" } else { "falha: $($r1.erro) $($r2.erro)" }
        registros = @($r1, $r2)
    }
}

function Undo-TmxGpuMsi {
    <#
    .SYNOPSIS
        Nunca deve ser chamado pelo rollback normal: as duas escritas de
        Set-TmxGpuMsi geram registros 'registry', revertidos pelos handlers de
        registro de Core/Rollback.ps1. Existe so para completar o trio
        Set-/Undo-/Test- exigido por Test-TmxAcaoList.
    #>
    [CmdletBinding()]
    param($Estado)
    throw 'reversao feita pelos registros de registro (tipo registry); Undo-TmxGpuMsi nao gerencia estado proprio'
}
