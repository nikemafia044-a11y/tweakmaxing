# tests/Install.Tests.ps1
# Aba Instalar: mapa de codigos de saida do winget/choco, fallback
# winget->choco em -Manager auto, parse de "winget list" e as acoes da
# ponte (apps.catalog, apps.install, apps.uninstall, apps.upgradeAll,
# apps.installed). Nao abre janela e nao exige elevacao - tudo aqui mocka
# Invoke-TmxWingetProcess/Invoke-TmxChocoProcess/Get-TmxCommandPath, entao
# nenhum winget/choco de verdade roda.

. (Join-Path $PSScriptRoot '_Helpers.ps1')

Describe 'Invoke-TmxPackage' -Tag 'Install' {

    BeforeAll {
        . (Join-Path $PSScriptRoot '_Helpers.ps1')
        Import-TmxTestModule
        New-TmxTestHome | Out-Null
    }

    AfterAll {
        Remove-TmxTestHome
    }

    Context 'Mapa de codigos de saida do winget' {

        BeforeEach {
            Mock -CommandName Get-TmxCommandPath -ModuleName TweakMaxing -MockWith {
                param($Name)
                "C:\fake\$Name.exe"
            }
        }

        It 'codigo <Codigo> vira <Resultado> (<DetalheContem>)' -ForEach @(
            @{ Codigo = 0;            Resultado = 'ok';     DetalheContem = 'codigo de saida 0';    Acao = 'Install' }
            @{ Codigo = 3010;         Resultado = 'ok';     DetalheContem = 'reinicio';              Acao = 'Install' }
            @{ Codigo = 1641;         Resultado = 'ok';     DetalheContem = 'reinicio';              Acao = 'Install' }
            @{ Codigo = -1978334967;  Resultado = 'ok';     DetalheContem = 'reinicio';              Acao = 'Install' }
            @{ Codigo = -1978334965;  Resultado = 'ok';     DetalheContem = 'reinicio';              Acao = 'Install' }
            @{ Codigo = -1978335135;  Resultado = 'pulado'; DetalheContem = 'ja instalado';          Acao = 'Install' }
            @{ Codigo = -1978335189;  Resultado = 'pulado'; DetalheContem = 'sem atualizacao';       Acao = 'Upgrade' }
            @{ Codigo = -1978335107;  Resultado = 'pulado'; DetalheContem = 'usuario atual';         Acao = 'Install' }
        ) {
            Mock -CommandName Invoke-TmxWingetProcess -ModuleName TweakMaxing -MockWith {
                param($Arguments)
                @{ codigo = $Codigo; saida = '' }
            }

            $programas = if ($Acao -eq 'Upgrade') { @('meu.app') } else { @('meu.app') }
            $r = Invoke-TmxPackage -Action $Acao -Programs $programas -Manager winget

            $r.Count | Should -Be 1
            $r[0].resultado | Should -Be $Resultado
            $r[0].codigo | Should -Be $Codigo
            $r[0].detalhe | Should -Match ([regex]::Escape($DetalheContem.Substring(0, [Math]::Min(6, $DetalheContem.Length))))
            $r[0].gerenciador | Should -Be 'winget'
        }

        It 'codigo desconhecido vira falha com o hex e o link do winget' {
            Mock -CommandName Invoke-TmxWingetProcess -ModuleName TweakMaxing -MockWith {
                @{ codigo = 87; saida = '' }
            }
            $r = Invoke-TmxPackage -Action Install -Programs @('meu.app') -Manager winget
            $r[0].resultado | Should -Be 'falha'
            $r[0].detalhe | Should -Match '0x00000057'
            $r[0].detalhe | Should -Match 'learn.microsoft.com/windows/package-manager/winget/returnCodes'
        }
    }

    Context 'Argumentos do winget' {

        BeforeEach {
            Mock -CommandName Get-TmxCommandPath -ModuleName TweakMaxing -MockWith { 'C:\fake\winget.exe' }
        }

        It 'prefixo msstore: vira --source msstore e some do id' {
            $script:argsCapturados = $null
            Mock -CommandName Invoke-TmxWingetProcess -ModuleName TweakMaxing -MockWith {
                param($Arguments)
                $script:argsCapturados = $Arguments
                @{ codigo = 0; saida = '' }
            }
            Invoke-TmxPackage -Action Install -Programs @('msstore:9WZDNCRFHWQZ') -Manager winget | Out-Null

            $script:argsCapturados | Should -Contain '--source'
            $idx = [array]::IndexOf($script:argsCapturados, '--source')
            $script:argsCapturados[$idx + 1] | Should -Be 'msstore'
            $script:argsCapturados | Should -Contain '9WZDNCRFHWQZ'
            $script:argsCapturados | Should -Not -Contain 'msstore:9WZDNCRFHWQZ'
        }

        It 'Upgrade all usa --all --include-unknown sem --id/--source' {
            $script:argsCapturados = $null
            Mock -CommandName Invoke-TmxWingetProcess -ModuleName TweakMaxing -MockWith {
                param($Arguments)
                $script:argsCapturados = $Arguments
                @{ codigo = 0; saida = '' }
            }
            Invoke-TmxPackage -Action Upgrade -Programs @('all') -Manager winget | Out-Null

            $script:argsCapturados | Should -Contain '--all'
            $script:argsCapturados | Should -Contain '--include-unknown'
            $script:argsCapturados | Should -Not -Contain '--id'
            $script:argsCapturados | Should -Not -Contain '--source'
        }
    }

    Context 'Manager auto: reserva no choco' {

        It 'cai para choco quando winget falha com codigo nao mapeado e o choco esta disponivel' {
            Mock -CommandName Get-TmxCommandPath -ModuleName TweakMaxing -MockWith {
                param($Name)
                "C:\fake\$Name.exe"
            }
            Mock -CommandName Invoke-TmxWingetProcess -ModuleName TweakMaxing -MockWith { @{ codigo = 87; saida = '' } }
            Mock -CommandName Invoke-TmxChocoProcess -ModuleName TweakMaxing -MockWith { @{ codigo = 0; saida = '' } }

            $r = Invoke-TmxPackage -Action Install -Programs @('meuapp') -Manager auto
            $r.Count | Should -Be 1
            $r[0].gerenciador | Should -Be 'choco'
            $r[0].resultado | Should -Be 'ok'
            $r[0].codigo | Should -Be 0
        }

        It 'sem choco disponivel devolve falha mencionando choco ausente' {
            Mock -CommandName Get-TmxCommandPath -ModuleName TweakMaxing -MockWith {
                param($Name)
                if ($Name -eq 'winget') { 'C:\fake\winget.exe' } else { $null }
            }
            Mock -CommandName Invoke-TmxWingetProcess -ModuleName TweakMaxing -MockWith { @{ codigo = 87; saida = '' } }

            $r = Invoke-TmxPackage -Action Install -Programs @('meuapp') -Manager auto
            $r[0].resultado | Should -Be 'falha'
            $r[0].detalhe | Should -Match 'ausente'
        }

        It 'nao cai para choco quando o winget so pulou (ja instalado)' {
            Mock -CommandName Get-TmxCommandPath -ModuleName TweakMaxing -MockWith {
                param($Name)
                "C:\fake\$Name.exe"
            }
            Mock -CommandName Invoke-TmxWingetProcess -ModuleName TweakMaxing -MockWith { @{ codigo = -1978335135; saida = '' } }
            Mock -CommandName Invoke-TmxChocoProcess -ModuleName TweakMaxing -MockWith { @{ codigo = 0; saida = '' } }

            $r = Invoke-TmxPackage -Action Install -Programs @('meuapp') -Manager auto
            $r[0].gerenciador | Should -Be 'winget'
            $r[0].resultado | Should -Be 'pulado'
            Should -Invoke -CommandName Invoke-TmxChocoProcess -ModuleName TweakMaxing -Times 0
        }
    }

    Context 'Codigos de saida do choco' {

        BeforeEach {
            Mock -CommandName Get-TmxCommandPath -ModuleName TweakMaxing -MockWith { 'C:\fake\choco.exe' }
        }

        It 'codigo <Codigo> do choco vira <Resultado>' -ForEach @(
            @{ Codigo = 0;    Resultado = 'ok' }
            @{ Codigo = 1641; Resultado = 'ok' }
            @{ Codigo = 3010; Resultado = 'ok' }
            @{ Codigo = 2;    Resultado = 'pulado' }
            @{ Codigo = 1;    Resultado = 'falha' }
        ) {
            Mock -CommandName Invoke-TmxChocoProcess -ModuleName TweakMaxing -MockWith { @{ codigo = $Codigo; saida = '' } }
            $r = Invoke-TmxPackage -Action Install -Programs @('meuapp') -Manager choco
            $r[0].resultado | Should -Be $Resultado
            $r[0].gerenciador | Should -Be 'choco'
        }

        It 'passa --no-progress para o choco' {
            $script:argsChocoCapturados = $null
            Mock -CommandName Invoke-TmxChocoProcess -ModuleName TweakMaxing -MockWith {
                param($Arguments)
                $script:argsChocoCapturados = $Arguments
                @{ codigo = 0; saida = '' }
            }
            Invoke-TmxPackage -Action Install -Programs @('meuapp') -Manager choco | Out-Null
            $script:argsChocoCapturados | Should -Contain '--no-progress'
        }
    }

    Context 'Validacao de id (Test-TmxPackageId) antes de montar argumentos' {

        It 'id de winget invalido vira falha sem chamar o processo' {
            Mock -CommandName Get-TmxCommandPath -ModuleName TweakMaxing -MockWith { 'C:\fake\winget.exe' }
            Mock -CommandName Invoke-TmxWingetProcess -ModuleName TweakMaxing -MockWith { @{ codigo = 0; saida = '' } }

            $r = Invoke-TmxPackage -Action Install -Programs @('id com espaco') -Manager winget
            $r[0].resultado | Should -Be 'falha'
            $r[0].detalhe | Should -Match 'invalido'
            Should -Invoke -CommandName Invoke-TmxWingetProcess -ModuleName TweakMaxing -Times 0
        }

        It 'id de choco invalido vira falha sem chamar o processo' {
            Mock -CommandName Get-TmxCommandPath -ModuleName TweakMaxing -MockWith { 'C:\fake\choco.exe' }
            Mock -CommandName Invoke-TmxChocoProcess -ModuleName TweakMaxing -MockWith { @{ codigo = 0; saida = '' } }

            $r = Invoke-TmxPackage -Action Install -Programs @('id;com;ponto-e-virgula') -Manager choco
            $r[0].resultado | Should -Be 'falha'
            $r[0].detalhe | Should -Match 'invalido'
            Should -Invoke -CommandName Invoke-TmxChocoProcess -ModuleName TweakMaxing -Times 0
        }

        It 'winget id vazio no catalogo pula direto para o choco em -Manager auto' {
            Mock -CommandName Get-TmxAppCatalog -ModuleName TweakMaxing -MockWith {
                @([pscustomobject]@{ id = 'semwinget'; winget = ''; choco = 'semwinget' })
            }
            Mock -CommandName Get-TmxCommandPath -ModuleName TweakMaxing -MockWith { param($Name) "C:\fake\$Name.exe" }
            Mock -CommandName Invoke-TmxWingetProcess -ModuleName TweakMaxing -MockWith { @{ codigo = 0; saida = '' } }
            Mock -CommandName Invoke-TmxChocoProcess -ModuleName TweakMaxing -MockWith { @{ codigo = 0; saida = '' } }

            $r = Invoke-TmxPackage -Action Install -Programs @('semwinget') -Manager auto -Catalog
            $r[0].gerenciador | Should -Be 'choco'
            $r[0].resultado | Should -Be 'ok'
            Should -Invoke -CommandName Invoke-TmxWingetProcess -ModuleName TweakMaxing -Times 0
        }
    }

    Context '-Catalog' {

        BeforeAll {
            $script:CatalogoTeste = @(
                [pscustomobject]@{ id = 'appum'; nome = 'App Um'; categoria = 'Utilitarios'; winget = 'Vendor.AppUm'; choco = 'appum'; link = 'https://example.org'; foss = $true }
            )
        }

        It 'lanca para um id desconhecido no catalogo' {
            Mock -CommandName Get-TmxAppCatalog -ModuleName TweakMaxing -MockWith { $script:CatalogoTeste }
            { Invoke-TmxPackage -Action Install -Programs @('naoexiste') -Manager winget -Catalog } |
                Should -Throw '*app desconhecido no catalogo*'
        }

        It 'resolve o id de winget do catalogo antes de rodar' {
            Mock -CommandName Get-TmxAppCatalog -ModuleName TweakMaxing -MockWith { $script:CatalogoTeste }
            Mock -CommandName Get-TmxCommandPath -ModuleName TweakMaxing -MockWith { 'C:\fake\winget.exe' }
            $script:argsCapturados = $null
            Mock -CommandName Invoke-TmxWingetProcess -ModuleName TweakMaxing -MockWith {
                param($Arguments)
                $script:argsCapturados = $Arguments
                @{ codigo = 0; saida = '' }
            }

            $r = Invoke-TmxPackage -Action Install -Programs @('appum') -Manager winget -Catalog
            $r[0].pacote | Should -Be 'appum'
            $script:argsCapturados | Should -Contain 'Vendor.AppUm'
        }
    }
}

