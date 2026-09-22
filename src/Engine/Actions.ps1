# Engine/Actions.ps1
# Granularidade de ACAO: cada tweak do catalogo tem `acoes[]` e cada acao e
# aplicada/verificada/revertida isoladamente.
#
# Contratos:
#   Invoke-TmxAction -Action -Tweak -Profile -> { ok, detalhe, naoAplicavel, naoSuportado, registros }
#   Test-TmxAction   -Action -Tweak -Profile -> { aplicado ($true/$false/$null), atual, esperado, detalhe }
#   Test-TmxTweakApplied -Tweak -Profile     -> agregado de todas as acoes do tweak
#
# Regra de ouro: o registro de estado (New-TmxStateRecord / Set-TmxRegistry) e
# persistido em disco ANTES de qualquer chamada que mude o sistema. Se o
# processo morrer no meio, Undo-TweakMaxing ainda sabe o que restaurar.
#
# Tudo que toca o sistema passa por um wrapper fino (mockavel nos testes).

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Get-TmxActionProp {
    <#
    .SYNOPSIS
        Le uma propriedade opcional de uma acao (pscustomobject ou hashtable),
        devolvendo $Padrao quando ausente ou nula. Sobrevive a Set-StrictMode.
    #>
    param($Action, [Parameter(Mandatory)] [string] $Nome, $Padrao = $null)

    if ($null -eq $Action) { return $Padrao }
    if ($Action -is [System.Collections.IDictionary]) {
        if (-not $Action.Contains($Nome)) { return $Padrao }
        $v = $Action[$Nome]
        if ($null -eq $v) { return $Padrao }
        return $v
    }
    $p = $Action.PSObject.Properties[$Nome]
    if ($null -eq $p -or $null -eq $p.Value) { return $Padrao }
    $p.Value
}

function ConvertTo-TmxRegistryValue {
    # Converte o valor do catalogo (vindo do JSON) para o tipo que o registro espera.
    param($Value, [string] $Type)
    switch ($Type) {
        'Binary'      { return [byte[]]@($Value | ForEach-Object { [byte]$_ }) }
        'MultiString' { return [string[]]@($Value) }
        'QWord'       { return [int64]$Value }
        'DWord'       {
            $v = [int64]$Value
            # DWord acima de int32 (ex.: 0xFFFFFFFF) precisa ir como negativo para o provider
            if ($v -gt [int]::MaxValue) { $v = $v - 4294967296 }
            return [int]$v
        }
        default       { return [string]$Value }
    }
}

function Test-TmxRegistryValueEqual {
    param($Atual, $Esperado, [string] $Type)
    if ($null -eq $Atual) { return $false }
    switch ($Type) {
        'DWord'       { return (([int64]$Atual -band 0xFFFFFFFF) -eq ([int64]$Esperado -band 0xFFFFFFFF)) }
        'QWord'       { return ([int64]$Atual -eq [int64]$Esperado) }
        'Binary'      { return ((@($Atual) -join ',') -eq (@($Esperado) -join ',')) }
        'MultiString' { return ((@($Atual) -join "`n") -eq (@($Esperado) -join "`n")) }
        default       { return ("$Atual" -ieq "$Esperado") }
    }
}

function Test-TmxAppxJaRemovido {
    <#
    .SYNOPSIS
        Erro de remocao que na verdade significa "o pacote ja nao esta ai".
        Nesse caso o alvo foi atingido e a acao nao deve virar falha.
    #>
    param([string] $Mensagem)
    if (-not $Mensagem) { return $false }
    [bool]($Mensagem -match '(?i)n[aã]o foi possivel localizar|n[aã]o encontrad|not found|is not installed|n[aã]o est[aá] instalado|0x80073CF1')
}

function Get-TmxRegistryCurrentValue {
    # Valor bruto atual, ou $null se a chave/valor nao existir.
    param([Parameter(Mandatory)] [string] $Path, [Parameter(Mandatory)] [string] $Name)
    $prop = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue
    if ($null -ne $prop -and ($prop.PSObject.Properties.Name -contains $Name)) { return $prop.$Name }
    $null
}

function ConvertTo-TmxDisplayValue {
    # Texto estavel para antes/depois na UI e no preview.
    param($Value)
    if ($null -eq $Value) { return '<ausente>' }
    if ($Value -is [string]) { return $Value }
    if ($Value -is [System.Collections.IEnumerable]) { return (@($Value) -join ',') }
    "$Value"
}

# ---------------------------------------------------------------------------
# Wrappers de chamadas externas (mockaveis nos testes)
# ---------------------------------------------------------------------------

function Invoke-TmxPowercfg {
    param([Parameter(Mandatory)] [string[]] $Arguments)
    $out = & powercfg.exe @Arguments 2>&1
    [pscustomobject]@{ saida = (@($out) -join "`n"); codigo = $LASTEXITCODE }
}

function Get-TmxActivePowerScheme {
    $r = Invoke-TmxPowercfg @('/getactivescheme')
    $guid = [regex]::Match($r.saida, '[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}').Value
    $nome = [regex]::Match($r.saida, '\(([^)]+)\)').Groups[1].Value
    if (-not $guid) { return $null }
    [pscustomobject]@{ guid = $guid; nome = $nome }
}

