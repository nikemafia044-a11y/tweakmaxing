# functions/features/Panels.ps1
# Atalhos para os paineis legados do Windows.
#
# A tabela e FIXA e mora no codigo, nao no feature.json: o que chega da
# interface e um id, nunca um comando. Sem isso, "abrir um painel" viraria
# "executar o que a pagina mandar" - e a pagina roda num WebView2.

$script:TmxPanelCatalogo = [ordered]@{
    'PAN-COMPMGMT'  = @{ nome = 'Gerenciamento do Computador';    comando = 'compmgmt.msc' }
    'PAN-CONTROL'   = @{ nome = 'Painel de Controle';             comando = 'control' }
    'PAN-MOUSE'     = @{ nome = 'Propriedades do Mouse';          comando = 'main.cpl' }
    'PAN-NETWORK'   = @{ nome = 'Conexoes de Rede';               comando = 'ncpa.cpl' }
    'PAN-POWER'     = @{ nome = 'Opcoes de Energia';              comando = 'powercfg.cpl' }
    'PAN-PRINTERS'  = @{ nome = 'Impressoras e Scanners';         comando = 'shell:::{A8A91A66-3A7D-4424-8D24-04E180695C7A}' }
    'PAN-PROGRAMS'  = @{ nome = 'Programas e Recursos';           comando = 'appwiz.cpl' }
    'PAN-REGION'    = @{ nome = 'Regiao';                         comando = 'intl.cpl' }
    'PAN-SECURITY'  = @{ nome = 'Seguranca e Manutencao';         comando = 'wscui.cpl' }
    'PAN-SOUND'     = @{ nome = 'Som';                            comando = 'mmsys.cpl' }
    'PAN-SYSTEM'    = @{ nome = 'Propriedades do Sistema';        comando = 'sysdm.cpl' }
    'PAN-TIMEDATE'  = @{ nome = 'Data e Hora';                    comando = 'timedate.cpl' }
    'PAN-FIREWALL'  = @{ nome = 'Firewall do Windows Defender';   comando = 'firewall.cpl' }
    'PAN-RESTORE'   = @{ nome = 'Restauracao do Sistema';         comando = 'rstrui.exe' }
}

function Get-TmxPanelCatalog {
    <#
    .SYNOPSIS
        Os 14 paineis legados, na ordem em que a interface os desenha.
    .OUTPUTS
        Array de { id, nome, comando }.
    #>
    [CmdletBinding()]
    param()

    $lista = New-Object 'System.Collections.Generic.List[object]'
    foreach ($id in $script:TmxPanelCatalogo.Keys) {
        $e = $script:TmxPanelCatalogo[$id]
        $lista.Add([pscustomobject]@{ id = "$id"; nome = "$($e.nome)"; comando = "$($e.comando)" })
    }
    # .ToArray(): @() sobre List generica vazia falha no PS 5.1
    $lista.ToArray()
}

function Open-TmxPanel {
    <#
    .SYNOPSIS
        Abre um painel pelo id da tabela fixa. Qualquer outro id lanca.
    .OUTPUTS
        { ok, id, nome, comando, simulado }
    .NOTES
        No modo de teste nada e aberto: a suite de GUI clica nos botoes de
        verdade e 14 janelas do Painel de Controle abertas por cima da janela
        em teste inviabilizariam o proprio print. O log registra a chamada.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string] $Id)

    $chave = "$Id"
    if (-not $chave -or -not $script:TmxPanelCatalogo.Contains($chave)) {
        throw "painel desconhecido: '$Id'"
    }
    $e       = $script:TmxPanelCatalogo[$chave]
    $comando = "$($e.comando)"

    $simulado = [bool]($null -ne $sync -and $sync.testMode)
    Write-TmxLog -Level INFO -Message 'panels.open' -Data @{ id = $chave; comando = $comando; simulado = $simulado }

    if (-not $simulado) { Start-TmxPanelProcess -Comando $comando | Out-Null }

    [pscustomobject]@{ ok = $true; id = $chave; nome = "$($e.nome)"; comando = $comando; simulado = $simulado }
}
