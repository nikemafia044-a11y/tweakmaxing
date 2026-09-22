# src/TweakMaxing.psm1
# Modulo raiz do TweakMaxing. Dot-source de tudo em ordem de dependencia.
#
# So carrega arquivos que existem: tarefas futuras adicionam Engine e as
# pastas de funcoes sem exigir alteracao aqui.
#
# Importante: o dot-source precisa acontecer NO ESCOPO DO MODULO (aqui,
# direto no foreach), nunca dentro de uma funcao auxiliar - caso contrario as
# funcoes definidas em cada arquivo ficam presas no escopo local da funcao
# auxiliar e desaparecem quando ela retorna.

$here = $PSScriptRoot

# --- Core (ordem de dependencia) --------------------------------------------
$tmxCoreOrder = 'Logger', 'Backup', 'Registry', 'Rollback', 'RestorePoint', 'Guard'
foreach ($tmxName in $tmxCoreOrder) {
    $tmxPath = Join-Path $here "Core\$tmxName.ps1"
    if (Test-Path -LiteralPath $tmxPath) { . $tmxPath }
}

# --- Engine (ordem de dependencia) ------------------------------------------
$tmxEngineOrder = 'Condition', 'Profile', 'Catalog', 'Plan', 'Actions', 'Apply', 'Preview'
foreach ($tmxName in $tmxEngineOrder) {
    $tmxPath = Join-Path $here "Engine\$tmxName.ps1"
    if (Test-Path -LiteralPath $tmxPath) { . $tmxPath }
}

# --- Pastas de funcoes (alfabetica dentro de cada pasta) --------------------
$tmxFunctionFolders = 'tweaks', 'install', 'features', 'session', 'bridge', 'ui'
foreach ($tmxFolder in $tmxFunctionFolders) {
    $tmxDir = Join-Path $here "functions\$tmxFolder"
    if (Test-Path -LiteralPath $tmxDir) {
        $tmxFiles = Get-ChildItem -LiteralPath $tmxDir -Filter '*.ps1' -File | Sort-Object Name
        foreach ($tmxFile in $tmxFiles) { . $tmxFile.FullName }
    }
}

Remove-Variable -Name tmxCoreOrder, tmxEngineOrder, tmxFunctionFolders, tmxName, tmxPath, tmxFolder, tmxDir, tmxFiles, tmxFile, here -ErrorAction SilentlyContinue
