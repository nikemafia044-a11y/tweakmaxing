# Lançador `irm "https://tweakmax1ng.vercel.app" | iex` — design

Aprovado pelo usuário em 2026-09-23.

## Objetivo

Executar o TweakMaxing pelo terminal com um comando curto, no estilo do WinUtil
(`irm "https://christitus.com/win" | iex`):

```powershell
irm "https://tweakmax1ng.vercel.app" | iex
```

## Fluxo

```
irm https://tweakmax1ng.vercel.app            (ou /win)
  -> Vercel, redirect temporario (307) ->
     https://github.com/nikemafia044-a11y/tweakmaxing/releases/latest/download/TweakMaxing.ps1
  -> iex executa o artefato compilado (ASCII puro, sem BOM)
  -> sem admin: pede UAC, baixa o release DA MESMA VERSAO (tag fixa) e reabre elevado
  -> GUI
```

## Peças

1. **Release no GitHub** (Task 15): `tools/Publish-Release.ps1` compila, gera SHA256 e publica
   `TweakMaxing.ps1` + `SHA256SUMS.txt` no release `v<VERSION>`. Repositório público
   `nikemafia044-a11y/tweakmaxing`; arquivo `REPO` com esse valor.
2. **Launcher Vercel**: pasta `launcher/` com `vercel.json` contendo apenas redirects (`/` e `/win`)
   para o asset `latest`. Projeto Vercel `tweakmax1ng` (nome escolhido pelo usuário para evitar
   colisão). Sem build, sem código.
3. **Elevação**: comportamento atual (UAC automático; o processo elevado baixa o release da versão
   exata em execução, nunca o `latest`).
4. **Documentação**: README, banner do console e release notes mostram o comando curto; a forma com
   parâmetros é `& ([scriptblock]::Create((irm "https://tweakmax1ng.vercel.app"))) -Headless -Preset notebook`.
   O caminho "Verificado" (download por tag fixa + conferência de SHA256) continua documentado para
   quem quer reprodutibilidade.

## Contratos

- `launcher/vercel.json`: `redirects[]` com `source` `/` e `/win`, `destination` = URL `latest` do
  asset, `permanent: false` (307 temporario, para o destino poder mudar sem cache permanente em cliente).
- O artefato continua ASCII puro: o `irm` do PS 5.1 devolve `System.String` para o asset do GitHub
  (verificado com o release do WinUtil), e ASCII não depende de codepage.

## Erros

- Nome `tweakmax1ng` ocupado na Vercel: usar a URL de produção que a Vercel atribuir e registrar a
  URL real no README antes de publicar a documentação.
- Release ausente/404: o `iex` receberia HTML e falharia no parse. Mitigação: publicar o release
  antes do launcher e verificar o redirect ponta a ponta.
- Antivírus bloqueando `irm | iex`: limitação conhecida (igual ao WinUtil); alternativa documentada
  (baixar, conferir SHA256, rodar com `-File`).

## Testes

- Pester: `launcher/vercel.json` é JSON válido, tem as duas rotas, destino aponta para o repositório
  do arquivo `REPO` e para `releases/latest/download/TweakMaxing.ps1`, e não é permanente.
- Ponta a ponta (após deploy): `irm https://tweakmax1ng.vercel.app` devolve texto cujo SHA256 é
  igual ao do asset publicado; `irm .../win` idem.

## Não-objetivos

- Domínio próprio (troca posterior só de DNS/Vercel, sem mexer no artefato).
- Assinatura Authenticode do script.