Describe 'Get-TmxInstalledPackages' -Tag 'Install' {

    BeforeAll {
        . (Join-Path $PSScriptRoot '_Helpers.ps1')
        Import-TmxTestModule
        New-TmxTestHome | Out-Null
        $script:FixtureTexto = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'fixtures\winget-list.txt') -Raw -Encoding UTF8
    }

    AfterAll {
        Remove-TmxTestHome
    }

    BeforeEach {
        Mock -CommandName Invoke-TmxWingetProcess -ModuleName TweakMaxing -MockWith {
            @{ codigo = 0; saida = $script:FixtureTexto }
        }
    }

    It 'devolve um item por linha de dados da fixture' {
        $itens = Get-TmxInstalledPackages
        $itens.Count | Should -Be 8
    }

    It 'preserva um nome com caractere largo (CJK)' {
        # O literal CJK nao entra neste arquivo (.ps1 sem BOM: PS 5.1 le como
        # ANSI e corrompe qualquer caractere fora de ASCII). Em vez disso,
        # confere o mesmo texto lido diretamente da fixture (essa, sim, UTF-8).
        $linhaFixture = @(Get-Content -LiteralPath (Join-Path $PSScriptRoot 'fixtures\winget-list.txt') -Encoding UTF8) |
            Where-Object { $_ -match 'Wide\.App' } | Select-Object -First 1
        $nomeEsperado = ($linhaFixture -split '\s{2,}')[0].Trim()

        $itens = Get-TmxInstalledPackages
        $alvo = $itens | Where-Object { $_.id -eq 'Wide.App' }
        $alvo | Should -Not -BeNullOrEmpty
        $alvo.nome | Should -Be $nomeEsperado
        # E realmente largo (fora de ASCII), nao um substituto qualquer.
        [int][char]$alvo.nome[0] | Should -BeGreaterThan 127
    }

    It 'traz a coluna disponivel quando ha atualizacao e nulo quando nao ha' {
        $itens = Get-TmxInstalledPackages
        $firefox = $itens | Where-Object { $_.id -eq 'Mozilla.Firefox' }
        $firefox.disponivel | Should -Be '130.0.2'

        $sete = $itens | Where-Object { $_.id -eq '7zip.7zip' }
        $sete.disponivel | Should -BeNullOrEmpty
    }

    It '-Catalog marca instalado=true para ids do catalogo e false para os demais' {
        Mock -CommandName Get-TmxAppCatalog -ModuleName TweakMaxing -MockWith {
            @([pscustomobject]@{ id = 'firefox'; winget = 'Mozilla.Firefox' })
        }
        $itens = Get-TmxInstalledPackages -Catalog
        $firefox = $itens | Where-Object { $_.id -eq 'Mozilla.Firefox' }
        $firefox.instalado | Should -BeTrue
        $firefox.catalogId | Should -Be 'firefox'

        $chrome = $itens | Where-Object { $_.id -eq 'Google.Chrome' }
        $chrome.instalado | Should -BeFalse
    }

    It 'acha o separador mesmo com cabecalho pt-BR (Nome/ID/Versao/Disponivel/Origem)' {
        # O cabecalho deixa de importar: so a linha de tracos (^-{10,}$) e usada
        # para achar onde os dados comecam, entao um winget localizado em
        # outro idioma (ou versao futura) tambem funciona.
        $textoPtBr = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'fixtures\winget-list-ptbr.txt') -Raw -Encoding UTF8
        Mock -CommandName Invoke-TmxWingetProcess -ModuleName TweakMaxing -MockWith { @{ codigo = 0; saida = $textoPtBr } }

        $itens = Get-TmxInstalledPackages
        $itens.Count | Should -Be 4
        ($itens | Where-Object { $_.id -eq 'Mozilla.Firefox' }).disponivel | Should -Be '130.0.2'
        ($itens | Where-Object { $_.id -eq 'Microsoft.SecHealthUI' }).disponivel | Should -BeNullOrEmpty
    }
}

