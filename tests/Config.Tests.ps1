# Testes do catalogo COMMITADO em src/config (o que o usuario realmente executa).
#
# Diferente de Tools.Convert.Tests.ps1, que valida a saida de uma conversao nova
# em pasta temporaria, aqui o alvo e o arquivo versionado: se alguem editar
# src/config/tweaks.json na mao e quebrar o schema, e este teste que pega.

. "$PSScriptRoot\_Helpers.ps1"

BeforeAll {
    . "$PSScriptRoot\_Helpers.ps1"
    Import-TmxTestModule

    $script:RepoRaiz  = Split-Path $PSScriptRoot -Parent
    $script:ConfigDir = Join-Path $script:RepoRaiz 'src\config'
    $script:SrcDir    = Join-Path $script:RepoRaiz 'src'

    $script:Catalogo = Get-TmxCatalog -Path $script:ConfigDir
}

AfterAll {
    Remove-Module TweakMaxing -Force -ErrorAction SilentlyContinue
}

Describe 'src/config/tweaks.json' -Tag 'Config' {

    It 'passa em Test-TmxCatalog sem nenhum erro' {
        $r = Test-TmxCatalog -Catalog $script:Catalogo
        $r.erros | Should -BeNullOrEmpty
        $r.ok    | Should -BeTrue
    }

    It 'nao tem id duplicado' {
        $ids = @($script:Catalogo | ForEach-Object { "$($_.id)" })
        @($ids | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name }) | Should -BeNullOrEmpty
    }

    It 'toda acao de tipo funcao tem o trio Set/Undo/Test carregado no modulo' {
        $nomes = New-Object 'System.Collections.Generic.HashSet[string]'
        foreach ($t in $script:Catalogo) {
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
            $sufixo = $n -replace '^Set-Tmx', ''
            foreach ($fn in $n, "Undo-Tmx$sufixo", "Test-Tmx$sufixo") {
                (Get-Command -Name $fn -ErrorAction SilentlyContinue) |
                    Should -Not -BeNullOrEmpty -Because "o catalogo referencia $n"
            }
        }
    }
}

