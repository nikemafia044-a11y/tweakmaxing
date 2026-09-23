# TweakMaxing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-optimized:subagent-driven-development (recommended) or superpowers-optimized:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Construir o TweakMaxing — utilitário Windows com paridade de funcionalidades com o WinUtil, GUI WPF+WebView2, lançado por `irm | iex`, mantendo a filosofia do CS2Tuner (ponto de restauração bloqueante, backup + desfazer por ação, selo de evidência, prévia antes de aplicar).

**Architecture:** PowerShell 5.1; `src/Core` portado do CS2Tuner com as correções da auditoria; `src/Engine` aplica **ações** tipadas (registry/service/scheduledTask/appx/powercfg/netadapter/bcdedit/feature/funcao) gravando `state.json` antes de cada escrita; GUI = janela WPF hospedando WebView2 com HTML/JS vanilla e ponte JSON (ações fechadas, nunca código); trabalho pesado em runspace pool; `Compile.ps1` gera um único `TweakMaxing.ps1` com JSONs, web e DLLs do SDK WebView2 embutidos em base64.

**Tech Stack:** Windows PowerShell 5.1 (também roda em pwsh 7), WPF, Microsoft.Web.WebView2 1.0.3240.44 (BSD-3), HTML/CSS/JS sem build, Pester ≥ 5, agent-browser 0.38 (CDP), winget/choco, DISM, git + gh (portátil em `tools/gh/bin/gh.exe`).

**Assumptions:**
- Assume o spike validado em 2026-09-22: `Add-Type -Path` das DLLs net462 do WebView2 funciona em PS 5.1 STA, `SetVirtualHostNameToFolderMapping` serve a UI, `WebMessageReceived`/`PostWebMessageAsJson` fazem a ponte e `WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS=--remote-debugging-port=N` expõe CDP para `agent-browser connect N`. NÃO funciona em host `ConstrainedLanguage` (checado no start).
- Assume que `$MyInvocation.MyCommand.ScriptBlock.ToString()` devolve o corpo do script sob `iex` (validado). Se o texto não contiver o marcador `#TMX-COMPILED`, o start rebaixa a URL fixa da versão.
- Assume `reference/winutil` clonado (commit de 2026-09-22; 67 tweaks, 33 features, 236 apps, 34 appx, 8 DNS). O conversor lê esses arquivos; NÃO funciona sem o clone (README documenta o `git clone`).
- Assume testes sem elevação usando `HKCU:\Software\TweakMaxing_Tests` e `TWEAKMAXING_HOME`; nada no CI toca HKLM, `Checkpoint-Computer`, winget ou DISM reais (mocks).
- Assume caminhos: projeto em `C:\Users\fantasy\Desktop\TweakMaxing`, CS2Tuner em `C:\Users\fantasy\Desktop\tweak` (fonte da porta, somente leitura).
- Assume PowerShell 5.1: sem `&&`, sem ternário, `@()` sobre List genérica vazia falha (usar `.ToArray()`), DWord > int32 vira negativo, `[array]::IndexOf` genérico falha com object[]+string (usar hashtable), `Read-Host` proibido fora de UI.

---

## Estrutura de arquivos

| Caminho | Responsabilidade |
|---|---|
| `src/Core/Guard.ps1` | Elevação, build, disco, reboot pendente, chassi, VM (porta) |
| `src/Core/Logger.ps1` | Transcript + `events.jsonl` (porta; ERROR vira Warning) |
| `src/Core/Backup.ps1` | Run, `state.json`, exports `.reg`/`.pow`/adaptadores (porta) |
| `src/Core/Registry.ps1` | `Set-TmxRegistry` com captura + `chaveRaizCriada` (porta + M2) |
| `src/Core/RestorePoint.ps1` | Ponto verificado, throttle, `-ConfirmSkip` callback (porta + M4 + B2) |
| `src/Core/Rollback.ps1` | `Undo-TweakMaxing` com `-TweakId`, persiste `revertido`, `-Quiet` (porta + A2 + M5 + B1) |
| `src/Engine/Condition.ps1` | Parser/avaliador de condições (porta) |
| `src/Engine/Catalog.ps1` | `Get-TmxCatalog`, `Test-TmxCatalog` (schema por ação) |
| `src/Engine/Profile.ps1` | `Get-TmxProfile` reduzido (os/network/storage/memory/gpu) |
| `src/Engine/Plan.ps1` | `Resolve-TmxPlan`, `Set-TmxPlanSelection`, `Set-TmxPlanConsent`, presets |
| `src/Engine/Actions.ps1` | `Invoke-TmxAction`/`Test-TmxAction` por tipo + wrappers mockáveis |
| `src/Engine/Apply.ps1` | `Invoke-TmxPlan` (-WhatIf), `Invoke-TmxBackupForTweak` (M1 bloqueante) |
| `src/Engine/Preview.ps1` | `Get-TmxPlanPreview` (antes→depois) |
| `src/functions/tweaks/*.ps1` | Funções nomeadas `Set-/Undo-/Test-Tmx*` (ex-InvokeScript do WinUtil + cmdlets do CS2Tuner) |
| `src/functions/install/*.ps1` | winget/choco: detecção, bootstrap, instalar/desinstalar/atualizar, instalados |
| `src/functions/features/*.ps1` | DISM (`feature`), correções, painéis, DNS |
| `src/functions/session/*.ps1` | `Start-TmxSession` (run + ponto de restauração), status |
| `src/functions/bridge/*.ps1` | `Invoke-TmxBridgeRequest` (dispatcher), ações, `Start-TmxJob` (pool), eventos |
| `src/functions/ui/*.ps1` | `Start-TmxUserInterface` (WPF + WebView2), diálogos WPF |
| `src/web/index.html`, `app.css`, `app.js` | UI |
| `src/config/*.json`, `src/config/overlay/tweaks.overrides.json` | Catálogos |
| `scripts/start.ps1`, `scripts/main.ps1` | Bootstrap e loop principal |
| `tools/Convert-WinUtilCatalog.ps1` | WinUtil → nossos JSONs |
| `tools/Convert-CS2TunerCatalog.ps1` | CS2Tuner → categoria Jogos |
| `tools/Get-WebView2Sdk.ps1` | Baixa/verifica/extrai o SDK em `packages/` |
| `tools/Publish-Release.ps1` | Compila, hash, tag, release |
| `Compile.ps1`, `Start-TmxDev.ps1` | Build único / execução a partir do fonte |
| `tests/*.Tests.ps1`, `tests/gui/*.ps1`, `tests/Invoke-Tests.ps1` | Pester + agent-browser |

Convenções de código: prefixo `Tmx`; objetos de retorno `[pscustomobject]`; mensagens ao usuário em PT-BR sem acento nos logs (compatibilidade de console) e com acento na UI; nunca `Write-Host` fora de `scripts/` e `functions/ui`; toda função com efeito colateral chamada só pelo Engine ou por `Undo-`.

---

## Fase 1 — Repositório e licença

### Task 1: Scaffold do repositório, LICENSE e notices

**Files:**
- Create: `.gitignore`, `LICENSE`, `THIRD-PARTY-NOTICES.md`, `README.md`, `VERSION`, `tests/Invoke-Tests.ps1`, `docs/testes-manuais.md`
- Create (vazios com cabeçalho): `src/Core/`, `src/Engine/`, `src/functions/{tweaks,install,features,session,bridge,ui}/`, `src/config/overlay/`, `src/web/`, `scripts/`, `tools/`, `tests/gui/`

**Security flag:** `none`

- [x] **Step 1: git init e .gitignore**

```bash
cd /c/Users/fantasy/Desktop/TweakMaxing && git init -b main
```

`.gitignore`:
```
reference/
packages/
tools/gh/
tools/gh.zip
TweakMaxing.ps1
SHA256SUMS.txt
runs/
*.log
TestResults*.xml
tests/gui/out/
.claude/settings.local.json
```

- [x] **Step 2: LICENSE (MIT, obra derivada)**

