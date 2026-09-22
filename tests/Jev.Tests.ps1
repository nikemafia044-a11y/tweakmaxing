# tests/Jev.Tests.ps1
# Verifica a integracao com o Jev (TypeSafe) SEM rede: geracao de payloads, lotes e traducao de respostas.
. "$PSScriptRoot\_Helpers.ps1"

Describe 'Jev: cliente e utilitarios' -Tag 'Jev' {
    BeforeAll {
        . "$PSScriptRoot\_Helpers.ps1"
        . "$PSScriptRoot\..\tools\jev\Invoke-TmxJev.ps1"
        $script:ChaveAntes = $env:TYPESAFE_API_KEY
    }
    AfterAll { $env:TYPESAFE_API_KEY = $script:ChaveAntes }

    It 'Invoke-TmxJev lanca com mensagem clara sem chave e nao chama a rede' {
        $env:TYPESAFE_API_KEY = ''
        Mock Invoke-RestMethod { throw 'nao deveria chamar' }
        { Invoke-TmxJev -State 'x' -Questions @{ q = @{ type = 'noul'; instructions = 'x?' } } } | Should -Throw '*TYPESAFE_API_KEY*'
        Should -Invoke Invoke-RestMethod -Times 0
    }

    It 'Invoke-TmxJev envia o corpo como bytes UTF-8 com Authorization Bearer' {
        $env:TYPESAFE_API_KEY = 'chave-de-teste'
        Mock Invoke-RestMethod {
            $script:Capturado = @{ Uri = $Uri; Headers = $Headers; Body = $Body }
            [pscustomobject]@{ answers = @{ q = @{ probability = 0.9 } }; usage = @{ input_tokens = 1; output_tokens = 1 } }
        }
        $r = Invoke-TmxJev -State @{ texto = 'acentua' + [char]0x00E7 + [char]0x00E3 + 'o' } -Questions @{ q = @{ type = 'noul'; instructions = 'x?' } }
        $r.answers.q.probability | Should -Be 0.9
        $script:Capturado.Uri | Should -Be 'https://api.typesafe.ai/v1/systemone'
        $script:Capturado.Headers.Authorization | Should -Be 'Bearer chave-de-teste'
        ($script:Capturado.Body -is [byte[]]) | Should -BeTrue
        $texto = [Text.Encoding]::UTF8.GetString($script:Capturado.Body)
        $texto | Should -Match '"model":"jev-latest"'
        $texto | Should -Match ('acentua' + [char]0x00E7 + [char]0x00E3 + 'o')
    }

    It 'Split-TmxJevBatches divide em lotes do tamanho pedido' {
        $lotes = Split-TmxJevBatches -Items @(1..95) -Size 40
        @($lotes).Count | Should -Be 3
        @($lotes[0]).Count | Should -Be 40
        @($lotes[2]).Count | Should -Be 15
    }

    It 'ConvertTo-TmxJevDecision traduz noul e choice em decisoes' {
        (ConvertTo-TmxJevDecision -Answer ([pscustomobject]@{ probability = 0.95 })).veredito | Should -Be 'sim'
        (ConvertTo-TmxJevDecision -Answer ([pscustomobject]@{ probability = 0.05 })).veredito | Should -Be 'nao'
        (ConvertTo-TmxJevDecision -Answer ([pscustomobject]@{ probability = 0.5 })).veredito | Should -Be 'incerto'
        $c = ConvertTo-TmxJevDecision -Answer ([pscustomobject]@{ probabilities = [pscustomobject]@{ MEDIDO = 0.9; TECNICO = 0.08; FOLCLORE = 0.02 } })
        $c.rotulo | Should -Be 'MEDIDO'; $c.decisao | Should -Be 'auto'
        $c2 = ConvertTo-TmxJevDecision -Answer ([pscustomobject]@{ probabilities = [pscustomobject]@{ MEDIDO = 0.5; TECNICO = 0.45; FOLCLORE = 0.05 } })
        $c2.decisao | Should -Be 'review'
    }
}

Describe 'Jev: geracao de payloads do catalogo e dos apps (offline)' -Tag 'Jev' {
    BeforeAll {
        . "$PSScriptRoot\_Helpers.ps1"
        $script:Raiz = Split-Path $PSScriptRoot -Parent
        $script:Saida = Join-Path ([IO.Path]::GetTempPath()) ("TmxJev_" + [guid]::NewGuid().ToString('N'))
    }
    AfterAll { if (Test-Path $script:Saida) { Remove-Item -LiteralPath $script:Saida -Recurse -Force } }

    It 'catalogo: -DryRun gera lotes com tres perguntas por tweak e sai com 3' {
        & (Join-Path $script:Raiz 'tools\jev\Invoke-TmxJevCatalogQa.ps1') -DryRun -OutDir $script:Saida *> $null
        $LASTEXITCODE | Should -Be 3
        $lotes = @(Get-ChildItem -LiteralPath $script:Saida -Filter 'catalogo-lote-*.json')
        $lotes.Count | Should -BeGreaterThan 1
        $p = Get-Content -LiteralPath $lotes[0].FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        $nIds = @($p.ids).Count
        @($p.questions.PSObject.Properties).Count | Should -Be (3 * $nIds)
        $primeiro = "$($p.ids[0])" -replace '[^A-Za-z0-9]', '_'
        $p.questions."tier_$primeiro".type | Should -Be 'choice'
        @($p.questions."tier_$primeiro".criteria.PSObject.Properties.Name | Sort-Object) | Should -Be @('FOLCLORE', 'MEDIDO', 'TECNICO')
        $p.questions."promessa_$primeiro".type | Should -Be 'noul'
        $p.state.itens.$primeiro.nome | Should -Not -BeNullOrEmpty
        (Get-Item $lotes[0].FullName).Length | Should -BeLessThan 120000
    }

    It 'apps: -DryRun gera lotes com uma pergunta por app' {
        & (Join-Path $script:Raiz 'tools\jev\Invoke-TmxJevAppsQa.ps1') -DryRun -OutDir $script:Saida *> $null
        $LASTEXITCODE | Should -Be 3
        $lotes = @(Get-ChildItem -LiteralPath $script:Saida -Filter 'apps-lote-*.json')
        $lotes.Count | Should -BeGreaterThan 1
        $p = Get-Content -LiteralPath $lotes[0].FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        @($p.questions.PSObject.Properties).Count | Should -Be @($p.ids).Count
    }
}