function Get-TmxPowerSettingIndex {
    # Indice AC atual de uma configuracao. powercfg imprime AC antes de DC em qualquer idioma.
    param(
        [string] $Scheme = 'SCHEME_CURRENT',
        [Parameter(Mandatory)] [string] $Sub,
        [Parameter(Mandatory)] [string] $Setting
    )
    $r = Invoke-TmxPowercfg @('/query', $Scheme, $Sub, $Setting)
    if ($r.codigo -ne 0) { return $null }
    $ms = [regex]::Matches($r.saida, ':\s*0x([0-9a-fA-F]{1,8})\s*$', 'Multiline')
    if ($ms.Count -eq 0) { return $null }
    [Convert]::ToInt64($ms[0].Groups[1].Value, 16)
}

function Get-TmxServiceState {
    param([Parameter(Mandatory)] [string] $Nome)
    $s = Get-Service -Name $Nome -ErrorAction Stop
    [pscustomobject]@{ startType = "$($s.StartType)"; status = "$($s.Status)" }
}

function Set-TmxServiceState {
    param(
        [Parameter(Mandatory)] [string] $Nome,
        [Parameter(Mandatory)] [string] $StartType,
        [switch] $Parar,
        [switch] $Iniciar
    )
    Set-Service -Name $Nome -StartupType $StartType -ErrorAction Stop
    if ($Parar)   { Stop-Service  -Name $Nome -Force -ErrorAction Stop }
    if ($Iniciar) { Start-Service -Name $Nome -ErrorAction Stop }
}

function Get-TmxAdapterAdvanced {
    param([Parameter(Mandatory)] [string] $Name)
    Get-NetAdapterAdvancedProperty -Name $Name -ErrorAction Stop
}

function Set-TmxAdapterAdvanced {
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $Keyword,
        [Parameter(Mandatory)] [string] $Value
    )
    Set-NetAdapterAdvancedProperty -Name $Name -RegistryKeyword $Keyword -RegistryValue $Value -ErrorAction Stop
}

function Get-TmxScheduledTaskState {
    <#
    .SYNOPSIS
        'Enabled' ou 'Disabled' para uma tarefa agendada. Lanca se a tarefa nao existir.
    #>
    param(
        [Parameter(Mandatory)] [string] $Caminho,
        [Parameter(Mandatory)] [string] $Nome
    )
    $t = Get-ScheduledTask -TaskPath $Caminho -TaskName $Nome -ErrorAction Stop
    if ("$($t.State)" -eq 'Disabled') { return 'Disabled' }
    'Enabled'
}

function Set-TmxScheduledTaskState {
    param(
        [Parameter(Mandatory)] [string] $Caminho,
        [Parameter(Mandatory)] [string] $Nome,
        [Parameter(Mandatory)] [ValidateSet('Enabled', 'Disabled')] [string] $Estado
    )
    if ($Estado -eq 'Disabled') {
        Disable-ScheduledTask -TaskPath $Caminho -TaskName $Nome -ErrorAction Stop | Out-Null
    } else {
        Enable-ScheduledTask -TaskPath $Caminho -TaskName $Nome -ErrorAction Stop | Out-Null
    }
}

function Get-TmxAppx {
    param(
        [Parameter(Mandatory)] [string] $Pacote,
        [switch] $TodosUsuarios
    )
    if ($TodosUsuarios) { Get-AppxPackage -Name $Pacote -AllUsers -ErrorAction SilentlyContinue }
    else                { Get-AppxPackage -Name $Pacote -ErrorAction SilentlyContinue }
}

function Remove-TmxAppx {
    param(
        [Parameter(Mandatory)] [string] $PackageFullName,
        [switch] $TodosUsuarios
    )
    if ($TodosUsuarios) { Remove-AppxPackage -Package $PackageFullName -AllUsers -ErrorAction Stop }
    else                { Remove-AppxPackage -Package $PackageFullName -ErrorAction Stop }
}

function Remove-TmxProvisionedAppx {
    # Impede que o pacote volte para novos usuarios. Falhar aqui nao invalida a remocao.
    param([Parameter(Mandatory)] [string] $Nome)
    $prov = Get-AppxProvisionedPackage -Online -ErrorAction Stop | Where-Object { "$($_.DisplayName)" -like $Nome }
    foreach ($p in @($prov)) {
        Remove-AppxProvisionedPackage -Online -PackageName $p.PackageName -ErrorAction Stop | Out-Null
    }
}

function Install-TmxStoreApp {
    <#
    .SYNOPSIS
        Reinstala um pacote da Microsoft Store via winget. Retorna o codigo de saida.
    #>
    param([Parameter(Mandatory)] [string] $StoreId)
    & winget.exe install --id $StoreId --source msstore --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
    $LASTEXITCODE
}

function Get-TmxWindowsFeature {
    # 'Enabled' ou 'Disabled' para um recurso opcional do Windows.
    param([Parameter(Mandatory)] [string] $Nome)
    $f = Get-WindowsOptionalFeature -Online -FeatureName $Nome -ErrorAction Stop
    if ("$($f.State)" -eq 'Enabled') { return 'Enabled' }
    'Disabled'
}

