# tests/Modes.Tests.ps1
# Testes da Task T2 (catalogo v2: modos, categoriasV2, textos didaticos e
# i18n.en) contra o catalogo REAL (src/config), nao um fixture minimo: o
# objetivo aqui e garantir que TODO tweak do catalogo (os 117 desta task mais
# os 9 novos da Task T3 em tweaks.v2.json, que tambem carregam 'modo') respeita
# as regras de modo/preset descritas em docs/specs/2026-09-24-v2-design.md #6.

. "$PSScriptRoot\_Helpers.ps1"

BeforeAll {
    . "$PSScriptRoot\_Helpers.ps1"
    Import-TmxTestModule

    $script:Catalog = Get-TmxCatalog
    $script:ModosValidos = @('leve', 'moderado', 'avancado', 'ultimate', 'extras')
    $script:CategoriasV2Validas = @('geral', 'aparencia', 'desempenho', 'privacidade', 'jogos', 'rede', 'gpu')
    $script:ModoOrdem = @('leve', 'moderado', 'avancado', 'ultimate')

    # Excecoes documentadas: risco alto que o pedido do usuario colocou
    # explicitamente em 'avancado' (nao 'ultimate'), contrariando a regra geral
    # "risco alto so em ultimate". Ver docs/v2/01-mapa-de-funcoes.md e o relato
    # da Task T2: OneDrive (APM-003) e Windows AI/Copilot (APM-004).
    $script:ExcecoesRiscoAltoForaDeUltimate = @('APM-003', 'APM-004')

    $script:ProfileDesktop = Import-TmxProfile -Path (Join-Path $PSScriptRoot 'fixtures\profile-desktop.json')
    $script:ProfileLaptop  = Import-TmxProfile -Path (Join-Path $PSScriptRoot 'fixtures\profile-laptop.json')
}

AfterAll {
    Remove-Module TweakMaxing -Force -ErrorAction SilentlyContinue
}

Describe 'Catalogo v2: todo tweak tem modo, categoriasV2, textos e i18n.en' -Tag 'Modes' {

    It 'carrega o catalogo real com pelo menos 117 tweaks (117 da Task T2 + os novos da T3)' {
        @($script:Catalog).Count | Should -BeGreaterOrEqual 117
    }

    It 'todo tweak tem "modo" preenchido e valido' {
        foreach ($t in $script:Catalog) {
            "$($t.modo)" | Should -Not -BeNullOrEmpty -Because "tweak $($t.id) sem modo"
            $t.modo | Should -BeIn $script:ModosValidos -Because "tweak $($t.id) com modo invalido '$($t.modo)'"
        }
    }

    It 'todo tweak tem "categoriasV2" como lista nao vazia, com valores validos' {
        foreach ($t in $script:Catalog) {
            $cats = @($t.categoriasV2)
            $cats.Count | Should -BeGreaterThan 0 -Because "tweak $($t.id) sem categoriasV2"
            foreach ($c in $cats) {
                $c | Should -BeIn $script:CategoriasV2Validas -Because "tweak $($t.id) com categoriaV2 invalida '$c'"
            }
        }
    }

    It 'todo tweak tem oQueFaz, beneficio e atencao preenchidos (pt-BR)' {
        foreach ($t in $script:Catalog) {
            "$($t.oQueFaz)"   | Should -Not -BeNullOrEmpty -Because "tweak $($t.id) sem oQueFaz"
            "$($t.beneficio)" | Should -Not -BeNullOrEmpty -Because "tweak $($t.id) sem beneficio"
            "$($t.atencao)"   | Should -Not -BeNullOrEmpty -Because "tweak $($t.id) sem atencao (pode ser 'Nenhuma.')"
        }
    }

    It 'todo tweak tem i18n.en.{nome,oQueFaz,beneficio,atencao} preenchidos' {
        foreach ($t in $script:Catalog) {
            $t.i18n | Should -Not -BeNullOrEmpty -Because "tweak $($t.id) sem bloco i18n"
            $t.i18n.en | Should -Not -BeNullOrEmpty -Because "tweak $($t.id) sem i18n.en"
            foreach ($campo in 'nome', 'oQueFaz', 'beneficio', 'atencao') {
                "$($t.i18n.en.$campo)" | Should -Not -BeNullOrEmpty -Because "tweak $($t.id) sem i18n.en.$campo"
            }
        }
    }
}

