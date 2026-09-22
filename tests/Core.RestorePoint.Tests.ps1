# Testes do ponto de restauracao.
# As etapas que exigem elevacao (protecao, listagem, checkpoint) sao mockadas
# dentro do modulo. O throttle usa o Set-TmxRegistry REAL apontado para HKCU,
# entao a captura/restauracao do valor anterior e exercitada de verdade.

. "$PSScriptRoot\_Helpers.ps1"

BeforeAll {
    . "$PSScriptRoot\_Helpers.ps1"
    Import-TmxTestModule
    New-TmxTestHome | Out-Null
    $script:TestRoot    = 'HKCU:\Software\TweakMaxing_Tests'
    $script:ThrottleKey = "$script:TestRoot\SystemRestore"
    $script:ThrottleVal = 'SystemRestorePointCreationFrequency'

    function script:Set-ProtectionEnabled {
        Mock Get-TmxSystemProtectionStatus -ModuleName TweakMaxing {
            [pscustomobject]@{ enabled = $true; motivo = 'mock'; bloqueadoPorPolitica = $false }
        }
    }
    # Simula o Windows: o ponto so aparece na lista depois que o checkpoint rodou.
    function script:Set-WindowsBehavesNormally {
        $global:Tmx_Created = $false
        Mock Invoke-TmxCheckpoint -ModuleName TweakMaxing { $global:Tmx_Created = $true }
        Mock Get-TmxRestorePoints -ModuleName TweakMaxing {
            if ($global:Tmx_Created) { @([pscustomobject]@{ SequenceNumber = 42; Description = 'TweakMaxing teste' }) }
            else                      { @() }
        }
    }
}

AfterAll {
    Remove-TmxTestKey
    Remove-TmxTestHome
    Remove-Variable -Name Tmx_Created, Tmx_Enabled -Scope Global -ErrorAction SilentlyContinue
    Stop-TmxLogger
    Remove-Module TweakMaxing -Force -ErrorAction SilentlyContinue
}

