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
    } else {
        # Mesma fonte unica dos outros catalogos ($sync.configs, depois src/config).
        $doc = Get-TmxConfigDocument -Name 'appx'
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
    param([string] $IsoPath)

    $oscdimg  = Get-TmxOscdimgPath
    $pasta    = Get-TmxMicroWinWorkRoot
    $livre    = Get-TmxFreeSpaceGB -Drive $pasta
    $elevado  = [bool](Test-TmxElevation)
    $testMode = [bool]($null -ne $sync -and $sync.testMode)

    # -1 significa "nao deu para medir": nao inventa reprovacao. Com a ISO
    # escolhida, o minimo vira tamanho da ISO x 3 + 5 GB (spec v2, secao 11).
    $minimoGB = Get-TmxMicroWinSpaceNeededGB -IsoPath $IsoPath
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

    # contaLocal ausente vale $true (compatibilidade com o pedido antigo).
    $contaLocal = ConvertTo-TmxMicroWinBool -Valor $Payload.contaLocal -Padrao $true

    $usuario = "$($Payload.usuario)"
    if ($contaLocal) {
        if (-not (Test-TmxMicroWinUsuario -Usuario $usuario)) {
            throw 'nome de usuario invalido: comece com letra e use ate 20 caracteres entre letras, numeros, hifen e sublinhado'
        }
        if (("$($Payload.senha)").Length -lt 1) { throw 'informe uma senha' }
    } else {
        $usuario = ''
    }

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
        contaLocal          = [bool]$contaLocal
        removerOneDrive     = ConvertTo-TmxMicroWinBool -Valor $Payload.removerOneDrive
        removerEdge         = ConvertTo-TmxMicroWinBool -Valor $Payload.removerEdge
        desativarTelemetria = ConvertTo-TmxMicroWinBool -Valor $Payload.desativarTelemetria
        incluirDrivers      = ConvertTo-TmxMicroWinBool -Valor $Payload.incluirDrivers
        removerDefender     = ConvertTo-TmxMicroWinBool -Valor $Payload.removerDefender
    }
}

function ConvertTo-TmxMicroWinBool {
    <#
    .SYNOPSIS
        Booleano de uma opcao do payload: so $true de verdade liga (texto
        'false' ou numero nao contam); ausente vale o -Padrao.
    #>
    [CmdletBinding()]
    param($Valor, [bool] $Padrao = $false)
    if ($null -eq $Valor) { return $Padrao }
    ($Valor -is [bool] -and $Valor)
}