Describe 'Catalogo v2: FOLCLORE e irreversivel nunca entram num modo' -Tag 'Modes' {

    It "tier FOLCLORE sempre tem modo 'extras'" {
        $folclore = @($script:Catalog | Where-Object { $_.tier -eq 'FOLCLORE' })
        $folclore.Count | Should -BeGreaterThan 0
        foreach ($t in $folclore) {
            $t.modo | Should -Be 'extras' -Because "$($t.id) e FOLCLORE mas tem modo '$($t.modo)'"
        }
    }

    It "reversivel 'nenhuma' sempre tem modo 'extras'" {
        $irreversiveis = @($script:Catalog | Where-Object { "$($_.reversivel)" -eq 'nenhuma' })
        $irreversiveis.Count | Should -BeGreaterThan 0
        foreach ($t in $irreversiveis) {
            $t.modo | Should -Be 'extras' -Because "$($t.id) e irreversivel mas tem modo '$($t.modo)'"
        }
    }

    It "controle 'info' sempre tem modo 'extras' (excecao documentada: SEC-001, Task T3 - guia com alternativa segura em 'ultimate', ver spec #7)" {
        # SEC-001 (Protecao em Tempo Real do Defender) e um caso especial descrito na propria
        # spec (docs/specs/2026-09-24-v2-design.md #7): e controle 'info' porque o estado e so
        # lido (nunca alterado por script), mas fica classificado em 'ultimate' porque a
        # ALTERNATIVA que ele oferece (exclusao de pastas) e uma troca de seguranca real. E
        # dono da Task T3 (tweaks.v2.json), nao desta task.
        $excecoesControleInfo = @('SEC-001')
        $infos = @($script:Catalog | Where-Object { "$($_.controle)" -eq 'info' -and $_.id -notin $excecoesControleInfo })
        $infos.Count | Should -BeGreaterThan 0
        foreach ($t in $infos) {
            $t.modo | Should -Be 'extras' -Because "$($t.id) e controle info mas tem modo '$($t.modo)'"
        }
    }

    It "risco alto so aparece em 'ultimate' ou 'extras' (excecoes documentadas: OneDrive/Windows AI em avancado)" {
        $altos = @($script:Catalog | Where-Object { "$($_.risco)" -eq 'alto' })
        $altos.Count | Should -BeGreaterThan 0
        foreach ($t in $altos) {
            if ($t.id -in $script:ExcecoesRiscoAltoForaDeUltimate) {
                $t.modo | Should -Be 'avancado' -Because "$($t.id) e uma excecao documentada (ver relato da Task T2)"
                continue
            }
            $t.modo | Should -BeIn @('ultimate', 'extras') -Because "$($t.id) tem risco alto mas modo '$($t.modo)'"
        }
    }
}

