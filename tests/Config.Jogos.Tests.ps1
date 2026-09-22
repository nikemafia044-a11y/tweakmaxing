# Testes da categoria "Jogos" (tools/Convert-CS2TunerCatalog.ps1 + src/config/tweaks.jogos.json).
#
# Espelha o padrao de Tools.Convert.Tests.ps1 (conversor) e Config.Tests.ps1
# (catalogo committado), mas focado no arquivo gerado a partir do CS2Tuner.

. "$PSScriptRoot\_Helpers.ps1"

BeforeAll {
    . "$PSScriptRoot\_Helpers.ps1"
    Import-TmxTestModule

    $script:RepoRaiz   = Split-Path $PSScriptRoot -Parent
    $script:Conversor  = Join-Path $script:RepoRaiz 'tools\Convert-CS2TunerCatalog.ps1'
    $script:FonteCs2   = 'C:\Users\fantasy\Desktop\tweak\data\tweaks.json'
    $script:ConfigDir  = Join-Path $script:RepoRaiz 'src\config'

    $script:Temp = Join-Path ([System.IO.Path]::GetTempPath()) ('TmxConvertJogos_{0}' -f ([guid]::NewGuid().ToString('N')))
    New-Item -ItemType Directory -Path $script:Temp -Force | Out-Null

    $script:Resumo = & $script:Conversor -Source $script:FonteCs2 -Out $script:Temp

    $script:TweaksGerados = @((Get-Content -LiteralPath (Join-Path $script:Temp 'tweaks.jogos.json') -Raw -Encoding UTF8 | ConvertFrom-Json).tweaks)

    # Catalogo combinado: o que o usuario realmente executa (src/config committado,
    # Task 6 + Task 7 juntos via Get-TmxCatalog no diretorio padrao).
    $script:CatalogoCombinado = Get-TmxCatalog -Path $script:ConfigDir
}

AfterAll {
    if ($script:Temp -and (Test-Path -LiteralPath $script:Temp)) {
        Remove-Item -LiteralPath $script:Temp -Recurse -Force -ErrorAction SilentlyContinue
    }
    Remove-Module TweakMaxing -Force -ErrorAction SilentlyContinue
}

Describe 'Convert-CS2TunerCatalog contagens e formato' -Tag 'Jogos' {

    It 'converte os 47 tweaks do CS2Tuner' {
        $script:TweaksGerados.Count | Should -Be 47
        $script:Resumo.tweaks | Should -Be 47
    }

    It 'ids sao JOG-001..JOG-047, em ordem, sem duplicata' {
        $ids = @($script:TweaksGerados | ForEach-Object { "$($_.id)" })
        $esperado = @(1..47 | ForEach-Object { 'JOG-{0:D3}' -f $_ })
        ($ids -join ',') | Should -Be ($esperado -join ',')
    }

    It 'grava UTF-8 sem BOM e com fim de linha LF' {
        $bytes = [System.IO.File]::ReadAllBytes((Join-Path $script:Temp 'tweaks.jogos.json'))
        ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should -BeFalse
        @($bytes | Where-Object { $_ -eq 13 }).Count | Should -Be 0
    }

    It 'e idempotente: a segunda passada produz os mesmos bytes' {
        $antes = (Get-FileHash -LiteralPath (Join-Path $script:Temp 'tweaks.jogos.json') -Algorithm SHA256).Hash
        & $script:Conversor -Source $script:FonteCs2 -Out $script:Temp | Out-Null
        $depois = (Get-FileHash -LiteralPath (Join-Path $script:Temp 'tweaks.jogos.json') -Algorithm SHA256).Hash
        $depois | Should -Be $antes
    }

    It 'falha claramente quando a fonte nao existe' {
        { & $script:Conversor -Source (Join-Path $script:Temp 'nao-existe.json') -Out (Join-Path $script:Temp 'saida-x') } |
            Should -Throw -ExpectedMessage '*nao encontrado*'
    }
}