```
MIT License

Copyright (c) 2026 TweakMaxing contributors

Portions derived from WinUtil (https://github.com/ChrisTitusTech/winutil)
Copyright (c) 2022 CT Tech Group LLC — licensed under the MIT License.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [x] **Step 3: THIRD-PARTY-NOTICES.md** — três seções: WinUtil (MIT, texto integral de `reference/winutil/LICENSE`, o que foi derivado: catálogos `config/*.json`, arquitetura de compilação e runspaces, lógica de winget/choco/DISM/fixes/updates/MicroWin); Microsoft.Web.WebView2 1.0.3240.44 (BSD-3, texto integral do `LICENSE.txt` do NuGet; DLLs embutidas: `Microsoft.Web.WebView2.Core.dll`, `Microsoft.Web.WebView2.Wpf.dll`, `WebView2Loader.dll` x64); CS2Tuner (mesmo autor, Core/Engine portados).

- [x] **Step 4: README.md inicial** com: o que é, aviso "obra derivada do WinUtil (MIT), com atribuição a Chris Titus Tech; não afiliado", filosofia (4 pontos), comando de clone da referência (`git clone https://github.com/ChrisTitusTech/winutil reference/winutil`), como rodar do fonte (`.\Start-TmxDev.ps1`), como compilar, como testar. Seção "Lançador" fica com o texto `(publicado na fase 10)`.

- [x] **Step 5: VERSION** = `0.1.0`. `tests/Invoke-Tests.ps1` = cópia de `..\tweak\tests\Invoke-Tests.ps1` (mesmos parâmetros `-Path -Tag -Verbosity`). `docs/testes-manuais.md` com o roteiro dos itens não automatizáveis: ponto de restauração real, winget real, DISM real, MicroWin (checklist com "esperado"/"observado").

- [x] **Step 6: Commit**

```bash
git add -A && git commit -m "chore: scaffold, MIT license with WinUtil attribution, third-party notices"
```

---

## Fase 2 — Core portado + correções da auditoria

### Task 2: Portar Core e testes do CS2Tuner com renomeação

**Files:**
- Create: `src/Core/{Guard,Logger,Backup,Registry,RestorePoint,Rollback}.ps1`, `src/TweakMaxing.psd1`, `src/TweakMaxing.psm1`, `tests/Core.Guard.Tests.ps1`, `tests/Core.Registry.Tests.ps1`, `tests/Core.RestorePoint.Tests.ps1`, `tests/Core.Rollback.Tests.ps1`, `tests/_Helpers.ps1`

**Security flag:** `security` (escrita em registro, elevação)

- [x] **Step 1: Copiar e renomear**

```powershell
$src = 'C:\Users\fantasy\Desktop\tweak'; $dst = 'C:\Users\fantasy\Desktop\TweakMaxing'
foreach ($f in 'Guard','Logger','Backup','Registry','RestorePoint','Rollback') {
  $t = Get-Content "$src\Core\$f.ps1" -Raw -Encoding UTF8
  $t = $t -replace '-Tuner', '-Tmx' -replace '\$script:Tuner', '$script:Tmx' -replace 'Undo-CS2Tuner', 'Undo-TweakMaxing' `
          -replace 'CS2TUNER_HOME', 'TWEAKMAXING_HOME' -replace "'CS2Tuner'", "'TweakMaxing'" -replace 'CS2Tuner', 'TweakMaxing' -replace 'Tuner', 'Tmx'
  Set-Content "$dst\src\Core\$f.ps1" $t -Encoding UTF8
}
```
Conferir depois com `grep -rn "Tuner\|CS2" src/Core` → zero ocorrências. Mesma transformação para os 4 arquivos de teste + `tests/fixtures/` não é necessária (fixtures ficam na Task 5). Chave de teste: `HKCU:\Software\TweakMaxing_Tests`.

- [x] **Step 2: `src/TweakMaxing.psm1`** carrega na ordem: Core (Logger, Backup, Registry, Rollback, RestorePoint, Guard), Engine (Condition, Profile, Catalog, Plan, Actions, Apply, Preview), `functions/**/*.ps1` (ordem alfabética por pasta: tweaks, install, features, session, bridge, ui). `src/TweakMaxing.psd1` com `FunctionsToExport = '*'` (módulo interno; o artefato compilado não usa módulo).

- [x] **Step 3: `tests/_Helpers.ps1`**: `Import-TmxTestModule` (Import-Module `src/TweakMaxing.psd1 -Force`), `New-TmxTestHome` (pasta temp + `$env:TWEAKMAXING_HOME`), `Remove-TmxTestKey`. Cada arquivo de teste começa com `. "$PSScriptRoot\_Helpers.ps1"`.

- [x] **Step 4: Rodar** `.\tests\Invoke-Tests.ps1 -Tag Registry,Rollback,RestorePoint,Guard` → todos os testes portados passam (esperado: 7 + 12 + 17 + 13 = 49; o teste "Start-CS2Tuner.ps1 (processo filho)" é removido — não há orquestrador de console).

- [x] **Step 5: Commit** `feat(core): port CS2Tuner Core with Tmx prefix and tests`

### Task 3: Correções A1, A2, M1, M2, M4, M5, B1, B2, B4 no Core

**Files:**
- Modify: `src/Core/Registry.ps1`, `src/Core/Rollback.ps1`, `src/Core/RestorePoint.ps1`, `src/Core/Logger.ps1`, `src/Core/Backup.ps1`
- Test: `tests/Core.Rollback.Tests.ps1`, `tests/Core.Registry.Tests.ps1`, `tests/Core.RestorePoint.Tests.ps1`

**Security flag:** `security`

**Does NOT cover:** A1 (valor anterior ilegível em powercfg/TRIM) é tratado nos handlers da Task 4, não aqui.

- [x] **Step 1: Testes que falham (Rollback)**

```powershell
It 'M2: undo remove os niveis intermediarios criados, ate o primeiro ancestral que existia' {
    $base = 'HKCU:\Software\TweakMaxing_Tests\M2'
    New-Item $base -Force | Out-Null
    Set-TmxRegistry -Path "$base\A\B\C" -Name V -Value 1 -Type DWord -TweakId 'TST-M2' | Out-Null
    (Get-TmxState)[-1].detalhe.chaveRaizCriada | Should -Be "$base\A"
    Undo-TweakMaxing -Latest -Quiet | Out-Null
    Test-Path "$base\A" | Should -BeFalse
    Test-Path $base | Should -BeTrue
}
It 'A2: registros revertidos ficam marcados e nao sao revertidos de novo' {
    # aplica, reverte, muda o valor na mao, reverte de novo -> valor manual preservado
    Set-TmxRegistry -Path $k -Name V -Value 1 -Type DWord -TweakId 'TST-A2' | Out-Null
    Undo-TweakMaxing -Latest -Quiet | Out-Null
    (Import-TmxState -StatePath $state)[-1].status | Should -Be 'revertido'
    New-ItemProperty -LiteralPath $k -Name V -Value 77 -PropertyType DWord -Force | Out-Null
    $r = Undo-TweakMaxing -Latest -Quiet
    $r.total | Should -Be 0
    (Get-ItemProperty $k).V | Should -Be 77
}
It 'A2: -TweakId reverte so os registros daquele tweak' { ... aplica TST-X e TST-Y; Undo -TweakId TST-X; X restaurado, Y intacto; state marca so X ... }
It 'B1: existiaAntes com tipoAnterior nulo vira falha explicita, nao grava DWord' { ... registro forjado em state.json com tipoAnterior=$null e valorAnterior='abc' -> resultado 'falha' e detalhe contem '.reg' ... }
It 'M5: -Quiet nao escreve no host' { ... Mock Write-Host {}; Undo -Quiet; Should -Invoke Write-Host -Times 0 ... }
```

Registry: `It 'M2: registra chaveRaizCriada como o primeiro ancestral inexistente'`. RestorePoint: `It 'M4: pular exige callback -ConfirmSkip; sem callback e sem frase -> exitCode 2'`, `It 'B2: New-TmxRestorePoint -WhatIf nao zera throttle nem chama checkpoint'` (Mock `Invoke-TmxCheckpoint`).

- [x] **Step 2: Implementar**

`Registry.ps1` — antes da escrita:
```powershell
$chaveRaizCriada = $null
if (-not $keyExisted) {
    $cur = $Path
    while ($cur -and -not (Test-Path -LiteralPath $cur)) { $chaveRaizCriada = $cur; $cur = Split-Path $cur -Parent }
}
# detalhe += chaveRaizCriada
```
`Rollback.ps1` `removerChaveCriada`: após remover o valor, `$raiz = if ($Record.detalhe.chaveRaizCriada) { $Record.detalhe.chaveRaizCriada } else { $path }`; remover `$path` se vazia, depois subir de `$path` até `$raiz` removendo cada nível enquanto vazio (sem valores e sem subchaves); parar no primeiro não-vazio.

`Rollback.ps1` `Undo-TweakMaxing`: parâmetro `[string] $TweakId`, `[switch] $Quiet`; filtrar `status -in aplicado,falha,aplicando` **e** `(-not $TweakId -or $_.tweakId -ieq $TweakId)`; após cada item com resultado `revertido`, setar `$rec.status='revertido'; $rec.revertidoEm=(Get-Date).ToString('o')`; ao final gravar o `state.json` de volta (`Save-TmxStateFile -StatePath -Registros`, nova função em `Backup.ps1` que reescreve o arquivo a partir de uma lista, sem depender do run em memória). `restaurarValorAnterior` com `tipoAnterior` nulo → `throw 'tipo anterior desconhecido; restaure pelo .reg em regbackup\'`. `Write-TmxRollbackReport` só se `-not $Quiet`.

`RestorePoint.ps1`: `Invoke-TmxRestorePointStage -ConfirmSkip [scriptblock]` (retorna bool); `Confirm-TmxSkipRestorePoint` sai do Core (vai para `functions/ui/Dialogs.ps1` na Task 8). Sem callback e com `-SkipRestorePoint` → `exitCode 2`, mensagem "confirmacao de pulo nao disponivel". `New-TmxRestorePoint` ganha `[CmdletBinding(SupportsShouldProcess)]` e `if (-not $PSCmdlet.ShouldProcess($Drive,'criar ponto de restauracao')) { $r.etapa='whatif'; return $r }` antes da etapa 3.

`Logger.ps1`: nível ERROR → `Write-Warning "[ERRO] $Message"` (B4).

- [x] **Step 3: Rodar** `.\tests\Invoke-Tests.ps1 -Tag Registry,Rollback,RestorePoint` → PASS (49 + 8 novos).
- [x] **Step 4: Commit** `fix(core): persist rollback results, undo by tweak, remove created parent keys, WhatIf on restore point`

---

## Fase 3 — Catálogo, motor de ações, conversor

### Task 4: Engine de ações (porta do CS2Tuner em granularidade de ação)

**Files:**
- Create: `src/Engine/Condition.ps1` (cópia renomeada de `Engine/Condition.ps1`), `src/Engine/Actions.ps1`, `src/Engine/Apply.ps1`, `src/Engine/Preview.ps1`, `tests/Engine.Condition.Tests.ps1` (porta dos 36 testes), `tests/Engine.Actions.Tests.ps1`, `tests/Engine.Preview.Tests.ps1`

**Security flag:** `security`

**Does NOT cover:** `appx` real, `scheduledTask` real, `feature` real (mockados); a instalação de apps (não passa pelo engine).

- [x] **Step 1: Testes** (`Engine.Actions.Tests.ps1`, registro real em HKCU, resto mockado):

