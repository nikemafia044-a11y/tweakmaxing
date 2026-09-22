# Testes das funcoes nomeadas de tweak (src/functions/tweaks/*.ps1).
#
# Todo executavel e todo cmdlet que mexe no sistema passa por um wrapper em
# _Wrappers.ps1 justamente para poder ser mockado aqui: nenhum teste desta suite
# toca o sistema de verdade.
#
# Cada Describe prova as tres coisas que importam no contrato:
#   (a) o registro de estado esta NO DISCO antes de o wrapper ser chamado
#       (o proprio mock le o state.json de dentro dele mesmo);
#   (b) Test-Tmx<X> reflete o estado mockado;
#   (c) Undo-Tmx<X> restaura usando o estado capturado, nao um chute.

. "$PSScriptRoot\_Helpers.ps1"

BeforeAll {
    . "$PSScriptRoot\_Helpers.ps1"
    Import-TmxTestModule
    New-TmxTestHome | Out-Null

    $script:Perfil = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'fixtures\profile-engine.json') -Raw -Encoding UTF8 | ConvertFrom-Json

    function script:New-TmxTweakFake {
        param([Parameter(Mandatory)] [string] $Id)
        [pscustomobject]@{ id = $Id; nome = "Teste $Id"; tier = 'MEDIDO'; reversivel = 'total' }
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

Describe 'Set-TmxHibernation' -Tag 'Tweaks' {

    BeforeEach {
        $script:run = New-TmxRun
        $global:TmxT_StatePath = $script:run.StatePath
        Reset-TmxCaptura
        $global:TmxT_Hibernate = 1

        Mock Get-TmxRegistryValue -ModuleName TweakMaxing { $global:TmxT_Hibernate }
        Mock Invoke-TmxPowercfg -ModuleName TweakMaxing {
            Add-TmxChamada ([pscustomobject]@{ args = ($Arguments -join ' ') })
            if ($Arguments -contains 'off') { $global:TmxT_Hibernate = 0 } else { $global:TmxT_Hibernate = 1 }
            [pscustomobject]@{ saida = ''; codigo = 0 }
        }
    }

    It 'persiste o estado anterior antes de chamar o powercfg' {
        $t = New-TmxTweakFake -Id 'ENE-001'
        $r = Set-TmxHibernation -Tweak $t -Profile $script:Perfil -Parametros $null

        $r.ok | Should -BeTrue
        $global:TmxT_Chamadas[0].args | Should -Be '/hibernate off'
        $global:TmxT_StateNoWrapper   | Should -Match '"funcao":\s*"Set-TmxHibernation"'
        $global:TmxT_StateNoWrapper   | Should -Match '"valorAnterior":\s*1'

        $recs = @(Get-TmxRegistrosDoDisco $script:run.StatePath)
        $recs.Count          | Should -Be 1
        $recs[0].tipo        | Should -Be 'cmdlet'
        $recs[0].status      | Should -Be 'aplicado'
    }

    It 'Test reflete o valor lido do registro' {
        $t = New-TmxTweakFake -Id 'ENE-001'
        (Test-TmxHibernation -Tweak $t -Profile $script:Perfil).aplicado | Should -BeFalse
        Set-TmxHibernation -Tweak $t -Profile $script:Perfil -Parametros $null | Out-Null
        (Test-TmxHibernation -Tweak $t -Profile $script:Perfil).aplicado | Should -BeTrue
    }

    It 'Undo religa a hibernacao com base no estado capturado' {
        Undo-TmxHibernation -Estado @{ hibernateEnabled = 1 } | Should -Match 'on'
        $global:TmxT_Chamadas[0].args | Should -Be '/hibernate on'
    }

    It 'Undo mantem desligado quando estava desligado antes' {
        Undo-TmxHibernation -Estado @{ hibernateEnabled = 0 } | Should -Match 'off'
        $global:TmxT_Chamadas[0].args | Should -Be '/hibernate off'
    }
}

Describe 'Set-TmxWidgets' -Tag 'Tweaks' {

    BeforeEach {
        $script:run = New-TmxRun
        $global:TmxT_StatePath = $script:run.StatePath
        Reset-TmxCaptura
        $global:TmxT_Pacotes = @(
            [pscustomobject]@{ PackageFullName = 'Microsoft.WidgetsPlatformRuntime_1.0_x64__8wekyb3d8bbwe' }
        )

        Mock Get-TmxAppx -ModuleName TweakMaxing {
            if ($Pacote -eq 'Microsoft.WidgetsPlatformRuntime') { return $global:TmxT_Pacotes }
            @()
        }
        Mock Remove-TmxAppx -ModuleName TweakMaxing {
            Add-TmxChamada ([pscustomobject]@{ acao = 'remove'; pacote = $PackageFullName })
            $global:TmxT_Pacotes = @()
        }
        Mock Remove-TmxProvisionedAppx -ModuleName TweakMaxing { }
        Mock Stop-TmxProcessByName -ModuleName TweakMaxing { }
        Mock Restart-TmxExplorer -ModuleName TweakMaxing { }
        Mock Install-TmxStoreApp -ModuleName TweakMaxing {
            Add-TmxChamada ([pscustomobject]@{ acao = 'install'; storeId = $StoreId })
            0
        }
    }

    It 'registra os PackageFullName antes de remover' {
        $t = New-TmxTweakFake -Id 'APM-001'
        $r = Set-TmxWidgets -Tweak $t -Profile $script:Perfil -Parametros $null

        $r.ok | Should -BeTrue
        $global:TmxT_StateNoWrapper | Should -Match 'Microsoft\.WidgetsPlatformRuntime_1\.0_x64__8wekyb3d8bbwe'
        $global:TmxT_StateNoWrapper | Should -Match '"funcao":\s*"Set-TmxWidgets"'
        $global:TmxT_Chamadas[0].acao | Should -Be 'remove'
    }

    It 'Test fica verdadeiro depois que os pacotes somem' {
        $t = New-TmxTweakFake -Id 'APM-001'
        (Test-TmxWidgets -Tweak $t -Profile $script:Perfil).aplicado | Should -BeFalse
        Set-TmxWidgets -Tweak $t -Profile $script:Perfil -Parametros $null | Out-Null
        (Test-TmxWidgets -Tweak $t -Profile $script:Perfil).aplicado | Should -BeTrue
    }

    It 'marca naoAplicavel quando nao ha pacote instalado' {
        $global:TmxT_Pacotes = @()
        $r = Set-TmxWidgets -Tweak (New-TmxTweakFake -Id 'APM-001') -Profile $script:Perfil -Parametros $null
        $r.ok           | Should -BeTrue
        $r.naoAplicavel | Should -BeTrue
    }

    It 'Undo reinstala pelo StoreId guardado no estado' {
        Undo-TmxWidgets -Estado @{ storeId = '9MSSGKG348SP' } | Should -Match '9MSSGKG348SP'
        $global:TmxT_Chamadas[0].storeId | Should -Be '9MSSGKG348SP'
    }
}

Describe 'Set-TmxStoreSearch' -Tag 'Tweaks' {

    BeforeEach {
        $script:run = New-TmxRun
        $global:TmxT_StatePath = $script:run.StatePath
        Reset-TmxCaptura
        $global:TmxT_Acl = 'Everyone:(F)'

        Mock Test-TmxItemPath -ModuleName TweakMaxing { $true }
        Mock Invoke-TmxIcacls -ModuleName TweakMaxing {
            if ($Arguments.Count -gt 1) {
                Add-TmxChamada ([pscustomobject]@{ args = @($Arguments) })
                if ($Arguments -contains '/deny')  { $global:TmxT_Acl = 'Everyone:(DENY)(F)' }
                if ($Arguments -contains '/grant') { $global:TmxT_Acl = 'Everyone:(F)' }
            }
            [pscustomobject]@{ saida = $global:TmxT_Acl; codigo = 0 }
        }
    }

    It 'nega a leitura de store.db e registra o estado antes' {
        $t = New-TmxTweakFake -Id 'INT-002'
        $r = Set-TmxStoreSearch -Tweak $t -Profile $script:Perfil -Parametros $null

        $r.ok | Should -BeTrue
        $global:TmxT_StateNoWrapper | Should -Match '"funcao":\s*"Set-TmxStoreSearch"'
        $global:TmxT_Chamadas[0].args | Should -Contain '/deny'
        $global:TmxT_Chamadas[0].args | Should -Contain '*S-1-1-0:F'
    }

    It 'Test detecta a negacao na ACL' {
        $t = New-TmxTweakFake -Id 'INT-002'
        (Test-TmxStoreSearch -Tweak $t -Profile $script:Perfil).aplicado | Should -BeFalse
        Set-TmxStoreSearch -Tweak $t -Profile $script:Perfil -Parametros $null | Out-Null
        (Test-TmxStoreSearch -Tweak $t -Profile $script:Perfil).aplicado | Should -BeTrue
    }

    It 'Undo devolve o acesso com /grant' {
        Undo-TmxStoreSearch -Estado @{ arquivo = 'C:\store.db' } | Out-Null
        $global:TmxT_Chamadas[0].args | Should -Contain '/grant'
    }
}

Describe 'Set-TmxSvcHostSplit' -Tag 'Tweaks' {

    BeforeEach {
        $script:run = New-TmxRun
        $global:TmxT_StatePath = $script:run.StatePath
        Reset-TmxCaptura
        $global:TmxT_MemKB = 16777216

        Mock Get-TmxPhysicalMemoryKB -ModuleName TweakMaxing { $global:TmxT_MemKB }
        Mock Set-TmxRegistry -ModuleName TweakMaxing {
            Add-TmxChamada ([pscustomobject]@{ path = $Path; name = $Name; valor = $Value })
            [pscustomobject]@{ status = 'aplicado'; erro = $null; tipo = 'registry' }
        }
        Mock Get-TmxRegistryValue -ModuleName TweakMaxing { $global:TmxT_Valor }
    }

    It 'grava o limiar com a memoria instalada e devolve o registro do Core' {
        $r = Set-TmxSvcHostSplit -Tweak (New-TmxTweakFake -Id 'SIS-001') -Profile $script:Perfil -Parametros $null
        $r.ok | Should -BeTrue
        $r.registro.tipo | Should -Be 'registry'
        $global:TmxT_Chamadas[0].name  | Should -Be 'SvcHostSplitThresholdInKB'
        $global:TmxT_Chamadas[0].valor | Should -Be 16777216
    }

    It 'recusa quando a memoria nao cabe em um DWord' {
        $global:TmxT_MemKB = [int64]::MaxValue
        $r = Set-TmxSvcHostSplit -Tweak (New-TmxTweakFake -Id 'SIS-001') -Profile $script:Perfil -Parametros $null
        $r.ok      | Should -BeFalse
        $r.detalhe | Should -Match 'DWord'
    }

    It 'Test compara o valor atual com a memoria instalada' {
        $global:TmxT_Valor = 16777216
        (Test-TmxSvcHostSplit -Tweak (New-TmxTweakFake -Id 'SIS-001') -Profile $script:Perfil).aplicado | Should -BeTrue
        $global:TmxT_Valor = 1024
        (Test-TmxSvcHostSplit -Tweak (New-TmxTweakFake -Id 'SIS-001') -Profile $script:Perfil).aplicado | Should -BeFalse
    }
}

Describe 'Set-TmxTelemetry' -Tag 'Tweaks' {

    BeforeEach {
        $script:run = New-TmxRun
        $global:TmxT_StatePath = $script:run.StatePath
        Reset-TmxCaptura
        $global:TmxT_Consent = 1
        $global:TmxT_Optout  = $null

        Mock Get-TmxDefenderPreference -ModuleName TweakMaxing { [pscustomobject]@{ SubmitSamplesConsent = $global:TmxT_Consent } }
        Mock Set-TmxDefenderSubmitSamples -ModuleName TweakMaxing {
            Add-TmxChamada ([pscustomobject]@{ alvo = 'defender'; valor = $Valor })
            $global:TmxT_Consent = $Valor
        }
        Mock Get-TmxMachineEnvVar -ModuleName TweakMaxing { $global:TmxT_Optout }
        Mock Set-TmxMachineEnvVar -ModuleName TweakMaxing {
            Add-TmxChamada ([pscustomobject]@{ alvo = 'env'; nome = $Nome; valor = $Valor })
            $global:TmxT_Optout = $Valor
        }
        Mock Set-TmxRegistry -ModuleName TweakMaxing { [pscustomobject]@{ status = 'aplicado'; erro = $null; tipo = 'registry' } }
    }

    It 'captura os valores anteriores antes de alterar' {
        $r = Set-TmxTelemetry -Tweak (New-TmxTweakFake -Id 'PRI-006') -Profile $script:Perfil -Parametros $null

        $r.ok | Should -BeTrue
        $global:TmxT_StateNoWrapper | Should -Match '"submitSamplesConsent":\s*1'
        $global:TmxT_Chamadas[0].alvo  | Should -Be 'defender'
        $global:TmxT_Chamadas[0].valor | Should -Be 2
    }

    It 'Test fica verdadeiro so com os dois pontos no alvo' {
        $t = New-TmxTweakFake -Id 'PRI-006'
        (Test-TmxTelemetry -Tweak $t -Profile $script:Perfil).aplicado | Should -BeFalse
        Set-TmxTelemetry -Tweak $t -Profile $script:Perfil -Parametros $null | Out-Null
        (Test-TmxTelemetry -Tweak $t -Profile $script:Perfil).aplicado | Should -BeTrue
    }

    It 'Undo restaura o consentimento e a variavel de ambiente anteriores' {
        Undo-TmxTelemetry -Estado @{ submitSamplesConsent = 1; powershellTelemetryOptout = $null } | Out-Null
        $global:TmxT_Consent | Should -Be 1
        $global:TmxT_Optout  | Should -BeNullOrEmpty
    }
}

Describe 'Set-TmxBitLocker' -Tag 'Tweaks' {

    BeforeEach {
        $script:run = New-TmxRun
        $global:TmxT_StatePath = $script:run.StatePath
        Reset-TmxCaptura
        $global:TmxT_Protecao = 'On'

        Mock Get-TmxBitLockerStatus -ModuleName TweakMaxing { [pscustomobject]@{ ProtectionStatus = $global:TmxT_Protecao } }
        Mock Disable-TmxBitLockerVolume -ModuleName TweakMaxing {
            Add-TmxChamada ([pscustomobject]@{ acao = 'disable'; montagem = $MountPoint })
            $global:TmxT_Protecao = 'Off'
        }
        Mock Enable-TmxBitLockerVolume -ModuleName TweakMaxing {
            Add-TmxChamada ([pscustomobject]@{ acao = 'enable'; montagem = $MountPoint })
            $global:TmxT_Protecao = 'On'
        }
    }

    It 'registra o estado anterior antes de desligar' {
        $r = Set-TmxBitLocker -Tweak (New-TmxTweakFake -Id 'SIS-003') -Profile $script:Perfil -Parametros $null
        $r.ok | Should -BeTrue
        $global:TmxT_StateNoWrapper   | Should -Match '"protecaoAnterior":\s*"On"'
        $global:TmxT_Chamadas[0].acao | Should -Be 'disable'
    }

    It 'nao faz nada quando o BitLocker ja esta desligado' {
        $global:TmxT_Protecao = 'Off'
        $r = Set-TmxBitLocker -Tweak (New-TmxTweakFake -Id 'SIS-003') -Profile $script:Perfil -Parametros $null
        $r.naoAplicavel | Should -BeTrue
        $global:TmxT_Chamadas.Count | Should -Be 0
    }

    It 'Undo so reativa se estava ligado antes' {
        Undo-TmxBitLocker -Estado @{ montagem = 'C:'; protecaoAnterior = 'Off' } | Should -Match 'nao estava ligado'
        $global:TmxT_Chamadas.Count | Should -Be 0

        Undo-TmxBitLocker -Estado @{ montagem = 'C:'; protecaoAnterior = 'On' } | Out-Null
        $global:TmxT_Chamadas[0].acao | Should -Be 'enable'
    }
}

Describe 'Set-TmxReservedStorage' -Tag 'Tweaks' {

    BeforeEach {
        $script:run = New-TmxRun
        $global:TmxT_StatePath = $script:run.StatePath
        Reset-TmxCaptura
        $global:TmxT_Reservado = 'Enabled'

        Mock Invoke-TmxDism -ModuleName TweakMaxing {
            if ($Arguments -contains '/Get-ReservedStorageState') {
                return [pscustomobject]@{ saida = "Reserved storage state is $($global:TmxT_Reservado)"; codigo = 0 }
            }
            Add-TmxChamada ([pscustomobject]@{ args = @($Arguments) })
            if ($Arguments -contains '/State:Disabled') { $global:TmxT_Reservado = 'Disabled' }
            if ($Arguments -contains '/State:Enabled')  { $global:TmxT_Reservado = 'Enabled' }
            [pscustomobject]@{ saida = ''; codigo = 0 }
        }
    }

    It 'desliga a reserva e guarda o estado anterior' {
        $r = Set-TmxReservedStorage -Tweak (New-TmxTweakFake -Id 'SIS-005') -Profile $script:Perfil -Parametros $null
        $r.ok | Should -BeTrue
        $global:TmxT_StateNoWrapper   | Should -Match '"estadoAnterior":\s*"Enabled"'
        $global:TmxT_Chamadas[0].args | Should -Contain '/State:Disabled'
    }

    It 'Test acompanha o estado do DISM' {
        $t = New-TmxTweakFake -Id 'SIS-005'
        (Test-TmxReservedStorage -Tweak $t -Profile $script:Perfil).aplicado | Should -BeFalse
        Set-TmxReservedStorage -Tweak $t -Profile $script:Perfil -Parametros $null | Out-Null
        (Test-TmxReservedStorage -Tweak $t -Profile $script:Perfil).aplicado | Should -BeTrue
    }

    It 'Undo volta ao estado guardado' {
        Undo-TmxReservedStorage -Estado @{ estadoAnterior = 'Enabled' } | Should -Match 'Enabled'
        $global:TmxT_Chamadas[0].args | Should -Contain '/State:Enabled'
    }
}

Describe 'Set-TmxTeredo' -Tag 'Tweaks' {

    BeforeEach {
        $script:run = New-TmxRun
        $global:TmxT_StatePath = $script:run.StatePath
        Reset-TmxCaptura
        $global:TmxT_Teredo = 'default'

        Mock Invoke-TmxNetsh -ModuleName TweakMaxing {
            if ($Arguments -contains 'show') {
                return [pscustomobject]@{ saida = "Type                   : $($global:TmxT_Teredo)"; codigo = 0 }
            }
            Add-TmxChamada ([pscustomobject]@{ args = @($Arguments) })
            $global:TmxT_Teredo = $Arguments[-1]
            [pscustomobject]@{ saida = ''; codigo = 0 }
        }
    }

    It 'desativa o Teredo guardando o estado anterior' {
        $r = Set-TmxTeredo -Tweak (New-TmxTweakFake -Id 'RED-004') -Profile $script:Perfil -Parametros $null
        $r.ok | Should -BeTrue
        $global:TmxT_StateNoWrapper   | Should -Match '"estadoAnterior":\s*"default"'
        $global:TmxT_Chamadas[0].args | Should -Contain 'disabled'
    }

    It 'Test reflete o estado do netsh' {
        $t = New-TmxTweakFake -Id 'RED-004'
        (Test-TmxTeredo -Tweak $t -Profile $script:Perfil).aplicado | Should -BeFalse
        Set-TmxTeredo -Tweak $t -Profile $script:Perfil -Parametros $null | Out-Null
        (Test-TmxTeredo -Tweak $t -Profile $script:Perfil).aplicado | Should -BeTrue
    }

    It 'Undo volta ao estado anterior' {
        Undo-TmxTeredo -Estado @{ estadoAnterior = 'default' } | Should -Match 'default'
        $global:TmxT_Chamadas[0].args | Should -Contain 'default'
    }
}

Describe 'Set-TmxIpv6' -Tag 'Tweaks' {

    BeforeEach {
        $script:run = New-TmxRun
        $global:TmxT_StatePath = $script:run.StatePath
        Reset-TmxCaptura
        $global:TmxT_Bindings = @(
            [pscustomobject]@{ Name = 'Ethernet'; Enabled = $true },
            [pscustomobject]@{ Name = 'Wi-Fi';    Enabled = $true },
            [pscustomobject]@{ Name = 'Bluetooth'; Enabled = $false }
        )

        Mock Get-TmxNetAdapterBindingState -ModuleName TweakMaxing { $global:TmxT_Bindings }
        Mock Set-TmxNetAdapterBindingState -ModuleName TweakMaxing {
            Add-TmxChamada ([pscustomobject]@{ nome = $Name; habilitado = $Habilitado })
            foreach ($b in $global:TmxT_Bindings) { if ($b.Name -eq $Name) { $b.Enabled = $Habilitado } }
        }
    }

    It 'salva so os adaptadores que estavam ligados e desliga cada um' {
        $r = Set-TmxIpv6 -Tweak (New-TmxTweakFake -Id 'RED-005') -Profile $script:Perfil -Parametros $null
        $r.ok | Should -BeTrue
        $global:TmxT_StateNoWrapper | Should -Match 'Ethernet'
        $global:TmxT_StateNoWrapper | Should -Match 'Wi-Fi'
        $global:TmxT_StateNoWrapper | Should -Not -Match 'Bluetooth'
        @($global:TmxT_Chamadas).Count | Should -Be 2
    }

    It 'Test fica verdadeiro quando nenhum adaptador tem IPv6' {
        $t = New-TmxTweakFake -Id 'RED-005'
        (Test-TmxIpv6 -Tweak $t -Profile $script:Perfil).aplicado | Should -BeFalse
        Set-TmxIpv6 -Tweak $t -Profile $script:Perfil -Parametros $null | Out-Null
        (Test-TmxIpv6 -Tweak $t -Profile $script:Perfil).aplicado | Should -BeTrue
    }

    It 'Undo religa exatamente os adaptadores guardados' {
        Undo-TmxIpv6 -Estado @{ componente = 'ms_tcpip6'; adaptadoresHabilitados = @('Ethernet', 'Wi-Fi') } | Out-Null
        @($global:TmxT_Chamadas | ForEach-Object { $_.nome }) | Should -Be @('Ethernet', 'Wi-Fi')
        @($global:TmxT_Chamadas | Where-Object { -not $_.habilitado }).Count | Should -Be 0
    }
}

Describe 'Set-TmxDns' -Tag 'Tweaks' {

    BeforeEach {
        $script:run = New-TmxRun
        $global:TmxT_StatePath = $script:run.StatePath
        Reset-TmxCaptura
        $global:TmxT_Dns = @{ 3 = @('192.168.0.1'); 7 = @() }

        Mock Get-TmxActiveNetAdapter -ModuleName TweakMaxing {
            @(
                [pscustomobject]@{ Name = 'Ethernet'; InterfaceIndex = 3; Status = 'Up' },
                [pscustomobject]@{ Name = 'Wi-Fi';    InterfaceIndex = 7; Status = 'Up' }
            )
        }
        Mock Get-TmxDnsServerAddress -ModuleName TweakMaxing {
            if ($Familia -ne 2) { return [pscustomobject]@{ ServerAddresses = @() } }
            [pscustomobject]@{ ServerAddresses = @($global:TmxT_Dns[$InterfaceIndex]) }
        }
        Mock Set-TmxDnsServerAddress -ModuleName TweakMaxing {
            Add-TmxChamada ([pscustomobject]@{ indice = $InterfaceIndex; servidores = @($Servidores); reset = [bool]$Reset })
            if ($Reset) { $global:TmxT_Dns[$InterfaceIndex] = @() }
            else        { $global:TmxT_Dns[$InterfaceIndex] = @($Servidores) }
        }
    }

    It 'salva o DNS anterior de cada adaptador antes de escrever' {
        $r = Set-TmxDns -Tweak (New-TmxTweakFake -Id 'RED-006') -Profile $script:Perfil -Parametros @{ provedor = 'Cloudflare' }

        $r.ok | Should -BeTrue
        $global:TmxT_StateNoWrapper | Should -Match '192\.168\.0\.1'
        $global:TmxT_StateNoWrapper | Should -Match '"provedor":\s*"Cloudflare"'

        @($global:TmxT_Chamadas).Count | Should -Be 2
        $global:TmxT_Chamadas[0].servidores | Should -Contain '1.1.1.1'
        $global:TmxT_Chamadas[0].servidores | Should -Contain '2606:4700:4700::1111'
    }

    It 'provedor dhcp usa reset em vez de lista de servidores' {
        Set-TmxDns -Tweak (New-TmxTweakFake -Id 'RED-006') -Profile $script:Perfil -Parametros @{ provedor = 'dhcp' } | Out-Null
        $global:TmxT_Chamadas[0].reset | Should -BeTrue
    }

    It 'recusa provedor desconhecido' {
        { Set-TmxDns -Tweak (New-TmxTweakFake -Id 'RED-006') -Profile $script:Perfil -Parametros @{ provedor = 'NaoExiste' } } |
            Should -Throw -ExpectedMessage '*desconhecido*'
    }

    It 'exige o parametro provedor' {
        { Set-TmxDns -Tweak (New-TmxTweakFake -Id 'RED-006') -Profile $script:Perfil -Parametros @{} } |
            Should -Throw -ExpectedMessage "*provedor*"
    }

    It 'Undo restaura adaptador por adaptador, inclusive o que estava em DHCP' {
        $estado = @{
            provedor = 'Cloudflare'
            adaptadores = @(
                @{ indice = 3; nome = 'Ethernet'; v4 = @('192.168.0.1'); v6 = @() },
                @{ indice = 7; nome = 'Wi-Fi';    v4 = @();              v6 = @() }
            )
        }
        Undo-TmxDns -Estado $estado | Out-Null

        @($global:TmxT_Chamadas).Count | Should -Be 2
        $global:TmxT_Chamadas[0].servidores | Should -Contain '192.168.0.1'
        $global:TmxT_Chamadas[1].reset      | Should -BeTrue
    }
}

Describe 'Set-TmxDiskCleanup e Set-TmxTempFiles' -Tag 'Tweaks' {

    BeforeEach {
        $script:run = New-TmxRun
        $global:TmxT_StatePath = $script:run.StatePath
        Reset-TmxCaptura

        Mock Invoke-TmxCleanmgr -ModuleName TweakMaxing {
            Add-TmxChamada ([pscustomobject]@{ alvo = 'cleanmgr'; args = @($Arguments) })
            [pscustomobject]@{ saida = ''; codigo = 0 }
        }
        Mock Invoke-TmxDism -ModuleName TweakMaxing {
            Add-TmxChamada ([pscustomobject]@{ alvo = 'dism'; args = @($Arguments) })
            [pscustomobject]@{ saida = ''; codigo = 0 }
        }
        Mock Remove-TmxItemPath -ModuleName TweakMaxing {
            Add-TmxChamada ([pscustomobject]@{ alvo = 'remove'; path = $Path })
        }
    }

    It 'a limpeza de disco registra a execucao antes de rodar os comandos' {
        $r = Set-TmxDiskCleanup -Tweak (New-TmxTweakFake -Id 'MAN-003') -Profile $script:Perfil -Parametros $null
        $r.ok | Should -BeTrue
        $global:TmxT_StateNoWrapper   | Should -Match '"irreversivel":\s*true'
        $global:TmxT_Chamadas[0].alvo | Should -Be 'cleanmgr'
        $global:TmxT_Chamadas[1].alvo | Should -Be 'dism'
    }

    It 'a limpeza de TEMP apaga as duas pastas' {
        $r = Set-TmxTempFiles -Tweak (New-TmxTweakFake -Id 'MAN-004') -Profile $script:Perfil -Parametros $null
        $r.ok | Should -BeTrue
        @($global:TmxT_Chamadas).Count | Should -Be 2
    }

    It 'Undo das duas acoes lanca dizendo que e irreversivel' {
        { Undo-TmxDiskCleanup -Estado @{} } | Should -Throw -ExpectedMessage '*irreversivel*'
        { Undo-TmxTempFiles   -Estado @{} } | Should -Throw -ExpectedMessage '*irreversivel*'
    }

    It 'Test devolve aplicado = $null porque nao ha estado a verificar' {
        (Test-TmxDiskCleanup -Tweak (New-TmxTweakFake -Id 'MAN-003') -Profile $script:Perfil).aplicado | Should -BeNullOrEmpty
        (Test-TmxTempFiles   -Tweak (New-TmxTweakFake -Id 'MAN-004') -Profile $script:Perfil).aplicado | Should -BeNullOrEmpty
    }
}

Describe 'Set-TmxOosu' -Tag 'Tweaks' {

    BeforeEach {
        $script:run = New-TmxRun
        $global:TmxT_StatePath = $script:run.StatePath
        Reset-TmxCaptura
        Mock Start-TmxUrl -ModuleName TweakMaxing {
            Add-TmxChamada ([pscustomobject]@{ url = $Url })
            $Url
        }
    }

    It 'abre apenas a URL oficial em https e nao cria registro' {
        $r = Set-TmxOosu -Tweak (New-TmxTweakFake -Id 'PRI-008') -Profile $script:Perfil -Parametros $null
        $r.ok | Should -BeTrue
        $global:TmxT_Chamadas[0].url | Should -Be 'https://www.oo-software.com/en/shutup10'
        $global:TmxT_Chamadas[0].url | Should -Match '^https://'

        @(Get-TmxRegistrosDoDisco $script:run.StatePath).Count | Should -Be 0
    }

    It 'Test nao tem o que verificar e Undo nao tem o que desfazer' {
        (Test-TmxOosu -Tweak (New-TmxTweakFake -Id 'PRI-008') -Profile $script:Perfil).aplicado | Should -BeNullOrEmpty
        Undo-TmxOosu -Estado $null | Should -Match 'nada a reverter'
    }
}

Describe 'Start-TmxUrl' -Tag 'Tweaks' {

    It 'recusa qualquer esquema que nao seja https' {
        { Start-TmxUrl -Url 'http://exemplo.com' }   | Should -Throw -ExpectedMessage '*https*'
        { Start-TmxUrl -Url 'file:///C:/windows' }   | Should -Throw -ExpectedMessage '*https*'
        { Start-TmxUrl -Url 'C:\windows\system32' }  | Should -Throw -ExpectedMessage '*https*'
    }
}

Describe 'Set-TmxExplorerRestart' -Tag 'Tweaks' {

    BeforeEach {
        $script:run = New-TmxRun
        $global:TmxT_StatePath = $script:run.StatePath
        Reset-TmxCaptura
        Mock Restart-TmxExplorer -ModuleName TweakMaxing { Add-TmxChamada ([pscustomobject]@{ acao = 'restart' }) }
    }

    It 'reinicia o Explorer sem criar registro de estado' {
        $r = Set-TmxExplorerRestart -Tweak (New-TmxTweakFake -Id 'INT-009') -Profile $script:Perfil -Parametros $null
        $r.ok | Should -BeTrue
        $r.PSObject.Properties['registro'] | Should -BeNullOrEmpty
        @(Get-TmxRegistrosDoDisco $script:run.StatePath).Count | Should -Be 0
    }

    It 'Undo reinicia de novo e Test nao tem estado' {
        Undo-TmxExplorerRestart -Estado $null | Should -Match 'Explorer'
        (Test-TmxExplorerRestart -Tweak (New-TmxTweakFake -Id 'INT-009') -Profile $script:Perfil).aplicado | Should -BeNullOrEmpty
    }
}

Describe 'Set-TmxRemoveEdge' -Tag 'Tweaks' {

    BeforeEach {
        $script:run = New-TmxRun
        $global:TmxT_StatePath = $script:run.StatePath
        Reset-TmxCaptura
        $global:TmxT_EdgeSetup = 'C:\Program Files (x86)\Microsoft\Edge\Application\120.0\Installer\setup.exe'

        Mock Get-TmxEdgeSetupPath -ModuleName TweakMaxing { $global:TmxT_EdgeSetup }
        Mock Test-TmxItemPath -ModuleName TweakMaxing { $true }
        Mock Invoke-TmxProcess -ModuleName TweakMaxing {
            Add-TmxChamada ([pscustomobject]@{ exe = $FilePath; args = @($ArgumentList) })
            $global:TmxT_EdgeSetup = $null
            [pscustomobject]@{ codigo = 0 }
        }
        Mock Invoke-TmxWinget -ModuleName TweakMaxing {
            Add-TmxChamada ([pscustomobject]@{ alvo = 'winget'; args = @($Arguments) })
            [pscustomobject]@{ saida = ''; codigo = 0 }
        }
    }

    It 'chama o desinstalador oficial com argumentos em array' {
        $r = Set-TmxRemoveEdge -Tweak (New-TmxTweakFake -Id 'APM-002') -Profile $script:Perfil -Parametros $null
        $r.ok | Should -BeTrue
        $global:TmxT_StateNoWrapper   | Should -Match '"funcao":\s*"Set-TmxRemoveEdge"'
        $global:TmxT_Chamadas[0].args | Should -Contain '--uninstall'
        $global:TmxT_Chamadas[0].args | Should -Contain '--force-uninstall'
    }

    It 'marca naoAplicavel quando o Edge nao esta instalado' {
        $global:TmxT_EdgeSetup = $null
        $r = Set-TmxRemoveEdge -Tweak (New-TmxTweakFake -Id 'APM-002') -Profile $script:Perfil -Parametros $null
        $r.naoAplicavel | Should -BeTrue
    }

    It 'Test fica verdadeiro quando o setup.exe some' {
        $t = New-TmxTweakFake -Id 'APM-002'
        (Test-TmxRemoveEdge -Tweak $t -Profile $script:Perfil).aplicado | Should -BeFalse
        Set-TmxRemoveEdge -Tweak $t -Profile $script:Perfil -Parametros $null | Out-Null
        (Test-TmxRemoveEdge -Tweak $t -Profile $script:Perfil).aplicado | Should -BeTrue
    }

    It 'Undo reinstala pelo winget' {
        Undo-TmxRemoveEdge -Estado @{ pacoteWinget = 'Microsoft.Edge' } | Should -Match 'winget'
        $global:TmxT_Chamadas[0].args | Should -Contain 'Microsoft.Edge'
    }
}

Describe 'Set-TmxUltimatePowerPlan' -Tag 'Tweaks' {

    BeforeEach {
        $script:run = New-TmxRun
        $global:TmxT_StatePath = $script:run.StatePath
        Reset-TmxCaptura
        $global:TmxT_NovoGuid = '11111111-2222-3333-4444-555555555555'

        Mock Get-TmxActivePowerScheme -ModuleName TweakMaxing {
            [pscustomobject]@{ guid = '381b4222-f694-41f0-9685-ff5bb260df2e'; nome = 'Equilibrado' }
        }
        Mock Invoke-TmxPowercfg -ModuleName TweakMaxing {
            Add-TmxChamada ([pscustomobject]@{ args = @($Arguments) })
            if ($Arguments -contains '/duplicatescheme') {
                return [pscustomobject]@{ saida = "GUID do Esquema de Energia: $($global:TmxT_NovoGuid)  (Desempenho maximo)"; codigo = 0 }
            }
            [pscustomobject]@{ saida = ''; codigo = 0 }
        }
    }

    It 'guarda o esquema anterior e o GUID criado antes de ativar' {
        $r = Set-TmxUltimatePowerPlan -Tweak (New-TmxTweakFake -Id 'ENE-004') -Profile $script:Perfil -Parametros $null
        $r.ok | Should -BeTrue

        $global:TmxT_Chamadas[0].args | Should -Contain '/duplicatescheme'
        $global:TmxT_Chamadas[1].args | Should -Contain '/setactive'

        $recs = @(Get-TmxRegistrosDoDisco $script:run.StatePath)
        $recs[0].detalhe.estado.esquemaAnterior | Should -Be '381b4222-f694-41f0-9685-ff5bb260df2e'
        $recs[0].detalhe.estado.esquemaCriado   | Should -Be $global:TmxT_NovoGuid
    }

    It 'Undo reativa o esquema anterior e apaga o duplicado' {
        Undo-TmxUltimatePowerPlan -Estado @{
            esquemaAnterior = '381b4222-f694-41f0-9685-ff5bb260df2e'
            nomeAnterior    = 'Equilibrado'
            esquemaCriado   = $global:TmxT_NovoGuid
        } | Out-Null

        $global:TmxT_Chamadas[0].args | Should -Contain '/setactive'
        $global:TmxT_Chamadas[1].args | Should -Contain '/delete'
        $global:TmxT_Chamadas[1].args | Should -Contain $global:TmxT_NovoGuid
    }
}

Describe 'Set-TmxRemoveUltimatePowerPlan' -Tag 'Tweaks' {

    BeforeEach {
        $script:run = New-TmxRun
        $global:TmxT_StatePath = $script:run.StatePath
        Reset-TmxCaptura
        $global:TmxT_Esquemas = @(
            'GUID do Esquema de Energia: 381b4222-f694-41f0-9685-ff5bb260df2e  (Equilibrado) *',
            'GUID do Esquema de Energia: 99999999-8888-7777-6666-555555555555  (Desempenho maximo)'
        )

        Mock Invoke-TmxPowercfg -ModuleName TweakMaxing {
            if ($Arguments -contains '/list') {
                return [pscustomobject]@{ saida = ($global:TmxT_Esquemas -join "`n"); codigo = 0 }
            }
            Add-TmxChamada ([pscustomobject]@{ args = @($Arguments) })
            if ($Arguments -contains '/delete') { $global:TmxT_Esquemas = @($global:TmxT_Esquemas[0]) }
            if ($Arguments -contains '/duplicatescheme') {
                return [pscustomobject]@{ saida = 'GUID do Esquema de Energia: aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee  (Desempenho maximo)'; codigo = 0 }
            }
            [pscustomobject]@{ saida = ''; codigo = 0 }
        }
    }

    It 'registra os GUIDs antes de apagar os planos duplicados' {
        $r = Set-TmxRemoveUltimatePowerPlan -Tweak (New-TmxTweakFake -Id 'ENE-005') -Profile $script:Perfil -Parametros $null
        $r.ok | Should -BeTrue
        $global:TmxT_StateNoWrapper   | Should -Match '99999999-8888-7777-6666-555555555555'
        $global:TmxT_Chamadas[0].args | Should -Contain '/delete'
    }

    It 'Test fica verdadeiro quando nao sobra plano de Desempenho Maximo' {
        $t = New-TmxTweakFake -Id 'ENE-005'
        (Test-TmxRemoveUltimatePowerPlan -Tweak $t -Profile $script:Perfil).aplicado | Should -BeFalse
        Set-TmxRemoveUltimatePowerPlan -Tweak $t -Profile $script:Perfil -Parametros $null | Out-Null
        (Test-TmxRemoveUltimatePowerPlan -Tweak $t -Profile $script:Perfil).aplicado | Should -BeTrue
    }

    It 'Undo recria um plano para cada um que havia sido removido' {
        Undo-TmxRemoveUltimatePowerPlan -Estado @{
            modelo   = 'e9a42b02-d5df-448d-aa00-03f14749eb61'
            esquemas = @(@{ guid = '99999999-8888-7777-6666-555555555555'; nome = 'Desempenho maximo' })
        } | Should -Match 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
        $global:TmxT_Chamadas[0].args | Should -Contain '/duplicatescheme'
    }
}

Describe 'Set-TmxRazerBlock' -Tag 'Tweaks' {

    BeforeEach {
        $script:run = New-TmxRun
        $global:TmxT_StatePath = $script:run.StatePath
        Reset-TmxCaptura
        $global:TmxT_Acl = 'Everyone:(F)'

        Mock Test-TmxItemPath -ModuleName TweakMaxing { $true }
        Mock Remove-TmxItemPath -ModuleName TweakMaxing { }
        Mock New-TmxDirectory -ModuleName TweakMaxing { $Path }
        Mock Stop-TmxProcessByName -ModuleName TweakMaxing { }
        Mock Invoke-TmxIcacls -ModuleName TweakMaxing {
            if ($Arguments.Count -gt 1) {
                Add-TmxChamada ([pscustomobject]@{ args = @($Arguments) })
                if ($Arguments -contains '/deny')      { $global:TmxT_Acl = 'Everyone:(DENY)(W)' }
                if ($Arguments -contains '/remove:d')  { $global:TmxT_Acl = 'Everyone:(F)' }
            }
            [pscustomobject]@{ saida = $global:TmxT_Acl; codigo = 0 }
        }
    }

    It 'nega escrita na pasta e registra antes' {
        $r = Set-TmxRazerBlock -Tweak (New-TmxTweakFake -Id 'SIS-008') -Profile $script:Perfil -Parametros $null
        $r.ok | Should -BeTrue
        $global:TmxT_StateNoWrapper   | Should -Match '"funcao":\s*"Set-TmxRazerBlock"'
        $global:TmxT_Chamadas[0].args | Should -Contain '/deny'
        $global:TmxT_Chamadas[0].args | Should -Contain '*S-1-1-0:(W)'
    }

    It 'Test detecta a negacao e Undo a remove' {
        $t = New-TmxTweakFake -Id 'SIS-008'
        (Test-TmxRazerBlock -Tweak $t -Profile $script:Perfil).aplicado | Should -BeFalse
        Set-TmxRazerBlock -Tweak $t -Profile $script:Perfil -Parametros $null | Out-Null
        (Test-TmxRazerBlock -Tweak $t -Profile $script:Perfil).aplicado | Should -BeTrue

        Undo-TmxRazerBlock -Estado @{ pasta = 'C:\Windows\Installer\Razer' } | Out-Null
        (Test-TmxRazerBlock -Tweak $t -Profile $script:Perfil).aplicado | Should -BeFalse
    }
}

Describe 'Set-TmxAdobeBlock' -Tag 'Tweaks' {

    BeforeEach {
        $script:run = New-TmxRun
        $global:TmxT_StatePath = $script:run.StatePath
        Reset-TmxCaptura
        $global:TmxT_Hosts = '127.0.0.1 localhost'

        Mock Test-TmxItemPath -ModuleName TweakMaxing { $true }
        Mock Get-TmxFileText -ModuleName TweakMaxing { $global:TmxT_Hosts }
        Mock Copy-TmxItemPath -ModuleName TweakMaxing {
            Add-TmxChamada ([pscustomobject]@{ acao = 'copy'; de = $Path; para = $Destino })
            $Destino
        }
        Mock Invoke-TmxWebRequestText -ModuleName TweakMaxing {
            Add-TmxChamada ([pscustomobject]@{ acao = 'download'; uri = $Uri })
            "0.0.0.0 activate.adobe.com"
        }
        Mock Add-TmxFileText -ModuleName TweakMaxing {
            Add-TmxChamada ([pscustomobject]@{ acao = 'append'; path = $Path })
            $global:TmxT_Hosts = "$($global:TmxT_Hosts)`n$Texto"
        }
        Mock Invoke-TmxIpconfig -ModuleName TweakMaxing { [pscustomobject]@{ saida = ''; codigo = 0 } }
    }

    It 'faz backup do hosts ANTES de baixar qualquer coisa' {
        $r = Set-TmxAdobeBlock -Tweak (New-TmxTweakFake -Id 'RED-002') -Profile $script:Perfil -Parametros $null
        $r.ok | Should -BeTrue

        $global:TmxT_Chamadas[0].acao | Should -Be 'copy'
        $global:TmxT_Chamadas[1].acao | Should -Be 'download'
        $global:TmxT_Chamadas[2].acao | Should -Be 'append'
        $global:TmxT_Chamadas[1].uri  | Should -Match '^https://'
    }

    It 'Test enxerga os dominios da Adobe no hosts' {
        $t = New-TmxTweakFake -Id 'RED-002'
        (Test-TmxAdobeBlock -Tweak $t -Profile $script:Perfil).aplicado | Should -BeFalse
        Set-TmxAdobeBlock -Tweak $t -Profile $script:Perfil -Parametros $null | Out-Null
        (Test-TmxAdobeBlock -Tweak $t -Profile $script:Perfil).aplicado | Should -BeTrue
    }

    It 'Undo restaura o arquivo a partir do backup guardado' {
        $bak = Join-Path $script:run.RunPath 'hosts.bak'
        Undo-TmxAdobeBlock -Estado @{ hosts = 'C:\Windows\System32\drivers\etc\hosts'; backup = $bak } | Should -Match 'hosts.bak'
        $global:TmxT_Chamadas[0].de | Should -Be $bak
    }

    It 'Undo sem backup no estado falha alto em vez de adivinhar' {
        { Undo-TmxAdobeBlock -Estado @{} } | Should -Throw -ExpectedMessage '*backup*'
    }
}

Describe 'Set-TmxRightClickMenu' -Tag 'Tweaks' {

    BeforeEach {
        $script:run = New-TmxRun
        $global:TmxT_StatePath = $script:run.StatePath
        Reset-TmxCaptura
        $global:TmxT_ChaveExiste = $false

        Mock Set-TmxRegistry -ModuleName TweakMaxing {
            Add-TmxChamada ([pscustomobject]@{ path = $Path; name = $Name; valor = $Value })
            $global:TmxT_ChaveExiste = $true
            [pscustomobject]@{ status = 'aplicado'; erro = $null; tipo = 'registry' }
        }
        Mock Test-TmxItemPath -ModuleName TweakMaxing { $global:TmxT_ChaveExiste }
        Mock Remove-TmxItemPath -ModuleName TweakMaxing {
            Add-TmxChamada ([pscustomobject]@{ acao = 'remove'; path = $Path })
            $global:TmxT_ChaveExiste = $false
        }
        Mock Restart-TmxExplorer -ModuleName TweakMaxing { }
    }

    It 'cria o InprocServer32 vazio e devolve o registro do Core' {
        $t = New-TmxTweakFake -Id 'INT-007'
        (Test-TmxRightClickMenu -Tweak $t -Profile $script:Perfil).aplicado | Should -BeFalse

        $r = Set-TmxRightClickMenu -Tweak $t -Profile $script:Perfil -Parametros $null
        $r.ok | Should -BeTrue
        $r.registro.tipo | Should -Be 'registry'
        $global:TmxT_Chamadas[0].path | Should -Match 'InprocServer32$'
        $global:TmxT_Chamadas[0].name | Should -Be '(Default)'

        (Test-TmxRightClickMenu -Tweak $t -Profile $script:Perfil).aplicado | Should -BeTrue
    }

    It 'Undo remove a chave do CLSID' {
        $global:TmxT_ChaveExiste = $true
        Undo-TmxRightClickMenu -Estado @{ chave = 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}' } | Out-Null
        $global:TmxT_Chamadas[0].acao | Should -Be 'remove'
        $global:TmxT_ChaveExiste | Should -BeFalse
    }
}

Describe 'Set-TmxExplorerAutoDiscovery' -Tag 'Tweaks' {

    BeforeEach {
        $script:run = New-TmxRun
        $global:TmxT_StatePath = $script:run.StatePath
        Reset-TmxCaptura
        $global:TmxT_FolderType = $null

        Mock Test-TmxItemPath -ModuleName TweakMaxing { $true }
        Mock Backup-TmxRegistryHive -ModuleName TweakMaxing {
            $arquivo = Join-Path $script:run.RegBackupPath (($Path -replace '[\\/:*?"<>|]', '_') + '.reg')
            Add-TmxChamada ([pscustomobject]@{ acao = 'export'; chave = $Path; arquivo = $arquivo })
            $arquivo
        }
        Mock Remove-TmxItemPath -ModuleName TweakMaxing {
            Add-TmxChamada ([pscustomobject]@{ acao = 'remove'; path = $Path })
        }
        Mock Set-TmxRegistry -ModuleName TweakMaxing {
            Add-TmxChamada ([pscustomobject]@{ acao = 'set'; path = $Path; name = $Name; valor = $Value })
            $global:TmxT_FolderType = $Value
            [pscustomobject]@{ status = 'aplicado'; erro = $null; tipo = 'registry' }
        }
        Mock Get-TmxRegistryValue -ModuleName TweakMaxing { $global:TmxT_FolderType }
        Mock Invoke-TmxRegImport -ModuleName TweakMaxing {
            Add-TmxChamada ([pscustomobject]@{ acao = 'import'; arquivo = $Arquivo })
            [pscustomobject]@{ saida = ''; codigo = 0 }
        }
    }

    It 'exporta Bags e BagMRU antes de remover' {
        $r = Set-TmxExplorerAutoDiscovery -Tweak (New-TmxTweakFake -Id 'DES-002') -Profile $script:Perfil -Parametros $null
        $r.ok | Should -BeTrue

        $acoes = @($global:TmxT_Chamadas | ForEach-Object { $_.acao })
        $acoes[0] | Should -Be 'export'
        $acoes[1] | Should -Be 'export'
        $acoes[2] | Should -Be 'remove'
        $acoes[3] | Should -Be 'remove'
        $acoes[4] | Should -Be 'set'
    }

    It 'Test compara o FolderType com NotSpecified' {
        $t = New-TmxTweakFake -Id 'DES-002'
        (Test-TmxExplorerAutoDiscovery -Tweak $t -Profile $script:Perfil).aplicado | Should -BeFalse
        Set-TmxExplorerAutoDiscovery -Tweak $t -Profile $script:Perfil -Parametros $null | Out-Null
        (Test-TmxExplorerAutoDiscovery -Tweak $t -Profile $script:Perfil).aplicado | Should -BeTrue
    }

    It 'Undo reimporta os .reg exportados' {
        $exports = @('C:\run\regbackup\bags.reg', 'C:\run\regbackup\bagmru.reg')
        Undo-TmxExplorerAutoDiscovery -Estado @{ exports = $exports } | Should -Match 'bagmru.reg'
        @($global:TmxT_Chamadas | Where-Object { $_.acao -eq 'import' }).Count | Should -Be 2
    }

    It 'Undo sem export no estado falha alto' {
        { Undo-TmxExplorerAutoDiscovery -Estado $null } | Should -Throw -ExpectedMessage '*sem estado*'
    }
}
