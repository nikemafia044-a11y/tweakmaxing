# Core/RestorePoint.ps1
# Criacao OBRIGATORIA e VERIFICADA de ponto de restauracao.
#
# Sequencia (New-TmxRestorePoint):
#   1. Verificar Protecao do Sistema no volume do sistema
#   2. Se desabilitada: habilitar + alocar >= 5% de shadow storage
#   3. Zerar o throttle de 24h (SystemRestorePointCreationFrequency = 0),
#      via Set-TmxRegistry -> fica no state.json, reversivel mesmo em crash
#   4. Capturar lista de pontos existentes
#   5. Checkpoint-Computer
#   6. VERIFICAR que a lista cresceu e o novo ponto tem a descricao esperada
#      (Checkpoint-Computer NAO lanca erro quando o Windows decide nao criar)
#   7. Restaurar o throttle original (sempre, em finally)
#   8. Qualquer falha -> resultado ok=$false; o orquestrador encerra com exit 2
#
# As etapas que exigem elevacao (protecao, listagem, checkpoint) sao funcoes
# separadas para que os testes possam mocka-las sem privilegios.

$script:TmxThrottleKeyPath   = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
$script:TmxThrottleValueName = 'SystemRestorePointCreationFrequency'
$script:TmxSkipPhrase        = 'SEM PONTO DE RESTAURACAO'

function Get-TmxSystemProtectionStatus {
    <#
    .SYNOPSIS
        Verifica se a Protecao do Sistema esta habilitada.
    #>
    [CmdletBinding()]
    param([string] $Drive = $env:SystemDrive)

    $policyKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\SystemRestore'
    $srKey     = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'

    $disableSR = (Get-ItemProperty -Path $policyKey -Name DisableSR -ErrorAction SilentlyContinue).DisableSR
    if ($disableSR -eq 1) {
        return [pscustomobject]@{ enabled = $false; motivo = 'Desabilitada por politica de grupo (DisableSR=1)'; bloqueadoPorPolitica = $true }
    }

    $interval = (Get-ItemProperty -Path $srKey -Name RPSessionInterval -ErrorAction SilentlyContinue).RPSessionInterval
    if ($null -eq $interval -or $interval -eq 0) {
        return [pscustomobject]@{ enabled = $false; motivo = 'RPSessionInterval ausente ou 0'; bloqueadoPorPolitica = $false }
    }

    [pscustomobject]@{ enabled = $true; motivo = 'RPSessionInterval ativo'; bloqueadoPorPolitica = $false }
}

function Enable-TmxSystemProtection {
    <#
    .SYNOPSIS
        Habilita a Protecao do Sistema no volume e garante >= MinPercent de shadow storage.
    #>
    [CmdletBinding()]
    param(
        [string] $Drive = $env:SystemDrive,
        [int]    $MinPercent = 5
    )

    Enable-ComputerRestore -Drive "$Drive\" -ErrorAction Stop
    Write-TmxLog -Level INFO -Message "Protecao do Sistema habilitada em $Drive"

    $out = & vssadmin.exe resize shadowstorage "/for=$Drive" "/on=$Drive" "/maxsize=$MinPercent%" 2>&1
    if ($LASTEXITCODE -ne 0) {
        # Nao e fatal: a verificacao do ponto (etapa 6) e quem decide.
        Write-TmxLog -Level WARN -Message "vssadmin resize retornou $LASTEXITCODE" -Data @{ saida = "$out" }
    } else {
        Write-TmxLog -Level INFO -Message "Shadow storage ajustado para >= $MinPercent% em $Drive"
    }
    $true
}

function Get-TmxRestorePoints {
    # Lista pontos existentes. Sem elevacao retorna vazio (nao lanca).
    @(Get-ComputerRestorePoint -ErrorAction SilentlyContinue |
        Select-Object SequenceNumber, Description, CreationTime, RestorePointType)
}

