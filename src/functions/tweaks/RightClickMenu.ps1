# functions/tweaks/RightClickMenu.ps1
# INT-007: menu de contexto classico do Windows 10.
#
# Criar a subchave InprocServer32 com valor padrao vazio faz o shell nao achar o
# manipulador do menu novo e cair de volta no classico. A escrita passa por
# Set-TmxRegistry (que marca 'removerChaveCriada'), entao a reversao normal ja
# apaga a chave. Undo-TmxRightClickMenu existe para o par Set/Undo/Test e para
# reversao direta com estado explicito.

$script:TmxRightClickClsid  = 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}'
$script:TmxRightClickInproc = 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32'

function Test-TmxRightClickMenu {
    [CmdletBinding()]
    param($Tweak, $Profile)

    $existe = Test-TmxItemPath -Path $script:TmxRightClickInproc
    [pscustomobject]@{
        aplicado = $existe
        atual    = $(if ($existe) { 'InprocServer32 presente' } else { 'InprocServer32 ausente' })
        esperado = 'InprocServer32 presente'
        detalhe  = "chave: $($script:TmxRightClickInproc)"
    }
}

function Set-TmxRightClickMenu {
    [CmdletBinding()]
    param($Tweak, $Profile, $Parametros)

    $rec = Set-TmxRegistry -Path $script:TmxRightClickInproc -Name '(Default)' -Value '' -Type 'String' `
            -TweakId "$($Tweak.id)" -PassThru
    $ok = ("$($rec.status)" -eq 'aplicado')
    if (-not $ok) {
        return [pscustomobject]@{ ok = $false; detalhe = "$($rec.erro)"; registro = $rec }
    }

    Restart-TmxExplorer
    [pscustomobject]@{ ok = $true; detalhe = 'menu de contexto classico ativado (Explorer reiniciado)'; registro = $rec }
}

function Undo-TmxRightClickMenu {
    [CmdletBinding()]
    param($Estado)

    $chave = $script:TmxRightClickClsid
    if ($Estado -and $Estado.chave) { $chave = "$($Estado.chave)" }

    if (Test-TmxItemPath -Path $chave) {
        Remove-TmxItemPath -Path $chave -Recursivo
    }
    Restart-TmxExplorer
    "chave $chave removida; menu de contexto do Windows 11 de volta"
}
