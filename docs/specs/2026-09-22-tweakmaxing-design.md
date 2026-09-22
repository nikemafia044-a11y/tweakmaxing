# TweakMaxing — Design

Data: 2026-09-22 · Status: aprovado (delegado pelo usuário após brainstorming) · Base: `AUDITORIA-CS2Tuner.md` (em `..\tweak`) e `reference/winutil` (clone público, MIT, commit de 2026-09-22).

## 1. Objetivo e escopo

Utilitário de otimização e manutenção do Windows 10/11 com **paridade funcional com o WinUtil** (ChrisTitusTech, MIT), interface gráfica, lançado por um comando colado no PowerShell, e com a filosofia do CS2Tuner mantida integralmente:

1. Ponto de restauração **obrigatório e bloqueante** antes da primeira alteração da sessão.
2. `state.json` gravado **antes** de cada escrita + `.reg`/`.pow`/adaptadores exportados + **Desfazer** por tweak e global.
3. **Selo de evidência** por item (MEDIDO / TECNICO / FOLCLORE) visível na GUI; nada é removido do catálogo; FOLCLORE vem desmarcado com aviso.
4. **Prévia antes de aplicar**: cada ação mostra chave/valor `antes → depois` lido ao vivo.

Idioma da interface e do catálogo: português brasileiro. Nomes de código: inglês (verbo-substantivo PowerShell, prefixo `Tmx`).

Nome/marca: **TweakMaxing**. Artefato: `TweakMaxing.ps1`. Repositório: `github.com/<usuario>/tweakmaxing`.

### Não-objetivos (v0.1)

- Chocolatey como gerenciador primário (só fallback quando o app não tem id winget ou o winget falha).
- Gravação de USB bootável no MicroWin (só geração de ISO).
- Temas além de claro/escuro automático; localização além de PT-BR; auto-atualização; telemetria.
- Reproduzir logotipo, nome ou identidade visual do WinUtil.
- Perfil de hardware completo do CS2Tuner (`Profile/`), benchmark (`Bench/`) e relatório HTML.

## 2. Arquitetura

```
TweakMaxing/
├── src/
│   ├── Core/                 # portado do CS2Tuner (Guard, Logger, Backup, Registry, RestorePoint, Rollback)
│   ├── Engine/               # Condition, Catalog (loader+schema), Plan, Apply (handlers por ação), Verify, Preview
│   ├── functions/            # install (winget/choco), features (DISM), fixes, updates, dns, appx, session, bridge, ui
│   ├── config/               # tweaks.json, applications.json, feature.json, preset.json, dns.json, appx.json
│   │   └── overlay/          # tweaks.overrides.json: tier/risco/presets/texto PT-BR por id de origem (mantido à mão)
│   └── web/                  # index.html, app.css, app.js (vanilla, sem build)
├── scripts/                  # start.ps1 (elevação, $sync, logs), main.ps1 (runspace de UI + espera)
├── tools/                    # Convert-WinUtilCatalog.ps1, Get-WebView2Sdk.ps1, Publish-Release.ps1
├── tests/                    # Pester 5+ (*.Tests.ps1) + tests/gui/ (agent-browser)
├── reference/winutil         # clone de estudo (ignorado pelo git; comando no README)
├── packages/                 # WebView2 SDK baixado pelo Compile (ignorado pelo git)
├── Compile.ps1               # gera TweakMaxing.ps1 (funções + JSON + web + DLLs base64)
├── TweakMaxing.ps1           # artefato compilado (ignorado pelo git; publicado na release)
├── LICENSE                   # MIT: (c) TweakMaxing + aviso "(c) 2022 CT Tech Group LLC" (obra derivada)
├── THIRD-PARTY-NOTICES.md    # WinUtil (MIT), WebView2 SDK (licença Microsoft), CS2Tuner
└── README.md
```

### 2.1 Processo e threads (espelha o WinUtil)