function Enable-TmxWindowsFeature {
    param([Parameter(Mandatory)] [string] $Nome)
    Enable-WindowsOptionalFeature -Online -FeatureName $Nome -NoRestart -ErrorAction Stop | Out-Null
}

function Disable-TmxWindowsFeature {
    param([Parameter(Mandatory)] [string] $Nome)
    Disable-WindowsOptionalFeature -Online -FeatureName $Nome -NoRestart -ErrorAction Stop | Out-Null
}

function Invoke-TmxBcdedit {
    param([Parameter(Mandatory)] [string[]] $Arguments)
    $out = & bcdedit.exe @Arguments 2>&1
    [pscustomobject]@{ saida = (@($out) -join "`n"); codigo = $LASTEXITCODE }
}

function Get-TmxBcdValue {
    <#
    .SYNOPSIS
        Valor de uma opcao em {current}, ou $null se ausente. Nomes de opcao sao iguais em qualquer idioma.
    #>
    param([Parameter(Mandatory)] [string] $Opcao)
    $r = Invoke-TmxBcdedit @('/enum', '{current}')
    if ($r.codigo -ne 0) { throw "bcdedit /enum falhou ($($r.codigo)): $($r.saida)" }
    $m = [regex]::Match($r.saida, "(?im)^\s*$([regex]::Escape($Opcao))\s+(\S+)\s*$")
    if ($m.Success) { return $m.Groups[1].Value }
    $null
}

function Backup-TmxBcd {
    param([string] $OutputDir)
    if (-not $OutputDir) {
        $run = Get-TmxRun
        if (-not $run) { throw 'Nenhuma execucao ativa. Chame New-TmxRun primeiro.' }
        $OutputDir = $run.RunPath
    }
    $file = Join-Path $OutputDir 'bcd-backup.bcd'
    if (Test-Path -LiteralPath $file) { return $file }
    $r = Invoke-TmxBcdedit @('/export', $file)
    if ($r.codigo -ne 0) { throw "bcdedit /export falhou: $($r.saida)" }
    Write-TmxLog -Level INFO -Message 'BCD exportado' -Data @{ arquivo = $file }
    $file
}

function New-TmxCmdletRecord {
    <#
    .SYNOPSIS
        Helper para funcoes customizadas (`acao.tipo = 'funcao'`): registro tipo
        'cmdlet' com estado suficiente para Undo-Tmx<X> -Estado.
    #>
    param(
        [Parameter(Mandatory)] [string] $TweakId,
        [Parameter(Mandatory)] [string] $Funcao,
        [Parameter(Mandatory)] [string] $Alvo,
        [Parameter(Mandatory)] $Estado,
        $ValorAnterior,
        $ValorNovo
    )
    New-TmxStateRecord -TweakId $TweakId -Tipo 'cmdlet' -Alvo $Alvo `
        -Detalhe @{ funcao = $Funcao; estado = $Estado } `
        -ValorAnterior $ValorAnterior -ValorNovo $ValorNovo -ReversaoTipo 'cmdlet'
}

# ---------------------------------------------------------------------------
# Invoke-TmxAction: aplica UMA acao
# ---------------------------------------------------------------------------