```powershell
Describe 'Invoke-TmxAction registry' { It 'grava, registra antes e reverte' {...} }
Describe 'Invoke-TmxAction service (mock Get/Set-TmxServiceState)' { It 'captura startType/status e reverte' {...} }
Describe 'Invoke-TmxAction scheduledTask (mock Get/Set-TmxScheduledTaskState)' { It 'captura Enabled/Disabled e reverte' {...} }
Describe 'Invoke-TmxAction appx (mock Get/Remove-TmxAppx, Install-TmxStoreApp)' {
  It 'registra PackageFullName e storeId; undo reinstala via storeId' {...}
  It 'sem storeId: undo resulta em falha com instrucao' {...} }
Describe 'Invoke-TmxAction powercfg' { It 'A1: indice anterior ilegivel -> nao aplica, ok=false' {...}; It 'le, grava, reverte' {...} }
Describe 'Invoke-TmxAction feature (mock Get/Enable/Disable-TmxWindowsFeature)' { It 'captura estado e reverte' {...} }
Describe 'Invoke-TmxAction funcao' {
  It 'chama Set-TmxX -Tweak -Profile -Parametros e registra cmdlet' {...}
  It 'funcao inexistente -> naoSuportado' {...}
  It 'nome fora de Set-Tmx* -> naoSuportado (nunca executa)' {...} }
Describe 'Invoke-TmxPlan' { It 'aplica selecionados, pula ja aplicados, exige consentimento, -WhatIf nao grava' {...}; It 'M1: export .reg falha em chave existente -> item falha sem escrever' {...} }
```

- [x] **Step 2: Implementar `Actions.ps1`** — contrato `Invoke-TmxAction -Action $a -Tweak $t -Profile $p` → `{ ok, detalhe, naoAplicavel, naoSuportado, registros }`; `Test-TmxAction` → `{ aplicado, atual, esperado, detalhe }`. Tipos e wrappers mockáveis:

| tipo | wrappers | registro (tipo / valorAnterior / reversao) |
|---|---|---|
| `registry` | `Set-TmxRegistry` | `registry` (já faz) |
| `service` | `Get-TmxServiceState`, `Set-TmxServiceState` | `service` / `{startType,status}` / `restaurarValorAnterior` |
| `scheduledTask` | `Get-TmxScheduledTaskState` (Get-ScheduledTask → `State`), `Set-TmxScheduledTaskState` (Enable/Disable-ScheduledTask) | `scheduledTask` / `'Ready'|'Disabled'` |
| `appx` | `Get-TmxAppx` (Get-AppxPackage -AllUsers), `Remove-TmxAppx`, `Remove-TmxProvisionedAppx`, `Install-TmxStoreApp -StoreId` (winget msstore) | `appx` / `{packageFullName, storeId}` / `reinstalar` |
| `powercfg` | `Invoke-TmxPowercfg`, `Get-TmxPowerSettingIndex` | `powercfg` (A1: `$null` → `ok=$false`, sem registro) |
| `netadapter` | porta | `netadapter` |
| `bcdedit` | porta de `Tweaks/Boot.ps1` | `bcdedit` |
| `feature` | `Get-TmxWindowsFeature` (Get-WindowsOptionalFeature -Online), `Enable-TmxWindowsFeature`, `Disable-TmxWindowsFeature` (`-NoRestart`) | `feature` / `'Enabled'|'Disabled'` |
| `funcao` | valida `^Set-Tmx[A-Za-z0-9]+$` e `Get-Command`; chama `& $nome -Tweak $t -Profile $p -Parametros $a.parametros` | o que a função registrar (`New-TmxCmdletRecord`) |

`Undo-TweakMaxing` (Rollback.ps1) ganha `scheduledTask`, `appx` (`reinstalar`) e `feature` no switch, com `Undo-Tmx*Record` em `Actions.ps1`.

`Apply.ps1`: `Invoke-TmxPlan -Plan -Profile [-WhatIf]` itera `$item.tweak.acoes`; por tweak: consentimento → `Test-TmxTweakApplied` (todas as ações `aplicado=$true` → `jaAplicado`) → `ShouldProcess` → `Invoke-TmxBackupForTweak` (M1: para cada `registry` cujo path existe, `Backup-TmxRegistryHive` deve devolver arquivo; senão `status='falha'`, `detalhe='backup .reg falhou: <path>'`, sem executar ações) → ações em ordem → pós-check. Resultado igual ao CS2Tuner (`itens[]`, `aplicados`, `jaAplicados`, `falhas`, `pulados`, `requerReboot`).

`Preview.ps1`: `Get-TmxPlanPreview -Plan -Profile` → por tweak selecionado, lista `{ tweakId, tipo, alvo, antes, depois, reversao }` usando `Test-TmxAction` (`atual`) e o valor-alvo da ação (`funcao`: `antes = Test-TmxX.atual`, `depois = Test-TmxX.esperado`).

- [x] **Step 3: Rodar** `.\tests\Invoke-Tests.ps1 -Tag Engine` → PASS.
- [x] **Step 4: Commit** `feat(engine): action-level apply/verify/undo/preview with mandatory .reg backup`

### Task 5: Esquema do catálogo, loader, validador, perfil e plano

**Files:**
- Create: `src/Engine/Catalog.ps1`, `src/Engine/Profile.ps1`, `src/Engine/Plan.ps1`, `src/config/preset.json`, `tests/Engine.Catalog.Tests.ps1`, `tests/Engine.Plan.Tests.ps1`, `tests/fixtures/profile-desktop.json`, `tests/fixtures/profile-laptop.json`, `tests/fixtures/catalog-min.json`

**Security flag:** `none`

**Does NOT cover:** o conteúdo real do catálogo (Task 6/7).

- [x] **Step 1: Testes** (`Engine.Catalog.Tests.ps1`): `Test-TmxCatalog` aceita `catalog-min.json` (6 itens: registry MEDIDO, funcao TECNICO, folclore, irreversível, toggle, combobox); rejeita: id duplicado, id fora de `^[A-Z]{3}-\d{3}$`, tier inválido, `reversivel` fora de `total|parcial|nenhuma`, FOLCLORE com presets, `nenhuma` sem `requerConsentimentoExtra`, `nenhuma` com presets, `funcao` sem `Undo-`/`Test-` correspondentes, `acao.tipo` desconhecido, string com `Invoke-Expression`/`[scriptblock]` em qualquer campo, item sem `porque`/`evidencia`, `controle` fora de `checkbox|toggle|combobox|button`, combobox sem `opcoes[]`.
`Engine.Plan.Tests.ps1`: presets `desktop|notebook|minimo`; FOLCLORE → `status='folclore', selecionado=$false, alternavel=$true` (pode ser ligado à mão — diferença do CS2Tuner); `reversivel='nenhuma'` → `status='irreversivel', selecionado=$false, alternavel=$true, exigeConfirmacao=$true`; laptop fixture bloqueia `bloqueiaSe os.isLaptop`; `Set-TmxPlanSelection` recusa `bloqueado`; toggle com estado atual lido (`Test-TmxTweakApplied`) → `estadoAtual`.

- [x] **Step 2: Implementar** `Catalog.ps1` (`Get-TmxCatalog -Path`, `Test-TmxCatalog -Catalog` → `{ok, erros[], total}`; conjuntos: tiers `MEDIDO|TECNICO|FOLCLORE`, riscos `baixo|medio|alto`, presets `desktop|notebook|minimo`, acoes `registry|service|scheduledTask|appx|powercfg|netadapter|bcdedit|feature|funcao`, reversoes `total|parcial|nenhuma`); `Plan.ps1` (`Resolve-TmxPlan -Catalog -Profile -Preset [-IncludeState]`, statuses `planejado|opcional|folclore|irreversivel|bloqueado|foraDoPreset|manual`; `Set-TmxPlanSelection`, `Set-TmxPlanConsent`, `Get-TmxPlanSummary`); `Profile.ps1` (`Get-TmxProfile` → `os{build,nome,isLaptop,isVM,elevado,vbsAtivo,bcd{disponivel,numproc,useplatformclock,disabledynamictick}}`, `network{adaptadorAtivo{nome,tipo}}`, `storage{discoSistema{tipo,midia,trimAtivo,espacoLivrePct}, cs2Path}`, `memory{capacidadeGB}`, `gpu{vendor,dataDriver,hagsAtivo,reflexProvavel,adaptadores[]}` — porta reduzida de `Profile/Get-OsProfile.ps1`, `Get-NetworkProfile.ps1`, `Get-StorageProfile.ps1`, `Get-MemoryProfile.ps1`, `Get-GpuProfile.ps1` do CS2Tuner; `Find-TmxCs2Path` porta de `Find-TunerCs2Path`). `preset.json`:

```json
{ "desktop":  { "nome": "Desktop",  "descricao": "PC de mesa: privacidade, desempenho e limpeza sem itens de energia para notebook." },
  "notebook": { "nome": "Notebook", "descricao": "Igual ao Desktop, sem planos de energia e sem itens que prejudicam bateria/termica." },
  "minimo":   { "nome": "Mínimo",   "descricao": "So o essencial de privacidade: telemetria, recursos de consumidor, WPBT." } }
```
(Quais tweaks entram em cada preset é decidido no campo `presets[]` de cada tweak.)

- [x] **Step 3: Rodar** `-Tag Catalog,Plan` → PASS. **Step 4: Commit** `feat(engine): catalog schema/validator, reduced profile, presets desktop/notebook/minimo`

### Task 6: Conversor WinUtil → TweakMaxing + overlay editorial + funções nomeadas

**Files:**
- Create: `tools/Convert-WinUtilCatalog.ps1`, `src/config/overlay/tweaks.overrides.json`, `src/config/{tweaks,applications,feature,appx,dns}.json` (gerados), `src/functions/tweaks/{Hibernation,Widgets,StoreSearch,SvcHostSplit,Telemetry,RemoveEdge,BitLocker,RemoveOneDrive,ReservedStorage,WindowsAI,RazerBlock,LogiBlock,AdobeBlock,RightClickMenu,DiskCleanup,TempFiles,Teredo,Ipv6,ExplorerAutoDiscovery,ExplorerRestart,UltimatePerformance,Dns}.ps1`, `tests/Tools.Convert.Tests.ps1`, `tests/Config.Tests.ps1`

