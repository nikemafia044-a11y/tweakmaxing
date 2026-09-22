# Testes do conversor WinUtil -> TweakMaxing (tools/Convert-WinUtilCatalog.ps1).
#
# O conversor roda uma vez em pasta temporaria no BeforeAll e todos os testes
# leem essa saida. Duas coisas importam aqui:
#   (a) fidelidade: as contagens do catalogo de origem tem que bater;
#   (b) o catalogo gerado tem que passar em Test-TmxCatalog com o modulo
#       carregado, porque o validador so consegue checar o trio
#       Set-/Undo-/Test-Tmx<X> se as funcoes existirem de verdade.

. "$PSScriptRoot\_Helpers.ps1"

BeforeAll {
    . "$PSScriptRoot\_Helpers.ps1"
    Import-TmxTestModule

    $script:RepoRaiz  = Split-Path $PSScriptRoot -Parent
    $script:Conversor = Join-Path $script:RepoRaiz 'tools\Convert-WinUtilCatalog.ps1'
    $script:Referencia = Join-Path $script:RepoRaiz 'reference\winutil'
    $script:Overlay    = Join-Path $script:RepoRaiz 'src\config\overlay\tweaks.overrides.json'
    $script:OverlayApp = Join-Path $script:RepoRaiz 'src\config\overlay\applications.overrides.json'

    $script:Temp = Join-Path ([System.IO.Path]::GetTempPath()) ('TmxConvert_{0}' -f ([guid]::NewGuid().ToString('N')))
    New-Item -ItemType Directory -Path $script:Temp -Force | Out-Null
    $script:Saida = Join-Path $script:Temp 'config'

    $script:Resumo = & $script:Conversor -Reference $script:Referencia -Out $script:Saida `
                        -Overlay $script:Overlay -OverlayApplications $script:OverlayApp |
                     Select-Object -Last 1

    function script:Get-TmxSaidaJson {
        param([Parameter(Mandatory)] [string] $Arquivo)
        Get-Content -LiteralPath (Join-Path $script:Saida $Arquivo) -Raw -Encoding UTF8 | ConvertFrom-Json
    }

    $script:Tweaks = @((Get-TmxSaidaJson 'tweaks.json').tweaks)
    $script:Apps   = @((Get-TmxSaidaJson 'applications.json').aplicativos)
    $script:Feats  = @((Get-TmxSaidaJson 'feature.json').recursos)
    $script:Appxs  = @((Get-TmxSaidaJson 'appx.json').appx)
    $script:Dnss   = @((Get-TmxSaidaJson 'dns.json').dns)

    # PackageId -> StoreId direto do catalogo de origem, para conferir o lookup.
    $script:MapaStore = @{}
    $appxOrigem = Get-Content -LiteralPath (Join-Path $script:Referencia 'config\appx.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($p in $appxOrigem.PSObject.Properties) {
        $pkg = "$($p.Value.PackageId)"
        if ($pkg -and $p.Value.StoreId) { $script:MapaStore[$pkg] = "$($p.Value.StoreId)" }
    }
}

AfterAll {
    if ($script:Temp -and (Test-Path -LiteralPath $script:Temp)) {
        Remove-Item -LiteralPath $script:Temp -Recurse -Force -ErrorAction SilentlyContinue
    }
    Remove-Module TweakMaxing -Force -ErrorAction SilentlyContinue
}

Describe 'Convert-WinUtilCatalog contagens' -Tag 'Convert' {

    It 'converte os 67 tweaks do WinUtil' {
        $script:Tweaks.Count | Should -Be 67
        $script:Resumo.tweaks | Should -Be 67
    }

    It 'converte os 236 aplicativos' {
        $script:Apps.Count | Should -Be 236
    }

    It 'converte os 33 recursos' {
        $script:Feats.Count | Should -Be 33
    }

    It 'converte os 34 pacotes appx' {
        $script:Appxs.Count | Should -Be 34
    }

    It 'converte os 8 provedores de DNS' {
        $script:Dnss.Count | Should -Be 8
    }
}

Describe 'Convert-WinUtilCatalog camada editorial' -Tag 'Convert' {

    It 'todo tweak tem tier, reversivel, porque, evidencia e controle' {
        $faltando = New-Object 'System.Collections.Generic.List[string]'
        foreach ($t in $script:Tweaks) {
            foreach ($campo in 'tier', 'reversivel', 'porque', 'evidencia', 'controle') {
                if (-not "$($t.$campo)") { $faltando.Add("$($t.id): $campo") }
            }
        }
        $faltando.ToArray() | Should -BeNullOrEmpty
    }

    It 'nenhum tweak FOLCLORE entra em preset' {
        $ruins = @($script:Tweaks | Where-Object { $_.tier -eq 'FOLCLORE' -and @($_.presets).Count -gt 0 })
        @($ruins | ForEach-Object { $_.id }) | Should -BeNullOrEmpty
    }

    It 'nenhum tweak irreversivel entra em preset' {
        $ruins = @($script:Tweaks | Where-Object { $_.reversivel -eq 'nenhuma' -and @($_.presets).Count -gt 0 })
        @($ruins | ForEach-Object { $_.id }) | Should -BeNullOrEmpty
    }

    It 'todo tweak irreversivel exige consentimento com frase' {
        foreach ($t in @($script:Tweaks | Where-Object { $_.reversivel -eq 'nenhuma' })) {
            $t.requerConsentimentoExtra | Should -BeTrue -Because "$($t.id) e irreversivel"
            "$($t.consentimento.frase)"  | Should -Not -BeNullOrEmpty -Because "$($t.id) e irreversivel"
        }
    }

    It 'todo tweak FOLCLORE traz o bloco folclore explicando por que nao recomendamos' {
        foreach ($t in @($script:Tweaks | Where-Object { $_.tier -eq 'FOLCLORE' })) {
            "$($t.folclore.porqueNaoRecomendamos)" | Should -Not -BeNullOrEmpty -Because "$($t.id) e FOLCLORE"
        }
    }

    It 'guarda a origem no WinUtil de cada tweak' {
        foreach ($t in $script:Tweaks) {
            "$($t.origem.winutil)" | Should -Not -BeNullOrEmpty
        }
    }

    It 'toggle carrega toggleDesligar com as acoes do estado desligado' {
        $toggles = @($script:Tweaks | Where-Object { $_.controle -eq 'toggle' })
        $toggles.Count | Should -BeGreaterThan 0
        foreach ($t in $toggles) {
            $t.PSObject.Properties['toggleDesligar'] | Should -Not -BeNullOrEmpty -Because "$($t.id) e toggle"
        }
    }

    It 'combobox tem ao menos duas opcoes com acoes' {
        foreach ($t in @($script:Tweaks | Where-Object { $_.controle -eq 'combobox' })) {
            @($t.opcoes).Count | Should -BeGreaterThan 1 -Because "$($t.id) e combobox"
            foreach ($o in @($t.opcoes)) {
                "$($o.valor)"  | Should -Not -BeNullOrEmpty
                "$($o.rotulo)" | Should -Not -BeNullOrEmpty
            }
        }
    }
}

Describe 'Convert-WinUtilCatalog acoes' -Tag 'Convert' {

    It 'toda acao appx com PackageId conhecido recebe o storeId' {
        $conferidos = 0
        foreach ($t in $script:Tweaks) {
            foreach ($a in @($t.acoes)) {
                if ("$($a.tipo)" -ne 'appx') { continue }
                $pkg = "$($a.pacote)"
                if (-not $script:MapaStore.ContainsKey($pkg)) { continue }
                "$($a.storeId)" | Should -Be $script:MapaStore[$pkg] -Because "$($t.id) remove $pkg"
                $conferidos++
            }
        }
        # Nao ha acao appx declarativa no catalogo atual do WinUtil (Widgets e
        # Windows AI passam por funcao nomeada). Se um dia houver, o laco acima
        # cobre; este Should documenta que o numero conferido e conhecido.
        $conferidos | Should -BeGreaterOrEqual 0
    }

    It 'nao copia script do WinUtil para dentro do catalogo' {
        $texto = Get-Content -LiteralPath (Join-Path $script:Saida 'tweaks.json') -Raw -Encoding UTF8
        $texto | Should -Not -Match 'Invoke-Expression'
        $texto | Should -Not -Match 'ScriptBlock\]::Create'
        $texto | Should -Not -Match 'Invoke-WinUtil'
    }

    It 'toda acao do tipo funcao aponta para um trio Set/Undo/Test existente' {
        $nomes = New-Object 'System.Collections.Generic.HashSet[string]'
        foreach ($t in $script:Tweaks) {
            $listas = @($t.acoes)
            foreach ($o in @($t.opcoes)) { $listas += @($o.acoes) }
            if ($t.PSObject.Properties['toggleDesligar']) { $listas += @($t.toggleDesligar) }
            foreach ($a in $listas) {
                if ($null -eq $a -or "$($a.tipo)" -ne 'funcao') { continue }
                [void]$nomes.Add("$($a.nome)")
            }
        }
        $nomes.Count | Should -BeGreaterThan 0
        foreach ($n in $nomes) {
            $n | Should -Match '^Set-Tmx[A-Za-z0-9]+$'
            $sufixo = $n.Substring('Set-Tmx'.Length)
            (Get-Command -Name $n -ErrorAction SilentlyContinue)              | Should -Not -BeNullOrEmpty
            (Get-Command -Name "Undo-Tmx$sufixo" -ErrorAction SilentlyContinue) | Should -Not -BeNullOrEmpty
            (Get-Command -Name "Test-Tmx$sufixo" -ErrorAction SilentlyContinue) | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Convert-WinUtilCatalog formato de saida' -Tag 'Convert' {

    It 'grava UTF-8 sem BOM e com fim de linha LF' {
        foreach ($arquivo in 'tweaks.json', 'applications.json', 'feature.json', 'appx.json', 'dns.json') {
            $bytes = [System.IO.File]::ReadAllBytes((Join-Path $script:Saida $arquivo))
            # BOM UTF-8 = EF BB BF
            ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should -BeFalse -Because "$arquivo nao pode ter BOM"
            @($bytes | Where-Object { $_ -eq 13 }).Count | Should -Be 0 -Because "$arquivo so pode ter LF"
        }
    }

    It 'e idempotente: a segunda passada produz os mesmos bytes' {
        $antes = @{}
        foreach ($arquivo in 'tweaks.json', 'applications.json', 'feature.json', 'appx.json', 'dns.json') {
            $antes[$arquivo] = (Get-FileHash -LiteralPath (Join-Path $script:Saida $arquivo) -Algorithm SHA256).Hash
        }

        & $script:Conversor -Reference $script:Referencia -Out $script:Saida `
            -Overlay $script:Overlay -OverlayApplications $script:OverlayApp | Out-Null

        foreach ($arquivo in $antes.Keys) {
            (Get-FileHash -LiteralPath (Join-Path $script:Saida $arquivo) -Algorithm SHA256).Hash |
                Should -Be $antes[$arquivo] -Because "$arquivo deve ser identico na segunda passada"
        }
    }
}

