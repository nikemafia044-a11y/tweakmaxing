# Testes do preview "antes -> depois" (src/Engine/Preview.ps1).
# So leitura: nenhuma acao e aplicada e nenhum registro de estado e criado.

. "$PSScriptRoot\_Helpers.ps1"

BeforeAll {
    . "$PSScriptRoot\_Helpers.ps1"
    Import-TmxTestModule
    New-TmxTestHome | Out-Null

    $script:Raiz   = 'HKCU:\Software\TweakMaxing_Tests\Engine\Preview'
    $script:Perfil = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'fixtures\profile-engine.json') -Raw -Encoding UTF8 | ConvertFrom-Json

    function script:New-TmxAcaoRegistroPv {
        param(
            [Parameter(Mandatory)] [string] $Nome,
            $Valor,
            [string] $Tipo = 'DWord',
            [switch] $Remover
        )
        $o = [pscustomobject]@{
            tipo      = 'registry'
            path      = 'HKCU:\Software\TweakMaxing_Tests\Engine\Preview\Pv'
            name      = $Nome
            value     = $Valor
            valueType = $Tipo
        }
        if ($Remover) { $o | Add-Member -NotePropertyName 'remove' -NotePropertyValue $true }
        $o
    }

    function script:New-TmxTweakPv {
        param(
            [Parameter(Mandatory)] [string] $Id,
            [Parameter(Mandatory)] [object[]] $Acoes,
            [string] $Reversivel = 'total'
        )
        [pscustomobject]@{
            id                       = $Id
            nome                     = "Preview $Id"
            categoria                = 'Teste'
            tier                     = 'MEDIDO'
            risco                    = 'baixo'
            presets                  = @('desktop')
            controle                 = 'checkbox'
            reversivel               = $Reversivel
            requerReboot             = $false
            requerConsentimentoExtra = $false
            condicoes                = [pscustomobject]@{ requer = @(); bloqueiaSe = @() }
            porque                   = 'teste'
            evidencia                = 'teste'
            posAplicar               = $null
            acoes                    = @($Acoes)
        }
    }

    function script:New-TmxPlanoPv {
        param([Parameter(Mandatory)] [object[]] $Tweaks)
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
                consentido       = $false
                exigeConfirmacao = $false
                motivos          = @()
                condicoes        = @()
                estadoAtual      = $null
                tweak            = $t
            }
        }
        [pscustomobject]@{ preset = 'desktop'; geradoEm = (Get-Date).ToString('o'); itens = @($itens); resumo = @{} }
    }

    function global:Set-TmxFakePv {
        param($Tweak, $Profile, $Parametros)
        [pscustomobject]@{ ok = $true; detalhe = 'nunca chamado no preview'; registro = $null }
    }
    function global:Test-TmxFakePv {
        param($Tweak, $Profile)
        [pscustomobject]@{ aplicado = $false; atual = 'pagefile 800MB'; esperado = 'pagefile 4096MB'; detalhe = 'fake' }
    }
}

AfterAll {
    Remove-Item -LiteralPath 'HKCU:\Software\TweakMaxing_Tests\Engine\Preview' -Recurse -Force -ErrorAction SilentlyContinue
    foreach ($fn in 'Set-TmxFakePv', 'Test-TmxFakePv') {
        Remove-Item -LiteralPath "Function:\$fn" -Force -ErrorAction SilentlyContinue
    }
    Remove-TmxTestHome
    Stop-TmxLogger
    Remove-Module TweakMaxing -Force -ErrorAction SilentlyContinue
}

