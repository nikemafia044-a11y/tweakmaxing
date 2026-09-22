# Core/Backup.ps1
# Pasta da execucao, state.json (fonte da verdade para rollback) e exports de seguranca.
#
# Layout: %LOCALAPPDATA%\TweakMaxing\runs\<runId>\
#   state.json        - registros de tudo que foi alterado (valor anterior incluso)
#   events.jsonl      - log estruturado
#   transcript.log    - transcript da sessao
#   regbackup\*.reg   - exports de ramos do registro ANTES de qualquer escrita
#   power-scheme.pow  - esquema de energia ativo
#   net-adapters.json - adaptadores e propriedades avancadas
#
# A variavel de ambiente TWEAKMAXING_HOME sobrescreve a raiz (usada pelos testes).

$script:TmxRun          = $null
$script:TmxStateRecords = $null

function Get-TmxHomePath {
    if ($env:TWEAKMAXING_HOME) { return $env:TWEAKMAXING_HOME }
    Join-Path $env:LOCALAPPDATA 'TweakMaxing'
}

function Get-TmxRunsRoot {
    Join-Path (Get-TmxHomePath) 'runs'
}

function New-TmxRun {
    <#
    .SYNOPSIS
        Cria a pasta da execucao, zera o estado em memoria e inicia o logger.
    #>
    [CmdletBinding()]
    param(
        [string] $RunsRoot = (Get-TmxRunsRoot)
    )

    $runId   = '{0:yyyyMMdd-HHmmss}-{1:x4}' -f (Get-Date), (Get-Random -Maximum 65535)
    $runPath = Join-Path $RunsRoot $runId
    $regPath = Join-Path $runPath 'regbackup'

    New-Item -ItemType Directory -Path $runPath -Force | Out-Null
    New-Item -ItemType Directory -Path $regPath -Force | Out-Null

    $script:TmxStateRecords = New-Object 'System.Collections.Generic.List[object]'
    $script:TmxRun = [pscustomobject]@{
        RunId         = $runId
        RunPath       = $runPath
        StatePath     = (Join-Path $runPath 'state.json')
        RegBackupPath = $regPath
        ReportPath    = (Join-Path $runPath 'relatorio.html')
        CriadoEm      = (Get-Date)
    }

    Initialize-TmxLogger -RunPath $runPath -RunId $runId | Out-Null
    Save-TmxState
    Write-TmxLog -Level INFO -Message 'Nova execucao criada' -Data @{ runId = $runId; caminho = $runPath }

    $script:TmxRun
}

function Get-TmxRun {
    $script:TmxRun
}

function Add-TmxStateRecord {
    <#
    .SYNOPSIS
        Anexa um registro ao estado e persiste imediatamente em disco.
    .NOTES
        O objeto e adicionado por referencia: quem chamou pode atualizar
        status/erro depois e chamar Save-TmxState para persistir.
        Ganha um 'seq' 1-based (posicao na lista) se ainda nao tiver: e a
        chave usada por Save-TmxStateFile para mesclar mudancas de status sem
        sobrescrever registros concorrentes de outro processo/escritor.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Record
    )
    if ($null -eq $script:TmxStateRecords) {
        $script:TmxStateRecords = New-Object 'System.Collections.Generic.List[object]'
    }
    $script:TmxStateRecords.Add($Record)
    if (-not ($Record.PSObject.Properties.Name -contains 'seq') -or $null -eq $Record.seq) {
        $Record | Add-Member -NotePropertyName seq -NotePropertyValue $script:TmxStateRecords.Count -Force
    }
    Save-TmxState
    $Record
}

