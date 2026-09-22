# Testes do plano (Engine/Plan.ps1), presets (Engine/Plan.ps1: Get-TmxPresets)
# e perfil reduzido (Engine/Profile.ps1).

. "$PSScriptRoot\_Helpers.ps1"

BeforeAll {
    . "$PSScriptRoot\_Helpers.ps1"
    Import-TmxTestModule
    New-TmxTestHome | Out-Null

    function global:Set-TmxDummy  { param($Tweak, $Profile, $Parametros) [pscustomobject]@{ ok = $true } }
    function global:Undo-TmxDummy { param($Estado) [pscustomobject]@{ ok = $true } }
    function global:Test-TmxDummy { param($Tweak, $Profile) [pscustomobject]@{ aplicado = $false } }

    $script:Catalog = Get-TmxCatalog -Path (Join-Path $PSScriptRoot 'fixtures\catalog-min.json')
    $script:ProfileDesktop = Import-TmxProfile -Path (Join-Path $PSScriptRoot 'fixtures\profile-desktop.json')
    $script:ProfileLaptop  = Import-TmxProfile -Path (Join-Path $PSScriptRoot 'fixtures\profile-laptop.json')

    function script:Get-TmxPlanItem {
        param($Plan, [string] $Id)
        $Plan.itens | Where-Object { $_.id -eq $Id } | Select-Object -First 1
    }

    function script:Get-TmxTestCatalogClone {
        # Clone profundo: testes que mutam um tweak (ex.: trocar condicoes) precisam da
        # propria copia, sem afetar $script:Catalog usado pelos outros testes.
        @($script:Catalog | ConvertTo-Json -Depth 12 | ConvertFrom-Json)
    }
}

AfterAll {
    Remove-Item Function:\Set-TmxDummy, Function:\Undo-TmxDummy, Function:\Test-TmxDummy -ErrorAction SilentlyContinue
    Remove-Item Function:\Test-TmxTweakApplied -ErrorAction SilentlyContinue
    Remove-TmxTestHome
    Stop-TmxLogger
    Remove-Module TweakMaxing -Force -ErrorAction SilentlyContinue
}

Describe 'Get-TmxPresets' -Tag 'Plan' {
    It 'le src/config/preset.json com desktop, notebook e minimo' {
        $p = Get-TmxPresets
        $p.desktop.nome  | Should -Be 'Desktop'
        $p.notebook.nome | Should -Be 'Notebook'
        # Acento evitado como literal no .ps1: arquivos deste repo nao usam BOM e o parser
        # do PowerShell 5.1 sem BOM le UTF-8 como codepage ANSI, corrompendo acentos.
        # [char]0x00ED monta o "i com acento" sem depender da codificacao do arquivo fonte.
        $p.minimo.nome   | Should -Be ('M' + [char]0x00ED + 'nimo')
        $p.desktop.descricao  | Should -Not -BeNullOrEmpty
        $p.notebook.descricao | Should -Not -BeNullOrEmpty
        $p.minimo.descricao   | Should -Not -BeNullOrEmpty
    }
}

Describe 'Resolve-TmxPlan: selecao por preset' -Tag 'Plan' {

    It "preset 'desktop' com perfil desktop seleciona REG-001 e FUN-002" {
        $plan = Resolve-TmxPlan -Catalog $script:Catalog -Profile $script:ProfileDesktop -Preset 'desktop'
        $selecionados = @($plan.itens | Where-Object { $_.selecionado } | ForEach-Object { $_.id }) | Sort-Object
        $selecionados | Should -Be @('FUN-002', 'REG-001')
    }

    It "preset 'notebook' com perfil desktop seleciona so REG-001 (FUN-002 fica foraDoPreset)" {
        $plan = Resolve-TmxPlan -Catalog $script:Catalog -Profile $script:ProfileDesktop -Preset 'notebook'
        $selecionados = @($plan.itens | Where-Object { $_.selecionado } | ForEach-Object { $_.id })
        $selecionados | Should -Be @('REG-001')

        $fun = Get-TmxPlanItem -Plan $plan -Id 'FUN-002'
        $fun.status | Should -Be 'foraDoPreset'
        $fun.selecionado | Should -BeFalse
        $fun.alternavel | Should -BeTrue
    }

    It "preset 'minimo' com perfil desktop seleciona REG-001 e CMB-006" {
        $plan = Resolve-TmxPlan -Catalog $script:Catalog -Profile $script:ProfileDesktop -Preset 'minimo'
        $selecionados = @($plan.itens | Where-Object { $_.selecionado } | ForEach-Object { $_.id }) | Sort-Object
        $selecionados | Should -Be @('CMB-006', 'REG-001')
    }
}

