# functions/bridge/Actions.Install.ps1
# Acoes da ponte para a aba Instalar: catalogo, gerenciadores, instalar,
# desinstalar, atualizar tudo, listar instalados, reparar winget, instalar
# Chocolatey, logos dos apps.
#
# Instalar/desinstalar app NAO exige sessao/ponto de restauracao (ao
# contrario dos tweaks): desinstalar e a propria reversao natural de um
# install, entao nao ha nada para "desfazer" via rollback do Core.

function Get-TmxCatalogAppOrThrow {
    <#
    .SYNOPSIS
        Devolve o app do catalogo com o id dado ou lanca "app desconhecido".
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]   $Id,
        [Parameter(Mandatory)] [object[]] $Catalogo
    )
    $achado = @($Catalogo | Where-Object { "$($_.id)" -ieq $Id }) | Select-Object -First 1
    if (-not $achado) { throw "app desconhecido: $Id" }
    $achado
}

function Register-TmxInstallActions {
    <#
    .SYNOPSIS
        Registra apps.catalog, apps.managers, apps.install, apps.uninstall,
        apps.upgradeAll, apps.installed, apps.repairWinget e apps.installChoco.
    #>
    [CmdletBinding()]
    param()

    Register-TmxBridgeAction -Name 'apps.catalog' -Handler {
        param($payload)

        $apps = Get-TmxAppCatalog
        $grupos = [ordered]@{}
        foreach ($a in $apps) {
            $cat = "$($a.categoria)"
            if (-not $cat) { $cat = 'Outros' }
            if (-not $grupos.Contains($cat)) {
                $grupos[$cat] = New-Object System.Collections.Generic.List[object]
            }
            $grupos[$cat].Add([ordered]@{
                id        = "$($a.id)"
                nome      = "$($a.nome)"
                descricao = "$($a.descricao)"
                categoria = $cat
                winget    = "$($a.winget)"
                choco     = "$($a.choco)"
                link      = "$($a.link)"
                foss      = [bool]$a.foss
            })
        }

        $categorias = New-Object System.Collections.Generic.List[object]
        foreach ($nomeCategoria in $grupos.Keys) {
            $categorias.Add([ordered]@{ nome = $nomeCategoria; apps = $grupos[$nomeCategoria].ToArray() })
        }

        @{ categorias = $categorias.ToArray() }
    }

    Register-TmxBridgeAction -Name 'apps.managers' -Handler {
        param($payload)
        Test-TmxPackageManager
    }

    Register-TmxBridgeAction -Name 'apps.install' -Async -Handler {
        param($payload)
        $ids = @($payload.ids | Where-Object { -not [string]::IsNullOrWhiteSpace("$_") })
        if ($ids.Count -eq 0) { throw 'nenhum app selecionado' }

        $catalogo = Get-TmxAppCatalog
        foreach ($id in $ids) { Get-TmxCatalogAppOrThrow -Id "$id" -Catalogo $catalogo | Out-Null }

        Invoke-TmxPackage -Action Install -Programs $ids -Manager auto -Catalog
    }

    Register-TmxBridgeAction -Name 'apps.uninstall' -Async -Handler {
        param($payload)
        $ids = @($payload.ids | Where-Object { -not [string]::IsNullOrWhiteSpace("$_") })
        if ($ids.Count -eq 0) { throw 'nenhum app selecionado' }

        $catalogo = Get-TmxAppCatalog
        foreach ($id in $ids) { Get-TmxCatalogAppOrThrow -Id "$id" -Catalogo $catalogo | Out-Null }

        Invoke-TmxPackage -Action Uninstall -Programs $ids -Manager auto -Catalog
    }

    Register-TmxBridgeAction -Name 'apps.upgradeAll' -Async -Handler {
        param($payload)
        Invoke-TmxPackage -Action Upgrade -Programs @('all') -Manager auto
    }

    Register-TmxBridgeAction -Name 'apps.installed' -Async -Handler {
        param($payload)
        @{ itens = Get-TmxInstalledPackages -Catalog }
    }

    Register-TmxBridgeAction -Name 'apps.repairWinget' -Async -Handler {
        param($payload)
        # Reparar o winget instala/atualiza o modulo Microsoft.WinGet.Client
        # da PowerShell Gallery - a UI mostra o que isso faz num modal antes
        # de chamar esta acao, e so manda { consentido: true } depois do
        # clique em "Reparar". Sem isso, a ponte recusa.
        if ($payload.consentido -ne $true) { throw 'consentimento pendente' }
        Install-TmxWinget -Force
    }

    Register-TmxBridgeAction -Name 'apps.installChoco' -Async -Handler {
        param($payload)
        # Mesma ideia: install.js mostra o modal explicando o download do
        # instalador oficial antes de chamar esta acao com consentido:true.
        if ($payload.consentido -ne $true) { throw 'consentimento pendente' }
        Install-TmxChoco
    }

    Register-TmxBridgeAction -Name 'apps.icons' -Async -Handler {
        param($payload)
        # Assincrono como os outros apps.* demorados: um icone pode envolver
        # download de rede (site oficial), e a janela nao pode travar por
        # isso. install.js chama em lotes de ate 40 ids (IntersectionObserver
        # + debounce), entao o limite aqui e so uma trava de sanidade contra
        # um payload malformado.
        $ids = @($payload.ids)
        if ($ids.Count -gt 40) { throw 'apps.icons aceita no maximo 40 ids por chamada' }
        foreach ($idBruto in $ids) {
            if ($idBruto -isnot [string]) { throw 'apps.icons: cada id precisa ser texto' }
        }

        $catalogo = Get-TmxAppCatalog
        # Lida UMA vez por lote (nao por app): Get-TmxUninstallEntries varre
        # o registro de desinstalar inteiro (HKLM + WOW6432Node + HKCU), e um
        # lote pode ter ate 40 ids - repetir a varredura por app deixaria um
        # lote cheio visivelmente lento.
        $entradasDesinstalar = Get-TmxUninstallEntries
        $icones = [ordered]@{}
        foreach ($id in $ids) {
            if ([string]::IsNullOrWhiteSpace("$id")) { continue }
            $app = @($catalogo | Where-Object { "$($_.id)" -ieq "$id" }) | Select-Object -First 1
            if (-not $app) { continue }
            $achado = Get-TmxAppIcon -App $app -UninstallEntries $entradasDesinstalar
            if ($achado) { $icones["$($achado.id)"] = @{ src = $achado.src; origem = $achado.origem } }
        }
        @{ icons = $icones }
    }
}