**Security flag:** `security` (funções que apagam/alteram sistema)

**Does NOT cover:** itens do CS2Tuner (Task 7). Buttons do WinUtil (`OOSU`, `AddUltPerf`, `RemoveUltPerf`) viram tweaks `controle: button`; `OOSU` (baixa e roda O&O ShutUp10) vira `funcao Set-TmxOosu` que só **abre o site** oficial — não baixamos executáveis de terceiros.

- [x] **Step 1: Overlay** `tweaks.overrides.json` — objeto por id do WinUtil (`WPFTweaksTelemetry` etc.), todos os 67 presentes, cada um com: `id` (nosso, `PRV-001`…), `nome`, `descricao`, `categoria` (Privacidade, Desempenho, Sistema, Interface, Rede, Manutenção, Energia, Aplicativos Microsoft), `tier`, `risco`, `presets`, `reversivel`, `requerReboot`, `requerConsentimentoExtra`, `porque`, `evidencia`, `folclore` (se FOLCLORE), `condicoes`, e `funcoes` (mapa InvokeScript→`Set-Tmx*` quando houver). Regra editorial (do spec §2.5); mapeamento mínimo obrigatório:

| WinUtil | tier | reversivel | presets | observação |
|---|---|---|---|---|
| Telemetry, Activity, Location, ConsumerFeatures, WPBT, DeliveryOptimization, PreventDeviceMetadata, EndTaskOnTaskbar, DisableExplorerAutoDiscovery, Hiber, Toggles de UI (ShowExt, HiddenFiles, DarkMode, TaskbarAlignment/Search/TaskView, NumLock, StickyKeys, MouseAcceleration, BatteryPercentage, DetailedBSoD, VerboseLogon, Scrollbars, WindowSnapping, HideSettingsHome, BingSearch, LoginBlur, DisableLockscreen, StartMenuRecommendations, GameMode, LongPaths, NewOutlook), AddUltPerf/RemoveUltPerf, changedns, RevertStartMenu, RightClickMenu, DisableStoreSearch, RemoveHomeAndGallery | MEDIDO | total | Standard → `desktop,notebook`; Minimal → `+minimo` (ConsumerFeatures, WPBT, Telemetry) | AddUltPerf: `bloqueiaSe os.isLaptop == true`, só `desktop` |
| EdgeDebloat, BraveDebloat, Storage (Storage Sense), ReservedStorage, IPv46, Teredo, DisableNotifications, DisableBGapps, Display (efeitos visuais), MultiplaneOverlay, UTC, DisableWarningForUnsignedRdp, RazerBlock, LogiBlock, StandbyFix, S3Sleep | TECNICO | total | `[]` | S3Sleep: `bloqueiaSe os.isLaptop == true` |
| Widget, RemoveEdge, RemoveOneDrive, WindowsAI, DisableBitLocker | TECNICO | parcial | `[]` | `requerConsentimentoExtra: true`; undo reinstala (winget/msstore) ou reativa BitLocker |
| DiskCleanup, DeleteTempFiles | MEDIDO | nenhuma | `[]` | categoria Manutenção, `requerConsentimentoExtra: true` |
| Services (SvcHostSplit + 5 serviços), DisableIPv6, BlockAdobeNet, RestorePoint | FOLCLORE | total | `[]` | RestorePoint do WinUtil é redundante com o nosso (fica como FOLCLORE informativo: "já é obrigatório"); BlockAdobeNet baixa hosts da internet |

`OOSUbutton` → TECNICO, `controle: button`, `funcao Set-TmxOosu` (abre `https://www.oo-software.com/en/shutup10`).

- [x] **Step 2: Conversor** `tools/Convert-WinUtilCatalog.ps1 -Reference reference/winutil -Out src/config` — lê `tweaks.json` (registry[] → ações `registry` com `path/name/value/valueType`, ignorando `OriginalValue`/`DefaultState`; service[] → `service`; appx[] → `appx` com `storeId` de `appx.json` quando bater; InvokeScript → `funcao` pelo mapa do overlay; ComboItems → `opcoes[]`); `applications.json` → `{ id (slug), nome, descricao (traduzida no overlay `applications.overrides.json` — se ausente mantém inglês), categoria PT-BR (Utilitários, Documentos, Ferramentas Pro, Multimídia, Ferramentas Microsoft, Jogos, Navegadores, Desenvolvimento, Comunicação, Auto-hospedado), winget, choco, link, foss }`; `feature.json` → `{ id, nome, descricao, categoria (Recursos|Correções|Painéis|Remoto), controle, feature[] | funcao | comando }`; `appx.json` → `{ id, nome, descricao, pacote, storeId }`; `dns.json` → igual + `nome` PT-BR. Falha com erro claro se `reference/winutil` não existir. Idempotente (mesma entrada → mesma saída byte a byte; UTF-8 sem BOM, indent 2, LF).

- [x] **Step 3: Funções nomeadas** (`src/functions/tweaks/*.ps1`), cada uma com `Set-TmxX -Tweak -Profile -Parametros`, `Undo-TmxX -Estado`, `Test-TmxX -Tweak -Profile`, registrando via `New-TmxCmdletRecord` **antes** do efeito, com wrappers mockáveis para cada executável externo (`Invoke-TmxPowercfg`, `Invoke-TmxIcacls`, `Invoke-TmxDism`, `Invoke-TmxNetsh`, `Invoke-TmxWinget`, `Invoke-TmxCleanmgr`). Sem `Write-Host`. Casos: Hibernation (`powercfg /hibernate off|on`, estado anterior via `HKLM:\SYSTEM\CurrentControlSet\Control\Power\HibernateEnabled`); Widgets (appx + `Test`); StoreSearch (icacls deny/grant); SvcHostSplit (registry via `Set-TmxRegistry` com valor calculado); Telemetry (Set-MpPreference com valor anterior lido, serviços via ação `service`, env var com valor anterior); RemoveEdge (setup.exe --uninstall; undo winget); BitLocker (`Get-BitLockerVolume` estado anterior; undo `Enable-BitLocker` só se estava ligado); RemoveOneDrive (porta; undo winget + serviço); ReservedStorage (DISM state, anterior via `DISM /Get-ReservedStorageState`); WindowsAI (appx + serviço + feature Recall, undo reinstala msstore quando houver storeId); RazerBlock/LogiBlock (icacls; undo remove deny); AdobeBlock (hosts: guarda cópia `hosts.bak` no run; undo restaura do backup); RightClickMenu (registry via `Set-TmxRegistry` + explorer restart); DiskCleanup/TempFiles (`reversivel: nenhuma` — `Undo-` lança "irreversivel"); Teredo (netsh state anterior); Ipv6 (bindings anteriores por adaptador); ExplorerAutoDiscovery (backup `.reg` dos Bags + remoção; undo importa o `.reg`); ExplorerRestart (helper `Restart-TmxExplorer`); UltimatePerformance (porta de `Tweaks/Power.ps1`); Dns (`Set-TmxDns -Parametros @{provedor}`: guarda servidores anteriores por adaptador; undo restaura; `Test` compara).

- [x] **Step 4: Testes** `Tools.Convert.Tests.ps1` (roda o conversor numa pasta temp: 67 tweaks, 236 apps, 33 features, 34 appx, 8 dns; todo tweak tem `tier`, `reversivel`, `porque`, `evidencia`; nenhum `presets` contém FOLCLORE/nenhuma; idempotência). `Config.Tests.ps1` (os JSONs commitados passam `Test-TmxCatalog`; toda `funcao` existe com `Undo-`/`Test-`; `grep` de `Invoke-Expression|scriptblock` em `src/` só acha comentários/validador). Testes unitários das funções com wrappers mockados em `tests/Functions.Tweaks.Tests.ps1` (um `It` por função: Set registra antes, Undo restaura, Test lê).

- [x] **Step 5: Rodar** `.\tools\Convert-WinUtilCatalog.ps1` e `-Tag Convert,Config,Tweaks` → PASS. **Step 6: Commit** `feat(catalog): import WinUtil catalog with evidence tiers and named reversible functions`

### Task 7: Categoria Jogos (catálogo do CS2Tuner) + handlers portados

**Files:**
- Create: `tools/Convert-CS2TunerCatalog.ps1`, `src/functions/tweaks/{NicPower,DefenderExclusion,Trim,Pagefile,GpuMsi,MouseSettings}.ps1`, `src/config/tweaks.jogos.json` (gerado; `Get-TmxCatalog` concatena `tweaks.json` + `tweaks.jogos.json`), `tests/Config.Jogos.Tests.ps1`

**Security flag:** `security`

- [x] **Step 1:** Conversor lê `..\tweak\data\tweaks.json`: `metodo.tipo registry` → ações `registry` (`type`→`valueType`); `powercfg` → ação `powercfg`; `netadapter` → ação; `bcdedit` → ação; `service` → ação; `powershellCmdlet` → `funcao` (`Set-TunerX`→`Set-TmxX`; `Enable-TunerTrim`→`Set-TmxTrim`; `Add-TunerDefenderExclusion`→`Set-TmxDefenderExclusion`); `manual` → `controle: 'info'` (novo valor permitido: item informativo, sem ações, sem checkbox; a UI mostra as instruções); `reversivel: true` → `'total'`; tier/risco/presets: `conservador`→`minimo`, `competitivo`→`desktop,notebook`, `agressivo`→`desktop`; `bloqueiaSe os.isLaptop` preservado; categoria `Jogos / <categoria original>`; ids `JOG-001…`; `origem: { cs2tuner: 'PWR-001' }`. Aplicação imediata (`aplicarImediato`) vira campo `posAplicar: 'SystemParametersInfo'|'SettingChange'` tratado em `Apply.ps1` via `Update-TmxMouseSettings`/`Send-TmxSettingChange` (porta de `Tweaks/InputStack.ps1` + `Profile/Native.ps1` com namespace `TweakMaxing.Native`).
- [x] **Step 2:** Portar `Tweaks/Power.ps1` (NIC), `Services.ps1` (Defender: pasta = `storage.cs2Path` raiz), `Storage.ps1` (TRIM com A1: `$antes -eq $null` → `ok=$false`; pagefile), `CpuScheduling.ps1` (MSI), `Boot.ps1` já na Task 4.
- [x] **Step 3:** Testes: 47 itens, `Test-TmxCatalog` ok no catálogo combinado, ids únicos entre os dois arquivos, fixture laptop bloqueia JOG de energia, `Set-TmxTrim` recusa aplicar sem valor anterior.
- [x] **Step 4: Commit** `feat(catalog): add Jogos category from CS2Tuner with ported handlers`

