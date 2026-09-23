Describe 'launcher/vercel.json (irm | iex)' -Tag 'Launcher' {

    BeforeAll {
        $raiz = Split-Path $PSScriptRoot -Parent
        $script:ArquivoLauncher = Join-Path $raiz 'launcher\vercel.json'
        $script:Repo = @(Get-Content -LiteralPath (Join-Path $raiz 'REPO') |
            Where-Object { $_.Trim() -and -not $_.TrimStart().StartsWith('#') })[-1].Trim()
        $script:Destino = "https://github.com/$script:Repo/releases/latest/download/TweakMaxing.ps1"
    }

    It 'existe e e JSON valido' {
        Test-Path -LiteralPath $script:ArquivoLauncher | Should -BeTrue
        { Get-Content -LiteralPath $script:ArquivoLauncher -Raw | ConvertFrom-Json } | Should -Not -Throw
    }

    It 'REPO nao e mais o placeholder' {
        $script:Repo | Should -Not -BeLike 'SEU_USUARIO/*'
    }

    It 'redireciona / e /win para o asset latest do repositorio, sem cache permanente' {
        $cfg = Get-Content -LiteralPath $script:ArquivoLauncher -Raw | ConvertFrom-Json
        foreach ($rota in '/', '/win') {
            $r = @($cfg.redirects | Where-Object { $_.source -eq $rota })
            $r.Count            | Should -Be 1 -Because "a rota $rota tem que existir uma vez"
            $r[0].destination   | Should -Be $script:Destino
            $r[0].permanent     | Should -BeFalse
        }
    }
}