function New-TmxStateRecord {
    <#
    .SYNOPSIS
        Cria um registro de estado com status 'aplicando' e persiste ANTES da escrita.
        Handlers de qualquer tipo usam isto; Set-TmxRegistry tem o seu proprio.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $TweakId,
        [Parameter(Mandatory)] [string] $Tipo,
        [Parameter(Mandatory)] [string] $Alvo,
        $Detalhe = @{},
        $ValorAnterior = $null,
        $ValorNovo = $null,
        [string] $ReversaoTipo = 'restaurarValorAnterior',
        [bool] $ExistiaAntes = $true
    )
    $rec = [pscustomobject]@{
        tweakId       = $TweakId
        tipo          = $Tipo
        alvo          = $Alvo
        detalhe       = $Detalhe
        valorAnterior = $ValorAnterior
        tipoAnterior  = $null
        existiaAntes  = $ExistiaAntes
        valorNovo     = $ValorNovo
        reversao      = @{ tipo = $ReversaoTipo }
        status        = 'aplicando'
        aplicadoEm    = $null
        erro          = $null
    }
    Add-TmxStateRecord -Record $rec | Out-Null
    $rec
}

function Complete-TmxStateRecord {
    # Fecha um registro: aplicado ou falha. Persiste.
    param(
        [Parameter(Mandatory)] $Record,
        [Parameter(Mandatory)] [bool] $Ok,
        [string] $Erro
    )
    if ($Ok) {
        $Record.status     = 'aplicado'
        $Record.aplicadoEm = (Get-Date).ToString('o')
    } else {
        $Record.status = 'falha'
        $Record.erro   = $Erro
    }
    Save-TmxState
    $Record
}

function Get-TmxState {
    # Emite os registros no pipeline (vazio -> nada). Quem precisa de array usa @(Get-TmxState).
    if ($null -eq $script:TmxStateRecords) { return }
    $script:TmxStateRecords.ToArray()
}

function Save-TmxState {
    <#
    .SYNOPSIS
        Persiste o estado EM MEMORIA do run ativo.
    .NOTES
        Antes de escrever, rele o arquivo (se ja existir) e preserva
        registros "estrangeiros": qualquer um cujo 'seq' a memoria nao
        conhece. Isso acontece quando outro escritor grava diretamente no
        state.json deste run sem passar pela memoria deste processo (ex.:
        Save-TmxStateFile de um Undo-TweakMaxing rodando em outro processo).
        O estrangeiro e anexado ao payload gravado, mas NAO e trazido para
        $script:TmxStateRecords - este processo continua sem conhece-lo.
    #>
    [CmdletBinding()]
    param()
    if (-not $script:TmxRun) { return }

    # .ToArray() em atribuicao DIRETA: @() sobre List generica vazia falha no PS 5.1,
    # e um array vazio saindo de "if {}" como expressao e desenrolado para $null pelo pipeline.
    $registros = New-Object 'object[]' 0
    if ($null -ne $script:TmxStateRecords) { $registros = $script:TmxStateRecords.ToArray() }

    $memSeqs = New-Object 'System.Collections.Generic.HashSet[int]'
    $i = 0
    foreach ($rec in $registros) {
        $i++
        [void]$memSeqs.Add((Get-TmxRecordSeq -Record $rec -Position $i))
    }

    $estrangeiros = New-Object 'System.Collections.Generic.List[object]'
    if (Test-Path -LiteralPath $script:TmxRun.StatePath) {
        try {
            $existing = Get-Content -LiteralPath $script:TmxRun.StatePath -Raw -Encoding UTF8 | ConvertFrom-Json
            $emDisco  = @($existing.registros | Where-Object { $null -ne $_ })
            $p = 0
            foreach ($discoRec in $emDisco) {
                $p++
                $seq = Get-TmxRecordSeq -Record $discoRec -Position $p
                if (-not $memSeqs.Contains($seq)) {
                    $estrangeiros.Add($discoRec)
                    Write-TmxLog -Level WARN -Message "registro estrangeiro preservado seq=$seq" -Data @{ tweakId = $discoRec.tweakId; alvo = $discoRec.alvo }
                }
            }
        } catch {
            # Arquivo corrompido/sendo escrito nesse instante por outro processo:
            # nao ha o que preservar com seguranca; segue so com a memoria.
            Write-TmxLog -Level WARN -Message "Falha ao reler state.json para preservar registros estrangeiros: $($_.Exception.Message)"
        }
    }

    # .ToArray() SEMPRE (mesmo vazio): New-Object 'object[]' N produz um array
    # que o ConvertTo-Json deste PowerShell serializa errado, como
    # {"value":[...],"Count":N} em vez de um array JSON puro. .ToArray() de
    # uma List (mesmo vazia) nao tem esse problema.
    $todosList = New-Object 'System.Collections.Generic.List[object]'
    foreach ($rec in $registros)    { $todosList.Add($rec) }
    foreach ($rec in $estrangeiros) { $todosList.Add($rec) }
    $todos = $todosList.ToArray()

    $payload = [ordered]@{
        runId      = $script:TmxRun.RunId
        criadoEm   = $script:TmxRun.CriadoEm.ToString('o')
        computador = $env:COMPUTERNAME
        registros  = $todos
    }
    $json = $payload | ConvertTo-Json -Depth 12
    # -WhatIf:$false: o state.json e a garantia de reversao; nunca pode ser pulado.
    Set-Content -LiteralPath $script:TmxRun.StatePath -Value $json -Encoding UTF8 -WhatIf:$false
}

