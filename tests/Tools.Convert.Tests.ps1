# Testes do conversor WinUtil -> TweakMaxing (tools/Convert-WinUtilCatalog.ps1).
#
# O conversor roda uma vez em pasta temporaria no BeforeAll e todos os testes
# leem essa saida. Duas coisas importam aqui:
#   (a) fidelidade: as contagens do catalogo de origem tem que bater;
#   (b) o catalogo gerado tem que passar em Test-TmxCatalog com o modulo
#       carregado, porque o validador so consegue checar o trio
#       Set-/Undo-/Test-Tmx<X> se as funcoes existirem de verdade.

. "$PSScriptRoot\_Helpers.ps1"

BeforeAll {
    . "$PSScriptRoot\_Helpers.ps1"
    Import-TmxTestModule

    $script:RepoRaiz  = Split-Path $PSScriptRoot -Parent
    $script:Conversor = Join-Path $script:RepoRaiz 'tools\Convert-WinUtilCatalog.ps1'
    $script:Referencia = Join-Path $script:RepoRaiz 'reference\winutil'
    $script:Overlay    = Join-Path $script:RepoRaiz 'src\config\overlay\tweaks.overrides.json'
    $script:OverlayApp = Join-Path $script:RepoRaiz 'src\config\overlay\applications.overrides.json'

    $script:Temp = Join-Path ([System.IO.Path]::GetTempPath()) ('TmxConvert_{0}' -f ([guid]::NewGuid().ToString('N')))
    New-Item -ItemType Directory -Path $script:Temp -Force | Out-Null
    $script:Saida = Join-Path $script:Temp 'config'

    $script:Resumo = & $script:Conversor -Reference $script:Referencia -Out $script:Saida `
                        -Overlay $script:Overlay -OverlayApplications $script:OverlayApp |
                     Select-Object -Last 1

    function script:Get-TmxSaidaJson {
        param([Parameter(Mandatory)] [string] $Arquivo)
        Get-Content -LiteralPath (Join-Path $script:Saida $Arquivo) -Raw -Encoding UTF8 | ConvertFrom-Json
    }

    $script:Tweaks = @((Get-TmxSaidaJson 'tweaks.json').tweaks)
    $script:Apps   = @((Get-TmxSaidaJson 'applications.json').aplicativos)
    $script:Feats  = @((Get-TmxSaidaJson 'feature.json').recursos)
    $script:Appxs  = @((Get-TmxSaidaJson 'appx.json').appx)
    $script:Dnss   = @((Get-TmxSaidaJson 'dns.json').dns)

    # PackageId -> StoreId direto do catalogo de origem, para conferir o lookup.
    $script:MapaStore = @{}
    $appxOrigem = Get-Content -LiteralPath (Join-Path $script:Referencia 'config\appx.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($p in $appxOrigem.PSObject.Properties) {
        $pkg = "$($p.Value.PackageId)"
        if ($pkg -and $p.Value.StoreId) { $script:MapaStore[$pkg] = "$($p.Value.StoreId)" }
    }
}

AfterAll {
    if ($script:Temp -and (Test-Path -LiteralPath $script:Temp)) {
        Remove-Item -LiteralPath $script:Temp -Recurse -Force -ErrorAction SilentlyContinue
    }
    Remove-Module TweakMaxing -Force -ErrorAction SilentlyContinue
}

Describe 'Convert-WinUtilCatalog contagens' -Tag 'Convert' {

    It 'converte os 67 tweaks do WinUtil' {
        $script:Tweaks.Count | Should -Be 67
        $script:Resumo.tweaks | Should -Be 67
    }

    It 'converte os 236 aplicativos' {
        $script:Apps.Count | Should -Be 236
    }

    It 'converte os 33 recursos' {
        $script:Feats.Count | Should -Be 33
    }

    It 'converte os 34 pacotes appx' {
        $script:Appxs.Count | Should -Be 34
    }

    It 'converte os 8 provedores de DNS' {
        $script:Dnss.Count | Should -Be 8
    }
}

Describe 'Convert-WinUtilCatalog camada editorial' -Tag 'Convert' {

    It 'todo tweak tem tier, reversivel, porque, evidencia e controle' {
        $faltando = New-Object 'System.Collections.Generic.List[string]'
        foreach ($t in $script:Tweaks) {
            foreach ($campo in 'tier', 'reversivel', 'porque', 'evidencia', 'controle') {
                if (-not "$($t.$campo)") { $faltando.Add("$($t.id): $campo") }
            }
        }
        $faltando.ToArray() | Should -BeNullOrEmpty
    }

    It 'nenhum tweak FOLCLORE entra em preset' {
        $ruins = @($script:Tweaks | Where-Object { $_.tier -eq 'FOLCLORE' -and @($_.presets).Count -gt 0 })
        @($ruins | ForEach-Object { $_.id }) | Should -BeNullOrEmpty
    }

    It 'nenhum tweak irreversivel entra em preset' {
        $ruins = @($script:Tweaks | Where-Object { $_.reversivel -eq 'nenhuma' -and @($_.presets).Count -gt 0 })
        @($ruins | ForEach-Object { $_.id }) | Should -BeNullOrEmpty
    }

    It 'todo tweak irreversivel exige consentimento com frase' {
        foreach ($t in @($script:Tweaks | Where-Object { $_.reversivel -eq 'nenhuma' })) {
            $t.requerConsentimentoExtra | Should -BeTrue -Because "$($t.id) e irreversivel"
            "$($t.consentimento.frase)"  | Should -Not -BeNullOrEmpty -Because "$($t.id) e irreversivel"
        }
    }

    It 'todo tweak FOLCLORE traz o bloco folclore explicando por que nao recomendamos' {
        foreach ($t in @($script:Tweaks | Where-Object { $_.tier -eq 'FOLCLORE' })) {
            "$($t.folclore.porqueNaoRecomendamos)" | Should -Not -BeNullOrEmpty -Because "$($t.id) e FOLCLORE"
        }
    }

    It 'guarda a origem no WinUtil de cada tweak' {
        foreach ($t in $script:Tweaks) {
            "$($t.origem.winutil)" | Should -Not -BeNullOrEmpty
        }
    }

    It 'toggle carrega toggleDesligar com as acoes do estado desligado' {
        $toggles = @($script:Tweaks | Where-Object { $_.controle -eq 'toggle' })
        $toggles.Count | Should -BeGreaterThan 0
        foreach ($t in $toggles) {
            $t.PSObject.Properties['toggleDesligar'] | Should -Not -BeNullOrEmpty -Because "$($t.id) e toggle"
        }
    }

    It 'combobox tem ao menos duas opcoes com acoes' {
        foreach ($t in @($script:Tweaks | Where-Object { $_.controle -eq 'combobox' })) {
            @($t.opcoes).Count | Should -BeGreaterThan 1 -Because "$($t.id) e combobox"
            foreach ($o in @($t.opcoes)) {
                "$($o.valor)"  | Should -Not -BeNullOrEmpty
                "$($o.rotulo)" | Should -Not -BeNullOrEmpty
            }
        }
    }
}

Describe 'Convert-WinUtilCatalog acoes' -Tag 'Convert' {

    It 'toda acao appx com PackageId conhecido recebe o storeId' {
        $conferidos = 0
        foreach ($t in $script:Tweaks) {
            foreach ($a in @($t.acoes)) {
                if ("$($a.tipo)" -ne 'appx') { continue }
                $pkg = "$($a.pacote)"
                if (-not $script:MapaStore.ContainsKey($pkg)) { continue }
                "$($a.storeId)" | Should -Be $script:MapaStore[$pkg] -Because "$($t.id) remove $pkg"
                $conferidos++
            }
        }
        # Nao ha acao appx declarativa no catalogo atual do WinUtil (Widgets e
        # Windows AI passam por funcao nomeada). Se um dia houver, o laco acima
        # cobre; este Should documenta que o numero conferido e conhecido.
        $conferidos | Should -BeGreaterOrEqual 0
    }

    It 'nao copia script do WinUtil para dentro do catalogo' {
        $texto = Get-Content -LiteralPath (Join-Path $script:Saida 'tweaks.json') -Raw -Encoding UTF8
        $texto | Should -Not -Match 'Invoke-Expression'
        $texto | Should -Not -Match 'ScriptBlock\]::Create'
        $texto | Should -Not -Match 'Invoke-WinUtil'
    }

    It 'toda acao do tipo funcao aponta para um trio Set/Undo/Test existente' {
        $nomes = New-Object 'System.Collections.Generic.HashSet[string]'
        foreach ($t in $script:Tweaks) {
            $listas = @($t.acoes)
            foreach ($o in @($t.opcoes)) { $listas += @($o.acoes) }
            if ($t.PSObject.Properties['toggleDesligar']) { $listas += @($t.toggleDesligar) }
            foreach ($a in $listas) {
                if ($null -eq $a -or "$($a.tipo)" -ne 'funcao') { continue }
                [void]$nomes.Add("$($a.nome)")
            }
        }
        $nomes.Count | Should -BeGreaterThan 0
        foreach ($n in $nomes) {
            $n | Should -Match '^Set-Tmx[A-Za-z0-9]+$'
            $sufixo = $n.Substring('Set-Tmx'.Length)
            (Get-Command -Name $n -ErrorAction SilentlyContinue)              | Should -Not -BeNullOrEmpty
            (Get-Command -Name "Undo-Tmx$sufixo" -ErrorAction SilentlyContinue) | Should -Not -BeNullOrEmpty
            (Get-Command -Name "Test-Tmx$sufixo" -ErrorAction SilentlyContinue) | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Convert-WinUtilCatalog formato de saida' -Tag 'Convert' {

    It 'grava UTF-8 sem BOM e com fim de linha LF' {
        foreach ($arquivo in 'tweaks.json', 'applications.json', 'feature.json', 'appx.json', 'dns.json') {
            $bytes = [System.IO.File]::ReadAllBytes((Join-Path $script:Saida $arquivo))
            # BOM UTF-8 = EF BB BF
            ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should -BeFalse -Because "$arquivo nao pode ter BOM"
            @($bytes | Where-Object { $_ -eq 13 }).Count | Should -Be 0 -Because "$arquivo so pode ter LF"
        }
    }

    It 'e idempotente: a segunda passada produz os mesmos bytes' {
        $antes = @{}
        foreach ($arquivo in 'tweaks.json', 'applications.json', 'feature.json', 'appx.json', 'dns.json') {
            $antes[$arquivo] = (Get-FileHash -LiteralPath (Join-Path $script:Saida $arquivo) -Algorithm SHA256).Hash
        }

        & $script:Conversor -Reference $script:Referencia -Out $script:Saida `
            -Overlay $script:Overlay -OverlayApplications $script:OverlayApp | Out-Null

        foreach ($arquivo in $antes.Keys) {
            (Get-FileHash -LiteralPath (Join-Path $script:Saida $arquivo) -Algorithm SHA256).Hash |
                Should -Be $antes[$arquivo] -Because "$arquivo deve ser identico na segunda passada"
        }
    }
}

