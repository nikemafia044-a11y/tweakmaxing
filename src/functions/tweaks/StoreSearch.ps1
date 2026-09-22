# functions/tweaks/StoreSearch.ps1
# INT-002: sugestoes da Microsoft Store na busca do Iniciar.
# O bloqueio e por ACL no cache local do catalogo (store.db): sem leitura, a
# busca nao tem de onde tirar sugestao. Estado atual = a ACL tem negacao.

function Get-TmxStoreDbPath {
    Join-Path $env:LocalAppData 'Packages\Microsoft.WindowsStore_8wekyb3d8bbwe\LocalState\store.db'
}

function Test-TmxStoreSearch {
    [CmdletBinding()]
    param($Tweak, $Profile)

    $arquivo = Get-TmxStoreDbPath
    if (-not (Test-TmxItemPath -Path $arquivo)) {
        return [pscustomobject]@{ aplicado = $null; atual = $null; esperado = 'negacao para Everyone'; detalhe = 'store.db nao existe nesta maquina' }
    }
    $r = Invoke-TmxIcacls @($arquivo)
    $temDeny = ("$($r.saida)" -match '(?i)\(DENY\)')
    [pscustomobject]@{
        aplicado = $temDeny
        atual    = $(if ($temDeny) { 'com negacao' } else { 'sem negacao' })
        esperado = 'com negacao'
        detalhe  = "ACL de store.db: $(if ($temDeny) { 'nega leitura' } else { 'sem negacao' })"
    }
}

function Set-TmxStoreSearch {
    [CmdletBinding()]
    param($Tweak, $Profile, $Parametros)

    $arquivo = Get-TmxStoreDbPath
    if (-not (Test-TmxItemPath -Path $arquivo)) {
        return [pscustomobject]@{ ok = $true; naoAplicavel = $true; detalhe = 'store.db nao existe nesta maquina' }
    }

    $antes = Invoke-TmxIcacls @($arquivo)
    $rec = New-TmxCmdletRecord -TweakId "$($Tweak.id)" -Funcao 'Set-TmxStoreSearch' -Alvo 'ACL de store.db' `
            -Estado @{ arquivo = $arquivo; aclAnterior = "$($antes.saida)" } `
            -ValorAnterior 'sem negacao' -ValorNovo 'com negacao'

    try {
        $r = Invoke-TmxIcacls @($arquivo, '/deny', '*S-1-1-0:F')
        if ($r.codigo -ne 0) { throw "icacls /deny falhou ($($r.codigo)): $($r.saida)" }
        Complete-TmxStateRecord -Record $rec -Ok $true | Out-Null
        [pscustomobject]@{ ok = $true; detalhe = 'leitura de store.db negada para Everyone'; registro = $rec }
    } catch {
        Complete-TmxStateRecord -Record $rec -Ok $false -Erro $_.Exception.Message | Out-Null
        [pscustomobject]@{ ok = $false; detalhe = $_.Exception.Message; registro = $rec }
    }
}

function Undo-TmxStoreSearch {
    [CmdletBinding()]
    param($Estado)

    $arquivo = Get-TmxStoreDbPath
    if ($Estado -and $Estado.arquivo) { $arquivo = "$($Estado.arquivo)" }

    $r = Invoke-TmxIcacls @($arquivo, '/grant', '*S-1-1-0:F')
    if ($r.codigo -ne 0) { throw "icacls /grant falhou ($($r.codigo)): $($r.saida)" }
    "acesso a store.db devolvido a Everyone"
}