Describe 'Wrappers de processo' -Tag 'Install' {

    BeforeAll {
        . (Join-Path $PSScriptRoot '_Helpers.ps1')
        Import-TmxTestModule
        New-TmxTestHome | Out-Null
    }

    AfterAll {
        Remove-TmxTestHome
    }

    Context 'Invoke-TmxProcessWithTimeout' {

        It 'mata o processo e devolve tempo esgotado quando estoura o limite' {
            # powershell -Command Start-Sleep 5, com TimeoutSeconds 1: tem que
            # voltar bem antes dos 5s (senao o timeout nao fez nada) e nao
            # pode deixar o processo rodando pendurado.
            $cron = [System.Diagnostics.Stopwatch]::StartNew()
            $r = Invoke-TmxProcessWithTimeout -FilePath 'powershell' `
                -Arguments @('-NoProfile', '-Command', 'Start-Sleep -Seconds 5') -TimeoutSeconds 1
            $cron.Stop()

            $r.codigo | Should -Be -1
            $r.saida | Should -Be 'tempo esgotado'
            $cron.Elapsed.TotalSeconds | Should -BeLessThan 4
        }

        It 'devolve o codigo de saida de verdade quando o processo termina a tempo' {
            $r = Invoke-TmxProcessWithTimeout -FilePath 'powershell' `
                -Arguments @('-NoProfile', '-Command', 'exit 0') -TimeoutSeconds 30
            $r.codigo | Should -Be 0
        }
    }

    Context 'Invoke-TmxWingetProcess/ChocoProcess/Invoke-TmxPowerShellFile repassam o timeout' {

        It 'Invoke-TmxWingetProcess usa 900s por padrao e repassa -TimeoutSeconds' {
            $script:capturado = $null
            Mock -CommandName Invoke-TmxProcessWithTimeout -ModuleName TweakMaxing -MockWith {
                param($FilePath, $Arguments, $TimeoutSeconds, $DescricaoErro)
                $script:capturado = @{ FilePath = $FilePath; TimeoutSeconds = $TimeoutSeconds }
                @{ codigo = 0; saida = '' }
            }
            Invoke-TmxWingetProcess -Arguments @('--version') | Out-Null
            $script:capturado.FilePath | Should -Be 'winget'
            $script:capturado.TimeoutSeconds | Should -Be 900

            Invoke-TmxWingetProcess -Arguments @('--version') -TimeoutSeconds 60 | Out-Null
            $script:capturado.TimeoutSeconds | Should -Be 60
        }

        It 'Invoke-TmxChocoProcess usa 900s por padrao e repassa -TimeoutSeconds' {
            $script:capturado = $null
            Mock -CommandName Invoke-TmxProcessWithTimeout -ModuleName TweakMaxing -MockWith {
                param($FilePath, $Arguments, $TimeoutSeconds, $DescricaoErro)
                $script:capturado = @{ FilePath = $FilePath; TimeoutSeconds = $TimeoutSeconds }
                @{ codigo = 0; saida = '' }
            }
            Invoke-TmxChocoProcess -Arguments @('--version') -TimeoutSeconds 60 | Out-Null
            $script:capturado.FilePath | Should -Be 'choco'
            $script:capturado.TimeoutSeconds | Should -Be 60
        }
    }

    Context 'ConvertFrom-TmxProcessOutputBytes' {

        It 'decodifica UTF-8 com BOM' {
            # Sem literal acentuado no .ps1 (sem BOM: PS 5.1 le como ANSI e
            # corrompe qualquer caractere fora de ASCII) - monta a partir do
            # codepoint: 0xE3 = a-til, 0xED = i-agudo.
            $texto = 'Extens' + [char]0xE3 + 'o de V' + [char]0xED + 'deo'
            $bytes = [byte[]](0xEF, 0xBB, 0xBF) + [System.Text.Encoding]::UTF8.GetBytes($texto)
            ConvertFrom-TmxProcessOutputBytes -Bytes $bytes | Should -Be $texto
        }

        It 'decodifica UTF-8 sem BOM (medido nesta maquina: winget list redirecionado sai assim)' {
            # Fixture gerada com Encoding.UTF8.GetBytes (nunca inclui BOM), nao
            # editada por uma ferramenta de texto que poderia normalizar/mudar
            # o encoding do arquivo.
            $bytes = [System.IO.File]::ReadAllBytes((Join-Path $PSScriptRoot 'fixtures\winget-output-utf8-sembom.txt'))
            ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should -BeFalse -Because 'a fixture nao pode ter BOM'

            $esperadoExtensao  = 'Extens' + [char]0xE3 + 'o de V' + [char]0xED + 'deo'
            $esperadoSeguranca = 'Seguran' + [char]0xE7 + 'a'

            $texto = ConvertFrom-TmxProcessOutputBytes -Bytes $bytes
            $texto | Should -Match ([regex]::Escape($esperadoExtensao))
            $texto | Should -Match ([regex]::Escape($esperadoSeguranca))
        }

        It 'cai para OEM 850 quando os bytes nao sao UTF-8 valido' {
            $original = 'Seguran' + [char]0xE7 + 'a do Windows'
            $bytesOem = [System.Text.Encoding]::GetEncoding(850).GetBytes($original)
            # Confere a premissa: esses bytes NAO formam UTF-8 valido (senao o
            # teste passaria por acidente, sem exercitar o fallback).
            { (New-Object System.Text.UTF8Encoding($false, $true)).GetString($bytesOem) } | Should -Throw

            ConvertFrom-TmxProcessOutputBytes -Bytes $bytesOem | Should -Be $original
        }

        It 'string vazia para bytes vazios/nulos' {
            ConvertFrom-TmxProcessOutputBytes -Bytes @() | Should -Be ''
            ConvertFrom-TmxProcessOutputBytes -Bytes $null | Should -Be ''
        }
    }

    Context 'Test-TmxPackageId' {

        It '<Id> e valido' -ForEach @(
            @{ Id = '7zip.7zip' }
            @{ Id = 'Mozilla.Firefox' }
            @{ Id = 'msstore:9WZDNCRFHWQZ' }
            @{ Id = 'meu-pacote_1.0+x' }
        ) {
            Test-TmxPackageId -Id $Id | Should -BeTrue
        }

        It '<Id> e invalido' -ForEach @(
            @{ Id = '' }
            @{ Id = $null }
            @{ Id = 'id com espaco' }
            @{ Id = 'id;rm -rf' }
            @{ Id = 'id"com"aspas' }
            @{ Id = "id`ncom`nquebra" }
        ) {
            Test-TmxPackageId -Id $Id | Should -BeFalse
        }
    }

    Context 'Get-TmxAppCatalog valida ids ao carregar' {

        It 'registra aviso (nao lanca, nao remove) para id mal formado no catalogo' {
            $s = [Hashtable]::Synchronized(@{})
            $s.configs = @{
                applications = [pscustomobject]@{
                    aplicativos = @(
                        [pscustomobject]@{ id = 'ok'; nome = 'Ok'; winget = 'Vendor.Ok'; choco = 'ok' }
                        [pscustomobject]@{ id = 'ruim'; nome = 'Ruim'; winget = 'id com espaco'; choco = '' }
                    )
                }
            }
            $global:sync = $s
            try {
                Mock -CommandName Write-TmxLog -ModuleName TweakMaxing -MockWith { }
                # $apps=... DENTRO do scriptblock nao vazaria para fora (o
                # call operator do Should -Not -Throw roda num escopo filho) -
                # chama de novo, fora, para conferir o retorno.
                { Get-TmxAppCatalog } | Should -Not -Throw
                $apps = Get-TmxAppCatalog
                $apps.Count | Should -Be 2
                # Get-TmxAppCatalog roda duas vezes neste teste (a checagem de
                # -Not -Throw e a leitura de verdade logo depois), entao o
                # aviso tambem sai duas vezes.
                Should -Invoke -CommandName Write-TmxLog -ModuleName TweakMaxing -Times 2 -ParameterFilter {
                    $Level -eq 'WARN' -and $Message -like '*winget mal formado*'
                }
            } finally {
                Remove-Variable -Name sync -Scope Global -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'Test-TmxPackageManager' -Tag 'Install' {

    BeforeAll {
        . (Join-Path $PSScriptRoot '_Helpers.ps1')
        Import-TmxTestModule
        New-TmxTestHome | Out-Null
    }

    AfterAll {
        Remove-TmxTestHome
    }

    It 'reporta os dois disponiveis quando os wrappers respondem' {
        Mock -CommandName Get-TmxCommandPath -ModuleName TweakMaxing -MockWith {
            param($Name) "C:\fake\$Name.exe"
        }
        Mock -CommandName Invoke-TmxWingetProcess -ModuleName TweakMaxing -MockWith { @{ codigo = 0; saida = 'v1.9.0' } }
        Mock -CommandName Invoke-TmxChocoProcess -ModuleName TweakMaxing -MockWith { @{ codigo = 0; saida = '2.3.0' } }

        $r = Test-TmxPackageManager
        $r.winget.disponivel | Should -BeTrue
        $r.winget.versao | Should -Be 'v1.9.0'
        $r.winget.caminho | Should -Be 'C:\fake\winget.exe'
        $r.choco.disponivel | Should -BeTrue
        $r.choco.versao | Should -Be '2.3.0'
    }

    It 'reporta os dois ausentes quando nada esta no PATH' {
        Mock -CommandName Get-TmxCommandPath -ModuleName TweakMaxing -MockWith { $null }

        $r = Test-TmxPackageManager
        $r.winget.disponivel | Should -BeFalse
        $r.winget.versao | Should -BeNullOrEmpty
        $r.choco.disponivel | Should -BeFalse
        $r.choco.versao | Should -BeNullOrEmpty
    }

    It 'nunca lanca mesmo se o wrapper do winget lancar' {
        Mock -CommandName Get-TmxCommandPath -ModuleName TweakMaxing -MockWith { 'C:\fake\winget.exe' }
        Mock -CommandName Invoke-TmxWingetProcess -ModuleName TweakMaxing -MockWith { throw 'estourou' }
        { Test-TmxPackageManager } | Should -Not -Throw
    }
}

Describe 'Ponte da aba Instalar' -Tag 'Install' {

    BeforeAll {
        . (Join-Path $PSScriptRoot '_Helpers.ps1')
        Import-TmxTestModule
        New-TmxTestHome | Out-Null
        $script:FixtureTextoGlobal = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'fixtures\winget-list.txt') -Raw -Encoding UTF8

        function New-TmxInstallTestSync {
            $doc = [pscustomobject]@{
                aplicativos = @(
                    [pscustomobject]@{ id = 'testapp'; nome = 'Test App'; descricao = 'app de teste'; categoria = 'Utilitarios'; winget = 'Vendor.TestApp'; choco = 'testapp'; link = 'https://example.org'; foss = $true }
                    [pscustomobject]@{ id = 'testapp2'; nome = 'Test App 2'; descricao = 'outro app de teste'; categoria = 'Jogos'; winget = 'Vendor.TestApp2'; choco = ''; link = 'https://example.org'; foss = $false }
                )
            }
            $s = [Hashtable]::Synchronized(@{})
            $s.version       = '0.1.0-test'
            $s.testMode      = $true
            $s.configs       = @{ applications = $doc }
            $s.bridgeActions = @{}
            $s.activeJob     = $null
            $s.session       = $null
            $s.uiEvents      = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList))
            $global:sync = $s
            $s
        }

        function Wait-TmxInstallTestEvent {
            param(
                [Parameter(Mandatory)] [string] $Nome,
                [int] $TimeoutSeconds = 10
            )
            $limite = (Get-Date).AddSeconds($TimeoutSeconds)
            while ((Get-Date) -lt $limite) {
                # .ToArray() (metodo sincronizado do wrapper) e nao o pipeline
                # direto: o job escreve em $sync.uiEvents de outra runspace e
                # enumerar a lista enquanto ela cresce lanca "Colecao foi
                # modificada".
                $achado = @(@($sync.uiEvents.ToArray()) | Where-Object { $_.event -eq $Nome })
                if ($achado.Count -gt 0) { return $achado[0] }
                Start-Sleep -Milliseconds 100
            }
            $null
        }
    }

    AfterAll {
        if (Get-Command Close-TmxRunspacePool -ErrorAction SilentlyContinue) { Close-TmxRunspacePool }
        Remove-TmxTestHome
        Remove-Variable -Name sync -Scope Global -ErrorAction SilentlyContinue
    }

    BeforeEach {
        New-TmxInstallTestSync | Out-Null
        Register-TmxInstallActions
    }

    Context 'apps.catalog' {
        It 'agrupa o catalogo por categoria' {
            $r = Invoke-TmxBridgeRequest -Json '{"id":"1","action":"apps.catalog"}' | ConvertFrom-Json
            $r.ok | Should -BeTrue
            $r.result.categorias.Count | Should -Be 2
            $nomes = @($r.result.categorias | ForEach-Object { $_.nome })
            $nomes | Should -Contain 'Utilitarios'
            $nomes | Should -Contain 'Jogos'
            $util = $r.result.categorias | Where-Object { $_.nome -eq 'Utilitarios' }
            $util.apps.Count | Should -Be 1
            $util.apps[0].id | Should -Be 'testapp'
        }
    }

    Context 'apps.managers' {
        It 'devolve o status dos dois gerenciadores' {
            $r = Invoke-TmxBridgeRequest -Json '{"id":"2","action":"apps.managers"}' | ConvertFrom-Json
            $r.ok | Should -BeTrue
            $r.result.winget | Should -Not -BeNullOrEmpty
            $r.result.choco | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Acoes assincronas' {

        AfterEach {
            Wait-TmxRemainingWork -TimeoutSeconds 20 | Out-Null
            Close-TmxRunspacePool
        }

        It 'apps.install rejeita um id desconhecido (job.done com ok:false)' {
            $r = Invoke-TmxBridgeRequest -Json '{"id":"3","action":"apps.install","payload":{"ids":["naoexiste"]}}' | ConvertFrom-Json
            $r.ok | Should -BeTrue
            $r.result.jobId | Should -Not -BeNullOrEmpty

            $pronto = Wait-TmxInstallTestEvent -Nome 'job.done'
            $pronto | Should -Not -BeNullOrEmpty
            $pronto.payload.ok | Should -BeFalse
            $pronto.payload.error.message | Should -Match 'app desconhecido'
        }

        It 'apps.install devolve jobId na hora e job.done acontece (winget de verdade, id inexistente vira falha)' -Skip:(-not (Get-Command winget -ErrorAction SilentlyContinue)) {
            # Sem mock aqui de proposito: o job roda no pool de runspaces (Start-TmxJob),
            # que tem SUA PROPRIA copia das funcoes (New-TmxSessionState copia o texto de
            # cada funcao para uma InitialSessionState nova) - Mock -ModuleName TweakMaxing
            # so vale no runspace onde Pester roda, entao nao alcanca o job. O caminho
            # assincrono de ponta a ponta (jobId na hora, job.done depois) e o que da para
            # testar aqui; o conteudo do resultado (mockado) e coberto na proxima Context,
            # chamando o handler direto no runspace do Pester.
            $r = Invoke-TmxBridgeRequest -Json '{"id":"4","action":"apps.install","payload":{"ids":["testapp"]}}' | ConvertFrom-Json
            $r.ok | Should -BeTrue
            $r.result.jobId | Should -Not -BeNullOrEmpty

            $pronto = Wait-TmxInstallTestEvent -Nome 'job.done' -TimeoutSeconds 30
            $pronto | Should -Not -BeNullOrEmpty
            $pronto.payload.ok | Should -BeTrue
            $pronto.payload.result.Count | Should -Be 1
            $pronto.payload.result[0].pacote | Should -Be 'testapp'
        }

        # apps.upgradeAll nao tem teste "de verdade" aqui de proposito: sem mock
        # (o pool de runspaces nao enxerga Mock -ModuleName), isso rodaria
        # "winget upgrade --all" de verdade nesta maquina. A cobertura fica
        # so no handler mockado, chamado direto, na Context seguinte.
    }

    Context 'Handlers assincronos chamados direto (mock so alcanca o runspace do Pester)' {

        It 'apps.install (handler) instala com winget mockado' {
            Mock -CommandName Get-TmxCommandPath -ModuleName TweakMaxing -MockWith { 'C:\fake\winget.exe' }
            Mock -CommandName Invoke-TmxWingetProcess -ModuleName TweakMaxing -MockWith { @{ codigo = 0; saida = '' } }

            $entry = Get-TmxBridgeAction -Name 'apps.install'
            $entry.async | Should -BeTrue
            $resultado = & $entry.handler ([pscustomobject]@{ ids = @('testapp') })

            $resultado.Count | Should -Be 1
            $resultado[0].pacote | Should -Be 'testapp'
            $resultado[0].resultado | Should -Be 'ok'
            $resultado[0].gerenciador | Should -Be 'winget'
        }

        It 'apps.uninstall (handler) desinstala com winget mockado' {
            Mock -CommandName Get-TmxCommandPath -ModuleName TweakMaxing -MockWith { 'C:\fake\winget.exe' }
            Mock -CommandName Invoke-TmxWingetProcess -ModuleName TweakMaxing -MockWith { @{ codigo = 0; saida = '' } }

            $entry = Get-TmxBridgeAction -Name 'apps.uninstall'
            $entry.async | Should -BeTrue
            $resultado = & $entry.handler ([pscustomobject]@{ ids = @('testapp') })

            $resultado[0].resultado | Should -Be 'ok'
        }

        It 'apps.upgradeAll (handler) usa Programs=all com winget mockado' {
            Mock -CommandName Get-TmxCommandPath -ModuleName TweakMaxing -MockWith { 'C:\fake\winget.exe' }
            $script:argsCapturados = $null
            Mock -CommandName Invoke-TmxWingetProcess -ModuleName TweakMaxing -MockWith {
                param($Arguments)
                $script:argsCapturados = $Arguments
                @{ codigo = 0; saida = '' }
            }

            $entry = Get-TmxBridgeAction -Name 'apps.upgradeAll'
            $entry.async | Should -BeTrue
            $resultado = & $entry.handler $null

            $resultado[0].pacote | Should -Be 'all'
            $resultado[0].resultado | Should -Be 'ok'
            $script:argsCapturados | Should -Contain '--all'
        }

        It 'apps.installed (handler) devolve itens a partir do winget list mockado' {
            Mock -CommandName Invoke-TmxWingetProcess -ModuleName TweakMaxing -MockWith {
                @{ codigo = 0; saida = $script:FixtureTextoGlobal }
            }
            $entry = Get-TmxBridgeAction -Name 'apps.installed'
            $entry.async | Should -BeTrue
            $resultado = & $entry.handler $null
            $resultado.itens.Count | Should -Be 8
        }

        It 'apps.repairWinget (handler) esta registrado como assincrono' {
            (Get-TmxBridgeAction -Name 'apps.repairWinget').async | Should -BeTrue
        }

        It 'apps.installChoco (handler) esta registrado como assincrono' {
            (Get-TmxBridgeAction -Name 'apps.installChoco').async | Should -BeTrue
        }
    }

    Context 'Consentimento obrigatorio (apps.repairWinget / apps.installChoco)' {

        It 'apps.repairWinget recusa sem { consentido: true }' {
            Mock -CommandName Install-TmxWinget -ModuleName TweakMaxing -MockWith { [pscustomobject]@{ ok = $true; detalhe = 'nao deveria ter rodado' } }
            $entry = Get-TmxBridgeAction -Name 'apps.repairWinget'

            { & $entry.handler $null } | Should -Throw '*consentimento pendente*'
            { & $entry.handler ([pscustomobject]@{ consentido = $false }) } | Should -Throw '*consentimento pendente*'
            Should -Invoke -CommandName Install-TmxWinget -ModuleName TweakMaxing -Times 0
        }

        It 'apps.repairWinget roda quando consentido:true' {
            Mock -CommandName Install-TmxWinget -ModuleName TweakMaxing -MockWith { [pscustomobject]@{ ok = $true; detalhe = 'reparado' } }
            $entry = Get-TmxBridgeAction -Name 'apps.repairWinget'

            $r = & $entry.handler ([pscustomobject]@{ consentido = $true })
            $r.ok | Should -BeTrue
            Should -Invoke -CommandName Install-TmxWinget -ModuleName TweakMaxing -Times 1
        }

        It 'apps.installChoco recusa sem { consentido: true }' {
            Mock -CommandName Install-TmxChoco -ModuleName TweakMaxing -MockWith { [pscustomobject]@{ ok = $true; detalhe = 'nao deveria ter rodado' } }
            $entry = Get-TmxBridgeAction -Name 'apps.installChoco'

            { & $entry.handler $null } | Should -Throw '*consentimento pendente*'
            Should -Invoke -CommandName Install-TmxChoco -ModuleName TweakMaxing -Times 0
        }

        It 'apps.installChoco roda quando consentido:true' {
            Mock -CommandName Install-TmxChoco -ModuleName TweakMaxing -MockWith { [pscustomobject]@{ ok = $true; detalhe = 'instalado' } }
            $entry = Get-TmxBridgeAction -Name 'apps.installChoco'

            $r = & $entry.handler ([pscustomobject]@{ consentido = $true })
            $r.ok | Should -BeTrue
            Should -Invoke -CommandName Install-TmxChoco -ModuleName TweakMaxing -Times 1
        }
    }
}

Describe 'Endurecimento dos wrappers de instalacao' -Tag 'Install' {

    BeforeAll {
        . (Join-Path $PSScriptRoot '_Helpers.ps1')
        Import-TmxTestModule
    }

    AfterAll {
        Remove-Module TweakMaxing -Force -ErrorAction SilentlyContinue
    }

    Context 'Test-TmxPackageId' {

        It 'recusa id que comeca com hifen' -ForEach @(
            @{ alvo = '-Force' }
            @{ alvo = '--id' }
            @{ alvo = '-' }
        ) {
            # Um id assim iria para a linha de comando na posicao do VALOR de
            # --id e seria lido como mais uma opcao pelo winget/choco.
            Test-TmxPackageId -Id $alvo | Should -BeFalse
        }

        It 'continua aceitando hifen no meio do id' {
            Test-TmxPackageId -Id 'Publisher.Produto-2024' | Should -BeTrue
            Test-TmxPackageId -Id 'msstore:9MSSGKG348SP'    | Should -BeTrue
        }
    }

    Context 'Invoke-TmxProcessWithTimeout' {

        It 'descarta o objeto Process no fim' {
            $script:processoFalso = [pscustomobject]@{ Id = 4242; ExitCode = 0; Descartado = $false }
            $script:processoFalso | Add-Member -MemberType ScriptMethod -Name WaitForExit -Value { param($ms) $true } -Force
            $script:processoFalso | Add-Member -MemberType ScriptMethod -Name Dispose     -Value { $this.Descartado = $true } -Force

            Mock -ModuleName TweakMaxing -CommandName Start-Process -MockWith { $script:processoFalso }

            $r = Invoke-TmxProcessWithTimeout -FilePath 'fake.exe' -Arguments @('--x') -TimeoutSeconds 5
            $r.codigo | Should -Be 0
            $script:processoFalso.Descartado | Should -BeTrue
        }

        It 'descarta o Process tambem quando o tempo estoura' {
            $script:processoFalso = [pscustomobject]@{ Id = 4243; ExitCode = 0; Descartado = $false }
            $script:processoFalso | Add-Member -MemberType ScriptMethod -Name WaitForExit -Value { param($ms) $false } -Force
            $script:processoFalso | Add-Member -MemberType ScriptMethod -Name Dispose     -Value { $this.Descartado = $true } -Force

            Mock -ModuleName TweakMaxing -CommandName Start-Process       -MockWith { $script:processoFalso }
            Mock -ModuleName TweakMaxing -CommandName Stop-TmxProcessTree -MockWith { }

            $r = Invoke-TmxProcessWithTimeout -FilePath 'fake.exe' -Arguments @('--x') -TimeoutSeconds 1
            $r.codigo | Should -Be -1
            $r.saida  | Should -Be 'tempo esgotado'
            $script:processoFalso.Descartado | Should -BeTrue
        }
    }
}
