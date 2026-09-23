# tests/AppIcon.Tests.ps1
# Get-TmxAppIcon (cache -> exe -> site) e a acao de ponte apps.icons.
#
# Nada aqui usa rede de verdade: Invoke-TmxIconDownload/Get-TmxUninstallEntries/
# Get-TmxExeIconBitmap/Invoke-TmxHttpRequestOnce sao mockados. O corte de
# 512 KB e testado direto em Read-TmxLimitedStream (a parte pura de
# Invoke-TmxHttpRequestOnce: le um Stream ate MaxBytes) contra um MemoryStream
# comum - nao precisa de rede nem de servidor local para provar a logica de
# corte. O redirect manual e testado mockando Invoke-TmxHttpRequestOnce
# direto (devolve statusCode/location controlados). O unico teste que roda
# um job de VERDADE (Start-TmxJob) e o de ponta a ponta no fim do arquivo.

. (Join-Path $PSScriptRoot '_Helpers.ps1')

function script:New-TmxTestPngBytes {
    <#
    .SYNOPSIS
        Bitmap NxN de verdade, codificado como PNG, em memoria (fixture para
        os testes que precisam decodificar/redimensionar uma imagem real).
    #>
    param([int] $Tamanho = 16)
    Add-Type -AssemblyName System.Drawing
    $bmp = New-Object System.Drawing.Bitmap($Tamanho, $Tamanho)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try { $g.Clear([System.Drawing.Color]::Red) } finally { $g.Dispose() }
    $ms = New-Object System.IO.MemoryStream
    try {
        $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
        $ms.ToArray()
    } finally {
        $ms.Dispose()
        $bmp.Dispose()
    }
}

function script:New-TmxTestBitmap {
    param([int] $Tamanho = 16)
    Add-Type -AssemblyName System.Drawing
    $bmp = New-Object System.Drawing.Bitmap($Tamanho, $Tamanho)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try { $g.Clear([System.Drawing.Color]::Blue) } finally { $g.Dispose() }
    $bmp
}

function script:New-TmxTestBigPngBytes {
    <#
    .SYNOPSIS
        PNG de verdade com lado grande (ex.: 2000x2000) mas ARQUIVO pequeno
        (uma cor solida comprime bem) - fixture pra provar que a guarda de
        "decompression bomb" olha a DIMENSAO decodificada, nao o tamanho do
        arquivo (que passaria facil no limite de 512 KB).
    #>
    param([int] $Lado = 2000)
    Add-Type -AssemblyName System.Drawing
    $bmp = New-Object System.Drawing.Bitmap($Lado, $Lado)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try { $g.Clear([System.Drawing.Color]::Green) } finally { $g.Dispose() }
    $ms = New-Object System.IO.MemoryStream
    try {
        $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
        $ms.ToArray()
    } finally {
        $ms.Dispose()
        $bmp.Dispose()
    }
}

