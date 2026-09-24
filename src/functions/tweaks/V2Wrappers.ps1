# functions/tweaks/V2Wrappers.ps1
# Wrappers finos usados apenas pelos ajustes novos da v2 (V2*.ps1). Mesma
# regra do resto do projeto: todo cmdlet/executavel que toca o sistema passa
# por aqui, mockavel nos testes, nunca chamado direto de dentro de uma funcao
# nomeada.
#
# Escritas cruas de registro (sem o registro de estado completo de
# Set-TmxRegistry) sao usadas pelos ajustes que precisam do padrao
# New-TmxCmdletRecord + Undo-Tmx<X> -Estado (mesclagem de string, restauracao
# exata) em vez da reversao generica 'registry'.

function Get-TmxV2RegistryStringValue {
    # Valor de uma string do registro, ou $null se a chave/valor nao existir. Nunca lanca.
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Name
    )
    $v = Get-TmxRegistryValue -Path $Path -Name $Name
    if ($null -eq $v) { return $null }
    "$v"
}

function Set-TmxV2RegistryStringValue {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Value
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
    }
    New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType String -Force -ErrorAction Stop | Out-Null
}

function Remove-TmxV2RegistryValue {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Name
    )
    if (-not (Test-Path -LiteralPath $Path)) { return }
    Remove-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue
}

function Get-TmxV2VideoControllers {
    # Adaptadores de video crus (Win32_VideoController), para deteccao de fabricante.
    Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop
}

function Get-TmxV2DefenderComputerStatus {
    Get-MpComputerStatus -ErrorAction Stop
}

function Start-TmxV2DefenderSettingsUri {
    # Abre a tela de configuracoes do Defender. Uri propria do Windows (nao https),
    # por isso nao reusa Start-TmxUrl (que so aceita https).
    Start-Process -FilePath 'windowsdefender://threatsettings' -ErrorAction Stop | Out-Null
    'windowsdefender://threatsettings'
}

function Get-TmxV2PwshCommand {
    # $null quando o PowerShell 7 (pwsh.exe) nao esta no PATH.
    Get-Command -Name 'pwsh' -CommandType Application -ErrorAction SilentlyContinue
}

function Get-TmxV2FileTextRaw {
    # Conteudo cru (sem parse) de um arquivo de texto, ou $null se nao existir.
    param([Parameter(Mandatory)] [string] $Path)
    # ReadAllText e nao Get-Content -Raw: a string do Get-Content carrega
    # propriedades ETS (PSDrive, PSProvider...) e, guardada no state.json,
    # faz o ConvertTo-Json -Depth 12 percorrer o grafo do provider (trava).
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

function Set-TmxV2FileTextRaw {
    # Escreve o texto exato (sem quebra de linha extra no fim), criando a pasta se preciso.
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Texto
    )
    $dir = Split-Path -Path $Path -Parent
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null
    }
    Set-Content -LiteralPath $Path -Value $Texto -Encoding UTF8 -NoNewline -ErrorAction Stop
}