Describe 'Resolve-TmxPlan: status especiais' -Tag 'Plan' {

    It 'FOLCLORE nao e selecionado mas e alternavel (usuario pode ligar a mao)' {
        $plan = Resolve-TmxPlan -Catalog $script:Catalog -Profile $script:ProfileDesktop -Preset 'desktop'
        $fol = Get-TmxPlanItem -Plan $plan -Id 'FOL-003'
        $fol.status | Should -Be 'folclore'
        $fol.selecionado | Should -BeFalse
        $fol.alternavel | Should -BeTrue
    }

    It "reversivel 'nenhuma' nao e selecionado e exige confirmacao" {
        $plan = Resolve-TmxPlan -Catalog $script:Catalog -Profile $script:ProfileDesktop -Preset 'desktop'
        $irr = Get-TmxPlanItem -Plan $plan -Id 'IRR-004'
        $irr.status | Should -Be 'irreversivel'
        $irr.selecionado | Should -BeFalse
        $irr.alternavel | Should -BeTrue
        $irr.exigeConfirmacao | Should -BeTrue
    }

    It 'controle info nao e selecionavel (vai para manual)' {
        $plan = Resolve-TmxPlan -Catalog $script:Catalog -Profile $script:ProfileDesktop -Preset 'desktop'
        $inf = Get-TmxPlanItem -Plan $plan -Id 'INF-007'
        $inf.status | Should -Be 'manual'
        $inf.selecionado | Should -BeFalse
        $inf.alternavel | Should -BeFalse
    }

    It 'preset vazio no tweak vira opcional e alternavel' {
        $plan = Resolve-TmxPlan -Catalog $script:Catalog -Profile $script:ProfileDesktop -Preset 'desktop'
        $tgl = Get-TmxPlanItem -Plan $plan -Id 'TGL-005'
        $tgl.status | Should -Be 'opcional'
        $tgl.selecionado | Should -BeFalse
        $tgl.alternavel | Should -BeTrue
    }

    It 'perfil de notebook bloqueia o dummy (FUN-002) no preset desktop' {
        $plan = Resolve-TmxPlan -Catalog $script:Catalog -Profile $script:ProfileLaptop -Preset 'desktop'
        $fun = Get-TmxPlanItem -Plan $plan -Id 'FUN-002'
        $fun.status | Should -Be 'bloqueado'
        $fun.selecionado | Should -BeFalse
        $fun.alternavel | Should -BeFalse
        ($fun.motivos -join '; ') | Should -Not -BeNullOrEmpty
        $fun.condicoes.Count | Should -BeGreaterThan 0
    }

    It "condicoes tem prioridade sobre FOLCLORE: 'requer' insatisfeito vira bloqueado, nao folclore" {
        $c = Get-TmxTestCatalogClone
        $fol = $c | Where-Object { $_.id -eq 'FOL-003' }
        # memory.capacidadeGB do perfil desktop e 32 - bem abaixo de 999999, entao o
        # requisito nunca e atendido, seja qual for o perfil de teste usado aqui.
        $fol.condicoes.requer = @('memory.capacidadeGB >= 999999 :: teste requer insatisfeito')

        $plan = Resolve-TmxPlan -Catalog $c -Profile $script:ProfileDesktop -Preset 'desktop'
        $item = Get-TmxPlanItem -Plan $plan -Id 'FOL-003'
        $item.status | Should -Be 'bloqueado'
        $item.selecionado | Should -BeFalse
        $item.alternavel | Should -BeFalse
        $item.condicoes.Count | Should -BeGreaterThan 0

        $res = Set-TmxPlanSelection -Plan $plan -Id 'FOL-003' -Selected $true
        $res.ok | Should -BeFalse
        $res.mensagem | Should -Match 'bloqueado'
    }

    It "preset notebook exclui semanticamente 'os.isLaptop != false', nao so '== true' literal" {
        $c = Get-TmxTestCatalogClone
        $fun = $c | Where-Object { $_.id -eq 'FUN-002' }
        # Se a regra do preset notebook fosse so um "grep" textual por '== true', esta
        # expressao (semanticamente equivalente) passaria batido e o item entraria
        # planejado no preset notebook - por isso presets tambem inclui 'notebook' aqui,
        # para isolar o efeito da regra de qualquer exclusao por presets[].
        $fun.presets = @('desktop', 'notebook')
        $fun.condicoes.bloqueiaSe = @('os.isLaptop != false :: teste semantico')

        $plan = Resolve-TmxPlan -Catalog $c -Profile $script:ProfileDesktop -Preset 'notebook'
        $item = Get-TmxPlanItem -Plan $plan -Id 'FUN-002'
        $item.status | Should -Be 'foraDoPreset'
        $item.selecionado | Should -BeFalse
    }
}