Describe 'Get-TmxAppIcon' -Tag 'AppIcon' {

    BeforeAll {
        . (Join-Path $PSScriptRoot '_Helpers.ps1')
        Import-TmxTestModule
        New-TmxTestHome | Out-Null
    }

    AfterAll {
        Remove-TmxTestHome
    }

    Context 'Get-TmxAppIconCacheDir' {
        It 'cria <home>\icons se nao existir e devolve o caminho' {
            $dir = Get-TmxAppIconCacheDir
            $dir | Should -Be (Join-Path $env:TWEAKMAXING_HOME 'icons')
            Test-Path -LiteralPath $dir | Should -BeTrue
        }
    }

    Context 'Ordem cache -> exe -> site' {

        It 'usa o cache em disco quando <id>.png ja existe, sem consultar exe/site' {
            Mock -CommandName Get-TmxUninstallEntries -ModuleName TweakMaxing -MockWith { , @() }
            Mock -CommandName Invoke-TmxIconDownload   -ModuleName TweakMaxing -MockWith { $null }

            $dir = Get-TmxAppIconCacheDir
            $bytesFixture = New-TmxTestPngBytes -Tamanho 64
            [System.IO.File]::WriteAllBytes((Join-Path $dir 'appcache.png'), $bytesFixture)

            $app = [pscustomobject]@{ id = 'appcache'; nome = 'App Cache'; link = 'https://example.org' }
            $r = Get-TmxAppIcon -App $app

            $r | Should -Not -BeNullOrEmpty
            $r.origem | Should -Be 'cache'
            $r.src | Should -Match '^data:image/png;base64,'

            Should -Invoke -CommandName Get-TmxUninstallEntries -ModuleName TweakMaxing -Times 0
            Should -Invoke -CommandName Invoke-TmxIconDownload   -ModuleName TweakMaxing -Times 0
        }

        It 'usa o icone do exe quando ha match no registro de desinstalar, sem consultar o site' {
            $exeFalso = Join-Path ([System.IO.Path]::GetTempPath()) 'tmx-fake-app.exe'
            if (-not (Test-Path -LiteralPath $exeFalso)) { New-Item -ItemType File -Path $exeFalso -Force | Out-Null }

            Mock -CommandName Get-TmxUninstallEntries -ModuleName TweakMaxing -MockWith {
                , @([pscustomobject]@{ DisplayName = 'App Exe'; DisplayIcon = "`"$exeFalso`",0" })
            }
            Mock -CommandName Get-TmxExeIconBitmap -ModuleName TweakMaxing -MockWith { New-TmxTestBitmap -Tamanho 32 }
            Mock -CommandName Invoke-TmxIconDownload -ModuleName TweakMaxing -MockWith { $null }

            $app = [pscustomobject]@{ id = 'appexe'; nome = 'App Exe'; link = 'https://example.org' }
            $r = Get-TmxAppIcon -App $app

            $r | Should -Not -BeNullOrEmpty
            $r.origem | Should -Be 'exe'
            Should -Invoke -CommandName Invoke-TmxIconDownload -ModuleName TweakMaxing -Times 0

            # E gravou no cache: uma segunda chamada acha o arquivo sem tocar o exe.
            Test-Path -LiteralPath (Join-Path (Get-TmxAppIconCacheDir) 'appexe.png') | Should -BeTrue
        }

        It 'cai para o site quando nao ha cache nem match de exe' {
            Mock -CommandName Get-TmxUninstallEntries -ModuleName TweakMaxing -MockWith { , @() }
            Mock -CommandName Invoke-TmxIconDownload -ModuleName TweakMaxing -MockWith {
                param($Url)
                New-TmxTestPngBytes -Tamanho 20
            }

            $app = [pscustomobject]@{ id = 'appsite'; nome = 'App Site'; link = 'https://example.org'; icon = $null }
            $r = Get-TmxAppIcon -App $app

            $r | Should -Not -BeNullOrEmpty
            $r.origem | Should -Be 'site'
        }
    }

    Context 'DisplayName: casamento exato ou "nome + espaco"' {

        It '"Git" nao casa com "GitHub Desktop" (fica sem icone de exe; offline entao sem site tambem)' {
            Mock -CommandName Get-TmxUninstallEntries -ModuleName TweakMaxing -MockWith {
                , @([pscustomobject]@{ DisplayName = 'GitHub Desktop'; DisplayIcon = 'C:\naoexiste\gh.exe' })
            }
            Mock -CommandName Get-TmxExeIconBitmap -ModuleName TweakMaxing -MockWith { New-TmxTestBitmap }
            Mock -CommandName Invoke-TmxIconDownload -ModuleName TweakMaxing -MockWith { $null }

            $app = [pscustomobject]@{ id = 'git'; nome = 'Git'; link = 'https://git-scm.com' }
            $r = Get-TmxAppIcon -App $app -Offline

            $r | Should -BeNullOrEmpty
            Should -Invoke -CommandName Get-TmxExeIconBitmap -ModuleName TweakMaxing -Times 0
        }

        It '"Git" casa com "Git" (igual) e com "Git 2.40" (prefixo + espaco)' {
            foreach ($displayName in 'Git', 'Git 2.40') {
                $exeFalso = Join-Path ([System.IO.Path]::GetTempPath()) ('tmx-git-{0}.exe' -f ([guid]::NewGuid().ToString('N')))
                New-Item -ItemType File -Path $exeFalso -Force | Out-Null

                Mock -CommandName Get-TmxUninstallEntries -ModuleName TweakMaxing -MockWith {
                    , @([pscustomobject]@{ DisplayName = $displayName; DisplayIcon = $exeFalso })
                }
                Mock -CommandName Get-TmxExeIconBitmap -ModuleName TweakMaxing -MockWith { New-TmxTestBitmap }

                $app = [pscustomobject]@{ id = ('git-{0}' -f ([guid]::NewGuid().ToString('N'))); nome = 'Git'; link = 'https://git-scm.com' }
                $r = Get-TmxAppIcon -App $app -Offline

                $r | Should -Not -BeNullOrEmpty -Because "DisplayName '$displayName' deveria casar com 'Git'"
                $r.origem | Should -Be 'exe'
            }
        }
    }

    Context 'Offline / testMode: nunca chama a rede (verificacao SINCRONA)' {

        BeforeEach {
            Mock -CommandName Get-TmxUninstallEntries -ModuleName TweakMaxing -MockWith { , @() }
            Mock -CommandName Invoke-TmxIconDownload   -ModuleName TweakMaxing -MockWith { New-TmxTestPngBytes }
        }

        It '-Offline nunca invoca Invoke-TmxIconDownload' {
            $app = [pscustomobject]@{ id = 'offline1'; nome = 'Offline Um'; link = 'https://example.org' }
            Get-TmxAppIcon -App $app -Offline | Out-Null
            Should -Invoke -CommandName Invoke-TmxIconDownload -ModuleName TweakMaxing -Times 0
        }

        It '$sync.testMode = $true tambem nunca invoca Invoke-TmxIconDownload (sem -Offline)' {
            $global:sync = [Hashtable]::Synchronized(@{ testMode = $true })
            try {
                $app = [pscustomobject]@{ id = 'offline2'; nome = 'Offline Dois'; link = 'https://example.org' }
                Get-TmxAppIcon -App $app | Out-Null
                Should -Invoke -CommandName Invoke-TmxIconDownload -ModuleName TweakMaxing -Times 0
            } finally {
                Remove-Variable -Name sync -Scope Global -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'Cache gravado e 64x64 PNG de verdade' {
        It 'grava <id>.png com 64x64 pixels apos resolver pelo site' {
            Mock -CommandName Get-TmxUninstallEntries -ModuleName TweakMaxing -MockWith { , @() }
            Mock -CommandName Invoke-TmxIconDownload -ModuleName TweakMaxing -MockWith { New-TmxTestPngBytes -Tamanho 20 }

            $app = [pscustomobject]@{ id = 'appresize'; nome = 'App Resize'; link = 'https://example.org'; icon = $null }
            $r = Get-TmxAppIcon -App $app
            $r | Should -Not -BeNullOrEmpty

            $arquivo = Join-Path (Get-TmxAppIconCacheDir) 'appresize.png'
            Test-Path -LiteralPath $arquivo | Should -BeTrue

            Add-Type -AssemblyName System.Drawing
            $img = [System.Drawing.Image]::FromFile($arquivo)
            try {
                $img.Width  | Should -Be 64
                $img.Height | Should -Be 64
                $img.RawFormat.Guid | Should -Be ([System.Drawing.Imaging.ImageFormat]::Png.Guid)
            } finally {
                $img.Dispose()
            }
        }
    }

    Context 'Sanitizacao de id (Test-TmxAppIconIdSafe)' {

        It '<Id> e seguro' -ForEach @(
            @{ Id = 'firefox' }
            @{ Id = '7zip' }
            @{ Id = 'meu-app_2.0' }
        ) {
            Test-TmxAppIconIdSafe -Id $Id | Should -BeTrue
        }

        It '<Id> NAO e seguro' -ForEach @(
            @{ Id = '' }
            @{ Id = $null }
            @{ Id = '../../etc/passwd' }
            @{ Id = '..\..\windows' }
            @{ Id = 'a..b' }
            @{ Id = 'com espaco' }
            @{ Id = 'com/barra' }
            @{ Id = 'com\barra' }
        ) {
            Test-TmxAppIconIdSafe -Id $Id | Should -BeFalse
        }

        It 'Get-TmxAppIcon devolve $null pra um id com atravessamento de pasta, sem tocar o registro' {
            Mock -CommandName Get-TmxUninstallEntries -ModuleName TweakMaxing -MockWith { throw 'nao deveria ser chamado' }
            $app = [pscustomobject]@{ id = '../../fora'; nome = 'Fora'; link = 'https://example.org' }
            $r = Get-TmxAppIcon -App $app -Offline
            $r | Should -BeNullOrEmpty
            Should -Invoke -CommandName Get-TmxUninstallEntries -ModuleName TweakMaxing -Times 0
        }
    }

    Context 'Guarda de decompression bomb (dimensao decodificada, nao tamanho do arquivo)' {

        It 'recusa uma imagem 2000x2000 mesmo vindo de um arquivo pequeno' {
            Mock -CommandName Get-TmxUninstallEntries -ModuleName TweakMaxing -MockWith { , @() }
            Mock -CommandName Invoke-TmxIconDownload -ModuleName TweakMaxing -MockWith {
                $bytes = New-TmxTestBigPngBytes -Lado 2000
                # A propria fixture prova a premissa do teste: pequena no
                # disco, grande decodificada.
                $bytes.Length | Should -BeLessThan 524288
                $bytes
            }

            $app = [pscustomobject]@{ id = 'appbomba'; nome = 'App Bomba'; link = 'https://example.org'; icon = $null }
            $r = Get-TmxAppIcon -App $app

            $r | Should -BeNullOrEmpty
            Test-Path -LiteralPath (Join-Path (Get-TmxAppIconCacheDir) 'appbomba.png') | Should -BeFalse
        }

        It 'Test-TmxIconImageDimensionsSafe recusa 1024x1025 e aceita 1024x1024' {
            Add-Type -AssemblyName System.Drawing
            $grande = New-Object System.Drawing.Bitmap(1024, 1025)
            try { Test-TmxIconImageDimensionsSafe -Imagem $grande | Should -BeFalse } finally { $grande.Dispose() }

            $limite = New-Object System.Drawing.Bitmap(1024, 1024)
            try { Test-TmxIconImageDimensionsSafe -Imagem $limite | Should -BeTrue } finally { $limite.Dispose() }
        }
    }

    Context 'Cache negativo: sem icone de verdade -> pula rede por 7 dias' {

        It 'grava <id>.none quando exe e site foram tentados de verdade e nenhum achou nada' {
            Mock -CommandName Get-TmxUninstallEntries -ModuleName TweakMaxing -MockWith { , @() }
            Mock -CommandName Invoke-TmxIconDownload -ModuleName TweakMaxing -MockWith { $null }

            $app = [pscustomobject]@{ id = 'appneg1'; nome = 'App Neg 1'; link = 'https://example.org'; icon = $null }
            $r = Get-TmxAppIcon -App $app
            $r | Should -BeNullOrEmpty

            Test-Path -LiteralPath (Join-Path (Get-TmxAppIconCacheDir) 'appneg1.none') | Should -BeTrue
        }

        It 'com o marcador fresco (< 7 dias), pula o site sem chamar Invoke-TmxIconDownload' {
            Mock -CommandName Get-TmxUninstallEntries -ModuleName TweakMaxing -MockWith { , @() }
            Mock -CommandName Invoke-TmxIconDownload -ModuleName TweakMaxing -MockWith { New-TmxTestPngBytes }

            Set-TmxAppIconNegativeCache -Id 'appneg2'

            $app = [pscustomobject]@{ id = 'appneg2'; nome = 'App Neg 2'; link = 'https://example.org'; icon = $null }
            $r = Get-TmxAppIcon -App $app

            $r | Should -BeNullOrEmpty
            Should -Invoke -CommandName Invoke-TmxIconDownload -ModuleName TweakMaxing -Times 0
        }

        It 'com o marcador velho (> 7 dias), tenta o site de novo' {
            Mock -CommandName Get-TmxUninstallEntries -ModuleName TweakMaxing -MockWith { , @() }
            Mock -CommandName Invoke-TmxIconDownload -ModuleName TweakMaxing -MockWith { New-TmxTestPngBytes -Tamanho 20 }

            Set-TmxAppIconNegativeCache -Id 'appneg3'
            $marcador = Get-TmxAppIconNegativeCachePath -Id 'appneg3'
            (Get-Item -LiteralPath $marcador).LastWriteTime = (Get-Date).AddDays(-8)

            $app = [pscustomobject]@{ id = 'appneg3'; nome = 'App Neg 3'; link = 'https://example.org'; icon = $null }
            $r = Get-TmxAppIcon -App $app

            $r | Should -Not -BeNullOrEmpty
            $r.origem | Should -Be 'site'
            Should -Invoke -CommandName Invoke-TmxIconDownload -ModuleName TweakMaxing -Times 1
        }

        It 'Test-TmxAppIconNegativeCacheFresh respeita o limite de dias' {
            Set-TmxAppIconNegativeCache -Id 'appneg4'
            Test-TmxAppIconNegativeCacheFresh -Id 'appneg4' -MaxAgeDays 7 | Should -BeTrue

            $marcador = Get-TmxAppIconNegativeCachePath -Id 'appneg4'
            (Get-Item -LiteralPath $marcador).LastWriteTime = (Get-Date).AddDays(-8)
            Test-TmxAppIconNegativeCacheFresh -Id 'appneg4' -MaxAgeDays 7 | Should -BeFalse
        }

        It 'nao grava cache negativo quando a tentativa foi pulada por -Offline' {
            Mock -CommandName Get-TmxUninstallEntries -ModuleName TweakMaxing -MockWith { , @() }
            Mock -CommandName Invoke-TmxIconDownload -ModuleName TweakMaxing -MockWith { $null }

            $app = [pscustomobject]@{ id = 'appneg5'; nome = 'App Neg 5'; link = 'https://example.org'; icon = $null }
            Get-TmxAppIcon -App $app -Offline | Out-Null

            Test-Path -LiteralPath (Join-Path (Get-TmxAppIconCacheDir) 'appneg5.none') | Should -BeFalse
        }
    }

    Context 'Falha isolada: nunca lanca' {
        It 'devolve $null (nao lanca) quando tudo falha' {
            Mock -CommandName Get-TmxUninstallEntries -ModuleName TweakMaxing -MockWith { throw 'estourou' }
            $app = [pscustomobject]@{ id = 'appfalha'; nome = 'App Falha'; link = 'https://example.org' }
            { $r = Get-TmxAppIcon -App $app -Offline } | Should -Not -Throw
            (Get-TmxAppIcon -App $app -Offline) | Should -BeNullOrEmpty
        }
    }
}

Describe 'Wrappers de icone (Test-TmxIconUrlHttps / Get-TmxHttpDownloadBytes)' -Tag 'AppIcon' {

    BeforeAll {
        . (Join-Path $PSScriptRoot '_Helpers.ps1')
        Import-TmxTestModule
    }

    Context 'Invoke-TmxIconDownload: so https, sem IP privado' {
        It 'recusa URL http (nao-https) sem tentar baixar' {
            Mock -CommandName Invoke-TmxHttpRequestOnce -ModuleName TweakMaxing -MockWith { 'nao deveria chegar aqui' }
            $r = Invoke-TmxIconDownload -Url 'http://example.org/icone.png'
            $r | Should -BeNullOrEmpty
            Should -Invoke -CommandName Invoke-TmxHttpRequestOnce -ModuleName TweakMaxing -Times 0
        }

        It 'Test-TmxIconUrlHttps distingue http de https' {
            Test-TmxIconUrlHttps -Url 'https://example.org' | Should -BeTrue
            Test-TmxIconUrlHttps -Url 'http://example.org'  | Should -BeFalse
            Test-TmxIconUrlHttps -Url 'ftp://example.org'   | Should -BeFalse
            Test-TmxIconUrlHttps -Url ''                     | Should -BeFalse
        }

        It 'Test-TmxIconUrlPrivateHost recusa IP literal privado/loopback' -ForEach @(
            @{ Url = 'https://127.0.0.1/x' }
            @{ Url = 'https://10.0.0.5/x' }
            @{ Url = 'https://172.16.0.1/x' }
            @{ Url = 'https://172.31.255.255/x' }
            @{ Url = 'https://192.168.1.1/x' }
            @{ Url = 'https://169.254.1.1/x' }
        ) {
            Test-TmxIconUrlPrivateHost -Url $Url | Should -BeTrue
        }

        It 'Test-TmxIconUrlPrivateHost deixa passar dominio e IP publico' -ForEach @(
            @{ Url = 'https://example.org/x' }
            @{ Url = 'https://8.8.8.8/x' }
            @{ Url = 'https://172.15.0.1/x' }
            @{ Url = 'https://172.32.0.1/x' }
        ) {
            Test-TmxIconUrlPrivateHost -Url $Url | Should -BeFalse
        }

        It 'Invoke-TmxIconDownload recusa quando a URL aponta pra IP privado' {
            Mock -CommandName Invoke-TmxHttpRequestOnce -ModuleName TweakMaxing -MockWith { throw 'nao deveria chegar aqui' }
            $r = Invoke-TmxIconDownload -Url 'https://192.168.0.1/icone.png'
            $r | Should -BeNullOrEmpty
            Should -Invoke -CommandName Invoke-TmxHttpRequestOnce -ModuleName TweakMaxing -Times 0
        }
    }

    Context 'Invoke-TmxIconDownload: redirect manual (Invoke-TmxHttpRequestOnce mockado)' {

        It 'segue um redirect https->https ate 200' {
            Mock -CommandName Invoke-TmxHttpRequestOnce -ModuleName TweakMaxing -MockWith {
                param($Url)
                if ($Url -eq 'https://example.org/a') {
                    [pscustomobject]@{ statusCode = 302; location = 'https://example.org/b'; bytes = $null }
                } else {
                    [pscustomobject]@{ statusCode = 200; location = $null; bytes = [byte[]]@(1,2,3) }
                }
            }
            $r = Invoke-TmxIconDownload -Url 'https://example.org/a'
            ($r -join ',') | Should -Be '1,2,3'
            Should -Invoke -CommandName Invoke-TmxHttpRequestOnce -ModuleName TweakMaxing -Times 2
        }

        It 'recusa quando o redirect aponta de https para http' {
            Mock -CommandName Invoke-TmxHttpRequestOnce -ModuleName TweakMaxing -MockWith {
                [pscustomobject]@{ statusCode = 302; location = 'http://evil.example/roubado'; bytes = $null }
            }
            $r = Invoke-TmxIconDownload -Url 'https://example.org/a'
            $r | Should -BeNullOrEmpty
            # Um so hop: a segunda tentativa (que seria pro http) nunca acontece.
            Should -Invoke -CommandName Invoke-TmxHttpRequestOnce -ModuleName TweakMaxing -Times 1
        }

        It 'recusa apos mais de 3 saltos de redirect' {
            $script:chamadas = 0
            Mock -CommandName Invoke-TmxHttpRequestOnce -ModuleName TweakMaxing -MockWith {
                $script:chamadas++
                [pscustomobject]@{ statusCode = 302; location = "https://example.org/salto$script:chamadas"; bytes = $null }
            }
            $r = Invoke-TmxIconDownload -Url 'https://example.org/a'
            $r | Should -BeNullOrEmpty
            # 1 inicial + 3 saltos permitidos = 4 tentativas; a 5a nunca acontece.
            $script:chamadas | Should -Be 4
        }
    }

    Context 'Read-TmxLimitedStream: corte de 512 KB e de tempo total (a parte pura de Invoke-TmxHttpRequestOnce)' {

        It 'devolve $null quando o cronometro ja passou do TimeoutMs, mesmo com Content-Length ok' {
            $fluxoLento = [pscustomobject]@{ }
            $fluxoLento | Add-Member -MemberType ScriptMethod -Name Read -Value {
                param($buf, $offset, $count)
                Start-Sleep -Milliseconds 30
                1
            } -Force

            $cronometro = [System.Diagnostics.Stopwatch]::StartNew()
            $r = Read-TmxLimitedStream -Stream $fluxoLento -MaxBytes 524288 -ContentLength -1 -Stopwatch $cronometro -TimeoutMs 20
            $r | Should -BeNullOrEmpty
        }

        It 'devolve $null so de olhar o Content-Length declarado, sem ler o stream' {
            $fluxoFalso = [pscustomobject]@{ LeituraChamada = $false }
            $fluxoFalso | Add-Member -MemberType ScriptMethod -Name Read -Value {
                param($buf, $offset, $count)
                $this.LeituraChamada = $true
                0
            } -Force

            $r = Read-TmxLimitedStream -Stream $fluxoFalso -MaxBytes 524288 -ContentLength 600000
            $r | Should -BeNullOrEmpty
            $fluxoFalso.LeituraChamada | Should -BeFalse -Because 'o Content-Length ja bastou para recusar'
        }

        It 'devolve $null quando o corpo de verdade passa do limite (Content-Length desconhecido)' {
            $grande = New-Object byte[] (524288 + 10)
            $fluxo = New-Object System.IO.MemoryStream(, $grande)
            try {
                $r = Read-TmxLimitedStream -Stream $fluxo -MaxBytes 524288 -ContentLength -1
                $r | Should -BeNullOrEmpty
            } finally {
                $fluxo.Dispose()
            }
        }

        It 'devolve os bytes certos quando o corpo esta dentro do limite' {
            $corpo = [System.Text.Encoding]::ASCII.GetBytes('conteudo pequeno de teste')
            $fluxo = New-Object System.IO.MemoryStream(, $corpo)
            try {
                $r = Read-TmxLimitedStream -Stream $fluxo -MaxBytes 524288 -ContentLength $corpo.Length
                $r | Should -Not -BeNullOrEmpty
                [System.Text.Encoding]::ASCII.GetString($r) | Should -Be 'conteudo pequeno de teste'
            } finally {
                $fluxo.Dispose()
            }
        }
    }
}

Describe 'Ponte: apps.icons' -Tag 'AppIcon' {

    BeforeAll {
        . (Join-Path $PSScriptRoot '_Helpers.ps1')
        Import-TmxTestModule
        New-TmxTestHome | Out-Null

        function New-TmxIconsTestSync {
            $doc = [pscustomobject]@{
                aplicativos = @(
                    [pscustomobject]@{ id = 'iconapp1'; nome = 'Icon App 1'; descricao = 'd'; categoria = 'Utilitarios'; winget = 'V.I1'; choco = ''; link = 'https://example.org'; icon = $null; foss = $true }
                    [pscustomobject]@{ id = 'iconapp2'; nome = 'Icon App 2'; descricao = 'd'; categoria = 'Utilitarios'; winget = 'V.I2'; choco = ''; link = 'https://example.org'; icon = $null; foss = $true }
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
    }

    AfterAll {
        Remove-TmxTestHome
        Remove-Variable -Name sync -Scope Global -ErrorAction SilentlyContinue
    }

    BeforeEach {
        New-TmxIconsTestSync | Out-Null
        Register-TmxInstallActions
    }

    It 'esta registrada como assincrona' {
        (Get-TmxBridgeAction -Name 'apps.icons').async | Should -BeTrue
    }

    It 'recusa mais de 40 ids' {
        $muitos = 1..41 | ForEach-Object { "id$_" }
        $entry = Get-TmxBridgeAction -Name 'apps.icons'
        { & $entry.handler ([pscustomobject]@{ ids = $muitos }) } | Should -Throw '*40*'
    }

    It 'aceita exatamente 40 ids sem lancar por causa do limite' {
        Mock -CommandName Get-TmxAppIcon -ModuleName TweakMaxing -MockWith { $null }
        $quarenta = 1..40 | ForEach-Object { "id$_" }
        $entry = Get-TmxBridgeAction -Name 'apps.icons'
        { & $entry.handler ([pscustomobject]@{ ids = $quarenta }) } | Should -Not -Throw
    }

    It 'ignora ids desconhecidos e devolve so os icones achados' {
        Mock -CommandName Get-TmxAppIcon -ModuleName TweakMaxing -MockWith {
            param($App)
            [pscustomobject]@{ id = $App.id; src = 'data:image/png;base64,QQ=='; origem = 'site' }
        }
        $entry = Get-TmxBridgeAction -Name 'apps.icons'
        $r = & $entry.handler ([pscustomobject]@{ ids = @('iconapp1', 'naoexiste') })

        $r.icons.Keys | Should -Contain 'iconapp1'
        $r.icons.Keys | Should -Not -Contain 'naoexiste'
        $r.icons['iconapp1'].origem | Should -Be 'site'
    }

    It 'nao inclui na resposta um id sem icone (Get-TmxAppIcon devolveu $null)' {
        Mock -CommandName Get-TmxAppIcon -ModuleName TweakMaxing -MockWith { $null }
        $entry = Get-TmxBridgeAction -Name 'apps.icons'
        $r = & $entry.handler ([pscustomobject]@{ ids = @('iconapp1', 'iconapp2') })
        $r.icons.Keys.Count | Should -Be 0
    }

    Context 'Payload ausente/sem ids: lista vazia, nao erro' {

        It 'payload $null devolve icons vazio, sem lancar' {
            Mock -CommandName Get-TmxAppIcon -ModuleName TweakMaxing -MockWith { throw 'nao deveria ser chamado' }
            $entry = Get-TmxBridgeAction -Name 'apps.icons'
            $r = $null
            { $r = & $entry.handler $null } | Should -Not -Throw
            $r.icons.Keys.Count | Should -Be 0
        }

        It 'payload sem a chave ids devolve icons vazio, sem lancar' {
            Mock -CommandName Get-TmxAppIcon -ModuleName TweakMaxing -MockWith { throw 'nao deveria ser chamado' }
            $entry = Get-TmxBridgeAction -Name 'apps.icons'
            $r = & $entry.handler ([pscustomobject]@{ outraCoisa = 1 })
            $r.icons.Keys.Count | Should -Be 0
        }

        It 'ids vazio ([]) devolve icons vazio' {
            $entry = Get-TmxBridgeAction -Name 'apps.icons'
            $r = & $entry.handler ([pscustomobject]@{ ids = @() })
            $r.icons.Keys.Count | Should -Be 0
        }

        It 'ainda recusa um id que nao e texto (numero, por exemplo)' {
            $entry = Get-TmxBridgeAction -Name 'apps.icons'
            { & $entry.handler ([pscustomobject]@{ ids = @('iconapp1', 42) }) } | Should -Throw '*texto*'
        }
    }

    Context 'apps.icons de ponta a ponta via Start-TmxJob (job assincrono de verdade)' {

        AfterEach {
            Wait-TmxRemainingWork -TimeoutSeconds 20 | Out-Null
            Close-TmxRunspacePool
        }

        It 'devolve jobId na hora e job.done chega com result.icons (testMode: sem rede)' {
            $r = Invoke-TmxBridgeRequest -Json '{"id":"e2e1","action":"apps.icons","payload":{"ids":["iconapp1","iconapp2"]}}' | ConvertFrom-Json
            $r.ok | Should -BeTrue
            $r.result.jobId | Should -Not -BeNullOrEmpty

            $limite = (Get-Date).AddSeconds(20)
            $pronto = $null
            while ((Get-Date) -lt $limite) {
                $achado = @(@($sync.uiEvents.ToArray()) | Where-Object { $_.event -eq 'job.done' -and $_.payload.jobId -eq $r.result.jobId })
                if ($achado.Count -gt 0) { $pronto = $achado[0]; break }
                Start-Sleep -Milliseconds 200
            }

            $pronto | Should -Not -BeNullOrEmpty -Because 'job.done deveria chegar dentro do tempo limite'
            $pronto.payload.ok | Should -BeTrue
            # payload.result e o hashtable {icons=...} DIRETO (sem passar por
            # JSON - $sync.uiEvents guarda o objeto real) - .Contains() e o
            # jeito certo de checar a chave, nao .PSObject.Properties (que
            # nesse caso devolveria os MEMBROS DO TIPO Hashtable, nao 'icons').
            $pronto.payload.result.Contains('icons') | Should -BeTrue
            $pronto.payload.result.icons | Should -Not -BeNull
        }
    }
}

Describe 'Invoke-TmxAppIconBatch' -Tag 'AppIcon' {

    BeforeAll {
        . (Join-Path $PSScriptRoot '_Helpers.ps1')
        Import-TmxTestModule
        New-TmxTestHome | Out-Null
    }

    AfterAll {
        Remove-TmxTestHome
    }

    It 'resolve todo mundo quando cabe no orcamento' {
        Mock -CommandName Get-TmxAppIcon -ModuleName TweakMaxing -MockWith {
            param($App)
            [pscustomobject]@{ id = $App.id; src = 'data:image/png;base64,QQ=='; origem = 'site' }
        }
        $apps = 1..5 | ForEach-Object { [pscustomobject]@{ id = "batch$_"; nome = "Batch $_" } }
        $r = Invoke-TmxAppIconBatch -Apps $apps -BudgetMs 8000
        $r.Keys.Count | Should -Be 5
    }

    It 'para de processar assim que o orcamento estoura, sem chamar Get-TmxAppIcon pros ids restantes' {
        Mock -CommandName Get-TmxAppIcon -ModuleName TweakMaxing -MockWith {
            param($App)
            Start-Sleep -Milliseconds 60
            [pscustomobject]@{ id = $App.id; src = 'data:image/png;base64,QQ=='; origem = 'site' }
        }
        $apps = 1..10 | ForEach-Object { [pscustomobject]@{ id = "orcamento$_"; nome = "Orcamento $_" } }

        $r = Invoke-TmxAppIconBatch -Apps $apps -BudgetMs 150

        # Com 60ms por app e orcamento de 150ms, no maximo uns 3 apps rodam
        # (o cronometro e checado ANTES de cada chamada) - com certeza nao
        # os 10.
        $r.Keys.Count | Should -BeLessThan 10
        Should -Invoke -CommandName Get-TmxAppIcon -ModuleName TweakMaxing -Times $r.Keys.Count
    }

    It 'lista vazia devolve icons vazio sem chamar Get-TmxAppIcon' {
        Mock -CommandName Get-TmxAppIcon -ModuleName TweakMaxing -MockWith { throw 'nao deveria ser chamado' }
        $r = Invoke-TmxAppIconBatch -Apps @() -BudgetMs 8000
        $r.Keys.Count | Should -Be 0
    }
}
