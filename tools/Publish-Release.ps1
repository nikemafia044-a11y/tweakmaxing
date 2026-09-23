<#
.SYNOPSIS
    Publica uma release versionada do TweakMaxing no GitHub.
.DESCRIPTION
    Passos, nesta ordem:
      1. Valida -Repo ('usuario/repositorio') e grava em REPO (idempotente).
      2. Le VERSION (ou grava -Version, que tambem atualiza o arquivo).
      3. Exige working tree limpa ANTES de qualquer escrita (git status
         --porcelain vazio); so entao grava REPO/VERSION e comita
         'chore(release): vX.Y.Z' se algo mudou.
      4. -CreateRepo: se o remoto 'origin' nao existir, roda
         'gh repo create <repo> --public --source . --push'. Se existir com
         URL diferente da esperada, falha (nao mexe no remoto de outro jeito).
      5. Roda .\Compile.ps1 -Repo <repo> (e -SkipSdk, se pedido).
      6. Confere que TweakMaxing.ps1 saiu, calcula o SHA256 e grava
         SHA256SUMS.txt no formato '<hash>  TweakMaxing.ps1'.
      7. Confere que docs\release-notes\v<versao>.md existe.
      8. Cria a tag anotada v<versao> (pula se ja existir apontando pro HEAD;
         falha se existir apontando para outro commit).
      9. Empurra 'main' e a tag, depois roda
         'gh release create v<versao> TweakMaxing.ps1 SHA256SUMS.txt
          --title "TweakMaxing v<versao>" --notes-file docs/release-notes/v<versao>.md'.

    -DryRun ainda compila e calcula o hash (e cria a tag local), mas so
    IMPRIME os comandos de 'git push' e 'gh' em vez de rodar - nenhum
    acesso de rede acontece.

    -NoPush pula 'git push' e 'gh release create' (so imprime os comandos
    que rodariam). Incompativel com -CreateRepo (que precisa empurrar para
    criar o remoto).

    Nunca usa Invoke-Expression; todo comando externo roda com argumentos
    em array.
.PARAMETER Repo
    'usuario/repositorio'. Obrigatorio.
.PARAMETER Gh
    Caminho do executavel gh. Padrao: tools\gh\bin\gh.exe se existir, senao
    'gh' do PATH.
.PARAMETER Version
    Versao x.y.z a gravar em VERSION antes de compilar. Sem isso, usa o que
    ja estiver em VERSION.
.PARAMETER DryRun
    Compila e cria a tag local, mas so imprime 'git push'/'gh' em vez de
    rodar.
.PARAMETER NoPush
    Nao empurra nada nem publica a release; so imprime os comandos.
.PARAMETER CreateRepo
    Cria o repositorio remoto (gh repo create --push) se 'origin' nao
    existir ainda.
.PARAMETER SkipSdk
    Repassado para Compile.ps1 -SkipSdk (artefato sem as DLLs do WebView2).
.EXAMPLE
    .\tools\Publish-Release.ps1 -Repo fulano/tweakmaxing -CreateRepo
.EXAMPLE
    .\tools\Publish-Release.ps1 -Repo fulano/tweakmaxing -Version 0.2.0
.EXAMPLE
    .\tools\Publish-Release.ps1 -Repo fulano/tweakmaxing -DryRun -SkipSdk
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Repo,
    [string] $Gh,
    [string] $Version,
    [switch] $DryRun,
    [switch] $NoPush,
    [switch] $CreateRepo,
    [switch] $SkipSdk
)

$ErrorActionPreference = 'Stop'

if ($CreateRepo -and $NoPush) {
    throw '-CreateRepo e -NoPush sao incompativeis: -CreateRepo precisa empurrar para criar o remoto.'
}

if ($Repo -notmatch '^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$') {
    throw "Repositorio invalido: '$Repo' (esperado 'usuario/repositorio', ex. 'fulano/tweakmaxing')."
}

if ($Version -and $Version -notmatch '^\d+\.\d+\.\d+$') {
    throw "Versao invalida: '$Version' (esperado x.y.z, ex. 0.2.0)."
}

