# functions/microwin/New-TmxUnattend.ps1
# Geracao do autounattend.xml a partir de tools/microwin/autounattend.template.xml.
#
# A senha passa por aqui e NAO pode vazar: nada neste arquivo chama
# Write-TmxLog com a senha, nem a coloca em mensagem de erro. O unico lugar em
# que ela aparece e dentro do XML gerado - que e exatamente o que o Windows
# precisa ler durante o OOBE.

function Get-TmxMicroWinTemplatePath {
    <#
    .SYNOPSIS
        Caminho do modelo autounattend.template.xml, ou $null.
    .DESCRIPTION
        Procura em varias raizes porque este codigo tambem roda DENTRO da
        runspace do pool de jobs, onde as funcoes sao recriadas a partir do
        texto e $PSScriptRoot pode chegar vazio. Por isso a busca comeca pelo
        ambiente ($env:TMX_MICROWIN_TEMPLATE, $env:TMX_DEV_ENTRY) e por
        $sync.webRoot, que atravessam a fronteira de runspace.
    #>
    [CmdletBinding()]
    param()

    $relativo = 'tools\microwin\autounattend.template.xml'
    $candidatos = New-Object 'System.Collections.Generic.List[string]'

    if ($env:TMX_MICROWIN_TEMPLATE) { $candidatos.Add("$env:TMX_MICROWIN_TEMPLATE") }

    if ($env:TMX_DEV_ENTRY) {
        $raiz = Split-Path -Parent "$env:TMX_DEV_ENTRY"
        if ($raiz) { $candidatos.Add((Join-Path $raiz $relativo)) }
    }

    if ($null -ne $sync -and $sync.webRoot) {
        # <repo>\src\web -> <repo>
        $raiz = Split-Path -Parent (Split-Path -Parent "$($sync.webRoot)")
        if ($raiz) { $candidatos.Add((Join-Path $raiz $relativo)) }
    }

    if ($PSScriptRoot) {
        # <repo>\src\functions\microwin -> <repo>
        $raiz = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        if ($raiz) { $candidatos.Add((Join-Path $raiz $relativo)) }
    }

    foreach ($c in $candidatos.ToArray()) {
        if ($c -and (Test-Path -LiteralPath $c)) { return "$c" }
    }
    $null
}

function Remove-TmxUnattendFile {
    <#
    .SYNOPSIS
        Sobrescreve o autounattend.xml com zeros e apaga. Nunca lanca.
    .DESCRIPTION
        O arquivo carrega a senha da conta local em TEXTO PURO (e assim que o
        Windows Setup a le). Ele so precisa existir entre o passo que o grava e
        o oscdimg: depois disso nao pode sobrar na pasta de trabalho, nem
        quando o build falha no meio.

        Sobrescrever antes de apagar e reducao de risco, nao garantia: em SSD
        com TRIM, ou num sistema de arquivos copy-on-write, o bloco original
        pode continuar no disco. O que garante alguma coisa e o arquivo nao
        ficar la.
    .OUTPUTS
        $true quando o arquivo nao existe mais no fim.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $true }

    try {
        $item = Get-Item -LiteralPath $Path -ErrorAction Stop
        if ($item.IsReadOnly) { $item.IsReadOnly = $false }

        $tamanho = [int]$item.Length
        if ($tamanho -gt 0) {
            $zeros = New-Object byte[] $tamanho
            [System.IO.File]::WriteAllBytes($item.FullName, $zeros)
        }
        Remove-Item -LiteralPath $item.FullName -Force -ErrorAction Stop
        $true
    } catch {
        Write-TmxLog -Level WARN -Message 'MicroWin: autounattend.xml nao pode ser apagado' -Data @{
            caminho = "$Path"; erro = "$($_.Exception.Message)"
        }
        -not (Test-Path -LiteralPath $Path)
    }
}

function Get-TmxKeyboardLayout {
    <#
    .SYNOPSIS
        Layout de teclado do idioma (pt-BR -> 0416:00000416). Desconhecido cai em en-US.
    #>
    [CmdletBinding()]
    param([string] $Idioma)

    # A tabela mora DENTRO da funcao de proposito: uma '$script:Tmx...' no topo
    # do arquivo nao atravessa a fronteira de runspace (a janela e o pool de
    # jobs recebem funcoes, nao variaveis de escopo de script) e chegaria $null.
    $teclados = @{
        'pt-BR' = '0416:00000416'
        'en-US' = '0409:00000409'
        'es-ES' = '040A:0000040A'
    }
    $chave = "$Idioma"
    if ($teclados.ContainsKey($chave)) { return $teclados[$chave] }
    '0409:00000409'
}

function New-TmxUnattend {
    <#
    .SYNOPSIS
        Preenche o modelo e devolve o XML do autounattend.xml como string.
    .PARAMETER Usuario
        Nome da conta local de administrador criada no OOBE.
    .PARAMETER Senha
        Senha dessa conta. Vai escapada para o XML e nunca para o log.
    .PARAMETER Idioma
        Locale/UI, ex.: 'pt-BR'.
    .PARAMETER TemplatePath
        Modelo alternativo. Sem ele, Get-TmxMicroWinTemplatePath resolve.
    .OUTPUTS
        O XML (string). Lanca se o resultado nao for XML valido.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Usuario,
        [string] $Senha = '',
        [string] $Idioma = 'pt-BR',
        [string] $TemplatePath
    )

    if (-not "$Usuario".Trim()) { throw 'usuario obrigatorio' }

    $modelo = $TemplatePath
    if (-not $modelo) { $modelo = Get-TmxMicroWinTemplatePath }
    if (-not $modelo -or -not (Test-Path -LiteralPath $modelo)) {
        throw 'modelo autounattend.template.xml nao encontrado (tools\microwin)'
    }

    # [string]: Get-Content -Raw ja devolve string, mas sem a conversao o
    # objeto carrega PSPath/PSProvider como NoteProperty e qualquer
    # ConvertTo-Json mais adiante desce por esse grafo ate travar.
    $texto = [string](Get-Content -LiteralPath $modelo -Raw -Encoding UTF8)
    if (-not $texto) { throw "modelo vazio: $modelo" }

    $teclado = Get-TmxKeyboardLayout -Idioma $Idioma

    # SecurityElement::Escape cobre & < > " ' - uma senha com '<' ou '&' sem
    # isso geraria um XML que o Windows Setup ignora inteiro.
    $texto = $texto.Replace('{{USUARIO}}', [System.Security.SecurityElement]::Escape("$Usuario"))
    $texto = $texto.Replace('{{SENHA}}',   [System.Security.SecurityElement]::Escape("$Senha"))
    $texto = $texto.Replace('{{IDIOMA}}',  [System.Security.SecurityElement]::Escape("$Idioma"))
    $texto = $texto.Replace('{{TECLADO}}', [System.Security.SecurityElement]::Escape("$teclado"))

    try {
        [xml]$conferencia = $texto
        if ($null -eq $conferencia.DocumentElement) { throw 'documento sem elemento raiz' }
    } catch {
        # A mensagem original pode carregar o trecho do XML (ou seja, a senha):
        # so a posicao do erro sobe daqui.
        throw 'o autounattend.xml gerado nao e um XML valido'
    }

    Write-TmxLog -Level INFO -Message 'autounattend.xml gerado' -Data @{ usuario = "$Usuario"; idioma = "$Idioma"; teclado = "$teclado" }
    $texto
}