function Invoke-TmxAction {
    <#
    .SYNOPSIS
        Aplica uma acao tipada do catalogo.
    .OUTPUTS
        { ok, detalhe, naoAplicavel, naoSuportado, registros }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Action,
        [Parameter(Mandatory)] $Tweak,
        $Profile
    )

    $out = [pscustomobject]@{ ok = $false; detalhe = $null; naoAplicavel = $false; naoSuportado = $false; registros = @() }
    $tweakId = "$($Tweak.id)"

    try {
        switch ("$($Action.tipo)") {

            'registry' {
                $remover = [bool](Get-TmxActionProp -Action $Action -Nome 'remove' -Padrao $false)
                $tipoVal = "$(Get-TmxActionProp -Action $Action -Nome 'valueType' -Padrao 'DWord')"

                if ($remover) {
                    $rec = Set-TmxRegistry -Path "$($Action.path)" -Name "$($Action.name)" -Remove -TweakId $tweakId -PassThru
                } else {
                    $val = ConvertTo-TmxRegistryValue -Value $Action.value -Type $tipoVal
                    $rec = Set-TmxRegistry -Path "$($Action.path)" -Name "$($Action.name)" -Value $val -Type $tipoVal -TweakId $tweakId -PassThru
                }

                $out.registros = @($rec)
                $out.ok = ("$($rec.status)" -eq 'aplicado')
                if ($out.ok) {
                    $out.detalhe = if ($remover) { "$($Action.name) removido" } else { "$($Action.name) = $(ConvertTo-TmxDisplayValue $Action.value)" }
                } else {
                    $out.detalhe = "$($Action.name): $($rec.erro)"
                }
            }

            'service' {
                $antes = Get-TmxServiceState -Nome "$($Action.nome)"
                $pararPedido = [bool](Get-TmxActionProp -Action $Action -Nome 'parar' -Padrao $false)
                $parar = ($pararPedido -and "$($antes.status)" -eq 'Running')

                $rec = New-TmxStateRecord -TweakId $tweakId -Tipo 'service' -Alvo "servico $($Action.nome)" `
                        -Detalhe @{ nome = "$($Action.nome)" } `
                        -ValorAnterior @{ startType = "$($antes.startType)"; status = "$($antes.status)" } `
                        -ValorNovo @{ startType = "$($Action.tipoInicio)"; status = $(if ($pararPedido) { 'Stopped' } else { "$($antes.status)" }) }
                $out.registros = @($rec)
                try {
                    Set-TmxServiceState -Nome "$($Action.nome)" -StartType "$($Action.tipoInicio)" -Parar:$parar
                    Complete-TmxStateRecord -Record $rec -Ok $true | Out-Null
                    $out.ok = $true
                    $out.detalhe = "$($Action.nome): $($antes.startType)/$($antes.status) -> $($Action.tipoInicio)"
                } catch {
                    Complete-TmxStateRecord -Record $rec -Ok $false -Erro $_.Exception.Message | Out-Null
                    $out.detalhe = $_.Exception.Message
                }
            }

            'scheduledTask' {
                $antes = Get-TmxScheduledTaskState -Caminho "$($Action.caminho)" -Nome "$($Action.nome)"
                $rec = New-TmxStateRecord -TweakId $tweakId -Tipo 'scheduledTask' -Alvo "tarefa $($Action.caminho)$($Action.nome)" `
                        -Detalhe @{ caminho = "$($Action.caminho)"; nome = "$($Action.nome)" } `
                        -ValorAnterior "$antes" -ValorNovo "$($Action.estado)"
                $out.registros = @($rec)
                try {
                    Set-TmxScheduledTaskState -Caminho "$($Action.caminho)" -Nome "$($Action.nome)" -Estado "$($Action.estado)"
                    Complete-TmxStateRecord -Record $rec -Ok $true | Out-Null
                    $out.ok = $true
                    $out.detalhe = "$($Action.nome): $antes -> $($Action.estado)"
                } catch {
                    Complete-TmxStateRecord -Record $rec -Ok $false -Erro $_.Exception.Message | Out-Null
                    $out.detalhe = $_.Exception.Message
                }
            }

            'appx' {
                $todos = [bool](Get-TmxActionProp -Action $Action -Nome 'todosUsuarios' -Padrao $false)
                $storeId = Get-TmxActionProp -Action $Action -Nome 'storeId' -Padrao $null
                # -AllUsers repete o mesmo PackageFullName uma vez por usuario:
                # sem deduplicar sairiam N registros e N remocoes do mesmo pacote.
                $pacotes = @(Get-TmxAppx -Pacote "$($Action.pacote)" -TodosUsuarios:$todos |
                             Where-Object { $_ -and "$($_.PackageFullName)" } |
                             Sort-Object PackageFullName -Unique)

                if ($pacotes.Count -eq 0) {
                    $out.ok = $true; $out.naoAplicavel = $true
                    $out.detalhe = "nenhum pacote '$($Action.pacote)' instalado"
                    break
                }

                $regs = New-Object 'System.Collections.Generic.List[object]'
                $falhas = @()
                foreach ($p in $pacotes) {
                    $full = "$($p.PackageFullName)"
                    $rec = New-TmxStateRecord -TweakId $tweakId -Tipo 'appx' -Alvo "appx $full" `
                            -Detalhe @{ packageFullName = $full; pacote = "$($Action.pacote)"; storeId = $storeId; todosUsuarios = $todos } `
                            -ValorAnterior $full -ValorNovo $null -ReversaoTipo 'reinstalar'
                    $regs.Add($rec)
                    try {
                        Remove-TmxAppx -PackageFullName $full -TodosUsuarios:$todos
                        if ($todos) {
                            try { Remove-TmxProvisionedAppx -Nome "$($Action.pacote)" }
                            catch { Write-TmxLog -Level WARN -Message "provisionamento de '$($Action.pacote)' nao removido: $($_.Exception.Message)" }
                        }
                        Complete-TmxStateRecord -Record $rec -Ok $true | Out-Null
                    } catch {
                        $msg = $_.Exception.Message
                        if (Test-TmxAppxJaRemovido -Mensagem $msg) {
                            # ja nao estava instalado: alvo atingido, nao e falha
                            Complete-TmxStateRecord -Record $rec -Ok $true | Out-Null
                            Write-TmxLog -Level WARN -Message "appx '$full' ja nao estava instalado: $msg"
                        } else {
                            Complete-TmxStateRecord -Record $rec -Ok $false -Erro $msg | Out-Null
                            $falhas += "$full : $msg"
                        }
                    }
                }
                $out.registros = $regs.ToArray()
                $out.ok = ($falhas.Count -eq 0)
                $out.detalhe = if ($out.ok) { "$($regs.Count) pacote(s) removido(s)" } else { $falhas -join '; ' }
            }

            'powercfg' {
                $ativo = Get-TmxActivePowerScheme
                if (-not $ativo) { $out.detalhe = 'esquema ativo nao identificado'; break }

                $antes = Get-TmxPowerSettingIndex -Scheme $ativo.guid -Sub "$($Action.subgrupo)" -Setting "$($Action.configuracao)"
                # A1: sem valor anterior nao ha reversao possivel -> nao aplica e nao registra.
                if ($null -eq $antes) {
                    $out.ok = $false
                    $out.detalhe = 'indice anterior ilegivel; nao aplicado'
                    break
                }

                $rec = New-TmxStateRecord -TweakId $tweakId -Tipo 'powercfg' -Alvo "$($Action.descricao)" `
                        -Detalhe @{ esquema = "$($ativo.guid)"; esquemaNome = "$($ativo.nome)"; subgrupo = "$($Action.subgrupo)"; configuracao = "$($Action.configuracao)" } `
                        -ValorAnterior $antes -ValorNovo ([int64]$Action.valor) -ExistiaAntes $true
                $out.registros = @($rec)

                $r1 = Invoke-TmxPowercfg @('/setacvalueindex', "$($ativo.guid)", "$($Action.subgrupo)", "$($Action.configuracao)", "$($Action.valor)")
                $r2 = $null
                if ($r1.codigo -eq 0) { $r2 = Invoke-TmxPowercfg @('/setactive', "$($ativo.guid)") }
                $ok = ($r1.codigo -eq 0 -and $null -ne $r2 -and $r2.codigo -eq 0)
                Complete-TmxStateRecord -Record $rec -Ok $ok -Erro $(if (-not $ok) { "powercfg: $($r1.saida) $($r2.saida)" }) | Out-Null
                $out.ok = $ok
                $out.detalhe = "indice AC $antes -> $($Action.valor) em '$($ativo.nome)'"
            }

            'netadapter' {
                $nome = $null
                if ($Profile) { $nome = $Profile.network.adaptadorAtivo.nome }
                if (-not $nome) { $out.detalhe = 'adaptador ativo desconhecido'; break }

                $todas = [bool](Get-TmxActionProp -Action $Action -Nome 'aplicarTodas' -Padrao $false)
                $props = @(Get-TmxAdapterAdvanced -Name "$nome")
                $alvos = @()
                foreach ($k in @($Action.chaves)) {
                    $p = $props | Where-Object { "$($_.RegistryKeyword)" -ieq "$k" } | Select-Object -First 1
                    if ($p) { $alvos += $p; if (-not $todas) { break } }
                }
                if ($alvos.Count -eq 0) {
                    $out.ok = $true; $out.naoAplicavel = $true
                    $out.detalhe = "driver de '$nome' nao expoe $(@($Action.chaves) -join '/')"
                    break
                }

                $regs = New-Object 'System.Collections.Generic.List[object]'
                $falhas = @()
                foreach ($p in $alvos) {
                    $antes = (@($p.RegistryValue) -join ',')
                    $rec = New-TmxStateRecord -TweakId $tweakId -Tipo 'netadapter' -Alvo "$nome :: $($p.DisplayName)" `
                            -Detalhe @{ adaptador = "$nome"; chave = "$($p.RegistryKeyword)"; nomeExibicao = "$($p.DisplayName)" } `
                            -ValorAnterior $antes -ValorNovo "$($Action.valorRegistro)"
                    $regs.Add($rec)
                    try {
                        Set-TmxAdapterAdvanced -Name "$nome" -Keyword "$($p.RegistryKeyword)" -Value "$($Action.valorRegistro)"
                        Complete-TmxStateRecord -Record $rec -Ok $true | Out-Null
                    } catch {
                        Complete-TmxStateRecord -Record $rec -Ok $false -Erro $_.Exception.Message | Out-Null
                        $falhas += "$($p.RegistryKeyword): $($_.Exception.Message)"
                    }
                }
                $out.registros = $regs.ToArray()
                $out.ok = ($falhas.Count -eq 0)
                $out.detalhe = if ($out.ok) { "$($regs.Count) propriedade(s) em '$nome'" } else { $falhas -join '; ' }
            }

            'bcdedit' {
                $opcao = "$($Action.opcao)"
                $antes = Get-TmxBcdValue -Opcao $opcao
                $existia = ($null -ne $antes)

                if ("$($Action.acao)" -eq 'deletevalue' -and -not $existia) {
                    $out.ok = $true; $out.naoAplicavel = $true
                    $out.detalhe = "'$opcao' ja nao esta definido"
                    break
                }

                Backup-TmxBcd | Out-Null

                $rec = New-TmxStateRecord -TweakId $tweakId -Tipo 'bcdedit' -Alvo "BCD {current} $opcao" `
                        -Detalhe @{ opcao = $opcao; acao = "$($Action.acao)" } -ValorAnterior $antes `
                        -ValorNovo $(if ("$($Action.acao)" -eq 'set') { "$($Action.valor)" } else { $null }) -ExistiaAntes $existia
                $out.registros = @($rec)

                $r = if ("$($Action.acao)" -eq 'set') { Invoke-TmxBcdedit @('/set', '{current}', $opcao, "$($Action.valor)") }
                     else { Invoke-TmxBcdedit @('/deletevalue', '{current}', $opcao) }
                $ok = ($r.codigo -eq 0)
                Complete-TmxStateRecord -Record $rec -Ok $ok -Erro $(if (-not $ok) { "bcdedit: $($r.saida)" }) | Out-Null

                $det = if ("$($Action.acao)" -eq 'set') { "$opcao : $(if ($existia) { $antes } else { '<ausente>' }) -> $($Action.valor)" }
                       else { "$opcao : $antes -> <removido>" }
                $out.ok = $ok
                $out.detalhe = if ($ok) { $det } else { "$det (falhou: $($r.saida))" }
            }

            'feature' {
                $antes = Get-TmxWindowsFeature -Nome "$($Action.nome)"
                if ("$antes" -ieq "$($Action.estado)") {
                    $out.ok = $true; $out.naoAplicavel = $true
                    $out.detalhe = "recurso $($Action.nome) ja esta $antes"
                    break
                }
                $rec = New-TmxStateRecord -TweakId $tweakId -Tipo 'feature' -Alvo "recurso $($Action.nome)" `
                        -Detalhe @{ nome = "$($Action.nome)" } -ValorAnterior "$antes" -ValorNovo "$($Action.estado)"
                $out.registros = @($rec)
                try {
                    if ("$($Action.estado)" -ieq 'Enabled') { Enable-TmxWindowsFeature -Nome "$($Action.nome)" }
                    else { Disable-TmxWindowsFeature -Nome "$($Action.nome)" }
                    Complete-TmxStateRecord -Record $rec -Ok $true | Out-Null
                    $out.ok = $true
                    $out.detalhe = "$($Action.nome): $antes -> $($Action.estado)"
                } catch {
                    Complete-TmxStateRecord -Record $rec -Ok $false -Erro $_.Exception.Message | Out-Null
                    $out.detalhe = $_.Exception.Message
                }
            }

            'funcao' {
                $fn = "$($Action.nome)"
                # Lista fechada por construcao: so Set-Tmx<Algo>. Nunca executa outra coisa.
                if ($fn -notmatch '^Set-Tmx[A-Za-z0-9]+$') {
                    $out.naoSuportado = $true
                    $out.detalhe = "nome de funcao nao permitido: '$fn'"
                    break
                }
                if (-not (Get-Command -Name $fn -CommandType Function -ErrorAction SilentlyContinue)) {
                    $out.naoSuportado = $true
                    $out.detalhe = "funcao '$fn' nao existe"
                    break
                }

                $r = & $fn -Tweak $Tweak -Profile $Profile -Parametros (Get-TmxActionProp -Action $Action -Nome 'parametros' -Padrao $null)
                $out.registros = @(Get-TmxFuncaoRecords -Resultado $r)
                $out.ok           = [bool](Get-TmxActionProp -Action $r -Nome 'ok' -Padrao $false)
                $out.naoAplicavel = [bool](Get-TmxActionProp -Action $r -Nome 'naoAplicavel' -Padrao $false)
                $out.naoSuportado = [bool](Get-TmxActionProp -Action $r -Nome 'naoSuportado' -Padrao $false)
                $out.detalhe      = "$(Get-TmxActionProp -Action $r -Nome 'detalhe' -Padrao '')"
            }

            default {
                $out.naoSuportado = $true
                $out.detalhe = "tipo de acao desconhecido: $($Action.tipo)"
            }
        }
    } catch {
        $out.ok = $false
        $out.detalhe = $_.Exception.Message
        Write-TmxLog -Level ERROR -Message "Acao '$($Action.tipo)' falhou em $tweakId : $($_.Exception.Message)"
    }

    $out
}