Describe 'Resolve-TmxPlan -IncludeState' -Tag 'Plan' {
    # Test-TmxTweakApplied ja existe de verdade em Engine/Actions.ps1 (dono: outro agente),
    # entao chamadas nao qualificadas feitas de DENTRO do modulo (Resolve-TmxPlan e uma
    # funcao do modulo) resolvem para a versao do modulo antes de olhar o escopo global -
    # uma "function global:Test-TmxTweakApplied" simples nao a sobrepoe. Mock -ModuleName
    # do Pester injeta o substituto no escopo correto do modulo.
    It 'preenche estadoAtual a partir de Test-TmxTweakApplied quando ele existe' {
        Mock -CommandName Test-TmxTweakApplied -ModuleName TweakMaxing -MockWith { @{ aplicado = $true } }
        $plan = Resolve-TmxPlan -Catalog $script:Catalog -Profile $script:ProfileDesktop -Preset 'desktop' -IncludeState
        $reg = Get-TmxPlanItem -Plan $plan -Id 'REG-001'
        $reg.estadoAtual | Should -BeTrue
    }

    It 'sem -IncludeState, estadoAtual fica nulo mesmo com Test-TmxTweakApplied existindo' {
        Mock -CommandName Test-TmxTweakApplied -ModuleName TweakMaxing -MockWith { @{ aplicado = $true } }
        $plan = Resolve-TmxPlan -Catalog $script:Catalog -Profile $script:ProfileDesktop -Preset 'desktop'
        $reg = Get-TmxPlanItem -Plan $plan -Id 'REG-001'
        $reg.estadoAtual | Should -BeNullOrEmpty
    }

    It 'so chama Test-TmxTweakApplied para planejado/opcional/folclore/irreversivel - nao para bloqueado/foraDoPreset/manual' {
        Mock -CommandName Test-TmxTweakApplied -ModuleName TweakMaxing -MockWith { @{ aplicado = $true } }
        # Preset desktop + perfil desktop (ver 'Get-TmxPlanSummary'): 2 planejados
        # (REG-001, FUN-002) + 1 opcional (TGL-005) + 1 folclore (FOL-003) + 1
        # irreversivel (IRR-004) = 5 chamadas esperadas; manual (INF-007) e
        # foraDoPreset (CMB-006) nao devem chamar a funcao.
        $plan = Resolve-TmxPlan -Catalog $script:Catalog -Profile $script:ProfileDesktop -Preset 'desktop' -IncludeState

        Should -Invoke -CommandName Test-TmxTweakApplied -ModuleName TweakMaxing -Times 5 -Exactly

        (Get-TmxPlanItem -Plan $plan -Id 'INF-007').estadoAtual | Should -BeNullOrEmpty
        (Get-TmxPlanItem -Plan $plan -Id 'CMB-006').estadoAtual | Should -BeNullOrEmpty
    }

    It 'nao chama Test-TmxTweakApplied para um item bloqueado, mesmo com -IncludeState' {
        Mock -CommandName Test-TmxTweakApplied -ModuleName TweakMaxing -MockWith { @{ aplicado = $true } }
        # Perfil laptop + preset desktop: FUN-002 fica bloqueado (ver describe acima).
        $plan = Resolve-TmxPlan -Catalog $script:Catalog -Profile $script:ProfileLaptop -Preset 'desktop' -IncludeState
        $fun = Get-TmxPlanItem -Plan $plan -Id 'FUN-002'
        $fun.status | Should -Be 'bloqueado'
        $fun.estadoAtual | Should -BeNullOrEmpty
    }
}

Describe 'Get-TmxPlanSummary' -Tag 'Plan' {
    It 'contagens do resumo batem com os status do preset desktop' {
        $plan = Resolve-TmxPlan -Catalog $script:Catalog -Profile $script:ProfileDesktop -Preset 'desktop'
        $r = $plan.resumo
        $r.total         | Should -Be 7
        $r.selecionados  | Should -Be 2
        $r.planejados    | Should -Be 2
        $r.opcionais     | Should -Be 1
        $r.manuais       | Should -Be 1
        $r.bloqueados    | Should -Be 0
        $r.foraDoPreset  | Should -Be 1
        $r.folclore      | Should -Be 1
        $r.irreversiveis | Should -Be 1
    }
}

