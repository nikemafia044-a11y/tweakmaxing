# functions/install/_Wrappers.ps1
# Wrappers finos em volta de winget/choco e do catalogo de aplicativos.
#
# Nada aqui decide "o que fazer" com o resultado (isso e Invoke-TmxPackage);
# so roda o processo/comando e devolve algo testavel (codigo + saida), para
# que os testes possam mockar so este arquivo e exercitar o resto de verdade.

function Get-TmxCommandPath {
    <#
    .SYNOPSIS
        Caminho de um executavel no PATH (ou $null se nao existir).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Name)

    $cmd = Get-Command -Name $Name -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($cmd) { return "$($cmd.Source)" }
    $null
}

function Stop-TmxProcessTree {
    <#
    .SYNOPSIS
        Mata um processo e todos os filhos dele (taskkill /T /F). Nunca lanca.
    .DESCRIPTION
        Usado quando um processo externo (winget/choco/powershell) estoura o
        tempo limite: Stop-Process so mata o processo apontado, e winget/choco
        as vezes abrem um processo filho (o instalador de verdade) que
        continuaria rodando orfao.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [int] $ProcessId)

    if ($ProcessId -le 0) { return }
    try { & taskkill.exe /PID $ProcessId /T /F 2>&1 | Out-Null } catch { }
}

function ConvertFrom-TmxProcessOutputBytes {
    <#
    .SYNOPSIS
        Decodifica a saida redirecionada (bytes) de winget/choco com o
        encoding certo.
    .DESCRIPTION
        winget/choco nao documentam um encoding fixo para saida redirecionada
        - depende do codepage ativo do console no momento em que o processo
        nasce. Medido nesta maquina (Windows pt-BR, codepage ativo 65001):
        "winget list" redirecionado sai em UTF-8 SEM BOM - Get-Content sem
        -Encoding explicito le como ANSI (1252) e qualquer nome com acento
        vira mojibake (ex.: um nome com a-til/e-agudo sai com dois
        caracteres estranhos no lugar de cada um). A leitura tenta,
        nesta ordem: BOM UTF-8 explicito; UTF-8 estrito (rejeita sequencia de
        byte invalida); OEM 850 como ultimo recurso (codepage classico de
        console Windows em pt-BR quando o processo NAO nasceu em modo UTF-8 -
        ex.: uma sessao com chcp 850 ainda ativo).
    #>
    [CmdletBinding()]
    param([byte[]] $Bytes)

    if ($null -eq $Bytes -or $Bytes.Length -eq 0) { return '' }

    if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) {
        return [System.Text.Encoding]::UTF8.GetString($Bytes, 3, $Bytes.Length - 3)
    }

    try {
        $utf8Estrito = New-Object System.Text.UTF8Encoding($false, $true)
        return $utf8Estrito.GetString($Bytes)
    } catch {
        return [System.Text.Encoding]::GetEncoding(850).GetString($Bytes)
    }
}

