# tests/Encoding.Tests.ps1
# Todo .ps1/.psm1/.psd1 do repositorio tem que ser ASCII puro.
#
# Por que isso importa aqui: os scripts sao gravados SEM BOM, e o parser do
# Windows PowerShell 5.1 le um arquivo sem BOM usando a codepage ANSI da
# maquina, nao UTF-8. Um unico caractere acentuado no fonte chega ao parser
# como dois caracteres Latin-1 - o que ja quebrou de verdade um regex de
# validacao do catalogo ('mais rapido' com 'a' acentuado parou de casar) e
# quebraria qualquer comparacao de string com acento.
#
# A saida: comentario vira ASCII simples; texto que PRECISA do acento e
# montado em runtime (via [char] com o code point) ou escrito como escape
# do proprio regex. Texto de interface com acento mora em .js/.html/.json,
# que sao lidos como UTF-8 de verdade.
#
# tools/gh fica de fora: e ferramenta de terceiro versionada como veio.

. (Join-Path $PSScriptRoot '_Helpers.ps1')

Describe 'Codificacao dos scripts' -Tag 'Encoding' {

    BeforeAll {
        . (Join-Path $PSScriptRoot '_Helpers.ps1')

        $script:Raiz = Split-Path $PSScriptRoot -Parent

        function Get-TmxScriptFiles {
            <#
            .SYNOPSIS
                Todos os .ps1/.psm1/.psd1 de src/, scripts/, tools/ e tests/,
                exceto os de tools/gh.
            #>
            [CmdletBinding()]
            param([Parameter(Mandatory)] [string] $Raiz)

            # Extensao conferida no objeto, nao via -Include: com -LiteralPath
            # (sem curinga no caminho) o -Include do Get-ChildItem e ignorado em
            # silencio e a varredura volta com o repositorio inteiro.
            $extensoes = @('.ps1', '.psm1', '.psd1')

            $lista = New-Object 'System.Collections.Generic.List[object]'
            foreach ($pasta in @('src', 'scripts', 'tools', 'tests')) {
                $caminho = Join-Path $Raiz $pasta
                if (-not (Test-Path -LiteralPath $caminho)) { continue }
                foreach ($f in (Get-ChildItem -LiteralPath $caminho -Recurse -File)) {
                    if ($extensoes -notcontains $f.Extension.ToLowerInvariant()) { continue }
                    if ($f.FullName -like '*\tools\gh\*') { continue }
                    $lista.Add($f)
                }
            }
            # .ToArray(): @() sobre List generica vazia falha no PS 5.1
            $lista.ToArray()
        }

        function Get-TmxNonAsciiReport {
            <#
            .SYNOPSIS
                Linhas com byte > 0x7F de um arquivo, no formato "arquivo:linha: texto".
            .OUTPUTS
                Array de strings (vazio quando o arquivo e ASCII puro).
            #>
            [CmdletBinding()]
            param([Parameter(Mandatory)] [string] $Caminho, [Parameter(Mandatory)] [string] $Raiz)

            $bytes = [System.IO.File]::ReadAllBytes($Caminho)
            $temByteAlto = $false
            foreach ($b in $bytes) {
                if ($b -gt 127) { $temByteAlto = $true; break }
            }

            $achados = New-Object 'System.Collections.Generic.List[string]'
            if (-not $temByteAlto) { return $achados.ToArray() }

            $relativo = $Caminho.Substring($Raiz.Length).TrimStart('\')

            # BOM (EF BB BF) tambem e byte nao-ASCII e e o caso mais comum:
            # aponta ele pelo nome em vez de apontar a linha 1 inteira.
            if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
                $achados.Add("${relativo}: BOM UTF-8 no inicio do arquivo")
            }

            $n = 0
            foreach ($linha in [System.IO.File]::ReadAllLines($Caminho)) {
                $n++
                # -cmatch: a classe negada ja e explicita, mas manter
                # case-sensitive evita qualquer surpresa de cultura.
                if ($linha -cmatch '[^\x00-\x7F]') {
                    $achados.Add("${relativo}:${n}: $linha")
                }
            }
            $achados.ToArray()
        }
    }

    It 'nenhum script tem byte fora do ASCII' {
        $arquivos = @(Get-TmxScriptFiles -Raiz $script:Raiz)
        $arquivos.Count | Should -BeGreaterThan 0

        $problemas = New-Object 'System.Collections.Generic.List[string]'
        foreach ($f in $arquivos) {
            foreach ($linha in @(Get-TmxNonAsciiReport -Caminho $f.FullName -Raiz $script:Raiz)) {
                $problemas.Add($linha)
            }
        }

        # A mensagem lista arquivo:linha para que a correcao seja direta.
        $texto = ($problemas.ToArray() -join "`n")
        $problemas.Count | Should -Be 0 -Because "os seguintes trechos nao sao ASCII:`n$texto"
    }

    It 'nenhum script comeca com BOM' {
        $comBom = New-Object 'System.Collections.Generic.List[string]'
        foreach ($f in @(Get-TmxScriptFiles -Raiz $script:Raiz)) {
            $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
            if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
                $comBom.Add($f.FullName.Substring($script:Raiz.Length).TrimStart('\'))
            }
        }
        $comBom.Count | Should -Be 0 -Because "com BOM: $($comBom.ToArray() -join ', ')"
    }
}