function Invoke-TmxCheckpoint {
    param([Parameter(Mandatory)] [string] $Description)
    Checkpoint-Computer -Description $Description -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
}

function New-TmxRestorePoint {
    <#
    .SYNOPSIS
        Cria e verifica um ponto de restauracao. Nunca lanca; retorna { ok, etapa, erro, ... }.
    .PARAMETER ThrottleKeyPath
        Chave do throttle. Parametrizada para os testes apontarem para HKCU.
    #>
    [CmdletBinding()]
    param(
        [string] $Description     = ('TweakMaxing {0:yyyy-MM-dd HH:mm:ss}' -f (Get-Date)),
        [string] $ThrottleKeyPath = $script:TmxThrottleKeyPath,
        [string] $Drive           = $env:SystemDrive
    )

    $r = [pscustomobject]@{
        ok                       = $false
        etapa                    = $null
        descricao                = $Description
        sequenceNumber           = $null
        erro                     = $null
        protecaoHabilitadaPorNos = $false
        throttleRestaurado       = $null
        pontosAntes              = 0
        pontosDepois             = 0
    }
    $throttleRec = $null

    Write-TmxLog -Level INFO -Message 'Iniciando criacao do ponto de restauracao' -Data @{ descricao = $Description }

    try {
        # --- 1 e 2: Protecao do Sistema ------------------------------------
        $r.etapa = 'protecao'
        $status = Get-TmxSystemProtectionStatus -Drive $Drive
        if (-not $status.enabled) {
            if ($status.bloqueadoPorPolitica) {
                throw "Protecao do Sistema desabilitada por politica: $($status.motivo). Nao e possivel criar ponto de restauracao."
            }
            Write-TmxLog -Level WARN -Message "Protecao do Sistema desabilitada ($($status.motivo)); tentando habilitar"
            Enable-TmxSystemProtection -Drive $Drive | Out-Null
            $r.protecaoHabilitadaPorNos = $true

            $status = Get-TmxSystemProtectionStatus -Drive $Drive
            if (-not $status.enabled) {
                throw "Nao foi possivel habilitar a Protecao do Sistema em $Drive ($($status.motivo))."
            }
        }

        # --- 3: Zerar throttle (via state.json, reversivel) -----------------
        $r.etapa = 'throttle'
        $throttleRec = Set-TmxRegistry -Path $ThrottleKeyPath -Name $script:TmxThrottleValueName `
                        -Value 0 -Type DWord -TweakId 'RP-THROTTLE' -PassThru
        if ($throttleRec.status -ne 'aplicado') {
            throw "Falha ao zerar o throttle de criacao de pontos: $($throttleRec.erro)"
        }

        # --- 4: Lista antes -------------------------------------------------
        $r.etapa = 'listagem'
        $antes = @(Get-TmxRestorePoints)
        $r.pontosAntes = $antes.Count

        # --- 5: Criar -------------------------------------------------------
        $r.etapa = 'checkpoint'
        Invoke-TmxCheckpoint -Description $Description

        # --- 6: Verificar ---------------------------------------------------
        $r.etapa = 'verificacao'
        $depois = @(Get-TmxRestorePoints)
        $r.pontosDepois = $depois.Count
        $seqAntes = @($antes | ForEach-Object { $_.SequenceNumber })
        $novo = $depois |
            Where-Object { $_.Description -eq $Description -and ($seqAntes -notcontains $_.SequenceNumber) } |
            Select-Object -First 1

        if (-not $novo) {
            throw ("O ponto nao apareceu na lista apos a criacao (antes: {0}, depois: {1}). " +
                   "O Windows pode ter recusado silenciosamente - verifique espaco em disco e a Protecao do Sistema.") -f $antes.Count, $depois.Count
        }

        $r.sequenceNumber = $novo.SequenceNumber
        $r.ok    = $true
        $r.etapa = 'concluido'
        Write-TmxLog -Level INFO -Message 'Ponto de restauracao criado e verificado' -Data @{ seq = $novo.SequenceNumber; descricao = $Description }
    }
    catch {
        $r.erro = $_.Exception.Message
        Write-TmxLog -Level ERROR -Message "Ponto de restauracao falhou na etapa '$($r.etapa)': $($r.erro)"
    }
    finally {
        # --- 7: Restaurar throttle, aconteca o que acontecer ----------------
        if ($throttleRec -and $throttleRec.status -eq 'aplicado') {
            try {
                Undo-TmxRegistryRecord -Record $throttleRec | Out-Null
                $throttleRec.status = 'revertido'
                $r.throttleRestaurado = $true
                Write-TmxLog -Level INFO -Message 'Throttle de criacao de pontos restaurado'
            } catch {
                $r.throttleRestaurado = $false
                Write-TmxLog -Level WARN -Message "Nao foi possivel restaurar o throttle: $($_.Exception.Message). Undo-TweakMaxing corrige."
            }
            Save-TmxState
        }
    }

    $r
}

function Confirm-TmxSkipRestorePoint {
    <#
    .SYNOPSIS
        Exige que o usuario digite a frase exata para pular o ponto de restauracao.
    #>
    Write-Host ''
    Write-Host '  ATENCAO: voce pediu para pular o ponto de restauracao.' -ForegroundColor Red
    Write-Host '  Sem ele, a unica reversao disponivel e Undo-TweakMaxing (state.json).' -ForegroundColor Yellow
    Write-Host '  Se o Windows nao inicializar, nao havera como voltar pelo Ambiente de Recuperacao.' -ForegroundColor Yellow
    Write-Host ''
    $typed = Read-Host "  Digite exatamente '$script:TmxSkipPhrase' para continuar"
    ($typed -ceq $script:TmxSkipPhrase)
}

function Invoke-TmxRestorePointStage {
    <#
    .SYNOPSIS
        Etapa do orquestrador. Retorna { proceed, exitCode, mensagem, pulado, resultado }.
        exitCode 2 = abortar sem aplicar nada.
    #>
    [CmdletBinding()]
    param(
        [switch] $SkipRestorePoint,
        [switch] $IUnderstandTheRisk,
        [switch] $DryRun,
        [string] $ThrottleKeyPath = $script:TmxThrottleKeyPath
    )

    $out = [pscustomobject]@{ proceed = $false; exitCode = 0; mensagem = $null; pulado = $false; resultado = $null }

    if ($DryRun) {
        $out.proceed  = $true
        $out.pulado   = $true
        $out.mensagem = 'DryRun: ponto de restauracao nao criado (nada sera alterado).'
        return $out
    }

    if ($SkipRestorePoint) {
        if (-not $IUnderstandTheRisk) {
            $out.exitCode = 2
            $out.mensagem = '-SkipRestorePoint so e aceito junto com -IUnderstandTheRisk. Nada foi alterado.'
            return $out
        }
        if (-not (Confirm-TmxSkipRestorePoint)) {
            $out.exitCode = 2
            $out.mensagem = 'Frase de confirmacao incorreta. Encerrando sem alterar nada.'
            return $out
        }
        $out.proceed  = $true
        $out.pulado   = $true
        $out.mensagem = 'Ponto de restauracao PULADO por decisao explicita do usuario.'
        Write-TmxLog -Level WARN -Message $out.mensagem
        return $out
    }

    $res = New-TmxRestorePoint -ThrottleKeyPath $ThrottleKeyPath
    $out.resultado = $res

    if ($res.ok) {
        $out.proceed  = $true
        $out.mensagem = "Ponto de restauracao criado e verificado (#$($res.sequenceNumber)): $($res.descricao)"
    } else {
        $out.exitCode = 2
        $out.mensagem = "Nao foi possivel criar/verificar o ponto de restauracao (etapa: $($res.etapa)). Motivo: $($res.erro) Nada foi alterado."
    }
    $out
}
