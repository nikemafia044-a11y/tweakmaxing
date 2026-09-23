# tests/Compile.Tests.ps1
# O Compile.ps1 e o artefato unico que ele gera.
#
# Compila UMA vez (BeforeAll) para uma pasta temporaria e confere o resultado
# de tres angulos:
#   1. o texto gerado (cabecalho, catalogos, interface, DLLs, tamanho, BOM);
#   2. o parser do PowerShell (zero erros de sintaxe);
#   3. o artefato RODANDO num processo separado - headless e a definicao das
#      funcoes. Rodar dentro do Pester nao provaria nada: o escopo do teste ja
#      tem as funcoes carregadas pelo Import-Module.

. (Join-Path $PSScriptRoot '_Helpers.ps1')

Describe 'Compile.ps1' -Tag 'Compile' {

    BeforeAll {
        . (Join-Path $PSScriptRoot '_Helpers.ps1')

        $script:Raiz     = Split-Path $PSScriptRoot -Parent
        $script:Compile  = Join-Path $script:Raiz 'Compile.ps1'
        $script:SdkDir   = Join-Path $script:Raiz 'packages\webview2'
        $script:Dlls     = 'Microsoft.Web.WebView2.Core.dll', 'Microsoft.Web.WebView2.Wpf.dll', 'WebView2Loader.dll'

        $script:TemSdk = $true
        foreach ($dll in $script:Dlls) {
            if (-not (Test-Path -LiteralPath (Join-Path $script:SdkDir $dll))) { $script:TemSdk = $false }
        }

        $script:Temp = Join-Path ([IO.Path]::GetTempPath()) ('TmxCompile_{0}' -f ([guid]::NewGuid().ToString('N')))
        New-Item -ItemType Directory -Path $script:Temp -Force | Out-Null
        $script:Artefato = Join-Path $script:Temp 'TweakMaxing.ps1'

        # O processo filho nao pode herdar a pasta de teste de outra suite.
        $script:HomeAnterior = $env:TWEAKMAXING_HOME
        Remove-Item Env:\TWEAKMAXING_HOME -ErrorAction SilentlyContinue

        # -SkipSdk so quando as DLLs faltam de verdade: nesta maquina elas
        # existem e o teste quer justamente provar que entram no artefato.
        $script:SaidaCompile = if ($script:TemSdk) {
            & $script:Compile -Out $script:Artefato 2>&1 | Out-String
        } else {
            & $script:Compile -Out $script:Artefato -SkipSdk 2>&1 | Out-String
        }

        $script:Texto = if (Test-Path -LiteralPath $script:Artefato) {
            [IO.File]::ReadAllText($script:Artefato)
        } else {
            ''
        }

        $script:Versao = (Get-Content -LiteralPath (Join-Path $script:Raiz 'VERSION') -Raw).Trim()
    }

    AfterAll {
        if ($script:HomeAnterior) { $env:TWEAKMAXING_HOME = $script:HomeAnterior }
        if ($script:Temp -and (Test-Path -LiteralPath $script:Temp)) {
            Remove-Item -LiteralPath $script:Temp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'Arquivo gerado' {

        It 'gera o artefato' {
            Test-Path -LiteralPath $script:Artefato | Should -BeTrue -Because "saida:`n$script:SaidaCompile"
        }

        It 'e UTF-8 com BOM (o conteudo embutido tem acento)' {
            $bytes = [IO.File]::ReadAllBytes($script:Artefato)
            $bytes[0] | Should -Be 0xEF
            $bytes[1] | Should -Be 0xBB
            $bytes[2] | Should -Be 0xBF
        }

        It 'passa pelo parser do PowerShell sem nenhum erro' {
            $erros = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile($script:Artefato, [ref]$null, [ref]$erros)
            $mensagens = @($erros | ForEach-Object { "linha $($_.Extent.StartLineNumber): $($_.Message)" })
            @($erros).Count | Should -Be 0 -Because ($mensagens -join "`n")
        }

        It 'tem menos de 8 MB' {
            (Get-Item -LiteralPath $script:Artefato).Length | Should -BeLessThan (8 * 1MB)
        }

        It 'traz o cabecalho de licenca com CT Tech Group, MIT e a versao' {
            $cabecalho = $script:Texto.Substring(0, 900)
            $cabecalho | Should -Match 'CT Tech Group'
            $cabecalho | Should -Match 'MIT'
            $cabecalho | Should -Match ([regex]::Escape("TweakMaxing v$script:Versao"))
            $cabecalho | Should -Match 'SHA256SUMS\.txt'
        }

        It 'mantem o marcador #TMX-COMPILED e substitui version/repo' {
            $script:Texto | Should -Match '#TMX-COMPILED'
            $script:Texto | Should -Match ([regex]::Escape("`$script:TmxVersion = '$script:Versao'"))
            $script:Texto | Should -Not -Match ([regex]::Escape('#{version}'))
            $script:Texto | Should -Not -Match ([regex]::Escape('#{repo}'))
        }

        It 'nao tem um segundo param() de script (o do main.ps1 foi removido)' {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:Artefato, [ref]$null, [ref]$null)
            $ast.ParamBlock | Should -Not -BeNullOrEmpty
            # Um param() de nivel de script fora do inicio seria erro de sintaxe
            # e o teste do parser acima ja teria quebrado; aqui so confirmamos
            # que o unico param que sobrou e o do start.ps1.
            $ast.ParamBlock.Parameters.Name.VariablePath.UserPath | Should -Contain 'Headless'
        }

        It 'grava SHA256SUMS.txt ao lado do artefato' {
            $sums = Join-Path $script:Temp 'SHA256SUMS.txt'
            Test-Path -LiteralPath $sums | Should -BeTrue
            $hash = (Get-FileHash -LiteralPath $script:Artefato -Algorithm SHA256).Hash
            (Get-Content -LiteralPath $sums -Raw) | Should -Match ([regex]::Escape($hash))
        }
    }

    Context 'Dados embutidos' {

        It 'embute os oito catalogos de src/config' {
            foreach ($nome in 'tweaks', 'tweaks.jogos', 'tweaks.updates', 'applications', 'feature', 'appx', 'dns', 'preset') {
                $script:Texto | Should -Match ([regex]::Escape("`$sync.configs['$nome']")) -Because "falta o catalogo '$nome'"
            }
        }

        It 'embute os arquivos da interface' {
            foreach ($nome in 'index.html', 'app.css', 'app.js', 'tweaks.js', 'microwin.js', 'install.js', 'configure.js', 'updates.js') {
                $script:Texto | Should -Match ([regex]::Escape("`$sync.embedded.web['$nome']")) -Because "falta o arquivo '$nome'"
            }
        }

        It 'embute o modelo do autounattend do MicroWin' {
            $script:Texto | Should -Match ([regex]::Escape('$sync.embedded.microwinTemplate'))
            $script:Texto | Should -Match '<unattend'
        }

        It 'embute as tres DLLs do WebView2 em base64' {
            if (-not $script:TemSdk) {
                Set-ItResult -Skipped -Because 'packages\webview2 nao existe nesta maquina'
                return
            }
            foreach ($dll in $script:Dlls) {
                $padrao = [regex]::Escape("`$sync.embedded.webview2['$dll'] = '") + "([A-Za-z0-9+/=]+)'"
                $m = [regex]::Match($script:Texto, $padrao)
                $m.Success | Should -BeTrue -Because "falta a DLL '$dll'"
                $m.Groups[1].Value.Length | Should -BeGreaterThan 100000 -Because "base64 de '$dll' parece truncado"
            }
        }

        It 'nao embute DLL nenhuma quando o SDK falta (-SkipSdk)' {
            if ($script:TemSdk) {
                Set-ItResult -Skipped -Because 'o SDK existe nesta maquina; o caminho sem DLL e o do aviso do compile'
                return
            }
            $script:Texto | Should -Not -Match ([regex]::Escape('$sync.embedded.webview2'))
            $script:SaidaCompile | Should -Match 'NAO vai conter as DLLs'
        }
    }

    Context 'Here-strings' {

        It 'nenhum ativo embutido tem linha que fecharia a here-string' {
            $ativos = New-Object 'System.Collections.Generic.List[string]'
            foreach ($f in (Get-ChildItem -LiteralPath (Join-Path $script:Raiz 'src\config') -Filter '*.json' -File)) {
                $ativos.Add($f.FullName)
            }
            foreach ($f in (Get-ChildItem -LiteralPath (Join-Path $script:Raiz 'src\web') -File -Recurse)) {
                $ativos.Add($f.FullName)
            }
            $modelo = Join-Path $script:Raiz 'tools\microwin\autounattend.template.xml'
            if (Test-Path -LiteralPath $modelo) { $ativos.Add($modelo) }

            $problemas = New-Object 'System.Collections.Generic.List[string]'
            foreach ($caminho in $ativos.ToArray()) {
                $n = 0
                foreach ($linha in [IO.File]::ReadAllLines($caminho)) {
                    $n++
                    if ($linha -match "^'@") { $problemas.Add("${caminho}:${n}") }
                }
            }
            $problemas.Count | Should -Be 0 -Because "fechariam a here-string: $($problemas.ToArray() -join ', ')"
        }

        It 'Assert-TmxHereStringSafe recusa conteudo perigoso, com arquivo e linha' {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:Compile, [ref]$null, [ref]$null)
            $fn = @($ast.FindAll({
                param($no)
                $no -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $no.Name -eq 'Assert-TmxHereStringSafe'
            }, $true))
            $fn.Count | Should -Be 1
            . ([scriptblock]::Create($fn[0].Extent.Text))

            { Assert-TmxHereStringSafe -Text "primeira`r`nsegunda" -Origem 'ok.json' } | Should -Not -Throw
            { Assert-TmxHereStringSafe -Text "primeira`r`n'@ fim" -Origem 'ruim.json' } | Should -Throw '*ruim.json:2*'
        }
    }

    Context 'Artefato em execucao (processo separado)' {

        BeforeAll {
            $saida = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:Artefato `
                -Headless -Preset desktop -DryRun -NoElevate 2>&1
            $script:CodigoPreset = $LASTEXITCODE
            $script:TextoPreset  = ($saida | Out-String)
        }

        It 'roda -Headless -Preset desktop -DryRun e sai com 0' {
            $script:CodigoPreset | Should -Be 0 -Because "saida:`n$script:TextoPreset"
        }

        It 'monta o plano com o catalogo embutido (nao cai para catalogo vazio)' {
            $script:TextoPreset | Should -Not -Match 'Catalogo indisponivel' -Because "saida:`n$script:TextoPreset"
            $script:TextoPreset | Should -Not -Match 'Nao foi possivel montar o plano' -Because "saida:`n$script:TextoPreset"
        }

        It 'simula pelo menos 9 itens' {
            $m = [regex]::Match($script:TextoPreset, 'Simulacao concluida:\s*(\d+) itens')
            $m.Success | Should -BeTrue -Because "saida:`n$script:TextoPreset"
            ([int]$m.Groups[1].Value) | Should -BeGreaterOrEqual 9 -Because "saida:`n$script:TextoPreset"
        }

        It 'recusa -Undo de uma execucao inexistente com codigo != 0' {
            $saida = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:Artefato `
                -Headless -Undo inexistente-de-verdade -NoElevate 2>&1
            $codigo = $LASTEXITCODE
            $texto  = ($saida | Out-String)
            $codigo | Should -Not -Be 0 -Because "saida:`n$texto"
            $texto | Should -Match 'Nao foi possivel reverter'
        }

        It 'define todas as funcoes no escopo do script (o que o pool de runspaces copia)' {
            # Tudo, menos o main.ps1: com ele o script chamaria 'exit' e levaria
            # o processo junto antes de qualquer verificacao.
            $marca = $script:Texto.IndexOf('# TMX-MAIN')
            $marca | Should -BeGreaterThan 0

            $corpo = Join-Path $script:Temp 'corpo.ps1'
            [IO.File]::WriteAllText($corpo, $script:Texto.Substring(0, $marca), (New-Object System.Text.UTF8Encoding($true)))

            $comando = ". '$corpo' -Headless -DryRun -NoElevate | Out-Null; " +
                       "'UI=' + [bool](Get-Command Start-TmxUserInterface -ErrorAction SilentlyContinue); " +
                       "'FUNCOES=' + @(Get-Command -CommandType Function | Where-Object { `$_.Name -match '-Tmx|TweakMaxing' }).Count; " +
                       "'CONFIGS=' + `$sync.configs.Count; " +
                       "'WEB=' + `$sync.embedded.web.Count"

            $texto = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -Command $comando 2>&1 | Out-String)

            $texto | Should -Match 'UI=True' -Because "saida:`n$texto"
            $texto | Should -Match 'CONFIGS=8' -Because "saida:`n$texto"
            $texto | Should -Match 'WEB=\d+' -Because "saida:`n$texto"
            $m = [regex]::Match($texto, 'FUNCOES=(\d+)')
            $m.Success | Should -BeTrue -Because "saida:`n$texto"
            ([int]$m.Groups[1].Value) | Should -BeGreaterThan 100 -Because "saida:`n$texto"
        }
    }
}
