# tests/MicroWin.Tests.ps1
# Aba MicroWin: leitura da ISO, build passo a passo, autounattend.xml e as
# acoes da ponte. Nao abre janela e nao exige elevacao.
#
# NADA aqui toca o sistema: oscdimg, Mount-DiskImage, o DISM inteiro e o
# robocopy estao todos mockados. A unica escrita real acontece dentro de
# TWEAKMAXING_HOME (pasta de trabalho) e de uma pasta temporaria de destino.

. (Join-Path $PSScriptRoot '_Helpers.ps1')

Describe 'MicroWin' -Tag 'MicroWin' {

    BeforeAll {
        . (Join-Path $PSScriptRoot '_Helpers.ps1')
        Import-TmxTestModule
        New-TmxTestHome | Out-Null

        $script:TmxRepo    = Split-Path $PSScriptRoot -Parent
        $script:TmxWebRoot = Join-Path $script:TmxRepo 'src\web'
        $script:TmxModelo  = Join-Path $script:TmxRepo 'tools\microwin\autounattend.template.xml'
        $script:TmxAppxJson = Join-Path $script:TmxRepo 'src\config\appx.json'

        # Resolucao do modelo sem depender de $PSScriptRoot dentro do modulo.
        $env:TMX_MICROWIN_TEMPLATE = $script:TmxModelo

        function New-TmxMicroWinTestSync {
            <#
            .SYNOPSIS
                $global:sync minimo para as acoes da ponte, com coletor de eventos.
            #>
            param([bool] $TestMode = $true)

            $s = [Hashtable]::Synchronized(@{})
            $s.version       = '0.1.0-test'
            $s.testMode      = $TestMode
            $s.webRoot       = $script:TmxWebRoot
            $s.configs       = @{}
            $s.bridgeActions = @{}
            $s.activeJob     = $null
            $s.session       = $null
            $s.uiEvents      = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList))
            $global:sync = $s
            $s
        }

        function Invoke-TmxBridgeTest {
            param(
                [Parameter(Mandatory)] [string] $Action,
                $Payload
            )
            $req = [ordered]@{ id = [guid]::NewGuid().ToString('N'); action = $Action; payload = $Payload }
            $json = Invoke-TmxBridgeRequest -Json ($req | ConvertTo-Json -Depth 12 -Compress)
            $json | ConvertFrom-Json
        }

        function Wait-TmxJobDoneById {
            param(
                [Parameter(Mandatory)] [string] $JobId,
                [int] $TimeoutSeconds = 60
            )
            $limite = (Get-Date).AddSeconds($TimeoutSeconds)
            while ((Get-Date) -lt $limite) {
                # .ToArray() e nao o pipeline direto: o job escreve na lista de
                # outra runspace e enumerar enquanto ela cresce lanca.
                $copia = @()
                try { $copia = $sync.uiEvents.ToArray() } catch { $copia = @() }
                $achado = @($copia | Where-Object { $_.event -eq 'job.done' -and "$($_.payload.jobId)" -eq $JobId })
                if ($achado.Count -gt 0) { return $achado[0].payload }
                Start-Sleep -Milliseconds 100
            }
            $null
        }

        function New-TmxFakeIso {
            <#
            .SYNOPSIS
                Um arquivo .iso vazio numa pasta temporaria (so para Test-Path).
            #>
            param()
            $pasta = Join-Path ([System.IO.Path]::GetTempPath()) ('TmxMicroWin_{0}' -f ([guid]::NewGuid().ToString('N')))
            New-Item -ItemType Directory -Path $pasta -Force | Out-Null
            $iso = Join-Path $pasta 'Windows11.iso'
            Set-Content -LiteralPath $iso -Value 'iso falsa' -Encoding ASCII
            [pscustomobject]@{ pasta = $pasta; iso = $iso; destino = (New-Item -ItemType Directory -Path (Join-Path $pasta 'saida') -Force).FullName }
        }

        function New-TmxFakeAppx {
            param([string] $Nome)
            [pscustomobject]@{ DisplayName = $Nome; PackageName = "${Nome}_1.0.0.0_neutral_~_8wekyb3d8bbwe" }
        }
    }

    AfterAll {
        if (Get-Command Close-TmxRunspacePool -ErrorAction SilentlyContinue) { Close-TmxRunspacePool }
        Remove-TmxTestHome
        Remove-Item Env:\TMX_MICROWIN_TEMPLATE -ErrorAction SilentlyContinue
        Remove-Variable -Name sync -Scope Global -ErrorAction SilentlyContinue
    }

    # -----------------------------------------------------------------------
    Context 'Pre-requisitos' {

        BeforeAll { . (Join-Path $PSScriptRoot '_Helpers.ps1') }

        BeforeEach {
            New-TmxMicroWinTestSync -TestMode $true | Out-Null
            Register-TmxMicroWinActions
        }

        It 'sem oscdimg a checagem reprova e explica o ADK' {
            Mock -CommandName Get-TmxOscdimgPath  -ModuleName TweakMaxing -MockWith { $null }
            Mock -CommandName Get-TmxFreeSpaceGB  -ModuleName TweakMaxing -MockWith { 120.0 }

            $r = Invoke-TmxBridgeTest -Action 'microwin.check'
            $r.ok | Should -BeTrue
            $r.result.pronto  | Should -BeFalse
            $r.result.oscdimg | Should -BeFalse
            (@($r.result.mensagens) -join ' ') | Should -Match 'oscdimg\.exe nao encontrado'
            (@($r.result.mensagens) -join ' ') | Should -Match 'Windows ADK'
            "$($r.result.urlAdk)" | Should -Match 'adk-install'
        }

        It 'devolve as constantes preenchidas (minimo de GB e link do ADK)' {
            Mock -CommandName Get-TmxOscdimgPath -ModuleName TweakMaxing -MockWith { 'C:\ADK\oscdimg.exe' }
            Mock -CommandName Get-TmxFreeSpaceGB -ModuleName TweakMaxing -MockWith { 120.0 }

            # Guarda de regressao: as constantes moram em funcao justamente
            # porque '$script:Tmx...' no topo do arquivo chega $null na
            # runspace da janela - e ai o minimo de espaco vira 0 e o regex de
            # usuario vira '' (que casa com tudo).
            $r = Invoke-TmxBridgeTest -Action 'microwin.check'
            [int]$r.result.espacoMinGB | Should -Be 20
            "$($r.result.urlAdk)" | Should -Not -BeNullOrEmpty
            (Get-TmxMicroWinUsuarioRegex) | Should -Not -BeNullOrEmpty
            Test-TmxMicroWinUsuario -Usuario '1fantasy' | Should -BeFalse
            Test-TmxMicroWinUsuario -Usuario 'fantasy'  | Should -BeTrue
            Test-TmxMicroWinUsuario -Usuario ''         | Should -BeFalse
        }

        It 'com oscdimg e espaco de sobra a checagem aprova no modo de teste' {
            Mock -CommandName Get-TmxOscdimgPath -ModuleName TweakMaxing -MockWith { 'C:\ADK\oscdimg.exe' }
            Mock -CommandName Get-TmxFreeSpaceGB -ModuleName TweakMaxing -MockWith { 120.0 }

            $r = Invoke-TmxBridgeTest -Action 'microwin.check'
            $r.result.pronto   | Should -BeTrue
            $r.result.espacoOk | Should -BeTrue
        }

        It 'reprova quando falta espaco em disco' {
            Mock -CommandName Get-TmxOscdimgPath -ModuleName TweakMaxing -MockWith { 'C:\ADK\oscdimg.exe' }
            Mock -CommandName Get-TmxFreeSpaceGB -ModuleName TweakMaxing -MockWith { 3.0 }

            $r = Invoke-TmxBridgeTest -Action 'microwin.check'
            $r.result.pronto   | Should -BeFalse
            $r.result.espacoOk | Should -BeFalse
            (@($r.result.mensagens) -join ' ') | Should -Match 'Espaco livre insuficiente'
        }

        It 'no modo de teste o seletor de ISO nao abre dialogo e devolve o caminho simulado' {
            $r = Invoke-TmxBridgeTest -Action 'microwin.pickIso' -Payload @{ simular = 'C:\ISOs\W11.iso' }
            $r.ok | Should -BeTrue
            "$($r.result.caminho)" | Should -Be 'C:\ISOs\W11.iso'
            $r.result.cancelado | Should -BeFalse
        }
    }

    # -----------------------------------------------------------------------
    Context 'Leitura da ISO' {

        BeforeAll { . (Join-Path $PSScriptRoot '_Helpers.ps1') }

        BeforeEach {
            New-TmxMicroWinTestSync -TestMode $true | Out-Null
            $script:Falsa = New-TmxFakeIso
            $global:TmxOrdem = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList))

            Mock -CommandName Mount-TmxDiskImageWrapper   -ModuleName TweakMaxing -MockWith { [void]$global:TmxOrdem.Add('mount-iso'); 'Z' }
            Mock -CommandName Dismount-TmxDiskImageWrapper -ModuleName TweakMaxing -MockWith { [void]$global:TmxOrdem.Add('dismount-iso'); $true }
            Mock -CommandName Get-TmxInstallImagePath     -ModuleName TweakMaxing -MockWith {
                [pscustomobject]@{ caminho = 'Z:\sources\install.wim'; formato = 'wim' }
            }
        }

        AfterEach {
            Remove-Item -LiteralPath $script:Falsa.pasta -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Variable -Name TmxOrdem -Scope Global -ErrorAction SilentlyContinue
        }

        It 'monta, le as edicoes e desmonta' {
            Mock -CommandName Get-TmxWindowsImageWrapper -ModuleName TweakMaxing -MockWith {
                @(
                    [pscustomobject]@{ ImageIndex = 1; ImageName = 'Windows 11 Home';       Version = '10.0.22631.1'; Architecture = 9 },
                    [pscustomobject]@{ ImageIndex = 2; ImageName = 'Windows 11 Pro';        Version = '10.0.22631.1'; Architecture = 9 }
                )
            }

            $info = Get-TmxIsoInfo -IsoPath $script:Falsa.iso
            $info.ok | Should -BeTrue
            @($info.edicoes).Count | Should -Be 2
            "$(@($info.edicoes)[1].nome)"        | Should -Be 'Windows 11 Pro'
            "$(@($info.edicoes)[1].arquitetura)" | Should -Be 'x64'
            [int](@($info.edicoes)[0].index)     | Should -Be 1
            @($global:TmxOrdem.ToArray()) | Should -Be @('mount-iso', 'dismount-iso')
        }

        It 'desmonta a ISO mesmo quando a leitura do WIM falha' {
            Mock -CommandName Get-TmxWindowsImageWrapper -ModuleName TweakMaxing -MockWith { throw 'wim corrompido' }

            $info = Get-TmxIsoInfo -IsoPath $script:Falsa.iso
            $info.ok | Should -BeFalse
            "$($info.mensagem)" | Should -Match 'wim corrompido'
            @($global:TmxOrdem.ToArray()) -contains 'dismount-iso' | Should -BeTrue
        }

        It 'recusa um arquivo que nao termina em .iso sem montar nada' {
            $outro = Join-Path $script:Falsa.pasta 'Windows11.img'
            Set-Content -LiteralPath $outro -Value 'x' -Encoding ASCII

            $info = Get-TmxIsoInfo -IsoPath $outro
            $info.ok | Should -BeFalse
            @($global:TmxOrdem.ToArray()).Count | Should -Be 0
        }
    }

    # -----------------------------------------------------------------------
    Context 'autounattend.xml' {

        BeforeAll { . (Join-Path $PSScriptRoot '_Helpers.ps1') }

        BeforeEach { New-TmxMicroWinTestSync -TestMode $true | Out-Null }

        It 'preenche usuario, idioma e teclado do pt-BR' {
            $xml = New-TmxUnattend -Usuario 'fantasy' -Senha 'Abc12345' -Idioma 'pt-BR' -TemplatePath $script:TmxModelo
            $xml | Should -Match 'fantasy'
            $xml | Should -Match 'pt-BR'
            $xml | Should -Match '0416:00000416'
            $xml | Should -Not -Match '\{\{'
        }

        It 'escapa < e & na senha e o resultado continua sendo XML valido' {
            $xml = New-TmxUnattend -Usuario 'fantasy' -Senha 'a<b&c' -Idioma 'pt-BR' -TemplatePath $script:TmxModelo
            $xml | Should -Match 'a&lt;b&amp;c'
            { [xml]$xml } | Should -Not -Throw
            ([xml]$xml).DocumentElement.Name | Should -Be 'unattend'
        }

        It 'recusa usuario vazio' {
            { New-TmxUnattend -Usuario '   ' -Senha 'x' -Idioma 'pt-BR' -TemplatePath $script:TmxModelo } |
                Should -Throw '*usuario obrigatorio*'
        }

        It 'nunca registra a senha no log' {
            $global:TmxLogs = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList))
            Mock -CommandName Write-TmxLog -ModuleName TweakMaxing -MockWith {
                $texto = "$Message"
                if ($Data) { foreach ($k in $Data.Keys) { $texto += " $k=$($Data[$k])" } }
                [void]$global:TmxLogs.Add($texto)
            }

            New-TmxUnattend -Usuario 'fantasy' -Senha 'SenhaSuperSecreta777' -Idioma 'pt-BR' -TemplatePath $script:TmxModelo | Out-Null

            @($global:TmxLogs.ToArray()).Count | Should -BeGreaterThan 0
            (@($global:TmxLogs.ToArray()) -join ' ') | Should -Not -Match 'SenhaSuperSecreta777'
            Remove-Variable -Name TmxLogs -Scope Global -ErrorAction SilentlyContinue
        }
    }

    # -----------------------------------------------------------------------
    Context 'Build' {

        BeforeAll { . (Join-Path $PSScriptRoot '_Helpers.ps1') }

        BeforeEach {
            New-TmxMicroWinTestSync -TestMode $false | Out-Null
            $script:Falsa    = New-TmxFakeIso
            $global:TmxOrdem = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList))
            $global:TmxArgs  = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList))

            Mock -CommandName Get-TmxOscdimgPath -ModuleName TweakMaxing -MockWith { 'C:\ADK\oscdimg.exe' }
            Mock -CommandName Get-TmxFreeSpaceGB -ModuleName TweakMaxing -MockWith { 120.0 }
            Mock -CommandName Test-TmxElevation  -ModuleName TweakMaxing -MockWith { $true }

            Mock -CommandName Mount-TmxDiskImageWrapper    -ModuleName TweakMaxing -MockWith { [void]$global:TmxOrdem.Add('mount-iso'); 'Z' }
            Mock -CommandName Dismount-TmxDiskImageWrapper -ModuleName TweakMaxing -MockWith { [void]$global:TmxOrdem.Add('dismount-iso'); $true }
            Mock -CommandName Copy-TmxIsoTree              -ModuleName TweakMaxing -MockWith { [void]$global:TmxOrdem.Add('copy'); 1 }
            Mock -CommandName Get-TmxInstallImagePath      -ModuleName TweakMaxing -MockWith {
                [pscustomobject]@{ caminho = (Join-Path $Raiz 'sources\install.wim'); formato = 'wim' }
            }
            Mock -CommandName Mount-TmxWindowsImageWrapper -ModuleName TweakMaxing -MockWith { [void]$global:TmxOrdem.Add('mount-image') }
            Mock -CommandName Get-TmxProvisionedAppxWrapper -ModuleName TweakMaxing -MockWith {
                @(
                    (New-TmxFakeAppx -Nome 'Microsoft.BingWeather'),
                    (New-TmxFakeAppx -Nome 'Microsoft.WindowsCalculator'),
                    (New-TmxFakeAppx -Nome 'Microsoft.Copilot')
                )
            }
            Mock -CommandName Remove-TmxProvisionedAppxWrapper -ModuleName TweakMaxing -MockWith {
                [void]$global:TmxOrdem.Add("appx:$PackageName")
            }
            Mock -CommandName Get-TmxWindowsPackageWrapper -ModuleName TweakMaxing -MockWith {
                @([pscustomobject]@{ PackageName = 'Microsoft-Windows-InternetExplorer-Optional-Package~31bf3856ad364e35~amd64~~11.0' })
            }
            Mock -CommandName Remove-TmxWindowsPackageWrapper -ModuleName TweakMaxing -MockWith {
                [void]$global:TmxOrdem.Add("pkg:$PackageName")
            }
            Mock -CommandName Dismount-TmxWindowsImageWrapper -ModuleName TweakMaxing -MockWith {
                [void]$global:TmxOrdem.Add($(if ($Save) { 'dismount-save' } else { 'dismount-discard' }))
            }
            # Cada argumento entra na lista separado: se o array voltar a ser
            # achatado num item so (foi um bug real de New-TmxIsoArgumentList),
            # a conferencia abaixo denuncia na hora.
            Mock -CommandName Invoke-TmxOscdimg -ModuleName TweakMaxing -MockWith {
                [void]$global:TmxOrdem.Add('oscdimg')
                foreach ($a in @($Arguments)) { [void]$global:TmxArgs.Add("$a") }
                $destino = @($Arguments)[@($Arguments).Count - 1]
                Set-Content -LiteralPath $destino -Value 'iso gerada' -Encoding ASCII
                [pscustomobject]@{ codigo = 0; saida = '' }
            }
        }

        AfterEach {
            Remove-Item -LiteralPath $script:Falsa.pasta -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Variable -Name TmxOrdem, TmxArgs -Scope Global -ErrorAction SilentlyContinue
        }

        It 'roda os passos na ordem combinada e gera a ISO' {
            $r = Invoke-TmxMicroWinBuild -IsoPath $script:Falsa.iso -EdicaoIndex 2 `
                -AppxRemover @('Microsoft.BingWeather', 'Microsoft.Copilot') `
                -PacotesRemover @('InternetExplorer') `
                -Usuario 'fantasy' -Senha 'Abc12345' -Destino $script:Falsa.destino

            $r.ok | Should -BeTrue
            $r.arquivo | Should -Not -BeNullOrEmpty
            Test-Path -LiteralPath $r.arquivo | Should -BeTrue

            $ordem = @($global:TmxOrdem.ToArray())
            $marcos = @($ordem | Where-Object { $_ -notmatch '^(appx|pkg):' })
            $marcos | Should -Be @('mount-iso', 'copy', 'dismount-iso', 'mount-image', 'dismount-save', 'oscdimg')

            # so os appx escolhidos (a Calculadora estava presente e ficou)
            $appx = @($ordem | Where-Object { $_ -like 'appx:*' })
            $appx.Count | Should -Be 2
            ($appx -join ' ') | Should -Match 'BingWeather'
            ($appx -join ' ') | Should -Match 'Copilot'
            ($appx -join ' ') | Should -Not -Match 'Calculator'

            $pkg = @($ordem | Where-Object { $_ -like 'pkg:*' })
            $pkg.Count | Should -Be 1
            ($pkg -join ' ') | Should -Match 'InternetExplorer'

            # a remocao de appx vem antes da de pacotes, e as duas antes do save
            [array]::IndexOf($ordem, $appx[0]) | Should -BeLessThan ([array]::IndexOf($ordem, $pkg[0]))
            [array]::IndexOf($ordem, $pkg[0])  | Should -BeLessThan ([array]::IndexOf($ordem, 'dismount-save'))
        }

        It 'monta o array de argumentos do oscdimg com os dois blocos de boot' {
            $lista = @(New-TmxIsoArgumentList -Origem 'C:\trab\contents' -Destino 'C:\saida\nova.iso')
            $lista | Should -Be @(
                '-m', '-o', '-u2', '-udfver102',
                '-bootdata:2#p0,e,bC:\trab\contents\boot\etfsboot.com#pEF,e,bC:\trab\contents\efi\microsoft\boot\efisys.bin',
                'C:\trab\contents',
                'C:\saida\nova.iso'
            )
        }

        It 'chama o oscdimg uma vez, com os argumentos esperados' {
            $r = Invoke-TmxMicroWinBuild -IsoPath $script:Falsa.iso -EdicaoIndex 1 `
                -Usuario 'fantasy' -Senha 'Abc12345' -Destino $script:Falsa.destino

            Should -Invoke -CommandName Invoke-TmxOscdimg -ModuleName TweakMaxing -Times 1 -Exactly

            $conteudo = Join-Path $r.pastaTrabalho 'contents'
            $esperado = @(
                '-m', '-o', '-u2', '-udfver102',
                ('-bootdata:2#p0,e,b{0}\boot\etfsboot.com#pEF,e,b{0}\efi\microsoft\boot\efisys.bin' -f $conteudo),
                $conteudo,
                $r.arquivo
            )
            @($global:TmxArgs.ToArray()) | Should -Be $esperado
        }

        It 'grava o autounattend.xml na raiz da ISO com o usuario e o pt-BR' {
            $r = Invoke-TmxMicroWinBuild -IsoPath $script:Falsa.iso -EdicaoIndex 1 `
                -Usuario 'fantasy' -Senha 'Abc12345' -Destino $script:Falsa.destino

            $xmlPath = Join-Path $r.pastaTrabalho 'contents\autounattend.xml'
            Test-Path -LiteralPath $xmlPath | Should -BeTrue
            $texto = [string](Get-Content -LiteralPath $xmlPath -Raw -Encoding UTF8)
            $texto | Should -Match '<Name>fantasy</Name>'
            $texto | Should -Match 'pt-BR'
            @($r.passos | Where-Object { "$($_.nome)" -eq 'autounattend' }).Count | Should -Be 1
        }

        It 'a ISO de origem nao e alterada' {
            $antes = (Get-Item -LiteralPath $script:Falsa.iso).LastWriteTimeUtc
            Invoke-TmxMicroWinBuild -IsoPath $script:Falsa.iso -EdicaoIndex 1 `
                -Usuario 'fantasy' -Senha 'Abc12345' -Destino $script:Falsa.destino | Out-Null
            (Get-Item -LiteralPath $script:Falsa.iso).LastWriteTimeUtc | Should -Be $antes
            [string](Get-Content -LiteralPath $script:Falsa.iso -Raw) | Should -Match 'iso falsa'
        }

        It 'falha na remocao de appx descarta a imagem e preserva a pasta de trabalho' {
            Mock -CommandName Remove-TmxProvisionedAppxWrapper -ModuleName TweakMaxing -MockWith {
                throw 'o DISM recusou o pacote'
            }

            $r = Invoke-TmxMicroWinBuild -IsoPath $script:Falsa.iso -EdicaoIndex 1 `
                -AppxRemover @('Microsoft.BingWeather') `
                -Usuario 'fantasy' -Senha 'Abc12345' -Destino $script:Falsa.destino

            $r.ok | Should -BeFalse
            "$($r.mensagem)" | Should -Match 'o DISM recusou o pacote'

            $ordem = @($global:TmxOrdem.ToArray())
            $ordem -contains 'dismount-discard' | Should -BeTrue
            $ordem -contains 'dismount-save'    | Should -BeFalse
            $ordem -contains 'oscdimg'          | Should -BeFalse

            Test-Path -LiteralPath $r.pastaTrabalho | Should -BeTrue
            @($r.passos | Where-Object { -not $_.ok }).Count | Should -Be 1
        }

        It 'sem oscdimg nem comeca e devolve a mensagem do ADK' {
            Mock -CommandName Get-TmxOscdimgPath -ModuleName TweakMaxing -MockWith { $null }

            $r = Invoke-TmxMicroWinBuild -IsoPath $script:Falsa.iso -EdicaoIndex 1 `
                -Usuario 'fantasy' -Senha 'Abc12345' -Destino $script:Falsa.destino

            $r.ok | Should -BeFalse
            "$($r.mensagem)" | Should -Match 'oscdimg\.exe nao encontrado'
            @($global:TmxOrdem.ToArray()).Count | Should -Be 0
        }

        It 'sem os 20 GB livres nem comeca' {
            Mock -CommandName Get-TmxFreeSpaceGB -ModuleName TweakMaxing -MockWith { 4.5 }

            $r = Invoke-TmxMicroWinBuild -IsoPath $script:Falsa.iso -EdicaoIndex 1 `
                -Usuario 'fantasy' -Senha 'Abc12345' -Destino $script:Falsa.destino

            $r.ok | Should -BeFalse
            "$($r.mensagem)" | Should -Match 'espaco livre insuficiente'
            @($global:TmxOrdem.ToArray()).Count | Should -Be 0
        }

        It 'nunca registra a senha no log durante o build' {
            $global:TmxLogs = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList))
            Mock -CommandName Write-TmxLog -ModuleName TweakMaxing -MockWith {
                $texto = "$Message"
                if ($Data) { foreach ($k in $Data.Keys) { $texto += " $k=$($Data[$k])" } }
                [void]$global:TmxLogs.Add($texto)
            }

            Invoke-TmxMicroWinBuild -IsoPath $script:Falsa.iso -EdicaoIndex 1 `
                -Usuario 'fantasy' -Senha 'SenhaSuperSecreta777' -Destino $script:Falsa.destino | Out-Null

            @($global:TmxLogs.ToArray()).Count | Should -BeGreaterThan 0
            (@($global:TmxLogs.ToArray()) -join ' ') | Should -Not -Match 'SenhaSuperSecreta777'
            (@($global:TmxLogs.ToArray()) -join ' ') | Should -Match 'fantasy'
            Remove-Variable -Name TmxLogs -Scope Global -ErrorAction SilentlyContinue
        }
    }

    # -----------------------------------------------------------------------
    Context 'Acoes da ponte' {

        BeforeAll { . (Join-Path $PSScriptRoot '_Helpers.ps1') }

        BeforeEach {
            New-TmxMicroWinTestSync -TestMode $true | Out-Null
            Register-TmxMicroWinActions
            $script:Falsa = New-TmxFakeIso
        }

        AfterEach {
            Remove-Item -LiteralPath $script:Falsa.pasta -Recurse -Force -ErrorAction SilentlyContinue
        }

        It 'microwin.apps devolve o catalogo de appx com id, nome e pacote' {
            $r = Invoke-TmxBridgeTest -Action 'microwin.apps'
            $r.ok | Should -BeTrue
            @($r.result.apps).Count | Should -BeGreaterOrEqual 30
            foreach ($a in @($r.result.apps)) {
                "$($a.id)"     | Should -Not -BeNullOrEmpty
                "$($a.nome)"   | Should -Not -BeNullOrEmpty
                "$($a.pacote)" | Should -Not -BeNullOrEmpty
            }
        }

        It 'microwin.build recusa uma ISO que nao existe antes de criar job' {
            $r = Invoke-TmxBridgeTest -Action 'microwin.build' -Payload @{
                iso = 'C:\nao\existe\x.iso'; edicao = 1; usuario = 'fantasy'; senha = 'x'
                destino = $script:Falsa.destino; simular = $true
            }
            $r.ok | Should -BeFalse
            "$($r.error.message)" | Should -Match 'ISO nao encontrada'
            $sync.activeJob | Should -BeNullOrEmpty
        }

        It 'microwin.build recusa um nome de usuario invalido antes de criar job' {
            $r = Invoke-TmxBridgeTest -Action 'microwin.build' -Payload @{
                iso = $script:Falsa.iso; edicao = 1; usuario = '1fantasy'; senha = 'x'
                destino = $script:Falsa.destino; simular = $true
            }
            $r.ok | Should -BeFalse
            "$($r.error.message)" | Should -Match 'nome de usuario invalido'
            $sync.activeJob | Should -BeNullOrEmpty
        }

        It 'microwin.build recusa um destino que nao existe antes de criar job' {
            $r = Invoke-TmxBridgeTest -Action 'microwin.build' -Payload @{
                iso = $script:Falsa.iso; edicao = 1; usuario = 'fantasy'; senha = 'x'
                destino = 'C:\pasta\que\nao\existe'; simular = $true
            }
            $r.ok | Should -BeFalse
            "$($r.error.message)" | Should -Match 'pasta de destino nao encontrada'
            $sync.activeJob | Should -BeNullOrEmpty
        }

        It 'microwin.build recusa senha vazia antes de criar job' {
            $r = Invoke-TmxBridgeTest -Action 'microwin.build' -Payload @{
                iso = $script:Falsa.iso; edicao = 1; usuario = 'fantasy'; senha = ''
                destino = $script:Falsa.destino; simular = $true
            }
            $r.ok | Should -BeFalse
            "$($r.error.message)" | Should -Match 'informe uma senha'
        }

        It 'no modo de teste microwin.build recusa a build de verdade' {
            $r = Invoke-TmxBridgeTest -Action 'microwin.build' -Payload @{
                iso = $script:Falsa.iso; edicao = 1; usuario = 'fantasy'; senha = 'Abc12345'
                destino = $script:Falsa.destino
            }
            $r.ok | Should -BeFalse
            "$($r.error.message)" | Should -Match 'so roda simulado'
            $sync.activeJob | Should -BeNullOrEmpty
        }

        It 'no modo de teste com simular a build escreve so o arquivo de simulacao' {
            $r = Invoke-TmxBridgeTest -Action 'microwin.build' -Payload @{
                iso = $script:Falsa.iso; edicao = 1; usuario = 'fantasy'; senha = 'Abc12345'
                destino = $script:Falsa.destino; simular = $true
                appx = @('Microsoft.BingWeather')
            }
            $r.ok | Should -BeTrue
            "$($r.result.jobId)" | Should -Not -BeNullOrEmpty

            $done = Wait-TmxJobDoneById -JobId "$($r.result.jobId)" -TimeoutSeconds 60
            $done | Should -Not -BeNullOrEmpty
            $done.ok | Should -BeTrue
            $done.result.ok       | Should -BeTrue
            $done.result.simulado | Should -BeTrue

            $arquivo = Join-Path $script:Falsa.destino 'microwin-simulado.txt'
            Test-Path -LiteralPath $arquivo | Should -BeTrue
            @(Get-ChildItem -LiteralPath $script:Falsa.destino -Filter '*.iso' -File).Count | Should -Be 0
        }
    }
}
