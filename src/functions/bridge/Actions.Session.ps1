# functions/bridge/Actions.Session.ps1
# Acoes da sessao: status, frase de pulo, abertura da sessao e reset (teste).

function Register-TmxSessionActions {
    <#
    .SYNOPSIS
        Registra session.status, session.skipPhrase, session.start e session.reset.
    #>
    [CmdletBinding()]
    param()

    Register-TmxBridgeAction -Name 'session.status' -Handler {
        param($payload)
        Get-TmxSessionStatus
    }

    Register-TmxBridgeAction -Name 'session.skipPhrase' -Handler {
        param($payload)
        @{ frase = (Get-TmxSkipPhrase) }
    }

    # Sincrona de proposito, apesar de o trabalho ir para o pool: a frase que
    # autoriza pular o ponto de restauracao TEM que ser conferida antes de
    # existir job - com -Async o handler so rodaria dentro do job e a resposta
    # imediata ja teria dito ok:true. Aqui o Start-TmxJob e chamado a mao e a
    # resposta leva o mesmo { jobId } que uma acao assincrona devolveria.
    Register-TmxBridgeAction -Name 'session.start' -Handler {
        param($payload)

        $skip = $false
        if ($payload -and $payload.skip) { $skip = [bool]$payload.skip }

        if ($skip) {
            $frase = ''
            if ($payload -and $null -ne $payload.frase) { $frase = "$($payload.frase)" }
            # -cne: sensivel a maiusculas. Pular o ponto e a unica porta de
            # saida do compromisso de reversibilidade.
            if ($frase -cne (Get-TmxSkipPhrase)) { throw 'frase de confirmacao incorreta' }
        }

        $jobId = Start-TmxJob -Name 'session.start' -Payload @{ skip = $skip } -Handler {
            param($p)
            $pular = $false
            if ($p -and $p.skip) { $pular = [bool]$p.skip }

            Send-TmxJobProgress -Pct 10 -Status 'Criando ponto de restauracao...'
            $r = Start-TmxSession -SkipConfirmado:$pular
            if (-not $r.ok) { throw "$($r.mensagem)" }
            Send-TmxJobProgress -Pct 100 -Status 'Sessao pronta'

            @{ ok = $true; session = (New-TmxSessionSnapshot -Session $r.session) }
        }

        @{ jobId = $jobId }
    }

    # So no modo de teste: a suite precisa reabrir a sessao do zero sem
    # reiniciar a janela.
    Register-TmxBridgeAction -Name 'session.reset' -Handler {
        param($payload)
        if (-not $sync.testMode) { throw 'session.reset so existe no modo de teste' }
        $sync.session = $null
        Send-TmxUiEvent -Event 'session.changed' -Payload (Get-TmxSessionStatus)
        @{ ok = $true }
    }
}
