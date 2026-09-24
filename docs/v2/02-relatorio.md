# TweakMaxing v2 (2.0.0): relatório

Execução do plano `docs/plans/2026-09-24-v2.md` contra o spec `docs/specs/2026-09-24-v2-design.md`.

## Entregas

| Onda | Tarefa | Commit |
|---|---|---|
| 1 | T1 casca, tema, fontes, i18n e barra de título; T2 modos, textos e inglês; T3 nove ajustes novos; T4 back-ends de sistema | `4e3a2f5` |
| 2 | T5 Painel, Limpeza, Restauração, Configurações e Sistema; T6 Otimizações; T7 Aplicativos e MicroWin | `fde2b15` |
| 3 | T8 integração (headless com modos, VRAM, README, capturas, relatório); T9 publicação | este commit |

## Verificação

- **Pester:** 33 arquivos e 973 testes (972 verdes e 1 pulado, nenhuma falha), um arquivo por processo (a suíte inteira num processo só esgotou a
  memória da máquina). O pulado é de propósito: o caminho "compilar sem o SDK do WebView2" não se aplica aqui,
  porque o SDK existe.
- **GUI (agent-browser via CDP):** 11 de 11 verdes: Shell, Painel, Otimizações, Limpeza, Restauração, Aplicativos,
  MicroWin, Sistema (Configurar e Atualizações), Configurações e Sessão.
- **Artefato compilado:** headless `-DryRun` em todos os modos, saindo com 0: leve (46 itens), moderado (74),
  avançado (90) e ultimate (94). Os modos são cumulativos.
- **Busca por azul:** `tests/Palette.Tests.ps1` não acha nenhuma cor com matiz entre 190° e 260° em `src/web`.
  O contraste AA dos pares de texto está verificado.
- **Capturas** em `docs/img`, comparadas com `docs/design/01..04`. A disposição, os textos e os tokens batem.
  A diferença que resta é o conteúdo que o próprio teste gera (toasts, dados simulados).

## Bugs achados e corrigidos na integração

1. `Get-TmxV2FileTextRaw` usava `Get-Content -Raw`. A string carrega propriedades ETS (PSDrive, PSProvider), e o
   `ConvertTo-Json -Depth 12` do state.json travava. Aplicar o SIS-014 pela GUI teria travado o job.
2. Um HashSet vazio devolvido pelo pipeline virava `$null` (APM-006 com "não manter nenhum").
3. A lista falsa de pontos de restauração não fazia round-trip de JSON com 0 ou 1 item.
4. Valores `byte[]` do registro saíam desenrolados em `Get-TmxItemPropertySafe`.
5. `cleanup.run` parava o `wuauserv` real em modo de teste.
6. A VRAM aparecia como 4 GB em AMD: o `DriverDesc` tem espaço duplo, e a subchave `Properties` sem permissão
   derrubava a enumeração inteira com `-ErrorAction Stop` (a leitura caía no `AdapterRAM` de 32 bits).
7. O headless não aceitava os modos v2 em `-Preset` (o spec §6 pede).

## Pendências conhecidas

- Os testes de GUI rodam só em pt-BR. O inglês é coberto pelo registro das chaves (`tmx.i18n.add` em cada tela),
  não por captura.
