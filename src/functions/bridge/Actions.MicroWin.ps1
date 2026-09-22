# functions/bridge/Actions.MicroWin.ps1
# Acoes da ponte para a aba "MicroWin": ISO enxuta do Windows.
#
# Regras herdadas das outras abas:
#   - o que demora vai para o pool de jobs (um por vez);
#   - a pre-validacao acontece na thread da janela, ANTES de existir job: com
#     -Async a resposta imediata ja teria dito ok:true e o erro so apareceria
#     no job.done.
#
# Regra propria desta aba: a SENHA nunca e registrada. Nada aqui passa
# $payload.senha para Write-TmxLog, nem a devolve no resultado.
#
# Nao ha gravacao em pendrive: o produto final e um arquivo .iso.

# Constantes em FUNCAO e nao em '$script:Tmx...': a janela roda numa runspace
# propria, montada a partir de um InitialSessionState que leva as funcoes, e
# as variaveis de escopo de script deste arquivo NAO chegam la. Com elas
# ausentes o regex virava $null e '-match $null' aceita qualquer texto - ou
# seja, a validacao do nome de usuario deixaria de existir justamente na
# janela de verdade (foi assim que o bug apareceu).

function Get-TmxMicroWinUsuarioRegex { '^[A-Za-z][A-Za-z0-9_-]{0,19}$' }
function Get-TmxMicroWinAdkUrl       { 'https://learn.microsoft.com/windows-hardware/get-started/adk-install' }
function Get-TmxMicroWinEspacoMinimoGB { 20 }

function Get-TmxMicroWinAppCatalog {
    <#
    .SYNOPSIS
        Os appx removiveis de src/config/appx.json: { id, nome, descricao, pacote }.
    .DESCRIPTION
        Prioridade: $sync.configs.appx (carregado por Start-TmxDev.ps1 /
        scripts/start.ps1); depois src/config/appx.json a partir de
        $sync.webRoot. Catalogo ausente e erro de configuracao, nao caso
        silencioso.
    #>
    [CmdletBinding()]
    param([string] $Path)

    $doc = $null

    if ($Path) {
        if (-not (Test-Path -LiteralPath $Path)) { throw "appx.json nao encontrado: $Path" }
        $doc = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    } elseif ($null -ne $sync -and $null -ne $sync.configs -and $null -ne $sync.configs.appx) {
        $doc = $sync.configs.appx
    } elseif ($null -ne $sync -and $sync.webRoot) {
        $caminho = Join-Path (Split-Path "$($sync.webRoot)" -Parent) 'config\appx.json'
        if (Test-Path -LiteralPath $caminho) {
            $doc = Get-Content -LiteralPath $caminho -Raw -Encoding UTF8 | ConvertFrom-Json
        }
    }

    if ($null -eq $doc) {
        throw 'catalogo de appx nao encontrado (nem $sync.configs.appx, nem src/config/appx.json).'
    }

    @(@($doc.appx) | ForEach-Object {
        @{
            id        = "$($_.id)"
            nome      = "$($_.nome)"
            descricao = "$($_.descricao)"
            pacote    = "$($_.pacote)"
        }
    })
}

