# Testes de Undo-TweakMaxing: valor alterado, valor criado do zero, chave inexistente,
# ordem inversa e recuperacao apos morte do processo (estado apenas em disco).

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

Describe 'Undo-TweakMaxing' -Tag 'Rollback' {

    BeforeEach {
        Remove-TmxTestKey
        New-Item -Path $script:TestRoot -Force | Out-Null
        $script:run = New-TmxRun
    }

    It 'restaura o valor original de um valor alterado' {
        $key = "$script:TestRoot\Alterado"
        New-Item -Path $key -Force | Out-Null
        New-ItemProperty -Path $key -Name 'V' -Value 100 -PropertyType DWord -Force | Out-Null

        Set-TmxRegistry -Path $key -Name 'V' -Value 999 -Type DWord
        (Get-ItemProperty -Path $key -Name 'V').V | Should -Be 999

        $sum = Undo-TweakMaxing -StatePath $script:run.StatePath 6> $null

        $sum.revertidos | Should -Be 1
        $sum.falhas     | Should -Be 0
        (Get-ItemProperty -Path $key -Name 'V').V | Should -Be 100
        (Get-Item -Path $key).GetValueKind('V').ToString() | Should -Be 'DWord'
    }

    It 'restaura um DWord com bit alto (0xFFFFFFFF) sem estourar int32' {
        $key = "$script:TestRoot\DwordAlto"
        New-Item -Path $key -Force | Out-Null
        New-ItemProperty -Path $key -Name 'V' -Value ([int]-1) -PropertyType DWord -Force | Out-Null

        Set-TmxRegistry -Path $key -Name 'V' -Value 5 -Type DWord
        ([int64](Get-ItemProperty -Path $key -Name 'V').V -band 0xFFFFFFFF) | Should -Be 5

        $sum = Undo-TweakMaxing -StatePath $script:run.StatePath 6> $null
        $sum.falhas | Should -Be 0
        ([int64](Get-ItemProperty -Path $key -Name 'V').V -band 0xFFFFFFFF) | Should -Be 4294967295
    }

    It 'restaura tipo e valor de uma String alterada' {
        $key = "$script:TestRoot\Str"
        New-Item -Path $key -Force | Out-Null
        New-ItemProperty -Path $key -Name 'S' -Value 'original' -PropertyType String -Force | Out-Null

        Set-TmxRegistry -Path $key -Name 'S' -Value 'novo' -Type String
        Undo-TweakMaxing -StatePath $script:run.StatePath 6> $null | Out-Null

        (Get-ItemProperty -Path $key -Name 'S').S | Should -Be 'original'
        (Get-Item -Path $key).GetValueKind('S').ToString() | Should -Be 'String'
    }

    It 'remove um valor criado do zero (chave ja existia)' {
        $key = "$script:TestRoot\ValorNovo"
        New-Item -Path $key -Force | Out-Null
        New-ItemProperty -Path $key -Name 'Outro' -Value 1 -PropertyType DWord -Force | Out-Null

        Set-TmxRegistry -Path $key -Name 'Criado' -Value 5 -Type DWord
        Undo-TweakMaxing -StatePath $script:run.StatePath 6> $null | Out-Null

        (Get-Item -Path $key).GetValueNames() | Should -Not -Contain 'Criado'
        # a chave e o outro valor continuam intactos
        Test-Path $key | Should -BeTrue
        (Get-ItemProperty -Path $key -Name 'Outro').Outro | Should -Be 1
    }

    It 'remove a chave inteira quando ela nao existia antes' {
        $key = "$script:TestRoot\Arvore\Nova\Folha"

        Set-TmxRegistry -Path $key -Name 'X' -Value 1 -Type DWord
        Test-Path $key | Should -BeTrue

        Undo-TweakMaxing -StatePath $script:run.StatePath 6> $null | Out-Null

        Test-Path $key | Should -BeFalse
    }

    It 'nao apaga a chave criada se algo mais foi colocado nela depois' {
        $key = "$script:TestRoot\Compartilhada"

        Set-TmxRegistry -Path $key -Name 'X' -Value 1 -Type DWord
        # outro programa gravou algo na mesma chave
        New-ItemProperty -Path $key -Name 'DeTerceiro' -Value 'z' -PropertyType String -Force | Out-Null

        Undo-TweakMaxing -StatePath $script:run.StatePath 6> $null | Out-Null

        Test-Path $key | Should -BeTrue
        (Get-Item -Path $key).GetValueNames() | Should -Not -Contain 'X'
        (Get-Item -Path $key).GetValueNames() | Should -Contain 'DeTerceiro'
    }

    It 'reverte na ordem inversa da aplicacao' {
        $key = "$script:TestRoot\Ordem"
        New-Item -Path $key -Force | Out-Null
        New-ItemProperty -Path $key -Name 'V' -Value 0 -PropertyType DWord -Force | Out-Null

        Set-TmxRegistry -Path $key -Name 'V' -Value 1 -Type DWord -TweakId 'PRIMEIRO'
        Set-TmxRegistry -Path $key -Name 'V' -Value 2 -Type DWord -TweakId 'SEGUNDO'

        $sum = Undo-TweakMaxing -StatePath $script:run.StatePath 6> $null

        $sum.itens[0].tweakId | Should -Be 'SEGUNDO'
        $sum.itens[1].tweakId | Should -Be 'PRIMEIRO'
        (Get-ItemProperty -Path $key -Name 'V').V | Should -Be 0
    }

    It 'funciona mesmo se o processo original tiver morrido (estado so em disco)' {
        $key = "$script:TestRoot\Morto"
        New-Item -Path $key -Force | Out-Null
        New-ItemProperty -Path $key -Name 'V' -Value 7 -PropertyType DWord -Force | Out-Null

        Set-TmxRegistry -Path $key -Name 'V' -Value 77 -Type DWord
        $statePath = $script:run.StatePath

        # simula um novo processo: recarrega o modulo e perde todo o estado em memoria
        Import-TmxTestModule
        (Get-TmxState).Count | Should -Be 0

        Undo-TweakMaxing -StatePath $statePath 6> $null | Out-Null

        (Get-ItemProperty -Path $key -Name 'V').V | Should -Be 7
    }

    It 'reverte registros com status "aplicando" (escrita interrompida)' {
        $key = "$script:TestRoot\Interrompido"
        New-Item -Path $key -Force | Out-Null
        New-ItemProperty -Path $key -Name 'V' -Value 3 -PropertyType DWord -Force | Out-Null

        Set-TmxRegistry -Path $key -Name 'V' -Value 33 -Type DWord

        # forja um crash: reescreve o state.json com status 'aplicando'
        $json = Get-Content -LiteralPath $script:run.StatePath -Raw | ConvertFrom-Json
        $json.registros[0].status = 'aplicando'
        $json | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $script:run.StatePath -Encoding UTF8

        Undo-TweakMaxing -StatePath $script:run.StatePath 6> $null | Out-Null

        (Get-ItemProperty -Path $key -Name 'V').V | Should -Be 3
    }

    It '-Latest encontra a execucao mais recente' {
        $key = "$script:TestRoot\Latest"
        New-Item -Path $key -Force | Out-Null
        New-ItemProperty -Path $key -Name 'V' -Value 1 -PropertyType DWord -Force | Out-Null

        Set-TmxRegistry -Path $key -Name 'V' -Value 2 -Type DWord

        Undo-TweakMaxing -Latest 6> $null | Out-Null

        (Get-ItemProperty -Path $key -Name 'V').V | Should -Be 1
    }

    It '-WhatIf simula sem tocar no registro' {
        $key = "$script:TestRoot\Simulado"
        New-Item -Path $key -Force | Out-Null
        New-ItemProperty -Path $key -Name 'V' -Value 1 -PropertyType DWord -Force | Out-Null

        Set-TmxRegistry -Path $key -Name 'V' -Value 2 -Type DWord

        $sum = Undo-TweakMaxing -StatePath $script:run.StatePath -WhatIf 6> $null

        $sum.pulados | Should -Be 1
        $sum.revertidos | Should -Be 0
        (Get-ItemProperty -Path $key -Name 'V').V | Should -Be 2
    }

    It 'falha em um item nao interrompe os demais' {
        $keyA = "$script:TestRoot\FalhaA"
        $keyB = "$script:TestRoot\FalhaB"
        New-Item -Path $keyA -Force | Out-Null
        New-Item -Path $keyB -Force | Out-Null
        New-ItemProperty -Path $keyA -Name 'V' -Value 1 -PropertyType DWord -Force | Out-Null
        New-ItemProperty -Path $keyB -Name 'V' -Value 1 -PropertyType DWord -Force | Out-Null

        Set-TmxRegistry -Path $keyA -Name 'V' -Value 2 -Type DWord -TweakId 'A'
        Set-TmxRegistry -Path $keyB -Name 'V' -Value 2 -Type DWord -TweakId 'B'

        # corrompe o registro de B com uma estrategia desconhecida
        $json = Get-Content -LiteralPath $script:run.StatePath -Raw | ConvertFrom-Json
        ($json.registros | Where-Object { $_.tweakId -eq 'B' }).reversao.tipo = 'inexistente'
        $json | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $script:run.StatePath -Encoding UTF8

        $sum = Undo-TweakMaxing -StatePath $script:run.StatePath 6> $null

        $sum.falhas     | Should -Be 1
        $sum.revertidos | Should -Be 1
        (Get-ItemProperty -Path $keyA -Name 'V').V | Should -Be 1
    }

    It 'M2: undo remove os niveis intermediarios criados, ate o primeiro ancestral que existia' {
        $base = $script:TestRoot
        $path = "$base\A\B\C"

        $rec = Set-TmxRegistry -Path $path -Name 'V' -Value 1 -Type DWord -PassThru
        $rec.detalhe.chaveRaizCriada | Should -Be "$base\A"

        Undo-TweakMaxing -StatePath $script:run.StatePath 6> $null | Out-Null

        Test-Path "$base\A" | Should -BeFalse
        Test-Path $base     | Should -BeTrue
    }

    It 'M2: nao apaga ancestral que ganhou outro conteudo depois' {
        $base = $script:TestRoot
        $path = "$base\A\B\C"

        Set-TmxRegistry -Path $path -Name 'V' -Value 1 -Type DWord | Out-Null
        # outro programa criou uma subchave em A depois da nossa escrita
        New-Item -Path "$base\A\Outro" -Force | Out-Null

        Undo-TweakMaxing -StatePath $script:run.StatePath 6> $null | Out-Null

        Test-Path "$base\A\B"     | Should -BeFalse
        Test-Path "$base\A"       | Should -BeTrue
        Test-Path "$base\A\Outro" | Should -BeTrue
    }

    It 'A2: registros revertidos ficam marcados e nao sao revertidos de novo' {
        $key = "$script:TestRoot\MarcaRevertido"
        New-Item -Path $key -Force | Out-Null
        New-ItemProperty -Path $key -Name 'V' -Value 5 -PropertyType DWord -Force | Out-Null

        Set-TmxRegistry -Path $key -Name 'V' -Value 55 -Type DWord

        Undo-TweakMaxing -StatePath $script:run.StatePath 6> $null | Out-Null

        $st = @(Import-TmxState -StatePath $script:run.StatePath)
        $st[0].status      | Should -Be 'revertido'
        $st[0].revertidoEm | Should -Not -BeNullOrEmpty

        # alteracao manual depois da reversao; um segundo undo nao deve tocar
        New-ItemProperty -Path $key -Name 'V' -Value 77 -PropertyType DWord -Force | Out-Null

        $sum2 = Undo-TweakMaxing -StatePath $script:run.StatePath 6> $null

        $sum2.total | Should -Be 0
        (Get-ItemProperty -Path $key -Name 'V').V | Should -Be 77
    }

    It 'A2: -TweakId reverte so os registros daquele tweak' {
        $keyA = "$script:TestRoot\TwkA"
        $keyB = "$script:TestRoot\TwkB"
        New-Item -Path $keyA -Force | Out-Null
        New-Item -Path $keyB -Force | Out-Null
        New-ItemProperty -Path $keyA -Name 'V' -Value 1 -PropertyType DWord -Force | Out-Null
        New-ItemProperty -Path $keyB -Name 'V' -Value 1 -PropertyType DWord -Force | Out-Null

        Set-TmxRegistry -Path $keyA -Name 'V' -Value 2 -Type DWord -TweakId 'TWK-A'
        Set-TmxRegistry -Path $keyB -Name 'V' -Value 2 -Type DWord -TweakId 'TWK-B'

        $sum = Undo-TweakMaxing -StatePath $script:run.StatePath -TweakId 'TWK-A' 6> $null

        $sum.total | Should -Be 1
        (Get-ItemProperty -Path $keyA -Name 'V').V | Should -Be 1
        (Get-ItemProperty -Path $keyB -Name 'V').V | Should -Be 2
    }

    It 'B1: existiaAntes com tipoAnterior nulo vira falha explicita' {
        $key = "$script:TestRoot\TipoNulo"
        New-Item -Path $key -Force | Out-Null
        New-ItemProperty -Path $key -Name 'V' -Value 1 -PropertyType DWord -Force | Out-Null

        Set-TmxRegistry -Path $key -Name 'V' -Value 2 -Type DWord

        # forja o state.json: tipoAnterior desconhecido
        $json = Get-Content -LiteralPath $script:run.StatePath -Raw | ConvertFrom-Json
        $json.registros[0].tipoAnterior = $null
        $json | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $script:run.StatePath -Encoding UTF8

        $sum = Undo-TweakMaxing -StatePath $script:run.StatePath 6> $null

        $sum.falhas | Should -Be 1
        $sum.itens[0].detalhe | Should -Match 'tipo anterior desconhecido'
    }

    It 'M5: -Quiet nao chama Write-TmxRollbackReport' {
        $key = "$script:TestRoot\Quiet"
        New-Item -Path $key -Force | Out-Null
        New-ItemProperty -Path $key -Name 'V' -Value 1 -PropertyType DWord -Force | Out-Null
        Set-TmxRegistry -Path $key -Name 'V' -Value 2 -Type DWord

        Mock Write-TmxRollbackReport -ModuleName TweakMaxing { }

        Undo-TweakMaxing -StatePath $script:run.StatePath -Quiet 6> $null | Out-Null

        Should -Invoke Write-TmxRollbackReport -ModuleName TweakMaxing -Times 0
    }

    It 'despacho dinamico: tipo desconhecido com Undo-TmxFakeRecord definido e revertido; sem funcao e pulado' {
        function global:Undo-TmxFakeRecord {
            param([Parameter(Mandatory)] $Record)
            "fake revertido: $($Record.alvo)"
        }
        try {
            $json = Get-Content -LiteralPath $script:run.StatePath -Raw | ConvertFrom-Json
            $json.registros = @(
                [pscustomobject]@{
                    tweakId = 'F1'; tipo = 'fake'; alvo = 'alvo-fake'
                    detalhe = @{}; valorAnterior = $null; tipoAnterior = $null
                    existiaAntes = $false; valorNovo = $null
                    reversao = @{ tipo = 'nenhuma' }; status = 'aplicado'; aplicadoEm = (Get-Date).ToString('o'); erro = $null
                },
                [pscustomobject]@{
                    tweakId = 'S1'; tipo = 'semfuncao'; alvo = 'alvo-semfuncao'
                    detalhe = @{}; valorAnterior = $null; tipoAnterior = $null
                    existiaAntes = $false; valorNovo = $null
                    reversao = @{ tipo = 'nenhuma' }; status = 'aplicado'; aplicadoEm = (Get-Date).ToString('o'); erro = $null
                }
            )
            $json | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $script:run.StatePath -Encoding UTF8

            $sum = Undo-TweakMaxing -StatePath $script:run.StatePath 6> $null

            $itemFake = $sum.itens | Where-Object { $_.tweakId -eq 'F1' }
            $itemSem  = $sum.itens | Where-Object { $_.tweakId -eq 'S1' }

            $itemFake.resultado | Should -Be 'revertido'
            $itemFake.detalhe   | Should -Match 'fake revertido'
            $itemSem.resultado  | Should -Be 'pulado'
            $itemSem.detalhe    | Should -Match 'sem reversao automatica'
        } finally {
            Remove-Item function:global:Undo-TmxFakeRecord -ErrorAction SilentlyContinue
        }
    }
}
