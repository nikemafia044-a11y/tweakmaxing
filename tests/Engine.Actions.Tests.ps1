# Testes do engine de acoes (src/Engine/Actions.ps1 + Apply.ps1).
#
# Registro e testado de verdade em HKCU:\Software\TweakMaxing_Tests\Engine\Actions;
# servico, tarefa agendada, appx, recurso do Windows, powercfg, netadapter e
# bcdedit passam por mocks dos wrappers.
#
# Cada tipo prova tres coisas:
#   (a) o registro de estado esta no disco ANTES do wrapper ser chamado
#       (o mock le o state.json de dentro dele mesmo);
#   (b) Test-TmxAction reflete o estado depois da aplicacao;
#   (c) Undo-TweakMaxing -Latest chama o wrapper inverso com o valor anterior
#       capturado (o Core despacha 'scheduledTask'/'appx'/'feature' para os
#       Undo-Tmx<Tipo>Record deste arquivo).

. "$PSScriptRoot\_Helpers.ps1"

BeforeAll {
    . "$PSScriptRoot\_Helpers.ps1"
    Import-TmxTestModule
    New-TmxTestHome | Out-Null

    $script:Raiz   = 'HKCU:\Software\TweakMaxing_Tests\Engine\Actions'
    $script:Perfil = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'fixtures\profile-engine.json') -Raw -Encoding UTF8 | ConvertFrom-Json

    # --- helpers de fixture -------------------------------------------------
    function script:New-TmxAcaoRegistro {
        param(
            [Parameter(Mandatory)] [string] $Sub,
            [Parameter(Mandatory)] [string] $Nome,
            $Valor,
            [string] $Tipo = 'DWord',
            [switch] $Remover
        )
        $o = [pscustomobject]@{
            tipo      = 'registry'
            path      = "HKCU:\Software\TweakMaxing_Tests\Engine\Actions\$Sub"
            name      = $Nome
            value     = $Valor
            valueType = $Tipo
        }
        if ($Remover) { $o | Add-Member -NotePropertyName 'remove' -NotePropertyValue $true }
        $o
    }

    function script:New-TmxTweakTeste {
        param(
            [Parameter(Mandatory)] [string] $Id,
            [Parameter(Mandatory)] [object[]] $Acoes,
            [switch] $Consentimento,
            [string] $Reversivel = 'total',
            [string] $PosAplicar = $null
        )
        [pscustomobject]@{
            id                       = $Id
            nome                     = "Teste $Id"
            descricao                = 'tweak de teste'
            categoria                = 'Teste'
            tier                     = 'MEDIDO'
            risco                    = 'baixo'
            presets                  = @('desktop')
            controle                 = 'checkbox'
            opcoes                   = @()
            reversivel               = $Reversivel
            requerReboot             = $false
            requerConsentimentoExtra = [bool]$Consentimento
            consentimento            = $null
            condicoes                = [pscustomobject]@{ requer = @(); bloqueiaSe = @() }
            porque                   = 'teste'
            evidencia                = 'teste'
            folclore                 = $null
            posAplicar               = $PosAplicar
            acoes                    = @($Acoes)
        }
    }

    function script:New-TmxPlanoTeste {
        param(
            [Parameter(Mandatory)] [object[]] $Tweaks,
            [string[]] $Consentidos = @()
        )
        $itens = foreach ($t in $Tweaks) {
            [pscustomobject]@{
                id               = $t.id
                nome             = $t.nome
                categoria        = $t.categoria
                tier             = $t.tier
                risco            = $t.risco
                reversivel       = $t.reversivel
                controle         = $t.controle
                status           = 'selecionado'
                selecionado      = $true
                alternavel       = $true
                consentido       = ($Consentidos -contains $t.id)
                exigeConfirmacao = [bool]$t.requerConsentimentoExtra
                motivos          = @()
                condicoes        = @()
                estadoAtual      = $null
                tweak            = $t
            }
        }
        [pscustomobject]@{ preset = 'desktop'; geradoEm = (Get-Date).ToString('o'); itens = @($itens); resumo = @{} }
    }

    function script:Get-TmxValorTeste {
        param([string] $Sub, [string] $Nome)
        (Get-ItemProperty -LiteralPath "HKCU:\Software\TweakMaxing_Tests\Engine\Actions\$Sub" -Name $Nome -ErrorAction SilentlyContinue).$Nome
    }

    function script:Get-TmxRegistrosDoDisco {
        param([Parameter(Mandatory)] [string] $Caminho)
        if (-not (Test-Path -LiteralPath $Caminho)) { return @() }
        $dados = Get-Content -LiteralPath $Caminho -Raw -Encoding UTF8 | ConvertFrom-Json
        @($dados.registros | Where-Object { $null -ne $_ })
    }

    # --- funcoes customizadas usadas pelo tipo de acao 'funcao' -------------
    function global:Set-TmxFake {
        param($Tweak, $Profile, $Parametros)
        $null = $global:TmxT_FakeChamadas.Add([pscustomobject]@{ TweakId = "$($Tweak.id)"; Valor = "$($Parametros.valor)"; Perfil = "$($Profile.os.nome)" })
        $rec = New-TmxCmdletRecord -TweakId "$($Tweak.id)" -Funcao 'Set-TmxFake' -Alvo 'estado falso' `
                -Estado @{ valor = $global:TmxT_FakeValor } -ValorAnterior $global:TmxT_FakeValor -ValorNovo "$($Parametros.valor)"
        $global:TmxT_StateNoSet = Get-Content -LiteralPath $global:TmxT_StatePath -Raw
        $global:TmxT_FakeValor = "$($Parametros.valor)"
        Complete-TmxStateRecord -Record $rec -Ok $true | Out-Null
        [pscustomobject]@{ ok = $true; detalhe = 'fake aplicado'; naoAplicavel = $false; naoSuportado = $false; registro = $rec }
    }
    function global:Test-TmxFake {
        param($Tweak, $Profile)
        [pscustomobject]@{
            aplicado = ("$($global:TmxT_FakeValor)" -eq 'novo')
            atual    = "$($global:TmxT_FakeValor)"
            esperado = 'novo'
            detalhe  = "fake = $($global:TmxT_FakeValor)"
        }
    }
    function global:Undo-TmxFake {
        param($Estado)
        $global:TmxT_FakeValor = "$($Estado.valor)"
        "fake restaurado para $($Estado.valor)"
    }

    # Par Set-/Test- em que a funcao de VERIFICACAO tambem declara
    # -Parametros: e o caso que Test-TmxAction passou a atender.
    function global:Set-TmxFakeP {
        param($Tweak, $Profile, $Parametros)
        [pscustomobject]@{ ok = $true; detalhe = 'fakep aplicado'; naoAplicavel = $false; naoSuportado = $false; registro = $null }
    }
    function global:Test-TmxFakeP {
        param($Tweak, $Profile, $Parametros)
        $global:TmxT_FakePParametros = $Parametros
        [pscustomobject]@{
            aplicado = ("$($Parametros.raiz)" -eq 'raiz-de-teste')
            atual    = "$($Parametros.raiz)"
            esperado = 'raiz-de-teste'
            detalhe  = "fakep raiz = $($Parametros.raiz)"
        }
    }

    function global:Set-TmxFalha {
        param($Tweak, $Profile, $Parametros)
        [pscustomobject]@{ ok = $false; detalhe = 'falhou de proposito'; naoAplicavel = $false; naoSuportado = $false; registro = $null }
    }
    function global:Test-TmxFalha {
        param($Tweak, $Profile)
        [pscustomobject]@{ aplicado = $false; atual = 'ruim'; esperado = 'bom'; detalhe = 'sempre falso' }
    }

}

AfterAll {
    Remove-Item -LiteralPath 'HKCU:\Software\TweakMaxing_Tests\Engine\Actions' -Recurse -Force -ErrorAction SilentlyContinue
    foreach ($fn in 'Set-TmxFake', 'Test-TmxFake', 'Undo-TmxFake', 'Set-TmxFakeP', 'Test-TmxFakeP', 'Set-TmxFalha', 'Test-TmxFalha') {
        Remove-Item -LiteralPath "Function:\$fn" -Force -ErrorAction SilentlyContinue
    }
    Remove-TmxTestHome
    Stop-TmxLogger
    Remove-Module TweakMaxing -Force -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------------------

Describe 'Invoke-TmxAction registry' -Tag 'Engine' {

    BeforeEach {
        Remove-Item -LiteralPath $script:Raiz -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -Path "$script:Raiz\Reg" -Force | Out-Null
        $script:run = New-TmxRun
    }

    It 'grava o valor, persiste o estado anterior e o undo restaura' {
        New-ItemProperty -LiteralPath "$script:Raiz\Reg" -Name 'V' -Value 10 -PropertyType DWord -Force | Out-Null
        $a = New-TmxAcaoRegistro -Sub 'Reg' -Nome 'V' -Valor 99
        $t = New-TmxTweakTeste -Id 'REG-001' -Acoes @($a)

        (Test-TmxAction -Action $a -Tweak $t -Profile $script:Perfil).aplicado | Should -BeFalse

        $r = Invoke-TmxAction -Action $a -Tweak $t -Profile $script:Perfil
        $r.ok           | Should -BeTrue
        $r.naoSuportado | Should -BeFalse
        (Get-TmxValorTeste 'Reg' 'V') | Should -Be 99
        (Test-TmxAction -Action $a -Tweak $t -Profile $script:Perfil).aplicado | Should -BeTrue

        $recs = @(Get-TmxRegistrosDoDisco $script:run.StatePath)
        $recs.Count             | Should -Be 1
        $recs[0].tipo           | Should -Be 'registry'
        $recs[0].valorAnterior  | Should -Be 10
        $recs[0].existiaAntes   | Should -BeTrue

        Undo-TweakMaxing -Latest 6> $null | Out-Null
        (Get-TmxValorTeste 'Reg' 'V') | Should -Be 10
    }

    It 'Test-TmxTweakApplied so e true quando todas as acoes estao no alvo' {
        $a1 = New-TmxAcaoRegistro -Sub 'Reg' -Nome 'A' -Valor 1
        $a2 = New-TmxAcaoRegistro -Sub 'Reg' -Nome 'B' -Valor 'texto' -Tipo 'String'
        $t  = New-TmxTweakTeste -Id 'REG-002' -Acoes @($a1, $a2)

        (Test-TmxTweakApplied -Tweak $t -Profile $script:Perfil).aplicado | Should -BeFalse

        Invoke-TmxAction -Action $a1 -Tweak $t -Profile $script:Perfil | Out-Null
        (Test-TmxTweakApplied -Tweak $t -Profile $script:Perfil).aplicado | Should -BeFalse

        Invoke-TmxAction -Action $a2 -Tweak $t -Profile $script:Perfil | Out-Null
        $agg = Test-TmxTweakApplied -Tweak $t -Profile $script:Perfil
        $agg.aplicado | Should -BeTrue
        $agg.atual    | Should -Match '1'
        $agg.atual    | Should -Match 'texto'
    }

    It 'DWord com bit alto (0xFFFFFFFF) grava e compara sem estourar int32' {
        $a = New-TmxAcaoRegistro -Sub 'Reg' -Nome 'Big' -Valor 4294967295
        $t = New-TmxTweakTeste -Id 'REG-003' -Acoes @($a)
        (Invoke-TmxAction -Action $a -Tweak $t -Profile $script:Perfil).ok | Should -BeTrue
        ([int64](Get-TmxValorTeste 'Reg' 'Big') -band 0xFFFFFFFF) | Should -Be 4294967295
        (Test-TmxAction -Action $a -Tweak $t -Profile $script:Perfil).aplicado | Should -BeTrue
    }

    It 'acao com remove apaga o valor e o undo o recria' {
        New-ItemProperty -LiteralPath "$script:Raiz\Reg" -Name 'Sumir' -Value 42 -PropertyType DWord -Force | Out-Null
        $a = New-TmxAcaoRegistro -Sub 'Reg' -Nome 'Sumir' -Remover
        $t = New-TmxTweakTeste -Id 'REG-004' -Acoes @($a)

        (Test-TmxAction -Action $a -Tweak $t -Profile $script:Perfil).aplicado | Should -BeFalse

        $r = Invoke-TmxAction -Action $a -Tweak $t -Profile $script:Perfil
        $r.ok | Should -BeTrue
        (Get-TmxValorTeste 'Reg' 'Sumir') | Should -BeNullOrEmpty
        (Test-TmxAction -Action $a -Tweak $t -Profile $script:Perfil).aplicado | Should -BeTrue

        Undo-TweakMaxing -Latest 6> $null | Out-Null
        (Get-TmxValorTeste 'Reg' 'Sumir') | Should -Be 42
    }

    It 'String compara sem diferenciar maiusculas' {
        New-ItemProperty -LiteralPath "$script:Raiz\Reg" -Name 'Caixa' -Value 'Habilitado' -PropertyType String -Force | Out-Null
        $a = New-TmxAcaoRegistro -Sub 'Reg' -Nome 'Caixa' -Valor 'habilitado' -Tipo 'String'
        $t = New-TmxTweakTeste -Id 'REG-005' -Acoes @($a)
        (Test-TmxAction -Action $a -Tweak $t -Profile $script:Perfil).aplicado | Should -BeTrue
    }
}

Describe 'Invoke-TmxAction service' -Tag 'Engine' {

    BeforeEach {
        $script:run = New-TmxRun
        $global:TmxT_StatePath  = $script:run.StatePath
        $global:TmxT_StateNoSet = $null
        $global:TmxT_Svc        = New-Object System.Collections.ArrayList
        $global:TmxT_SvcEstado  = [pscustomobject]@{ startType = 'Automatic'; status = 'Running' }

        Mock Get-TmxServiceState -ModuleName TweakMaxing { $global:TmxT_SvcEstado }
        Mock Set-TmxServiceState -ModuleName TweakMaxing {
            if (-not $global:TmxT_StateNoSet) { $global:TmxT_StateNoSet = Get-Content -LiteralPath $global:TmxT_StatePath -Raw -Encoding UTF8 }
            $null = $global:TmxT_Svc.Add([pscustomobject]@{ Nome = $Nome; StartType = $StartType; Parar = [bool]$Parar; Iniciar = [bool]$Iniciar })
        }
    }

    It 'captura startType/status antes de mexer e a reversao devolve o original' {
        $a = [pscustomobject]@{ tipo = 'service'; nome = 'DiagTrack'; tipoInicio = 'Disabled'; parar = $true }
        $t = New-TmxTweakTeste -Id 'SVC-001' -Acoes @($a)

        (Test-TmxAction -Action $a -Tweak $t -Profile $script:Perfil).aplicado | Should -BeFalse

        $r = Invoke-TmxAction -Action $a -Tweak $t -Profile $script:Perfil
        $r.ok | Should -BeTrue
        $global:TmxT_Svc[0].Nome      | Should -Be 'DiagTrack'
        $global:TmxT_Svc[0].StartType | Should -Be 'Disabled'
        $global:TmxT_Svc[0].Parar     | Should -BeTrue

        # (a) o estado anterior ja estava no disco quando o wrapper rodou
        $global:TmxT_StateNoSet | Should -Match '"tipo":\s*"service"'
        $global:TmxT_StateNoSet | Should -Match 'Automatic'
        $global:TmxT_StateNoSet | Should -Match 'Running'

        # (b) verificacao reflete o novo estado
        $global:TmxT_SvcEstado = [pscustomobject]@{ startType = 'Disabled'; status = 'Stopped' }
        (Test-TmxAction -Action $a -Tweak $t -Profile $script:Perfil).aplicado | Should -BeTrue

        # (c) reversao usa o valor capturado
        Undo-TweakMaxing -Latest 6> $null | Out-Null
        $global:TmxT_Svc[1].StartType | Should -Be 'Automatic'
        $global:TmxT_Svc[1].Iniciar   | Should -BeTrue
    }

    It 'nao tenta parar um servico que ja esta parado' {
        $global:TmxT_SvcEstado = [pscustomobject]@{ startType = 'Manual'; status = 'Stopped' }
        $a = [pscustomobject]@{ tipo = 'service'; nome = 'Fax'; tipoInicio = 'Disabled'; parar = $true }
        $t = New-TmxTweakTeste -Id 'SVC-002' -Acoes @($a)

        Invoke-TmxAction -Action $a -Tweak $t -Profile $script:Perfil | Out-Null
        $global:TmxT_Svc[0].Parar | Should -BeFalse
    }
}

Describe 'Invoke-TmxAction scheduledTask' -Tag 'Engine' {

    BeforeEach {
        $script:run = New-TmxRun
        $global:TmxT_StatePath  = $script:run.StatePath
        $global:TmxT_StateNoSet = $null
        $global:TmxT_Task       = New-Object System.Collections.ArrayList
        $global:TmxT_TaskEstado = 'Enabled'

        Mock Get-TmxScheduledTaskState -ModuleName TweakMaxing { $global:TmxT_TaskEstado }
        Mock Set-TmxScheduledTaskState -ModuleName TweakMaxing {
            if (-not $global:TmxT_StateNoSet) { $global:TmxT_StateNoSet = Get-Content -LiteralPath $global:TmxT_StatePath -Raw -Encoding UTF8 }
            $null = $global:TmxT_Task.Add([pscustomobject]@{ Caminho = $Caminho; Nome = $Nome; Estado = $Estado })
            $global:TmxT_TaskEstado = $Estado
        }
    }

    It 'desativa a tarefa, registra o estado anterior e a reversao reativa' {
        $a = [pscustomobject]@{
            tipo    = 'scheduledTask'
            caminho = '\Microsoft\Windows\Application Experience\'
            nome    = 'ProgramDataUpdater'
            estado  = 'Disabled'
        }
        $t = New-TmxTweakTeste -Id 'TSK-001' -Acoes @($a)

        (Test-TmxAction -Action $a -Tweak $t -Profile $script:Perfil).aplicado | Should -BeFalse

        $r = Invoke-TmxAction -Action $a -Tweak $t -Profile $script:Perfil
        $r.ok | Should -BeTrue
        $global:TmxT_Task[0].Nome   | Should -Be 'ProgramDataUpdater'
        $global:TmxT_Task[0].Estado | Should -Be 'Disabled'

        $global:TmxT_StateNoSet | Should -Match '"tipo":\s*"scheduledTask"'
        $global:TmxT_StateNoSet | Should -Match '"valorAnterior":\s*"Enabled"'

        (Test-TmxAction -Action $a -Tweak $t -Profile $script:Perfil).aplicado | Should -BeTrue

        Undo-TweakMaxing -Latest 6> $null | Out-Null
        $global:TmxT_Task[1].Estado | Should -Be 'Enabled'
        $global:TmxT_TaskEstado     | Should -Be 'Enabled'
    }
}

Describe 'Invoke-TmxAction appx' -Tag 'Engine' {

    BeforeEach {
        $script:run = New-TmxRun
        $global:TmxT_StatePath   = $script:run.StatePath
        $global:TmxT_StateNoSet  = $null
        $global:TmxT_AppxExiste  = $true
        $global:TmxT_Removidos   = New-Object System.Collections.ArrayList
        $global:TmxT_Instalados  = New-Object System.Collections.ArrayList

        Mock Get-TmxAppx -ModuleName TweakMaxing {
            if (-not $global:TmxT_AppxExiste) { return }
            [pscustomobject]@{ Name = 'Contoso.Bloat'; PackageFullName = 'Contoso.Bloat_1.2.3.0_x64__8wekyb3d8bbwe' }
        }
        Mock Remove-TmxAppx -ModuleName TweakMaxing {
            if (-not $global:TmxT_StateNoSet) { $global:TmxT_StateNoSet = Get-Content -LiteralPath $global:TmxT_StatePath -Raw -Encoding UTF8 }
            $null = $global:TmxT_Removidos.Add("$PackageFullName")
            $global:TmxT_AppxExiste = $false
        }
        Mock Remove-TmxProvisionedAppx -ModuleName TweakMaxing { }
        Mock Install-TmxStoreApp -ModuleName TweakMaxing {
            $null = $global:TmxT_Instalados.Add("$StoreId")
            $global:TmxT_AppxExiste = $true
            0
        }
    }

    It 'guarda packageFullName e storeId antes de remover; a reversao reinstala pela Store' {
        $a = [pscustomobject]@{ tipo = 'appx'; pacote = 'Contoso.Bloat'; storeId = '9NBLGGH4XYZ'; todosUsuarios = $false }
        $t = New-TmxTweakTeste -Id 'APX-001' -Acoes @($a) -Reversivel 'parcial'

        (Test-TmxAction -Action $a -Tweak $t -Profile $script:Perfil).aplicado | Should -BeFalse

        $r = Invoke-TmxAction -Action $a -Tweak $t -Profile $script:Perfil
        $r.ok | Should -BeTrue
        $global:TmxT_Removidos[0] | Should -Be 'Contoso.Bloat_1.2.3.0_x64__8wekyb3d8bbwe'

        $global:TmxT_StateNoSet | Should -Match '"tipo":\s*"appx"'
        $global:TmxT_StateNoSet | Should -Match 'Contoso\.Bloat_1\.2\.3\.0'
        $global:TmxT_StateNoSet | Should -Match '9NBLGGH4XYZ'
        $global:TmxT_StateNoSet | Should -Match 'reinstalar'

        (Test-TmxAction -Action $a -Tweak $t -Profile $script:Perfil).aplicado | Should -BeTrue

        Undo-TweakMaxing -Latest 6> $null | Out-Null
        $global:TmxT_Instalados[0] | Should -Be '9NBLGGH4XYZ'
    }

    It 'pacote ausente -> naoAplicavel, sem registro de estado' {
        $global:TmxT_AppxExiste = $false
        $a = [pscustomobject]@{ tipo = 'appx'; pacote = 'Contoso.Bloat'; storeId = '9NBLGGH4XYZ'; todosUsuarios = $false }
        $t = New-TmxTweakTeste -Id 'APX-002' -Acoes @($a)

        $r = Invoke-TmxAction -Action $a -Tweak $t -Profile $script:Perfil
        $r.ok           | Should -BeTrue
        $r.naoAplicavel | Should -BeTrue
        @($r.registros).Count | Should -Be 0
        @(Get-TmxRegistrosDoDisco $script:run.StatePath).Count | Should -Be 0
        $global:TmxT_Removidos.Count | Should -Be 0
    }

    It 'sem storeId a reversao falha com instrucao para a Microsoft Store' {
        $a = [pscustomobject]@{ tipo = 'appx'; pacote = 'Contoso.Bloat'; todosUsuarios = $false }
        $t = New-TmxTweakTeste -Id 'APX-003' -Acoes @($a) -Reversivel 'nenhuma'

        (Invoke-TmxAction -Action $a -Tweak $t -Profile $script:Perfil).ok | Should -BeTrue

        $sum = Undo-TweakMaxing -Latest 6> $null
        $item = @($sum.itens | Where-Object { "$($_.tipo)" -eq 'appx' })[0]
        $item.resultado | Should -Be 'falha'
        $item.detalhe   | Should -Match 'Microsoft Store'
        $global:TmxT_Instalados.Count | Should -Be 0
    }

    It 'o mesmo PackageFullName repetido (-AllUsers) vira um registro e uma remocao' {
        Mock Get-TmxAppx -ModuleName TweakMaxing {
            [pscustomobject]@{ Name = 'Contoso.Bloat'; PackageFullName = 'Contoso.Bloat_1.2.3.0_x64__8wekyb3d8bbwe' }
            [pscustomobject]@{ Name = 'Contoso.Bloat'; PackageFullName = 'Contoso.Bloat_1.2.3.0_x64__8wekyb3d8bbwe' }
        }
        $a = [pscustomobject]@{ tipo = 'appx'; pacote = 'Contoso.Bloat'; storeId = '9NBLGGH4XYZ'; todosUsuarios = $true }
        $t = New-TmxTweakTeste -Id 'APX-004' -Acoes @($a) -Reversivel 'parcial'

        $r = Invoke-TmxAction -Action $a -Tweak $t -Profile $script:Perfil
        $r.ok | Should -BeTrue
        @($r.registros).Count | Should -Be 1
        @(Get-TmxRegistrosDoDisco $script:run.StatePath).Count | Should -Be 1
        $global:TmxT_Removidos.Count | Should -Be 1
    }

    It 'pacote que ja sumiu durante a remocao nao vira falha' {
        Mock Remove-TmxAppx -ModuleName TweakMaxing { throw 'Remove-AppxPackage: o pacote nao foi possivel localizar (0x80073CF1)' }
        $a = [pscustomobject]@{ tipo = 'appx'; pacote = 'Contoso.Bloat'; storeId = '9NBLGGH4XYZ'; todosUsuarios = $false }
        $t = New-TmxTweakTeste -Id 'APX-005' -Acoes @($a) -Reversivel 'parcial'

        $r = Invoke-TmxAction -Action $a -Tweak $t -Profile $script:Perfil
        $r.ok | Should -BeTrue
        @(Get-TmxRegistrosDoDisco $script:run.StatePath)[0].status | Should -Be 'aplicado'
    }

    It 'erro real na remocao continua sendo falha' {
        Mock Remove-TmxAppx -ModuleName TweakMaxing { throw 'Acesso negado' }
        $a = [pscustomobject]@{ tipo = 'appx'; pacote = 'Contoso.Bloat'; storeId = '9NBLGGH4XYZ'; todosUsuarios = $false }
        $t = New-TmxTweakTeste -Id 'APX-006' -Acoes @($a) -Reversivel 'parcial'

        $r = Invoke-TmxAction -Action $a -Tweak $t -Profile $script:Perfil
        $r.ok      | Should -BeFalse
        $r.detalhe | Should -Match 'Acesso negado'
        @(Get-TmxRegistrosDoDisco $script:run.StatePath)[0].status | Should -Be 'falha'
    }
}

Describe 'Invoke-TmxAction feature' -Tag 'Engine' {

    BeforeEach {
        $script:run = New-TmxRun
        $global:TmxT_StatePath  = $script:run.StatePath
        $global:TmxT_StateNoSet = $null
        $global:TmxT_Feat       = 'Enabled'
        $global:TmxT_FeatCalls  = New-Object System.Collections.ArrayList

        Mock Get-TmxWindowsFeature -ModuleName TweakMaxing { $global:TmxT_Feat }
        Mock Enable-TmxWindowsFeature -ModuleName TweakMaxing {
            if (-not $global:TmxT_StateNoSet) { $global:TmxT_StateNoSet = Get-Content -LiteralPath $global:TmxT_StatePath -Raw -Encoding UTF8 }
            $null = $global:TmxT_FeatCalls.Add("Enable:$Nome"); $global:TmxT_Feat = 'Enabled'
        }
        Mock Disable-TmxWindowsFeature -ModuleName TweakMaxing {
            if (-not $global:TmxT_StateNoSet) { $global:TmxT_StateNoSet = Get-Content -LiteralPath $global:TmxT_StatePath -Raw -Encoding UTF8 }
            $null = $global:TmxT_FeatCalls.Add("Disable:$Nome"); $global:TmxT_Feat = 'Disabled'
        }
    }

    It 'captura o estado anterior, desativa e a reversao reativa' {
        $a = [pscustomobject]@{ tipo = 'feature'; nome = 'Printing-XPSServices-Features'; estado = 'Disabled' }
        $t = New-TmxTweakTeste -Id 'FEA-001' -Acoes @($a)

        (Test-TmxAction -Action $a -Tweak $t -Profile $script:Perfil).aplicado | Should -BeFalse

        $r = Invoke-TmxAction -Action $a -Tweak $t -Profile $script:Perfil
        $r.ok | Should -BeTrue
        $global:TmxT_FeatCalls[0] | Should -Be 'Disable:Printing-XPSServices-Features'
        $global:TmxT_StateNoSet   | Should -Match '"tipo":\s*"feature"'
        $global:TmxT_StateNoSet   | Should -Match '"valorAnterior":\s*"Enabled"'

        (Test-TmxAction -Action $a -Tweak $t -Profile $script:Perfil).aplicado | Should -BeTrue

        Undo-TweakMaxing -Latest 6> $null | Out-Null
        $global:TmxT_FeatCalls[1] | Should -Be 'Enable:Printing-XPSServices-Features'
    }

    It 'recurso ja no estado alvo -> naoAplicavel e nada roda' {
        $global:TmxT_Feat = 'Disabled'
        $a = [pscustomobject]@{ tipo = 'feature'; nome = 'Printing-XPSServices-Features'; estado = 'Disabled' }
        $t = New-TmxTweakTeste -Id 'FEA-002' -Acoes @($a)

        $r = Invoke-TmxAction -Action $a -Tweak $t -Profile $script:Perfil
        $r.naoAplicavel | Should -BeTrue
        $global:TmxT_FeatCalls.Count | Should -Be 0
        @(Get-TmxRegistrosDoDisco $script:run.StatePath).Count | Should -Be 0
    }
}

Describe 'Invoke-TmxAction powercfg' -Tag 'Engine' {

    BeforeEach {
        $script:run = New-TmxRun
        $global:TmxT_StatePath  = $script:run.StatePath
        $global:TmxT_StateNoSet = $null
        $global:TmxT_Idx        = 1
        $global:TmxT_Pcfg       = New-Object System.Collections.ArrayList

        Mock Get-TmxActivePowerScheme -ModuleName TweakMaxing { [pscustomobject]@{ guid = '381b4222-f694-41f0-9685-ff5bb260df2e'; nome = 'Balanceado' } }
        Mock Get-TmxPowerSettingIndex -ModuleName TweakMaxing { $global:TmxT_Idx }
        Mock Invoke-TmxPowercfg -ModuleName TweakMaxing {
            if (-not $global:TmxT_StateNoSet) { $global:TmxT_StateNoSet = Get-Content -LiteralPath $global:TmxT_StatePath -Raw -Encoding UTF8 }
            $null = $global:TmxT_Pcfg.Add((@($Arguments) -join ' '))
            [pscustomobject]@{ saida = ''; codigo = 0 }
        }
    }

    It 'A1: indice anterior ilegivel -> ok=false, zero registros e powercfg nao e chamado' {
        Mock Get-TmxPowerSettingIndex -ModuleName TweakMaxing { $null }
        $a = [pscustomobject]@{ tipo = 'powercfg'; subgrupo = 'SUB_PROCESSOR'; configuracao = 'PERFBOOSTMODE'; valor = 0; descricao = 'Boost de desempenho' }
        $t = New-TmxTweakTeste -Id 'PWR-001' -Acoes @($a)

        $r = Invoke-TmxAction -Action $a -Tweak $t -Profile $script:Perfil
        $r.ok      | Should -BeFalse
        $r.detalhe | Should -Match 'ilegivel'
        @($r.registros).Count | Should -Be 0
        @(Get-TmxRegistrosDoDisco $script:run.StatePath).Count | Should -Be 0
        $global:TmxT_Pcfg.Count | Should -Be 0
    }

    It 'le o indice, grava e a reversao restaura o valor anterior' {
        $a = [pscustomobject]@{ tipo = 'powercfg'; subgrupo = 'SUB_PROCESSOR'; configuracao = 'PERFBOOSTMODE'; valor = 0; descricao = 'Boost de desempenho' }
        $t = New-TmxTweakTeste -Id 'PWR-002' -Acoes @($a)

        (Test-TmxAction -Action $a -Tweak $t -Profile $script:Perfil).aplicado | Should -BeFalse

        $r = Invoke-TmxAction -Action $a -Tweak $t -Profile $script:Perfil
        $r.ok | Should -BeTrue
        $global:TmxT_Pcfg[0] | Should -Match '^/setacvalueindex'
        $global:TmxT_Pcfg[1] | Should -Match '^/setactive'
        $global:TmxT_StateNoSet | Should -Match '"tipo":\s*"powercfg"'
        $global:TmxT_StateNoSet | Should -Match '"valorAnterior":\s*1'

        $global:TmxT_Idx = 0
        (Test-TmxAction -Action $a -Tweak $t -Profile $script:Perfil).aplicado | Should -BeTrue

        Undo-TweakMaxing -Latest 6> $null | Out-Null
        $global:TmxT_Pcfg[2] | Should -Match '^/setacvalueindex'
        $global:TmxT_Pcfg[2] | Should -Match ' 1$'
    }
}

Describe 'Invoke-TmxAction netadapter' -Tag 'Engine' {

    BeforeEach {
        $script:run = New-TmxRun
        $global:TmxT_StatePath  = $script:run.StatePath
        $global:TmxT_StateNoSet = $null
        $global:TmxT_NicValor   = '1'
        $global:TmxT_Nic        = New-Object System.Collections.ArrayList

        Mock Get-TmxAdapterAdvanced -ModuleName TweakMaxing {
            [pscustomobject]@{ RegistryKeyword = '*InterruptModeration'; DisplayName = 'Interrupt Moderation'; RegistryValue = @($global:TmxT_NicValor) }
        }
        Mock Set-TmxAdapterAdvanced -ModuleName TweakMaxing {
            if (-not $global:TmxT_StateNoSet) { $global:TmxT_StateNoSet = Get-Content -LiteralPath $global:TmxT_StatePath -Raw -Encoding UTF8 }
            $null = $global:TmxT_Nic.Add([pscustomobject]@{ Name = $Name; Keyword = $Keyword; Value = $Value })
            $global:TmxT_NicValor = "$Value"
        }
    }

    It 'grava o valor anterior da chave e a reversao devolve' {
        $a = [pscustomobject]@{ tipo = 'netadapter'; chaves = @('*InterruptModeration'); valorRegistro = '0'; valorExibicao = 'Desabilitado'; aplicarTodas = $false }
        $t = New-TmxTweakTeste -Id 'NET-001' -Acoes @($a)

        (Test-TmxAction -Action $a -Tweak $t -Profile $script:Perfil).aplicado | Should -BeFalse

        $r = Invoke-TmxAction -Action $a -Tweak $t -Profile $script:Perfil
        $r.ok | Should -BeTrue
        $global:TmxT_Nic[0].Name    | Should -Be 'Ethernet'
        $global:TmxT_Nic[0].Keyword | Should -Be '*InterruptModeration'
        $global:TmxT_Nic[0].Value   | Should -Be '0'
        $global:TmxT_StateNoSet     | Should -Match '"tipo":\s*"netadapter"'
        $global:TmxT_StateNoSet     | Should -Match '"valorAnterior":\s*"1"'

        (Test-TmxAction -Action $a -Tweak $t -Profile $script:Perfil).aplicado | Should -BeTrue

        Undo-TweakMaxing -Latest 6> $null | Out-Null
        $global:TmxT_Nic[1].Value | Should -Be '1'
    }

    It 'driver que nao expoe a chave -> naoAplicavel' {
        $a = [pscustomobject]@{ tipo = 'netadapter'; chaves = @('*NaoExiste'); valorRegistro = '0'; valorExibicao = 'x'; aplicarTodas = $false }
        $t = New-TmxTweakTeste -Id 'NET-002' -Acoes @($a)
        $r = Invoke-TmxAction -Action $a -Tweak $t -Profile $script:Perfil
        $r.naoAplicavel | Should -BeTrue
        $global:TmxT_Nic.Count | Should -Be 0
    }
}

Describe 'Invoke-TmxAction bcdedit' -Tag 'Engine' {

    BeforeEach {
        $script:run = New-TmxRun
        $global:TmxT_StatePath  = $script:run.StatePath
        $global:TmxT_StateNoSet = $null
        $global:TmxT_BcdEnum    = "identifier              {current}`r`ndescription             Windows 11`r`n"
        $global:TmxT_Bcd        = New-Object System.Collections.ArrayList

        Mock Invoke-TmxBcdedit -ModuleName TweakMaxing {
            $args0 = @($Arguments)
            $null = $global:TmxT_Bcd.Add(($args0 -join ' '))
            if ($args0[0] -eq '/set' -or $args0[0] -eq '/deletevalue') {
                if (-not $global:TmxT_StateNoSet) { $global:TmxT_StateNoSet = Get-Content -LiteralPath $global:TmxT_StatePath -Raw -Encoding UTF8 }
            }
            if ($args0[0] -eq '/set') {
                $global:TmxT_BcdEnum = $global:TmxT_BcdEnum + ("{0}              {1}`r`n" -f $args0[2], $args0[3])
            }
            if ($args0[0] -eq '/deletevalue') {
                $global:TmxT_BcdEnum = [regex]::Replace($global:TmxT_BcdEnum, "(?im)^\s*$([regex]::Escape($args0[2]))\s+\S+\s*\r?\n", '')
            }
            if ($args0[0] -eq '/enum') { return [pscustomobject]@{ saida = $global:TmxT_BcdEnum; codigo = 0 } }
            [pscustomobject]@{ saida = ''; codigo = 0 }
        }
    }

    It 'set em opcao ausente: registra existiaAntes=false e a reversao remove' {
        $a = [pscustomobject]@{ tipo = 'bcdedit'; acao = 'set'; opcao = 'useplatformclock'; valor = 'false' }
        $t = New-TmxTweakTeste -Id 'BCD-001' -Acoes @($a)

        (Test-TmxAction -Action $a -Tweak $t -Profile $script:Perfil).aplicado | Should -BeFalse

        $r = Invoke-TmxAction -Action $a -Tweak $t -Profile $script:Perfil
        $r.ok | Should -BeTrue
        ($global:TmxT_Bcd -join '|') | Should -Match '/export'
        ($global:TmxT_Bcd -join '|') | Should -Match '/set \{current\} useplatformclock false'
        $global:TmxT_StateNoSet | Should -Match '"tipo":\s*"bcdedit"'
        $global:TmxT_StateNoSet | Should -Match '"existiaAntes":\s*false'

        (Test-TmxAction -Action $a -Tweak $t -Profile $script:Perfil).aplicado | Should -BeTrue

        Undo-TweakMaxing -Latest 6> $null | Out-Null
        ($global:TmxT_Bcd -join '|') | Should -Match '/deletevalue \{current\} useplatformclock'
        (Test-TmxAction -Action $a -Tweak $t -Profile $script:Perfil).aplicado | Should -BeFalse
    }

    It 'deletevalue de opcao ausente -> naoAplicavel, sem registro' {
        $a = [pscustomobject]@{ tipo = 'bcdedit'; acao = 'deletevalue'; opcao = 'useplatformclock'; valor = $null }
        $t = New-TmxTweakTeste -Id 'BCD-002' -Acoes @($a)
        $r = Invoke-TmxAction -Action $a -Tweak $t -Profile $script:Perfil
        $r.naoAplicavel | Should -BeTrue
        @(Get-TmxRegistrosDoDisco $script:run.StatePath).Count | Should -Be 0
    }
}

Describe 'Invoke-TmxAction funcao' -Tag 'Engine' {

    BeforeEach {
        Remove-Item -LiteralPath $script:Raiz -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -Path "$script:Raiz\Fn" -Force | Out-Null
        $script:run = New-TmxRun
        $global:TmxT_StatePath    = $script:run.StatePath
        $global:TmxT_StateNoSet   = $null
        $global:TmxT_FakeValor    = 'antigo'
        $global:TmxT_FakeChamadas = New-Object System.Collections.ArrayList
    }

    It 'chama Set-TmxFake com -Tweak/-Profile/-Parametros, registra cmdlet e a reversao restaura' {
        $a = [pscustomobject]@{ tipo = 'funcao'; nome = 'Set-TmxFake'; parametros = [pscustomobject]@{ valor = 'novo' } }
        $t = New-TmxTweakTeste -Id 'FUN-001' -Acoes @($a)

        (Test-TmxAction -Action $a -Tweak $t -Profile $script:Perfil).aplicado | Should -BeFalse

        $r = Invoke-TmxAction -Action $a -Tweak $t -Profile $script:Perfil
        $r.ok | Should -BeTrue
        @($r.registros).Count | Should -Be 1

        $global:TmxT_FakeChamadas[0].TweakId | Should -Be 'FUN-001'
        $global:TmxT_FakeChamadas[0].Valor   | Should -Be 'novo'
        $global:TmxT_FakeChamadas[0].Perfil  | Should -Be 'Windows 11 Pro'

        $global:TmxT_StateNoSet | Should -Match '"tipo":\s*"cmdlet"'
        $global:TmxT_StateNoSet | Should -Match 'Set-TmxFake'

        (Test-TmxAction -Action $a -Tweak $t -Profile $script:Perfil).aplicado | Should -BeTrue

        Undo-TweakMaxing -Latest 6> $null | Out-Null
        $global:TmxT_FakeValor | Should -Be 'antigo'
    }

    It 'Test-Tmx* que declara -Parametros recebe os parametros da acao' {
        # Simetria com Invoke-TmxAction: sem isso a funcao Test- olhava para o
        # alvo PADRAO enquanto a Set- escrevia no alvo dos parametros, e a
        # pos-verificacao de Invoke-TmxPlan reportava 'falha' para uma escrita
        # que tinha dado certo.
        $global:TmxT_FakePParametros = $null
        $a = [pscustomobject]@{ tipo = 'funcao'; nome = 'Set-TmxFakeP'; parametros = [pscustomobject]@{ raiz = 'raiz-de-teste' } }
        $t = New-TmxTweakTeste -Id 'FUN-003' -Acoes @($a)

        $r = Test-TmxAction -Action $a -Tweak $t -Profile $script:Perfil

        "$($global:TmxT_FakePParametros.raiz)" | Should -Be 'raiz-de-teste'
        $r.aplicado | Should -BeTrue
        $r.atual    | Should -Be 'raiz-de-teste'
    }

    It 'Test-Tmx* sem -Parametros continua sendo chamada com -Tweak/-Profile' {
        # Test-TmxFake declara so -Tweak/-Profile: passar -Parametros para ela
        # seria um erro de binding, nao um recurso.
        $global:TmxT_FakeValor = 'novo'
        $a = [pscustomobject]@{ tipo = 'funcao'; nome = 'Set-TmxFake'; parametros = [pscustomobject]@{ valor = 'novo' } }
        $t = New-TmxTweakTeste -Id 'FUN-004' -Acoes @($a)

        $r = Test-TmxAction -Action $a -Tweak $t -Profile $script:Perfil

        $r.aplicado | Should -BeTrue
        $r.detalhe  | Should -Be 'fake = novo'
    }

    It 'funcao Set-Tmx* inexistente -> naoSuportado' {
        $a = [pscustomobject]@{ tipo = 'funcao'; nome = 'Set-TmxNaoExiste'; parametros = $null }
        $t = New-TmxTweakTeste -Id 'FUN-002' -Acoes @($a)
        $r = Invoke-TmxAction -Action $a -Tweak $t -Profile $script:Perfil
        $r.naoSuportado | Should -BeTrue
        $r.ok           | Should -BeFalse
        @(Get-TmxRegistrosDoDisco $script:run.StatePath).Count | Should -Be 0
    }

    It 'nome fora do padrao Set-Tmx* -> naoSuportado e nada e executado' {
        New-Item -Path "$script:Raiz\Fn\Sentinela" -Force | Out-Null
        $a = [pscustomobject]@{ tipo = 'funcao'; nome = 'Remove-Item'; parametros = [pscustomobject]@{ LiteralPath = "$script:Raiz\Fn\Sentinela"; Recurse = $true } }
        $t = New-TmxTweakTeste -Id 'FUN-003' -Acoes @($a)

        $r = Invoke-TmxAction -Action $a -Tweak $t -Profile $script:Perfil
        $r.naoSuportado | Should -BeTrue
        $r.ok           | Should -BeFalse
        $r.detalhe      | Should -Match 'nao permitido'
        Test-Path -LiteralPath "$script:Raiz\Fn\Sentinela" | Should -BeTrue
        @(Get-TmxRegistrosDoDisco $script:run.StatePath).Count | Should -Be 0

        (Test-TmxAction -Action $a -Tweak $t -Profile $script:Perfil).aplicado | Should -BeNullOrEmpty
    }
}

Describe 'Invoke-TmxPlan' -Tag 'Engine' {

    BeforeEach {
        Remove-Item -LiteralPath $script:Raiz -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -Path "$script:Raiz\P" -Force | Out-Null
        New-ItemProperty -LiteralPath "$script:Raiz\P" -Name 'Existente' -Value 1 -PropertyType DWord -Force | Out-Null
        New-ItemProperty -LiteralPath "$script:Raiz\P" -Name 'JaOk'      -Value 7 -PropertyType DWord -Force | Out-Null
        $script:run = New-TmxRun

        $script:tweaks = @(
            (New-TmxTweakTeste -Id 'TST-001' -Acoes @(
                (New-TmxAcaoRegistro -Sub 'P' -Nome 'Existente' -Valor 2),
                (New-TmxAcaoRegistro -Sub 'P' -Nome 'Novo' -Valor 'abc' -Tipo 'String'))),
            (New-TmxTweakTeste -Id 'TST-002' -Acoes @((New-TmxAcaoRegistro -Sub 'P' -Nome 'JaOk' -Valor 7))),
            (New-TmxTweakTeste -Id 'TST-003' -Acoes @((New-TmxAcaoRegistro -Sub 'Q\Nova' -Nome 'Big' -Valor 4294967295))),
            (New-TmxTweakTeste -Id 'TST-004' -Acoes @((New-TmxAcaoRegistro -Sub 'P' -Nome 'Consent' -Valor 1)) -Consentimento)
        )
        $script:plano = New-TmxPlanoTeste -Tweaks $script:tweaks
    }

    It 'aplica os selecionados, pula os ja aplicados e barra os sem consentimento' {
        $r = Invoke-TmxPlan -Plan $script:plano -Profile $script:Perfil

        (@($r.itens | Where-Object { $_.id -eq 'TST-001' })[0]).status | Should -Be 'aplicado'
        (@($r.itens | Where-Object { $_.id -eq 'TST-002' })[0]).status | Should -Be 'jaAplicado'
        (@($r.itens | Where-Object { $_.id -eq 'TST-003' })[0]).status | Should -Be 'aplicado'
        (@($r.itens | Where-Object { $_.id -eq 'TST-004' })[0]).status | Should -Be 'semConsentimento'

        $r.aplicados   | Should -Be 2
        $r.jaAplicados | Should -Be 1
        $r.pulados     | Should -Be 1
        $r.falhas      | Should -Be 0

        (Get-TmxValorTeste 'P' 'Existente') | Should -Be 2
        (Get-TmxValorTeste 'P' 'Novo')      | Should -Be 'abc'
        ([int64](Get-TmxValorTeste 'Q\Nova' 'Big') -band 0xFFFFFFFF) | Should -Be 4294967295
        (Get-TmxValorTeste 'P' 'Consent')   | Should -BeNullOrEmpty
    }

    It 'com consentimento dado o item e aplicado' {
        $plano = New-TmxPlanoTeste -Tweaks $script:tweaks -Consentidos @('TST-004')
        $r = Invoke-TmxPlan -Plan $plano -Profile $script:Perfil
        (@($r.itens | Where-Object { $_.id -eq 'TST-004' })[0]).status | Should -Be 'aplicado'
        (Get-TmxValorTeste 'P' 'Consent') | Should -Be 1
    }

    It '-WhatIf nao escreve nada: state.json sem registros e valores intactos' {
        $r = Invoke-TmxPlan -Plan $script:plano -Profile $script:Perfil -WhatIf

        (@($r.itens | Where-Object { $_.id -eq 'TST-001' })[0]).status | Should -Be 'simulado'
        (@($r.itens | Where-Object { $_.id -eq 'TST-003' })[0]).status | Should -Be 'simulado'
        @(Get-TmxRegistrosDoDisco $script:run.StatePath).Count | Should -Be 0
        (Get-TmxValorTeste 'P' 'Existente') | Should -Be 1
        (Get-TmxValorTeste 'P' 'Novo')      | Should -BeNullOrEmpty
        Test-Path -LiteralPath "$script:Raiz\Q\Nova" | Should -BeFalse
    }

    It 'M1: export .reg falhando bloqueia o tweak sem escrever nada' {
        Mock Backup-TmxRegistryHive -ModuleName TweakMaxing { $null }

        $r = Invoke-TmxPlan -Plan $script:plano -Profile $script:Perfil
        $item = @($r.itens | Where-Object { $_.id -eq 'TST-001' })[0]
        $item.status  | Should -Be 'falha'
        $item.detalhe | Should -Match 'backup \.reg falhou'
        (Get-TmxValorTeste 'P' 'Existente') | Should -Be 1
        (Get-TmxValorTeste 'P' 'Novo')      | Should -BeNullOrEmpty

        # TST-003 escreve numa chave que ainda nao existe: nao ha ramo a exportar
        (@($r.itens | Where-Object { $_.id -eq 'TST-003' })[0]).status | Should -Be 'aplicado'
    }

    It 'falha em um item nao impede o proximo' {
        $ruim = New-TmxTweakTeste -Id 'AAA-001' -Acoes @([pscustomobject]@{ tipo = 'funcao'; nome = 'Set-TmxFalha'; parametros = $null })
        $bom  = New-TmxTweakTeste -Id 'ZZZ-001' -Acoes @((New-TmxAcaoRegistro -Sub 'P' -Nome 'Depois' -Valor 5))
        $plano = New-TmxPlanoTeste -Tweaks @($ruim, $bom)

        $r = Invoke-TmxPlan -Plan $plano -Profile $script:Perfil
        (@($r.itens | Where-Object { $_.id -eq 'AAA-001' })[0]).status | Should -Be 'falha'
        (@($r.itens | Where-Object { $_.id -eq 'ZZZ-001' })[0]).status | Should -Be 'aplicado'
        $r.falhas    | Should -Be 1
        $r.aplicados | Should -Be 1
        (Get-TmxValorTeste 'P' 'Depois') | Should -Be 5
    }

    It '-Ids restringe a execucao aos ids informados' {
        $r = Invoke-TmxPlan -Plan $script:plano -Profile $script:Perfil -Ids 'TST-003'
        @($r.itens).Count | Should -Be 1
        @($r.itens)[0].id | Should -Be 'TST-003'
        (Get-TmxValorTeste 'P' 'Existente') | Should -Be 1
        ([int64](Get-TmxValorTeste 'Q\Nova' 'Big') -band 0xFFFFFFFF) | Should -Be 4294967295
    }

    It 'posAplicar chama Send-TmxSettingChange quando o comando existe' {
        # Send-TmxSettingChange agora e uma funcao real do modulo (src/functions/tweaks/Native.ps1,
        # Task 7): um stub global nao a sombreia dentro do modulo, entao o comando precisa
        # ser mockado no ModuleName, nao redefinido como funcao global.
        Mock Send-TmxSettingChange -ModuleName TweakMaxing { $true }

        $t = New-TmxTweakTeste -Id 'POS-001' -Acoes @((New-TmxAcaoRegistro -Sub 'P' -Nome 'Pos' -Valor 3)) -PosAplicar 'SettingChange'
        $plano = New-TmxPlanoTeste -Tweaks @($t)
        (Invoke-TmxPlan -Plan $plano -Profile $script:Perfil).aplicados | Should -Be 1

        Should -Invoke Send-TmxSettingChange -ModuleName TweakMaxing -Times 1 -Exactly
    }

    It 'falha parcial: registros das acoes que passaram e depois preenchido' {
        $t = New-TmxTweakTeste -Id 'PAR-001' -Acoes @(
            (New-TmxAcaoRegistro -Sub 'P' -Nome 'Parcial' -Valor 8),
            [pscustomobject]@{ tipo = 'funcao'; nome = 'Set-TmxFalha'; parametros = $null }
        )
        $r = Invoke-TmxPlan -Plan (New-TmxPlanoTeste -Tweaks @($t)) -Profile $script:Perfil
        $item = @($r.itens)[0]

        $item.status    | Should -Be 'falha'
        $item.registros | Should -Be 1
        $item.detalhe   | Should -Match 'falhou de proposito'
        # a 1a acao passou: o pos-check mostra o que sobrou no sistema
        $item.depois    | Should -Not -BeNullOrEmpty
        $item.depois    | Should -Match '8'
        $item.depois    | Should -Match 'ruim'
        (Get-TmxValorTeste 'P' 'Parcial') | Should -Be 8
    }
}

Describe 'Invoke-TmxBackupForTweak (exports nao bloqueantes)' -Tag 'Engine' {

    BeforeEach {
        $script:run = New-TmxRun
        $global:TmxT_PowBackups = 0
        $global:TmxT_NetBackups = 0
        $global:TmxT_Idx        = 1
        $global:TmxT_NicValor   = '1'

        # powercfg e netadapter "de verdade": o estado acompanha a escrita, senao
        # o pos-check de Invoke-TmxPlan reprovaria o tweak e mascararia o aviso.
        Mock Get-TmxActivePowerScheme -ModuleName TweakMaxing { [pscustomobject]@{ guid = '381b4222-f694-41f0-9685-ff5bb260df2e'; nome = 'Balanceado' } }
        Mock Get-TmxPowerSettingIndex -ModuleName TweakMaxing { $global:TmxT_Idx }
        Mock Invoke-TmxPowercfg -ModuleName TweakMaxing {
            if (@($Arguments)[0] -eq '/setacvalueindex') { $global:TmxT_Idx = [int64](@($Arguments)[4]) }
            [pscustomobject]@{ saida = ''; codigo = 0 }
        }
        Mock Get-TmxAdapterAdvanced -ModuleName TweakMaxing {
            [pscustomobject]@{ RegistryKeyword = '*InterruptModeration'; DisplayName = 'Interrupt Moderation'; RegistryValue = @($global:TmxT_NicValor) }
        }
        Mock Set-TmxAdapterAdvanced -ModuleName TweakMaxing { $global:TmxT_NicValor = "$Value" }

        # valores-alvo diferentes por tweak: se fossem iguais, o segundo cairia
        # em 'jaAplicado' e nem chegaria ao backup.
        function script:New-AcaoPwr { param($Valor) [pscustomobject]@{ tipo = 'powercfg'; subgrupo = 'SUB_PROCESSOR'; configuracao = 'PERFBOOSTMODE'; valor = $Valor; descricao = 'Boost' } }
        function script:New-AcaoNic { param($Valor) [pscustomobject]@{ tipo = 'netadapter'; chaves = @('*InterruptModeration'); valorRegistro = $Valor; valorExibicao = 'x'; aplicarTodas = $false } }
    }

    It 'export do .pow falhando vira aviso, nao bloqueia, e o proximo tweak tenta de novo' {
        Mock Backup-TmxPowerScheme -ModuleName TweakMaxing { $global:TmxT_PowBackups++; $null }

        $plano = New-TmxPlanoTeste -Tweaks @(
            (New-TmxTweakTeste -Id 'BKP-001' -Acoes @((New-AcaoPwr 0))),
            (New-TmxTweakTeste -Id 'BKP-002' -Acoes @((New-AcaoPwr 2)))
        )

        $r = Invoke-TmxPlan -Plan $plano -Profile $script:Perfil

        # tentou nos dois tweaks: a flag de "feito" so e marcada quando o arquivo sai
        $global:TmxT_PowBackups | Should -Be 2
        foreach ($item in @($r.itens)) {
            $item.status | Should -Be 'aplicado'
            @($item.avisos).Count | Should -Be 1
            @($item.avisos)[0] | Should -Match 'esquema de energia'
        }
        # e o valor anterior foi para o state.json mesmo sem o .pow
        @(Get-TmxRegistrosDoDisco $script:run.StatePath | Where-Object { $_.tipo -eq 'powercfg' }).Count | Should -Be 2
    }

    It 'export dos adaptadores falhando vira aviso e tambem e retentado' {
        Mock Backup-TmxNetworkAdapters -ModuleName TweakMaxing { $global:TmxT_NetBackups++; $null }

        $plano = New-TmxPlanoTeste -Tweaks @(
            (New-TmxTweakTeste -Id 'BKP-003' -Acoes @((New-AcaoNic '0'))),
            (New-TmxTweakTeste -Id 'BKP-004' -Acoes @((New-AcaoNic '2')))
        )

        $r = Invoke-TmxPlan -Plan $plano -Profile $script:Perfil
        $global:TmxT_NetBackups | Should -Be 2
        @(@($r.itens)[0].avisos)[0] | Should -Match 'adaptadores'
        @($r.itens | Where-Object { $_.status -eq 'falha' }).Count | Should -Be 0
    }

    It 'export bem-sucedido acontece uma vez so na execucao' {
        Mock Backup-TmxPowerScheme -ModuleName TweakMaxing { $global:TmxT_PowBackups++; [pscustomobject]@{ guid = 'g'; arquivo = 'x.pow' } }

        $plano = New-TmxPlanoTeste -Tweaks @(
            (New-TmxTweakTeste -Id 'BKP-005' -Acoes @((New-AcaoPwr 0))),
            (New-TmxTweakTeste -Id 'BKP-006' -Acoes @((New-AcaoPwr 2)))
        )

        $r = Invoke-TmxPlan -Plan $plano -Profile $script:Perfil
        $global:TmxT_PowBackups | Should -Be 1
        foreach ($item in @($r.itens)) {
            $item.status | Should -Be 'aplicado'
            @($item.avisos).Count | Should -Be 0
        }
    }
}