Describe 'Set-TmxPlanSelection / Set-TmxPlanConsent' -Tag 'Plan' {

    It 'recusa alternar um id desconhecido' {
        $plan = Resolve-TmxPlan -Catalog $script:Catalog -Profile $script:ProfileDesktop -Preset 'desktop'
        $res = Set-TmxPlanSelection -Plan $plan -Id 'ZZZ-999' -Selected $true
        $res.ok | Should -BeFalse
    }

    It 'recusa alternar um item bloqueado' {
        $plan = Resolve-TmxPlan -Catalog $script:Catalog -Profile $script:ProfileLaptop -Preset 'desktop'
        $res = Set-TmxPlanSelection -Plan $plan -Id 'FUN-002' -Selected $true
        $res.ok | Should -BeFalse
        $res.mensagem | Should -Match 'bloqueado'
    }

    It 'liga um item opcional (alternavel) e atualiza o resumo' {
        $plan = Resolve-TmxPlan -Catalog $script:Catalog -Profile $script:ProfileDesktop -Preset 'desktop'
        $antes = $plan.resumo.selecionados
        $res = Set-TmxPlanSelection -Plan $plan -Id 'TGL-005' -Selected $true
        $res.ok | Should -BeTrue
        (Get-TmxPlanItem -Plan $plan -Id 'TGL-005').selecionado | Should -BeTrue
        $plan.resumo.selecionados | Should -Be ($antes + 1)
    }

    It 'Set-TmxPlanConsent marca e desmarca consentido' {
        $plan = Resolve-TmxPlan -Catalog $script:Catalog -Profile $script:ProfileDesktop -Preset 'desktop'
        $r1 = Set-TmxPlanConsent -Plan $plan -Id 'IRR-004' -Consented $true
        $r1.ok | Should -BeTrue
        (Get-TmxPlanItem -Plan $plan -Id 'IRR-004').consentido | Should -BeTrue

        $r2 = Set-TmxPlanConsent -Plan $plan -Id 'IRR-004' -Consented $false
        $r2.ok | Should -BeTrue
        (Get-TmxPlanItem -Plan $plan -Id 'IRR-004').consentido | Should -BeFalse
    }

    It 'Set-TmxPlanConsent recusa id desconhecido' {
        $plan = Resolve-TmxPlan -Catalog $script:Catalog -Profile $script:ProfileDesktop -Preset 'desktop'
        $res = Set-TmxPlanConsent -Plan $plan -Id 'ZZZ-999' -Consented $true
        $res.ok | Should -BeFalse
    }
}

Describe 'Get-TmxProfile' -Tag 'Plan' {
    It 'retorna todas as secoes ao vivo, sem lancar, mesmo sem elevacao' {
        # Chamada direta (nao dentro de { } | Should -Not -Throw): atribuicao dentro de um
        # scriptblock de Should nao escapa para o escopo do It no Pester 6. Se Get-TmxProfile
        # lancar, o teste falha sozinho com a excecao nao tratada.
        $p = Get-TmxProfile
        $p.PSObject.Properties.Name | Should -Contain 'os'
        $p.PSObject.Properties.Name | Should -Contain 'network'
        $p.PSObject.Properties.Name | Should -Contain 'storage'
        $p.PSObject.Properties.Name | Should -Contain 'memory'
        $p.PSObject.Properties.Name | Should -Contain 'gpu'
        $p.os.PSObject.Properties.Name | Should -Contain 'isLaptop'
        $p.os.PSObject.Properties.Name | Should -Contain 'bcd'
    }

    It 'Find-TmxCs2Path nunca lanca' {
        { Find-TmxCs2Path } | Should -Not -Throw
    }

    It 'Save-TmxProfile / Import-TmxProfile fazem roundtrip por JSON' {
        $tmxHome = $env:TWEAKMAXING_HOME
        $path = Join-Path $tmxHome 'perfil-roundtrip.json'
        $salvo = Save-TmxProfile -Profile $script:ProfileDesktop -Path $path
        Test-Path $salvo | Should -BeTrue

        $lido = Import-TmxProfile -Path $salvo
        $lido.os.build | Should -Be $script:ProfileDesktop.os.build
        $lido.gpu.vendor | Should -Be $script:ProfileDesktop.gpu.vendor
        $lido.storage.discoSistema.tipo | Should -Be $script:ProfileDesktop.storage.discoSistema.tipo
    }
}