function Invoke-TmxProcessWithTimeout {
    <#
    .SYNOPSIS
        Roda um processo externo com limite de tempo; mata a arvore inteira
        se estourar. Base comum de Invoke-TmxWingetProcess/ChocoProcess/
        Invoke-TmxPowerShellFile.
    .DESCRIPTION
        Start-Process -PassThru (sem -Wait) + Process.WaitForExit(ms), nao
        Start-Process -Wait: -Wait nao tem limite de tempo, e winget/choco
        podem ficar pendurados esperando rede/prompt que nunca chega.
    .OUTPUTS
        [pscustomobject] @{ codigo; saida }. Nunca lanca. Ao estourar o
        tempo: { codigo = -1; saida = 'tempo esgotado' }.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]   $FilePath,
        [Parameter(Mandatory)] [string[]] $Arguments,
        [int]    $TimeoutSeconds = 900,
        [string] $DescricaoErro = $FilePath
    )

    $arquivoTmp = [System.IO.Path]::GetTempFileName()
    try {
        $processo = Start-Process -FilePath $FilePath -ArgumentList $Arguments `
            -NoNewWindow -PassThru -RedirectStandardOutput $arquivoTmp -ErrorAction Stop

        $limiteMs = [Math]::Max(0, $TimeoutSeconds) * 1000
        $terminou = $processo.WaitForExit($limiteMs)

        if (-not $terminou) {
            Stop-TmxProcessTree -ProcessId $processo.Id
            return [pscustomobject]@{ codigo = -1; saida = 'tempo esgotado' }
        }

        $codigo = [int]$processo.ExitCode
        $bytes  = @()
        if (Test-Path -LiteralPath $arquivoTmp) {
            $bytes = [System.IO.File]::ReadAllBytes($arquivoTmp)
        }
        $saida = ConvertFrom-TmxProcessOutputBytes -Bytes $bytes
        [pscustomobject]@{ codigo = $codigo; saida = $saida }
    } catch {
        [pscustomobject]@{ codigo = -1; saida = "$DescricaoErro nao pode ser executado: $($_.Exception.Message)" }
    } finally {
        Remove-Item -LiteralPath $arquivoTmp -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-TmxWingetProcess {
    <#
    .SYNOPSIS
        Roda winget com os argumentos dados e devolve { codigo, saida }.
    .PARAMETER TimeoutSeconds
        Padrao 900 (install/upgrade podem baixar arquivo grande); chamadas
        curtas (--version, list) devem passar um valor bem menor.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string[]] $Arguments,
        [int] $TimeoutSeconds = 900
    )
    Invoke-TmxProcessWithTimeout -FilePath 'winget' -Arguments $Arguments -TimeoutSeconds $TimeoutSeconds -DescricaoErro 'winget'
}

function Invoke-TmxChocoProcess {
    <#
    .SYNOPSIS
        Roda choco com os argumentos dados e devolve { codigo, saida }.
    .PARAMETER TimeoutSeconds
        Ver Invoke-TmxWingetProcess.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string[]] $Arguments,
        [int] $TimeoutSeconds = 900
    )
    Invoke-TmxProcessWithTimeout -FilePath 'choco' -Arguments $Arguments -TimeoutSeconds $TimeoutSeconds -DescricaoErro 'choco'
}

function Test-TmxPackageId {
    <#
    .SYNOPSIS
        Confere se um id de pacote (winget ou choco) tem formato valido.
    .DESCRIPTION
        Winget usa "Publisher.Produto" (ponto) e o prefixo "msstore:" (dois-
        pontos) para ids da Microsoft Store, que por baixo do prefixo sao
        alfanumericos. O conjunto aceito cobre os dois formatos sem abrir
        espaco para separador de argumento, aspas ou qualquer coisa que nao
        faca sentido num --id de linha de comando.
    #>
    [CmdletBinding()]
    param([string] $Id)
    if ([string]::IsNullOrWhiteSpace($Id)) { return $false }
    $Id -cmatch '^[A-Za-z0-9_.+:@-]+$'
}

function Install-TmxWingetClientModule {
    <#
    .SYNOPSIS
        Instala/repara o winget via modulo Microsoft.WinGet.Client (PS Gallery).
    .OUTPUTS
        $true quando os dois passos rodaram sem lancar; $false caso contrario.
        Nunca lanca.
    #>
    [CmdletBinding()]
    param()

    try {
        Install-Module -Name Microsoft.WinGet.Client -Scope CurrentUser -Force -ErrorAction Stop
        Repair-WinGetPackageManager -ErrorAction Stop
        $true
    } catch {
        if (Get-Command -Name Write-TmxLog -ErrorAction SilentlyContinue) {
            Write-TmxLog -Level WARN -Message "Falha ao instalar/reparar Microsoft.WinGet.Client: $($_.Exception.Message)"
        }
        $false
    }
}

function Invoke-TmxPowerShellFile {
    <#
    .SYNOPSIS
        Roda um .ps1 como PROCESSO SEPARADO (powershell -File), nunca por
        Invoke-Expression/[scriptblock]::Create dentro deste processo.
    .DESCRIPTION
        E o unico jeito aprovado, neste projeto, de executar texto baixado da
        rede: o arquivo fica no disco (auditavel, com SHA-256 registrado por
        quem chama) e roda isolado, sem poder tocar variaveis/funcoes deste
        processo. Usa o mesmo limite de tempo + kill de arvore de
        Invoke-TmxWingetProcess/ChocoProcess (ver Invoke-TmxProcessWithTimeout).
    .OUTPUTS
        [pscustomobject] @{ codigo }. Nunca lanca (falha ao iniciar, ou tempo
        esgotado, viram codigo -1).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [int] $TimeoutSeconds = 900
    )

    $r = Invoke-TmxProcessWithTimeout -FilePath 'powershell' -Arguments @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $Path
    ) -TimeoutSeconds $TimeoutSeconds -DescricaoErro 'powershell'

    [pscustomobject]@{ codigo = $r.codigo }
}

function Invoke-TmxChocoBootstrap {
    <#
    .SYNOPSIS
        Baixa o instalador oficial do Chocolatey para disco e roda como
        processo separado (so deve ser chamado depois de consentimento
        explicito na UI - a ponte (Actions.Install.ps1) recusa
        apps.installChoco sem { consentido: true }, e o modal que pede esse
        consentimento mora em install.js).
    .DESCRIPTION
        Nunca executa o texto baixado dentro deste processo (sem
        Invoke-Expression, sem [scriptblock]::Create): o instalador vai para
        <home>\downloads\choco-install.ps1, o SHA-256 fica no log, e quem
        roda o arquivo e um powershell -File separado
        (Invoke-TmxPowerShellFile), isolado deste processo.

        O SHA-256 e trilha de auditoria (fica no log para conferencia manual
        depois), NAO verificacao: o instalador oficial muda com frequencia e
        a Chocolatey Software nao publica um hash fixo esperado para
        comparar contra. Sem esse hash de referencia, um mismatch aqui nao
        teria contra o que ser comparado - so registrar o que foi executado
        importa. A execucao em processo separado, so depois de consentimento
        explicito na UI, e o controle real; o hash e so para investigar
        depois, se precisar.
    .OUTPUTS
        [pscustomobject] @{ ok; sha256; detalhe }. Nunca lanca.
    #>
    [CmdletBinding()]
    param()

    try {
        # PS 5.1 pode negociar um protocolo que o site recusa; o instalador
        # oficial forca TLS 1.2 pelo mesmo motivo.
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

        $pastaDownloads = Join-Path (Get-TmxUiHomePath) 'downloads'
        New-Item -ItemType Directory -Path $pastaDownloads -Force -ErrorAction Stop | Out-Null
        $arquivoInstalador = Join-Path $pastaDownloads 'choco-install.ps1'

        Invoke-WebRequest -Uri 'https://community.chocolatey.org/install.ps1' -UseBasicParsing -TimeoutSec 60 `
            -OutFile $arquivoInstalador -ErrorAction Stop

        $sha256 = (Get-FileHash -LiteralPath $arquivoInstalador -Algorithm SHA256).Hash.ToLowerInvariant()

        if (Get-Command -Name Write-TmxLog -ErrorAction SilentlyContinue) {
            Write-TmxLog -Level INFO -Message 'Instalador do Chocolatey baixado' -Data @{ sha256 = $sha256; caminho = $arquivoInstalador }
        }

        $r = Invoke-TmxPowerShellFile -Path $arquivoInstalador
        if ($r.codigo -ne 0) {
            return [pscustomobject]@{ ok = $false; sha256 = $sha256; detalhe = "instalador do Chocolatey saiu com codigo $($r.codigo)" }
        }

        if (-not (Get-Command -Name choco -ErrorAction SilentlyContinue)) {
            return [pscustomobject]@{ ok = $false; sha256 = $sha256; detalhe = 'choco nao apareceu no PATH apos a instalacao' }
        }

        [pscustomobject]@{ ok = $true; sha256 = $sha256; detalhe = 'Chocolatey instalado' }
    } catch {
        [pscustomobject]@{ ok = $false; sha256 = $null; detalhe = $_.Exception.Message }
    }
}

