# Testes das funcoes nomeadas da categoria Jogos (src/functions/tweaks/{NicPower,
# DefenderExclusion,Trim,Pagefile,GpuMsi,Native}.ps1).
#
# Mesmo padrao de tests/Functions.Tweaks.Tests.ps1: todo wrapper que toca o
# sistema e mockado, e cada Describe prova (a) o registro esta no disco ANTES
# do wrapper ser chamado, (b) Test-Tmx<X> reflete o estado mockado, (c)
# Undo-Tmx<X> restaura usando o estado capturado. GpuMsi e a excecao: usa
# registro real sob uma subchave HKCU de teste (redirecionada por
# Set-TmxEnumRoot), porque a propria escrita passa por Set-TmxRegistry.

. "$PSScriptRoot\_Helpers.ps1"

BeforeAll {
    . "$PSScriptRoot\_Helpers.ps1"
    Import-TmxTestModule
    New-TmxTestHome | Out-Null

    # Perfil minimo com o formato REAL usado pelas funcoes portadas do
    # CS2Tuner (storage.cs2Path = caminho completo do executavel).
    $script:Perfil = [pscustomobject]@{
        network = [pscustomobject]@{ adaptadorAtivo = [pscustomobject]@{ nome = 'Ethernet'; tipo = 'Ethernet' } }
        storage = [pscustomobject]@{ cs2Path = 'D:\SteamLibrary\steamapps\common\Counter-Strike Global Offensive\game\bin\win64\cs2.exe' }
        gpu     = [pscustomobject]@{
            adaptadores = @(
                [pscustomobject]@{ modelo = 'NVIDIA GeForce RTX 4070'; vendor = 'NVIDIA'; pnpId = 'TESTGPU0001'; integrada = $false }
            )
        }
    }

    function script:New-TmxTweakFake {
        param([Parameter(Mandatory)] [string] $Id)
        [pscustomobject]@{ id = $Id; nome = "Teste $Id"; tier = 'MEDIDO'; reversivel = 'total'; acoes = @() }
    }

    function script:Get-TmxRegistrosDoDisco {
        param([Parameter(Mandatory)] [string] $Caminho)
        if (-not (Test-Path -LiteralPath $Caminho)) { return @() }
        $dados = Get-Content -LiteralPath $Caminho -Raw -Encoding UTF8 | ConvertFrom-Json
        @($dados.registros | Where-Object { $null -ne $_ })
    }

    function script:Reset-TmxCaptura {
        $global:TmxT_StateNoWrapper = $null
        $global:TmxT_Chamadas = New-Object System.Collections.ArrayList
    }

    function script:Add-TmxChamada {
        param([Parameter(Mandatory)] $Registro)
        if (-not $global:TmxT_StateNoWrapper) {
            $global:TmxT_StateNoWrapper = Get-Content -LiteralPath $global:TmxT_StatePath -Raw -Encoding UTF8
        }
        $null = $global:TmxT_Chamadas.Add($Registro)
    }
}

