# functions/tweaks/RemoveEdge.ps1
# APM-002: remocao do Microsoft Edge.
#
# O desinstalador e o oficial da Microsoft; o truque do WinUtil e criar um
# MicrosoftEdge.exe vazio na pasta do Edge legado, que e o que destrava a
# desinstalacao em nivel de sistema. Reversibilidade PARCIAL: a volta e winget.

function Get-TmxEdgeLegacyStubPath {
    Join-Path $env:SystemRoot 'SystemApps\Microsoft.MicrosoftEdge_8wekyb3d8bbwe\MicrosoftEdge.exe'
}

function Test-TmxRemoveEdge {
    [CmdletBinding()]
    param($Tweak, $Profile)

    $setup = Get-TmxEdgeSetupPath
    $removido = [string]::IsNullOrEmpty("$setup")
    [pscustomobject]@{
        aplicado = $removido
        atual    = $(if ($removido) { 'Edge ausente' } else { "$setup" })
        esperado = 'Edge ausente'
        detalhe  = $(if ($removido) { 'nenhum setup.exe do Edge encontrado' } else { 'Edge instalado' })
    }
}

function Set-TmxRemoveEdge {
    [CmdletBinding()]
    param($Tweak, $Profile, $Parametros)

    $setup = Get-TmxEdgeSetupPath
    if (-not $setup) {
        return [pscustomobject]@{ ok = $true; naoAplicavel = $true; detalhe = 'Microsoft Edge nao esta instalado' }
    }

    $stub = Get-TmxEdgeLegacyStubPath
    $rec = New-TmxCmdletRecord -TweakId "$($Tweak.id)" -Funcao 'Set-TmxRemoveEdge' -Alvo 'Microsoft Edge' `
            -Estado @{ setup = "$setup"; stub = "$stub"; pacoteWinget = 'Microsoft.Edge' } `
            -ValorAnterior 'instalado' -ValorNovo 'removido'

    try {
        if (-not (Test-TmxItemPath -Path $stub)) {
            New-Item -Path $stub -ItemType File -Force -ErrorAction Stop | Out-Null
        }
        $r = Invoke-TmxProcess -FilePath $setup -ArgumentList @('--uninstall', '--system-level', '--force-uninstall', '--delete-profile')
        if ($null -ne $r.codigo -and $r.codigo -ne 0) {
            throw "setup.exe --uninstall saiu com codigo $($r.codigo)"
        }
        Complete-TmxStateRecord -Record $rec -Ok $true | Out-Null
        [pscustomobject]@{ ok = $true; detalhe = 'Microsoft Edge removido'; registro = $rec }
    } catch {
        Complete-TmxStateRecord -Record $rec -Ok $false -Erro $_.Exception.Message | Out-Null
        [pscustomobject]@{ ok = $false; detalhe = $_.Exception.Message; registro = $rec }
    }
}

function Undo-TmxRemoveEdge {
    [CmdletBinding()]
    param($Estado)

    $pacote = 'Microsoft.Edge'
    if ($Estado -and $Estado.pacoteWinget) { $pacote = "$($Estado.pacoteWinget)" }

    $r = Invoke-TmxWinget @('install', '--id', $pacote, '--source', 'winget',
                            '--accept-package-agreements', '--accept-source-agreements')
    if ($r.codigo -ne 0) { throw "winget install $pacote falhou ($($r.codigo)): $($r.saida)" }
    "Microsoft Edge reinstalado via winget ($pacote)"
}
