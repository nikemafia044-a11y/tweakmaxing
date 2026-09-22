# functions/bridge/Register-TmxBridgeAction.ps1
# Registro das acoes que a UI pode chamar pela ponte JSON.
#
# Nada aqui conhece WebView2: a ponte e um dicionario nome -> handler, o que
# permite testar tudo sem abrir janela.

function Register-TmxBridgeAction {
    <#
    .SYNOPSIS
        Registra (ou substitui) uma acao da ponte.
    .PARAMETER Name
        Nome exato usado pelo JS em bridge.call('<nome>', payload).
    .PARAMETER Handler
        Scriptblock que recebe o payload como unico argumento e devolve o
        resultado. Lancar excecao vira { ok:false, error:{ message } }.
    .PARAMETER Async
        Roda no pool de runspaces via Start-TmxJob; a resposta imediata leva
        so o jobId e o resultado chega pelo evento job.done.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [scriptblock] $Handler,
        [switch] $Async
    )

    if ($null -eq $sync) { throw 'Register-TmxBridgeAction: $sync nao existe (bootstrap nao rodou).' }
    if (-not $sync.ContainsKey('bridgeActions') -or $null -eq $sync.bridgeActions) {
        $sync.bridgeActions = @{}
    }

    $sync.bridgeActions[$Name] = @{ handler = $Handler; async = [bool]$Async }
}

function Get-TmxBridgeAction {
    <#
    .SYNOPSIS
        Devolve o registro de uma acao (ou $null se nao existir).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Name)

    if ($null -eq $sync -or $null -eq $sync.bridgeActions) { return $null }
    $sync.bridgeActions[$Name]
}

function Clear-TmxBridgeActions {
    <#
    .SYNOPSIS
        Esvazia o registro de acoes (usado pelos testes entre contextos).
    #>
    [CmdletBinding()]
    param()
    if ($null -ne $sync) { $sync.bridgeActions = @{} }
}