function Get-TmxAppCatalog {
    <#
    .SYNOPSIS
        Lista achatada dos aplicativos do catalogo: { id, nome, descricao,
        categoria, winget, choco, link, foss }.
    .DESCRIPTION
        Prioridade: $sync.configs.applications (ja carregado por
        Start-TmxDev.ps1/scripts/start.ps1). Sem isso, le
        src/config/applications.json a partir de $sync.webRoot. Lanca so
        quando nenhuma das duas fontes existe - um catalogo ausente e um erro
        de configuracao, nao um caso silencioso.

        Valida (so registra aviso; nao remove nem altera nada) os ids de
        winget/choco de cada app contra Test-TmxPackageId. A recusa de
        verdade - falha sem chamar o processo - acontece em
        Invoke-TmxPackage, na hora de montar os argumentos; aqui e so para o
        log denunciar cedo um catalogo com id mal formado.
    #>
    [CmdletBinding()]
    param()

    $doc = $null

    if ($null -ne $sync -and $null -ne $sync.configs -and $null -ne $sync.configs.applications) {
        $doc = $sync.configs.applications
    } elseif ($null -ne $sync -and $sync.webRoot) {
        $caminho = Join-Path (Split-Path "$($sync.webRoot)" -Parent) 'config\applications.json'
        if (Test-Path -LiteralPath $caminho) {
            $doc = Get-Content -LiteralPath $caminho -Raw -Encoding UTF8 | ConvertFrom-Json
        }
    }

    if ($null -eq $doc) {
        throw 'catalogo de aplicativos nao encontrado (nem $sync.configs.applications, nem src/config/applications.json).'
    }

    $apps = @($doc.aplicativos)

    if (Get-Command -Name Write-TmxLog -ErrorAction SilentlyContinue) {
        foreach ($app in $apps) {
            $idWinget = "$($app.winget)"
            $idChoco  = "$($app.choco)"
            if ($idWinget -and -not (Test-TmxPackageId -Id $idWinget)) {
                Write-TmxLog -Level WARN -Message 'Catalogo: id de winget mal formado' -Data @{ appId = "$($app.id)"; winget = $idWinget }
            }
            if ($idChoco -and -not (Test-TmxPackageId -Id $idChoco)) {
                Write-TmxLog -Level WARN -Message 'Catalogo: id de choco mal formado' -Data @{ appId = "$($app.id)"; choco = $idChoco }
            }
        }
    }

    # A virgula evita que um catalogo de 1 app so seja desenrolado no pipeline.
    ,$apps
}