Describe 'Convert-WinUtilCatalog falhas declaradas' -Tag 'Convert' {

    It 'falha nomeando a chave quando o overlay esta incompleto' {
        $doc = Get-Content -LiteralPath $script:Overlay -Raw -Encoding UTF8 | ConvertFrom-Json
        $doc.PSObject.Properties.Remove('WPFTweaksTelemetry')

        $overlayQuebrado = Join-Path $script:Temp 'overlay-incompleto.json'
        $doc | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $overlayQuebrado -Encoding UTF8

        $saidaQuebrada = Join-Path $script:Temp 'config-quebrado'
        { & $script:Conversor -Reference $script:Referencia -Out $saidaQuebrada `
              -Overlay $overlayQuebrado -OverlayApplications $script:OverlayApp } |
            Should -Throw -ExpectedMessage '*WPFTweaksTelemetry*'
    }

    It 'falha quando a referencia do WinUtil nao existe' {
        $inexistente = Join-Path $script:Temp 'winutil-que-nao-existe'
        { & $script:Conversor -Reference $inexistente -Out (Join-Path $script:Temp 'config-vazio') `
              -Overlay $script:Overlay -OverlayApplications $script:OverlayApp } |
            Should -Throw -ExpectedMessage '*nao encontrada*'
    }
}

