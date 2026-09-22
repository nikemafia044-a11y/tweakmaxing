# Testes de Set-TmxRegistry: captura do valor anterior, criacao de chave, -WhatIf.
# Usa HKCU (nao exige elevacao) e uma raiz isolada via TWEAKMAXING_HOME.

. "$PSScriptRoot\_Helpers.ps1"

BeforeAll {
    . "$PSScriptRoot\_Helpers.ps1"
    Import-TmxTestModule
    New-TmxTestHome | Out-Null
    $script:TestSubKey = 'Core\Registry'
    $script:TestRoot   = "HKCU:\Software\TweakMaxing_Tests\$script:TestSubKey"
}

AfterAll {
    Remove-TmxTestKey -SubKey $script:TestSubKey
    Remove-TmxTestHome
    Stop-TmxLogger
    Remove-Module TweakMaxing -Force -ErrorAction SilentlyContinue
}

Describe 'Set-TmxRegistry' -Tag 'Registry' {

    BeforeEach {
        Remove-TmxTestKey -SubKey $script:TestSubKey
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

    It 'M2: registra chaveRaizCriada como o primeiro ancestral inexistente' {
        New-Item -Path "$script:TestRoot\Raiz" -Force | Out-Null
        $key = "$script:TestRoot\Raiz\Sub\Folha"

        $rec = Set-TmxRegistry -Path $key -Name 'X' -Value 1 -Type DWord -PassThru

        $rec.detalhe.chaveRaizCriada | Should -Be "$script:TestRoot\Raiz\Sub"
    }

    It '-Remove captura o valor anterior, persiste antes de remover, e undo restaura' {
        $key = "$script:TestRoot\ParaRemover"
        New-Item -Path $key -Force | Out-Null
        New-ItemProperty -Path $key -Name 'V' -Value 42 -PropertyType DWord -Force | Out-Null

        $rec = Set-TmxRegistry -Path $key -Name 'V' -Remove -TweakId 'RM-1' -PassThru

        $rec.status        | Should -Be 'aplicado'
        $rec.valorAnterior | Should -Be 42
        $rec.tipoAnterior  | Should -Be 'DWord'
        $rec.reversao.tipo | Should -Be 'restaurarValorAnterior'
        (Get-Item -Path $key).GetValueNames() | Should -Not -Contain 'V'

        # persistiu ANTES de remover: o state.json ja tem o registro com o valor anterior
        $emDisco = Import-TmxState -StatePath $script:run.StatePath
        ($emDisco | Where-Object { $_.tweakId -eq 'RM-1' }).valorAnterior | Should -Be 42

        Undo-TweakMaxing -StatePath $script:run.StatePath 6> $null | Out-Null
        (Get-ItemProperty -Path $key -Name 'V').V | Should -Be 42
    }

    It '-Remove em valor inexistente e naoAplicavel' {
        $key = "$script:TestRoot\SemValor"
        New-Item -Path $key -Force | Out-Null

        $rec = Set-TmxRegistry -Path $key -Name 'Fantasma' -Remove -PassThru

        $rec.status | Should -Be 'naoAplicavel'
        (Get-TmxState).Count | Should -Be 0
    }

    It '-Remove -WhatIf nao persiste nem remove' {
        $key = "$script:TestRoot\RemoveWhatIf"
        New-Item -Path $key -Force | Out-Null
        New-ItemProperty -Path $key -Name 'V' -Value 9 -PropertyType DWord -Force | Out-Null

        $rec = Set-TmxRegistry -Path $key -Name 'V' -Remove -WhatIf -PassThru

        $rec.status | Should -Be 'whatif'
        (Get-ItemProperty -Path $key -Name 'V').V | Should -Be 9
        (Get-TmxState).Count | Should -Be 0
    }
}

Describe 'Escrita sem execucao ativa' -Tag 'Registry' {

    # A guarda de Core/Backup.ps1: sem New-TmxRun nao existe state.json, logo
    # nao existe reversao - e sem reversao nada pode ser escrito no sistema.
    # $script:TmxRun e zerado por dentro do modulo porque nao ha (nem deve
    # haver) uma funcao publica para encerrar uma execucao.

    BeforeEach {
        Remove-TmxTestKey -SubKey $script:TestSubKey
        New-Item -Path $script:TestRoot -Force | Out-Null
        InModuleScope TweakMaxing {
            $script:TmxRun          = $null
            $script:TmxStateRecords = $null
        }
    }

    AfterEach {
        InModuleScope TweakMaxing {
            $script:TmxRun          = $null
            $script:TmxStateRecords = $null
        }
    }

    It 'Set-TmxRegistry lanca e nao escreve nada' {
        $key = "$script:TestRoot\SemRun"
        New-Item -Path $key -Force | Out-Null

        { Set-TmxRegistry -Path $key -Name 'V' -Value 1 -Type DWord -TweakId 'SR-1' } |
            Should -Throw 'nenhuma execucao ativa: chame New-TmxRun antes de alterar o sistema'

        # O valor nao foi criado: a guarda dispara ANTES da escrita.
        (Get-Item -Path $key).GetValueNames() | Should -Not -Contain 'V'
        @(Get-TmxState).Count | Should -Be 0
    }

    It 'Set-TmxRegistry -Remove lanca e nao remove nada' {
        $key = "$script:TestRoot\SemRunRemove"
        New-Item -Path $key -Force | Out-Null
        New-ItemProperty -Path $key -Name 'V' -Value 9 -PropertyType DWord -Force | Out-Null

        { Set-TmxRegistry -Path $key -Name 'V' -Remove -TweakId 'SR-2' } |
            Should -Throw 'nenhuma execucao ativa: chame New-TmxRun antes de alterar o sistema'

        (Get-ItemProperty -Path $key -Name 'V').V | Should -Be 9
    }

    It 'New-TmxStateRecord lanca' {
        { New-TmxStateRecord -TweakId 'SR-3' -Tipo 'cmdlet' -Alvo 'alvo qualquer' } |
            Should -Throw 'nenhuma execucao ativa: chame New-TmxRun antes de alterar o sistema'
        @(Get-TmxState).Count | Should -Be 0
    }

    It 'New-TmxCmdletRecord lanca (passa por New-TmxStateRecord)' {
        { New-TmxCmdletRecord -TweakId 'SR-4' -Funcao 'Set-TmxFake' -Alvo 'alvo' -Estado @{ a = 1 } } |
            Should -Throw 'nenhuma execucao ativa: chame New-TmxRun antes de alterar o sistema'
    }

    It 'Save-TmxState lanca' {
        { Save-TmxState } | Should -Throw 'nenhuma execucao ativa: chame New-TmxRun antes de alterar o sistema'
    }

    It 'New-TmxRun passa pela guarda e deixa o estado gravavel de novo' {
        $run = New-TmxRun
        Test-Path -LiteralPath $run.StatePath | Should -BeTrue

        $key = "$script:TestRoot\ComRun"
        $rec = Set-TmxRegistry -Path $key -Name 'V' -Value 3 -Type DWord -TweakId 'SR-5' -PassThru
        $rec.status | Should -Be 'aplicado'
        (Get-ItemProperty -Path $key -Name 'V').V | Should -Be 3
    }
}
