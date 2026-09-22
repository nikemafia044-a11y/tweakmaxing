# Testes das guardas e utilitarios do nucleo (Logger, Backup) que nao exigem elevacao.

. "$PSScriptRoot\_Helpers.ps1"

BeforeAll {
    . "$PSScriptRoot\_Helpers.ps1"
    Import-TmxTestModule
    New-TmxTestHome | Out-Null
}

AfterAll {
    Remove-TmxTestHome
    Stop-TmxLogger
    Remove-Module TweakMaxing -Force -ErrorAction SilentlyContinue
}

Describe 'Assert-TmxGuards' -Tag 'Guard' {

    It 'retorna a estrutura esperada' {
        $g = Assert-TmxGuards -AllowUnelevated
        $g.PSObject.Properties.Name | Should -Contain 'ok'
        $g.PSObject.Properties.Name | Should -Contain 'bloqueios'
        $g.PSObject.Properties.Name | Should -Contain 'avisos'
        $g.contexto.build | Should -BeGreaterThan 0
        $g.contexto.PSObject.Properties.Name | Should -Contain 'isLaptop'
        $g.contexto.PSObject.Properties.Name | Should -Contain 'isVM'
    }

    It 'bloqueia quando a build minima e maior que a atual' {
        $g = Assert-TmxGuards -AllowUnelevated -MinBuild 999999
        $g.ok | Should -BeFalse
        ($g.bloqueios -join ' ') | Should -Match 'Build do Windows'
    }

    It 'bloqueia quando o espaco livre minimo e absurdo' {
        $g = Assert-TmxGuards -AllowUnelevated -MinFreeGB 99999
        $g.ok | Should -BeFalse
        ($g.bloqueios -join ' ') | Should -Match 'Espaco livre'
    }

    It 'sem -AllowUnelevated, falta de elevacao vira bloqueio' {
        if (Test-TmxElevation) { Set-ItResult -Skipped -Because 'sessao ja esta elevada' }
        $g = Assert-TmxGuards
        ($g.bloqueios -join ' ') | Should -Match 'Administrador'
    }
}

Describe 'Test-TmxPendingReboot' -Tag 'Guard' {
    It 'retorna pending como booleano e razoes como array' {
        $r = Test-TmxPendingReboot
        $r.pending | Should -BeOfType [bool]
        , $r.razoes | Should -BeOfType [array]
    }
}

Describe 'Logger e estrutura da execucao' -Tag 'Backup' {

    It 'New-TmxRun cria pasta, state.json e events.jsonl' {
        $run = New-TmxRun
        Test-Path $run.RunPath      | Should -BeTrue
        Test-Path $run.StatePath    | Should -BeTrue
        Test-Path $run.RegBackupPath | Should -BeTrue
        Test-Path (Join-Path $run.RunPath 'events.jsonl') | Should -BeTrue
    }

    It 'Write-TmxLog anexa uma linha JSON valida' {
        $run = New-TmxRun
        Write-TmxLog -Level INFO -Message 'teste de log' -Data @{ chave = 'valor' }
        $linhas = Get-Content (Join-Path $run.RunPath 'events.jsonl')
        $ultima = $linhas[-1] | ConvertFrom-Json
        $ultima.message    | Should -Be 'teste de log'
        $ultima.data.chave | Should -Be 'valor'
    }

    It 'state.json de execucao vazia tem zero registros' {
        $run = New-TmxRun
        (Import-TmxState -StatePath $run.StatePath).Count | Should -Be 0
    }

    It 'state.json vazio grava "registros": [] no arquivo cru, nunca null' {
        $run = New-TmxRun
        $raw = Get-Content $run.StatePath -Raw
        $raw | Should -Not -Match '"registros":\s*null'
        $raw | Should -Match '"registros":\s*\['
    }
}

Describe 'ConvertTo-TmxRegExportPath' -Tag 'Backup' {
    It 'converte HKLM:\ para HKEY_LOCAL_MACHINE\' {
        ConvertTo-TmxRegExportPath 'HKLM:\SOFTWARE\Teste' | Should -Be 'HKEY_LOCAL_MACHINE\SOFTWARE\Teste'
    }
    It 'converte HKCU:\ para HKEY_CURRENT_USER\' {
        ConvertTo-TmxRegExportPath 'HKCU:\Software\X' | Should -Be 'HKEY_CURRENT_USER\Software\X'
    }
    It 'mantem caminho ja no formato do reg.exe' {
        ConvertTo-TmxRegExportPath 'HKEY_USERS\.DEFAULT' | Should -Be 'HKEY_USERS\.DEFAULT'
    }
}

Describe 'Backup-TmxRegistryHive' -Tag 'Backup' {
    It 'exporta um ramo HKCU para .reg' {
        $run = New-TmxRun
        $key = 'HKCU:\Software\TweakMaxing_Tests\Export'
        New-Item -Path $key -Force | Out-Null
        New-ItemProperty -Path $key -Name 'V' -Value 1 -PropertyType DWord -Force | Out-Null

        $file = Backup-TmxRegistryHive -Path $key

        $file | Should -Not -BeNullOrEmpty
        Test-Path $file | Should -BeTrue
        (Get-Content $file -Raw) | Should -Match 'TweakMaxing_Tests\\Export'

        Remove-TmxTestKey
    }
}
