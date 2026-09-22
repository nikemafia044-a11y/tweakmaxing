# Testes de Undo-TweakMaxing: valor alterado, valor criado do zero, chave inexistente,
# ordem inversa e recuperacao apos morte do processo (estado apenas em disco).

. "$PSScriptRoot\_Helpers.ps1"

BeforeAll {
    . "$PSScriptRoot\_Helpers.ps1"
    Import-TmxTestModule
    New-TmxTestHome | Out-Null
    $script:TestSubKey = 'Core\Rollback'
    $script:TestRoot   = "HKCU:\Software\TweakMaxing_Tests\$script:TestSubKey"
}

AfterAll {
    Remove-TmxTestKey -SubKey $script:TestSubKey
    Remove-TmxTestHome
    Stop-TmxLogger
    Remove-Module TweakMaxing -Force -ErrorAction SilentlyContinue
}

Describe 'Undo-TweakMaxing' -Tag 'Rollback' {

    BeforeEach {
        Remove-TmxTestKey -SubKey $script:TestSubKey
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

        # a forja so vale no arquivo; sem recarregar, o run ainda ativo usaria a
        # memoria (onde o registro continua 'aplicado', nao testando o cenario).
        Import-TmxTestModule
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

        # forca a leitura do arquivo forjado (run ativo usaria a memoria intacta)
        Import-TmxTestModule
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

        # forca a leitura do arquivo forjado (run ativo usaria a memoria intacta)
        Import-TmxTestModule
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

            # forca a leitura do arquivo forjado (run ativo usaria a memoria, vazia).
            # funcoes global: sobrevivem ao reimport do modulo (escopos distintos).
            Import-TmxTestModule

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

    It 'despacho dinamico: registro sem tipo vira falha explicita' {
        $json = Get-Content -LiteralPath $script:run.StatePath -Raw | ConvertFrom-Json
        $json.registros = @(
            [pscustomobject]@{
                tweakId = 'SEMTIPO'; tipo = $null; alvo = 'alvo-sem-tipo'
                detalhe = @{}; valorAnterior = $null; tipoAnterior = $null
                existiaAntes = $false; valorNovo = $null
                reversao = @{ tipo = 'nenhuma' }; status = 'aplicado'; aplicadoEm = (Get-Date).ToString('o'); erro = $null
            }
        )
        $json | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $script:run.StatePath -Encoding UTF8
        Import-TmxTestModule

        $sum = Undo-TweakMaxing -StatePath $script:run.StatePath 6> $null

        $sum.falhas | Should -Be 1
        $sum.itens[0].detalhe | Should -Match 'registro sem tipo'
    }

    It 'M2: ancestral que ganhou valor Default de terceiro e preservado' {
        $base = $script:TestRoot
        $path = "$base\A\B\C"

        Set-TmxRegistry -Path $path -Name 'V' -Value 1 -Type DWord | Out-Null
        # outro programa gravou um valor (Default) na chave intermediaria
        Set-Item -LiteralPath "$base\A" -Value 'terceiro'

        Undo-TweakMaxing -StatePath $script:run.StatePath 6> $null | Out-Null

        Test-Path "$base\A\B" | Should -BeFalse
        Test-Path "$base\A"   | Should -BeTrue
        (Get-Item -LiteralPath "$base\A").GetValue('') | Should -Be 'terceiro'
    }

    It '-WhatIf mantem status "aplicado" no arquivo' {
        $key = "$script:TestRoot\WhatIfArquivo"
        New-Item -Path $key -Force | Out-Null
        New-ItemProperty -Path $key -Name 'V' -Value 1 -PropertyType DWord -Force | Out-Null
        Set-TmxRegistry -Path $key -Name 'V' -Value 2 -Type DWord

        Undo-TweakMaxing -StatePath $script:run.StatePath -WhatIf 6> $null | Out-Null

        $st = @(Import-TmxState -StatePath $script:run.StatePath)
        $st[0].status | Should -Be 'aplicado'
    }

    It 'lost-update: run ativo preserva registro concorrente apos novo Set-TmxRegistry' {
        $key1 = "$script:TestRoot\LU1"
        $key2 = "$script:TestRoot\LU2"
        $key3 = "$script:TestRoot\LU3"
        New-Item -Path $key1 -Force | Out-Null
        New-Item -Path $key2 -Force | Out-Null
        New-ItemProperty -Path $key1 -Name 'V' -Value 1 -PropertyType DWord -Force | Out-Null
        New-ItemProperty -Path $key2 -Name 'V' -Value 1 -PropertyType DWord -Force | Out-Null

        Set-TmxRegistry -Path $key1 -Name 'V' -Value 2 -Type DWord -TweakId 'LU-1'
        Set-TmxRegistry -Path $key2 -Name 'V' -Value 2 -Type DWord -TweakId 'LU-2'

        # o run continua ativo neste mesmo processo: Undo deve operar sobre a
        # memoria para nao perder a marcacao quando o terceiro Set gravar depois.
        Undo-TweakMaxing -StatePath $script:run.StatePath -TweakId 'LU-1' 6> $null | Out-Null

        Set-TmxRegistry -Path $key3 -Name 'V' -Value 5 -Type DWord -TweakId 'LU-3'

        $st = @(Import-TmxState -StatePath $script:run.StatePath)
        $st.Count | Should -Be 3
        ($st | Where-Object { $_.tweakId -eq 'LU-1' }).status | Should -Be 'revertido'
        ($st | Where-Object { $_.tweakId -eq 'LU-2' }).status | Should -Be 'aplicado'
        ($st | Where-Object { $_.tweakId -eq 'LU-3' }).status | Should -Be 'aplicado'
    }

    It 'merge sem run ativo: preserva registro adicionado por outro escritor durante a reversao' {
        $keyA = "$script:TestRoot\CA"
        $keyB = "$script:TestRoot\CB"
        $keyC = "$script:TestRoot\CC"
        New-Item -Path $keyA -Force | Out-Null
        New-Item -Path $keyB -Force | Out-Null
        New-Item -Path $keyC -Force | Out-Null
        New-ItemProperty -Path $keyA -Name 'V' -Value 1 -PropertyType DWord -Force | Out-Null
        New-ItemProperty -Path $keyB -Name 'V' -Value 1 -PropertyType DWord -Force | Out-Null
        New-ItemProperty -Path $keyC -Name 'V' -Value 1 -PropertyType DWord -Force | Out-Null

        Set-TmxRegistry -Path $keyA -Name 'V' -Value 2 -Type DWord -TweakId 'C-A'
        Set-TmxRegistry -Path $keyB -Name 'V' -Value 2 -Type DWord -TweakId 'C-B'
        Set-TmxRegistry -Path $keyC -Name 'V' -Value 2 -Type DWord -TweakId 'C-C'
        $statePath = $script:run.StatePath

        # simula outro processo: perde o run ativo em memoria
        Import-TmxTestModule
        (Get-TmxState).Count | Should -Be 0

        Mock Undo-TmxRegistryRecord -ModuleName TweakMaxing {
            param($Record)
            # simula um terceiro escritor gravando um novo registro durante a nossa reversao
            $json = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
            $novo = [pscustomobject]@{
                tweakId = 'CONCORRENTE'; tipo = 'registry'; alvo = 'x::y'; seq = 999
                detalhe = @{}; valorAnterior = $null; tipoAnterior = $null
                existiaAntes = $false; valorNovo = $null
                reversao = @{ tipo = 'nenhuma' }; status = 'aplicado'; aplicadoEm = (Get-Date).ToString('o'); erro = $null
            }
            $json.registros = @($json.registros) + $novo
            $json | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $statePath -Encoding UTF8
            "revertido (mock) para $($Record.alvo)"
        }

        Undo-TweakMaxing -StatePath $statePath -TweakId 'C-A' 6> $null | Out-Null

        $st = @(Import-TmxState -StatePath $statePath)
        $st.Count | Should -Be 4
        ($st | Where-Object { $_.tweakId -eq 'C-A' }).status | Should -Be 'revertido'
        ($st | Where-Object { $_.tweakId -eq 'C-B' }).status | Should -Be 'aplicado'
        ($st | Where-Object { $_.tweakId -eq 'C-C' }).status | Should -Be 'aplicado'
        ($st | Where-Object { $_.tweakId -eq 'CONCORRENTE' }).status | Should -Be 'aplicado'
    }
}

Describe 'Save-TmxState' -Tag 'Rollback' {

    BeforeEach {
        Remove-TmxTestKey -SubKey $script:TestSubKey
        New-Item -Path $script:TestRoot -Force | Out-Null
        $script:run = New-TmxRun
    }

    It 'preserva registro estrangeiro escrito diretamente no arquivo (run ativo)' {
        $key1 = "$script:TestRoot\Estr1"
        New-Item -Path $key1 -Force | Out-Null
        New-ItemProperty -Path $key1 -Name 'V' -Value 1 -PropertyType DWord -Force | Out-Null

        Set-TmxRegistry -Path $key1 -Name 'V' -Value 2 -Type DWord -TweakId 'MEM-1'
        $statePath = $script:run.StatePath

        # simula outro escritor gravando diretamente no arquivo, sem passar pela memoria
        $json = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        $estranho = [pscustomobject]@{
            tweakId = 'ESTRANHO'; tipo = 'registry'; alvo = 'x::y'; seq = 777
            detalhe = @{}; valorAnterior = $null; tipoAnterior = $null
            existiaAntes = $false; valorNovo = $null
            reversao = @{ tipo = 'nenhuma' }; status = 'aplicado'; aplicadoEm = (Get-Date).ToString('o'); erro = $null
        }
        $json.registros = @($json.registros) + $estranho
        $json | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $statePath -Encoding UTF8

        $key2 = "$script:TestRoot\Estr2"
        New-Item -Path $key2 -Force | Out-Null
        Set-TmxRegistry -Path $key2 -Name 'V' -Value 9 -Type DWord -TweakId 'MEM-2' 3> $null

        $st = @(Import-TmxState -StatePath $statePath)
        $st.Count | Should -Be 3
        ($st | Where-Object { $_.tweakId -eq 'MEM-1' }).status    | Should -Be 'aplicado'
        ($st | Where-Object { $_.tweakId -eq 'MEM-2' }).status    | Should -Be 'aplicado'
        ($st | Where-Object { $_.tweakId -eq 'ESTRANHO' }).seq    | Should -Be 777
        ($st | Where-Object { $_.tweakId -eq 'ESTRANHO' }).status | Should -Be 'aplicado'

        # o estrangeiro nunca entrou na memoria deste processo
        (Get-TmxState).Count | Should -Be 2
    }
}

Describe 'Save-TmxStateFile' -Tag 'Rollback' {

    BeforeEach {
        Remove-TmxTestKey -SubKey $script:TestSubKey
        New-Item -Path $script:TestRoot -Force | Out-Null
        $script:run = New-TmxRun
    }

    It 'seq duplicado e ambiguo mesmo apos desempate: mudanca nao aplicada e seq retornado' {
        $statePath = $script:run.StatePath

        $json = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        $json.registros = @(
            [pscustomobject]@{
                tweakId = 'DUP'; tipo = 'registry'; alvo = 'a::b'; seq = 5
                detalhe = @{}; valorAnterior = $null; tipoAnterior = $null
                existiaAntes = $false; valorNovo = $null
                reversao = @{ tipo = 'nenhuma' }; status = 'aplicado'; aplicadoEm = (Get-Date).ToString('o'); erro = $null
            },
            [pscustomobject]@{
                tweakId = 'OK'; tipo = 'registry'; alvo = 'c::d'; seq = 6
                detalhe = @{}; valorAnterior = $null; tipoAnterior = $null
                existiaAntes = $false; valorNovo = $null
                reversao = @{ tipo = 'nenhuma' }; status = 'aplicado'; aplicadoEm = (Get-Date).ToString('o'); erro = $null
            }
        )
        $json | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $statePath -Encoding UTF8

        # duas mudancas com o MESMO seq=5, tweakId e alvo - ambiguo mesmo apos
        # desempate por (seq, tweakId, alvo), pois sao indistinguiveis entre si.
        $mudanca1  = [pscustomobject]@{ tweakId = 'DUP'; alvo = 'a::b'; seq = 5; status = 'revertido'; revertidoEm = (Get-Date).ToString('o') }
        $mudanca2  = [pscustomobject]@{ tweakId = 'DUP'; alvo = 'a::b'; seq = 5; status = 'revertido'; revertidoEm = (Get-Date).ToString('o') }
        $mudancaOk = [pscustomobject]@{ tweakId = 'OK';  alvo = 'c::d'; seq = 6; status = 'revertido'; revertidoEm = (Get-Date).ToString('o') }

        $naoAplicados = Save-TmxStateFile -StatePath $statePath -Registros @($mudanca1, $mudanca2, $mudancaOk) 3> $null

        @($naoAplicados) | Should -Be @(5)

        $st = @(Import-TmxState -StatePath $statePath)
        ($st | Where-Object { $_.tweakId -eq 'DUP' }).status | Should -Be 'aplicado'
        ($st | Where-Object { $_.tweakId -eq 'OK' }).status  | Should -Be 'revertido'
    }

    It 'seq duplicado com tweakId/alvo diferentes e desempatado corretamente' {
        $statePath = $script:run.StatePath

        $json = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        $json.registros = @(
            [pscustomobject]@{
                tweakId = 'A'; tipo = 'registry'; alvo = 'x::y'; seq = 5
                detalhe = @{}; valorAnterior = $null; tipoAnterior = $null
                existiaAntes = $false; valorNovo = $null
                reversao = @{ tipo = 'nenhuma' }; status = 'aplicado'; aplicadoEm = (Get-Date).ToString('o'); erro = $null
            },
            [pscustomobject]@{
                tweakId = 'B'; tipo = 'registry'; alvo = 'p::q'; seq = 5
                detalhe = @{}; valorAnterior = $null; tipoAnterior = $null
                existiaAntes = $false; valorNovo = $null
                reversao = @{ tipo = 'nenhuma' }; status = 'aplicado'; aplicadoEm = (Get-Date).ToString('o'); erro = $null
            }
        )
        $json | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $statePath -Encoding UTF8

        $mudancaA = [pscustomobject]@{ tweakId = 'A'; alvo = 'x::y'; seq = 5; status = 'revertido'; revertidoEm = (Get-Date).ToString('o') }
        $mudancaB = [pscustomobject]@{ tweakId = 'B'; alvo = 'p::q'; seq = 5; status = 'revertido'; revertidoEm = (Get-Date).ToString('o') }

        $naoAplicados = Save-TmxStateFile -StatePath $statePath -Registros @($mudancaA, $mudancaB)

        @($naoAplicados).Count | Should -Be 0

        $st = @(Import-TmxState -StatePath $statePath)
        ($st | Where-Object { $_.tweakId -eq 'A' }).status | Should -Be 'revertido'
        ($st | Where-Object { $_.tweakId -eq 'B' }).status | Should -Be 'revertido'
    }
}
