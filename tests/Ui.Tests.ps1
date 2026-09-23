# tests/Ui.Tests.ps1
# Guardas da janela (src/functions/ui). Nao abre janela, nao exige elevacao e
# nao carrega o WebView2: exercita so as funcoes puras que os handlers da
# janela chamam.
#
# Test-TmxUiNavegacaoPermitida e a lista de permissao de NavigationStarting.
# Ela vale por uma razao especifica: a pagina servida em
# https://app.tweakmaxing tem window.chrome.webview, ou seja, a ponte para o
# PowerShell. Deixar a janela navegar para fora seria entregar essa ponte a
# uma origem remota. Por isso a comparacao e pelo objeto [uri] (Scheme + Host)
# e nao por prefixo de texto - os casos de 'app.tweakmaxing.evil.com' e
# 'app.tweakmaxing@evil.com' abaixo sao exatamente os que um -like ingenuo
# deixaria passar.

. (Join-Path $PSScriptRoot '_Helpers.ps1')

Describe 'Test-TmxUiNavegacaoPermitida' -Tag 'Ui' {

    BeforeAll {
        . (Join-Path $PSScriptRoot '_Helpers.ps1')
        Import-TmxTestModule
    }

    AfterAll {
        Remove-Module TweakMaxing -Force -ErrorAction SilentlyContinue
    }

    It 'permite <Rotulo>' -ForEach @(
        @{ Rotulo = 'a propria pagina';        Uri = 'https://app.tweakmaxing/index.html' }
        @{ Rotulo = 'a raiz do host virtual';  Uri = 'https://app.tweakmaxing/' }
        @{ Rotulo = 'host em maiusculas';      Uri = 'https://APP.TWEAKMAXING/x' }
        @{ Rotulo = 'um recurso com query';    Uri = 'https://app.tweakmaxing/app.js?v=2' }
        @{ Rotulo = 'about:blank';             Uri = 'about:blank' }
        @{ Rotulo = 'about:blank em caixa alta'; Uri = 'ABOUT:BLANK' }
    ) {
        Test-TmxUiNavegacaoPermitida -Uri $Uri | Should -BeTrue
    }

    It 'recusa <Rotulo>' -ForEach @(
        # Sufixo de dominio: o host real e evil.com.
        @{ Rotulo = 'subdominio de outro dominio'; Uri = 'https://app.tweakmaxing.evil.com/' }
        # Userinfo: tudo antes do '@' e usuario, o host e evil.com.
        @{ Rotulo = 'host verdadeiro depois do @'; Uri = 'https://app.tweakmaxing@evil.com/' }
        @{ Rotulo = 'http em vez de https';        Uri = 'http://app.tweakmaxing/' }
        # O nome do host aparece so no caminho.
        @{ Rotulo = 'o host virtual no caminho';   Uri = 'https://evil.com/app.tweakmaxing' }
        @{ Rotulo = 'string vazia';                Uri = '' }
        @{ Rotulo = 'URI malformada';              Uri = 'ht!tp:://///' }
        @{ Rotulo = 'file://';                     Uri = 'file:///C:/Windows/System32/cmd.exe' }
        @{ Rotulo = 'javascript:';                 Uri = 'javascript:alert(1)' }
        @{ Rotulo = 'data:';                       Uri = 'data:text/html,<script>1</script>' }
        @{ Rotulo = 'about: que nao e blank';      Uri = 'about:config' }
        @{ Rotulo = 'caminho relativo solto';      Uri = '/index.html' }
    ) {
        Test-TmxUiNavegacaoPermitida -Uri $Uri | Should -BeFalse
    }

    It 'recusa $null sem lancar' {
        # O evento do WebView2 pode chegar com Uri nula; a guarda nao pode
        # virar excecao dentro de um handler da thread da UI.
        Test-TmxUiNavegacaoPermitida -Uri $null | Should -BeFalse
    }

    It 'devolve sempre um booleano, nunca $null' {
        foreach ($u in @('https://app.tweakmaxing/x', 'https://evil.com/', '', $null)) {
            (Test-TmxUiNavegacaoPermitida -Uri $u) -is [bool] | Should -BeTrue
        }
    }
}
