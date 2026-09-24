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
        # Sitios de execucao dinamica conhecidos, por arquivo. Entrar nesta lista
        # NAO e aprovacao: e registro de que alguem olhou e de qual e a origem do
        # texto executado. A regra do projeto continua sendo que nada vindo do
        # catalogo (JSON) pode virar codigo.
        $script:SitiosDinamicosConhecidos = @{
            'Catalog.ps1'      = 'OK - o validador cita os proprios padroes proibidos dentro da regex que procura por eles; nada e executado.'
            'Start-TmxJob.ps1' = 'OK - scriptblock tem afinidade com o runspace onde nasceu e nao atravessa a fronteira; o texto vem de $Handler.ToString(), um scriptblock ja compilado neste processo, nunca de JSON.'
        }

        # Comentario de verdade e o que o parser do PowerShell marca como
        # comentario - inclusive bloco <# ... #>. Casar prefixo '#' na linha
        # deixava passar bloco de ajuda e dava falso positivo.
        function script:Get-TmxOcorrenciasEmCodigo {
            param(
                [Parameter(Mandatory)] [string] $Path,
                [Parameter(Mandatory)] [string] $Padrao
            )
            $tokens = $null
            $erros  = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$erros)
            $comentarios = @($tokens | Where-Object { $_.Kind -eq [System.Management.Automation.Language.TokenKind]::Comment })

            $texto = [System.IO.File]::ReadAllText($Path)
            $saida = New-Object 'System.Collections.Generic.List[string]'
            foreach ($m in [regex]::Matches($texto, $Padrao, 'IgnoreCase')) {
                $emComentario = $false
                foreach ($c in $comentarios) {
                    if ($m.Index -ge $c.Extent.StartOffset -and $m.Index -lt $c.Extent.EndOffset) { $emComentario = $true; break }
                }
                if ($emComentario) { continue }
                $linha = ($texto.Substring(0, $m.Index) -split "`n").Count
                $saida.Add("${Path}:${linha}")
            }
            , $saida.ToArray()
        }
    }

    It 'nenhum .ps1 de src usa Invoke-Expression fora de comentario' {
        $arquivos = @(Get-ChildItem -LiteralPath $script:SrcDir -Recurse -Filter '*.ps1' -File)
        $arquivos.Count | Should -BeGreaterThan 0

        $achados = New-Object 'System.Collections.Generic.List[string]'
        foreach ($f in $arquivos) {
            # Catalog.ps1 carrega o padrao dentro da regex do proprio validador.
            if ($f.Name -eq 'Catalog.ps1') { continue }
            foreach ($o in (Get-TmxOcorrenciasEmCodigo -Path $f.FullName -Padrao 'Invoke-Expression')) {
                $achados.Add($o)
            }
        }
        $achados.ToArray() | Should -BeNullOrEmpty
    }

    It 'todo uso de ScriptBlock::Create esta num sitio conhecido e justificado' {
        $arquivos = @(Get-ChildItem -LiteralPath $script:SrcDir -Recurse -Filter '*.ps1' -File)

        $achados = New-Object 'System.Collections.Generic.List[string]'
        foreach ($f in $arquivos) {
            if ($script:SitiosDinamicosConhecidos.ContainsKey($f.Name)) { continue }
            foreach ($o in (Get-TmxOcorrenciasEmCodigo -Path $f.FullName -Padrao '\[scriptblock\]::Create')) {
                $achados.Add($o)
            }
        }
        $achados.ToArray() | Should -BeNullOrEmpty
    }

    It 'a lista de sitios de execucao dinamica continua curta e com justificativa escrita' {
        # Se esta lista crescer sem ninguem notar, a regra vira decoracao.
        $script:SitiosDinamicosConhecidos.Count | Should -BeLessOrEqual 3
        foreach ($k in $script:SitiosDinamicosConhecidos.Keys) {
            "$($script:SitiosDinamicosConhecidos[$k])" | Should -Match '^(OK|PENDENTE)' -Because "$k precisa dizer se foi aprovado ou esta pendente"
            "$($script:SitiosDinamicosConhecidos[$k])".Length | Should -BeGreaterThan 40 -Because "$k precisa da justificativa por extenso"
        }
    }

    It 'nenhuma funcao de tweak constroi codigo dinamicamente' {
        # Aqui a regra e absoluta, sem lista de excecao: as funcoes nomeadas so
        # falam com o sistema por wrapper, nunca montando codigo a partir de texto.
        $dir = Join-Path $script:SrcDir 'functions\tweaks'
        $arquivos = @(Get-ChildItem -LiteralPath $dir -Recurse -Filter '*.ps1' -File)
        $arquivos.Count | Should -BeGreaterThan 0

        $achados = New-Object 'System.Collections.Generic.List[string]'
        foreach ($f in $arquivos) {
            foreach ($o in (Get-TmxOcorrenciasEmCodigo -Path $f.FullName -Padrao 'Invoke-Expression|\[scriptblock\]::Create|ScriptBlock\]::Create')) {
                $achados.Add($o)
            }
        }
        $achados.ToArray() | Should -BeNullOrEmpty
    }

    It 'nenhuma funcao de tweak escreve no host' {
        $dir = Join-Path $script:SrcDir 'functions\tweaks'
        $achados = New-Object 'System.Collections.Generic.List[string]'
        foreach ($f in @(Get-ChildItem -LiteralPath $dir -Recurse -Filter '*.ps1' -File)) {
            foreach ($o in (Get-TmxOcorrenciasEmCodigo -Path $f.FullName -Padrao '\bWrite-Host\b')) {
                $achados.Add($o)
            }
        }
        $achados.ToArray() | Should -BeNullOrEmpty
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

    It 'tem exatamente os presets antigos e os modos v2' {
        $doc = Get-Content -LiteralPath (Join-Path $script:ConfigDir 'preset.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $chaves = @($doc.PSObject.Properties.Name | Sort-Object)
        $chaves -join ',' | Should -Be 'avancado,desktop,leve,minimo,moderado,notebook,ultimate'
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
