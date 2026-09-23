# tests/Compile.Tests.ps1
# O Compile.ps1 e o artefato unico que ele gera.
#
# Compila UMA vez (BeforeAll) para uma pasta temporaria e confere o resultado
# de tres angulos:
#   1. o texto gerado (ASCII puro, sem BOM, cabecalho, catalogos, interface,
#      DLLs, tamanho);
#   2. o parser do PowerShell (zero erros de sintaxe);
#   3. o artefato RODANDO num processo separado - com -File e tambem por texto
#      (simulando 'iex (irm ...)', sem arquivo nenhum no disco). Rodar dentro
#      do Pester nao provaria nada: o escopo do teste ja tem as funcoes
#      carregadas pelo Import-Module.
#
# Todo processo filho tem prazo: um artefato que trave (esperando entrada, por
# exemplo) tem que quebrar o teste, nao pendurar a suite.

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

        function script:Invoke-TmxChildProcess {
            <#
            .SYNOPSIS
                Roda powershell.exe com prazo; devolve { codigo, texto, estourou }.
            #>
            param(
                [Parameter(Mandatory)] [string[]] $Argumentos,
                [int] $TimeoutMs = 120000
            )

            # [Diagnostics.Process] e nao Start-Process -PassThru: o objeto que
            # o Start-Process devolve volta com ExitCode VAZIO depois do
            # WaitForExit, e o teste passaria a comparar $null com 0.
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName               = (Get-Command powershell.exe).Source
            $psi.UseShellExecute        = $false
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError  = $true
            $psi.CreateNoWindow         = $true
            foreach ($a in $Argumentos) { $psi.Arguments += '"' + ($a -replace '"', '\"') + '" ' }

            $p = [System.Diagnostics.Process]::Start($psi)
            # ReadToEndAsync ANTES do WaitForExit: um pipe cheio trava o filho.
            $tarefaOut = $p.StandardOutput.ReadToEndAsync()
            $tarefaErr = $p.StandardError.ReadToEndAsync()

            if (-not $p.WaitForExit($TimeoutMs)) {
                try { $p.Kill() } catch { }
                try { & taskkill.exe /PID $p.Id /T /F 2>&1 | Out-Null } catch { }
                return [pscustomobject]@{ codigo = -1; texto = "ESTOUROU $TimeoutMs ms"; estourou = $true }
            }

            $saida = ''
            $erro  = ''
            if ($tarefaOut.Wait(15000)) { $saida = $tarefaOut.Result }
            if ($tarefaErr.Wait(5000))  { $erro  = $tarefaErr.Result }
            # O stderr de um powershell.exe redirecionado vem em CLIXML (barras
            # de progresso serializadas): ruido puro nas mensagens de falha.
            $erro = "$erro" -replace '(?s)#< CLIXML.*$', ''

            [pscustomobject]@{ codigo = $p.ExitCode; texto = "$saida$erro"; estourou = $false }
        }

        function script:Invoke-TmxArtefatoPorTexto {
            <#
            .SYNOPSIS
                Roda o artefato SEM arquivo, como 'iex (irm ...)': o texto vira
                scriptblock e e invocado com os parametros.
            .DESCRIPTION
                -EncodedCommand (e nao -File) de proposito: assim o processo
                filho nao tem $PSCommandPath - exatamente a situacao do 'iex'.
            #>
            param([Parameter(Mandatory)] [string] $Parametros)

            $comando =
                "'SEMARQUIVO=' + [string]::IsNullOrEmpty(`$PSCommandPath); " +
                "`$s=[IO.File]::ReadAllText('$script:Artefato'); " +
                "`$sb=[scriptblock]::Create(`$s); " +
                "& `$sb $Parametros; " +
                "`$c=0; if (`$null -ne `$global:TmxExitCode) { `$c=[int]`$global:TmxExitCode }; exit `$c"

            $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($comando))
            Invoke-TmxChildProcess -Argumentos @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $enc)
        }

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

        It 'e ASCII puro e sem BOM' {
            # Sem BOM porque o artefato tambem e consumido por 'iex': um EF BB BF
            # chega como U+FEFF no inicio do texto e o parser recusa. E so da
            # para viver sem BOM porque TUDO e ASCII - o acento dos catalogos
            # vira \uXXXX e a interface vira base64.
            $bytes = [IO.File]::ReadAllBytes($script:Artefato)
            ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) |
                Should -BeFalse -Because 'o artefato nao pode comecar com BOM'

            $indice = -1
            for ($i = 0; $i -lt $bytes.Length; $i++) {
                if ($bytes[$i] -gt 127) { $indice = $i; break }
            }
            $indice | Should -Be -1 -Because "ha byte fora do ASCII no offset $indice"
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

        It 'nao decide nada lendo o proprio texto (sem $MyInvocation.ScriptBlock)' {
            # Sob 'iex', $MyInvocation.MyCommand.ScriptBlock e o do comando
            # ENVOLVENTE, nao o corpo do artefato: a elevacao sem arquivo baixa
            # o release da versao em vez de tentar se auto-recuperar.
            # (a mencao em comentario no start.ps1 explica justamente por que
            # nao da para fazer isso; o que nao pode existir e a CHAMADA)
            $script:Texto | Should -Not -Match ([regex]::Escape('ScriptBlock.ToString()'))
            $script:Texto | Should -Match 'releases/download/v'
            $script:Texto | Should -Match ([regex]::Escape('Invoke-WebRequest -Uri $url -OutFile $self'))
        }

        It 'nao tem um segundo param() de script (o do main.ps1 foi removido)' {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:Artefato, [ref]$null, [ref]$null)
            $ast.ParamBlock | Should -Not -BeNullOrEmpty
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

        It 'escapa o acento dos catalogos como \uXXXX sem mudar o documento' {
            $script:Texto | Should -Match '\\u00' -Because 'os catalogos em portugues tem acento'

            $m = [regex]::Match($script:Texto, "(?s)\`$sync\.configs\['preset'\] = @'\r?\n(.*?)\r?\n'@")
            $m.Success | Should -BeTrue

            $doArtefato = $m.Groups[1].Value | ConvertFrom-Json
            $doDisco    = Get-Content -LiteralPath (Join-Path $script:Raiz 'src\config\preset.json') -Raw -Encoding UTF8 | ConvertFrom-Json

            ($doArtefato | ConvertTo-Json -Depth 20) | Should -Be ($doDisco | ConvertTo-Json -Depth 20)
        }

        It 'embute os arquivos da interface em base64 dos bytes' {
            foreach ($nome in 'index.html', 'app.css', 'app.js', 'tweaks.js', 'microwin.js', 'install.js', 'configure.js', 'updates.js') {
                $script:Texto | Should -Match ([regex]::Escape("`$sync.embedded.web['$nome']")) -Because "falta o arquivo '$nome'"
            }

            $m = [regex]::Match($script:Texto, [regex]::Escape("`$sync.embedded.web['index.html'] = '") + "([A-Za-z0-9+/=]+)'")
            $m.Success | Should -BeTrue
            $bytes   = [Convert]::FromBase64String($m.Groups[1].Value)
            $doDisco = [IO.File]::ReadAllBytes((Join-Path $script:Raiz 'src\web\index.html'))
            $bytes.Length | Should -Be $doDisco.Length -Because 'os bytes tem que sair identicos aos do repositorio'
            [Text.Encoding]::UTF8.GetString($bytes) | Should -Match '<!DOCTYPE'
        }

        It 'embute o modelo do autounattend do MicroWin em base64' {
            $m = [regex]::Match($script:Texto, [regex]::Escape('$sync.embedded.microwinTemplate = ''') + "([A-Za-z0-9+/=]+)'")
            $m.Success | Should -BeTrue
            [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($m.Groups[1].Value)) | Should -Match '<unattend'
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

    Context 'Here-strings e escape' {

        It 'nenhum catalogo embutido tem linha que fecharia a here-string' {
            # So os catalogos: a interface e o modelo entram em base64, que nao
            # tem quebra de linha nem aspa.
            $problemas = New-Object 'System.Collections.Generic.List[string]'
            foreach ($f in (Get-ChildItem -LiteralPath (Join-Path $script:Raiz 'src\config') -Filter '*.json' -File)) {
                $n = 0
                foreach ($linha in [IO.File]::ReadAllLines($f.FullName)) {
                    $n++
                    if ($linha -match "^'@") { $problemas.Add("$($f.Name):$n") }
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

        It 'ConvertTo-TmxAsciiJson escapa so o que esta fora do ASCII' {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:Compile, [ref]$null, [ref]$null)
            $fn = @($ast.FindAll({
                param($no)
                $no -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $no.Name -eq 'ConvertTo-TmxAsciiJson'
            }, $true))
            $fn.Count | Should -Be 1
            . ([scriptblock]::Create($fn[0].Extent.Text))

            # O acento entra por [char] e o esperado e montado com o mesmo
            # truque: este arquivo, como todo .ps1 do repositorio, e ASCII puro.
            $barra    = [char]0x005C
            $original = '{ "a": "caf' + [char]0x00E9 + '", "b": "ascii ' + $barra + $barra + ' puro" }'
            $esperado = '{ "a": "caf' + $barra + 'u00e9", "b": "ascii ' + $barra + $barra + ' puro" }'

            $saida = ConvertTo-TmxAsciiJson -Text $original
            $saida | Should -Be $esperado
            (ConvertFrom-Json $saida).a | Should -Be ('caf' + [char]0x00E9)
        }
    }

    Context 'Artefato em execucao (processo separado)' {

        BeforeAll {
            $script:RunPreset = Invoke-TmxChildProcess -Argumentos @(
                '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script:Artefato,
                '-Headless', '-Preset', 'desktop', '-DryRun', '-NoElevate')
        }

        It 'roda -Headless -Preset desktop -DryRun e sai com 0' {
            $script:RunPreset.estourou | Should -BeFalse
            $script:RunPreset.codigo | Should -Be 0 -Because "saida:`n$($script:RunPreset.texto)"
        }

        It 'monta o plano com o catalogo embutido (nao cai para catalogo vazio)' {
            $script:RunPreset.texto | Should -Not -Match 'Catalogo indisponivel' -Because "saida:`n$($script:RunPreset.texto)"
            $script:RunPreset.texto | Should -Not -Match 'Nao foi possivel montar o plano' -Because "saida:`n$($script:RunPreset.texto)"
        }

        It 'simula pelo menos 9 itens' {
            $m = [regex]::Match($script:RunPreset.texto, 'Simulacao concluida:\s*(\d+) itens')
            $m.Success | Should -BeTrue -Because "saida:`n$($script:RunPreset.texto)"
            ([int]$m.Groups[1].Value) | Should -BeGreaterOrEqual 9 -Because "saida:`n$($script:RunPreset.texto)"
        }

        It 'roda tambem SEM arquivo, como o iex faria (texto -> scriptblock)' {
            $r = Invoke-TmxArtefatoPorTexto -Parametros '-Headless -Preset desktop -DryRun -NoElevate'
            $r.estourou | Should -BeFalse
            $r.texto | Should -Match 'SEMARQUIVO=True' -Because "o processo filho tinha caminho de script:`n$($r.texto)"
            $r.texto | Should -Match 'Simulacao concluida:\s*\d+ itens' -Because "saida:`n$($r.texto)"
            $r.codigo | Should -Be 0 -Because "saida:`n$($r.texto)"
        }

        It 'recusa -Undo de uma execucao inexistente com codigo != 0' {
            $r = Invoke-TmxChildProcess -Argumentos @(
                '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script:Artefato,
                '-Headless', '-Undo', 'inexistente-de-verdade', '-NoElevate')
            $r.estourou | Should -BeFalse
            $r.codigo | Should -Not -Be 0 -Because "saida:`n$($r.texto)"
            $r.texto | Should -Match 'Nao foi possivel reverter'
        }

        It 'recusa -Undo latest quando nao ha execucao nenhuma' {
            $vazio = Join-Path $script:Temp ('home-vazio-{0}' -f ([guid]::NewGuid().ToString('N')))
            New-Item -ItemType Directory -Path $vazio -Force | Out-Null
            $env:TWEAKMAXING_HOME = $vazio
            try {
                $r = Invoke-TmxChildProcess -Argumentos @(
                    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script:Artefato,
                    '-Headless', '-Undo', 'latest', '-NoElevate')
            } finally {
                Remove-Item Env:\TWEAKMAXING_HOME -ErrorAction SilentlyContinue
            }
            $r.estourou | Should -BeFalse
            $r.codigo | Should -Not -Be 0 -Because "saida:`n$($r.texto)"
            $r.texto | Should -Match 'Nao foi possivel reverter'
            $r.texto | Should -Match 'Nenhuma execucao encontrada'
        }

        It 'define todas as funcoes no escopo do script (o que o pool de runspaces copia)' {
            # Tudo, menos o main.ps1: com ele o script chamaria 'exit' e levaria
            # o processo junto antes de qualquer verificacao.
            $marca = $script:Texto.IndexOf('# TMX-MAIN')
            $marca | Should -BeGreaterThan 0

            $corpo = Join-Path $script:Temp 'corpo.ps1'
            [IO.File]::WriteAllText($corpo, $script:Texto.Substring(0, $marca), (New-Object System.Text.ASCIIEncoding))

            $comando = ". '$corpo' -Headless -DryRun -NoElevate | Out-Null; " +
                       "'UI=' + [bool](Get-Command Start-TmxUserInterface -ErrorAction SilentlyContinue); " +
                       "'FUNCOES=' + @(Get-Command -CommandType Function | Where-Object { `$_.Name -match '-Tmx|TweakMaxing' }).Count; " +
                       "'CONFIGS=' + `$sync.configs.Count; " +
                       "'WEB=' + `$sync.embedded.web.Count"
            $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($comando))

            $r = Invoke-TmxChildProcess -Argumentos @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $enc)

            $r.estourou | Should -BeFalse
            $r.texto | Should -Match 'UI=True' -Because "saida:`n$($r.texto)"
            $r.texto | Should -Match 'CONFIGS=8' -Because "saida:`n$($r.texto)"
            $m = [regex]::Match($r.texto, 'FUNCOES=(\d+)')
            $m.Success | Should -BeTrue -Because "saida:`n$($r.texto)"
            ([int]$m.Groups[1].Value) | Should -BeGreaterThan 100 -Because "saida:`n$($r.texto)"
        }
    }
}