function Get-TmxRecordSeq {
    <#
    .SYNOPSIS
        Identidade estavel de um registro para fins de merge: o campo 'seq'
        quando presente, senao a posicao (1-based) dele no array informado.
    #>
    param($Record, [Parameter(Mandatory)] [int] $Position)
    if ($Record.PSObject.Properties.Name -contains 'seq' -and $null -ne $Record.seq) {
        return [int]$Record.seq
    }
    $Position
}

function Save-TmxStateFile {
    <#
    .SYNOPSIS
        Mescla no state.json em disco as mudancas de status/revertidoEm dos
        registros informados (tipicamente so os que acabaram de ser
        revertidos), identificados por 'seq'. NUNCA sobrescreve o array
        inteiro com um snapshot de memoria: rele o arquivo no momento da
        escrita e so altera os registros que baterem por seq (ou posicao, na
        ausencia de seq), preservando registros novos que outro processo
        possa ter escrito nesse meio-tempo.
    .NOTES
        O fallback por posicao (quando 'seq' esta ausente) pressupoe que o
        arquivo e append-only entre a leitura original e esta escrita: nada
        reordena ou remove registros existentes, so acrescenta no fim. Se
        essa premissa for violada, o fallback por posicao pode casar o
        registro errado - por isso 'seq' e sempre preferido quando presente.

        Colisao de 'seq' entre os REGISTROS INFORMADOS (dois ou mais
        candidatos com o mesmo seq) e desempatada por (seq, tweakId, alvo)
        contra cada registro em disco. Se, mesmo assim, mais de um candidato
        continuar batendo (ambiguidade real), a mudanca NAO e aplicada aquele
        registro, um aviso e logado e o seq entra na lista retornada.
    .OUTPUTS
        Array (possivelmente vazio) com os valores de 'seq' que nao puderam
        ser aplicados por ambiguidade.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $StatePath,
        [Parameter(Mandatory)] $Registros
    )
    if (-not (Test-Path -LiteralPath $StatePath)) {
        throw "state.json nao encontrado em: $StatePath"
    }

    # Indexa as mudancas (memoria) por seq ANTES de reler o disco. Guarda TODOS
    # os candidatos de cada seq (pode haver colisao) para desempatar depois
    # por (seq, tweakId, alvo) contra cada registro em disco especifico.
    $porSeq = @{}
    $i = 0
    foreach ($rec in @($Registros)) {
        $i++
        $chave = Get-TmxRecordSeq -Record $rec -Position $i
        if (-not $porSeq.ContainsKey($chave)) {
            $porSeq[$chave] = New-Object 'System.Collections.Generic.List[object]'
        }
        $porSeq[$chave].Add($rec)
    }

    # Rele o arquivo AGORA (o mais perto possivel da escrita) para minimizar
    # a janela de corrida com outro escritor.
    $existing = Get-Content -LiteralPath $StatePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $emDisco  = @($existing.registros | Where-Object { $null -ne $_ })

    $naoAplicados = New-Object 'System.Collections.Generic.List[int]'
    $pos = 0
    foreach ($discoRec in $emDisco) {
        $pos++
        $chave = Get-TmxRecordSeq -Record $discoRec -Position $pos
        if (-not $porSeq.ContainsKey($chave)) { continue }

        $candidatos = $porSeq[$chave]
        $match = $null
        if ($candidatos.Count -eq 1) {
            $match = $candidatos[0]
        } else {
            # Colisao de seq entre as mudancas: desempata por (seq, tweakId, alvo).
            $refinados = @($candidatos | Where-Object {
                "$($_.tweakId)" -eq "$($discoRec.tweakId)" -and "$($_.alvo)" -eq "$($discoRec.alvo)"
            })
            if ($refinados.Count -eq 1) { $match = $refinados[0] }
        }

        if ($null -eq $match) {
            if (-not $naoAplicados.Contains($chave)) {
                $naoAplicados.Add($chave)
                Write-TmxLog -Level WARN -Message 'seq duplicado; mudanca nao aplicada' -Data @{ seq = $chave }
            }
            continue
        }

        $discoRec | Add-Member -NotePropertyName status      -NotePropertyValue $match.status -Force
        $discoRec | Add-Member -NotePropertyName revertidoEm -NotePropertyValue $match.revertidoEm -Force
    }

    # $emDisco ja e um array puro (via @(...) sobre pipeline, nao New-Object) -
    # serializa certo mesmo vazio (ver nota em Save-TmxState sobre o problema
    # especifico de New-Object 'object[]' N com ConvertTo-Json).
    $payload = [ordered]@{
        runId      = $existing.runId
        criadoEm   = $existing.criadoEm
        computador = $existing.computador
        registros  = $emDisco
    }
    $json = $payload | ConvertTo-Json -Depth 12
    # -WhatIf:$false: reescrever o state.json apos reversao e a garantia contra
    # reverter o mesmo registro duas vezes; nunca pode ser pulado.
    Set-Content -LiteralPath $StatePath -Value $json -Encoding UTF8 -WhatIf:$false

    # ,@(): forca a saida a ser SEMPRE um array (mesmo vazio/1 item) para quem capturar.
    ,@($naoAplicados.ToArray())
}