---

## Fase 4 — Casca da GUI

### Task 8: Bootstrap, runspaces, WebView2 host, ponte e abas vazias

**Files:**
- Create: `scripts/start.ps1`, `scripts/main.ps1`, `src/functions/ui/Start-TmxUserInterface.ps1`, `src/functions/ui/Dialogs.ps1`, `src/functions/ui/Get-TmxWebView2.ps1`, `src/functions/bridge/Invoke-TmxBridgeRequest.ps1`, `src/functions/bridge/Register-TmxBridgeAction.ps1`, `src/functions/bridge/Start-TmxJob.ps1`, `src/functions/bridge/Send-TmxUiEvent.ps1`, `src/functions/bridge/Actions.Shell.ps1`, `src/web/index.html`, `src/web/app.css`, `src/web/app.js`, `Start-TmxDev.ps1`, `tools/Get-WebView2Sdk.ps1`, `tests/Bridge.Tests.ps1`, `tests/gui/_GuiHelpers.ps1`, `tests/gui/Test-Shell.ps1`

**Security flag:** `security` (elevação, execução de código do script salvo, mensagens da UI)

**Does NOT cover:** conteúdo das abas (Tasks 9–13). Cobre: janela, 5 abas vazias, barra de status, ponte `shell.ping`, `shell.version`, `session.status`, `-DebugPort`, `-TestMode`, `-Headless -DryRun -Preset`.

- [x] **Step 1: `tools/Get-WebView2Sdk.ps1`** — baixa `https://www.nuget.org/api/v2/package/Microsoft.Web.WebView2/1.0.3240.44` para `packages/webview2.nupkg`, confere SHA256 `8a8841b6d78c40010d7340287fd55e1355c717568aca7abcc3a14a86280babf7` (falha se diferente), extrai (`Expand-Archive` após copiar para `.zip`) `lib/net462/Microsoft.Web.WebView2.Core.dll`, `lib/net462/Microsoft.Web.WebView2.Wpf.dll`, `runtimes/win-x64/native/WebView2Loader.dll`, `LICENSE.txt` para `packages/webview2/`. Idempotente.

- [x] **Step 2: `scripts/start.ps1`** (baseado em `reference/winutil/scripts/start.ps1`, simplificado):

