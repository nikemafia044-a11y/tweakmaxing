# Identidade visual, cards didáticos e logos — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers-optimized:subagent-driven-development. Tasks 1–3 run in parallel (disjoint files).

**Goal:** paleta cinza/verde-azulado sem azul, menu lateral, card de ajuste didático e logos na aba Instalar, sem mudar o método de execução.
**Architecture:** só `src/web/**` muda para o layout; logos ganham um módulo PowerShell novo + ação de ponte `apps.icons` em job assíncrono.
**Tech Stack:** PowerShell 5.1, Pester 6, WebView2 + HTML/JS vanilla, agent-browser (CDP) para GUI.
**Spec:** `docs/specs/2026-09-23-visual-didatico-logos-design.md` (contratos, tokens, seletores preservados).
**Assumptions:** fontes .ps1 continuam ASCII puro (tests/Encoding.Tests.ps1); HTML/CSS/JS podem ter acento (UTF-8 sem BOM). Assume ~1.9 GB livres em C: — 2 testes de `session.start` falham pela guarda de 2 GB e NÃO são regressão.

---

### Task 1: Paleta + casca com menu lateral
**Files:** `src/web/app.css`, `src/web/index.html`, `src/web/configure.css`, `src/web/updates.css`, `src/web/microwin.css`, `src/web/tweaks.css` (só troca de literais de cor, se houver), create `tests/Palette.Tests.ps1`.
- [ ] Teste Pester primeiro: (a) nenhum literal azul em `src/web/**/*.{css,js,html}` (hex/rgb com matiz 190–260° e saturação > 25%); (b) tokens `--active`, `--active-hover`, `--active-fg`, `--elevated` existem no `:root` escuro e claro; (c) contraste ≥ 4.5 para (fg,bg), (fg,panel), (muted,panel), (active-fg,active), (accent-fg,accent) nos dois temas — ler valores do app.css.
- [ ] Tokens conforme o spec; `.btn-primary`/switch ligado usam `--active`; `.aba.active` = fundo `--elevated` + barra à esquerda `--accent`; foco `--accent`.
- [ ] `<header>` → `<aside id="sidebar">` com SVG próprio, `.aba[data-tab]` com ícone SVG inline + rótulo, ordem Ajustes, Instalar, Configurar, Atualizações, MicroWin. Layout: body em grid (aside | main+footer). Colapsa para 64 px < 900 px.
- [ ] Verificar: `Invoke-Pester tests\Palette.Tests.ps1,tests\Compile.Tests.ps1`; `tests\gui\Test-Shell.ps1` PASS; commit `feat(ui): gray/teal palette and sidebar shell`.

### Task 2: Card de ajuste didático
**Files:** `src/web/tweaks.js`, `src/web/tweaks.css`.
- [ ] Linha compacta: nome + controle; `descricao` em 1 linha; selos (evidência, risco `.selo-risco-baixo|medio|alto`, reversibilidade, `Reinício`); "Saiba mais" (`<details class="tw-mais">`) com os blocos Por quê/Evidência/folclore existentes. Preservar `.tweak[data-id]`, `.estado`, `.tw-undo`, `#tw-<id>`, `#sw-<id>`, `.selo-folclore`, `#tw-*` da barra.
- [ ] Usar só tokens (nenhum literal de cor). Switch ligado = `--active`.
- [ ] Verificar: `tests\gui\Test-Tweaks.ps1` PASS; Pester `tests\Bridge.Tweaks.Tests.ps1`; commit `feat(ui): compact didactic tweak cards with Saiba mais`.

### Task 3: Logos dos apps (back + front)
**Files:** create `src/functions/install/Get-TmxAppIcon.ps1`, `tests/AppIcon.Tests.ps1`; modify registro de ações da ponte de apps (onde ficam `apps.*`), `src/web/install.js`, `tools/Convert-WinUtilCatalog.ps1` (+ `icon`), `src/config/applications.json` (regerado), `tests/Tools.Convert.Tests.ps1`.
- [ ] Testes primeiro (contratos do spec §4): ordem cache→exe→site; testMode/offline sem rede (mock de `Invoke-TmxIconDownload` com `-Times 0` só em chamada SÍNCRONA); só https; > 512 KB recusado; saída 64×64 PNG em `<home>\icons\<id>.png`; `apps.icons` recusa > 40 ids e ignora desconhecidos; conversor emite `icon` (null padrão, overlay sobrescreve).
- [ ] Implementar seguindo os padrões existentes (wrappers mockáveis como em `functions/install/_Wrappers.ps1`, constantes como funções, ASCII puro, job via Start-TmxJob como as outras ações demoradas de apps).
- [ ] Front: `.app-icone` com iniciais; IntersectionObserver → lotes de 40 → `apps.icons` → `<img width=32 height=32 alt="">`; cache em memória; nunca bloquear a lista. Preservar `#app-<id>`, `.app`, `#app-busca`, `#app-selecionados`, `#app-gerenciadores`.
- [ ] Verificar: Pester `tests\AppIcon.Tests.ps1,tests\Install.Tests.ps1,tests\Tools.Convert.Tests.ps1,tests\Encoding.Tests.ps1`; `tests\gui\Test-Install.ps1` PASS; commit `feat(install): app logos from installed exe, official site or initials`.

### Task 4: Integração e verificação final (após 1–3)
- [ ] Suíte Pester completa; 4 testes de GUI; `Compile.ps1` + headless dry-run do artefato (exit 0).
- [ ] Capturas novas de cada seção em `docs/img/` via agent-browser; grep de azul = 0; contraste pelo Palette.Tests.
- [ ] Teste manual de ícones na GUI: um app instalado (exe), um via site, um com iniciais.
- [ ] `docs/togsboost/06-relatorio-final.md`; README (capturas); memória; commit.
