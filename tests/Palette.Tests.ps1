# tests/Palette.Tests.ps1
# Paleta visual (identidade cinza/teal) da interface web.
#
# Tres angulos:
#   1. nenhuma cor literal (hex ou rgb()/rgba()) em src/web/**/*.css,*.js,*.html
#      cai na faixa de azul (matiz 190-260 com saturacao > 25%) - a marca
#      antiga usava azul e a task pede a substituicao completa por tokens.
#   2. app.css define --active, --active-hover, --active-fg e --elevated
#      tanto no tema escuro (:root) quanto no tema claro
#      (@media prefers-color-scheme: light).
#   3. contraste WCAG >= 4.5:1 nos dois temas para os pares de texto/fundo
#      que a casca usa de verdade.
#
# So le CSS/JS/HTML como texto: nao depende do modulo TweakMaxing nem de
# elevacao.

. (Join-Path $PSScriptRoot '_Helpers.ps1')

Describe 'Paleta visual' -Tag 'Palette' {

    BeforeAll {
        $script:Raiz   = Split-Path $PSScriptRoot -Parent
        $script:WebDir = Join-Path $script:Raiz 'src\web'
        $script:AppCss = Join-Path $script:WebDir 'app.css'

        function script:ConvertFrom-TmxHex {
            <#
            .SYNOPSIS
                '#rgb' ou '#rrggbb'(aa) -> @{ R; G; B } (0-255).
            #>
            param([Parameter(Mandatory)] [string] $Hex)
            $h = $Hex.TrimStart('#')
            if ($h.Length -eq 3) {
                $h = -join ($h.ToCharArray() | ForEach-Object { "$_$_" })
            }
            [pscustomobject]@{
                R = [Convert]::ToInt32($h.Substring(0, 2), 16)
                G = [Convert]::ToInt32($h.Substring(2, 2), 16)
                B = [Convert]::ToInt32($h.Substring(4, 2), 16)
            }
        }

        function script:Get-TmxColorMatches {
            <#
            .SYNOPSIS
                Toda cor literal (#rgb/#rrggbb/#rrggbbaa, rgb()/rgba()) de um texto.
            .OUTPUTS
                Array de @{ Texto; R; G; B } (0-255 cada canal).
            #>
            param([Parameter(Mandatory)] [string] $Text)

            $lista = New-Object 'System.Collections.Generic.List[object]'

            foreach ($m in [regex]::Matches($Text, '#([0-9a-fA-F]{8}|[0-9a-fA-F]{6}|[0-9a-fA-F]{3})\b')) {
                $cor = script:ConvertFrom-TmxHex -Hex $m.Value
                $lista.Add([pscustomobject]@{ Texto = $m.Value; R = $cor.R; G = $cor.G; B = $cor.B })
            }

            $padraoRgb = 'rgba?\(\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)\s*(?:,\s*[\d.]+\s*)?\)'
            foreach ($m in [regex]::Matches($Text, $padraoRgb)) {
                $lista.Add([pscustomobject]@{
                    Texto = $m.Value
                    R     = [double]$m.Groups[1].Value
                    G     = [double]$m.Groups[2].Value
                    B     = [double]$m.Groups[3].Value
                })
            }

            $lista.ToArray()
        }

        function script:Get-TmxHsl {
            <#
            .SYNOPSIS
                RGB (0-255) -> @{ H (0-360); S (0-100); L (0-100) }.
            #>
            param(
                [Parameter(Mandatory)] [double] $R,
                [Parameter(Mandatory)] [double] $G,
                [Parameter(Mandatory)] [double] $B
            )
            $rf = $R / 255.0
            $gf = $G / 255.0
            $bf = $B / 255.0
            $max = [Math]::Max($rf, [Math]::Max($gf, $bf))
            $min = [Math]::Min($rf, [Math]::Min($gf, $bf))
            $l = ($max + $min) / 2.0
            $h = 0.0
            $s = 0.0
            if ($max -ne $min) {
                $d = $max - $min
                if ($l -gt 0.5) { $s = $d / (2.0 - $max - $min) } else { $s = $d / ($max + $min) }
                if ($max -eq $rf) {
                    $h = ($gf - $bf) / $d
                    if ($gf -lt $bf) { $h += 6 }
                } elseif ($max -eq $gf) {
                    $h = (($bf - $rf) / $d) + 2
                } else {
                    $h = (($rf - $gf) / $d) + 4
                }
                $h = $h / 6.0
            }
            [pscustomobject]@{ H = $h * 360.0; S = $s * 100.0; L = $l * 100.0 }
        }

        function script:Get-TmxLuminance {
            <#
            .SYNOPSIS
                Luminancia relativa (WCAG) de um RGB 0-255.
            #>
            param(
                [Parameter(Mandatory)] [double] $R,
                [Parameter(Mandatory)] [double] $G,
                [Parameter(Mandatory)] [double] $B
            )
            function Canal([double] $c) {
                $c = $c / 255.0
                if ($c -le 0.03928) { return $c / 12.92 }
                return [Math]::Pow((($c + 0.055) / 1.055), 2.4)
            }
            (0.2126 * (Canal $R)) + (0.7152 * (Canal $G)) + (0.0722 * (Canal $B))
        }

        function script:Get-TmxContraste {
            <#
            .SYNOPSIS
                Razao de contraste WCAG entre duas cores hex.
            #>
            param([Parameter(Mandatory)] [string] $HexA, [Parameter(Mandatory)] [string] $HexB)
            $a = script:ConvertFrom-TmxHex -Hex $HexA
            $b = script:ConvertFrom-TmxHex -Hex $HexB
            $la = script:Get-TmxLuminance -R $a.R -G $a.G -B $a.B
            $lb = script:Get-TmxLuminance -R $b.R -G $b.G -B $b.B
            $clara  = [Math]::Max($la, $lb)
            $escura = [Math]::Min($la, $lb)
            ($clara + 0.05) / ($escura + 0.05)
        }

        function script:Get-TmxCssVars {
            <#
            .SYNOPSIS
                Le '--nome: valor;' de um bloco de texto CSS.
            .OUTPUTS
                Hashtable nome (sem '--') -> valor (aparado, sem ';').
            #>
            param([Parameter(Mandatory)] [string] $BlockText)
            $vars = @{}
            foreach ($m in [regex]::Matches($BlockText, '--([a-zA-Z0-9-]+)\s*:\s*([^;]+);')) {
                $vars[$m.Groups[1].Value] = $m.Groups[2].Value.Trim()
            }
            $vars
        }

        # ':root { ... }' aparece duas vezes no texto de app.css: a primeira,
        # solta, e o tema escuro; a segunda, dentro do bloco
        # '@media (prefers-color-scheme: light)', e o tema claro. Como as
        # declaracoes de variavel nao tem chaves aninhadas, o regex simples
        # '[^{}]*' basta para separar as duas sem precisar entender @media.
        $script:TextoAppCss = Get-Content -LiteralPath $script:AppCss -Raw -Encoding UTF8
        $script:BlocosRoot  = @([regex]::Matches($script:TextoAppCss, ':root\s*\{([^{}]*)\}') |
            ForEach-Object { $_.Groups[1].Value })

        $script:Dark  = @{}
        $script:Light = @{}
        if ($script:BlocosRoot.Count -ge 1) { $script:Dark  = script:Get-TmxCssVars -BlockText $script:BlocosRoot[0] }
        if ($script:BlocosRoot.Count -ge 2) { $script:Light = script:Get-TmxCssVars -BlockText $script:BlocosRoot[1] }

        $script:Arquivos = @(Get-ChildItem -LiteralPath $script:WebDir -Recurse -File |
            Where-Object { $_.Extension -in '.css', '.js', '.html' })
    }

    Context 'Nenhum azul sobrevive' {

        It 'nenhuma cor literal em src/web cai na faixa de azul (matiz 190-260, saturacao > 25%)' {
            $script:Arquivos.Count | Should -BeGreaterThan 0

            $problemas = New-Object 'System.Collections.Generic.List[string]'
            foreach ($arquivo in $script:Arquivos) {
                $texto = Get-Content -LiteralPath $arquivo.FullName -Raw -Encoding UTF8
                foreach ($cor in (script:Get-TmxColorMatches -Text $texto)) {
                    $hsl = script:Get-TmxHsl -R $cor.R -G $cor.G -B $cor.B
                    if ($hsl.H -ge 190 -and $hsl.H -le 260 -and $hsl.S -gt 25) {
                        $relativo = $arquivo.FullName.Substring($script:Raiz.Length).TrimStart('\')
                        $problemas.Add(("{0}: {1} (matiz={2} sat={3})" -f $relativo, $cor.Texto,
                            [Math]::Round($hsl.H, 1), [Math]::Round($hsl.S, 1)))
                    }
                }
            }

            $texto = $problemas.ToArray() -join "`n"
            $problemas.Count | Should -Be 0 -Because "cores azuis encontradas:`n$texto"
        }
    }

    Context 'Tokens novos em app.css' {

        It 'define --active, --active-hover, --active-fg e --elevated no tema escuro' {
            foreach ($nome in 'active', 'active-hover', 'active-fg', 'elevated') {
                $script:Dark.ContainsKey($nome) | Should -BeTrue -Because "falta --$nome no :root escuro"
            }
        }

        It 'define --active, --active-hover, --active-fg e --elevated no tema claro' {
            foreach ($nome in 'active', 'active-hover', 'active-fg', 'elevated') {
                $script:Light.ContainsKey($nome) | Should -BeTrue -Because "falta --$nome no tema claro"
            }
        }
    }

    Context 'Contraste WCAG (>= 4.5:1)' {

        # -ForEach precisa dos dados na fase de Discovery, antes de qualquer
        # BeforeAll rodar - por isso a lista e um literal aqui, nao algo
        # montado em BeforeAll.
        $paresContraste = @(
            @{ Fg = 'fg';        Bg = 'bg' }
            @{ Fg = 'fg';        Bg = 'panel' }
            @{ Fg = 'muted';     Bg = 'panel' }
            @{ Fg = 'active-fg'; Bg = 'active' }
            @{ Fg = 'accent-fg'; Bg = 'accent' }
        )

        It 'tema escuro: <Fg> sobre <Bg>' -ForEach $paresContraste {
            $script:Dark.ContainsKey($Fg) | Should -BeTrue -Because "--$Fg nao existe no tema escuro"
            $script:Dark.ContainsKey($Bg) | Should -BeTrue -Because "--$Bg nao existe no tema escuro"
            $c = script:Get-TmxContraste -HexA $script:Dark[$Fg] -HexB $script:Dark[$Bg]
            $c | Should -BeGreaterOrEqual 4.5 -Because "obtido: $([Math]::Round($c, 2)):1"
        }

        It 'tema claro: <Fg> sobre <Bg>' -ForEach $paresContraste {
            $script:Light.ContainsKey($Fg) | Should -BeTrue -Because "--$Fg nao existe no tema claro"
            $script:Light.ContainsKey($Bg) | Should -BeTrue -Because "--$Bg nao existe no tema claro"
            $c = script:Get-TmxContraste -HexA $script:Light[$Fg] -HexB $script:Light[$Bg]
            $c | Should -BeGreaterOrEqual 4.5 -Because "obtido: $([Math]::Round($c, 2)):1"
        }
    }
}
