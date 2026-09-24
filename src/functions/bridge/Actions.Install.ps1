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

function Get-TmxAppCategoryOrder {
    <#
    .SYNOPSIS
        Ids das categorias da tela Aplicativos, na ordem das abas (spec 10).
    #>
    [CmdletBinding()]
    param()
    @('navegadores', 'comunicacao', 'jogos', 'desenvolvimento', 'multimidia', 'utilitarios')
}

function Get-TmxAppCategoryLabels {
    <#
    .SYNOPSIS
        Rotulo pt-BR de cada categoria v2 (acentos via [char]: o .ps1 e ASCII).
    #>
    [CmdletBinding()]
    param()
    @{
        navegadores     = 'Navegadores'
        comunicacao     = ('Comunica' + [char]0x00E7 + [char]0x00E3 + 'o')
        jogos           = 'Jogos'
        desenvolvimento = 'Desenvolvimento'
        multimidia      = ('Multim' + [char]0x00ED + 'dia')
        utilitarios     = ('Utilit' + [char]0x00E1 + 'rios')
    }
}

function Get-TmxAppCategoryV2 {
    <#
    .SYNOPSIS
        Categoria v2 de um app: 'categoriaV2' do catalogo quando valida; senao
        mapeia a 'categoria' antiga (Navegadores, Comunicacao, Jogos,
        Desenvolvimento, Multimidia); todo o resto cai em 'utilitarios'.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] $App)

    $ordem = @(Get-TmxAppCategoryOrder)
    $v2 = "$($App.categoriaV2)".ToLowerInvariant()
    if ($v2 -and ($ordem -contains $v2)) { return $v2 }

    switch -Regex ("$($App.categoria)") {
        '^Navegadores$'     { return 'navegadores' }
        '^Comunica'         { return 'comunicacao' }
        '^Jogos$'           { return 'jogos' }
        '^Desenvolvimento$' { return 'desenvolvimento' }
        '^Multim'           { return 'multimidia' }
    }
    'utilitarios'
}

function Get-TmxSimulatedInstalledPackages {
    <#
    .SYNOPSIS
        Lista de "instalados" do modo de teste: um item por id do catalogo
        pedido, no mesmo formato de Get-TmxInstalledPackages -Catalog. Ids fora
        do catalogo sao ignorados. Nunca chama o winget.
    #>
    [CmdletBinding()]
    param([object[]] $Ids = @())

    $catalogo = Get-TmxAppCatalog
    $itens = New-Object System.Collections.Generic.List[object]
    foreach ($id in @($Ids | ForEach-Object { "$_" } | Where-Object { $_ })) {
        $app = @($catalogo | Where-Object { "$($_.id)" -ieq $id }) | Select-Object -First 1
        if (-not $app) { continue }
        $itens.Add([pscustomobject]@{
            id = "$($app.winget)"; nome = "$($app.nome)"; versao = '1.0'; disponivel = $null
            instalado = $true; catalogId = "$($app.id)"
        })
    }
    ,$itens.ToArray()
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

        # v2 (spec 10): seis categorias fixas, na ordem da tela. Cada grupo
        # leva 'id' (chave estavel: o front traduz por ela) e 'nome' (rotulo
        # pt-BR). A descricao em ingles vem de i18n.en.descricao do catalogo.
        $apps = Get-TmxAppCatalog
        $grupos = [ordered]@{}
        foreach ($idCat in @(Get-TmxAppCategoryOrder)) {
            $grupos[$idCat] = New-Object System.Collections.Generic.List[object]
        }
        foreach ($a in $apps) {
            $cat = Get-TmxAppCategoryV2 -App $a
            $descricaoEn = ''
            if ($a.i18n -and $a.i18n.en -and $a.i18n.en.descricao) { $descricaoEn = "$($a.i18n.en.descricao)" }
            $grupos[$cat].Add([ordered]@{
                id          = "$($a.id)"
                nome        = "$($a.nome)"
                descricao   = "$($a.descricao)"
                descricaoEn = $descricaoEn
                categoria   = $cat
                winget      = "$($a.winget)"
                choco       = "$($a.choco)"
                link        = "$($a.link)"
                foss        = [bool]$a.foss
            })
        }

        $rotulos = Get-TmxAppCategoryLabels
        $categorias = New-Object System.Collections.Generic.List[object]
        foreach ($idCat in $grupos.Keys) {
            if ($grupos[$idCat].Count -eq 0) { continue }
            $categorias.Add([ordered]@{ id = $idCat; nome = "$($rotulos[$idCat])"; apps = $grupos[$idCat].ToArray() })
        }

        @{ categorias = $categorias.ToArray(); total = @($apps).Count }
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
        # Modo de teste com 'simular': nada de winget - a lista de instalados
        # e montada a partir dos ids pedidos (so os que existem no catalogo).
        # Sem 'simular' o caminho normal continua (os testes Pester mockam o
        # winget e contam com isso).
        if ($null -ne $sync -and $sync.testMode -and $null -ne $payload -and $null -ne $payload.simular) {
            return @{ itens = (Get-TmxSimulatedInstalledPackages -Ids @($payload.simular)); simulado = $true }
        }
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
        # isso. install.js chama em lotes de ate 10 ids (IntersectionObserver
        # + debounce), entao o limite de 40 aqui e so uma trava de sanidade
        # contra um payload malformado - o back-end aceita ate 40 mesmo que
        # o front-end nunca peca mais que 10 por vez.
        #
        # Payload ausente ou sem 'ids' vira lista vazia (icons:{}), nao erro:
        # um pedido vazio nao e um pedido malformado.
        $ids = New-Object 'System.Collections.Generic.List[string]'
        if ($null -ne $payload -and $null -ne $payload.ids) {
            foreach ($idBruto in @($payload.ids)) {
                if ($null -eq $idBruto) { continue }
                if ($idBruto -isnot [string]) { throw 'apps.icons: cada id precisa ser texto' }
                $ids.Add($idBruto)
            }
        }
        if ($ids.Count -gt 40) { throw 'apps.icons aceita no maximo 40 ids por chamada' }
        if ($ids.Count -eq 0) { return @{ icons = [ordered]@{}; pendentes = @() } }

        $catalogo = Get-TmxAppCatalog
        $apps = New-Object 'System.Collections.Generic.List[object]'
        foreach ($id in $ids) {
            if ([string]::IsNullOrWhiteSpace($id)) { continue }
            $app = @($catalogo | Where-Object { "$($_.id)" -ieq "$id" }) | Select-Object -First 1
            if ($app) { $apps.Add($app) }
        }

        # Lida UMA vez por lote (nao por app): Get-TmxUninstallEntries varre
        # o registro de desinstalar inteiro (HKLM + WOW6432Node + HKCU), e um
        # lote pode ter ate 40 ids - repetir a varredura por app deixaria um
        # lote cheio visivelmente lento.
        $entradasDesinstalar = Get-TmxUninstallEntries

        # Orcamento de 8s pro lote INTEIRO (nao por app): ids que nao
        # couberem saem sem icone (front-end so mantem as iniciais) - nunca
        # travam o slot de job unico do app. Ids do payload que nao existem
        # no catalogo nunca entram em 'pendentes' (nunca chegam a virar um
        # item de $apps) - ficam so de fora de 'icons', como sempre.
        $resultado = Invoke-TmxAppIconBatch -Apps $apps.ToArray() -UninstallEntries $entradasDesinstalar -BudgetMs 8000
        @{ icons = $resultado.Icones; pendentes = $resultado.Pendentes }
    }
}
