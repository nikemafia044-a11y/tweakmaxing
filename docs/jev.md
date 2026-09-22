# Jev (TypeSafe) no TweakMaxing — verificações em lote que economizam tokens

O Jev é um modelo de decisão: recebe evidência crua e perguntas tipadas (sim/não, escolha, escala) e devolve probabilidades calibradas em menos de um segundo, por uma fração de centavo. Ele não escreve texto. Por isso é usado aqui onde antes um agente de linguagem leria centenas de itens só para julgar um campo de cada.

## Pré-requisito

```powershell
$env:TYPESAFE_API_KEY = '<sua chave>'   # console.typesafe.ai/keys — nunca commitar
```

Sem a chave, os scripts geram os payloads em `tools/jev/out/` (ignorado pelo git) e encerram com código 3, sem chamada de rede.

## Scripts

| Script | O que julga | Chamadas |
|---|---|---|
| `tools/jev/Invoke-TmxJevCatalogQa.ps1` | Para cada um dos 114 tweaks: o selo (MEDIDO/TECNICO/FOLCLORE) que o texto sustenta, se `porque`/`evidencia` prometem ganho não verificável, se o texto está em pt-BR | 3 lotes de 40 |
| `tools/jev/Invoke-TmxJevAppsQa.ps1` | Quais das 236 descrições de apps ainda estão em inglês (alimenta `applications.overrides.json`) | 4 lotes de 60 |
| `tools/jev/Invoke-TmxJevTestTriage.ps1` | Roda a suíte Pester e classifica cada falha: ambiente, flaky, defeito, outro; lista defeitos primeiro | 1 chamada por até 64 falhas |

A saída de cada um vai para `tools/jev/out/*.json` e para o console. Só o que ficou `review`/`incerto` ou contradiz o catálogo exige leitura humana.

## Como isso substitui trabalho de agente

- Revisar o selo de evidência de 114 tweaks com um agente custa dezenas de milhares de tokens por rodada. Com o Jev, uma rodada custa três chamadas de centavos e devolve só a lista de exceções.
- Descobrir quais descrições de app faltam traduzir era leitura manual do JSON inteiro; agora é uma lista pronta.
- Depois de uma suíte com falhas, a triagem separa interferência de ambiente (chave de teste apagada por outro processo, porta ocupada) de defeito real antes de gastar contexto investigando.

## Regras ao escrever novas perguntas

1. Uma decisão estreita por pergunta; opções com descrição do que entra e do que não entra.
2. Passe o texto original (`porque`, `evidencia`, mensagem de erro), nunca um resumo seu.
3. Agrupe até ~40–64 itens por chamada referenciando-os por chave (`` `itens.PRV_001` ``); mantenha o corpo abaixo de 120 K caracteres.
4. Aja sobre `auto`/`sim`/`não`; revise `review`/`incerto`.

Referência da API: https://docs.typesafe.ai/api.md
