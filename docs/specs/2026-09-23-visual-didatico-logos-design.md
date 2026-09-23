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
- `Get-TmxAppIcon -App <obj> [-Offline]` devolve `@{ id; src = 'data:image/png;base64,...'; origem = 'cache'|'exe'|'site' }` ou `$null`.
  Ordem: cache (`<id>.png`) → exe instalado (entradas de Desinstalar em HKLM/HKCU/WOW6432Node cujo `DisplayName`
  contém o nome do app, sem diferenciar maiúsculas; `DisplayIcon` sem o sufixo `,N`; `ExtractAssociatedIcon`) → site
  (`icon` do catálogo; senão, `https://<host de link>/favicon.ico` e, se falhar, o primeiro `<link rel="icon"|"apple-touch-icon">`
  do HTML da página; só https; timeout de 5 s; no máximo 512 KB).
  A imagem é redimensionada para **64×64 PNG** (2× de 32 px) e gravada em cache.
- Todo acesso externo passa por wrappers mockáveis (`Invoke-TmxIconDownload`, `Get-TmxUninstallEntries`, `Get-TmxExeIconBitmap`).
- Em `-TestMode`/`$sync.testMode` ou com `-Offline`: sem rede (só cache e exe).
- Ação da ponte `apps.icons`, payload `{ ids: [...] }` (no máximo 40 por chamada), que roda em job assíncrono como as outras ações
  demoradas e devolve `{ icons: { <id>: { src, origem } } }`. Id desconhecido ou sem ícone fica de fora.

### Front-end (src/web/install.js)
- Cada `.app-row` ganha, antes do nome, `<span class="app-icone">`: primeiro com as iniciais (1–2 letras) num círculo `--elevated`.
- Um `IntersectionObserver` junta os ids visíveis em lotes de até 40 e chama `apps.icons`; o `<img width=32 height=32>`
  substitui as iniciais quando chega. A resposta é guardada em memória. A lista nunca espera ícone.

## Erros

- Falha de rede, HTML sem ícone, arquivo inválido ou maior que 512 KB: item sem ícone (fica com as iniciais) e log em WARN, sem toast.
- Uma falha em um ícone não derruba o lote.

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
