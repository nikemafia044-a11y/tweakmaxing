# functions/tweaks/AdobeBlock.ps1
# RED-002 (FOLCLORE): lista de bloqueio de dominios da Adobe no arquivo hosts.
#
# So roda se o usuario marcar. Antes de escrever qualquer coisa, o arquivo hosts
# inteiro e copiado para <run>\hosts.bak: a reversao restaura o arquivo original
# byte a byte, em vez de tentar adivinhar o que apagar com expressao regular.

$script:TmxAdobeHostsUrl = 'https://github.com/Ruddernation-Designs/Adobe-URL-Block-List/raw/refs/heads/master/hosts'

function Get-TmxAdobeHostsBackupPath {
    $run = Get-TmxRun
    if (-not $run) { throw 'Nenhuma execucao ativa. Chame New-TmxRun primeiro.' }
    Join-Path $run.RunPath 'hosts.bak'
}

function Test-TmxAdobeBlock {
    [CmdletBinding()]
    param($Tweak, $Profile)

    $hosts = Get-TmxHostsPath
    if (-not (Test-TmxItemPath -Path $hosts)) {
        return [pscustomobject]@{ aplicado = $null; atual = $null; esperado = 'hosts com dominios da Adobe'; detalhe = 'arquivo hosts nao encontrado' }
    }
    $texto = ''
    try { $texto = "$(Get-TmxFileText -Path $hosts)" } catch { $texto = '' }
    $tem = ($texto -match '(?i)adobe')
    [pscustomobject]@{
        aplicado = $tem
        atual    = $(if ($tem) { 'hosts cita dominios da Adobe' } else { 'hosts sem dominios da Adobe' })
        esperado = 'hosts cita dominios da Adobe'
        detalhe  = "arquivo: $hosts"
    }
}

function Set-TmxAdobeBlock {
    [CmdletBinding()]
    param($Tweak, $Profile, $Parametros)

    $hosts = Get-TmxHostsPath
    if (-not (Test-TmxItemPath -Path $hosts)) {
        return [pscustomobject]@{ ok = $false; detalhe = "arquivo hosts nao encontrado: $hosts" }
    }

    $backup = Get-TmxAdobeHostsBackupPath
    $rec = New-TmxCmdletRecord -TweakId "$($Tweak.id)" -Funcao 'Set-TmxAdobeBlock' -Alvo 'arquivo hosts' `
            -Estado @{ hosts = $hosts; backup = $backup; origem = $script:TmxAdobeHostsUrl } `
            -ValorAnterior $backup -ValorNovo 'hosts com lista de bloqueio da Adobe'

    try {
        # Backup ANTES do download: se a rede falhar no meio, o backup ja existe.
        Copy-TmxItemPath -Path $hosts -Destino $backup | Out-Null

        $lista = Invoke-TmxWebRequestText -Uri $script:TmxAdobeHostsUrl
        if (-not $lista) { throw 'a lista de bloqueio voltou vazia' }

        Add-TmxFileText -Path $hosts -Texto "$lista"
        Invoke-TmxIpconfig @('/flushdns') | Out-Null

        Complete-TmxStateRecord -Record $rec -Ok $true | Out-Null
        [pscustomobject]@{ ok = $true; detalhe = "lista adicionada ao hosts (backup em $backup)"; registro = $rec }
    } catch {
        Complete-TmxStateRecord -Record $rec -Ok $false -Erro $_.Exception.Message | Out-Null
        [pscustomobject]@{ ok = $false; detalhe = $_.Exception.Message; registro = $rec }
    }
}

function Undo-TmxAdobeBlock {
    [CmdletBinding()]
    param($Estado)

    if (-not $Estado -or -not $Estado.backup) { throw 'sem backup do hosts no estado; nada a restaurar' }
    $backup = "$($Estado.backup)"
    $hosts  = "$($Estado.hosts)"
    if (-not $hosts) { $hosts = Get-TmxHostsPath }

    if (-not (Test-TmxItemPath -Path $backup)) { throw "backup do hosts nao encontrado: $backup" }

    Copy-TmxItemPath -Path $backup -Destino $hosts | Out-Null
    Invoke-TmxIpconfig @('/flushdns') | Out-Null
    "arquivo hosts restaurado a partir de $backup"
}