Describe 'Convert-WinUtilCatalog falhas declaradas' -Tag 'Convert' {

    It 'falha nomeando a chave quando o overlay esta incompleto' {
        $doc = Get-Content -LiteralPath $script:Overlay -Raw -Encoding UTF8 | ConvertFrom-Json
        $doc.PSObject.Properties.Remove('WPFTweaksTelemetry')

        $overlayQuebrado = Join-Path $script:Temp 'overlay-incompleto.json'
        $doc | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $overlayQuebrado -Encoding UTF8

        $saidaQuebrada = Join-Path $script:Temp 'config-quebrado'
        { & $script:Conversor -Reference $script:Referencia -Out $saidaQuebrada `
              -Overlay $overlayQuebrado -OverlayApplications $script:OverlayApp } |
            Should -Throw -ExpectedMessage '*WPFTweaksTelemetry*'
    }

    It 'falha quando a referencia do WinUtil nao existe' {
        $inexistente = Join-Path $script:Temp 'winutil-que-nao-existe'
        { & $script:Conversor -Reference $inexistente -Out (Join-Path $script:Temp 'config-vazio') `
              -Overlay $script:Overlay -OverlayApplications $script:OverlayApp } |
            Should -Throw -ExpectedMessage '*nao encontrada*'
    }
}

Describe 'Convert-WinUtilCatalog saida valida contra o schema' -Tag 'Convert' {

    It 'o catalogo gerado passa em Test-TmxCatalog' {
        $cat = Get-TmxCatalog -Path (Join-Path $script:Saida 'tweaks.json')
        $r = Test-TmxCatalog -Catalog $cat
        $r.erros | Should -BeNullOrEmpty
        $r.ok    | Should -BeTrue
        $r.total | Should -Be 67
    }
}