function Get-TmxFuncaoRecords {
    # Normaliza o que uma funcao customizada devolveu: 'registros' (lista) ou 'registro' (um).
    param($Resultado)
    if ($null -eq $Resultado) { return @() }
    $rr = Get-TmxActionProp -Action $Resultado -Nome 'registros' -Padrao $null
    if ($null -eq $rr) { $rr = Get-TmxActionProp -Action $Resultado -Nome 'registro' -Padrao $null }
    if ($null -eq $rr) { return @() }
    @($rr | Where-Object { $_ })
}

# ---------------------------------------------------------------------------
# Test-TmxAction / Test-TmxTweakApplied: verificacao
# ---------------------------------------------------------------------------

function Test-TmxAction {
    <#
    .SYNOPSIS
        Verifica se UMA acao ja esta no estado alvo.
    .OUTPUTS
        { aplicado ($true/$false/$null), atual, esperado, detalhe }. $null = nao verificavel.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Action,
        [Parameter(Mandatory)] $Tweak,
        $Profile
    )

    $out = [pscustomobject]@{ aplicado = $null; atual = $null; esperado = $null; detalhe = $null }

    try {
        switch ("$($Action.tipo)") {

            'registry' {
                $remover = [bool](Get-TmxActionProp -Action $Action -Nome 'remove' -Padrao $false)
                $tipoVal = "$(Get-TmxActionProp -Action $Action -Nome 'valueType' -Padrao 'DWord')"
                $val = Get-TmxRegistryCurrentValue -Path "$($Action.path)" -Name "$($Action.name)"

                $out.atual = ConvertTo-TmxDisplayValue $val
                if ($remover) {
                    $out.esperado = '<removido>'
                    $out.aplicado = ($null -eq $val)
                } else {
                    $out.esperado = ConvertTo-TmxDisplayValue $Action.value
                    $out.aplicado = [bool](Test-TmxRegistryValueEqual -Atual $val -Esperado $Action.value -Type $tipoVal)
                }
                $out.detalhe = "$($Action.name)=$($out.atual)"
            }

            'service' {
                $s = Get-TmxServiceState -Nome "$($Action.nome)"
                $pararPedido = [bool](Get-TmxActionProp -Action $Action -Nome 'parar' -Padrao $false)
                $out.atual    = "$($s.startType)/$($s.status)"
                $out.esperado = "$($Action.tipoInicio)$(if ($pararPedido) { '/Stopped' })"
                $ok = ("$($s.startType)" -eq "$($Action.tipoInicio)")
                if ($pararPedido) { $ok = ($ok -and "$($s.status)" -eq 'Stopped') }
                $out.aplicado = $ok
                $out.detalhe  = "servico $($Action.nome): $($out.atual)"
            }

            'scheduledTask' {
                $estado = Get-TmxScheduledTaskState -Caminho "$($Action.caminho)" -Nome "$($Action.nome)"
                $out.atual    = "$estado"
                $out.esperado = "$($Action.estado)"
                $out.aplicado = ("$estado" -ieq "$($Action.estado)")
                $out.detalhe  = "tarefa $($Action.nome): $estado"
            }

            'appx' {
                $todos = [bool](Get-TmxActionProp -Action $Action -Nome 'todosUsuarios' -Padrao $false)
                $pacotes = @(Get-TmxAppx -Pacote "$($Action.pacote)" -TodosUsuarios:$todos)
                $out.atual    = if ($pacotes.Count -eq 0) { '<ausente>' } else { (@($pacotes | ForEach-Object { "$($_.PackageFullName)" }) -join '; ') }
                $out.esperado = "<removido: $($Action.pacote)>"
                $out.aplicado = ($pacotes.Count -eq 0)
                $out.detalhe  = "$($Action.pacote): $($pacotes.Count) instalado(s)"
            }

            'powercfg' {
                $idx = Get-TmxPowerSettingIndex -Sub "$($Action.subgrupo)" -Setting "$($Action.configuracao)"
                $out.atual    = $idx
                $out.esperado = [int64]$Action.valor
                if ($null -eq $idx) {
                    $out.detalhe = 'nao foi possivel ler o indice atual'
                } else {
                    $out.aplicado = ([int64]$idx -eq [int64]$Action.valor)
                    $out.detalhe  = "indice AC atual: $idx"
                }
            }

            'netadapter' {
                $nome = $null
                if ($Profile) { $nome = $Profile.network.adaptadorAtivo.nome }
                if (-not $nome) { $out.detalhe = 'adaptador ativo desconhecido'; break }

                $todas = [bool](Get-TmxActionProp -Action $Action -Nome 'aplicarTodas' -Padrao $false)
                $props = @(Get-TmxAdapterAdvanced -Name "$nome")
                $alvos = @()
                foreach ($k in @($Action.chaves)) {
                    $p = $props | Where-Object { "$($_.RegistryKeyword)" -ieq "$k" } | Select-Object -First 1
                    if ($p) { $alvos += $p; if (-not $todas) { break } }
                }
                if ($alvos.Count -eq 0) { $out.detalhe = "driver nao expoe: $(@($Action.chaves) -join ', ')"; break }

                $vals = @($alvos | ForEach-Object { "$($_.RegistryKeyword)=$(@($_.RegistryValue) -join ',')" })
                $out.atual    = ($vals -join '; ')
                $out.esperado = "$($Action.valorRegistro)"
                $out.aplicado = -not [bool](@($alvos | Where-Object { (@($_.RegistryValue) -join ',') -ne "$($Action.valorRegistro)" }).Count)
                $out.detalhe  = $out.atual
            }

            'bcdedit' {
                $atual = Get-TmxBcdValue -Opcao "$($Action.opcao)"
                $out.atual = $atual
                if ("$($Action.acao)" -eq 'set') {
                    $out.esperado = "$($Action.valor)"
                    $out.aplicado = ($null -ne $atual -and "$atual" -ieq "$($Action.valor)")
                } else {
                    $out.esperado = '<removido>'
                    $out.aplicado = ($null -eq $atual)
                }
                $out.detalhe = "$($Action.opcao) = $(if ($null -eq $atual) { '<ausente>' } else { $atual })"
            }

            'feature' {
                $estado = Get-TmxWindowsFeature -Nome "$($Action.nome)"
                $out.atual    = "$estado"
                $out.esperado = "$($Action.estado)"
                $out.aplicado = ("$estado" -ieq "$($Action.estado)")
                $out.detalhe  = "recurso $($Action.nome): $estado"
            }

            'funcao' {
                $fn = "$($Action.nome)"
                if ($fn -notmatch '^Set-Tmx[A-Za-z0-9]+$') { $out.detalhe = "nome de funcao nao permitido: '$fn'"; break }
                $teste = $fn -replace '^Set-', 'Test-'
                if (-not (Get-Command -Name $teste -CommandType Function -ErrorAction SilentlyContinue)) {
                    $out.detalhe = "sem funcao de verificacao ($teste)"
                    break
                }
                $r = & $teste -Tweak $Tweak -Profile $Profile
                if ($r -is [bool]) {
                    $out.aplicado = $r
                } else {
                    $out.aplicado = Get-TmxActionProp -Action $r -Nome 'aplicado' -Padrao $null
                    $out.atual    = Get-TmxActionProp -Action $r -Nome 'atual' -Padrao $null
                    $out.esperado = Get-TmxActionProp -Action $r -Nome 'esperado' -Padrao $null
                    $out.detalhe  = Get-TmxActionProp -Action $r -Nome 'detalhe' -Padrao $null
                }
            }

            default { $out.detalhe = "tipo de acao desconhecido: $($Action.tipo)" }
        }
    } catch {
        $out.aplicado = $null
        $out.detalhe  = "erro ao verificar: $($_.Exception.Message)"
    }

    $out
}

