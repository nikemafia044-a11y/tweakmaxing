# functions/tweaks/RemoveOneDrive.ps1
# APM-003: remocao do OneDrive (porte do script do WinUtil para wrappers).
#
# Sequencia: nega a exclusao da pasta do OneDrive (para o desinstalador nao levar
# os arquivos do usuario junto), roda o OneDriveSetup.exe /uninstall, limpa os
# residuos, devolve a permissao e desativa o OneSyncSvc.
# Reversibilidade PARCIAL: a volta e winget + restauracao do tipo de inicio do servico.

function Get-TmxOneDriveSetupPath {
    Join-Path $env:SystemRoot 'System32\OneDriveSetup.exe'
}

function Test-TmxRemoveOneDrive {
    [CmdletBinding()]
    param($Tweak, $Profile)

    $pastaApp = Join-Path $env:LocalAppData 'Microsoft\OneDrive'
    $presente = (Test-TmxItemPath -Path $pastaApp)
    [pscustomobject]@{
        aplicado = (-not $presente)
        atual    = $(if ($presente) { 'OneDrive instalado' } else { 'OneDrive ausente' })
        esperado = 'OneDrive ausente'
        detalhe  = "pasta do aplicativo: $pastaApp"
    }
}

function Set-TmxRemoveOneDrive {
    [CmdletBinding()]
    param($Tweak, $Profile, $Parametros)

    $setup = Get-TmxOneDriveSetupPath
    if (-not (Test-TmxItemPath -Path $setup)) {
        return [pscustomobject]@{ ok = $true; naoAplicavel = $true; detalhe = 'OneDriveSetup.exe nao encontrado' }
    }

    $pastaUsuario = "$($env:OneDrive)"
    $servicoAntes = $null
    try { $servicoAntes = (Get-TmxServiceState -Nome 'OneSyncSvc').startType } catch { $servicoAntes = $null }

    $rec = New-TmxCmdletRecord -TweakId "$($Tweak.id)" -Funcao 'Set-TmxRemoveOneDrive' -Alvo 'Microsoft OneDrive' `
            -Estado @{ pasta = $pastaUsuario; servicoAnterior = $servicoAntes; pacoteWinget = 'Microsoft.OneDrive' } `
            -ValorAnterior 'instalado' -ValorNovo 'removido'

    try {
        if ($pastaUsuario -and (Test-TmxItemPath -Path $pastaUsuario)) {
            Invoke-TmxIcacls @($pastaUsuario, '/deny', '*S-1-5-32-544:(D,DC)') | Out-Null
        }

        $r = Invoke-TmxProcess -FilePath $setup -ArgumentList @('/uninstall')
        if ($null -ne $r.codigo -and $r.codigo -ne 0) {
            throw "OneDriveSetup.exe /uninstall saiu com codigo $($r.codigo)"
        }

        # OneDrive segura arquivos via FileCoAuth e via Explorer.
        Stop-TmxProcessByName -Nome @('FileCoAuth', 'explorer')
        Remove-TmxItemPath -Path (Join-Path $env:LocalAppData 'Microsoft\OneDrive') -Recursivo -Silencioso
        Remove-TmxItemPath -Path (Join-Path $env:ProgramData 'Microsoft OneDrive') -Recursivo -Silencioso

        if ($pastaUsuario -and (Test-TmxItemPath -Path $pastaUsuario)) {
            Invoke-TmxIcacls @($pastaUsuario, '/grant', '*S-1-5-32-544:(D,DC)') | Out-Null
        }

        if ($null -ne $servicoAntes) {
            Set-TmxServiceState -Nome 'OneSyncSvc' -StartType 'Disabled'
        }

        Complete-TmxStateRecord -Record $rec -Ok $true | Out-Null
        [pscustomobject]@{ ok = $true; detalhe = 'OneDrive removido e OneSyncSvc desativado'; registro = $rec }
    } catch {
        Complete-TmxStateRecord -Record $rec -Ok $false -Erro $_.Exception.Message | Out-Null
        [pscustomobject]@{ ok = $false; detalhe = $_.Exception.Message; registro = $rec }
    }
}

function Undo-TmxRemoveOneDrive {
    [CmdletBinding()]
    param($Estado)

    $pacote = 'Microsoft.OneDrive'
    if ($Estado -and $Estado.pacoteWinget) { $pacote = "$($Estado.pacoteWinget)" }

    $partes = New-Object 'System.Collections.Generic.List[string]'

    $r = Invoke-TmxWinget @('install', '--id', $pacote, '--source', 'winget',
                            '--accept-package-agreements', '--accept-source-agreements')
    if ($r.codigo -ne 0) { throw "winget install $pacote falhou ($($r.codigo)): $($r.saida)" }
    $partes.Add("OneDrive reinstalado via winget ($pacote)")

    $servico = $null
    if ($Estado) { $servico = $Estado.servicoAnterior }
    if ($servico) {
        Set-TmxServiceState -Nome 'OneSyncSvc' -StartType "$servico"
        $partes.Add("OneSyncSvc restaurado para $servico")
    }

    $partes.ToArray() -join '; '
}