- `start.ps1`: checa `FullLanguage`, reeleva via `Start-Process -Verb RunAs` com parâmetros serializados (PSSerializer + base64, como o WinUtil) — sem string de código com dados do usuário. Quando executado por `irm|iex` não existe arquivo: o próprio texto do script (`$MyInvocation.MyCommand.ScriptBlock`) é gravado em `%LOCALAPPDATA%\TweakMaxing\TweakMaxing-<versao>.ps1` e o filho elevado roda esse arquivo. Cria `$sync` (Hashtable sincronizada), pasta de logs e transcript.
- `main.ps1`: modo headless (`-Preset X [-DryRun]`) ou GUI. GUI roda em runspace STA dedicado; trabalho pesado (aplicar, instalar, DISM, winget) roda num runspace pool via `Start-TmxJob`; a UI só recebe eventos.
- Estado compartilhado em `$sync` (configs, seleção, job ativo, sessão/run atual, referência ao WebView2).

### 2.2 GUI: janela WPF + WebView2 + HTML

- Janela WPF única (XAML mínimo: título, ícone, grid com o controle `Microsoft.Web.WebView2.Wpf.WebView2`).
- SDK WebView2 `1.0.3240.44` (NuGet, SHA256 `8a8841b6…babf7`): `Compile.ps1` baixa o pacote uma vez em `packages/`, confere o hash, extrai `Microsoft.Web.WebView2.Core.dll`, `Microsoft.Web.WebView2.Wpf.dll` (net462) e `WebView2Loader.dll` (x64) e os embute em base64 no `TweakMaxing.ps1` (~1,2 MB). Em runtime são gravados em `%LOCALAPPDATA%\TweakMaxing\lib\<versao>\` e carregados com `Add-Type -Path`. Runtime WebView2 (Edge) ausente → diálogo WPF oferecendo `winget install Microsoft.EdgeWebView2Runtime`.
- Conteúdo web (`src/web/*`) embutido no script e extraído para `%LOCALAPPDATA%\TweakMaxing\ui\<versao>\`; servido via `SetVirtualHostNameToFolderMapping('app.tweakmaxing', pasta)` → `https://app.tweakmaxing/index.html`.
- **Ponte** (`functions/bridge/`): JSON em ambos os sentidos. UI → PS: `window.chrome.webview.postMessage({id, action, payload})`; PS → UI: `CoreWebView2.PostWebMessageAsJson({id, ok, result|error})` para respostas e `{event, payload}` para progresso. Ações são um dicionário fechado (`Get-TmxBridgeActions`): `catalog.get`, `preset.apply`, `plan.preview`, `plan.apply`, `undo.tweak`, `undo.run`, `runs.list`, `apps.install`, `apps.upgradeAll`, `apps.installed`, `features.apply`, `fixes.run`, `panels.open`, `updates.setPolicy`, `dns.set`, `microwin.*`, `session.status`. Nada da UI vira código PowerShell.
- Teste da UI: o script aceita `-DebugPort <n>` que define `WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS=--remote-debugging-port=<n>` antes de criar o ambiente; `agent-browser connect <n>` fala CDP com o WebView2.

### 2.3 Layout da GUI (abas, espelhando o WinUtil)

| Aba | Conteúdo |
|---|---|
| **Instalar** | Busca; categorias colapsáveis; checkbox por app com selo FOSS; botões Instalar selecionados / Desinstalar / Atualizar tudo / Mostrar instalados / Limpar seleção; indicador do gerenciador detectado (winget ok / choco fallback / nenhum → botão reparar winget). |
| **Ajustes** | Seletor de preset (Desktop / Notebook / Mínimo) que pré-marca itens; lista por categoria com checkbox, **selo de evidência** (MEDIDO verde, TECNICO azul, FOLCLORE âmbar) e selo de reversão (Total / Parcial / **Irreversível** vermelho); hover mostra "porquê", "evidência" e o aviso de folclore; toggles (dark mode, extensões…) refletem estado atual; botões Aplicar selecionados (abre **prévia**) / Desfazer por item / "Desfazer tudo desta sessão"; painel Histórico de execuções com Desfazer por run. |
| **Configurar** | Recursos do Windows (DISM) com Ativar/Desativar; Correções (reset de rede, reinstalar winget, reset do Windows Update, DISM+SFC, NTP, AutoLogon); Painéis legados (12 atalhos `.cpl`/`.msc`); DNS (seleção de provedor + benchmark opcional). |
| **Atualizações** | Três políticas: Padrão / Só segurança / Adiar. Nunca desabilita `wuauserv`/`UsoSvc`. Cada política é um tweak comum (registro + serviços com estado anterior), portanto reversível. |
| **MicroWin** | Avançado, última fase: ISO de origem → montar → remover apps/recursos selecionados → unattend (conta local) → nova ISO via `oscdimg` (exige ADK; caso contrário instrui). Sem gravação de USB. |
| **Barra de status** | Ponto de restauração (não criado / criando / #seq criado / pulado); pasta do run atual; comando "Desfazer tudo" copiável; job ativo com progresso. |

### 2.4 Sessão, ponto de restauração e desfazer

- Sessão (run) nasce no primeiro clique em Aplicar/Instalar-que-altera-sistema: `New-TmxRun` cria `%LOCALAPPDATA%\TweakMaxing\runs\<runId>\` (`state.json`, `events.jsonl`, `transcript.log`, `regbackup\`).
- Em seguida `Invoke-TmxRestorePointStage`: cria e **verifica** o ponto (porta de `New-TunerRestorePoint`, inclusive throttle e restauração do throttle em `finally`). Falha → modal com o erro e **nada é aplicado**. Pular exige digitar a frase `SEM PONTO DE RESTAURACAO` num diálogo (callback injetado, achado M4). O ponto vale para a sessão inteira; a barra de status mostra o número.
- Cada ação grava um registro no `state.json` **antes** de escrever (porta de `Set-TunerRegistry`/`New-TunerStateRecord`), com `tweakId`, tipo, alvo, valor anterior, estratégia de reversão e status.
- `Undo-TweakMaxing -RunId|-Latest|-StatePath [-TweakId]` reverte em ordem inversa, marca `status='revertido'` + `revertidoEm` e persiste (achado A2). Desfazer por item = filtro por `tweakId` no run atual; global = run inteiro; histórico = qualquer run.
- Correções do Core aplicadas na cópia: A1 (não aplicar sem valor anterior legível), A2 (persistir reversão), M1 (`.reg` obrigatório quando a chave existe), M2 (`chaveRaizCriada` → undo remove a partir do primeiro ancestral criado), M4/M5 (sem Read-Host/Write-Host no Core; callbacks e `-Quiet`), B1 (tipo anterior nulo → falha explícita).

### 2.5 Catálogo (`src/config/*.json`)

Todos os arquivos nascem de `tools/Convert-WinUtilCatalog.ps1` (lê `reference/winutil/config/*.json`) + `src/config/overlay/tweaks.overrides.json` (mantido à mão: tier, risco, presets, `porque`, `evidencia`, nomes/descrições em PT-BR). O conversor é re-executável; o overlay é a fonte das decisões editoriais.

**tweaks.json** — cada item:

```json
{ "id": "TEL-001", "origem": { "winutil": "WPFTweaksTelemetry", "link": "https://winutil.christitus.com/..." },
  "nome": "Telemetria — desativar", "descricao": "...", "categoria": "Privacidade",
  "tier": "MEDIDO", "risco": "baixo", "presets": ["desktop","notebook","minimo"],
  "controle": "checkbox|toggle|combobox|button", "opcoes": [...],
  "reversivel": "total|parcial|nenhuma", "requerReboot": false, "requerConsentimentoExtra": false,
  "condicoes": { "requer": [], "bloqueiaSe": ["os.isLaptop == true :: ..."] },
  "porque": "...", "evidencia": "...", "folclore": { "oQueE": "...", "porqueCircula": "...", "porqueNaoRecomendamos": "..." },
  "acoes": [
    { "tipo": "registry", "path": "HKLM:\\...", "name": "...", "value": 0, "valueType": "DWord" },
    { "tipo": "service", "nome": "diagtrack", "tipoInicio": "Disabled" },
    { "tipo": "scheduledTask", "caminho": "\\Microsoft\\Windows\\...", "estado": "Disabled" },
    { "tipo": "appx", "pacote": "Microsoft.WidgetsPlatformRuntime", "storeId": "9MSSGKG348SP" },
    { "tipo": "powercfg", "subgrupo": "...", "configuracao": "...", "valor": 100 },
    { "tipo": "bcdedit", "acao": "set", "opcao": "bootmenupolicy", "valor": "legacy" },
    { "tipo": "funcao", "nome": "Set-TmxHibernation", "parametros": {} }
  ] }
```

Regras de esquema (validador `Test-TmxCatalog`): id único `AAA-NNN`; `tier`, `risco`, `reversivel` de conjuntos fechados; toda `acao.tipo` de conjunto fechado; `funcao` só aceita funções `Set-Tmx*` existentes com `Undo-Tmx*` e `Test-Tmx*` correspondentes (**os `InvokeScript`/`UndoScript` do WinUtil viram funções nomeadas; JSON nunca contém código**); `reversivel: "nenhuma"` exige `requerConsentimentoExtra: true` e `presets: []`; FOLCLORE exige bloco `folclore` e `presets: []`; `OriginalValue` do WinUtil é descartado — o valor anterior é sempre capturado ao vivo.

Regra de classificação de tier (aplicada no overlay, com justificativa por item):

- **MEDIDO**: a configuração faz exatamente o que o nome diz e o efeito é verificável por leitura direta (telemetria/serviços/ícones/extensões/tema/aceleração do mouse/plano Ultimate/DNS/hibernação/recursos do Windows). Cobre a maioria dos itens "Essential" e "Customize".
- **TECNICO**: mecanismo plausível, ganho depende do contexto ou é indireto (debloat de Edge/Brave, Storage Sense, Reserved Storage, IPv4 preferido, Teredo, notificações, MPO).
- **FOLCLORE**: sem sustentação ou com custo maior que o ganho (desativar IPv6, `SvcHostSplitThresholdInKB` "Services", S3 forçado, bloquear Adobe via hosts baixado da internet, lote de serviços). Ficam no catálogo, desmarcados, com aviso.

Reversão: registro/serviço/tarefa/powercfg/bcdedit/DISM = **total** (estado anterior capturado). Remoção de Edge/OneDrive/Widgets/Copilot = **parcial** (undo reinstala via winget/msstore, dados de perfil não voltam). Limpeza de disco, arquivos temporários, `cleanmgr`, `/ResetBase` = **nenhuma** (exigem confirmação digitada e nunca entram em preset; ficam em categoria "Manutenção").

**Presets** (`preset.json`): `minimo` (⊂ WinUtil Minimal: consumer features, WPBT, telemetria), `notebook` (Standard sem itens `bloqueiaSe os.isLaptop` e sem planos de energia), `desktop` (Standard + Ultimate Performance + itens de desempenho). Nunca incluem FOLCLORE nem `reversivel: nenhuma`. Os 47 tweaks do CS2Tuner entram como categoria **Jogos** com seus tiers originais (folclore incluso, desmarcado) — condições e handlers já existem.

**applications.json**: 236 apps (id, nome, descrição PT-BR, categoria, winget, choco, link, foss). **feature.json**: recursos DISM (Ativar/Desativar reversível) + correções + painéis. **appx.json**: 34 apps da Microsoft removíveis com `storeId` (undo = reinstalar). **dns.json**: 8 provedores.

### 2.6 Motor de aplicação

Porta do `Invoke-TweakPlan` com granularidade de **ação**: para cada tweak selecionado → consentimento extra (se exigido) → `Test-TmxApplied` (pular se já aplicado) → backup específico (`.reg` da chave, `.pow`, adaptadores, BCD) → handler da ação com registro no `state.json` → pós-verificação. Falha em um item não interrompe os demais. `-WhatIf` simula tudo (usado pela prévia e pelo headless `-DryRun`).

**Prévia** (`Get-TmxPlanPreview`): para cada ação, lê o valor atual e devolve `{ alvo, antes, depois, tipo, reversao }`; a UI mostra a tabela antes de confirmar. Itens `funcao` descrevem o efeito via `Test-Tmx*` (estado atual) + texto fixo do "depois".

**Instalação**: `Install-TmxPackage` (winget por pacote, códigos de saída mapeados como no WinUtil; fallback choco quando o app só tem id choco ou winget falha e o choco está presente). Bootstrap de winget (`Install-TmxWinget`) e de choco só com consentimento explícito na UI. Instalações não entram no `state.json` (desinstalar é a reversão natural, exposta na própria aba).

**Atualizações**: `Padrão` remove as políticas; `Só segurança` = adiar feature 365 d, quality 4 d, sem drivers, sem reboot automático com usuário logado (porta do `Invoke-WPFUpdatessecurity`); `Adiar` = pausar por 35 dias (`PauseUpdatesExpiryTime`/`PauseFeatureUpdates*`/`PauseQualityUpdates*`) mantendo serviços em Manual/Automático. Tudo via ações `registry`/`service` → reversível.

### 2.7 Compilação e distribuição

- `Compile.ps1`: `scripts/start.ps1` + `src/Core,Engine,functions/**/*.ps1` + `$sync.configs.<nome> = @'json'@ | ConvertFrom-Json` + `web/*` em here-strings + DLLs base64 + `scripts/main.ps1` → `TweakMaxing.ps1` com cabeçalho contendo versão, SHA256 do WinUtil de referência, aviso MIT e atribuição a Chris Titus Tech.
- Versão: `MAJOR.MINOR.PATCH` em `VERSION`; tag `vX.Y.Z`.
- `tools/Publish-Release.ps1`: compila, calcula SHA256, cria tag e release no GitHub (`gh release create vX.Y.Z TweakMaxing.ps1 SHA256SUMS.txt`).
- Lançador (README): `irm https://github.com/<usuario>/tweakmaxing/releases/download/v0.1.0/TweakMaxing.ps1 | iex` (tag fixa, HTTPS) e o roteiro de verificação: baixar, `Get-FileHash`, comparar com `SHA256SUMS.txt`, executar. Fonte pública no mesmo repositório.
- Só HTTPS; nenhum download em runtime além dos gerenciadores de pacote acionados pelo usuário.

## 3. Interfaces e contratos

- Handler de ação: `Invoke-TmxAction -Action <obj> -Tweak <obj> -Profile <obj>` → `{ ok, detalhe, naoAplicavel, naoSuportado, registros[] }`; `Test-TmxAction` → `{ aplicado ($true/$false/$null), atual, esperado, detalhe }`; undo por `reversao.tipo` do registro (`restaurarValorAnterior | removerValor | removerChaveCriada | cmdlet | reinstalar | naoAplicavel`).
- Funções nomeadas: `Set-TmxX -Tweak -Profile -Parametros` / `Undo-TmxX -Estado` / `Test-TmxX -Tweak -Profile` (contrato do CS2Tuner).
- Ponte: request `{id:string, action:string, payload:object}`; response `{id, ok:bool, result?, error?:{message, detalhe}}`; evento `{event:'job.progress'|'job.done'|'session.changed'|'log', payload}`.
- Perfil mínimo para condições: `os.build`, `os.isLaptop`, `os.isVM`, `os.elevado`, `os.vbsAtivo`, `os.bcd.*`, `network.adaptadorAtivo.*`, `storage.discoSistema.*`, `memory.capacidadeGB`, `gpu.vendor` (porta reduzida do `Get-TunerProfile`).

## 4. Erros e segurança

- Toda escrita passa por `Set-TmxRegistry` (captura + estado antes) ou por `New-TmxStateRecord` antes do efeito. `grep` no CI: nenhum `Set-ItemProperty|New-ItemProperty|Remove-Item` fora de `Core/Registry.ps1`, `Core/Rollback.ps1` e funções `Undo-Tmx*`.
- Nenhum `Invoke-Expression`/`[scriptblock]::Create` sobre dados de JSON ou da UI (teste Pester faz grep).
- Elevação obrigatória para GUI; `-DryRun`/`-Headless -DryRun` rodam sem elevação.
- Erros de handler viram `status='falha'` com detalhe; erros da ponte viram resposta `ok:false` e toast na UI; exceções no runspace de UI são logadas e encerram com código 1.
- Logs: `events.jsonl` por run + `logs\tweakmaxing_<data>.log` global.

## 5. Testes

- **Pester** (`tests/*.Tests.ps1`, HKCU `Software\TweakMaxing_Tests`, raiz isolada via `TWEAKMAXING_HOME`): Core (portado + novos: A1, A2, M1, M2, `-TweakId`), Condition, Catalog (schema, todos os JSONs resolvem, todo `funcao` existe com Undo/Test, nenhum FOLCLORE/irreversível em preset, tier em todo item, notebook exclui `isLaptop`), Apply roundtrip por tipo de ação (registry/service/scheduledTask mockado/appx mockado/funcao), Preview, Updates (as 3 políticas em HKCU de teste), Install (winget mockado: códigos de saída, fallback choco), Converter (WinUtil → nosso JSON, contagem e ids), Compile (gera arquivo, parse sem erro, cabeçalho com atribuição, tamanho < 8 MB), Headless (`-DryRun -Preset desktop` sai 0).
- **GUI** (`tests/gui/*.ps1` + agent-browser via CDP): janela abre; 5 abas + status; Ajustes lista N itens com selos; preset marca os esperados; hover em FOLCLORE mostra aviso; prévia mostra antes→depois de um tweak de teste (`TST-*` em HKCU, visível só com `-TestMode`); aplicar + desfazer por item e por sessão refletem no estado; Instalar detecta winget; screenshots salvos em `tests/gui/out/`.
- Ponto de restauração real, `winget` real e MicroWin: testados manualmente (roteiro em `docs/testes-manuais.md`), nunca no CI.

## 6. Modos de falha avaliados

| Modo | Severidade | Tratamento |
|---|---|---|
| SDK WebView2 não carrega (DLL bloqueada, x86, runtime ausente) | Crítico → mitigado | DLLs embutidas (sem download); `Unblock-File`; runtime ausente → diálogo WPF com instalação via winget; mensagem clara e saída 1. |
| Apartment/threads: PS 7 vs 5.1, host não-STA | Alto → mitigado | UI em runspace STA próprio (padrão WinUtil), independente do host. |
| `irm\|iex` sem arquivo para reelevar | Alto → mitigado | Grava o próprio texto do script em `%LOCALAPPDATA%` e eleva com `-File`; fallback: rebaixar a URL fixa da versão. |
| Ponto de restauração falha (política, VSS) | Alto → por design | Bloqueia; pular só com frase digitada; status visível. |
| winget ausente/quebrado | Médio | Detecção + reparo com consentimento; choco fallback. |
| Catálogo do WinUtil muda | Baixo | Conversor re-executável + overlay por id de origem; teste de contagem alerta. |
| Escrita em HKCU do admin ≠ usuário logado | Baixo | Registrar SID e avisar na barra de status quando diferir. |
| Antivírus bloqueia `iex` | Baixo | Documentado no README (verificação de hash + execução por arquivo). |

## 7. Ordem de construção

1. Repo + LICENSE + THIRD-PARTY + README inicial + `.gitignore` + clone de referência.
2. Core portado com correções A1/A2/M1/M2/M4/M5/B1 + testes de rollback (incluindo `-TweakId` e idempotência).
3. Esquema + loader + validador dos JSONs; conversor WinUtil→TweakMaxing; overlay com tier em todo item; presets.
4. Casca da GUI: WPF + WebView2 + ponte + abas vazias + `-DebugPort` + teste agent-browser "abre".
5. Aba Ajustes: catálogo, selos, preset, prévia, aplicar, desfazer item/sessão, histórico.
6. Aba Instalar: winget/choco, instalar/desinstalar/atualizar tudo/instalados.
7. Aba Configurar: recursos DISM, correções, painéis, DNS.
8. Aba Atualizações.
9. `Compile.ps1` + headless `-DryRun`.
10. Publicação: `Publish-Release.ps1`, release v0.1.0, SHA256, README com lançador e verificação (exige `gh auth login` do usuário).
11. MicroWin (aba Avançado).
12. Suite final: Pester completa + GUI agent-browser + roteiro manual.
