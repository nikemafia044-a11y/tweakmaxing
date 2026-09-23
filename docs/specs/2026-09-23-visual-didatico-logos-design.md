# Identidade visual, cards didáticos e logos dos apps — design

Aprovado em 2026-09-23. Decisões do usuário:
- sem análise do TogsBoost (a licença proprietária proíbe; ver `docs/togsboost/01-licenca-e-tecnologia.md`);
- logos: ícone do exe instalado → ícone do site oficial (baixado uma vez, com cache) → iniciais;
- navegação por menu lateral.

**Restrição central: muda só o layout.** O método de execução (start.ps1/main.ps1, ponte JSON, jobs, sessão,
ponto de restauração, state.json, Desfazer, headless, `irm | iex`) não muda. Nenhuma ação da ponte é
renomeada nem muda de contrato; só entra a ação nova `apps.icons`.

## Escopo

1. Paleta cinza e verde-azulado, sem nenhum azul.
2. Casca com menu lateral e logo próprio.
3. Card de ajuste compacto e didático, com "Saiba mais".
4. Logos na aba Instalar (back-end + front-end).
5. Documentos `docs/togsboost/05-lacunas.md` e `06-relatorio-final.md`.

Fora do escopo: funções novas de sistema (não há lacuna em fonte aberta, porque o WinUtil já foi importado inteiro), tema claro
com identidade nova (o tema claro só troca o azul por cinza e o verde-azulado escuro) e mudança de textos do catálogo.

## 1. Tokens (src/web/app.css, `:root`)

Os nomes existentes são mantidos (os outros CSS já usam), com valores novos e tokens adicionais:

| Token | Escuro | Claro | Uso |
|---|---|---|---|
| `--bg` | `#16181B` | `#F3F4F5` | fundo da janela |
| `--panel` | `#1F2226` | `#FFFFFF` | cards e painéis |
| `--panel-2` / `--elevated` | `#2A2E33` | `#E9EBED` | hover, menus, fundo de botão |
| `--linha` | `#33383E` | `#D5D8DC` | divisórias |
| `--fg` | `#E8EAED` | `#16181B` | texto principal |
| `--muted` | `#9AA0A6` | `#51565C` | descrições |
| `--accent` | `#8A9199` | `#5F666D` | seleção, foco, abas (substitui o azul) |
| `--accent-fg` | `#16181B` | `#FFFFFF` | texto sobre `--accent` |
| `--active` | `#14B8A6` | `#0F766E` | botão primário, interruptor ligado |
| `--active-hover` | `#0D9488` | `#115E59` | hover do ativo |
| `--active-fg` | `#04201D` | `#FFFFFF` | texto sobre `--active` (contraste AA) |
| `--ok` | `#3CCF7A` | `#12864A` | sucesso |
| `--warn` | `#E0A83A` | `#8A5D00` | risco médio / folclore |
| `--danger` | `#E5484D` | `#C02626` | risco alto |
| `--laranja` | `#FF8C42` | `#A94E00` | parcial |

Regras: `.btn-primary`, interruptores ligados (`[role=switch][aria-checked=true]`) e botão ativo usam
`--active`/`--active-fg`; aba selecionada e foco usam `--accent`. Nenhum literal de cor azul
(`#4f8cff`, `#1d5fd4` ou qualquer cor com matiz 190°–260° e saturação > 25%) em `src/web/**`.
Texto em fundo: contraste ≥ 4,5:1 (verificado por script).

## 2. Casca

- `<header>` vira `<aside id="sidebar">` à esquerda (largura 220 px; 64 px abaixo de 900 px de largura, só ícones).
- Topo do aside: logo próprio em SVG inline (monograma "TM" geométrico em `--active` sobre `--elevated`) + nome + `#versao`.
- Os botões continuam `button.aba[data-tab=...]`, com ícone SVG inline próprio + rótulo; a ordem é
  Ajustes, Instalar, Configurar, Atualizações, MicroWin. A lógica de troca de aba (app.js) não muda.
