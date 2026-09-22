# Testes do avaliador de condicoes (src/Engine/Condition.ps1).
# Porta dos testes do CS2Tuner: parser + avaliacao contra um objeto de perfil.
# Puros: nao tocam registro, disco ou rede.

. "$PSScriptRoot\_Helpers.ps1"

BeforeAll {
    . "$PSScriptRoot\_Helpers.ps1"
    Import-TmxTestModule
}

AfterAll {
    Remove-Module TweakMaxing -Force -ErrorAction SilentlyContinue
}

Describe 'ConvertFrom-TmxCondition (parser)' -Tag 'Engine' {

    It 'faz parse de caminho, operador e valor' {
        $c = ConvertFrom-TmxCondition 'os.build >= 18363'
        $c.caminho  | Should -Be 'os.build'
        $c.operador | Should -Be '>='
        $c.valor    | Should -Be '18363'
    }

    It 'separa o motivo apos ::' {
        $c = ConvertFrom-TmxCondition 'os.isLaptop == true :: em notebook nao'
        $c.valor  | Should -Be 'true'
        $c.motivo | Should -Be 'em notebook nao'
    }

    It 'aceita valor entre aspas com espacos' {
        (ConvertFrom-TmxCondition 'gpu.modelo contains "RTX 40"').valor | Should -Be 'RTX 40'
    }

    It 'exists nao aceita valor' {
        { ConvertFrom-TmxCondition 'os.bcd exists true' } | Should -Throw
    }

    It 'comparacao exige valor' {
        { ConvertFrom-TmxCondition 'os.build >=' } | Should -Throw
    }

    It 'rejeita operador desconhecido' {
        { ConvertFrom-TmxCondition 'os.build ~= 1' } | Should -Throw
    }
}

Describe 'Test-TmxCondition (avaliacao)' -Tag 'Engine' {

    BeforeAll {
        . "$PSScriptRoot\_Helpers.ps1"
        $script:p = [pscustomobject]@{
            os      = [pscustomobject]@{ build = 26100; isLaptop = $false; nome = 'Windows 11'; nulo = $null }
            gpu     = [pscustomobject]@{ vendor = 'NVIDIA'; dataDriver = '2024-08-20'; lista = @('a', 'b') }
            storage = [pscustomobject]@{ pct = 6.7; tipo = 'NVMe' }
            hex     = [pscustomobject]@{ prio = '0x26' }
        }
    }

    It '<expr> -> <esperado>' -TestCases @(
        @{ expr = 'os.build >= 18363';            esperado = $true }
        @{ expr = 'os.build < 18363';             esperado = $false }
        @{ expr = 'os.build == 26100';            esperado = $true }
        @{ expr = 'os.build != 26100';            esperado = $false }
        @{ expr = 'os.isLaptop == true';          esperado = $false }
        @{ expr = 'os.isLaptop == false';         esperado = $true }
        @{ expr = 'os.isLaptop != true';          esperado = $true }
        @{ expr = 'gpu.vendor == nvidia';         esperado = $true }
        @{ expr = 'gpu.vendor != AMD';            esperado = $true }
        @{ expr = 'gpu.dataDriver >= 2022-06-01'; esperado = $true }
        @{ expr = 'gpu.dataDriver < 2022-06-01';  esperado = $false }
        @{ expr = 'storage.pct < 15';             esperado = $true }
        @{ expr = 'storage.pct > 15';             esperado = $false }
        @{ expr = 'os.nome contains windows';     esperado = $true }
        @{ expr = 'os.nome contains linux';       esperado = $false }
        @{ expr = 'gpu.lista contains B';         esperado = $true }
        @{ expr = 'gpu.lista contains z';         esperado = $false }
        @{ expr = 'gpu.vendor exists';            esperado = $true }
        @{ expr = 'gpu.inexistente exists';       esperado = $false }
        @{ expr = 'os.nulo exists';               esperado = $false }
        @{ expr = 'os.nulo == null';              esperado = $true }
        @{ expr = 'gpu.inexistente == null';      esperado = $true }
        @{ expr = 'gpu.vendor != null';           esperado = $true }
        @{ expr = 'hex.prio == 0x26';             esperado = $true }
        @{ expr = 'hex.prio == 38';               esperado = $true }
    ) {
        (Test-TmxCondition -Expression $expr -Profile $script:p).resultado | Should -Be $esperado
    }

    It 'caminho ausente em comparacao -> indeterminado ($null)' {
        $r = Test-TmxCondition -Expression 'gpu.inexistente == 1' -Profile $script:p
        $r.resultado  | Should -BeNullOrEmpty
        $r.encontrado | Should -BeFalse
        $r.detalhe    | Should -Match 'indeterminada'
    }

    It 'valor nao numerico comparado com numero -> indeterminado' {
        (Test-TmxCondition -Expression 'gpu.vendor > 5' -Profile $script:p).resultado | Should -BeNullOrEmpty
    }

    It 'expoe valorAtual e motivo' {
        $r = Test-TmxCondition -Expression 'os.build >= 1 :: build ok' -Profile $script:p
        $r.valorAtual | Should -Be 26100
        $r.motivo     | Should -Be 'build ok'
    }

    It 'funciona com hashtables' {
        $h = @{ a = @{ b = 3 } }
        (Test-TmxCondition -Expression 'a.b == 3' -Profile $h).resultado | Should -BeTrue
    }

    It 'resolve caminho do perfil real (fixture profile-engine.json)' {
        $perfil = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'fixtures\profile-engine.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        (Test-TmxCondition -Expression 'os.isLaptop == false' -Profile $perfil).resultado                 | Should -BeTrue
        (Test-TmxCondition -Expression 'network.adaptadorAtivo.tipo == Ethernet' -Profile $perfil).resultado | Should -BeTrue
        (Test-TmxCondition -Expression 'storage.cs2Path exists' -Profile $perfil).resultado               | Should -BeTrue
    }
}