```powershell
param([switch]$Headless, [ValidateSet('desktop','notebook','minimo','')][string]$Preset, [switch]$DryRun, [int]$DebugPort, [switch]$TestMode, [switch]$NoElevate)
#TMX-COMPILED  (marcador; Compile.ps1 injeta versao em $script:TmxVersion)
$script:TmxVersion = '#{version}'
if ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') { Write-Host 'TweakMaxing precisa de FullLanguage.' -ForegroundColor Red; return 1 }
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrator')
$precisaElevar = -not $isAdmin -and -not $NoElevate -and -not ($Headless -and $DryRun)
if ($precisaElevar) {
    $home = Join-Path $env:LOCALAPPDATA 'TweakMaxing'; New-Item -ItemType Directory -Force $home | Out-Null
    $self = $PSCommandPath
    if (-not $self) {
        $texto = $MyInvocation.MyCommand.ScriptBlock.ToString()
        if ($texto -notmatch '#TMX-COMPILED') { $texto = Invoke-RestMethod "https://github.com/#{repo}/releases/download/v$script:TmxVersion/TweakMaxing.ps1" }
        $self = Join-Path $home "TweakMaxing-$script:TmxVersion.ps1"; Set-Content -LiteralPath $self -Value $texto -Encoding UTF8
    }
    $params = @{}; foreach ($p in $PSBoundParameters.GetEnumerator()) { $params[$p.Key] = if ($p.Value -is [switch]) { [bool]$p.Value } else { $p.Value } }
    $payload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes([Management.Automation.PSSerializer]::Serialize(@{ ScriptPath = $self; Parameters = $params })))
    $boot = "`$l=[Management.Automation.PSSerializer]::Deserialize([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$payload')));`$p=`$l.Parameters;& `$l.ScriptPath @p"
    Start-Process powershell -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-STA','-EncodedCommand',[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($boot)))
    return
}
$sync = [Hashtable]::Synchronized(@{}); $sync.version = $script:TmxVersion; $sync.configs = @{}; $sync.testMode = [bool]$TestMode; $sync.debugPort = $DebugPort
$sync.home = Join-Path $env:LOCALAPPDATA 'TweakMaxing'; $sync.logDir = Join-Path $sync.home 'logs'; New-Item -ItemType Directory -Force $sync.logDir | Out-Null
$sync.selected = @{ tweaks = [Collections.Generic.List[string]]::new(); apps = [Collections.Generic.List[string]]::new(); features = [Collections.Generic.List[string]]::new() }
Start-Transcript -Path (Join-Path $sync.logDir ("tweakmaxing_{0:yyyy-MM-dd_HH-mm-ss}.log" -f (Get-Date))) -Append | Out-Null
```
`-TestMode`: raiz `TWEAKMAXING_HOME` = `<temp>\TweakMaxing_Tests`, catálogo ganha 3 tweaks `TST-001..003` (HKCU `Software\TweakMaxing_Tests\Gui`, um registry, um toggle, um FOLCLORE) e o ponto de restauração é substituído por um mock que "cria" `#999` (nunca chama `Checkpoint-Computer`).

- [x] **Step 3: `scripts/main.ps1`** — headless: `Get-TmxProfile` → `Get-TmxCatalog` → `Resolve-TmxPlan -Preset` → se `-DryRun`: `Invoke-TmxPlan -WhatIf`, imprime resumo, `exit 0`; sem `-DryRun`: `Start-TmxSession` (ponto real) → `Invoke-TmxPlan` → resumo → `exit (falhas -gt 0)`. GUI: runspace STA (`New-TmxSessionState` importa todas as funções + `$sync`) executa `Start-TmxUserInterface`; thread principal espera e trata erros como em `reference/winutil/scripts/main.ps1`; ao fechar, `Wait-TmxRemainingWork`, `Close-TmxRunspacePool`, `Stop-Transcript`.

- [x] **Step 4: `Start-TmxUserInterface.ps1`** — do spike: `Get-TmxWebView2` grava as DLLs (base64 em `$sync.embedded.webview2` quando compilado; ou `packages/webview2/` no dev) em `%LOCALAPPDATA%\TweakMaxing\lib\<versao>\`, `Unblock-File`, `Add-Type`, PATH; se `Add-Type` falhar ou `CoreWebView2Environment.GetAvailableBrowserVersionString()` lançar → `Show-TmxDialog -Titulo 'WebView2 ausente' -Texto ... -Botoes 'Instalar via winget','Fechar'` (WPF `Window` simples em `Dialogs.ps1`) e `winget install Microsoft.EdgeWebView2Runtime`; `WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS` só se `$sync.debugPort`; UI extraída para `%LOCALAPPDATA%\TweakMaxing\ui\<versao>\` (dev: `src/web` direto); host `app.tweakmaxing`; `WebMessageReceived` → `Invoke-TmxBridgeRequest -Json $e.WebMessageAsJson` → `PostWebMessageAsJson`; `$sync.webview = $wv`; `Send-TmxUiEvent -Event -Payload` faz `$sync.webview.Dispatcher.Invoke({ $sync.webview.CoreWebView2.PostWebMessageAsJson(...) })`. Janela 1200×760, título `TweakMaxing <versao>`, ícone gerado (WPF `DrawingImage` com as iniciais "TM" — sem assets do WinUtil).

- [x] **Step 5: Ponte** — `Register-TmxBridgeAction -Name 'shell.ping' -Handler { param($payload, $ctx) ... }` guarda em `$sync.bridgeActions` (hashtable). `Invoke-TmxBridgeRequest -Json` → parse; ação inexistente → `{id, ok:false, error:{message:'acao desconhecida'}}`; handler lança → `ok:false` com mensagem; handlers marcados `-Async` rodam via `Start-TmxJob` e respondem imediatamente `{id, ok:true, result:{jobId}}`, emitindo `job.progress {jobId, pct, status}` e `job.done {jobId, ok, result}`. `Start-TmxJob` = runspace pool (`[runspacefactory]::CreateRunspacePool(1, 2, $sessionState, $Host)`), um job por vez (`$sync.activeJob`), fila simples. Ações desta task: `shell.ping`, `shell.version`, `shell.openUrl` (Start-Process só `https://`), `session.status` (`{ restorePoint: {estado:'nenhum'|'criando'|'criado'|'pulado', seq}, runId, runPath, undoCommand }`), `log.tail`.

- [x] **Step 6: Web** — `index.html`: header com logo texto "TweakMaxing", nav com 5 abas (`data-tab="instalar|ajustes|configurar|atualizacoes|microwin"`), `<main>` com 5 seções (vazias, cada uma com `<h2>` e `<p class="vazio">Em construção</p>`), `<footer id="status">` com 4 células (`#st-rp`, `#st-run`, `#st-undo` com botão copiar, `#st-job`), container de toasts `#toasts`, modal genérico `#modal`. `app.css`: tema escuro (`--bg #12131a`, `--panel #1b1d27`, `--accent #4f8cff`), claro via `prefers-color-scheme`, selos (`.selo-medido` verde, `.selo-tecnico` azul, `.selo-folclore` âmbar, `.selo-irreversivel` vermelho, `.selo-parcial` laranja). `app.js`: `const bridge = { call(action, payload) → Promise (id = crypto.randomUUID(), pendings map, timeout 120 s), on(event, fn) }`; `window.chrome.webview.addEventListener('message', …)` roteia `id` → resolve/reject, `event` → listeners; se `window.chrome?.webview` ausente (aberto em navegador comum) usa stub que rejeita com "sem ponte"; troca de abas; `refreshStatus()` a cada `session.changed` e ao iniciar; toasts; `modal.open({titulo, html, botoes:[{rotulo, classe, onClick}]})`.

- [x] **Step 7: `Start-TmxDev.ps1`** — dot-source de `src/**/*.ps1` na ordem do `.psm1`, carrega `src/config/*.json` em `$sync.configs`, `$sync.webRoot = src/web`, `$sync.sdkDir = packages/webview2`, e roda `scripts/start.ps1` + `scripts/main.ps1` (mesmos parâmetros). É o que os testes de GUI usam.

- [x] **Step 8: Testes** — `tests/Bridge.Tests.ps1`: ação desconhecida → `ok:false`; `shell.ping` → `pong`; handler que lança → `ok:false` com mensagem; `shell.openUrl` recusa `file:`/`http:`; `-Async` responde `jobId` e depois emite `job.done` (mock `Send-TmxUiEvent`). `tests/gui/_GuiHelpers.ps1`: `Start-TmxGui -Port 9333 -TestMode` (Start-Process `powershell -STA -File Start-TmxDev.ps1 -DebugPort 9333 -TestMode -NoElevate`, espera `http://127.0.0.1:<port>/json/version` até 40 s), `Stop-TmxGui`, `Invoke-AB` (agent-browser com `timeout 30`). `tests/gui/Test-Shell.ps1`: conecta, `get title` = `TweakMaxing 0.1.0`, `get count nav [data-tab]` = 5, clica cada aba e checa `is visible #tab-<x>`, `get text #st-rp` contém "Nenhum ponto", screenshot `tests/gui/out/shell.png`, fecha. Sai com código ≠ 0 em falha.

- [x] **Step 9: Rodar** `.\tests\Invoke-Tests.ps1 -Tag Bridge` → PASS; `.\tests\gui\Test-Shell.ps1` → PASS. **Step 10: Commit** `feat(gui): WPF+WebView2 shell, JSON bridge, job runner, dev runner and CDP test harness`

---

## Fase 5 — Aba Ajustes

### Task 9: Sessão + ponto de restauração na GUI

**Files:**
- Create: `src/functions/session/Start-TmxSession.ps1`, `src/functions/session/Get-TmxSessionStatus.ps1`, `src/functions/bridge/Actions.Session.ps1`, `tests/Session.Tests.ps1`
- Modify: `src/functions/ui/Dialogs.ps1`, `src/web/app.js`

**Security flag:** `security`

**Does NOT cover:** ponto de restauração real em testes (mock `Invoke-TmxCheckpoint`/`Get-TmxRestorePoints`).

- [x] **Step 1: Testes** — `Start-TmxSession` cria run + chama `Invoke-TmxRestorePointStage`; sucesso → `$sync.session = {runId, runPath, restorePoint={estado:'criado', seq}}`; falha → `$sync.session.restorePoint.estado='falhou'`, retorna `{ok:false, mensagem}` e **nenhum** run marcado como pronto para aplicar (`$sync.session.pronto=$false`); `-SkipConfirmado` (frase digitada na UI) → `estado='pulado'`; `-TestMode` → mock cria `#999`; segunda chamada na mesma sessão é no-op (`ok:true`, mesmo runId).
- [x] **Step 2: Implementar** — `session.start {skip:bool, frase:string}`: se `skip`, exige `frase -ceq 'SEM PONTO DE RESTAURACAO'` (ação `session.skipPhrase` devolve a frase para a UI exibir); roda `Start-TmxSession` como job (`-Async`) emitindo `session.changed`; `session.status` completo. UI: antes de qualquer `plan.apply`/`features.apply`/`fixes.run`, `ensureSession()` → se sem sessão, modal "Criando ponto de restauração…" com progresso; em falha, modal com o erro e dois botões: "Fechar" e "Prosseguir sem ponto (digite a frase)". `#st-rp` mostra estado e `#seq`.
- [x] **Step 3: Rodar** `-Tag Session` → PASS. **Step 4: Commit** `feat(session): blocking restore point stage wired to the GUI with typed skip phrase`

### Task 10: Aba Ajustes completa (catálogo, selos, preset, prévia, aplicar, desfazer, histórico)

**Files:**
- Create: `src/functions/bridge/Actions.Tweaks.ps1`, `src/web/tweaks.js` (carregado por `index.html`), `tests/Bridge.Tweaks.Tests.ps1`, `tests/gui/Test-Tweaks.ps1`
- Modify: `src/web/index.html`, `src/web/app.css`, `src/web/app.js`

**Security flag:** `security`

- [x] **Step 1: Ações da ponte** — `catalog.get {}` → `{ presets, categorias:[{nome, itens:[{id, nome, descricao, categoria, tier, risco, reversivel, controle, opcoes, status, selecionado, alternavel, motivos, estadoAtual, requerReboot, requerConsentimentoExtra, consentimento, porque, evidencia, folclore, origem}]}] }` (plano resolvido com `-IncludeState` para toggles/combobox); `preset.apply {preset}` → re-resolve o plano e devolve ids selecionados; `plan.setSelection {id, selecionado}`; `plan.setConsent {id, frase}` (compara com `tweak.consentimento.frase`; para `reversivel:'nenhuma'` a frase padrão é `ACEITO ACAO IRREVERSIVEL`); `plan.preview {ids}` → `Get-TmxPlanPreview`; `plan.apply {ids}` (`-Async`; exige `$sync.session.pronto`; roda `Invoke-TmxPlan` só com os ids; emite `job.progress` por tweak e `job.done` com o resultado; `posAplicar` executado); `plan.applyToggle {id, ligado}` (toggle = aplicar ou desfazer o tweak imediatamente, com sessão); `undo.tweak {id}` → `Undo-TweakMaxing -RunId atual -TweakId id -Quiet`; `undo.run {runId?}` → `-Latest`/`-RunId`; `runs.list` → `[{runId, criadoEm, registros, revertidos, pendentes}]` lendo cada `state.json` em `Get-TmxRunsRoot`; `undo.command` → string `Undo-TweakMaxing -RunId <id>` (e como executar: `irm ... | iex; Undo-TweakMaxing -RunId ...` — a função existe no script compilado quando chamado com `-Headless -Undo <runId>`, adicionar esse parâmetro em `start.ps1`/`main.ps1`).
- [x] **Step 2: UI (`tweaks.js`)** — barra superior: seletor de preset (3 botões + "Limpar"), busca, contadores; lista por categoria (colapsável) com, por item: checkbox (ou toggle/combobox/button conforme `controle`; `info` só texto), nome, selo tier, selo reversão (`Total`/`Parcial`/`Irreversível`), selo `Reboot` quando `requerReboot`, botão `?` que abre popover com descrição/porquê/evidência/origem (link WinUtil) e, em FOLCLORE, o bloco "por que circula / por que não recomendamos" com fundo âmbar; `title` (hover) em FOLCLORE = "Sem evidência de ganho. Desmarcado por padrão."; itens `bloqueado` desabilitados com o motivo; botão "Desfazer" por item (habilitado se há registro `aplicado` do id no run atual); rodapé da aba: "Aplicar selecionados (N)", "Desfazer tudo desta sessão", "Histórico". Fluxo Aplicar: `ensureSession()` → `plan.preview` → modal tabela `Alvo | Antes | Depois | Reversão` agrupada por tweak, itens com consentimento extra mostram campo para digitar a frase (`plan.setConsent`) → botão "Confirmar e aplicar" → progresso no `#st-job` → modal de resultado (aplicados/já aplicados/falhas/pulados, aviso de reboot). Histórico: modal com `runs.list` e botão Desfazer por run.
- [x] **Step 3: Testes** — `Bridge.Tweaks.Tests.ps1` (TestMode, HKCU): `catalog.get` traz `TST-001..003` com selos; `preset.apply desktop` seleciona `TST-001` e não `TST-003` (FOLCLORE); `plan.preview` de `TST-001` mostra `antes` = valor atual e `depois` = 1; `plan.apply` grava e `undo.tweak` restaura; `undo.run` reverte tudo; `runs.list` mostra o run com `revertidos`. `tests/gui/Test-Tweaks.ps1` (agent-browser): aba Ajustes visível; `get count .tweak` ≥ 3; `is checked` de `#tw-TST-003` = false e `get attr #tw-TST-003 title` contém "Sem evidência"; clica preset Desktop → `#tw-TST-001` checked; clica Aplicar → modal prévia tem texto "Antes" e "Depois"; confirma → espera `#st-job` conter "concluído"; `get text #tw-TST-001 .estado` = "aplicado"; clica Desfazer do item → estado "revertido"; screenshots `ajustes.png`, `previa.png`.
- [x] **Step 4: Rodar** `-Tag Tweaks` e `tests\gui\Test-Tweaks.ps1` → PASS. **Step 5: Commit** `feat(ajustes): tweak tab with evidence badges, presets, live preview, apply and per-item/session undo`

---

## Fase 6 — Aba Instalar

### Task 11: winget/choco: detecção, instalar, desinstalar, atualizar, instalados

**Files:**
- Create: `src/functions/install/Test-TmxPackageManager.ps1`, `src/functions/install/Install-TmxWinget.ps1`, `src/functions/install/Install-TmxChoco.ps1`, `src/functions/install/Invoke-TmxPackage.ps1`, `src/functions/install/Get-TmxInstalledPackages.ps1`, `src/functions/bridge/Actions.Install.ps1`, `src/web/install.js`, `tests/Install.Tests.ps1`, `tests/gui/Test-Install.ps1`

**Security flag:** `security` (executa instaladores)

**Does NOT cover:** instalações reais nos testes (winget/choco mockados via `Invoke-TmxWingetProcess`/`Invoke-TmxChocoProcess`).

- [x] **Step 1:** `Test-TmxPackageManager` → `{ winget:{disponivel, versao}, choco:{disponivel, versao} }` (porta de `Test-WinUtilPackageManager`: `winget --version`, `choco --version`, checagem `Microsoft.DesktopAppInstaller`). `Install-TmxWinget` (porta de `Install-WinUtilWinget`: via `Microsoft.WinGet.Client` do PSGallery **ou** msstore bootstrap; só quando a UI confirma). `Install-TmxChoco` (porta; consentimento). `Invoke-TmxPackage -Action Install|Uninstall|Upgrade -Programs [string[]] -Manager winget|choco` — porta de `Install-WinUtilProgramWinget` com o mapa de códigos (`-1978335135` já instalado, `-1978335189` sem atualização, `3010/1641/-1978334967/-1978334965` reboot, `-1978335107` contexto admin) e fallback: `Manager=auto` → winget; se falhar com código não mapeado e o app tem `choco` e choco disponível → tenta choco; resultado `{ pacote, gerenciador, acao, codigo, resultado:'ok'|'pulado'|'falha', detalhe }` por item. `Upgrade all` = `winget upgrade --all …`. `Get-TmxInstalledPackages` = `winget list --accept-source-agreements` parse (ids) + cruzamento com o catálogo.
- [x] **Step 2:** Ações: `apps.catalog`, `apps.managers`, `apps.install {ids}` (`-Async`, progresso por pacote), `apps.uninstall {ids}`, `apps.upgradeAll`, `apps.installed`, `apps.repairWinget` (consentimento na UI), `apps.installChoco`. Instalações **não** exigem sessão/ponto (não alteram configuração do sistema; desinstalar é a reversão) — a UI diz isso no rodapé da aba.
- [x] **Step 3: UI (`install.js`)** — busca, categorias colapsáveis (Expandir/Recolher todas), checkbox por app com selo `FOSS`, link para o site, contador "Selecionados: N", botões Instalar/Desinstalar/Atualizar tudo/Mostrar instalados/Limpar; painel do gerenciador (winget ✓/✗ com botão Reparar; choco ✓/✗ com botão Instalar); resultado por pacote em tabela após o job.
- [x] **Step 4: Testes** — mapa de códigos; fallback choco quando winget falha e há id choco; sem choco → falha; `Upgrade all` monta argumentos corretos; `apps.installed` parse de saída de exemplo (fixture `tests/fixtures/winget-list.txt`). GUI: aba Instalar lista ≥ 200 apps, busca "firefox" filtra, seleciona 2 → contador "2", painel mostra winget disponível (máquina real tem).
- [x] **Step 5: Commit** `feat(instalar): winget-first package install/uninstall/upgrade with choco fallback`

---

## Fase 7 — Aba Configurar

### Task 12: Recursos do Windows, correções, painéis, DNS

**Files:**
- Create: `src/functions/features/Invoke-TmxFeature.ps1`, `src/functions/features/Fixes.ps1`, `src/functions/features/Panels.ps1`, `src/functions/bridge/Actions.Features.ps1`, `src/web/configure.js`, `tests/Features.Tests.ps1`, `tests/gui/Test-Configure.ps1`

**Security flag:** `security`

**Does NOT cover:** DISM/SFC/netsh reais nos testes (wrappers mockados).

- [x] **Step 1:** Recursos DISM viram tweaks `controle: toggle` com uma ação `feature` por nome (`Enable`/`Disable` via engine → registro + undo); catálogo `feature.json` alimenta a lista. Correções (`Fixes.ps1`, porta de `Invoke-WPFFixesNetwork`, `Invoke-WPFFixesWinget`, `Invoke-WPFFixesUpdate` (-Aggressive opcional), `Invoke-WPFSystemRepair` (DISM RestoreHealth + SFC), `Invoke-WPFFixesNTPPool` (registro via `Set-TmxRegistry` + `w32tm`), AutoLogon (abre a página oficial do Sysinternals; não baixa)): funções `Invoke-TmxFix<Nome>` com wrappers mockáveis, sem undo (são ações de manutenção) — a UI pede confirmação com texto do que será feito. Painéis: `Panels.ps1` `Open-TmxPanel -Id` com tabela fixa id→comando (`compmgmt.msc`, `control`, `main.cpl`, `ncpa.cpl`, `powercfg.cpl`, `shell:::{A8A91A66-3A7D-4424-8D24-04E180695C7A}`, `appwiz.cpl`, `intl.cpl`, `wscui.cpl`, `mmsys.cpl`, `sysdm.cpl`, `timedate.cpl`, `firewall.cpl`, `rstrui.exe`) — só ids da tabela. DNS: tweak `combobox` `RED-0xx` com `funcao Set-TmxDns` (Task 6) e opção "Padrão (DHCP)"; benchmark opcional `Get-TmxDnsBenchmark` (porta de `Get-WinUtilDNSBenchmark`, `-Async`).
- [x] **Step 2:** Ações: `features.list`, `features.apply {id, ligado}` (via engine + sessão), `fixes.list`, `fixes.run {id}` (`-Async`, confirmação já dada na UI), `panels.open {id}`, `dns.benchmark`.
- [x] **Step 3: UI (`configure.js`)** — três colunas: Recursos (toggles com estado atual), Correções (botões com descrição e diálogo de confirmação), Painéis (grade de botões); bloco DNS (select + Aplicar + Testar latência).
- [x] **Step 4: Testes** — `panels.open` recusa id fora da tabela; `fixes.run` chama os wrappers na ordem documentada (mock); `features.apply` grava registro `feature` e undo chama `Disable-`/`Enable-` inverso. GUI: aba Configurar mostra 14 painéis, 6 correções, ≥ 6 recursos; clicar "Painel de Controle" chama `panels.open` (verificar pelo log `log.tail`).
- [x] **Step 5: Commit** `feat(configurar): windows features via engine, maintenance fixes, legacy panels and DNS`

---

## Fase 8 — Aba Atualizações

### Task 13: Políticas de Windows Update reversíveis

**Files:**
- Create: `src/config/tweaks.updates.json` (3 tweaks `UPD-001..003`, grupo exclusivo `grupo: 'windows-update'`), `src/functions/tweaks/WindowsUpdate.ps1`, `src/web/updates.js`, `tests/Updates.Tests.ps1`

**Security flag:** `security`

**Does NOT cover:** desativar `wuauserv`/`UsoSvc` — proibido por design (teste garante que nenhuma ação `service` com esses nomes tem `tipoInicio: Disabled`).

- [x] **Step 1:** `UPD-001 Padrão` = `funcao Set-TmxUpdatePolicyDefault` (remove valores de política `HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate` e `\AU`, via `Set-TmxRegistry` com `-Remove` (novo parâmetro: registra `valorAnterior` e reversão `restaurarValorAnterior`), serviços BITS/wuauserv Manual, UsoSvc Automatic); `UPD-002 Só segurança` = ações `registry` (`ExcludeWUDriversInQualityUpdate=1`, `DeferFeatureUpdates=1`, `DeferFeatureUpdatesPeriodInDays=365`, `DeferQualityUpdates=1`, `DeferQualityUpdatesPeriodInDays=4`, `AU\AUOptions=4`, `AU\NoAutoRebootWithLoggedOnUsers=1`, `DriverSearching\DontSearchWindowsUpdate=1`) — porta de `Invoke-WPFUpdatessecurity`; `UPD-003 Adiar` = `funcao Set-TmxUpdatePause` (grava `HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings` `PauseUpdatesExpiryTime`, `PauseFeatureUpdatesStartTime/EndTime`, `PauseQualityUpdatesStartTime/EndTime` = agora + 35 dias, via `Set-TmxRegistry`). Todos MEDIDO, `reversivel: total`, `presets: []`, `controle: 'radio'` (novo controle: grupo exclusivo; aplicar um desfaz o anterior do grupo no run atual).
- [x] **Step 2:** UI: três cartões com descrição do que cada política faz (lista exata de chaves), o ativo marcado (`Test-`), botão Aplicar → prévia → aplicar; aviso fixo "O serviço do Windows Update nunca é desativado".
- [x] **Step 3: Testes** (HKCU redirecionado por parâmetro `-PolicyRoot` nas funções): aplicar `UPD-002` grava as 8 chaves com anterior capturado; `UPD-003` grava datas +35 d; trocar para `UPD-001` reverte a anterior; undo restaura; nenhum `service` de WU é `Disabled`. GUI: aba mostra 3 cartões.
- [x] **Step 4: Commit** `feat(atualizacoes): default/security-only/defer policies as reversible tweaks`

---

## Fase 9 — Compilação e headless

### Task 14: `Compile.ps1` e modo headless

**Files:**
- Create: `Compile.ps1`, `tests/Compile.Tests.ps1`
- Modify: `scripts/start.ps1`, `scripts/main.ps1`, `src/functions/ui/Get-TmxWebView2.ps1`

**Security flag:** `none`

- [x] **Step 1:** `Compile.ps1 [-Run] [-SkipSdk]`: lê `VERSION`; roda `tools/Get-WebView2Sdk.ps1` se `packages/webview2` ausente; monta: cabeçalho
```
<#
  TweakMaxing v{ver} — utilitario de otimizacao do Windows. MIT.
  Obra derivada do WinUtil (c) 2022 CT Tech Group LLC (MIT) — https://github.com/ChrisTitusTech/winutil
  Inclui Microsoft.Web.WebView2 1.0.3240.44 (BSD-3). Ver THIRD-PARTY-NOTICES.md no repositorio.
  Fonte: https://github.com/{repo} — compilado em {data} a partir do commit {sha}
#>
```
+ `start.ps1` (com `#{version}`/`#{repo}` substituídos) + todos `src/Core,Engine,functions/**/*.ps1` + para cada `src/config/*.json`: `$sync.configs.<basename> = @'…'@ | ConvertFrom-Json` + `$sync.embedded.web = @{ 'index.html' = @'…'@; … }` + `$sync.embedded.webview2 = @{ 'Microsoft.Web.WebView2.Core.dll' = '<base64>'; … }` + `main.ps1` → `TweakMaxing.ps1` (UTF-8 com BOM para o PS 5.1 ler acentos). Verifica que nenhum here-string de conteúdo contém `'@` no início de linha (escapa se necessário) e que o resultado parseia (`[Management.Automation.Language.Parser]::ParseFile` sem erros). `-Run` executa.
- [x] **Step 2:** Headless: `TweakMaxing.ps1 -Headless -Preset desktop -DryRun` imprime o plano (id, nome, tier, status) e a simulação; `-Headless -Undo <runId>` executa `Undo-TweakMaxing -RunId`; `-Headless -Preset X` (sem DryRun) exige elevação, cria ponto real e aplica.
- [x] **Step 3: Testes** — compila para pasta temp; arquivo existe, < 8 MB, parse sem erros, cabeçalho contém "CT Tech Group" e "MIT"; `powershell -NoProfile -File TweakMaxing.ps1 -Headless -Preset desktop -DryRun -NoElevate` sai 0 e imprime "Simulacao"; `-Headless -Undo inexistente` sai ≠ 0 com mensagem.
- [x] **Step 4: Commit** `feat(build): single-file compile with embedded configs, web assets and WebView2 SDK; headless mode`

---

## Fase 10 — Publicação

### Task 15: Release v0.1.0, SHA256 e lançador

**Files:**
- Create: `tools/Publish-Release.ps1`, `docs/publicacao.md`
- Modify: `README.md`

**Security flag:** `security` (distribuição)

- [ ] **Step 1:** `Publish-Release.ps1 -Repo <user>/tweakmaxing [-Gh tools/gh/bin/gh.exe]`: `Compile.ps1`; `Get-FileHash -Algorithm SHA256` → `SHA256SUMS.txt` (`<hash>  TweakMaxing.ps1`); `git tag -a v<ver>`; `git push --tags`; `gh release create v<ver> TweakMaxing.ps1 SHA256SUMS.txt --title "TweakMaxing v<ver>" --notes-file docs/release-notes/v<ver>.md`. Substitui `#{repo}` em `start.ps1` no compile pelo repo passado (persistido em `REPO` na raiz).
- [ ] **Step 2: README** — seção "Como usar": (a) rápido: `irm https://github.com/<user>/tweakmaxing/releases/download/v0.1.0/TweakMaxing.ps1 | iex`; (b) verificado: `Invoke-WebRequest … -OutFile TweakMaxing.ps1; (Get-FileHash TweakMaxing.ps1).Hash -eq (Get-Content SHA256SUMS.txt).Split(' ')[0]; powershell -ExecutionPolicy Bypass -File .\TweakMaxing.ps1`; por que tag fixa; por que HTTPS; o que a GUI faz antes de alterar (ponto, prévia, desfazer). Seção "Desfazer": `TweakMaxing.ps1 -Headless -Undo <runId>` e onde ficam os runs. Seção "Licença e créditos". Screenshots das abas (`docs/img/*.png` vindos dos testes GUI).
- [ ] **Step 3:** Executar (após o usuário rodar `tools\gh\bin\gh.exe auth login`): `gh repo create <user>/tweakmaxing --public --source . --push`, `Publish-Release.ps1`. Conferir `curl -sL <url do release> | Get-FileHash` = SHA publicado. Se o login não estiver disponível, deixar tudo pronto e documentar em `docs/publicacao.md` os 3 comandos restantes.
- [ ] **Step 4: Commit** `docs: launcher, verification steps and release tooling`

---

## Fase 11 — MicroWin

### Task 16: Geração de ISO enxuta (avançado)

**Files:**
- Create: `src/functions/microwin/{Get-TmxIsoInfo,Mount-TmxIso,Remove-TmxIsoPackages,New-TmxUnattend,New-TmxIso}.ps1`, `src/functions/bridge/Actions.MicroWin.ps1`, `src/web/microwin.js`, `tests/MicroWin.Tests.ps1`

**Security flag:** `security`

**Does NOT cover:** gravação de USB; drivers injetados; edições não-x64. A ISO original nunca é modificada (copiada para `%LOCALAPPDATA%\TweakMaxing\microwin\<data>\`).

- [x] **Step 1:** Porta reduzida de `reference/winutil/functions/private/Invoke-WinUtilISO.ps1` + `Invoke-WinUtilISOScript.ps1`: pré-checagens (`oscdimg.exe` do ADK ou `Get-TmxOscdimg` que só **indica** o instalador do ADK; espaço ≥ 20 GB; elevação), `Mount-DiskImage`, cópia, `Get-WindowsImage` (lista de edições), `Mount-WindowsImage`, remoção de provisionados (lista de `appx.json` selecionada na UI) e de pacotes/recursos opcionais selecionados, `New-TmxUnattend` (gera `autounattend.xml` a partir de `reference/winutil/tools/autounattend.xml` com nome de usuário/senha da UI, idioma pt-BR), `Dismount-WindowsImage -Save`, `oscdimg -m -o -u2 -udfver102 -bootdata:…` → ISO em pasta escolhida. Cada etapa emite `job.progress`. Falha em qualquer etapa desmonta e limpa.
- [x] **Step 2:** Ações: `microwin.check` (pré-requisitos), `microwin.info {iso}`, `microwin.build {iso, edicao, appx[], recursos[], usuario, senha, destino}` (`-Async`). UI: aviso "Avançado — demora 20–60 min e usa até 20 GB", seletor de ISO (caminho digitado + botão que abre `OpenFileDialog` WPF via `shell.pickFile`), lista de edições, checkboxes de appx/recursos, campos de conta, botão Gerar, progresso.
- [x] **Step 3: Testes** (mocks de `Mount-DiskImage`/`Get-WindowsImage`/`Mount-WindowsImage`/`oscdimg`): `microwin.check` sem oscdimg → `ok:false` com instrução; `build` chama as etapas na ordem e desmonta em falha; unattend gerado contém usuário e `pt-BR`; caminho de ISO inexistente → erro claro.
- [x] **Step 4: Commit** `feat(microwin): lean ISO builder (advanced) ported from WinUtil without USB writing`

---

## Fase 12 — Verificação final

### Task 17: Suite completa, GUI, screenshots, roteiro manual, memória

- [ ] **Step 1:** `.\tests\Invoke-Tests.ps1` → 0 falhas; anotar total no README (badge textual).
- [ ] **Step 2:** `tests\gui\Test-Shell.ps1`, `Test-Tweaks.ps1`, `Test-Install.ps1`, `Test-Configure.ps1` → PASS; copiar screenshots para `docs/img/`.
- [ ] **Step 3:** `Compile.ps1 -Run` abre a GUI compilada (fechar); `TweakMaxing.ps1 -Headless -Preset notebook -DryRun` sai 0.
- [ ] **Step 4:** `docs/testes-manuais.md` preenchido com o que foi executado nesta máquina (ponto de restauração real: sim/não; winget real: sim/não) e o que ficou pendente.
- [ ] **Step 5:** `git status` limpo; `git log --oneline` com um commit por task; memória do Claude atualizada (`tweakmaxing-projeto.md`).

---

## Self-review

- **Cobertura do spec:** §1 filosofia → Tasks 3, 9, 10 (ponto bloqueante, state antes, selos, prévia); §2.1 → Task 8; §2.2 → Task 8/14; §2.3 abas → Tasks 10, 11, 12, 13, 16 + status em 8/9; §2.4 → Tasks 3, 9, 10; §2.5 catálogo/overlay/tiers/presets/Jogos → Tasks 5, 6, 7, 13; §2.6 motor/prévia/instalação/updates → Tasks 4, 11, 13; §2.7 compile/publicação → Tasks 14, 15; §3 contratos → Tasks 4, 8; §4 segurança → Tasks 3, 6 (grep), 8; §5 testes → cada task + 17; §6 falhas → 8 (WebView2, STA, iex), 9 (ponto), 11 (winget); §7 ordem → fases 1–12.
- **Placeholders:** nenhum "TBD"; onde o código não está literal, a especificação nomeia função, parâmetros, retorno, fonte de porta e o teste que prova.
- **Consistência de nomes:** `Set-TmxRegistry`, `New-TmxStateRecord`, `New-TmxCmdletRecord`, `Undo-TweakMaxing -RunId|-Latest|-TweakId|-Quiet`, `Invoke-TmxRestorePointStage -ConfirmSkip`, `Invoke-TmxAction`/`Test-TmxAction`, `Invoke-TmxPlan`, `Get-TmxPlanPreview`, `Resolve-TmxPlan`, `Register-TmxBridgeAction`/`Invoke-TmxBridgeRequest`/`Start-TmxJob`/`Send-TmxUiEvent`, `Start-TmxSession`, `Invoke-TmxPackage`, `Set-TmxDns` — usados com os mesmos nomes em todas as tasks.
- **Redução de escopo:** MicroWin sem USB e AutoLogon/OOSU sem download de binários de terceiros são decisões explícitas do spec (não-objetivos / segurança), não cortes silenciosos.
