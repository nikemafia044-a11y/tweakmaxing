# Testes do loader e validador do catalogo (Engine/Catalog.ps1).

. "$PSScriptRoot\_Helpers.ps1"

BeforeAll {
    . "$PSScriptRoot\_Helpers.ps1"
    Import-TmxTestModule
    New-TmxTestHome | Out-Null

    # Funcoes 'funcao' exigidas pelo item FUN-002 do catalogo de teste.
    function global:Set-TmxDummy  { param($Tweak, $Profile, $Parametros) [pscustomobject]@{ ok = $true } }
    function global:Undo-TmxDummy { param($Estado) [pscustomobject]@{ ok = $true } }
    function global:Test-TmxDummy { param($Tweak, $Profile) [pscustomobject]@{ aplicado = $false } }

    $script:CatalogPath = Join-Path $PSScriptRoot 'fixtures\catalog-min.json'
    $script:Catalog     = Get-TmxCatalog -Path $script:CatalogPath

    function script:Get-TmxTestCatalogClone {
        # Clone profundo: cada teste de mutacao precisa de sua propria copia.
        @($script:Catalog | ConvertTo-Json -Depth 12 | ConvertFrom-Json)
    }

    function script:Find-TmxTestItem {
        param($Catalog, [string] $Id)
        $Catalog | Where-Object { $_.id -eq $Id } | Select-Object -First 1
    }
}

AfterAll {
    Remove-Item Function:\Set-TmxDummy, Function:\Undo-TmxDummy, Function:\Test-TmxDummy -ErrorAction SilentlyContinue
    Remove-TmxTestHome
    Stop-TmxLogger
    Remove-Module TweakMaxing -Force -ErrorAction SilentlyContinue
}