function Get-TmxMicroWinCheck {
    <#
    .SYNOPSIS
        Pre-requisitos do MicroWin, em um objeto que a tela lista com check/x.
    .OUTPUTS
        @{ pronto; oscdimg; oscdimgPath; espacoLivreGB; espacoMinGB; espacoOk;
           elevado; testMode; urlAdk; mensagens[] }
    #>
    [CmdletBinding()]
    param()

    $oscdimg  = Get-TmxOscdimgPath
    $pasta    = Get-TmxMicroWinWorkRoot
    $livre    = Get-TmxFreeSpaceGB -Drive $pasta
    $elevado  = [bool](Test-TmxElevation)
    $testMode = [bool]($null -ne $sync -and $sync.testMode)

    # -1 significa "nao deu para medir": nao inventa reprovacao.
    $minimoGB = Get-TmxMicroWinEspacoMinimoGB
    $espacoOk = ($livre -lt 0 -or $livre -ge $minimoGB)

    $mensagens = New-Object 'System.Collections.Generic.List[string]'
    if (-not $oscdimg) { $mensagens.Add('oscdimg.exe nao encontrado: instale o Windows ADK (Deployment Tools)') }
    if (-not $espacoOk) { $mensagens.Add(('Espaco livre insuficiente: {0} GB de {1} GB necessarios' -f $livre, $minimoGB)) }
    if (-not $elevado -and -not $testMode) { $mensagens.Add('Abra o TweakMaxing como administrador: o MicroWin monta imagem e usa o DISM') }

    @{
        pronto        = [bool]($oscdimg -and $espacoOk -and ($elevado -or $testMode))
        oscdimg       = [bool]$oscdimg
        oscdimgPath   = $(if ($oscdimg) { "$oscdimg" } else { '' })
        espacoLivreGB = $livre
        espacoMinGB   = $minimoGB
        espacoOk      = [bool]$espacoOk
        elevado       = $elevado
        testMode      = $testMode
        pastaTrabalho = "$pasta"
        urlAdk        = (Get-TmxMicroWinAdkUrl)
        mensagens     = $mensagens.ToArray()
    }
}

function Test-TmxMicroWinUsuario {
    <#
    .SYNOPSIS
        $true para um nome de conta local aceitavel (letra + ate 19 de
        [A-Za-z0-9_-]).
    #>
    [CmdletBinding()]
    param([string] $Usuario)
    ("$Usuario" -match (Get-TmxMicroWinUsuarioRegex))
}

function Assert-TmxMicroWinBuildPayload {
    <#
    .SYNOPSIS
        Valida o pedido de build; lanca na primeira coisa errada.
    .OUTPUTS
        Hashtable normalizado (sem a senha - ela segue separada).
    .NOTES
        Roda na thread da janela, antes de existir job. Nenhuma mensagem de
        erro daqui repete a senha.
    #>
    [CmdletBinding()]
    param($Payload)

    $iso = "$($Payload.iso)"
    if (-not $iso) { throw 'escolha a ISO de origem' }
    if ($iso -notmatch '\.iso$') { throw 'o arquivo de origem precisa terminar em .iso' }
    # -PathType Leaf: uma PASTA chamada 'algo.iso' passaria no Test-Path solto
    # e o erro so apareceria la na frente, no Mount-DiskImage.
    if (-not (Test-Path -LiteralPath $iso -PathType Leaf)) { throw "ISO nao encontrada: $iso" }

    $edicao = 0
    if (-not [int]::TryParse("$($Payload.edicao)", [ref]$edicao) -or $edicao -lt 1) {
        throw 'escolha a edicao do Windows'
    }

    $usuario = "$($Payload.usuario)"
    if (-not (Test-TmxMicroWinUsuario -Usuario $usuario)) {
        throw 'nome de usuario invalido: comece com letra e use ate 20 caracteres entre letras, numeros, hifen e sublinhado'
    }

    if (("$($Payload.senha)").Length -lt 1) { throw 'informe uma senha' }

    $destino = "$($Payload.destino)"
    if (-not $destino) { throw 'escolha a pasta de destino' }
    if (-not (Test-Path -LiteralPath $destino -PathType Container)) { throw "pasta de destino nao encontrada: $destino" }

    @{
        iso      = $iso
        edicao   = $edicao
        usuario  = $usuario
        destino  = $destino
        appx     = @(@($Payload.appx)    | ForEach-Object { "$_" } | Where-Object { $_ })
        pacotes  = @(@($Payload.pacotes) | ForEach-Object { "$_" } | Where-Object { $_ })
    }
}