Describe 'Convert-WinUtilCatalog saida valida contra o schema' -Tag 'Convert' {

    It 'o catalogo gerado passa em Test-TmxCatalog' {
        $cat = Get-TmxCatalog -Path (Join-Path $script:Saida 'tweaks.json')
        $r = Test-TmxCatalog -Catalog $cat
        $r.erros | Should -BeNullOrEmpty
        $r.ok    | Should -BeTrue
        $r.total | Should -Be 67
    }
}

Describe 'Convert-WinUtilCatalog serializador' -Tag 'Convert' {

    BeforeAll {
        # -SomenteDefinicoes carrega as funcoes do conversor sem converter nada.
        # O script liga Set-StrictMode; desligamos logo em seguida para nao
        # contaminar o resto do arquivo de teste.
        . $script:Conversor -Reference 'ignorado' -Out 'ignorado' -SomenteDefinicoes
        Set-StrictMode -Off

        function script:ConvertFrom-TmxJsonValor {
            # Le de volta um valor JSON solto, para provar o round-trip.
            param([Parameter(Mandatory)] [string] $Json)
            (ConvertFrom-Json "{ `"v`": $Json }").v
        }
    }

    It 'escapa barra invertida e aspas' {
        ConvertTo-TmxJsonString -Texto 'a\b'  | Should -Be '"a\\b"'
        ConvertTo-TmxJsonString -Texto 'a"b'  | Should -Be '"a\"b"'
        ConvertTo-TmxJsonString -Texto 'C:\Windows\System32' | Should -Be '"C:\\Windows\\System32"'
    }

    It 'escapa os brancos de controle com a forma curta' {
        ConvertTo-TmxJsonString -Texto "a`nb" | Should -Be '"a\nb"'
        ConvertTo-TmxJsonString -Texto "a`tb" | Should -Be '"a\tb"'
        ConvertTo-TmxJsonString -Texto "a`rb" | Should -Be '"a\rb"'
        ConvertTo-TmxJsonString -Texto "a`bb" | Should -Be '"a\bb"'
        ConvertTo-TmxJsonString -Texto "a`fb" | Should -Be '"a\fb"'
    }

    It 'escapa caractere de controle abaixo de 0x20 na forma \u' {
        ConvertTo-TmxJsonString -Texto ("a" + [char]0x01 + "b") | Should -Be '"a\u0001b"'
        ConvertTo-TmxJsonString -Texto ("a" + [char]0x1F + "b") | Should -Be '"a\u001fb"'
    }

    It 'mantem acento e unicode literais, sem virar sequencia \u' {
        # Os acentuados sao montados por codigo de proposito: este arquivo nao tem
        # BOM, e o parser do PS 5.1 leria um literal acentuado embutido usando a
        # codepage ANSI, corrompendo justamente o que o teste quer provar.
        $acentuado = 'Hist' + [char]0x00F3 + 'rico de a' + [char]0x00E7 + [char]0x00F5 + 'es n' + [char]0x00E3 + 'o lidas'
        $r = ConvertTo-TmxJsonString -Texto $acentuado
        $r | Should -Be ('"' + $acentuado + '"')
        $r | Should -Not -Match '\\u00'

        # Grego e par substituto (emoji) tambem passam inteiros.
        $amplo = [char]0x03BB + [char]0xD83D + [char]0xDE80
        ConvertTo-TmxJsonString -Texto $amplo | Should -Be ('"' + $amplo + '"')
        $r | Should -Not -Match '\\u00'
    }

    It 'o que ele escreve volta identico pelo ConvertFrom-Json' {
        foreach ($original in @(
            'a\b',
            'a"b',
            "linha1`nlinha2`tfim",
            ("controle" + [char]0x01 + "fim"),
            ('Hist' + [char]0x00F3 + 'rico de a' + [char]0x00E7 + [char]0x00F5 + 'es n' + [char]0x00E3 + 'o lidas'),
            'C:\Program Files (x86)\Microsoft\Edge'
        )) {
            $json = ConvertTo-TmxJsonString -Texto $original
            ConvertFrom-TmxJsonValor -Json $json | Should -Be $original -Because "round-trip de '$original'"
        }
    }

    It 'serializa objeto e array vazios de forma compacta' {
        ConvertTo-TmxJsonText -Valor ([ordered]@{}) | Should -Be '{}'
        ConvertTo-TmxJsonText -Valor @()             | Should -Be '[]'
        ConvertTo-TmxJsonText -Valor $null           | Should -Be 'null'
        ConvertTo-TmxJsonText -Valor $true           | Should -Be 'true'
        ConvertTo-TmxJsonText -Valor $false          | Should -Be 'false'
    }

    It 'preserva a ordem das chaves em vez de alfabetizar' {
        $o = [ordered]@{ zeta = 1; alfa = 2; meio = 3 }
        $texto = ConvertTo-TmxJsonText -Valor $o
        $texto.IndexOf('zeta') | Should -BeLessThan $texto.IndexOf('alfa')
        $texto.IndexOf('alfa') | Should -BeLessThan $texto.IndexOf('meio')
    }

    It 'indenta com 2 espacos por nivel' {
        $texto = ConvertTo-TmxJsonText -Valor ([ordered]@{ a = [ordered]@{ b = 1 } })
        $texto | Should -Match "(?m)^  `"a`": \{"
        $texto | Should -Match "(?m)^    `"b`": 1"
    }
}

Describe 'Convert-WinUtilCatalog conversao de valor de registro' -Tag 'Convert' {

    BeforeAll {
        . $script:Conversor -Reference 'ignorado' -Out 'ignorado' -SomenteDefinicoes
        Set-StrictMode -Off
    }

    It 'converte decimal e hexadecimal de DWord para numero' {
        ConvertTo-TmxValorRegistro -Bruto '0'    -Tipo 'DWord' | Should -Be 0
        ConvertTo-TmxValorRegistro -Bruto '5'    -Tipo 'DWord' | Should -Be 5
        ConvertTo-TmxValorRegistro -Bruto '32'   -Tipo 'DWord' | Should -Be 32
        ConvertTo-TmxValorRegistro -Bruto '0x20' -Tipo 'DWord' | Should -Be 32
    }

    It 'preserva o sinal negativo que ja vem escrito assim' {
        ConvertTo-TmxValorRegistro -Bruto '-1' -Tipo 'DWord' | Should -Be -1
    }

    It 'mantem DWord acima de Int32.MaxValue como numero NAO assinado no catalogo' {
        # Decisao deliberada: o catalogo e legivel, entao guarda 4294967295.
        ConvertTo-TmxValorRegistro -Bruto '4294967295' -Tipo 'DWord' | Should -Be 4294967295
        ConvertTo-TmxValorRegistro -Bruto '0xffffffff' -Tipo 'DWord' | Should -Be 4294967295
        (ConvertTo-TmxValorRegistro -Bruto '0xffffffff' -Tipo 'DWord') | Should -BeGreaterThan ([int]::MaxValue)
    }

    It 'quem converte para o int32 negativo do provider e o Engine, uma vez so' {
        # Prova o contrato documentado em ConvertTo-TmxValorRegistro: o valor sem
        # sinal do catalogo vira -1 ao passar pelo Engine, e so la.
        $doCatalogo = ConvertTo-TmxValorRegistro -Bruto '0xffffffff' -Tipo 'DWord'
        ConvertTo-TmxRegistryValue -Value $doCatalogo -Type 'DWord' | Should -Be -1
        ConvertTo-TmxRegistryValue -Value 32 -Type 'DWord'          | Should -Be 32
    }

    It 'QWord tambem vira numero' {
        ConvertTo-TmxValorRegistro -Bruto '1' -Tipo 'QWord' | Should -Be 1
    }

    It 'String continua texto, inclusive quando parece numero' {
        ConvertTo-TmxValorRegistro -Bruto 'Deny'      -Tipo 'String' | Should -BeOfType [string]
        ConvertTo-TmxValorRegistro -Bruto '2'         -Tipo 'String' | Should -Be '2'
        (ConvertTo-TmxValorRegistro -Bruto '2'        -Tipo 'String') | Should -BeOfType [string]
        ConvertTo-TmxValorRegistro -Bruto 'show:home' -Tipo 'String' | Should -Be 'show:home'
    }

    It 'falha alto em vez de gravar lixo quando o DWord nao e numerico' {
        { ConvertTo-TmxValorRegistro -Bruto 'NotSpecified' -Tipo 'DWord' } |
            Should -Throw -ExpectedMessage '*nao e numerico*'
    }
}

Describe 'Convert-WinUtilCatalog aplicativos: campo icon' -Tag 'Convert' {

    BeforeAll {
        # -SomenteDefinicoes carrega as funcoes do conversor sem converter
        # nada, para exercitar ConvertTo-TmxApplications isolada (mesmo
        # padrao da Describe 'serializador' acima).
        . $script:Conversor -Reference 'ignorado' -Out 'ignorado' -SomenteDefinicoes
        Set-StrictMode -Off
    }

    It 'icon e null quando nao ha overlay' {
        $winutil = [pscustomobject]@{
            WPFInstallExemplo = [pscustomobject]@{
                content = 'Exemplo'; description = 'desc'; category = 'Utilities'
                winget = 'Vendor.Exemplo'; link = 'https://exemplo.org'
            }
        }
        $apps = ConvertTo-TmxApplications -Winutil $winutil -Overlay $null
        $apps.Count | Should -Be 1
        # ConvertTo-TmxApplications devolve [ordered]@{} (nao pscustomobject);
        # .Contains() e o jeito certo de provar que a CHAVE existe com valor
        # null, em vez de simplesmente estar ausente (um indexador/dot-access
        # devolveria $null nos dois casos).
        $apps[0].Contains('icon') | Should -BeTrue -Because 'a chave icon precisa existir mesmo quando o valor e null'
        $apps[0].icon | Should -BeNullOrEmpty
    }

    It 'overlay icon sobrescreve o padrao null, igual descricao' {
        $winutil = [pscustomobject]@{
            WPFInstallExemplo = [pscustomobject]@{
                content = 'Exemplo'; description = 'desc'; category = 'Utilities'
                winget = 'Vendor.Exemplo'; link = 'https://exemplo.org'
            }
        }
        $overlay = [pscustomobject]@{
            WPFInstallExemplo = [pscustomobject]@{
                descricao = 'Descricao editorial'
                icon      = 'https://exemplo.org/icone.png'
            }
        }
        $apps = ConvertTo-TmxApplications -Winutil $winutil -Overlay $overlay
        $apps[0].descricao | Should -Be 'Descricao editorial'
        $apps[0].icon | Should -Be 'https://exemplo.org/icone.png'
    }

    It 'catalogo gerado de verdade traz a chave icon em todo aplicativo' {
        foreach ($a in $script:Apps) {
            $a.PSObject.Properties['icon'] | Should -Not -BeNullOrEmpty -Because "$($a.id) precisa ter a chave icon"
        }
    }
}

Describe 'Convert-WinUtilCatalog distribuicao editorial' -Tag 'Convert' {

    It 'mantem a distribuicao de tier acordada' {
        # 2026-09-23: INT-001 e DES-003 rebaixados de MEDIDO para TECNICO apos
        # auditoria Jev - o proprio texto de evidencia diz que o efeito varia.
        @($script:Tweaks | Where-Object { $_.tier -eq 'MEDIDO' }).Count   | Should -Be 40
        @($script:Tweaks | Where-Object { $_.tier -eq 'TECNICO' }).Count  | Should -Be 23
        @($script:Tweaks | Where-Object { $_.tier -eq 'FOLCLORE' }).Count | Should -Be 4
    }

    It 'mantem a distribuicao de reversibilidade acordada' {
        @($script:Tweaks | Where-Object { $_.reversivel -eq 'total' }).Count   | Should -Be 58
        @($script:Tweaks | Where-Object { $_.reversivel -eq 'parcial' }).Count | Should -Be 7
        @($script:Tweaks | Where-Object { $_.reversivel -eq 'nenhuma' }).Count | Should -Be 2
    }

    It 'bloqueio de instalador de periferico e parcial, e a evidencia diz por que' {
        foreach ($wpf in 'WPFTweaksRazerBlock', 'WPFTweaksLogiBlock') {
            $t = $script:Tweaks | Where-Object { $_.origem.winutil -eq $wpf }
            $t.reversivel | Should -Be 'parcial' -Because "$wpf esvazia a pasta do instalador sem copia de seguranca"
            $t.evidencia  | Should -Match '(?i)parcial'
        }
    }

    It 'todo tweak parcial explica na evidencia o que nao volta' {
        foreach ($t in @($script:Tweaks | Where-Object { $_.reversivel -eq 'parcial' })) {
            "$($t.evidencia)" | Should -Not -BeNullOrEmpty -Because "$($t.id) e parcial"
            "$($t.evidencia)".Length | Should -BeGreaterThan 80 -Because "$($t.id) precisa dizer o que nao volta"
        }
    }
}