function Get-TmxMicroWinOptionNames {
    <#
    .SYNOPSIS
        As opcoes booleanas do build, na ordem da tela.
    #>
    [CmdletBinding()]
    param()
    @('removerOneDrive', 'removerEdge', 'desativarTelemetria', 'contaLocal', 'incluirDrivers', 'removerDefender')
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
        [string[]] $Pacotes = @(),
        [hashtable] $Opcoes = @{},
        [int] $AtrasoMs = 0
    )

    # Os mesmos passos (e o mesmo ponto de cancelamento) do build de verdade,
    # so que cada um e uma espera curta: a interface ve progresso por etapa e
    # o microwin.cancel pode ser exercitado sem montar imagem nenhuma.
    $etapas = New-Object 'System.Collections.Generic.List[object]'
    $etapas.Add(@('montar-iso', 5, 'Montando a ISO de origem...'))
    $etapas.Add(@('copiar-arquivos', 15, 'Copiando os arquivos da ISO...'))
    $etapas.Add(@('desmontar-iso', 35, 'Desmontando a ISO de origem...'))
    if ($Opcoes.incluirDrivers) { $etapas.Add(@('exportar-drivers', 42, 'Exportando os drivers deste PC...')) }
    $etapas.Add(@('montar-imagem', 45, 'Montando a imagem do Windows...'))
    $etapas.Add(@('remover-appx', 60, 'Removendo os aplicativos escolhidos...'))
    $etapas.Add(@('remover-pacotes', 66, 'Removendo os pacotes escolhidos...'))
    if ($Opcoes.removerOneDrive)     { $etapas.Add(@('remover-onedrive', 70, 'Removendo o OneDrive da imagem...')) }
    if ($Opcoes.removerEdge)         { $etapas.Add(@('remover-edge', 72, 'Removendo o Microsoft Edge da imagem...')) }
    if ($Opcoes.removerDefender)     { $etapas.Add(@('remover-defender', 74, 'Removendo o Windows Defender da imagem...')) }
    if ($Opcoes.desativarTelemetria) { $etapas.Add(@('telemetria', 76, 'Desativando a telemetria (registro offline)...')) }
    if ($Opcoes.incluirDrivers)      { $etapas.Add(@('adicionar-drivers', 78, 'Adicionando os drivers na imagem...')) }
    if ($Opcoes.contaLocal -ne $false) { $etapas.Add(@('autounattend', 80, 'Gravando o autounattend.xml...')) }
    $etapas.Add(@('gravar-imagem', 85, 'Gravando as mudancas na imagem...'))
    $etapas.Add(@('gerar-iso', 95, 'Gerando o arquivo .iso...'))

    $passos = New-Object 'System.Collections.Generic.List[object]'
    $passos.Add(@{ nome = 'validar'; ok = $true; detalhe = 'entradas aceitas' })

    foreach ($e in $etapas) {
        if (Test-TmxMicroWinCancelRequested) {
            $passos.Add(@{ nome = 'cancelado'; ok = $false; detalhe = 'build cancelado pelo usuario' })
            $passos.Add(@{ nome = 'limpar-trabalho'; ok = $true; detalhe = 'nada a apagar (simulacao)' })
            Send-TmxJobProgress -Pct 100 -Status 'Cancelado'
            return @{
                ok = $false; cancelado = $true; simulado = $true
                mensagem = 'build cancelado pelo usuario'; arquivo = ''; tamanhoGB = 0.0
                pastaTrabalho = "$Destino"; passos = $passos.ToArray()
            }
        }
        Send-TmxJobProgress -Pct ([int]$e[1]) -Status "$($e[2])"
        if ($AtrasoMs -gt 0) { Start-Sleep -Milliseconds $AtrasoMs }
        $passos.Add(@{ nome = "$($e[0])"; ok = $true; detalhe = 'simulado' })
    }

    $ligadas = @(@(Get-TmxMicroWinOptionNames) | Where-Object { $Opcoes[$_] }) -join ', '
    $arquivo = Join-Path $Destino 'microwin-simulado.txt'
    $linhas = @(
        'TweakMaxing MicroWin - build simulada (modo de teste)',
        "gerado em: $((Get-Date).ToString('o'))",
        "usuario: $Usuario",
        "edicao: $Edicao",
        "appx marcados: $(@($Appx).Count)",
        "pacotes marcados: $(@($Pacotes).Count)",
        "opcoes: $ligadas",
        'nenhuma imagem foi montada e nenhuma ISO foi gerada.'
    )
    Set-Content -LiteralPath $arquivo -Value $linhas -Encoding UTF8 -Force
    $passos.Add(@{ nome = 'simular'; ok = $true; detalhe = "arquivo escrito em $arquivo" })

    @{
        ok            = $true
        cancelado     = $false
        simulado      = $true
        mensagem      = 'Build simulada: nenhuma imagem foi montada.'
        arquivo       = "$arquivo"
        tamanhoGB     = 0.0
        pastaTrabalho = "$Destino"
        passos        = $passos.ToArray()
    }
}

function Get-TmxMicroWinSimulatedIsoInfo {
    <#
    .SYNOPSIS
        Leitura de ISO do modo de teste: confere o arquivo e devolve edicoes
        fixas, no formato de Get-TmxIsoInfo. Nunca monta nada.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $IsoPath)

    if ($IsoPath -notmatch '\.iso$') {
        return @{ ok = $false; mensagem = 'o arquivo precisa terminar em .iso'; tamanhoGB = 0.0; edicoes = @() }
    }
    if (-not (Test-Path -LiteralPath $IsoPath -PathType Leaf)) {
        return @{ ok = $false; mensagem = "ISO nao encontrada: $IsoPath"; tamanhoGB = 0.0; edicoes = @() }
    }
    $gb = [math]::Round([double](Get-Item -LiteralPath $IsoPath).Length / 1GB, 2)
    @{
        ok = $true; mensagem = 'leitura simulada (modo de teste)'; tamanhoGB = $gb
        edicoes = @(
            @{ index = 1; nome = 'Windows 11 Home'; versao = '10.0.26100'; arquitetura = 'x64' },
            @{ index = 5; nome = 'Windows 11 Education'; versao = '10.0.26100'; arquitetura = 'x64' },
            @{ index = 6; nome = 'Windows 11 Pro'; versao = '10.0.26100'; arquitetura = 'x64' }
        )
    }
}