function Import-TmxState {
    <#
    .SYNOPSIS
        Le os registros de um state.json. Nao depende do estado em memoria.
    .NOTES
        Registros antigos sem 'seq' recebem seq = posicao (1-based) no
        arquivo, para que Save-TmxStateFile ainda consiga mescla-los. Esse
        fallback por posicao pressupoe um arquivo append-only: se algo
        reordenar ou remover registros entre esta leitura e uma escrita
        posterior (Save-TmxStateFile), a posicao deixa de identificar o
        mesmo registro com seguranca - por isso 'seq' real (quando presente)
        e sempre preferido a posicao.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $StatePath
    )
    if (-not (Test-Path -LiteralPath $StatePath)) {
        throw "state.json nao encontrado em: $StatePath"
    }
    $data      = Get-Content -LiteralPath $StatePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $registros = @($data.registros | Where-Object { $null -ne $_ })

    $i = 0
    foreach ($rec in $registros) {
        $i++
        if (-not ($rec.PSObject.Properties.Name -contains 'seq') -or $null -eq $rec.seq) {
            $rec | Add-Member -NotePropertyName seq -NotePropertyValue $i -Force
        }
    }

    # Emite no pipeline; caller usa @(Import-TmxState ...) quando precisa de array.
    $registros
}

# ---------------------------------------------------------------------------
# Exports de seguranca
# ---------------------------------------------------------------------------

function ConvertTo-TmxRegExportPath {
    <#
    .SYNOPSIS
        Converte caminho PowerShell (HKLM:\...) para o formato do reg.exe (HKEY_LOCAL_MACHINE\...).
    #>
    param([Parameter(Mandatory)] [string] $Path)

    $p = $Path.Trim()
    $map = [ordered]@{
        '^HKLM:\\' = 'HKEY_LOCAL_MACHINE\'
        '^HKCU:\\' = 'HKEY_CURRENT_USER\'
        '^HKCR:\\' = 'HKEY_CLASSES_ROOT\'
        '^HKU:\\'  = 'HKEY_USERS\'
        '^HKCC:\\' = 'HKEY_CURRENT_CONFIG\'
        '^HKLM\\'  = 'HKEY_LOCAL_MACHINE\'
        '^HKCU\\'  = 'HKEY_CURRENT_USER\'
    }
    foreach ($pattern in $map.Keys) {
        if ($p -match $pattern) { return ($p -replace $pattern, $map[$pattern]) }
    }
    $p
}

