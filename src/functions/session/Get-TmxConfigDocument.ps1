# functions/session/Get-TmxConfigDocument.ps1
# Fonte unica dos documentos de src/config, para dev E para o artefato unico.
#
# Duas origens, nesta ordem:
#   1. $sync.configs['<nome>'] - ja parseado. No Start-TmxDev.ps1 vem dos
#      arquivos; no TweakMaxing.ps1 compilado vem das here-strings embutidas
#      pelo Compile.ps1. E a unica origem que existe no compilado.
#   2. <repo>\src\config\<nome>.json, derivado de $sync.webRoot (<repo>\src\web).
#      Nunca de $PSScriptRoot: dentro de uma runspace do pool as funcoes chegam
#      como texto e $PSScriptRoot e $null.
#
# Sem nenhuma das duas o retorno e $null: quem chama decide se isso e erro de
# configuracao (a maioria lanca) ou caso silencioso.

function Get-TmxConfigDir {
    <#
    .SYNOPSIS
        Pasta src/config derivada de $sync.webRoot, ou $null.
    #>
    [CmdletBinding()]
    param()

    if ($null -ne $sync -and $sync.webRoot) {
        $dir = Join-Path (Split-Path "$($sync.webRoot)" -Parent) 'config'
        if (Test-Path -LiteralPath $dir) { return "$dir" }
    }
    $null
}

function Get-TmxConfigDocument {
    <#
    .SYNOPSIS
        Documento JSON de src/config ja parseado, ou $null.
    .PARAMETER Name
        Nome do arquivo sem '.json' (tweaks, tweaks.jogos, tweaks.updates,
        applications, feature, appx, dns, preset) - a mesma chave usada em
        $sync.configs.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Name)

    $cfg = $null
    if ($null -ne $sync) { $cfg = $sync.configs }
    # .Contains() explicito: com StrictMode ligado, $cfg.$Name numa hashtable
    # sem a chave quebraria em vez de devolver $null.
    if ($null -ne $cfg -and $cfg -is [System.Collections.IDictionary] -and $cfg.Contains($Name)) {
        $doc = $cfg[$Name]
        if ($null -ne $doc) { return $doc }
    }

    $dir = Get-TmxConfigDir
    if ($dir) {
        $caminho = Join-Path $dir "$Name.json"
        if (Test-Path -LiteralPath $caminho) {
            return (Get-Content -LiteralPath $caminho -Raw -Encoding UTF8 | ConvertFrom-Json)
        }
    }
    $null
}

function Get-TmxConfigDocumentName {
    <#
    .SYNOPSIS
        Nomes de documento disponiveis que batem um curinga (ex.: 'tweaks*'),
        em ordem alfabetica.
    .DESCRIPTION
        Usado pelo catalogo, que e a concatenacao de todo tweaks*.json. Olha
        $sync.configs primeiro (unica origem do compilado) e so vai ao disco
        quando nao ha nada carregado.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Pattern)

    $nomes = New-Object 'System.Collections.Generic.List[string]'

    $cfg = $null
    if ($null -ne $sync) { $cfg = $sync.configs }
    if ($null -ne $cfg -and $cfg -is [System.Collections.IDictionary]) {
        # @($cfg.Keys): 'foreach' sobre uma hashtable VAZIA no PS 5.1 devolve a
        # propria hashtable, nao zero itens.
        foreach ($chave in @(@($cfg.Keys) | Sort-Object)) {
            if ("$chave" -like $Pattern) { $nomes.Add("$chave") }
        }
    }

    if ($nomes.Count -eq 0) {
        $dir = Get-TmxConfigDir
        if ($dir) {
            foreach ($arquivo in @(Get-ChildItem -LiteralPath $dir -Filter "$Pattern.json" -File | Sort-Object Name)) {
                $nomes.Add($arquivo.BaseName)
            }
        }
    }

    # .ToArray(): @() sobre List generica vazia falha no PS 5.1
    $nomes.ToArray()
}