Describe 'New-TmxRestorePoint' -Tag 'RestorePoint' {

    BeforeEach {
        Remove-TmxTestKey
        New-Item -Path $script:ThrottleKey -Force | Out-Null
        New-ItemProperty -Path $script:ThrottleKey -Name $script:ThrottleVal -Value 1440 -PropertyType DWord -Force | Out-Null
        $script:run = New-TmxRun
    }

    It 'cria, verifica e restaura o throttle no caminho feliz' {
        Set-ProtectionEnabled
        Set-WindowsBehavesNormally

        $r = New-TmxRestorePoint -Description 'TweakMaxing teste' -ThrottleKeyPath $script:ThrottleKey

        $r.ok                 | Should -BeTrue
        $r.etapa              | Should -Be 'concluido'
        $r.sequenceNumber     | Should -Be 42
        $r.throttleRestaurado | Should -BeTrue
        (Get-ItemProperty -Path $script:ThrottleKey -Name $script:ThrottleVal).$($script:ThrottleVal) | Should -Be 1440
        Should -Invoke Invoke-TmxCheckpoint -ModuleName TweakMaxing -Times 1 -Exactly
    }

    It 'zera o throttle DURANTE o checkpoint' {
        Set-ProtectionEnabled
        $global:Tmx_Created = $false
        Mock Get-TmxRestorePoints -ModuleName TweakMaxing {
            if ($global:Tmx_Created) { @([pscustomobject]@{ SequenceNumber = 1; Description = 'TweakMaxing teste' }) } else { @() }
        }
        Mock Invoke-TmxCheckpoint -ModuleName TweakMaxing {
            $global:Tmx_Created = $true
            $global:Tmx_ThrottleDuringCheckpoint = (Get-ItemProperty -Path 'HKCU:\Software\TweakMaxing_Tests\SystemRestore' -Name SystemRestorePointCreationFrequency).SystemRestorePointCreationFrequency
        }

        New-TmxRestorePoint -Description 'TweakMaxing teste' -ThrottleKeyPath $script:ThrottleKey | Out-Null

        $global:Tmx_ThrottleDuringCheckpoint | Should -Be 0
        Remove-Variable -Name Tmx_ThrottleDuringCheckpoint -Scope Global
    }

    It 'restaura o throttle mesmo quando o checkpoint lanca erro' {
        Set-ProtectionEnabled
        Mock Get-TmxRestorePoints -ModuleName TweakMaxing { @() }
        Mock Invoke-TmxCheckpoint -ModuleName TweakMaxing { throw 'Acesso negado (simulado)' }

        $r = New-TmxRestorePoint -Description 'TweakMaxing teste' -ThrottleKeyPath $script:ThrottleKey 2> $null

        $r.ok    | Should -BeFalse
        $r.etapa | Should -Be 'checkpoint'
        $r.erro  | Should -Match 'Acesso negado'
        $r.throttleRestaurado | Should -BeTrue
        (Get-ItemProperty -Path $script:ThrottleKey -Name $script:ThrottleVal).$($script:ThrottleVal) | Should -Be 1440

        # o registro do throttle no state.json ficou como revertido - Undo nao vai tocar nele
        $st = Import-TmxState -StatePath $script:run.StatePath
        ($st | Where-Object { $_.tweakId -eq 'RP-THROTTLE' }).status | Should -Be 'revertido'
    }

    It 'falha na verificacao quando o Windows recusa silenciosamente' {
        Set-ProtectionEnabled
        Mock Invoke-TmxCheckpoint -ModuleName TweakMaxing { }          # nao lanca, nao cria
        Mock Get-TmxRestorePoints -ModuleName TweakMaxing { @() }

        $r = New-TmxRestorePoint -Description 'TweakMaxing teste' -ThrottleKeyPath $script:ThrottleKey 2> $null

        $r.ok    | Should -BeFalse
        $r.etapa | Should -Be 'verificacao'
        $r.erro  | Should -Match 'nao apareceu'
        $r.throttleRestaurado | Should -BeTrue
    }

    It 'nao confunde um ponto antigo com a mesma descricao' {
        Set-ProtectionEnabled
        Mock Invoke-TmxCheckpoint -ModuleName TweakMaxing { }
        # ja existia um ponto com a mesma descricao; nenhum novo foi criado
        Mock Get-TmxRestorePoints -ModuleName TweakMaxing {
            @([pscustomobject]@{ SequenceNumber = 7; Description = 'TweakMaxing teste' })
        }

        $r = New-TmxRestorePoint -Description 'TweakMaxing teste' -ThrottleKeyPath $script:ThrottleKey 2> $null

        $r.ok    | Should -BeFalse
        $r.etapa | Should -Be 'verificacao'
    }

    It 'habilita a Protecao do Sistema quando desabilitada e segue' {
        $global:Tmx_Enabled = $false
        Mock Get-TmxSystemProtectionStatus -ModuleName TweakMaxing {
            [pscustomobject]@{ enabled = $global:Tmx_Enabled; motivo = 'mock'; bloqueadoPorPolitica = $false }
        }
        Mock Enable-TmxSystemProtection -ModuleName TweakMaxing { $global:Tmx_Enabled = $true; $true }
        Set-WindowsBehavesNormally

        $r = New-TmxRestorePoint -Description 'TweakMaxing teste' -ThrottleKeyPath $script:ThrottleKey 3> $null

        $r.ok | Should -BeTrue
        $r.protecaoHabilitadaPorNos | Should -BeTrue
        Should -Invoke Enable-TmxSystemProtection -ModuleName TweakMaxing -Times 1 -Exactly
    }

    It 'aborta na etapa protecao se nao conseguir habilitar' {
        Mock Get-TmxSystemProtectionStatus -ModuleName TweakMaxing {
            [pscustomobject]@{ enabled = $false; motivo = 'mock'; bloqueadoPorPolitica = $false }
        }
        Mock Enable-TmxSystemProtection -ModuleName TweakMaxing { $true }
        Mock Invoke-TmxCheckpoint -ModuleName TweakMaxing { }

        $r = New-TmxRestorePoint -Description 'TweakMaxing teste' -ThrottleKeyPath $script:ThrottleKey 2> $null 3> $null

        $r.ok    | Should -BeFalse
        $r.etapa | Should -Be 'protecao'
        Should -Invoke Invoke-TmxCheckpoint -ModuleName TweakMaxing -Times 0
        # throttle nem chegou a ser tocado
        (Get-ItemProperty -Path $script:ThrottleKey -Name $script:ThrottleVal).$($script:ThrottleVal) | Should -Be 1440
        @(Import-TmxState -StatePath $script:run.StatePath).Count | Should -Be 0
    }

    It 'aborta por politica de grupo sem tentar habilitar' {
        Mock Get-TmxSystemProtectionStatus -ModuleName TweakMaxing {
            [pscustomobject]@{ enabled = $false; motivo = 'DisableSR=1'; bloqueadoPorPolitica = $true }
        }
        Mock Enable-TmxSystemProtection -ModuleName TweakMaxing { $true }

        $r = New-TmxRestorePoint -Description 'TweakMaxing teste' -ThrottleKeyPath $script:ThrottleKey 2> $null

        $r.ok    | Should -BeFalse
        $r.erro  | Should -Match 'politica'
        Should -Invoke Enable-TmxSystemProtection -ModuleName TweakMaxing -Times 0
    }

    It 'remove o throttle ao final se ele nao existia antes' {
        Remove-ItemProperty -Path $script:ThrottleKey -Name $script:ThrottleVal -Force
        Set-ProtectionEnabled
        Set-WindowsBehavesNormally

        $r = New-TmxRestorePoint -Description 'TweakMaxing teste' -ThrottleKeyPath $script:ThrottleKey

        $r.ok | Should -BeTrue
        (Get-Item -Path $script:ThrottleKey).GetValueNames() | Should -Not -Contain $script:ThrottleVal
    }

    It 'B2: New-TmxRestorePoint -WhatIf nao zera o throttle nem chama o checkpoint' {
        Set-ProtectionEnabled
        Mock Invoke-TmxCheckpoint -ModuleName TweakMaxing { throw 'nao deveria ser chamado' }

        $r = New-TmxRestorePoint -Description 'TweakMaxing teste' -ThrottleKeyPath $script:ThrottleKey -WhatIf

        $r.ok    | Should -BeFalse
        $r.etapa | Should -Be 'whatif'
        Should -Invoke Invoke-TmxCheckpoint -ModuleName TweakMaxing -Times 0
        (Get-ItemProperty -Path $script:ThrottleKey -Name $script:ThrottleVal).$($script:ThrottleVal) | Should -Be 1440
        @(Import-TmxState -StatePath $script:run.StatePath).Count | Should -Be 0
    }
}

