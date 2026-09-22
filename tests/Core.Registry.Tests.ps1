# Testes de Set-TmxRegistry: captura do valor anterior, criacao de chave, -WhatIf.
# Usa HKCU (nao exige elevacao) e uma raiz isolada via TWEAKMAXING_HOME.

. "$PSScriptRoot\_Helpers.ps1"

BeforeAll {
    . "$PSScriptRoot\_Helpers.ps1"
    Import-TmxTestModule
    New-TmxTestHome | Out-Null
    $script:TestRoot = 'HKCU:\Software\TweakMaxing_Tests'
}

AfterAll {
    Remove-TmxTestKey
    Remove-TmxTestHome
    Stop-TmxLogger
    Remove-Module TweakMaxing -Force -ErrorAction SilentlyContinue
}

Describe 'Set-TmxRegistry' -Tag 'Registry' {

    BeforeEach {
        Remove-TmxTestKey
        New-Item -Path $script:TestRoot -Force | Out-Null
        $script:run = New-TmxRun
    }

    It 'captura o valor anterior quando o valor ja existe' {
        $key = "$script:TestRoot\Existente"
        New-Item -Path $key -Force | Out-Null
        New-ItemProperty -Path $key -Name 'Val' -Value 10 -PropertyType DWord -Force | Out-Null

        $rec = Set-TmxRegistry -Path $key -Name 'Val' -Value 42 -Type DWord -TweakId 'T-1' -PassThru

        $rec.status        | Should -Be 'aplicado'
        $rec.existiaAntes  | Should -BeTrue
        $rec.valorAnterior | Should -Be 10
        $rec.tipoAnterior  | Should -Be 'DWord'
        $rec.valorNovo     | Should -Be 42
        $rec.reversao.tipo | Should -Be 'restaurarValorAnterior'
        (Get-ItemProperty -Path $key -Name 'Val').Val | Should -Be 42
    }

    It 'marca existiaAntes = false quando o valor nao existe mas a chave sim' {
        $key = "$script:TestRoot\SoChave"
        New-Item -Path $key -Force | Out-Null

        $rec = Set-TmxRegistry -Path $key -Name 'Novo' -Value 1 -Type DWord -PassThru

        $rec.existiaAntes        | Should -BeFalse
        $rec.valorAnterior       | Should -BeNullOrEmpty
        $rec.detalhe.chaveCriada | Should -BeFalse
        $rec.reversao.tipo       | Should -Be 'removerValor'
    }

    It 'cria o caminho e sinaliza chaveCriada quando a chave nao existe' {
        $key = "$script:TestRoot\Nova\Sub\Folha"

        $rec = Set-TmxRegistry -Path $key -Name 'X' -Value 7 -Type DWord -PassThru

        $rec.existiaAntes        | Should -BeFalse
        $rec.detalhe.chaveCriada | Should -BeTrue
        $rec.reversao.tipo       | Should -Be 'removerChaveCriada'
        (Get-ItemProperty -Path $key -Name 'X').X | Should -Be 7
    }

    It 'preserva o tipo anterior ao capturar (String)' {
        $key = "$script:TestRoot\Tipos"
        New-Item -Path $key -Force | Out-Null
        New-ItemProperty -Path $key -Name 'S' -Value 'abc' -PropertyType String -Force | Out-Null

        $rec = Set-TmxRegistry -Path $key -Name 'S' -Value 'xyz' -Type String -PassThru

        $rec.tipoAnterior  | Should -Be 'String'
        $rec.valorAnterior | Should -Be 'abc'
    }

    It 'nao escreve nada com -WhatIf e nao registra estado' {
        $key = "$script:TestRoot\WhatIf"

        $rec = Set-TmxRegistry -Path $key -Name 'X' -Value 1 -Type DWord -WhatIf -PassThru

        $rec.status | Should -Be 'whatif'
        Test-Path $key | Should -BeFalse
        (Get-TmxState).Count | Should -Be 0
    }

    It 'persiste o registro de estado em disco antes de concluir' {
        $key = "$script:TestRoot\Persistido"

        Set-TmxRegistry -Path $key -Name 'X' -Value 1 -Type DWord -TweakId 'T-2'

        $emDisco = Import-TmxState -StatePath $script:run.StatePath
        @($emDisco | Where-Object { $_.tweakId -eq 'T-2' }).Count | Should -Be 1
        ($emDisco | Where-Object { $_.tweakId -eq 'T-2' }).status | Should -Be 'aplicado'
    }

    It 'nao retorna nada sem -PassThru' {
        $key = "$script:TestRoot\Silencioso"
        $out = Set-TmxRegistry -Path $key -Name 'X' -Value 1 -Type DWord
        $out | Should -BeNullOrEmpty
    }
}