Describe 'Convert-CS2TunerCatalog mapeamento editorial' -Tag 'Jogos' {

    It 'toda categoria comeca com "Jogos / "' {
        foreach ($t in $script:TweaksGerados) {
            "$($t.categoria)" | Should -Match '^Jogos / ' -Because "$($t.id)"
        }
    }

    It 'guarda o id original do CS2Tuner em origem.cs2tuner' {
        foreach ($t in $script:TweaksGerados) {
            "$($t.origem.cs2tuner)" | Should -Not -BeNullOrEmpty -Because "$($t.id)"
        }
    }

    It 'reversivel e sempre total (fonte so tem reversivel=true)' {
        foreach ($t in $script:TweaksGerados) {
            "$($t.reversivel)" | Should -Be 'total' -Because "$($t.id)"
        }
    }

    It 'os 6 tweaks FOLCLORE tem presets vazio e bloco folclore com porqueNaoRecomendamos' {
        $folclore = @($script:TweaksGerados | Where-Object { $_.tier -eq 'FOLCLORE' })
        $folclore.Count | Should -Be 6
        foreach ($t in $folclore) {
            @($t.presets).Count | Should -Be 0 -Because "$($t.id)"
            "$($t.folclore.porqueNaoRecomendamos)" | Should -Not -BeNullOrEmpty -Because "$($t.id)"
        }
    }

    It 'tweaks manuais viram controle info com instrucoes e sem acoes' {
        $manuais = @($script:TweaksGerados | Where-Object { $_.controle -eq 'info' })
        $manuais.Count | Should -BeGreaterThan 0
        foreach ($t in $manuais) {
            "$($t.instrucoes)" | Should -Not -BeNullOrEmpty -Because "$($t.id)"
            @($t.acoes).Count | Should -Be 0 -Because "$($t.id)"
        }
    }

    It 'SVC-005 (exclusao do Defender) exige consentimento com frase' {
        $t = $script:TweaksGerados | Where-Object { $_.origem.cs2tuner -eq 'SVC-005' }
        $t | Should -Not -BeNullOrEmpty
        $t.requerConsentimentoExtra | Should -BeTrue
        "$($t.consentimento.frase)" | Should -Not -BeNullOrEmpty
    }

    It 'toda acao powershellCmdlet mapeada aponta para uma funcao Set-Tmx conhecida' {
        $funcoesEsperadas = @('Set-TmxUltimatePowerPlan', 'Set-TmxNicPower', 'Set-TmxDefenderExclusion', 'Set-TmxTrim', 'Set-TmxPagefile', 'Set-TmxGpuMsi')
        $achadas = New-Object 'System.Collections.Generic.HashSet[string]'
        foreach ($t in $script:TweaksGerados) {
            foreach ($a in @($t.acoes)) {
                if ("$($a.tipo)" -eq 'funcao') { [void]$achadas.Add("$($a.nome)") }
            }
        }
        foreach ($f in $achadas) { $funcoesEsperadas | Should -Contain $f }
    }

    It 'STO-004 (pagefile) carrega tamanhoMB nos parametros da acao' {
        $t = $script:TweaksGerados | Where-Object { $_.origem.cs2tuner -eq 'STO-004' }
        $acao = @($t.acoes | Where-Object { $_.tipo -eq 'funcao' }) | Select-Object -First 1
        $acao.nome | Should -Be 'Set-TmxPagefile'
        [int]$acao.parametros.tamanhoMB | Should -Be 16384
    }
}

Describe 'src/config catalogo combinado (Task 6 + Task 7)' -Tag 'Jogos' {

    It 'passa em Test-TmxCatalog sem nenhum erro' {
        $r = Test-TmxCatalog -Catalog $script:CatalogoCombinado
        $r.erros | Should -BeNullOrEmpty
        $r.ok    | Should -BeTrue
    }

    It 'nao tem id duplicado entre tweaks.json e tweaks.jogos.json' {
        $ids = @($script:CatalogoCombinado | ForEach-Object { "$($_.id)" })
        @($ids | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name }) | Should -BeNullOrEmpty
    }

    It 'tem os 47 tweaks JOG-*' {
        @($script:CatalogoCombinado | Where-Object { "$($_.id)" -match '^JOG-\d{3}$' }).Count | Should -Be 47
    }

    It 'toda acao de tipo funcao referenciada por um tweak JOG-* tem o trio Set/Undo/Test carregado' {
        $nomes = New-Object 'System.Collections.Generic.HashSet[string]'
        foreach ($t in $script:CatalogoCombinado) {
            if ("$($t.id)" -notmatch '^JOG-\d{3}$') { continue }
            foreach ($a in @($t.acoes)) {
                if ($null -eq $a -or "$($a.tipo)" -ne 'funcao') { continue }
                [void]$nomes.Add("$($a.nome)")
            }
        }
        $nomes.Count | Should -BeGreaterThan 0
        foreach ($n in $nomes) {
            $sufixo = $n -replace '^Set-Tmx', ''
            foreach ($fn in $n, "Undo-Tmx$sufixo", "Test-Tmx$sufixo") {
                (Get-Command -Name $fn -ErrorAction SilentlyContinue) |
                    Should -Not -BeNullOrEmpty -Because "o catalogo Jogos referencia $n"
            }
        }
    }
}