- `main` e `footer#status` ficam à direita do aside. Todos os ids existentes são preservados.

## 3. Card de ajuste (src/web/tweaks.js + tweaks.css)

Linha compacta, mantendo `.tweak[data-id]`, `.estado`, `.tw-undo`, `#tw-<id>`, `#sw-<id>` e as classes `.selo-*`:
- nome + interruptor/controle;
- `descricao` (o que faz) em uma linha, com reticências;
- fileira de selos: evidência (`MEDIDO`/`TÉCNICO`/`FOLCLORE`), risco (`baixo`/`médio`/`alto`, novo selo
  `.selo-risco-<nível>` com cor `--ok`/`--warn`/`--danger`), reversibilidade (`Reversível`/`Parcial`/`Irreversível`),
  `Reinício` quando `requerReboot`;
- botão/`<details>` "Saiba mais", que mostra os blocos já existentes: Por quê, Evidência e, no caso do folclore, os blocos de folclore.
Prévia e resultado com Desfazer continuam como estão; só herdam a paleta.

## 4. Logos dos apps

### Catálogo
`applications.json` ganha `icon` (URL https ou `null`). O conversor copia `icon` do overlay
(`applications.overrides.json`) quando existir; o padrão é `null`. O teste do conversor cobre isso.

### Back-end (novo: `src/functions/install/Get-TmxAppIcon.ps1`)
- `Get-TmxAppIconCacheDir`: `<home do TweakMaxing>\icons` (mesma raiz de `runs`, respeitando `TWEAKMAXING_HOME`).
- `Get-TmxAppIcon -App <obj> [-Offline] [-UninstallEntries <lista>]` devolve
  `@{ id; src = 'data:image/png;base64,...'; origem = 'cache'|'exe'|'site' }` ou `$null`. Nunca lança.
  Ordem: cache (`<id>.png`) → exe instalado (entradas de Desinstalar em HKLM/HKCU/WOW6432Node cujo `DisplayName`
  é **igual ao nome do app** (sem diferenciar maiúsculas) **ou começa por `"<nome> "`** — ex.: `Git` casa `Git` e
  `Git 2.40`, mas não casa `GitHub Desktop`; `DisplayIcon` sem o sufixo `,N`; `ExtractAssociatedIcon`) → site
  (`icon` do catálogo; senão, `https://<host de link>/favicon.ico` e, se falhar, o primeiro `<link rel="icon"|"apple-touch-icon">`
  do HTML da página; só https, nunca um IP literal privado/loopback; timeout de 5 s (`ReadWriteTimeout` também,
  e um cronômetro por download cobre o corpo inteiro, não só cada leitura); no máximo 512 KB; redirect (3xx) é
  seguido **na mão**, no máximo 3 saltos, revalidando https + IP não-privado a cada salto — um salto https→http
  para a cadeia na hora).
  A imagem decodificada é revalidada por dimensão (**recusa lado > 1024px ou mais de 1.048.576 pixels** —
  guarda contra "decompression bomb": um arquivo pequeno pode descomprimir enorme) e desenhada **direto** da
  fonte para o destino 64×64 (sem cópia intermediária em tamanho cheio), virando **64×64 PNG** gravado em cache.
  `id` é validado (`^[A-Za-z0-9_.-]+$`, sem `..`) antes de virar nome de arquivo.
- Cache negativo: quando exe **e** site foram tentados de verdade (não pulados por offline/testMode/orçamento) e
  nenhum achou nada, grava `<id>.none` e para de tentar rede por esse id por 7 dias.
- Todo acesso externo passa por wrappers mockáveis (`Invoke-TmxHttpRequestOnce`, `Invoke-TmxIconDownload`,
  `Get-TmxUninstallEntries`, `Get-TmxExeIconBitmap`).
- Em `-TestMode`/`$sync.testMode` ou com `-Offline`: sem rede (só cache e exe).
- `Invoke-TmxAppIconBatch -Apps <lista> [-UninstallEntries] [-BudgetMs 8000]`: resolve uma lista de apps já
  resolvidos (não ids) respeitando um **orçamento de tempo total do lote** (padrão 8 s) — ids que não couberem
  saem sem ícone (front-end mantém as iniciais) e **sem** cache negativo (a função simplesmente não roda pra eles).