Describe 'Get-TmxCatalog' -Tag 'Catalog' {

    It 'carrega o catalogo-min.json com os 7 itens esperados' {
        $script:Catalog.Count | Should -Be 7
        ($script:Catalog | ForEach-Object { $_.id }) | Should -Contain 'REG-001'
        ($script:Catalog | ForEach-Object { $_.id }) | Should -Contain 'FUN-002'
    }

    It 'concatena todos os tweaks*.json de um diretorio, ordenados por nome' {
        $dir = Join-Path ([System.IO.Path]::GetTempPath()) ('TmxCatalogTest_{0}' -f ([guid]::NewGuid().ToString('N')))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        try {
            @{ tweaks = @($script:Catalog | Where-Object { $_.id -eq 'REG-001' }) } | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $dir 'tweaks-a.json') -Encoding UTF8
            @{ tweaks = @($script:Catalog | Where-Object { $_.id -eq 'FOL-003' }) } | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $dir 'tweaks-b.json') -Encoding UTF8
            # Nao deve ser pego: nao bate no filtro tweaks*.json.
            @{ tweaks = @($script:Catalog | Where-Object { $_.id -eq 'IRR-004' }) } | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $dir 'outro.json') -Encoding UTF8

            $c = Get-TmxCatalog -Path $dir
            $c.Count | Should -Be 2
            ($c | ForEach-Object { $_.id }) | Should -Contain 'REG-001'
            ($c | ForEach-Object { $_.id }) | Should -Contain 'FOL-003'
            ($c | ForEach-Object { $_.id }) | Should -Not -Contain 'IRR-004'
        } finally {
            Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'aceita um caminho de arquivo unico e carrega so aquele arquivo' {
        $c = Get-TmxCatalog -Path $script:CatalogPath
        $c.Count | Should -Be 7
    }

    It 'lanca com mensagem clara quando o diretorio nao tem tweaks*.json' {
        $dir = Join-Path ([System.IO.Path]::GetTempPath()) ('TmxCatalogVazio_{0}' -f ([guid]::NewGuid().ToString('N')))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        try {
            { Get-TmxCatalog -Path $dir } | Should -Throw '*tweaks*'
        } finally {
            Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'lanca quando o caminho nao existe' {
        { Get-TmxCatalog -Path 'C:\caminho\que\nao\existe\de\jeito\nenhum' } | Should -Throw
    }
}

Describe 'Test-TmxCatalog' -Tag 'Catalog' {

    It 'aceita o catalogo-min.json sem erros' {
        $r = Test-TmxCatalog -Catalog $script:Catalog
        $r.ok | Should -BeTrue -Because ($r.erros -join '; ')
        $r.total | Should -Be 7
        $r.erros.Count | Should -Be 0
    }

    It 'rejeita id duplicado' {
        $c = Get-TmxTestCatalogClone
        (Find-TmxTestItem $c 'FUN-002').id = 'REG-001'
        $r = Test-TmxCatalog -Catalog $c
        $r.ok | Should -BeFalse
        ($r.erros -join '; ') | Should -Match 'duplicado'
    }

    It 'rejeita id fora do formato CAT-NNN' {
        $c = Get-TmxTestCatalogClone
        (Find-TmxTestItem $c 'REG-001').id = 'reg-1'
        $r = Test-TmxCatalog -Catalog $c
        $r.ok | Should -BeFalse
        ($r.erros -join '; ') | Should -Match 'formato'
    }

    It 'rejeita campo obrigatorio vazio (nome)' {
        $c = Get-TmxTestCatalogClone
        (Find-TmxTestItem $c 'REG-001').nome = ''
        $r = Test-TmxCatalog -Catalog $c
        $r.ok | Should -BeFalse
        ($r.erros -join '; ') | Should -Match "'nome' vazio"
    }

    It 'rejeita campo obrigatorio ausente (presets)' {
        $c = Get-TmxTestCatalogClone
        $item = Find-TmxTestItem $c 'REG-001'
        $item.PSObject.Properties.Remove('presets')
        $r = Test-TmxCatalog -Catalog $c
        $r.ok | Should -BeFalse
        ($r.erros -join '; ') | Should -Match "'presets' ausente"
    }

    It 'rejeita tier fora do conjunto fechado' {
        $c = Get-TmxTestCatalogClone
        (Find-TmxTestItem $c 'REG-001').tier = 'LENDARIO'
        $r = Test-TmxCatalog -Catalog $c
        $r.ok | Should -BeFalse
        ($r.erros -join '; ') | Should -Match 'tier invalido'
    }

    It "rejeita id em minusculas ('reg-001') mesmo tendo o formato CAT-NNN em letras" {
        $c = Get-TmxTestCatalogClone
        (Find-TmxTestItem $c 'REG-001').id = 'reg-001'
        $r = Test-TmxCatalog -Catalog $c
        $r.ok | Should -BeFalse
        ($r.erros -join '; ') | Should -Match 'id fora do formato'
    }

    It "considera 'REG-001' e 'reg-001' o mesmo id (duplicado, case-insensitive)" {
        $c = Get-TmxTestCatalogClone
        # REG-001 ja existe no catalogo; renomear outro item para a mesma grafia em
        # minusculas ainda deve contar como duplicado (HashSet com OrdinalIgnoreCase).
        (Find-TmxTestItem $c 'FUN-002').id = 'reg-001'
        $r = Test-TmxCatalog -Catalog $c
        $r.ok | Should -BeFalse
        ($r.erros -join '; ') | Should -Match 'duplicado'
    }

    It "rejeita tier em minusculas ('medido') - conjunto fechado e case-sensitive" {
        $c = Get-TmxTestCatalogClone
        (Find-TmxTestItem $c 'REG-001').tier = 'medido'
        $r = Test-TmxCatalog -Catalog $c
        $r.ok | Should -BeFalse
        ($r.erros -join '; ') | Should -Match 'tier invalido'
    }

    It 'rejeita risco fora do conjunto fechado' {
        $c = Get-TmxTestCatalogClone
        (Find-TmxTestItem $c 'REG-001').risco = 'extremo'
        $r = Test-TmxCatalog -Catalog $c
        $r.ok | Should -BeFalse
        ($r.erros -join '; ') | Should -Match 'risco invalido'
    }

    It 'rejeita preset fora do conjunto fechado' {
        $c = Get-TmxTestCatalogClone
        (Find-TmxTestItem $c 'REG-001').presets = @('desktop', 'esportivo')
        $r = Test-TmxCatalog -Catalog $c
        $r.ok | Should -BeFalse
        ($r.erros -join '; ') | Should -Match 'preset invalido'
    }

    It 'rejeita controle fora do conjunto fechado' {
        $c = Get-TmxTestCatalogClone
        (Find-TmxTestItem $c 'REG-001').controle = 'slider'
        $r = Test-TmxCatalog -Catalog $c
        $r.ok | Should -BeFalse
        ($r.erros -join '; ') | Should -Match 'controle invalido'
    }

    It 'rejeita reversivel fora do conjunto fechado' {
        $c = Get-TmxTestCatalogClone
        (Find-TmxTestItem $c 'REG-001').reversivel = 'as vezes'
        $r = Test-TmxCatalog -Catalog $c
        $r.ok | Should -BeFalse
        ($r.erros -join '; ') | Should -Match 'reversivel invalido'
    }

    It 'rejeita acoes[].tipo fora do conjunto fechado' {
        $c = Get-TmxTestCatalogClone
        (Find-TmxTestItem $c 'REG-001').acoes[0].tipo = 'shellexec'
        $r = Test-TmxCatalog -Catalog $c
        $r.ok | Should -BeFalse
        ($r.erros -join '; ') | Should -Match 'acoes\[\]\.tipo invalido'
    }

    It 'rejeita nome de funcao fora do padrao Set-Tmx(X)' {
        $c = Get-TmxTestCatalogClone
        (Find-TmxTestItem $c 'FUN-002').acoes[0].nome = 'Invoke-TmxDummy'
        $r = Test-TmxCatalog -Catalog $c
        $r.ok | Should -BeFalse
        ($r.erros -join '; ') | Should -Match 'nome de funcao invalido'
    }

    It 'rejeita funcao que bate no padrao mas nao existe (Get-Command)' {
        $c = Get-TmxTestCatalogClone
        (Find-TmxTestItem $c 'FUN-002').acoes[0].nome = 'Set-TmxNaoExiste'
        $r = Test-TmxCatalog -Catalog $c
        $r.ok | Should -BeFalse
        ($r.erros -join '; ') | Should -Match 'nao encontrada'
    }

    It 'rejeita funcao sem o par Undo-Tmx(X)/Test-Tmx(X)' {
        function global:Set-TmxSemPar { }
        try {
            $c = Get-TmxTestCatalogClone
            (Find-TmxTestItem $c 'FUN-002').acoes[0].nome = 'Set-TmxSemPar'
            $r = Test-TmxCatalog -Catalog $c
            $r.ok | Should -BeFalse
            ($r.erros -join '; ') | Should -Match "Undo-TmxSemPar|Test-TmxSemPar"
        } finally {
            Remove-Item Function:\Set-TmxSemPar -ErrorAction SilentlyContinue
        }
    }

    It 'rejeita FOLCLORE com presets nao vazio' {
        $c = Get-TmxTestCatalogClone
        (Find-TmxTestItem $c 'FOL-003').presets = @('desktop')
        $r = Test-TmxCatalog -Catalog $c
        $r.ok | Should -BeFalse
        ($r.erros -join '; ') | Should -Match 'FOLCLORE nao pode ter presets'
    }

    It 'rejeita FOLCLORE sem folclore.porqueNaoRecomendamos' {
        $c = Get-TmxTestCatalogClone
        (Find-TmxTestItem $c 'FOL-003').folclore.porqueNaoRecomendamos = ''
        $r = Test-TmxCatalog -Catalog $c
        $r.ok | Should -BeFalse
        ($r.erros -join '; ') | Should -Match 'porqueNaoRecomendamos'
    }

    It "rejeita reversivel 'nenhuma' sem requerConsentimentoExtra" {
        $c = Get-TmxTestCatalogClone
        (Find-TmxTestItem $c 'IRR-004').requerConsentimentoExtra = $false
        $r = Test-TmxCatalog -Catalog $c
        $r.ok | Should -BeFalse
        ($r.erros -join '; ') | Should -Match "reversivel 'nenhuma' exige requerConsentimentoExtra"
    }

    It "rejeita reversivel 'nenhuma' com presets nao vazio" {
        $c = Get-TmxTestCatalogClone
        (Find-TmxTestItem $c 'IRR-004').presets = @('desktop')
        $r = Test-TmxCatalog -Catalog $c
        $r.ok | Should -BeFalse
        ($r.erros -join '; ') | Should -Match "reversivel 'nenhuma' nao pode ter presets"
    }

    It 'rejeita requerConsentimentoExtra sem consentimento.frase' {
        $c = Get-TmxTestCatalogClone
        (Find-TmxTestItem $c 'IRR-004').consentimento.frase = ''
        $r = Test-TmxCatalog -Catalog $c
        $r.ok | Should -BeFalse
        ($r.erros -join '; ') | Should -Match "'consentimento.frase'"
    }

    It 'rejeita combobox com menos de 2 opcoes' {
        $c = Get-TmxTestCatalogClone
        $item = Find-TmxTestItem $c 'CMB-006'
        $item.opcoes = @($item.opcoes[0])
        $r = Test-TmxCatalog -Catalog $c
        $r.ok | Should -BeFalse
        ($r.erros -join '; ') | Should -Match 'combobox exige ao menos 2'
    }

    It 'rejeita opcao de combobox sem rotulo' {
        $c = Get-TmxTestCatalogClone
        $item = Find-TmxTestItem $c 'CMB-006'
        $item.opcoes[0].PSObject.Properties.Remove('rotulo')
        $r = Test-TmxCatalog -Catalog $c
        $r.ok | Should -BeFalse
        ($r.erros -join '; ') | Should -Match "opcoes\[\] falta campo 'rotulo'"
    }

    It 'rejeita acao invalida dentro de opcoes[].acoes[] (combobox) mencionando id e tipo' {
        $c = Get-TmxTestCatalogClone
        $item = Find-TmxTestItem $c 'CMB-006'
        $item.opcoes[0].acoes[0].tipo = 'shellexec'
        $r = Test-TmxCatalog -Catalog $c
        $r.ok | Should -BeFalse
        ($r.erros -join '; ') | Should -Match 'CMB-006'
        ($r.erros -join '; ') | Should -Match 'shellexec'
        ($r.erros -join '; ') | Should -Match 'opcoes\[\]\.acoes\[\]\.tipo invalido'
    }

    It 'rejeita funcao inexistente dentro de opcoes[].acoes[] (combobox)' {
        $c = Get-TmxTestCatalogClone
        $item = Find-TmxTestItem $c 'CMB-006'
        $item.opcoes[0].acoes[0] = [pscustomobject]@{ tipo = 'funcao'; nome = 'Set-TmxNaoExisteOpcao'; parametros = @{} }
        $r = Test-TmxCatalog -Catalog $c
        $r.ok | Should -BeFalse
        ($r.erros -join '; ') | Should -Match 'CMB-006'
        ($r.erros -join '; ') | Should -Match "'Set-TmxNaoExisteOpcao' nao encontrada"
    }

    It 'rejeita acao invalida dentro de toggleDesligar[] quando presente' {
        $c = Get-TmxTestCatalogClone
        $item = Find-TmxTestItem $c 'TGL-005'
        $item | Add-Member -MemberType NoteProperty -Name 'toggleDesligar' -Value @(
            [pscustomobject]@{ tipo = 'shellexec' }
        )
        $r = Test-TmxCatalog -Catalog $c
        $r.ok | Should -BeFalse
        ($r.erros -join '; ') | Should -Match 'TGL-005'
        ($r.erros -join '; ') | Should -Match 'toggleDesligar\[\]\.tipo invalido'
    }

    It 'aceita toggleDesligar[] valido sem introduzir erros novos' {
        $c = Get-TmxTestCatalogClone
        $item = Find-TmxTestItem $c 'TGL-005'
        $item | Add-Member -MemberType NoteProperty -Name 'toggleDesligar' -Value @(
            [pscustomobject]@{ tipo = 'registry'; caminho = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; nome = 'SoftLandingEnabled'; valor = 1; tipoValor = 'DWord' }
        )
        $r = Test-TmxCatalog -Catalog $c
        $r.ok | Should -BeTrue -Because ($r.erros -join '; ')
    }

    It 'rejeita radio sem grupo' {
        $c = Get-TmxTestCatalogClone
        (Find-TmxTestItem $c 'REG-001').controle = 'radio'
        $r = Test-TmxCatalog -Catalog $c
        $r.ok | Should -BeFalse
        ($r.erros -join '; ') | Should -Match "'radio' exige 'grupo'"
    }

    It 'rejeita campo de texto com Invoke-Expression / iex / scriptblock' {
        $c = Get-TmxTestCatalogClone
        (Find-TmxTestItem $c 'REG-001').porque = 'teste Invoke-Expression aqui'
        $r = Test-TmxCatalog -Catalog $c
        $r.ok | Should -BeFalse
        ($r.erros -join '; ') | Should -Match 'padrao proibido'
    }

    It 'rejeita condicao que nao faz parse' {
        $c = Get-TmxTestCatalogClone
        (Find-TmxTestItem $c 'FUN-002').condicoes.bloqueiaSe = @('os.isLaptop parecidoCom true')
        $r = Test-TmxCatalog -Catalog $c
        $r.ok | Should -BeFalse
        ($r.erros -join '; ') | Should -Match 'FUN-002'
    }

    It 'rejeita percentual usado como promessa de ganho em evidencia/porque' {
        $c = Get-TmxTestCatalogClone
        (Find-TmxTestItem $c 'REG-001').evidencia = 'Testes internos mostram ganho de 30% em FPS'
        $r = Test-TmxCatalog -Catalog $c
        $r.ok | Should -BeFalse
        ($r.erros -join '; ') | Should -Match 'percentual usado como promessa de ganho'
    }

    It 'rejeita promessa percentual com "a" acentuado (regex nao pode depender de BOM no arquivo)' {
        $c = Get-TmxTestCatalogClone
        # [char]0x00E1 monta o 'a' acentuado sem depender da codificacao do .ps1 do teste
        # (mesma razao pela qual o regex $promessa em Catalog.ps1 monta o literal assim).
        $frase = 'Deixa o sistema mais r' + [char]0x00E1 + 'pido em 20%'
        (Find-TmxTestItem $c 'REG-001').porque = $frase
        $r = Test-TmxCatalog -Catalog $c
        $r.ok | Should -BeFalse
        ($r.erros -join '; ') | Should -Match 'percentual usado como promessa de ganho'
    }

    It 'nao aplica a checagem de percentual em FOLCLORE (pode citar a promessa ao desmentir)' {
        $c = Get-TmxTestCatalogClone
        (Find-TmxTestItem $c 'FOL-003').evidencia = 'A crenca promete ganho de 30% em FPS, mas nao se sustenta.'
        $r = Test-TmxCatalog -Catalog $c
        ($r.erros -join '; ') | Should -Not -Match 'percentual usado como promessa de ganho'
    }
}