# ---------------------------------------------------------------------------
# Auxiliares
# ---------------------------------------------------------------------------

function Set-TmxValueFile {
    <#
    .SYNOPSIS
        Grava $Value na primeira linha nao-vazia/nao-comentario de $Path,
        preservando o resto do arquivo (comentarios, se houver). Cria o
        arquivo se nao existir. Devolve $true se o conteudo mudou.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Value
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        Set-Content -LiteralPath $Path -Value $Value -Encoding ASCII -NoNewline
        Add-Content -LiteralPath $Path -Value '' -Encoding ASCII
        return $true
    }

    $linhas = @(Get-Content -LiteralPath $Path)
    $trocou = $false
    $mudou  = $false
    $novo = New-Object 'System.Collections.Generic.List[string]'
    foreach ($linha in $linhas) {
        $t = "$linha".Trim()
        if (-not $trocou -and $t -and -not $t.StartsWith('#')) {
            if ($t -ne $Value) { $mudou = $true }
            $novo.Add($Value)
            $trocou = $true
        } else {
            $novo.Add($linha)
        }
    }
    if (-not $trocou) {
        $novo.Add($Value)
        $mudou = $true
    }
    if ($mudou) {
        Set-Content -LiteralPath $Path -Value $novo.ToArray() -Encoding ASCII
    }
    $mudou
}

function Invoke-TmxNative {
    <#
    .SYNOPSIS
        Roda um executavel nativo com argumentos em array e devolve codigo +
        saida (stdout e stderr juntos, como texto).
    .DESCRIPTION
        Nao usa '2>&1' direto com $ErrorActionPreference = 'Stop': no
        PowerShell 5.1 isso empacota CADA linha da stderr de um executavel
        nativo num NativeCommandError e vira erro terminante mesmo quando o
        processo sai com codigo 0 (ex.: o aviso de CRLF do git, ou a
        mensagem "nao esta autenticado" do gh auth status). Por isso o EAP
        vira 'Continue' so ao redor desta chamada.
    .OUTPUTS
        [pscustomobject]@{ Codigo; Saida (string[]) }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]   $FilePath,
        [Parameter(Mandatory)] [string[]] $Args
    )

    $eapAnterior = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $bruto = & $FilePath @Args 2>&1
    } finally {
        $ErrorActionPreference = $eapAnterior
    }
    $saida = @($bruto | ForEach-Object { "$_" })
    [pscustomobject]@{ Codigo = $LASTEXITCODE; Saida = $saida }
}