function Test-TmxTweakApplied {
    <#
    .SYNOPSIS
        Agrega Test-TmxAction de todas as acoes do tweak.
        $true so quando TODAS estao aplicadas; $false se alguma nao esta; $null quando ha duvida.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Tweak,
        $Profile
    )

    $out = [pscustomobject]@{ aplicado = $null; atual = $null; esperado = $null; detalhe = $null }
    $acoes = @($Tweak.acoes)
    if ($acoes.Count -eq 0) {
        $out.detalhe = 'tweak sem acoes'
        return $out
    }

    $res = New-Object 'System.Collections.Generic.List[object]'
    foreach ($a in $acoes) { $res.Add((Test-TmxAction -Action $a -Tweak $Tweak -Profile $Profile)) }
    $arr = $res.ToArray()

    $temFalso = @($arr | Where-Object { $_.aplicado -eq $false }).Count -gt 0
    $temNulo  = @($arr | Where-Object { $null -eq $_.aplicado }).Count -gt 0

    if ($temFalso)     { $out.aplicado = $false }
    elseif ($temNulo)  { $out.aplicado = $null }
    else               { $out.aplicado = $true }

    $out.atual    = (@($arr | ForEach-Object { "$($_.atual)" }) -join '; ')
    $out.esperado = (@($arr | ForEach-Object { "$($_.esperado)" }) -join '; ')
    $out.detalhe  = (@($arr | ForEach-Object { "$($_.detalhe)" } | Where-Object { $_ }) -join '; ')
    $out
}

