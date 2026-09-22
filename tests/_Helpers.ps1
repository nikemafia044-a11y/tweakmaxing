# tests/_Helpers.ps1
# Utilitarios compartilhados pelos testes Pester do TweakMaxing: import do
# modulo, pasta de execucao isolada (TWEAKMAXING_HOME) e limpeza da chave de
# testes no registro. Nao exige elevacao.

function Import-TmxTestModule {
    <#
    .SYNOPSIS
        Importa o modulo TweakMaxing a partir de src/TweakMaxing.psd1.
    #>
    [CmdletBinding()]
    param()
    Import-Module (Join-Path $PSScriptRoot '..\src\TweakMaxing.psd1') -Force
}

function New-TmxTestHome {
    <#
    .SYNOPSIS
        Cria uma pasta temporaria unica e aponta TWEAKMAXING_HOME para ela.
    .OUTPUTS
        O caminho da pasta criada.
    #>
    [CmdletBinding()]
    param()
    $tmxHome = Join-Path ([System.IO.Path]::GetTempPath()) ('TweakMaxingTests_{0}' -f ([guid]::NewGuid().ToString('N')))
    New-Item -ItemType Directory -Path $tmxHome -Force | Out-Null
    $env:TWEAKMAXING_HOME = $tmxHome
    $tmxHome
}

function Remove-TmxTestHome {
    <#
    .SYNOPSIS
        Remove a pasta apontada por TWEAKMAXING_HOME (se existir) e limpa a variavel de ambiente.
    #>
    [CmdletBinding()]
    param()
    if ($env:TWEAKMAXING_HOME -and (Test-Path -LiteralPath $env:TWEAKMAXING_HOME)) {
        Remove-Item -LiteralPath $env:TWEAKMAXING_HOME -Recurse -Force -ErrorAction SilentlyContinue
    }
    Remove-Item Env:\TWEAKMAXING_HOME -ErrorAction SilentlyContinue
}

function Remove-TmxTestKey {
    <#
    .SYNOPSIS
        Remove recursivamente HKCU:\Software\TweakMaxing_Tests, se existir.
    #>
    [CmdletBinding()]
    param()
    Remove-Item -LiteralPath 'HKCU:\Software\TweakMaxing_Tests' -Recurse -Force -ErrorAction SilentlyContinue
}