Describe 'Invoke-TmxRestorePointStage' -Tag 'RestorePoint' {

    BeforeEach {
        Remove-TmxTestKey
        New-Item -Path $script:ThrottleKey -Force | Out-Null
        New-ItemProperty -Path $script:ThrottleKey -Name $script:ThrottleVal -Value 1440 -PropertyType DWord -Force | Out-Null
        $script:run = New-TmxRun
    }

    It 'DryRun prossegue sem criar ponto' {
        Mock New-TmxRestorePoint -ModuleName TweakMaxing { throw 'nao deveria ser chamado' }

        $s = Invoke-TmxRestorePointStage -DryRun

        $s.proceed  | Should -BeTrue
        $s.pulado   | Should -BeTrue
        $s.exitCode | Should -Be 0
        Should -Invoke New-TmxRestorePoint -ModuleName TweakMaxing -Times 0
    }

    It '-SkipRestorePoint sem -IUnderstandTheRisk retorna exitCode 2' {
        $s = Invoke-TmxRestorePointStage -SkipRestorePoint
        $s.proceed  | Should -BeFalse
        $s.exitCode | Should -Be 2
        $s.mensagem | Should -Match 'IUnderstandTheRisk'
    }

    It 'M4: -SkipRestorePoint sem -ConfirmSkip retorna exitCode 2' {
        $s = Invoke-TmxRestorePointStage -SkipRestorePoint -IUnderstandTheRisk
        $s.proceed  | Should -BeFalse
        $s.exitCode | Should -Be 2
        $s.mensagem | Should -Match 'confirmacao de pulo'
    }

    It 'M4: -ConfirmSkip que retorna $true prossegue como pulado' {
        Mock New-TmxRestorePoint -ModuleName TweakMaxing { throw 'nao deveria ser chamado' }

        $s = Invoke-TmxRestorePointStage -SkipRestorePoint -IUnderstandTheRisk -ConfirmSkip { $true } 6> $null

        $s.proceed  | Should -BeTrue
        $s.pulado   | Should -BeTrue
        $s.exitCode | Should -Be 0
        Should -Invoke New-TmxRestorePoint -ModuleName TweakMaxing -Times 0
    }

    It 'M4: -ConfirmSkip que retorna $false retorna exitCode 2' {
        $s = Invoke-TmxRestorePointStage -SkipRestorePoint -IUnderstandTheRisk -ConfirmSkip { $false }

        $s.proceed  | Should -BeFalse
        $s.exitCode | Should -Be 2
    }

    It 'sucesso do ponto prossegue com exitCode 0' {
        Mock New-TmxRestorePoint -ModuleName TweakMaxing {
            [pscustomobject]@{ ok = $true; etapa = 'concluido'; sequenceNumber = 9; descricao = 'x'; erro = $null }
        }
        $s = Invoke-TmxRestorePointStage
        $s.proceed  | Should -BeTrue
        $s.exitCode | Should -Be 0
        $s.mensagem | Should -Match '#9'
    }

    It 'falha do ponto aborta com exitCode 2 sem deixar nada aplicado (fluxo real com checkpoint falhando)' {
        Mock Get-TmxSystemProtectionStatus -ModuleName TweakMaxing {
            [pscustomobject]@{ enabled = $true; motivo = 'mock'; bloqueadoPorPolitica = $false }
        }
        Mock Get-TmxRestorePoints -ModuleName TweakMaxing { @() }
        Mock Invoke-TmxCheckpoint -ModuleName TweakMaxing { throw 'falha simulada' }

        $s = Invoke-TmxRestorePointStage -ThrottleKeyPath $script:ThrottleKey 2> $null

        $s.proceed  | Should -BeFalse
        $s.exitCode | Should -Be 2
        $s.mensagem | Should -Match 'checkpoint'
        $s.mensagem | Should -Match 'Nada foi alterado'

        # nenhum registro ficou 'aplicado'; o throttle esta 'revertido' e o valor original de volta
        $st = @(Import-TmxState -StatePath $script:run.StatePath)
        @($st | Where-Object { $_.status -eq 'aplicado' }).Count | Should -Be 0
        (Get-ItemProperty -Path $script:ThrottleKey -Name $script:ThrottleVal).$($script:ThrottleVal) | Should -Be 1440
    }
}
