# tests/Headless.Tests.ps1
# O caminho headless de ponta a ponta, num processo separado.
#
# Nao da para exercitar isso dentro do Pester: o objetivo e justamente provar
# que o Start-TmxDev.ps1 monta UM escopo de script (start.ps1 e main.ps1 entram
# por dot-source) e que, por causa disso, as funcoes do Engine enxergam as
# variaveis $script:Tmx*. Rodar aqui dentro reusaria o escopo do proprio teste
# e esconderia exatamente o bug.

. (Join-Path $PSScriptRoot '_Helpers.ps1')

Describe 'Execucao headless' -Tag 'Headless' {

    BeforeAll {
        . (Join-Path $PSScriptRoot '_Helpers.ps1')

        $script:RaizRepo = Split-Path $PSScriptRoot -Parent
        $script:DevRunner = Join-Path $script:RaizRepo 'Start-TmxDev.ps1'

        # O processo filho nao pode herdar a pasta de teste de outra suite.
        $script:HomeAnterior = $env:TWEAKMAXING_HOME
        Remove-Item Env:\TWEAKMAXING_HOME -ErrorAction SilentlyContinue
    }

    AfterAll {
        if ($script:HomeAnterior) { $env:TWEAKMAXING_HOME = $script:HomeAnterior }
    }

    Context 'Start-TmxDev.ps1 -Headless -Preset desktop -DryRun' {

        BeforeAll {
            $saida = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:DevRunner `
                -Headless -Preset desktop -DryRun -NoElevate 2>&1
            $script:Codigo = $LASTEXITCODE
            $script:Texto  = ($saida | Out-String)
        }

        It 'sai com 0' {
            $script:Codigo | Should -Be 0 -Because "saida:`n$script:Texto"
        }

        It 'monta o plano com o catalogo real (sem cair para catalogo vazio)' {
            $script:Texto | Should -Not -Match 'Nao foi possivel montar o plano' -Because "saida:`n$script:Texto"
            $script:Texto | Should -Not -Match 'Catalogo indisponivel' -Because "saida:`n$script:Texto"
        }

        It 'simula pelo menos 9 itens' {
            $m = [regex]::Match($script:Texto, 'Simulacao concluida:\s*(\d+) itens')
            $m.Success | Should -BeTrue -Because "saida:`n$script:Texto"
            ([int]$m.Groups[1].Value) | Should -BeGreaterOrEqual 9 -Because "saida:`n$script:Texto"
        }

        It 'nao altera nada (permanece uma simulacao)' {
            $script:Texto | Should -Match 'nada foi alterado'
        }
    }
}
