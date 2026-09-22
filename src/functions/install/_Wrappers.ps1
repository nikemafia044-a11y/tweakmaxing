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

function Invoke-TmxWingetProcess {
    <#
    .SYNOPSIS
        Roda winget com os argumentos dados e devolve { codigo, saida }.
    .DESCRIPTION
        Start-Process (nao Invoke-Expression/&): winget as vezes escreve saida
        colorida/interativa que trava um pipe simples; redirecionar so o
        stdout para um arquivo temporario evita isso e ainda deixa ler o texto
        depois. Nunca lanca - uma falha ao iniciar o processo vira codigo -1.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string[]] $Arguments)

    $arquivoTmp = [System.IO.Path]::GetTempFileName()
    try {
        $processo = Start-Process -FilePath 'winget' -ArgumentList $Arguments `
            -NoNewWindow -Wait -PassThru -RedirectStandardOutput $arquivoTmp -ErrorAction Stop

        $saida = ''
        if (Test-Path -LiteralPath $arquivoTmp) {
            $conteudo = Get-Content -LiteralPath $arquivoTmp -Raw -ErrorAction SilentlyContinue
            if ($null -ne $conteudo) { $saida = [string]$conteudo }
        }
        [pscustomobject]@{ codigo = [int]$processo.ExitCode; saida = $saida }
    } catch {
        [pscustomobject]@{ codigo = -1; saida = "winget nao pode ser executado: $($_.Exception.Message)" }
    } finally {
        Remove-Item -LiteralPath $arquivoTmp -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-TmxChocoProcess {
    <#
    .SYNOPSIS
        Roda choco com os argumentos dados e devolve { codigo, saida }.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string[]] $Arguments)

    $arquivoTmp = [System.IO.Path]::GetTempFileName()
    try {
        $processo = Start-Process -FilePath 'choco' -ArgumentList $Arguments `
            -NoNewWindow -Wait -PassThru -RedirectStandardOutput $arquivoTmp -ErrorAction Stop

        $saida = ''
        if (Test-Path -LiteralPath $arquivoTmp) {
            $conteudo = Get-Content -LiteralPath $arquivoTmp -Raw -ErrorAction SilentlyContinue
            if ($null -ne $conteudo) { $saida = [string]$conteudo }
        }
        [pscustomobject]@{ codigo = [int]$processo.ExitCode; saida = $saida }
    } catch {
        [pscustomobject]@{ codigo = -1; saida = "choco nao pode ser executado: $($_.Exception.Message)" }
    } finally {
        Remove-Item -LiteralPath $arquivoTmp -Force -ErrorAction SilentlyContinue
    }
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
        processo.
    .OUTPUTS
        [pscustomobject] @{ codigo }. Nunca lanca (falha ao iniciar vira -1).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)

    try {
        $processo = Start-Process -FilePath 'powershell' -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $Path
        ) -NoNewWindow -Wait -PassThru -ErrorAction Stop
        [pscustomobject]@{ codigo = [int]$processo.ExitCode }
    } catch {
        [pscustomobject]@{ codigo = -1 }
    }
}

function Invoke-TmxChocoBootstrap {
    <#
    .SYNOPSIS
        Baixa o instalador oficial do Chocolatey para disco e roda como
        processo separado (so deve ser chamado depois de consentimento
        explicito na UI - o modal de confirmacao mora em install.js, nao
        aqui).
    .DESCRIPTION
        Nunca executa o texto baixado dentro deste processo (sem
        Invoke-Expression, sem [scriptblock]::Create): o instalador vai para
        <home>\downloads\choco-install.ps1, o SHA-256 fica no log como
        trilha de auditoria, e quem roda o arquivo e um powershell -File
        separado (Invoke-TmxPowerShellFile), isolado deste processo.
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

    # A virgula evita que um catalogo de 1 app so seja desenrolado no pipeline.
    ,@($doc.aplicativos)
}
