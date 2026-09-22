# functions/install/Get-TmxInstalledPackages.ps1
# Le "winget list" e devolve os pacotes instalados. Porta a ideia de
# reference/winutil/functions/public/Invoke-WPFGetInstalled.ps1, mas sem
# depender da UI do WinUtil: aqui e so parse + (opcionalmente) cruzamento
# com o catalogo do TweakMaxing.

function ConvertFrom-TmxWingetListOutput {
    <#
    .SYNOPSIS
        Faz o parse de "winget list --accept-source-agreements
        --disable-interactivity" para uma lista de { id, nome, versao, disponivel }.
    .DESCRIPTION
        As colunas de winget list sao separadas por 2+ espacos (Name/Id/Version
        [/Available] [/Source]); dividir por posicao de caractere quebra com
        nomes de largura variavel (CJK etc.), entao o parse divide por
        '\s{2,}' em vez de contar colunas fixas. Uma linha de separador
        (soh tracos) marca onde os dados comecam; linhas que nao dividem em
        pelo menos 3 campos (rodape, "N upgrades available.", linhas em
        branco) sao ignoradas.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string] $Texto)

    $linhas = @($Texto -split "`r?`n")

    $idxCabecalho = -1
    for ($i = 0; $i -lt $linhas.Count; $i++) {
        if ($linhas[$i] -match '^\s*Name\s+Id\s+Version') { $idxCabecalho = $i; break }
    }
    if ($idxCabecalho -lt 0) { return @() }

    $idxSeparador = $idxCabecalho + 1
    if ($idxSeparador -ge $linhas.Count -or $linhas[$idxSeparador].Trim() -notmatch '^-+$') {
        return @()
    }

    $itens = New-Object System.Collections.Generic.List[object]
    for ($i = $idxSeparador + 1; $i -lt $linhas.Count; $i++) {
        $linha = $linhas[$i]
        if ([string]::IsNullOrWhiteSpace($linha)) { continue }

        $campos = @($linha -split '\s{2,}' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
        if ($campos.Count -lt 3) { continue }

        $nome   = $campos[0]
        $id     = $campos[1]
        $versao = $campos[2]
        $disponivel = $null
        if ($campos.Count -ge 4 -and $campos[3] -ne '-' -and $campos[3] -ne '') {
            $disponivel = $campos[3]
        }

        $itens.Add([pscustomobject]@{ id = $id; nome = $nome; versao = $versao; disponivel = $disponivel })
    }

    # Sem virgula aqui de proposito: quem chama (Get-TmxInstalledPackages,
    # logo abaixo) ja envolve a chamada com @() - somar os dois desenrolaria
    # um resultado de 1 item so num array de 1 elemento contendo outro array.
    $itens.ToArray()
}

function Get-TmxInstalledPackages {
    <#
    .SYNOPSIS
        Pacotes instalados via winget, opcionalmente cruzados com o catalogo.
    .PARAMETER Catalog
        Quando presente, cada item ganha 'instalado' (bool: casou com um app
        do catalogo pelo id de winget, sem diferenciar maiusculas/minusculas)
        e, quando casou, 'catalogId' com o id interno do TweakMaxing.
    .OUTPUTS
        Array de [pscustomobject] { id, nome, versao, disponivel [, instalado, catalogId] }.
    #>
    [CmdletBinding()]
    param([switch] $Catalog)

    $r = Invoke-TmxWingetProcess -Arguments @('list', '--accept-source-agreements', '--disable-interactivity')
    $itens = @(ConvertFrom-TmxWingetListOutput -Texto "$($r.saida)")

    if ($Catalog) {
        # Sem @() aqui: Get-TmxAppCatalog ja se protege com virgula (ver
        # _Wrappers.ps1) - envolver de novo dobraria o array num resultado
        # de 1 categoria/app so.
        $catalogo = Get-TmxAppCatalog
        foreach ($item in $itens) {
            $match = $null
            foreach ($app in $catalogo) {
                $idWinget = "$($app.winget)"
                if ($idWinget -and $idWinget -ieq $item.id) { $match = $app; break }
            }
            if ($match) {
                Add-Member -InputObject $item -NotePropertyName 'catalogId' -NotePropertyValue "$($match.id)" -Force
                Add-Member -InputObject $item -NotePropertyName 'instalado' -NotePropertyValue $true -Force
            } else {
                Add-Member -InputObject $item -NotePropertyName 'instalado' -NotePropertyValue $false -Force
            }
        }
    }

    # Idem: sem a virgula, um unico item instalado sairia como objeto solto.
    ,$itens
}