Describe 'src nao executa texto do catalogo' -Tag 'Config' {

    BeforeAll {
        # Sitios de execucao dinamica revisados e permitidos, por arquivo.
        # Regra do projeto: NADA vindo do catalogo (JSON) pode virar codigo. Um
        # sitio so entra aqui quando a origem do texto e comprovadamente interna
        # ao processo, nunca dado de configuracao.
        #
        #   Catalog.ps1      - o validador cita os proprios padroes proibidos
        #                      dentro da regex que procura por eles.
        #   Start-TmxJob.ps1 - scriptblock tem afinidade com o runspace onde
        #                      nasceu e nao atravessa a fronteira; o texto vem de
        #                      $Handler.ToString() (um scriptblock ja compilado no
        #                      processo), nunca de JSON.
        $script:SitiosDinamicosPermitidos = @{
            'Catalog.ps1'      = '[scriptblock]::Create'
            'Start-TmxJob.ps1' = '[scriptblock]::Create'
        }
    }

    It 'nenhum .ps1 de src usa Invoke-Expression' {
        $achados = New-Object 'System.Collections.Generic.List[string]'
        $arquivos = @(Get-ChildItem -LiteralPath $script:SrcDir -Recurse -Filter '*.ps1' -File)
        $arquivos.Count | Should -BeGreaterThan 0

        foreach ($m in @($arquivos | Select-String -Pattern 'Invoke-Expression')) {
            $linha = "$($m.Line)".Trim()
            # Comentario e permitido: e assim que documentamos POR QUE nao usamos.
            if ($linha.StartsWith('#')) { continue }
            if ((Split-Path $m.Path -Leaf) -eq 'Catalog.ps1') { continue }
            $achados.Add("$($m.Path):$($m.LineNumber): $linha")
        }
        $achados.ToArray() | Should -BeNullOrEmpty
    }

    It 'so usa ScriptBlock::Create em sitios revisados, com origem interna ao processo' {
        $achados = New-Object 'System.Collections.Generic.List[string]'
        $arquivos = @(Get-ChildItem -LiteralPath $script:SrcDir -Recurse -Filter '*.ps1' -File)

        foreach ($m in @($arquivos | Select-String -Pattern '\[scriptblock\]::Create')) {
            $linha = "$($m.Line)".Trim()
            if ($linha.StartsWith('#')) { continue }
            $nome = Split-Path $m.Path -Leaf
            if ($script:SitiosDinamicosPermitidos.ContainsKey($nome)) { continue }
            $achados.Add("$($m.Path):$($m.LineNumber): $linha")
        }
        $achados.ToArray() | Should -BeNullOrEmpty
    }

    It 'nenhuma funcao de tweak constroi codigo dinamicamente' {
        # Aqui a regra e absoluta: as funcoes nomeadas so falam com o sistema por
        # wrapper, nunca montando comando ou scriptblock a partir de texto.
        $dir = Join-Path $script:SrcDir 'functions\tweaks'
        $arquivos = @(Get-ChildItem -LiteralPath $dir -Recurse -Filter '*.ps1' -File)
        $arquivos.Count | Should -BeGreaterThan 0

        $achados = @($arquivos | Select-String -Pattern 'Invoke-Expression|\[scriptblock\]::Create|ScriptBlock\]::Create' |
                     Where-Object { -not "$($_.Line)".Trim().StartsWith('#') } |
                     ForEach-Object { "$($_.Path):$($_.LineNumber)" })
        $achados | Should -BeNullOrEmpty
    }

    It 'nenhuma funcao de tweak escreve no host' {
        $dir = Join-Path $script:SrcDir 'functions\tweaks'
        $achados = @(Get-ChildItem -LiteralPath $dir -Recurse -Filter '*.ps1' -File |
                     Select-String -Pattern '\bWrite-Host\b' |
                     Where-Object { -not "$($_.Line)".Trim().StartsWith('#') } |
                     ForEach-Object { "$($_.Path):$($_.LineNumber)" })
        $achados | Should -BeNullOrEmpty
    }
}

Describe 'src/config/applications.json' -Tag 'Config' {

    It 'tem ids unicos' {
        $doc = Get-Content -LiteralPath (Join-Path $script:ConfigDir 'applications.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $ids = @($doc.aplicativos | ForEach-Object { "$($_.id)" })
        $ids.Count | Should -BeGreaterThan 0
        @($ids | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name }) | Should -BeNullOrEmpty
    }

    It 'todo aplicativo tem nome e categoria' {
        $doc = Get-Content -LiteralPath (Join-Path $script:ConfigDir 'applications.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($a in @($doc.aplicativos)) {
            "$($a.nome)"      | Should -Not -BeNullOrEmpty -Because "id $($a.id)"
            "$($a.categoria)" | Should -Not -BeNullOrEmpty -Because "id $($a.id)"
        }
    }
}

Describe 'src/config/preset.json' -Tag 'Config' {

    It 'tem exatamente as chaves desktop, notebook e minimo' {
        $doc = Get-Content -LiteralPath (Join-Path $script:ConfigDir 'preset.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $chaves = @($doc.PSObject.Properties.Name | Sort-Object)
        $chaves -join ',' | Should -Be 'desktop,minimo,notebook'
    }

    It 'todo preset usado no catalogo existe em preset.json' {
        $doc = Get-Content -LiteralPath (Join-Path $script:ConfigDir 'preset.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $validos = @($doc.PSObject.Properties.Name)
        foreach ($t in $script:Catalogo) {
            foreach ($p in @($t.presets)) {
                $validos | Should -Contain $p -Because "$($t.id) usa o preset '$p'"
            }
        }
    }
}