Describe 'Resolve-TmxPlan: itens de energia bloqueados em notebook' -Tag 'Jogos' {

    BeforeAll {
        $script:PerfilLaptop  = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'fixtures\profile-laptop.json')  -Raw -Encoding UTF8 | ConvertFrom-Json
        $script:PerfilDesktop = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'fixtures\profile-desktop.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        # JOG-001/002/005 = PWR-001/002/005, JOG-012 = CPU-005: todos com
        # bloqueiaSe os.isLaptop == true no catalogo de origem.
        $script:IdsEnergiaLaptop = 'JOG-001', 'JOG-002', 'JOG-005', 'JOG-012'
    }

    It 'perfil de notebook real + preset desktop: fica bloqueado (bloqueiaSe os.isLaptop)' {
        $plano = Resolve-TmxPlan -Catalog $script:CatalogoCombinado -Profile $script:PerfilLaptop -Preset desktop
        foreach ($id in $script:IdsEnergiaLaptop) {
            $item = $plano.itens | Where-Object { $_.id -eq $id }
            $item | Should -Not -BeNullOrEmpty -Because $id
            $item.status | Should -Be 'bloqueado' -Because $id
            $item.selecionado | Should -BeFalse -Because $id
        }
    }

    It 'perfil desktop + preset notebook: fica fora do preset (excluido por ser prejudicial em notebook)' {
        $plano = Resolve-TmxPlan -Catalog $script:CatalogoCombinado -Profile $script:PerfilDesktop -Preset notebook
        foreach ($id in $script:IdsEnergiaLaptop) {
            $item = $plano.itens | Where-Object { $_.id -eq $id }
            $item | Should -Not -BeNullOrEmpty -Because $id
            $item.status | Should -Be 'foraDoPreset' -Because $id
            $item.selecionado | Should -BeFalse -Because $id
        }
    }

    It 'perfil desktop + preset desktop: planejado e selecionado (nao e notebook, nada bloqueia)' {
        $plano = Resolve-TmxPlan -Catalog $script:CatalogoCombinado -Profile $script:PerfilDesktop -Preset desktop
        foreach ($id in $script:IdsEnergiaLaptop) {
            $item = $plano.itens | Where-Object { $_.id -eq $id }
            $item.status | Should -Be 'planejado' -Because $id
            $item.selecionado | Should -BeTrue -Because $id
        }
    }
}

Describe 'Resolve-TmxPlan: FOLCLORE de Jogos nunca selecionado' -Tag 'Jogos' {

    It 'os 6 tweaks JOG FOLCLORE ficam status folclore e nao selecionados' {
        $perfil = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'fixtures\profile-desktop.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $plano  = Resolve-TmxPlan -Catalog $script:CatalogoCombinado -Profile $perfil -Preset desktop

        $idsFolcloreJog = @($script:CatalogoCombinado | Where-Object { "$($_.id)" -match '^JOG-\d{3}$' -and $_.tier -eq 'FOLCLORE' } | ForEach-Object { "$($_.id)" })
        $idsFolcloreJog.Count | Should -Be 6

        foreach ($id in $idsFolcloreJog) {
            $item = $plano.itens | Where-Object { $_.id -eq $id }
            $item.status | Should -Be 'folclore' -Because $id
            $item.selecionado | Should -BeFalse -Because $id
        }
    }
}