- Ação da ponte `apps.icons`, payload `{ ids: [...] }` (no máximo 40 por chamada; payload ausente ou sem `ids`
  vira lista vazia, não erro), que roda em job assíncrono como as outras ações demoradas, lê o registro de
  desinstalar uma vez por lote e devolve `{ icons: { <id>: { src, origem } } }`. Id desconhecido ou sem ícone
  fica de fora.

### Front-end (src/web/install.js)
- Cada `.app-row` ganha, antes do nome, `<span class="app-icone">`: primeiro com as iniciais (1–2 letras) num círculo `--elevated`.
- Um `IntersectionObserver` junta os ids visíveis em lotes de **até 10** (back-end aceita até 40, mas o front nunca
  pede mais que 10 por vez) e chama `apps.icons`; o `<img width=32 height=32>` substitui as iniciais quando chega
  (só se `src` começar literalmente com `data:image/png;base64,`). A resposta é guardada em memória.
- **No máximo um lote em voo por vez.** Um id só vira "já pedido" (nunca mais solicitado) quando o **lote inteiro**
  responde com sucesso; numa rejeição (rede, ou "já existe um trabalho em andamento" porque outra ação do usuário
  está usando o único slot de job da ponte), os ids voltam pra fila e a próxima tentativa espera um backoff
  crescente (1 s, 2 s, 4 s, ... até 15 s). Um evento `job.done` global acorda a fila na hora, sem esperar o backoff.
  A lista nunca espera ícone e nunca perde um id.
- Ações do usuário que disparam job assíncrono (instalar, desinstalar, atualizar tudo, listar instalados, reparar
  winget, instalar Chocolatey) esperam e tentam de novo (~20 s) quando o slot está ocupado, em vez de falhar na
  hora — mesmo padrão de `chamarJobComEspera` (`src/web/configure.js`).
- Em cada re-render da lista (recarga do catálogo), o `IntersectionObserver` antigo é desconectado antes de criar
  as linhas novas.

## Erros

- Falha de rede, HTML sem ícone, arquivo inválido, maior que 512 KB, redirect inválido/http, IP privado, dimensão
  grande demais, ou id não reservado pelo orçamento do lote: item sem ícone (fica com as iniciais) e log em WARN,
  sem toast. Só o caso "site tentado de verdade e não achou nada" grava cache negativo — nunca o corte por
  orçamento.
- Uma falha em um ícone não derruba o lote; uma falha do lote inteiro (rede, ou slot ocupado) não perde os ids,
  só adia a tentativa.

## Testes

- Pester: `Get-TmxAppIcon` (ordem cache → exe → site, offline/testMode sem rede, limite de tamanho, só https, cache gravado 64×64)
  e ação `apps.icons` (lote > 40 recusado, ids desconhecidos ignorados); conversor com `icon`.
- Script de paleta `tests/Palette.Tests.ps1`: nenhum azul em `src/web/**`; contraste ≥ 4,5 para os pares de texto dos tokens.
- GUI com agent-browser (`tests/gui/*.ps1`): os 4 testes existentes continuam passando; capturas novas de cada seção em `docs/img/`.
- Suíte completa verde (salvo as 2 falhas de ambiente de `session.start` enquanto C: tiver menos de 2 GB livres).

## Riscos

- **Seletores dos testes de GUI quebrarem com o layout novo (crítico):** mitigado mantendo todos os ids e classes listados e
  rodando os 4 testes de GUI.
- **Favicon de baixa resolução ou ausente:** aceitável; nesse caso ficam as iniciais.
- **O `DisplayName` casar com o app errado (ex.: "Git" casando "GitHub Desktop"):** só se aceita casamento com o nome
  inteiro, sem diferenciar maiúsculas, ou "nome + espaço"; na dúvida, pula para o site.
