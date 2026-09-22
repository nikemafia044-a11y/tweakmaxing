# src/TweakMaxing.psm1
# Modulo raiz do TweakMaxing. Dot-source de tudo em ordem de dependencia.
#
# O Core e obrigatorio: sem qualquer um dos seis arquivos o modulo nao tem
# como garantir reversibilidade, entao a importacao falha alto. Engine e as
# pastas de funcoes sao carregados so quando existem (tarefas futuras as
# adicionam sem exigir alteracao aqui).
#
# Importante: o dot-source precisa acontecer NO ESCOPO DO MODULO (aqui,
# direto no foreach), nunca dentro de uma funcao auxiliar - caso contrario as
# funcoes definidas em cada arquivo ficam presas no escopo local da funcao
# auxiliar e desaparecem quando ela retorna.

$here = $PSScriptRoot

# --- Core (ordem de dependencia; obrigatorio) -------------------------------
$tmxCoreOrder = 'Logger', 'Backup', 'Registry', 'Rollback', 'RestorePoint', 'Guard'
foreach ($tmxName in $tmxCoreOrder) {
    $tmxPath = Join-Path $here "Core\$tmxName.ps1"
    if (-not (Test-Path -LiteralPath $tmxPath)) {
        throw "Core\$tmxName.ps1 nao encontrado - modulo TweakMaxing incompleto."
    }
    . $tmxPath
}

# --- Engine (ordem de dependencia; depois o resto em ordem alfabetica) ------
$tmxEngineOrder  = 'Condition', 'Profile', 'Catalog', 'Plan', 'Actions', 'Apply', 'Preview'
$tmxEngineDir    = Join-Path $here 'Engine'
$tmxEngineCarregados = New-Object 'System.Collections.Generic.List[string]'
foreach ($tmxName in $tmxEngineOrder) {
    $tmxPath = Join-Path $tmxEngineDir "$tmxName.ps1"
    if (Test-Path -LiteralPath $tmxPath) { . $tmxPath; $tmxEngineCarregados.Add("$tmxName.ps1") }
}
if (Test-Path -LiteralPath $tmxEngineDir) {
    $tmxEngineExtras = Get-ChildItem -LiteralPath $tmxEngineDir -Filter '*.ps1' -File | Sort-Object Name
    foreach ($tmxFile in $tmxEngineExtras) {
        if (-not $tmxEngineCarregados.Contains($tmxFile.Name)) { . $tmxFile.FullName; $tmxEngineCarregados.Add($tmxFile.Name) }
    }
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

Remove-Variable -Name tmxCoreOrder, tmxEngineOrder, tmxEngineDir, tmxEngineCarregados, tmxEngineExtras, tmxFunctionFolders, tmxName, tmxPath, tmxFolder, tmxDir, tmxFiles, tmxFile, here -ErrorAction SilentlyContinue