function Invoke-TmxGit {
    <#
    .SYNOPSIS
        Roda git com argumentos em array; lanca com a saida se o codigo de
        saida nao for zero.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string[]] $Args)

    $r = Invoke-TmxNative -FilePath 'git' -Args $Args
    if ($r.Codigo -ne 0) {
        throw "git $($Args -join ' ') falhou (codigo $($r.Codigo)):`n$($r.Saida -join "`n")"
    }
    $r.Saida
}

# ---------------------------------------------------------------------------
# 1. Raiz do repositorio e arvore limpa (antes de qualquer escrita)
# ---------------------------------------------------------------------------

$tmxRaiz = Split-Path -Parent $PSScriptRoot
if (-not $tmxRaiz) { $tmxRaiz = (Get-Location).Path }

Push-Location $tmxRaiz
try {
    $rGit = Invoke-TmxNative -FilePath 'git' -Args @('rev-parse', '--is-inside-work-tree')
    if ($rGit.Codigo -ne 0) { throw "Nao e um repositorio git: $tmxRaiz" }

    $statusAntes = @(& git status --porcelain)
    if ($statusAntes.Count -gt 0) {
        throw "Working tree suja. Comite ou descarte as mudancas antes de publicar:`n$($statusAntes -join "`n")"
    }

    # -----------------------------------------------------------------------
    # 2. REPO / VERSION
    # -----------------------------------------------------------------------

    $arquivoRepo    = Join-Path $tmxRaiz 'REPO'
    $arquivoVersao  = Join-Path $tmxRaiz 'VERSION'

    $repoMudou = Set-TmxValueFile -Path $arquivoRepo -Value $Repo

    if ($Version) {
        $versaoMudou = Set-TmxValueFile -Path $arquivoVersao -Value $Version
        $versao = $Version
    } else {
        if (-not (Test-Path -LiteralPath $arquivoVersao)) { throw "VERSION nao encontrado em $tmxRaiz (ou use -Version)." }
        $versao = (Get-Content -LiteralPath $arquivoVersao -Raw).Trim()
        $versaoMudou = $false
    }
    if (-not $versao) { throw 'VERSION esta vazio.' }

    if ($repoMudou -or $versaoMudou) {
        Invoke-TmxGit -Args @('add', '--', 'REPO', 'VERSION') | Out-Null
        Invoke-TmxGit -Args @('commit', '-m', "chore(release): v$versao") | Out-Null
        Write-Host "Commit 'chore(release): v$versao' criado (REPO/VERSION)." -ForegroundColor Cyan
    }

    $tag = "v$versao"

    # -----------------------------------------------------------------------
    # 3. gh: caminho e -CreateRepo
    # -----------------------------------------------------------------------

    $ghPath = $Gh
    if (-not $ghPath) {
        $ghPortavel = Join-Path $tmxRaiz 'tools\gh\bin\gh.exe'
        $ghPath = if (Test-Path -LiteralPath $ghPortavel) { $ghPortavel } else { 'gh' }
    }

    $rRemote = Invoke-TmxNative -FilePath 'git' -Args @('remote', 'get-url', 'origin')
    $temRemote = ($rRemote.Codigo -eq 0)
    $remoteUrl = if ($temRemote) { ($rRemote.Saida -join "`n").Trim() } else { $null }

    if ($CreateRepo) {
        if ($temRemote) {
            $esperados = @("https://github.com/$Repo.git", "https://github.com/$Repo", "git@github.com:$Repo.git")
            if ($esperados -notcontains $remoteUrl) {
                throw "Remoto 'origin' ja existe com URL diferente ('$remoteUrl'); -CreateRepo nao vai mexer nele. Remova o remoto ou ajuste -Repo."
            }
            Write-Host "Remoto 'origin' ja aponta para $Repo; -CreateRepo ignorado (idempotente)." -ForegroundColor Cyan
        } else {
            $argsCreate = @('repo', 'create', $Repo, '--public', '--source', '.', '--push')
            if ($DryRun) {
                Write-Host "[DryRun] $ghPath $($argsCreate -join ' ')"
            } else {
                $rAuth = Invoke-TmxNative -FilePath $ghPath -Args @('auth', 'status')
                if ($rAuth.Codigo -ne 0) {
                    throw "gh nao esta autenticado (necessario para -CreateRepo). Rode '$ghPath auth login' e tente de novo.`n$($rAuth.Saida -join "`n")"
                }
                & $ghPath @argsCreate
                if ($LASTEXITCODE -ne 0) { throw "gh repo create falhou (codigo $LASTEXITCODE)." }
                $temRemote = $true
            }
        }
    } elseif (-not $temRemote) {
        Write-Warning "Remoto 'origin' nao existe. Use -CreateRepo na primeira publicacao ou rode 'git remote add origin ...' manualmente."
    }

    # -----------------------------------------------------------------------
    # 4. Compilar
    # -----------------------------------------------------------------------

    # Hashtable, nao array: splat de array em PS 5.1 liga por POSICAO, nao
    # por nome - '-Repo', $Repo, '-SkipSdk' num array viraria 3 argumentos
    # posicionais e quebraria o param() do Compile.ps1. So hashtable liga
    # por nome (e o unico jeito de splat um [switch]).
    $compileScript = Join-Path $tmxRaiz 'Compile.ps1'
    $compileParams = @{ Repo = $Repo }
    if ($SkipSdk) { $compileParams['SkipSdk'] = $true }

    Write-Host ("Compilando: Compile.ps1 -Repo {0}{1}" -f $Repo, $(if ($SkipSdk) { ' -SkipSdk' } else { '' })) -ForegroundColor Cyan
    try {
        & $compileScript @compileParams
    } catch {
        throw "Compile.ps1 falhou: $($_.Exception.Message)"
    }

    $artefato = Join-Path $tmxRaiz 'TweakMaxing.ps1'
    if (-not (Test-Path -LiteralPath $artefato)) { throw "Compile.ps1 rodou mas $artefato nao foi encontrado." }

    $hash = (Get-FileHash -LiteralPath $artefato -Algorithm SHA256).Hash
    $sumsPath = Join-Path $tmxRaiz 'SHA256SUMS.txt'
    Set-Content -LiteralPath $sumsPath -Value ("{0}  {1}" -f $hash, 'TweakMaxing.ps1') -Encoding ASCII

    Write-Host ("SHA256: {0}" -f $hash) -ForegroundColor Cyan

    # -----------------------------------------------------------------------
    # 5. Notas de release
    # -----------------------------------------------------------------------

    $notas = Join-Path $tmxRaiz "docs\release-notes\$tag.md"
    if (-not (Test-Path -LiteralPath $notas)) {
        throw "Notas de release ausentes: docs\release-notes\$tag.md. Crie o arquivo antes de publicar."
    }

    # -----------------------------------------------------------------------
    # 6. Tag anotada
    # -----------------------------------------------------------------------

    $tagLista = & git tag -l $tag
    $tagExiste = ("$tagLista".Trim() -eq $tag)

    if ($tagExiste) {
        $tagCommit  = (Invoke-TmxGit -Args @('rev-parse', "$tag^{commit}") | Select-Object -Last 1).Trim()
        $headCommit = (Invoke-TmxGit -Args @('rev-parse', 'HEAD') | Select-Object -Last 1).Trim()
        if ($tagCommit -ne $headCommit) {
            throw "A tag $tag ja existe e aponta para outro commit ($tagCommit; HEAD e $headCommit). Ajuste VERSION ou remova a tag manualmente."
        }
        Write-Host "Tag $tag ja existe e aponta para HEAD; nao recriada." -ForegroundColor Cyan
    } else {
        Invoke-TmxGit -Args @('tag', '-a', $tag, '-m', "TweakMaxing $tag") | Out-Null
        Write-Host "Tag $tag criada." -ForegroundColor Cyan
    }

    # -----------------------------------------------------------------------
    # 7. Push + gh release create
    # -----------------------------------------------------------------------

    $ghArgsRelease = @(
        'release', 'create', $tag, 'TweakMaxing.ps1', 'SHA256SUMS.txt',
        '--title', "TweakMaxing $tag",
        '--notes-file', "docs/release-notes/$tag.md"
    )

    if ($NoPush) {
        Write-Host '-NoPush: nada empurrado. Comandos que rodariam:' -ForegroundColor Yellow
        Write-Host '  git push origin main'
        Write-Host "  git push origin $tag"
        Write-Host "  $ghPath $($ghArgsRelease -join ' ')"
    } elseif ($DryRun) {
        Write-Host '[DryRun] git push origin main'
        Write-Host "[DryRun] git push origin $tag"
        Write-Host "[DryRun] $ghPath $($ghArgsRelease -join ' ')"
    } else {
        $rAuth = Invoke-TmxNative -FilePath $ghPath -Args @('auth', 'status')
        if ($rAuth.Codigo -ne 0) {
            throw "gh nao esta autenticado (necessario para publicar). Rode '$ghPath auth login' e tente de novo.`n$($rAuth.Saida -join "`n")"
        }

        Invoke-TmxGit -Args @('push', 'origin', 'main') | Out-Null
        Invoke-TmxGit -Args @('push', 'origin', $tag) | Out-Null

        & $ghPath @ghArgsRelease
        if ($LASTEXITCODE -ne 0) { throw "gh release create falhou (codigo $LASTEXITCODE)." }
    }

    # -----------------------------------------------------------------------
    # 8. Resumo
    # -----------------------------------------------------------------------

    $launcher = "https://github.com/$Repo/releases/download/$tag/TweakMaxing.ps1"
    Write-Host ''
    Write-Host 'Lancador:' -ForegroundColor Green
    Write-Host "  irm $launcher | iex"
    Write-Host ("SHA256: {0}" -f $hash)
} finally {
    Pop-Location
}
