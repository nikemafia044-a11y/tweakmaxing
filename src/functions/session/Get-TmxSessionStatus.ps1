# functions/session/Get-TmxSessionStatus.ps1
# O que a barra de status da janela mostra sobre a sessao.
#
# Le SO $sync.session: nada de $script:Tmx* aqui. A sessao nasce dentro de um
# job (outra runspace) e o estado de escopo de script dele nao existe na thread
# da janela - $sync e a unica memoria compartilhada entre as duas.

function Get-TmxSessionStatus {
    <#
    .SYNOPSIS
        Estado atual da sessao, seguro de chamar de qualquer runspace.
    .OUTPUTS
        @{ restorePoint = @{ estado; seq; mensagem }; runId; runPath;
           undoCommand; pronto; elevado; testMode }
        estado: nenhum | criando | criado | pulado | falhou
    #>
    [CmdletBinding()]
    param()

    $s        = $null
    $testMode = $false
    if ($null -ne $sync) {
        $s        = $sync.session
        $testMode = [bool]$sync.testMode
    }

    $estado   = 'nenhum'
    $seq      = $null
    $mensagem = $null
    $runId    = $null
    $runPath  = $null
    $undo     = $null
    $pronto   = $false

    if ($s) {
        if ($s.restorePoint) {
            if ($s.restorePoint.estado) { $estado = "$($s.restorePoint.estado)" }
            $seq = $s.restorePoint.seq
            if ($s.restorePoint.mensagem) { $mensagem = "$($s.restorePoint.mensagem)" }
        }
        if ($s.runId)       { $runId   = "$($s.runId)" }
        if ($s.runPath)     { $runPath = "$($s.runPath)" }
        if ($s.undoCommand) { $undo    = "$($s.undoCommand)" }
        $pronto = [bool]$s.pronto
    }

    @{
        restorePoint = @{ estado = $estado; seq = $seq; mensagem = $mensagem }
        runId        = $runId
        runPath      = $runPath
        undoCommand  = $undo
        pronto       = $pronto
        elevado      = [bool](Test-TmxElevation)
        testMode     = $testMode
    }
}
