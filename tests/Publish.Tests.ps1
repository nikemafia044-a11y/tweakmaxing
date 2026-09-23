# tests/Publish.Tests.ps1
# tools/Publish-Release.ps1: fluxo completo de publicacao (REPO/VERSION,
# Compile.ps1, SHA256SUMS.txt, tag, plano de push/gh release create) testado
# com -DryRun/-NoPush num clone LOCAL do proprio repositorio (git clone
# --quiet: a origem e uma pasta no disco, nao uma URL - nenhuma rede
# envolvida). O clone aponta 'origin' para essa pasta local, entao TODO
# teste aqui usa -DryRun (ou falha antes de chegar no push): um push de
# verdade aqui empurraria para dentro do proprio repositorio de
# desenvolvimento.
#
# Pulado inteiro, com aviso, se 'git' nao estiver disponivel na maquina.

. (Join-Path $PSScriptRoot '_Helpers.ps1')

$script:TmxTemGit = [bool](Get-Command git -ErrorAction SilentlyContinue)
if (-not $script:TmxTemGit) {
    Write-Warning "tests/Publish.Tests.ps1: 'git' nao encontrado no PATH - suite inteira pulada."
}

Describe 'Publish-Release.ps1' -Tag 'Publish' -Skip:(-not $script:TmxTemGit) {

    BeforeAll {
        $script:Raiz   = Split-Path $PSScriptRoot -Parent
        $script:Clones = New-Object 'System.Collections.Generic.List[string]'

        function New-TmxPublishClone {
            <#
            .SYNOPSIS
                Clone local (git clone --quiet de uma pasta no disco, sem
                rede) do repositorio de teste, com user.name/user.email
                configurados so nesse clone.
            #>
            [CmdletBinding()]
            param()

            $destino = Join-Path ([IO.Path]::GetTempPath()) ('TmxPublish_{0}' -f ([guid]::NewGuid().ToString('N')))
            $saida = & git clone --quiet -- $script:Raiz $destino 2>&1
            if ($LASTEXITCODE -ne 0) { throw "git clone falhou:`n$($saida -join "`n")" }

            Push-Location $destino
            try {
                & git config user.email 'tests@tweakmaxing.local' | Out-Null
                & git config user.name  'TweakMaxing Tests' | Out-Null
            } finally {
                Pop-Location
            }

            $script:Clones.Add($destino)
            $destino
        }

        function Add-TmxReleaseNotes {
            <#
            .SYNOPSIS
                Cria docs\release-notes\v<versao>.md no clone e comita, para
                que Publish-Release.ps1 nao recuse por notas ausentes.
            #>
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)] [string] $Clone,
                [Parameter(Mandatory)] [string] $Versao
            )

            $pasta = Join-Path $Clone 'docs\release-notes'
            New-Item -ItemType Directory -Path $pasta -Force | Out-Null
            $arquivo = Join-Path $pasta "v$Versao.md"
            Set-Content -LiteralPath $arquivo -Value "# v$Versao`n`nNotas de teste." -Encoding ASCII

            Push-Location $Clone
            try {
                & git add -- "docs/release-notes/v$Versao.md" | Out-Null
                & git commit -m "teste: notas de release v$Versao" --quiet | Out-Null
            } finally {
                Pop-Location
            }
        }
    }

    AfterAll {
        foreach ($pasta in $script:Clones.ToArray()) {
            if (Test-Path -LiteralPath $pasta) {
                Remove-Item -LiteralPath $pasta -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'Fluxo completo (DryRun)' {

        BeforeAll {
            $script:Clone   = New-TmxPublishClone
            $script:Publish = Join-Path $script:Clone 'tools\Publish-Release.ps1'
            Add-TmxReleaseNotes -Clone $script:Clone -Versao '9.9.9'

            $script:Erro = $null
            try {
                $script:Saida = & $script:Publish -Repo 'testuser/tweakmaxing-test' -Version '9.9.9' -SkipSdk -DryRun *>&1
            } catch {
                $script:Erro  = $_
                $script:Saida = @()
            }
            $script:Texto = ($script:Saida | Out-String)
            # O host as vezes quebra uma linha longa do Write-Host na largura
            # do console; achatado (sem quebras de linha) o teste de
            # substring nao depende de largura nenhuma.
            $script:TextoAchatado = ($script:Texto -replace '\s+', ' ')
        }

        It 'roda sem lancar excecao' {
            $script:Erro | Should -BeNullOrEmpty -Because $script:Texto
        }

        It 'gera TweakMaxing.ps1' {
            Test-Path -LiteralPath (Join-Path $script:Clone 'TweakMaxing.ps1') | Should -BeTrue -Because $script:Texto
        }

        It 'grava SHA256SUMS.txt com hash batendo com Get-FileHash' {
            $artefato = Join-Path $script:Clone 'TweakMaxing.ps1'
            $sums     = Join-Path $script:Clone 'SHA256SUMS.txt'
            Test-Path -LiteralPath $sums | Should -BeTrue -Because $script:Texto

            $hash = (Get-FileHash -LiteralPath $artefato -Algorithm SHA256).Hash
            (Get-Content -LiteralPath $sums -Raw).Trim() | Should -Be "$hash  TweakMaxing.ps1"
        }

        It 'grava REPO com o repositorio informado' {
            $linhas = @(Get-Content -LiteralPath (Join-Path $script:Clone 'REPO'))
            $valor  = ($linhas | Where-Object { $_.Trim() -and -not $_.Trim().StartsWith('#') } | Select-Object -Last 1)
            "$valor".Trim() | Should -Be 'testuser/tweakmaxing-test'
        }

        It 'cria a tag v9.9.9 localmente (sem empurrar)' {
            Push-Location $script:Clone
            try {
                $tags = & git tag -l 'v9.9.9'
            } finally {
                Pop-Location
            }
            "$tags".Trim() | Should -Be 'v9.9.9'
        }

        It 'imprime o plano de git push/gh release create com a tag certa, sem executar' {
            # Contra a versao achatada (sem quebra de linha): o console pode
            # quebrar uma linha longa do Write-Host em qualquer largura, o
            # que partiria uma frase no meio numa comparacao direta.
            $script:TextoAchatado | Should -Match ([regex]::Escape('[DryRun] git push origin main'))
            $script:TextoAchatado | Should -Match ([regex]::Escape('[DryRun] git push origin v9.9.9'))
            $script:TextoAchatado | Should -Match ([regex]::Escape('release create v9.9.9'))
            $script:TextoAchatado | Should -Match ([regex]::Escape('TweakMaxing v9.9.9'))
            $script:TextoAchatado | Should -Match ([regex]::Escape('--notes-file docs/release-notes/v9.9.9.md'))
        }

        It 'nao publicou de verdade (nenhuma URL de release criada no output)' {
            $script:Texto | Should -Not -Match 'releases/tag/'
        }
    }

    Context 'Validacoes' {

        It 'recusa repositorio invalido' {
            $clone   = New-TmxPublishClone
            $publish = Join-Path $clone 'tools\Publish-Release.ps1'
            { & $publish -Repo 'espaco invalido' -DryRun } | Should -Throw '*Repositorio invalido*'
        }

        It 'recusa working tree suja' {
            $clone   = New-TmxPublishClone
            $publish = Join-Path $clone 'tools\Publish-Release.ps1'
            Set-Content -LiteralPath (Join-Path $clone 'sujo.txt') -Value 'sujo' -Encoding ASCII
            { & $publish -Repo 'testuser/tweakmaxing-test' -DryRun } | Should -Throw '*suja*'
        }

        It 'recusa quando faltam as notas de release' {
            $clone   = New-TmxPublishClone
            $publish = Join-Path $clone 'tools\Publish-Release.ps1'
            # '6.6.6' nao tem docs\release-notes\v6.6.6.md neste clone.
            { & $publish -Repo 'testuser/tweakmaxing-test' -Version '6.6.6' -SkipSdk -DryRun } |
                Should -Throw '*Notas de release ausentes*'
        }

        It '-CreateRepo e -NoPush juntos sao recusados sem tocar em nada' {
            $clone   = New-TmxPublishClone
            $publish = Join-Path $clone 'tools\Publish-Release.ps1'
            { & $publish -Repo 'testuser/tweakmaxing-test' -CreateRepo -NoPush } |
                Should -Throw '*incompativeis*'
        }
    }

    Context '-NoPush' {

        It 'compila e cria a tag, mas so imprime os comandos de push/release' {
            $clone   = New-TmxPublishClone
            $publish = Join-Path $clone 'tools\Publish-Release.ps1'
            Add-TmxReleaseNotes -Clone $clone -Versao '8.8.8'

            $saida = & $publish -Repo 'testuser/tweakmaxing-test' -Version '8.8.8' -SkipSdk -NoPush *>&1
            $texto = ($saida | Out-String)

            Test-Path -LiteralPath (Join-Path $clone 'TweakMaxing.ps1') | Should -BeTrue -Because $texto
            $texto | Should -Match ([regex]::Escape('-NoPush: nada empurrado'))
            $texto | Should -Not -Match 'releases/tag/'
        }
    }
}