Describe 'Get-TmxPlanPreview' -Tag 'Engine' {

    BeforeEach {
        Remove-Item -LiteralPath $script:Raiz -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -Path "$script:Raiz\Pv" -Force | Out-Null
        $script:run = New-TmxRun
    }

    It 'registry: mostra o valor atual e o valor alvo, sem tocar no registro' {
        New-ItemProperty -LiteralPath "$script:Raiz\Pv" -Name 'V' -Value 10 -PropertyType DWord -Force | Out-Null
        $t = New-TmxTweakPv -Id 'PV-001' -Acoes @((New-TmxAcaoRegistroPv -Nome 'V' -Valor 99))

        $pv = @(Get-TmxPlanPreview -Plan (New-TmxPlanoPv -Tweaks @($t)) -Profile $script:Perfil)

        $pv.Count        | Should -Be 1
        $pv[0].tweakId   | Should -Be 'PV-001'
        $pv[0].tipo      | Should -Be 'registry'
        $pv[0].alvo      | Should -Match 'Pv::V$'
        $pv[0].antes     | Should -Be '10'
        $pv[0].depois    | Should -Be '99'
        $pv[0].reversao  | Should -Be 'total'

        # nada foi aplicado nem registrado
        (Get-ItemProperty -LiteralPath "$script:Raiz\Pv" -Name 'V').V | Should -Be 10
        @(Get-TmxState).Count | Should -Be 0
    }

    It 'valor ausente aparece como <ausente>' {
        $t = New-TmxTweakPv -Id 'PV-002' -Acoes @((New-TmxAcaoRegistroPv -Nome 'NaoExiste' -Valor 1))
        $pv = @(Get-TmxPlanPreview -Plan (New-TmxPlanoPv -Tweaks @($t)) -Profile $script:Perfil)
        $pv[0].antes  | Should -Be '<ausente>'
        $pv[0].depois | Should -Be '1'
    }

    It 'acao de remocao: depois = <removido>' {
        New-ItemProperty -LiteralPath "$script:Raiz\Pv" -Name 'Sumir' -Value 7 -PropertyType DWord -Force | Out-Null
        $t = New-TmxTweakPv -Id 'PV-003' -Acoes @((New-TmxAcaoRegistroPv -Nome 'Sumir' -Remover)) -Reversivel 'parcial'
        $pv = @(Get-TmxPlanPreview -Plan (New-TmxPlanoPv -Tweaks @($t)) -Profile $script:Perfil)
        $pv[0].antes    | Should -Be '7'
        $pv[0].depois   | Should -Be '<removido>'
        $pv[0].reversao | Should -Be 'parcial'
    }

    It 'uma linha por acao, na ordem do catalogo' {
        $t = New-TmxTweakPv -Id 'PV-004' -Acoes @(
            (New-TmxAcaoRegistroPv -Nome 'A' -Valor 1),
            (New-TmxAcaoRegistroPv -Nome 'B' -Valor 'txt' -Tipo 'String')
        )
        $pv = @(Get-TmxPlanPreview -Plan (New-TmxPlanoPv -Tweaks @($t)) -Profile $script:Perfil)
        $pv.Count     | Should -Be 2
        $pv[0].alvo   | Should -Match '::A$'
        $pv[1].alvo   | Should -Match '::B$'
        $pv[1].depois | Should -Be 'txt'
    }

    It 'funcao: antes/depois vem de Test-TmxFakePv' {
        $a = [pscustomobject]@{ tipo = 'funcao'; nome = 'Set-TmxFakePv'; parametros = [pscustomobject]@{ tamanhoMB = 4096 } }
        $t = New-TmxTweakPv -Id 'PV-005' -Acoes @($a)
        $pv = @(Get-TmxPlanPreview -Plan (New-TmxPlanoPv -Tweaks @($t)) -Profile $script:Perfil)

        $pv[0].tipo   | Should -Be 'funcao'
        $pv[0].alvo   | Should -Be 'Set-TmxFakePv'
        $pv[0].antes  | Should -Be 'pagefile 800MB'
        $pv[0].depois | Should -Be 'pagefile 4096MB'
    }

    It 'funcao sem Test-Tmx<X>: depois cai para o nome do tweak' {
        $a = [pscustomobject]@{ tipo = 'funcao'; nome = 'Set-TmxSemVerificacao'; parametros = $null }
        $t = New-TmxTweakPv -Id 'PV-006' -Acoes @($a)
        $pv = @(Get-TmxPlanPreview -Plan (New-TmxPlanoPv -Tweaks @($t)) -Profile $script:Perfil)
        $pv[0].antes  | Should -Be '<ausente>'
        $pv[0].depois | Should -Be 'Preview PV-006'
    }

    It '-Ids restringe o preview aos ids informados' {
        $t1 = New-TmxTweakPv -Id 'PV-007' -Acoes @((New-TmxAcaoRegistroPv -Nome 'X' -Valor 1))
        $t2 = New-TmxTweakPv -Id 'PV-008' -Acoes @((New-TmxAcaoRegistroPv -Nome 'Y' -Valor 2))
        $pv = @(Get-TmxPlanPreview -Plan (New-TmxPlanoPv -Tweaks @($t1, $t2)) -Profile $script:Perfil -Ids 'PV-008')
        $pv.Count      | Should -Be 1
        $pv[0].tweakId | Should -Be 'PV-008'
    }

    It 'itens nao selecionados ficam de fora' {
        $t = New-TmxTweakPv -Id 'PV-009' -Acoes @((New-TmxAcaoRegistroPv -Nome 'Z' -Valor 1))
        $plano = New-TmxPlanoPv -Tweaks @($t)
        $plano.itens[0].selecionado = $false
        @(Get-TmxPlanPreview -Plan $plano -Profile $script:Perfil).Count | Should -Be 0
    }
}