function ConvertTo-TmxMicroWinPayload {
    # Resultado do build -> JSON enxuto da interface (sem senha, sempre).
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Resultado)

    @{
        ok            = [bool]$Resultado.ok
        cancelado     = [bool]$Resultado.cancelado
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
        Registra microwin.check, microwin.cancel, microwin.pickIso,
        microwin.info, microwin.apps, microwin.cleanupWorkDirs e microwin.build.
    #>
    [CmdletBinding()]
    param()

    Register-TmxBridgeAction -Name 'microwin.check' -Handler {
        param($payload)
        $iso = ''
        if ($null -ne $payload -and $payload.iso) { $iso = "$($payload.iso)" }
        Get-TmxMicroWinCheck -IsoPath $iso
    }

    # Sincrona: so levanta a bandeira que o build confere entre um passo e
    # outro. O build cancelado descarta a imagem (-Discard), solta a ISO e
    # apaga a pasta de trabalho; o resultado chega no job.done com
    # cancelado:true.
    Register-TmxBridgeAction -Name 'microwin.cancel' -Handler {
        param($payload)
        $ativo = $null
        if ($null -ne $sync) { $ativo = $sync.activeJob }
        if ($null -eq $ativo -or "$($ativo.name)" -ne 'microwin.build') {
            return @{ ok = $false; cancelando = $false; mensagem = 'nenhum build do MicroWin em andamento' }
        }
        $sync.microwinCancelar = $true
        Write-TmxLog -Level WARN -Message 'MicroWin: cancelamento pedido' -Data @{ jobId = "$($ativo.jobId)" }
        @{ ok = $true; cancelando = $true; jobId = "$($ativo.jobId)"; mensagem = 'cancelando: a imagem sera descartada e a pasta de trabalho apagada' }
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
        # Modo de teste com 'simular': nenhuma imagem e montada; o arquivo
        # precisa existir e as edicoes sao fixas.
        if ($null -ne $sync -and $sync.testMode -and $payload.simular -eq $true) {
            $info = Get-TmxMicroWinSimulatedIsoInfo -IsoPath $iso
        } else {
            $info = Get-TmxIsoInfo -IsoPath $iso
        }
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
        $opcoes = @{}
        foreach ($nome in @(Get-TmxMicroWinOptionNames)) { $opcoes[$nome] = [bool]$dados[$nome] }

        if ($null -ne $sync -and $sync.testMode) {
            if (-not $payload.simular) {
                throw 'no modo de teste o MicroWin so roda simulado (nenhuma imagem e montada)'
            }
            # Atraso por etapa (ms, ate 5000): a suite de GUI usa para ter
            # tempo de clicar em Cancelar no meio do build simulado.
            $atraso = 0
            if ($null -ne $payload.simularAtrasoMs) { [void][int]::TryParse("$($payload.simularAtrasoMs)", [ref]$atraso) }
            $atraso = [math]::Max(0, [math]::Min(5000, $atraso))

            $sync.microwinCancelar = $false
            $jobId = Start-TmxJob -Name 'microwin.build' -Payload @{
                destino = $dados.destino; usuario = $dados.usuario; edicao = $dados.edicao
                appx = $dados.appx; pacotes = $dados.pacotes; opcoes = $opcoes; atraso = $atraso
            } -Handler {
                param($p)
                $op = @{}
                if ($p.opcoes) { foreach ($k in @($p.opcoes.Keys)) { $op[$k] = [bool]$p.opcoes[$k] } }
                $r = New-TmxMicroWinSimulatedBuild -Destino "$($p.destino)" -Usuario "$($p.usuario)" `
                    -Edicao ([int]$p.edicao) -Appx @($p.appx) -Pacotes @($p.pacotes) -Opcoes $op -AtrasoMs ([int]$p.atraso)
                if ($r.ok) { Send-TmxJobProgress -Pct 100 -Status 'Concluido' }
                ConvertTo-TmxMicroWinPayload -Resultado $r
            }
            return @{ jobId = $jobId }
        }

        # A senha entra no payload do job e NAO no log: Start-TmxJob registra
        # so jobId e nome.
        $sync.microwinCancelar = $false
        $senhaJob = ''
        if ($dados.contaLocal) { $senhaJob = "$($payload.senha)" }
        $jobId = Start-TmxJob -Name 'microwin.build' -Payload @{
            iso = $dados.iso; edicao = $dados.edicao; usuario = $dados.usuario
            senha = $senhaJob; destino = $dados.destino
            appx = $dados.appx; pacotes = $dados.pacotes; opcoes = $opcoes
        } -Handler {
            param($p)
            Send-TmxJobProgress -Pct 2 -Status 'Conferindo os pre-requisitos...'
            $o = $p.opcoes
            $r = Invoke-TmxMicroWinBuild -IsoPath "$($p.iso)" -EdicaoIndex ([int]$p.edicao) `
                -AppxRemover @($p.appx) -PacotesRemover @($p.pacotes) `
                -Usuario "$($p.usuario)" -Senha "$($p.senha)" -Destino "$($p.destino)" `
                -ContaLocal ([bool]$o.contaLocal) -RemoverOneDrive ([bool]$o.removerOneDrive) `
                -RemoverEdge ([bool]$o.removerEdge) -DesativarTelemetria ([bool]$o.desativarTelemetria) `
                -IncluirDrivers ([bool]$o.incluirDrivers) -RemoverDefender ([bool]$o.removerDefender)
            ConvertTo-TmxMicroWinPayload -Resultado $r
        }

        @{ jobId = $jobId }
    }
}