function Backup-TmxRegistryHive {
    <#
    .SYNOPSIS
        Exporta um ramo do registro para .reg na pasta da execucao.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [string] $OutputDir
    )

    if (-not $OutputDir) {
        if (-not $script:TmxRun) { throw 'Nenhuma execucao ativa. Chame New-TmxRun primeiro.' }
        $OutputDir = $script:TmxRun.RegBackupPath
    }
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

    $regPath  = ConvertTo-TmxRegExportPath -Path $Path
    $safeName = ($regPath -replace '[\\/:*?"<>|]', '_')
    $file     = Join-Path $OutputDir "$safeName.reg"

    $output = & reg.exe export $regPath $file /y 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-TmxLog -Level WARN -Message "Falha ao exportar ramo: $regPath" -Data @{ saida = "$output" }
        return $null
    }

    Write-TmxLog -Level INFO -Message "Ramo exportado: $regPath" -Data @{ arquivo = $file }
    $file
}

function Backup-TmxPowerScheme {
    <#
    .SYNOPSIS
        Exporta o esquema de energia ativo (.pow).
    #>
    [CmdletBinding()]
    param([string] $OutputDir)

    if (-not $OutputDir) {
        if (-not $script:TmxRun) { throw 'Nenhuma execucao ativa. Chame New-TmxRun primeiro.' }
        $OutputDir = $script:TmxRun.RunPath
    }

    $file = Join-Path $OutputDir 'power-scheme.pow'
    try {
        $active = (& powercfg /getactivescheme 2>&1) -join ' '
        $guid   = [regex]::Match($active, '[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}').Value
        if (-not $guid) { throw "GUID do esquema ativo nao identificado: $active" }

        if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file -Force }
        & powercfg /export $file $guid 2>&1 | Out-Null

        if (-not (Test-Path -LiteralPath $file)) { throw 'powercfg /export nao gerou o arquivo' }

        Write-TmxLog -Level INFO -Message 'Esquema de energia exportado' -Data @{ guid = $guid; arquivo = $file }
        return [pscustomobject]@{ guid = $guid; arquivo = $file }
    } catch {
        Write-TmxLog -Level WARN -Message "Falha ao exportar esquema de energia: $($_.Exception.Message)"
        return $null
    }
}

function Backup-TmxNetworkAdapters {
    <#
    .SYNOPSIS
        Salva adaptadores de rede e suas propriedades avancadas em JSON.
    #>
    [CmdletBinding()]
    param([string] $OutputDir)

    if (-not $OutputDir) {
        if (-not $script:TmxRun) { throw 'Nenhuma execucao ativa. Chame New-TmxRun primeiro.' }
        $OutputDir = $script:TmxRun.RunPath
    }

    $file = Join-Path $OutputDir 'net-adapters.json'
    try {
        $adapters = @(Get-NetAdapter -ErrorAction Stop | ForEach-Object {
            $name = $_.Name
            [pscustomobject]@{
                nome                  = $name
                descricao             = $_.InterfaceDescription
                status                = "$($_.Status)"
                velocidadeLink        = $_.LinkSpeed
                mac                   = $_.MacAddress
                propriedadesAvancadas = @(
                    Get-NetAdapterAdvancedProperty -Name $name -ErrorAction SilentlyContinue |
                        Select-Object DisplayName, DisplayValue, RegistryKeyword, @{ n = 'RegistryValue'; e = { @($_.RegistryValue) -join ',' } }
                )
            }
        })
        $adapters | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $file -Encoding UTF8
        Write-TmxLog -Level INFO -Message 'Adaptadores de rede salvos' -Data @{ quantidade = $adapters.Count; arquivo = $file }
        return $file
    } catch {
        Write-TmxLog -Level WARN -Message "Falha ao salvar adaptadores de rede: $($_.Exception.Message)"
        return $null
    }
}