Describe 'Catalogo v2: presets por modo sao cumulativos (leve C moderado C avancado C ultimate)' -Tag 'Modes' {

    It "aceita 'leve','moderado','avancado','ultimate' como -Preset (nunca 'extras')" {
        { Resolve-TmxPlan -Catalog $script:Catalog -Profile $script:ProfileDesktop -Preset 'extras' } | Should -Throw
    }

    It 'a selecao de cada modo e um subconjunto estrito do proximo modo' {
        $selecoes = @{}
        foreach ($modo in $script:ModoOrdem) {
            $plan = Resolve-TmxPlan -Catalog $script:Catalog -Profile $script:ProfileDesktop -Preset $modo
            $selecoes[$modo] = [System.Collections.Generic.HashSet[string]]::new(
                [string[]]@($plan.itens | Where-Object { $_.selecionado } | ForEach-Object { $_.id })
            )
        }

        # leve subconjunto de moderado subconjunto de avancado subconjunto de ultimate.
        for ($i = 0; $i -lt $script:ModoOrdem.Count - 1; $i++) {
            $atual   = $selecoes[$script:ModoOrdem[$i]]
            $proximo = $selecoes[$script:ModoOrdem[$i + 1]]
            foreach ($id in $atual) {
                $proximo.Contains($id) | Should -BeTrue -Because "'$id' esta em '$($script:ModoOrdem[$i])' mas nao em '$($script:ModoOrdem[$i + 1])'"
            }
            # cumulativo estrito: cada modo seguinte tem pelo menos os mesmos itens
            # (nao precisa ter MAIS, mas nunca pode ter menos).
            $proximo.Count | Should -BeGreaterOrEqual $atual.Count
        }
    }

    It "um tweak com modo 'extras' nunca e selecionado automaticamente em nenhum preset de modo" {
        $extras = @($script:Catalog | Where-Object { $_.modo -eq 'extras' -and $_.tier -ne 'FOLCLORE' -and "$($_.reversivel)" -ne 'nenhuma' -and "$($_.controle)" -ne 'info' })
        $extras.Count | Should -BeGreaterThan 0
        foreach ($modo in $script:ModoOrdem) {
            $plan = Resolve-TmxPlan -Catalog $script:Catalog -Profile $script:ProfileDesktop -Preset $modo
            foreach ($t in $extras) {
                $item = $plan.itens | Where-Object { $_.id -eq $t.id } | Select-Object -First 1
                $item.selecionado | Should -BeFalse -Because "$($t.id) (modo extras) foi selecionado em preset '$modo'"
                # status normalmente e 'opcional' (opt-in por ID); pode ser 'bloqueado' se o
                # tweak tiver seu proprio 'condicoes.requer' nao satisfeito pelo perfil de
                # teste (ex.: JOG-016/017 exigem driver/GPU especificos) - o que importa aqui
                # e nunca 'planejado'/selecionado, nao o status exato.
                $item.status | Should -Not -Be 'planejado'
            }
        }
    }
}

Describe 'Catalogo v2: plano de desempenho maximo nao entra em notebook' -Tag 'Modes' {

    It "ENE-004 fica bloqueado num perfil de notebook, em qualquer preset de modo" {
        foreach ($modo in $script:ModoOrdem) {
            $plan = Resolve-TmxPlan -Catalog $script:Catalog -Profile $script:ProfileLaptop -Preset $modo
            $item = $plan.itens | Where-Object { $_.id -eq 'ENE-004' } | Select-Object -First 1
            $item.status | Should -Be 'bloqueado' -Because "preset '$modo'"
            $item.selecionado | Should -BeFalse
        }
    }

    It 'ENE-004 e selecionavel (planejado) num perfil desktop no preset leve' {
        $plan = Resolve-TmxPlan -Catalog $script:Catalog -Profile $script:ProfileDesktop -Preset 'leve'
        $item = $plan.itens | Where-Object { $_.id -eq 'ENE-004' } | Select-Object -First 1
        $item.status | Should -Be 'planejado'
        $item.selecionado | Should -BeTrue
    }
}

Describe 'Catalogo v2: ultimate de risco alto exige consentimento separado' -Tag 'Modes' {

    It "todo tweak com modo 'ultimate' e risco 'alto' tem requerConsentimentoExtra=true e consentimento.frase preenchida" {
        $ultimateAltos = @($script:Catalog | Where-Object { $_.modo -eq 'ultimate' -and "$($_.risco)" -eq 'alto' })
        $ultimateAltos.Count | Should -BeGreaterThan 0
        foreach ($t in $ultimateAltos) {
            $t.requerConsentimentoExtra | Should -BeTrue -Because "$($t.id) e ultimate/risco alto"
            "$($t.consentimento.frase)" | Should -Not -BeNullOrEmpty -Because "$($t.id) e ultimate/risco alto"
        }
    }
}

