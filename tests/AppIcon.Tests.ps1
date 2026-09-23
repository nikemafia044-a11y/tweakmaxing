# tests/AppIcon.Tests.ps1
# Get-TmxAppIcon (cache -> exe -> site) e a acao de ponte apps.icons.
#
# Nada aqui usa rede de verdade: Invoke-TmxIconDownload/Get-TmxUninstallEntries/
# Get-TmxExeIconBitmap sao mockados. O corte de 512 KB e testado direto em
# Read-TmxLimitedStream (a parte pura de Get-TmxHttpDownloadBytes: le um
# Stream ate MaxBytes) contra um MemoryStream comum - nao precisa de rede
# nem de servidor local para provar a logica de corte.

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

    Context 'Invoke-TmxIconDownload: so https' {
        It 'recusa URL http (nao-https) sem tentar baixar' {
            Mock -CommandName Get-TmxHttpDownloadBytes -ModuleName TweakMaxing -MockWith { 'nao deveria chegar aqui' }
            $r = Invoke-TmxIconDownload -Url 'http://example.org/icone.png'
            $r | Should -BeNullOrEmpty
            Should -Invoke -CommandName Get-TmxHttpDownloadBytes -ModuleName TweakMaxing -Times 0
        }

        It 'Test-TmxIconUrlHttps distingue http de https' {
            Test-TmxIconUrlHttps -Url 'https://example.org' | Should -BeTrue
            Test-TmxIconUrlHttps -Url 'http://example.org'  | Should -BeFalse
            Test-TmxIconUrlHttps -Url 'ftp://example.org'   | Should -BeFalse
            Test-TmxIconUrlHttps -Url ''                     | Should -BeFalse
        }
    }

    Context 'Read-TmxLimitedStream: corte de 512 KB (a parte pura de Get-TmxHttpDownloadBytes)' {

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
}
