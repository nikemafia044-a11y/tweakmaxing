# TweakMaxing v2: mapa de funções

Os 29 ajustes da tabela do pedido "TweakMaxing v2", comparados com o catálogo (`src/config/tweaks*.json` e o overlay
`tweaks.overrides.json`). Resultado: **20 já existem** e **9 são novos** (spec §7). A ação é *manter* (código e modo
já corretos), *melhorar o texto* (código mantido, textos `oQueFaz`/`beneficio`/`atencao` e `i18n.en` novos) ou
*implementar*.

Todos os 20 existentes receberam textos novos em pt-BR e em inglês; por isso a ação deles é *melhorar o texto*.

| # | Função (pedido) | Modo pedido | Id no catálogo | Modo no catálogo | Já existe? | Ação |
|---|---|---|---|---|---|---|
| 1 | Ativar modo escuro | Leve | INT-009 | leve | sim | melhorar o texto |
| 2 | Alinhar barra de tarefas à esquerda | Leve | INT-021 | leve | sim | melhorar o texto |
| 3 | Menu de contexto clássico | Leve | INT-007 | leve | sim | melhorar o texto |
| 4 | Finalizar tarefa no botão direito | Leve | INT-005 | leve | sim | melhorar o texto |
| 5 | Tela azul detalhada | Leve | SIS-010 | leve | sim | melhorar o texto |
| 6 | Remover atraso dos menus | Leve | INT-024 | leve | não | implementar |
| 7 | Desativar dicas da tela de bloqueio | Leve | INT-025 | leve | não | implementar |
| 8 | Desativar rastreamento de localização | Leve | PRI-002 | leve | sim | melhorar o texto |
| 9 | Desativar Wi-Fi Sense | Leve | PRI-009 | leve | não | implementar |
| 10 | Desativar aceleração do mouse | Leve | JOG-029 | leve | sim | melhorar o texto |
| 11 | Ativar Modo de Jogo | Leve | DES-003 | leve | sim | melhorar o texto |
| 12 | Plano de energia de desempenho máximo | Leve | ENE-004 | leve | sim | melhorar o texto (bloqueado em notebook: `os.isLaptop == true`) |
| 13 | Executar Limpeza de Disco | Leve | MAN-003 | **extras** | sim | melhorar o texto |
| 14 | Otimizar rede | Moderado | JOG-007 + JOG-023 | moderado | sim | melhorar o texto |
| 15 | Separação de prioridade Win32 | Moderado | JOG-008 | moderado | sim | melhorar o texto |
| 16 | Ativar HAGS | Moderado | JOG-015 | moderado | sim | melhorar o texto |
| 17 | Otimização para jogos em janela | Moderado | JOG-048 | moderado | não | implementar |
| 18 | Bloquear apps da Store em segundo plano | Moderado | DES-001 | moderado | sim | melhorar o texto |
| 19 | Otimizar painel da GPU | Moderado | JOG-049 | **extras** | não | implementar |
| 20 | PowerShell 7 como padrão | Extras | SIS-014 | extras | não | implementar |
| 21 | Hora do sistema em UTC | Extras | SIS-004 | extras | sim | melhorar o texto |
| 22 | Serviços pouco usados como manual | Avançado | SIS-001 | **extras** | sim | melhorar o texto |
| 23 | Remover bloatware (escolher o que manter) | Avançado | APM-006 | avancado | não | implementar |
| 24 | Remover apps de jogos da Microsoft | Avançado | APM-007 | avancado | não | implementar |
| 25 | Remover OneDrive | Avançado | APM-003 | avancado | sim | melhorar o texto |
| 26 | Desativar Copilot | Avançado | APM-004 | avancado | sim | melhorar o texto |
| 27 | Desativar Inicialização Rápida | Avançado | JOG-006 | avancado | sim | melhorar o texto |
| 28 | Desativar Isolamento do Núcleo | Ultimate | JOG-009 | ultimate | sim | melhorar o texto |
| 29 | Desativar proteção em tempo real do Defender | Ultimate | SEC-001 | ultimate | não | implementar |

## Divergências do pedido

Três itens ficam num modo diferente do pedido, pelas regras do spec §6:

- **13, Limpeza de Disco (MAN-003):** ação única e irreversível, sem estado para desfazer, então fica em `extras`.
  A limpeza também está na tela **Limpeza** (spec §8).
- **19, Painel da GPU (JOG-049):** não altera nada sozinho. Detecta o fabricante e mostra um guia manual; é `controle:
  info` e, por isso, fica em `extras`.
- **22, Serviços como manual (SIS-001):** classificado como FOLCLORE; o texto explica o motivo. O relatório
  `02-relatorio.md` registra a divergência.

## Duplicatas conhecidas

- A aceleração do mouse também existe como INT-013 (interruptor do WinUtil, em `extras`). O modo Leve usa JOG-029,
  que tem backup e Desfazer próprios.
- O plano de desempenho máximo também existe como JOG-001 (em `extras`). O modo Leve usa ENE-004.
- "Otimizar rede" é a soma de dois tweaks: JOG-007 (economia de energia da placa) e JOG-023 (limitador de rede para
  multimídia).