Describe 'Get-TmxPresets: os 4 modos existem como presets, com i18n.en' -Tag 'Modes' {

    It "leve/moderado/avancado/ultimate existem com nome/descricao pt-BR e i18n.en" {
        $p = Get-TmxPresets
        foreach ($modo in $script:ModoOrdem) {
            $p.$modo.nome | Should -Not -BeNullOrEmpty -Because $modo
            $p.$modo.descricao | Should -Not -BeNullOrEmpty -Because $modo
            $p.$modo.i18n.en.nome | Should -Not -BeNullOrEmpty -Because $modo
            $p.$modo.i18n.en.descricao | Should -Not -BeNullOrEmpty -Because $modo
        }
        # presets antigos continuam intactos.
        $p.desktop.nome  | Should -Be 'Desktop'
        $p.notebook.nome | Should -Be 'Notebook'
    }

    It "'extras' NAO existe em preset.json (nunca e um preset selecionavel)" {
        $p = Get-TmxPresets
        $p.PSObject.Properties.Name | Should -Not -Contain 'extras'
    }
}

Describe 'Test-TmxCatalog: modo/categoriasV2/i18n invalidos sao rejeitados quando presentes' -Tag 'Modes' {

    It 'rejeita um modo fora do enum' {
        $c = @($script:Catalog | Select-Object -First 1 | ForEach-Object { $_ | ConvertTo-Json -Depth 12 | ConvertFrom-Json })
        $c[0].modo = 'inexistente'
        $r = Test-TmxCatalog -Catalog $c
        $r.ok | Should -BeFalse
        ($r.erros -join '; ') | Should -Match 'modo invalido'
    }

    It 'rejeita uma categoriaV2 fora do enum' {
        $c = @($script:Catalog | Select-Object -First 1 | ForEach-Object { $_ | ConvertTo-Json -Depth 12 | ConvertFrom-Json })
        $c[0].categoriasV2 = @('inexistente')
        $r = Test-TmxCatalog -Catalog $c
        $r.ok | Should -BeFalse
        ($r.erros -join '; ') | Should -Match 'categoriasV2 invalido'
    }

    It 'aceita um tweak sem modo/categoriasV2/i18n (campos continuam opcionais no schema)' {
        $c = @($script:Catalog | Select-Object -First 1 | ForEach-Object { $_ | ConvertTo-Json -Depth 12 | ConvertFrom-Json })
        $c[0].PSObject.Properties.Remove('modo')
        $c[0].PSObject.Properties.Remove('categoriasV2')
        $c[0].PSObject.Properties.Remove('i18n')
        $r = Test-TmxCatalog -Catalog $c
        $r.ok | Should -BeTrue
    }
}

Describe 'Catalogo v2: aplicativos (categoriaV2 e i18n.en.descricao)' -Tag 'Modes' {

    It 'todo aplicativo do catalogo real tem categoriaV2 valido e i18n.en.descricao preenchido' {
        $appsPath = Join-Path $PSScriptRoot '..\src\config\applications.json'
        Test-Path -LiteralPath $appsPath | Should -BeTrue
        $doc = Get-Content -LiteralPath $appsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $apps = @($doc.aplicativos)
        $apps.Count | Should -BeGreaterOrEqual 236

        $categoriasV2AppValidas = @('navegadores', 'comunicacao', 'jogos', 'desenvolvimento', 'multimidia', 'utilitarios')
        foreach ($a in $apps) {
            $a.categoriaV2 | Should -BeIn $categoriasV2AppValidas -Because "app '$($a.id)'"
            "$($a.i18n.en.descricao)" | Should -Not -BeNullOrEmpty -Because "app '$($a.id)'"
        }
    }
}