function New-TmxMicroWinSimulatedBuild {
    <#
    .SYNOPSIS
        "Build" do modo de teste: escreve um .txt no destino e nada mais.
    .DESCRIPTION
        O modo de teste NAO pode montar imagem, chamar o DISM nem gerar ISO -
        e a mesma trava das outras abas. Com 'simular' ligado a interface e a
        suite de GUI conseguem exercitar o caminho inteiro (validacao -> job
        -> progresso -> resultado) sem tocar no sistema.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Destino,
        [string] $Usuario,
        [int] $Edicao = 1,
        [string[]] $Appx = @(),
        [string[]] $Pacotes = @()
    )

    $arquivo = Join-Path $Destino 'microwin-simulado.txt'
    $linhas = @(
        'TweakMaxing MicroWin - build simulada (modo de teste)',
        "gerado em: $((Get-Date).ToString('o'))",
        "usuario: $Usuario",
        "edicao: $Edicao",
        "appx marcados: $(@($Appx).Count)",
        "pacotes marcados: $(@($Pacotes).Count)",
        'nenhuma imagem foi montada e nenhuma ISO foi gerada.'
    )
    Set-Content -LiteralPath $arquivo -Value $linhas -Encoding UTF8 -Force

    @{
        ok            = $true
        simulado      = $true
        mensagem      = 'Build simulada: nenhuma imagem foi montada.'
        arquivo       = "$arquivo"
        tamanhoGB     = 0.0
        pastaTrabalho = "$Destino"
        passos        = @(
            @{ nome = 'validar';  ok = $true; detalhe = 'entradas aceitas' },
            @{ nome = 'simular';  ok = $true; detalhe = "arquivo escrito em $arquivo" }
        )
    }
}

function ConvertTo-TmxMicroWinPayload {
    # Resultado do build -> JSON enxuto da interface (sem senha, sempre).
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Resultado)

    @{
        ok            = [bool]$Resultado.ok
        simulado      = [bool]$Resultado.simulado
        mensagem      = "$($Resultado.mensagem)"
        arquivo       = "$($Resultado.arquivo)"
        tamanhoGB     = $Resultado.tamanhoGB
        pastaTrabalho = "$($Resultado.pastaTrabalho)"
        passos        = @(@($Resultado.passos) | ForEach-Object {
            @{ nome = "$($_.nome)"; ok = [bool]$_.ok; detalhe = "$($_.detalhe)" }
        })
    }
}

# ---------------------------------------------------------------------------
# Registro das acoes da ponte
# ---------------------------------------------------------------------------