# ---------------------------------------------------------------------------
# Reversao dos tipos de registro introduzidos aqui
# (powercfg/service/netadapter/cmdlet/registry ficam em Core/Rollback.ps1)
# ---------------------------------------------------------------------------

function Undo-TmxScheduledTaskRecord {
    param([Parameter(Mandatory)] $Record)
    $ant = "$($Record.valorAnterior)"
    if (-not $ant) { throw 'estado anterior da tarefa desconhecido' }
    Set-TmxScheduledTaskState -Caminho "$($Record.detalhe.caminho)" -Nome "$($Record.detalhe.nome)" -Estado $ant
    "tarefa $($Record.detalhe.nome) restaurada para $ant"
}

function Undo-TmxAppxRecord {
    param([Parameter(Mandatory)] $Record)
    $pacote  = "$($Record.detalhe.pacote)"
    $storeId = "$($Record.detalhe.storeId)"
    if (-not $storeId) { throw "sem storeId: reinstale '$pacote' pela Microsoft Store" }
    $codigo = Install-TmxStoreApp -StoreId $storeId
    if ($codigo -ne 0) { throw "winget retornou $codigo ao reinstalar '$storeId'" }
    "pacote '$pacote' reinstalado pela Store ($storeId)"
}

function Undo-TmxFeatureRecord {
    param([Parameter(Mandatory)] $Record)
    $ant  = "$($Record.valorAnterior)"
    $nome = "$($Record.detalhe.nome)"
    if ($ant -ieq 'Enabled')       { Enable-TmxWindowsFeature  -Nome $nome }
    elseif ($ant -ieq 'Disabled')  { Disable-TmxWindowsFeature -Nome $nome }
    else { throw 'estado anterior do recurso desconhecido' }
    "recurso $nome restaurado para $ant"
}

function Undo-TmxBcdeditRecord {
    param([Parameter(Mandatory)] $Record)
    $opcao = "$($Record.detalhe.opcao)"
    if ($Record.existiaAntes -and $null -ne $Record.valorAnterior) {
        $r = Invoke-TmxBcdedit @('/set', '{current}', $opcao, "$($Record.valorAnterior)")
        if ($r.codigo -ne 0) { throw "bcdedit /set $opcao falhou: $($r.saida)" }
        return "$opcao restaurado para $($Record.valorAnterior)"
    }
    $r = Invoke-TmxBcdedit @('/deletevalue', '{current}', $opcao)
    if ($r.codigo -ne 0 -and $r.saida -notmatch '(?i)nao foi possivel localizar|could not be found|elemento nao') {
        throw "bcdedit /deletevalue $opcao falhou: $($r.saida)"
    }
    "$opcao removido (nao existia antes)"
}
