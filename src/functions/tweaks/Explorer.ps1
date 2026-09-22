# functions/tweaks/Explorer.ps1
# DES-002: descoberta automatica de tipo de pasta.
# Compartilhado: Set-TmxExplorerRestart, usado pelos toggles que so precisam do
# shell redesenhar.

# ---------------------------------------------------------------------------
# DES-002: Bags/BagMRU + FolderType
# ---------------------------------------------------------------------------

$script:TmxBagsPath   = 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags'
$script:TmxBagMRUPath = 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\BagMRU'
$script:TmxAllFolders = 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags\AllFolders\Shell'

function Test-TmxExplorerAutoDiscovery {
    [CmdletBinding()]
    param($Tweak, $Profile)

    $v = Get-TmxRegistryValue -Path $script:TmxAllFolders -Name 'FolderType'
    [pscustomobject]@{
        aplicado = ("$v" -eq 'NotSpecified')
        atual    = "$v"
        esperado = 'NotSpecified'
        detalhe  = "FolderType em AllFolders\Shell: $v"
    }
}

function Set-TmxExplorerAutoDiscovery {
    [CmdletBinding()]
    param($Tweak, $Profile, $Parametros)

    # Apagar Bags/BagMRU e destrutivo e o Core nao exporta chave sozinho: exportamos
    # antes, e o undo e um reg import desses arquivos.
    $exports = New-Object 'System.Collections.Generic.List[string]'
    foreach ($chave in @($script:TmxBagsPath, $script:TmxBagMRUPath)) {
        if (-not (Test-TmxItemPath -Path $chave)) { continue }
        $arquivo = Backup-TmxRegistryHive -Path $chave
        if ($arquivo) { $exports.Add("$arquivo") }
    }

    $rec = New-TmxCmdletRecord -TweakId "$($Tweak.id)" -Funcao 'Set-TmxExplorerAutoDiscovery' -Alvo 'banco de visualizacoes do Explorer' `
            -Estado @{ exports = $exports.ToArray(); bags = $script:TmxBagsPath; bagMRU = $script:TmxBagMRUPath } `
            -ValorAnterior ($exports.ToArray() -join '; ') -ValorNovo 'Bags/BagMRU removidos, FolderType=NotSpecified'

    try {
        foreach ($chave in @($script:TmxBagsPath, $script:TmxBagMRUPath)) {
            if (Test-TmxItemPath -Path $chave) { Remove-TmxItemPath -Path $chave -Recursivo }
        }
        Complete-TmxStateRecord -Record $rec -Ok $true | Out-Null
    } catch {
        Complete-TmxStateRecord -Record $rec -Ok $false -Erro $_.Exception.Message | Out-Null
        return [pscustomobject]@{ ok = $false; detalhe = $_.Exception.Message; registros = @($rec) }
    }

    $recReg = Set-TmxRegistry -Path $script:TmxAllFolders -Name 'FolderType' -Value 'NotSpecified' -Type 'String' `
                -TweakId "$($Tweak.id)" -PassThru
    $ok = ("$($recReg.status)" -eq 'aplicado')
    [pscustomobject]@{
        ok        = $ok
        detalhe   = $(if ($ok) { 'descoberta automatica desativada; saia e entre de novo para valer' } else { "$($recReg.erro)" })
        registros = @($rec, $recReg)
    }
}

function Undo-TmxExplorerAutoDiscovery {
    [CmdletBinding()]
    param($Estado)

    if (-not $Estado) { throw 'sem estado: nao ha exports de Bags/BagMRU para reimportar' }
    $exports = @($Estado.exports)
    if ($exports.Count -eq 0) { return 'nao havia Bags/BagMRU para exportar; nada a reimportar' }

    $ok = New-Object 'System.Collections.Generic.List[string]'
    foreach ($arquivo in $exports) {
        if (-not $arquivo) { continue }
        if (-not (Test-TmxItemPath -Path "$arquivo")) { throw "export nao encontrado: $arquivo" }
        $r = Invoke-TmxRegImport -Arquivo "$arquivo"
        if ($r.codigo -ne 0) { throw "reg import '$arquivo' falhou ($($r.codigo)): $($r.saida)" }
        $ok.Add("$arquivo")
    }
    "Bags/BagMRU reimportados de: $($ok.ToArray() -join '; ')"
}

# ---------------------------------------------------------------------------
# Compartilhado: reiniciar o Explorer
# ---------------------------------------------------------------------------
# Varios toggles do WinUtil terminam em Invoke-WinUtilExplorerUpdate. Aqui isso
# vira uma unica funcao nomeada. Ela nao muda estado nenhum: nao cria registro,
# nao tem o que verificar e o "undo" e reiniciar de novo.

function Test-TmxExplorerRestart {
    [CmdletBinding()]
    param($Tweak, $Profile)
    [pscustomobject]@{
        aplicado = $null
        atual    = $null
        esperado = $null
        detalhe  = 'reiniciar o Explorer nao deixa estado: nada a verificar'
    }
}

function Set-TmxExplorerRestart {
    [CmdletBinding()]
    param($Tweak, $Profile, $Parametros)
    Restart-TmxExplorer
    [pscustomobject]@{ ok = $true; detalhe = 'Explorer reiniciado' }
}

function Undo-TmxExplorerRestart {
    [CmdletBinding()]
    param($Estado)
    Restart-TmxExplorer
    'Explorer reiniciado'
}