AfterAll {
    Remove-TmxTestHome
    Stop-TmxLogger
    Remove-Module TweakMaxing -Force -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------------------

Describe 'Set-TmxNicPower' -Tag 'Jogos' {

    BeforeEach {
        $script:run = New-TmxRun
        $global:TmxT_StatePath = $script:run.StatePath
        Reset-TmxCaptura
        $global:TmxT_Allow = 'Enabled'

        Mock Get-TmxNicPm -ModuleName TweakMaxing { [pscustomobject]@{ AllowComputerToTurnOffDevice = $global:TmxT_Allow } }
        Mock Set-TmxNicPm -ModuleName TweakMaxing {
            param($Name, $Allow)
            Add-TmxChamada ([pscustomobject]@{ nome = $Name; allow = $Allow })
            $global:TmxT_Allow = $Allow
        }
    }

    It 'persiste o estado anterior antes de chamar o wrapper' {
        $t = New-TmxTweakFake -Id 'JOG-007'
        $r = Set-TmxNicPower -Tweak $t -Profile $script:Perfil -Parametros $null

        $r.ok | Should -BeTrue
        $global:TmxT_Chamadas[0].allow | Should -Be 'Disabled'
        $global:TmxT_StateNoWrapper    | Should -Match '"funcao":\s*"Set-TmxNicPower"'
        $global:TmxT_StateNoWrapper    | Should -Match '"valorAnterior":\s*"Enabled"'

        $recs = @(Get-TmxRegistrosDoDisco $script:run.StatePath)
        $recs.Count     | Should -Be 1
        $recs[0].tipo   | Should -Be 'cmdlet'
        $recs[0].status | Should -Be 'aplicado'
    }

    It 'Test reflete o valor lido do wrapper' {
        $t = New-TmxTweakFake -Id 'JOG-007'
        (Test-TmxNicPower -Tweak $t -Profile $script:Perfil).aplicado | Should -BeFalse
        Set-TmxNicPower -Tweak $t -Profile $script:Perfil -Parametros $null | Out-Null
        (Test-TmxNicPower -Tweak $t -Profile $script:Perfil).aplicado | Should -BeTrue
    }

    It 'marca naoAplicavel quando o adaptador nao suporta gerenciamento de energia' {
        $global:TmxT_Allow = 'Unsupported'
        $r = Set-TmxNicPower -Tweak (New-TmxTweakFake -Id 'JOG-007') -Profile $script:Perfil -Parametros $null
        $r.ok           | Should -BeTrue
        $r.naoAplicavel | Should -BeTrue
        @(Get-TmxRegistrosDoDisco $script:run.StatePath).Count | Should -Be 0
    }

    It 'Undo restaura o valor anterior guardado no estado' {
        Undo-TmxNicPower -Estado @{ adaptador = 'Ethernet'; anterior = 'Enabled' } | Should -Match 'Enabled'
        $global:TmxT_Chamadas[0].allow | Should -Be 'Enabled'
        $global:TmxT_Chamadas[0].nome  | Should -Be 'Ethernet'
    }
}

# ---------------------------------------------------------------------------

Describe 'Set-TmxDefenderExclusion' -Tag 'Jogos' {

    BeforeEach {
        $script:run = New-TmxRun
        $global:TmxT_StatePath = $script:run.StatePath
        Reset-TmxCaptura
        $global:TmxT_Exclusoes = @()

        Mock Get-TmxDefenderExclusions -ModuleName TweakMaxing { $global:TmxT_Exclusoes }
        Mock Add-TmxDefenderExclusionPath -ModuleName TweakMaxing {
            param($Path)
            Add-TmxChamada ([pscustomobject]@{ acao = 'add'; caminho = $Path })
            $global:TmxT_Exclusoes = @($Path)
        }
        Mock Remove-TmxDefenderExclusionPath -ModuleName TweakMaxing {
            param($Path)
            Add-TmxChamada ([pscustomobject]@{ acao = 'remove'; caminho = $Path })
            $global:TmxT_Exclusoes = @()
        }
    }

    It 'Get-TmxCs2Folder resolve a raiz do jogo a partir do executavel' {
        Get-TmxCs2Folder -Profile $script:Perfil | Should -Be 'D:\SteamLibrary\steamapps\common\Counter-Strike Global Offensive'
    }

    It 'persiste o estado anterior antes de chamar o wrapper' {
        $t = New-TmxTweakFake -Id 'JOG-038'
        $r = Set-TmxDefenderExclusion -Tweak $t -Profile $script:Perfil -Parametros $null

        $r.ok | Should -BeTrue
        $global:TmxT_Chamadas[0].acao    | Should -Be 'add'
        $global:TmxT_StateNoWrapper      | Should -Match '"funcao":\s*"Set-TmxDefenderExclusion"'

        $recs = @(Get-TmxRegistrosDoDisco $script:run.StatePath)
        $recs.Count     | Should -Be 1
        $recs[0].status | Should -Be 'aplicado'
    }

    It 'Test reflete a exclusao mockada' {
        $t = New-TmxTweakFake -Id 'JOG-038'
        (Test-TmxDefenderExclusion -Tweak $t -Profile $script:Perfil).aplicado | Should -BeFalse
        Set-TmxDefenderExclusion -Tweak $t -Profile $script:Perfil -Parametros $null | Out-Null
        (Test-TmxDefenderExclusion -Tweak $t -Profile $script:Perfil).aplicado | Should -BeTrue
    }

    It 'Undo remove a exclusao guardada no estado' {
        Undo-TmxDefenderExclusion -Estado @{ pasta = 'D:\SteamLibrary\steamapps\common\Counter-Strike Global Offensive' } | Should -Match 'removida'
        $global:TmxT_Chamadas[0].acao    | Should -Be 'remove'
        $global:TmxT_Chamadas[0].caminho | Should -Be 'D:\SteamLibrary\steamapps\common\Counter-Strike Global Offensive'
    }
}

# ---------------------------------------------------------------------------

Describe 'Set-TmxTrim' -Tag 'Jogos' {

    BeforeEach {
        $script:run = New-TmxRun
        $global:TmxT_StatePath = $script:run.StatePath
        Reset-TmxCaptura
        $global:TmxT_TrimDisabled = 1
        $global:TmxT_FsutilLegivel = $true

        Mock Invoke-TmxFsutil -ModuleName TweakMaxing {
            param($Arguments)
            $args2 = @($Arguments)
            if ($args2 -contains 'query') {
                # Leitura pura (nao muda estado): nao captura, para nao marcar o
                # instantaneo do disco antes do registro de estado ser persistido.
                if (-not $global:TmxT_FsutilLegivel) {
                    return [pscustomobject]@{ saida = 'saida inesperada sem o padrao conhecido'; codigo = 0 }
                }
                return [pscustomobject]@{ saida = "NTFS DisableDeleteNotify = $global:TmxT_TrimDisabled"; codigo = 0 }
            }
            # 'set'
            Add-TmxChamada ([pscustomobject]@{ acao = 'set'; args = ($args2 -join ' ') })
            $global:TmxT_TrimDisabled = [int]($args2[-1])
            [pscustomobject]@{ saida = ''; codigo = 0 }
        }
    }

    It 'persiste o estado anterior antes de chamar fsutil set' {
        $t = New-TmxTweakFake -Id 'JOG-040'
        $r = Set-TmxTrim -Tweak $t -Profile $script:Perfil -Parametros $null

        $r.ok | Should -BeTrue
        $global:TmxT_StateNoWrapper | Should -Match '"funcao":\s*"Set-TmxTrim"'
        $global:TmxT_StateNoWrapper | Should -Match '"valorAnterior":\s*1'

        $recs = @(Get-TmxRegistrosDoDisco $script:run.StatePath)
        $recs.Count     | Should -Be 1
        $recs[0].status | Should -Be 'aplicado'
    }

    It 'Test reflete o valor lido do fsutil' {
        $t = New-TmxTweakFake -Id 'JOG-040'
        (Test-TmxTrim -Tweak $t -Profile $script:Perfil).aplicado | Should -BeFalse
        Set-TmxTrim -Tweak $t -Profile $script:Perfil -Parametros $null | Out-Null
        (Test-TmxTrim -Tweak $t -Profile $script:Perfil).aplicado | Should -BeTrue
    }

    It 'A1: fsutil ilegivel nao aplica e NAO grava registro' {
        $global:TmxT_FsutilLegivel = $false
        $r = Set-TmxTrim -Tweak (New-TmxTweakFake -Id 'JOG-040') -Profile $script:Perfil -Parametros $null
        $r.ok      | Should -BeFalse
        $r.detalhe | Should -Match 'ilegivel'
        @(Get-TmxRegistrosDoDisco $script:run.StatePath).Count | Should -Be 0
    }

    It 'Undo restaura o valor guardado no estado' {
        Undo-TmxTrim -Estado @{ anterior = 1 } | Should -Match 'restaurado para 1'
        $global:TmxT_Chamadas[0].acao | Should -Be 'set'
    }
}

# ---------------------------------------------------------------------------

Describe 'Set-TmxPagefile' -Tag 'Jogos' {

    BeforeEach {
        $script:run = New-TmxRun
        $global:TmxT_StatePath = $script:run.StatePath
        Reset-TmxCaptura
        $global:TmxT_Pagefile = [pscustomobject]@{ automatico = $true; arquivos = @() }

        Mock Get-TmxPagefileState -ModuleName TweakMaxing { $global:TmxT_Pagefile }
        Mock Set-TmxPagefileState -ModuleName TweakMaxing {
            param($Automatico, $Arquivos)
            Add-TmxChamada ([pscustomobject]@{ automatico = $Automatico; arquivos = @($Arquivos) })
            $global:TmxT_Pagefile = [pscustomobject]@{ automatico = $Automatico; arquivos = @($Arquivos) }
        }
    }

    It 'persiste o estado anterior antes de chamar o wrapper' {
        $t = New-TmxTweakFake -Id 'JOG-043'
        $r = Set-TmxPagefile -Tweak $t -Profile $script:Perfil -Parametros @{ tamanhoMB = 16384 }

        $r.ok | Should -BeTrue
        $global:TmxT_Chamadas[0].automatico | Should -BeFalse
        $global:TmxT_StateNoWrapper         | Should -Match '"funcao":\s*"Set-TmxPagefile"'

        $recs = @(Get-TmxRegistrosDoDisco $script:run.StatePath)
        $recs.Count     | Should -Be 1
        $recs[0].status | Should -Be 'aplicado'
    }

    It 'recusa tamanhoMB menor ou igual a zero e nao grava registro' {
        foreach ($v in 0, -1) {
            $r = Set-TmxPagefile -Tweak (New-TmxTweakFake -Id 'JOG-043') -Profile $script:Perfil -Parametros @{ tamanhoMB = $v }
            $r.ok      | Should -BeFalse -Because "tamanhoMB=$v"
            $r.detalhe | Should -Match 'nunca e desativado'
        }
        @(Get-TmxRegistrosDoDisco $script:run.StatePath).Count | Should -Be 0
    }

    It 'Test reflete o estado mockado usando os parametros da acao do proprio tweak' {
        $t = New-TmxTweakFake -Id 'JOG-043'
        $t.acoes = @([pscustomobject]@{ tipo = 'funcao'; nome = 'Set-TmxPagefile'; parametros = @{ tamanhoMB = 16384 } })

        (Test-TmxPagefile -Tweak $t -Profile $script:Perfil).aplicado | Should -BeFalse

        Set-TmxPagefile -Tweak $t -Profile $script:Perfil -Parametros @{ tamanhoMB = 16384 } | Out-Null
        (Test-TmxPagefile -Tweak $t -Profile $script:Perfil).aplicado | Should -BeTrue
    }

    It 'Undo restaura automatico=true guardado no estado' {
        Undo-TmxPagefile -Estado @{ automatico = $true; arquivos = @() } | Should -Match 'automatico=True'
        $global:TmxT_Chamadas[0].automatico | Should -BeTrue
    }

    It 'poscondicao: se o CIM nao refletir o pedido apos escrever, ok=$false com detalhe' {
        # Simula Set-CimInstance/New-CimInstance "bem-sucedido" (sem excecao) mas o
        # estado relido nao bate com o pedido (2 arquivos em vez de 1) - mesmo
        # espirito do A1 do Trim: nao confiar so na ausencia de excecao.
        Mock Set-TmxPagefileState -ModuleName TweakMaxing {
            param($Automatico, $Arquivos)
            Add-TmxChamada ([pscustomobject]@{ automatico = $Automatico; arquivos = @($Arquivos) })
            $global:TmxT_Pagefile = [pscustomobject]@{
                automatico = $Automatico
                arquivos   = @(
                    [pscustomobject]@{ nome = 'C:\pagefile.sys'; inicial = 16384; maximo = 16384 }
                    [pscustomobject]@{ nome = 'D:\pagefile.sys'; inicial = 4096;  maximo = 4096 }
                )
            }
        }

        $t = New-TmxTweakFake -Id 'JOG-043'
        $r = Set-TmxPagefile -Tweak $t -Profile $script:Perfil -Parametros @{ tamanhoMB = 16384 }

        $r.ok      | Should -BeFalse
        $r.detalhe | Should -Match 'poscondicao'

        $recs = @(Get-TmxRegistrosDoDisco $script:run.StatePath)
        $recs.Count     | Should -Be 1
        $recs[0].status | Should -Be 'falha'
        "$($recs[0].erro)" | Should -Match 'poscondicao'
    }
}

# ---------------------------------------------------------------------------

Describe 'Set-TmxGpuMsi' -Tag 'Jogos' {

    BeforeAll {
        # Set-TmxEnumRoot so aceita redirecionar a raiz do registro com este
        # hook ligado (fora de teste ele lanca 'hook de teste desabilitado').
        $env:TWEAKMAXING_TEST_HOOKS = '1'
    }

    AfterAll {
        Remove-Item Env:\TWEAKMAXING_TEST_HOOKS -ErrorAction SilentlyContinue
    }

    BeforeEach {
        Remove-TmxTestKey -SubKey 'Jogos\GpuMsi'
        $script:run = New-TmxRun
        $script:EnumRoot = 'HKCU:\Software\TweakMaxing_Tests\Jogos\GpuMsi\Enum'
        Set-TmxEnumRoot -Path $script:EnumRoot
        New-Item -Path (Join-Path $script:EnumRoot 'TESTGPU0001') -Force | Out-Null
    }

    AfterEach {
        Set-TmxEnumRoot -Path 'HKLM:\SYSTEM\CurrentControlSet\Enum'
        Remove-TmxTestKey -SubKey 'Jogos\GpuMsi'
    }

    It 'Set-TmxEnumRoot lanca quando o hook de teste esta desligado' {
        Remove-Item Env:\TWEAKMAXING_TEST_HOOKS -ErrorAction SilentlyContinue
        try {
            { Set-TmxEnumRoot -Path $script:EnumRoot } | Should -Throw '*hook de teste desabilitado*'
        } finally {
            $env:TWEAKMAXING_TEST_HOOKS = '1'
        }
    }

    It 'sem MessageSignaledInterruptProperties: naoAplicavel e nada e escrito' {
        $t = New-TmxTweakFake -Id 'JOG-013'
        $r = Set-TmxGpuMsi -Tweak $t -Profile $script:Perfil -Parametros $null

        $r.ok           | Should -BeTrue
        $r.naoAplicavel | Should -BeTrue

        $d = Get-TmxGpuDeviceKey -Profile $script:Perfil
        Test-Path -LiteralPath $d.msi | Should -BeFalse
        @(Get-Content -LiteralPath $script:run.StatePath -Raw -Encoding UTF8 | ConvertFrom-Json).registros | Should -BeNullOrEmpty
    }

    It 'Test-TmxGpuMsi tambem reporta nao verificavel sem a chave MSI' {
        $t = New-TmxTweakFake -Id 'JOG-013'
        (Test-TmxGpuMsi -Tweak $t -Profile $script:Perfil).aplicado | Should -Be $null
    }

    It 'com MessageSignaledInterruptProperties presente: aplica via Set-TmxRegistry e grava 2 registros' {
        $d = Get-TmxGpuDeviceKey -Profile $script:Perfil
        New-Item -Path $d.msi -Force | Out-Null
        New-Item -Path $d.affinity -Force | Out-Null

        $t = New-TmxTweakFake -Id 'JOG-013'
        $r = Set-TmxGpuMsi -Tweak $t -Profile $script:Perfil -Parametros $null

        $r.ok | Should -BeTrue
        @($r.registros).Count | Should -Be 2

        (Get-ItemProperty -LiteralPath $d.msi -Name MSISupported).MSISupported | Should -Be 1
        (Get-ItemProperty -LiteralPath $d.affinity -Name DevicePriority).DevicePriority | Should -Be 3

        (Test-TmxGpuMsi -Tweak $t -Profile $script:Perfil).aplicado | Should -BeTrue
    }

    It 'Undo-TmxGpuMsi lanca (reversao acontece pelos registros de registro)' {
        { Undo-TmxGpuMsi -Estado $null } | Should -Throw
    }
}

# ---------------------------------------------------------------------------

Describe 'Native: Initialize-TmxNativeTypes / Send-TmxSettingChange' -Tag 'Jogos' {

    It 'Initialize-TmxNativeTypes compila (ou ja compilou) os tipos e devolve $true' {
        Initialize-TmxNativeTypes | Should -BeTrue
    }

    It 'Send-TmxSettingChange devolve $true (chamada real e inofensiva: so faz broadcast)' {
        Send-TmxSettingChange | Should -BeTrue
    }
}
