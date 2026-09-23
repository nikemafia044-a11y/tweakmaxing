# Lançador irm | iex — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-optimized:executing-plans. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `irm "https://tweakmax1ng.vercel.app" | iex` abre o TweakMaxing publicado.
**Architecture:** Release público no GitHub (`nikemafia044-a11y/tweakmaxing`, via `tools/Publish-Release.ps1`) + projeto Vercel `tweakmax1ng` que só redireciona (307, temporario) para `releases/latest/download/TweakMaxing.ps1`.
**Tech Stack:** PowerShell 5.1, Pester 6, gh CLI portátil, Vercel (`npx vercel`).
**Assumptions:** gh logado como `nikemafia044-a11y` (verificado) — não funciona se o token perder o escopo `repo`. Vercel CLI autenticável neste host — se não estiver, usar o conector Vercel MCP; se nenhum funcionar, o launcher fica pronto no repo e o README mostra a URL do GitHub.

Spec: `docs/specs/2026-09-23-launcher-irm-design.md`.

---

### Task 1: `launcher/vercel.json` com teste

**Files:** Create `launcher/vercel.json`, `tests/Launcher.Tests.ps1`

**Does NOT cover:** outras rotas além de `/` e `/win` (404 da Vercel).

- [x] Step 1: teste Pester — JSON válido; `redirects` com `source` `/` e `/win`; `destination` = `https://github.com/<REPO>/releases/latest/download/TweakMaxing.ps1` (REPO lido do arquivo `REPO`, última linha não-comentário); `permanent` = `$false`.
- [x] Step 2: rodar `Invoke-Pester tests\Launcher.Tests.ps1` → FAIL (arquivo ausente).
- [x] Step 3: criar `launcher/vercel.json`.
- [x] Step 4: rodar → PASS (depois que a Task 3 gravar o REPO real; antes, o teste compara com o valor do arquivo REPO, portanto deve passar já com o repo atual gravado no vercel.json se REPO for atualizado nesta task).
- [x] Step 5: commit `feat(launcher): vercel redirect for irm | iex`.

### Task 2: Documentação do comando curto

**Files:** Modify `README.md`, `docs/release-notes/v0.1.0.md`, `docs/publicacao.md`, `.gitignore`

- [x] README "Como usar": bloco principal `irm "https://tweakmax1ng.vercel.app" | iex` (PowerShell, UAC automático); forma com parâmetros `& ([scriptblock]::Create((irm "https://tweakmax1ng.vercel.app"))) -Headless -Preset notebook`; manter caminho Verificado (tag fixa + SHA256) com `<repo>` = `nikemafia044-a11y/tweakmaxing`.
- [x] Trocar `SEU_USUARIO`/`<repo>` por `nikemafia044-a11y/tweakmaxing` em release notes e publicacao.md.
- [x] `.gitignore`: `state.md`, `session-log.md` (notas internas de sessão).
- [x] `Invoke-Pester tests` → 0 falhas; commit `docs: short irm launcher`.

### Task 3: Publicação no GitHub

- [x] Varredura de segredos antes de tornar público: `git grep -nE "gho_|ghp_|TYPESAFE_API_KEY *= *'[^<]|sk-[A-Za-z0-9]{20}"` → só ocorrências documentais.
- [ ] `.\tools\Publish-Release.ps1 -Repo nikemafia044-a11y/tweakmaxing -CreateRepo` → release `v0.1.0` com `TweakMaxing.ps1` e `SHA256SUMS.txt`.
- [ ] `gh release view v0.1.0 -R nikemafia044-a11y/tweakmaxing` lista os 2 assets.

### Task 4: Deploy Vercel

- [x] `npx vercel deploy launcher --prod --yes --name tweakmax1ng` (ou `vercel link --project tweakmax1ng` + deploy). Se o CLI não estiver autenticado, usar o conector Vercel.
- [x] Anotar a URL de produção real; se diferente de `tweakmax1ng.vercel.app`, atualizar README/docs.

### Task 5: Verificação ponta a ponta

- [ ] `irm https://tweakmax1ng.vercel.app` e `/win` → `System.String`; SHA256 do texto (bytes ASCII) = linha de `SHA256SUMS.txt`.
- [ ] `& ([scriptblock]::Create((irm https://tweakmax1ng.vercel.app))) -Headless -Preset notebook -DryRun -NoElevate` → exit 0.
- [ ] Atualizar memória `tweakmaxing-projeto.md`; `git status` limpo.