function Register-TmxMicroWinActions {
    <#
    .SYNOPSIS
        Registra microwin.check, microwin.pickIso, microwin.info,
        microwin.apps, microwin.cleanupWorkDirs e microwin.build.
    #>
    [CmdletBinding()]
    param()

    Register-TmxBridgeAction -Name 'microwin.check' -Handler {
        param($payload)
        Get-TmxMicroWinCheck
    }

    Register-TmxBridgeAction -Name 'microwin.pickIso' -Handler {
        param($payload)

        # No modo de teste nenhum dialogo nativo abre: ele bloquearia a thread
        # da janela e a suite de GUI ficaria pendurada num modal do Windows.
        if ($null -ne $sync -and $sync.testMode) {
            $simulado = "$($payload.simular)"
            return @{ caminho = $simulado; cancelado = [bool](-not $simulado); simulado = $true }
        }

        $caminho = Show-TmxOpenFileDialog -Filtro 'Imagem de disco (*.iso)|*.iso' -Titulo 'Escolha a ISO do Windows'
        @{ caminho = "$caminho"; cancelado = [bool](-not $caminho); simulado = $false }
    }

    Register-TmxBridgeAction -Name 'microwin.info' -Async -Handler {
        param($payload)
        $iso = "$($payload.iso)"
        if (-not $iso) { throw 'escolha a ISO de origem' }
        Send-TmxJobProgress -Pct 10 -Status 'Montando a ISO para leitura...'
        $info = Get-TmxIsoInfo -IsoPath $iso
        Send-TmxJobProgress -Pct 100 -Status 'Concluido'
        @{
            ok        = [bool]$info.ok
            mensagem  = "$($info.mensagem)"
            tamanhoGB = $info.tamanhoGB
            edicoes   = @(@($info.edicoes) | ForEach-Object {
                @{
                    index       = [int]$_.index
                    nome        = "$($_.nome)"
                    versao      = "$($_.versao)"
                    arquitetura = "$($_.arquitetura)"
                }
            })
        }
    }

    Register-TmxBridgeAction -Name 'microwin.apps' -Handler {
        param($payload)
        @{ apps = @(Get-TmxMicroWinAppCatalog) }
    }

    # Sincrona: e so apagar pasta, nao vale ocupar a fila de jobs. Mas nao pode
    # rodar POR CIMA de um build - a pasta de trabalho dele sumiria no meio.
    Register-TmxBridgeAction -Name 'microwin.cleanupWorkDirs' -Handler {
        param($payload)

        if ($null -ne $sync -and $null -ne $sync.activeJob) {
            throw 'espere o trabalho atual terminar antes de limpar as pastas de trabalho'
        }

        $manter = 0
        if ($payload -and $null -ne $payload.manterUltimas) { $manter = [int]$payload.manterUltimas }
        if ($manter -lt 0) { $manter = 0 }

        $r = Clear-TmxMicroWinWorkDirs -ManterUltimas $manter
        @{
            ok        = [bool]$r.ok
            pasta     = "$($r.pasta)"
            removidas = [int]$r.removidas
            mantidas  = [int]$r.mantidas
            erros     = @(@($r.erros) | ForEach-Object { "$_" })
        }
    }

    # Sincrona de proposito: iso, edicao, usuario, senha e destino tem que ser
    # recusados ANTES de existir job.
    Register-TmxBridgeAction -Name 'microwin.build' -Handler {
        param($payload)

        $dados = Assert-TmxMicroWinBuildPayload -Payload $payload

        if ($null -ne $sync -and $sync.testMode) {
            if (-not $payload.simular) {
                throw 'no modo de teste o MicroWin so roda simulado (nenhuma imagem e montada)'
            }
            $jobId = Start-TmxJob -Name 'microwin.build' -Payload @{
                destino = $dados.destino; usuario = $dados.usuario; edicao = $dados.edicao
                appx = $dados.appx; pacotes = $dados.pacotes
            } -Handler {
                param($p)
                Send-TmxJobProgress -Pct 10 -Status 'Simulando a geracao da ISO...'
                $r = New-TmxMicroWinSimulatedBuild -Destino "$($p.destino)" -Usuario "$($p.usuario)" `
                    -Edicao ([int]$p.edicao) -Appx @($p.appx) -Pacotes @($p.pacotes)
                Send-TmxJobProgress -Pct 100 -Status 'Concluido'
                ConvertTo-TmxMicroWinPayload -Resultado $r
            }
            return @{ jobId = $jobId }
        }

        # A senha entra no payload do job e NAO no log: Start-TmxJob registra
        # so jobId e nome.
        $jobId = Start-TmxJob -Name 'microwin.build' -Payload @{
            iso = $dados.iso; edicao = $dados.edicao; usuario = $dados.usuario
            senha = "$($payload.senha)"; destino = $dados.destino
            appx = $dados.appx; pacotes = $dados.pacotes
        } -Handler {
            param($p)
            Send-TmxJobProgress -Pct 2 -Status 'Conferindo os pre-requisitos...'
            $r = Invoke-TmxMicroWinBuild -IsoPath "$($p.iso)" -EdicaoIndex ([int]$p.edicao) `
                -AppxRemover @($p.appx) -PacotesRemover @($p.pacotes) `
                -Usuario "$($p.usuario)" -Senha "$($p.senha)" -Destino "$($p.destino)"
            ConvertTo-TmxMicroWinPayload -Resultado $r
        }

        @{ jobId = $jobId }
    }
}
