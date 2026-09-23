# Lacunas de funções (Fase 5)

Data: 2026-09-23.

## Fonte usada

A licença do TogsBoost proíbe engenharia reversa, extração de componentes e análise competitiva
(ver `01-licenca-e-tecnologia.md`). Por decisão do usuário, **nenhuma função do TogsBoost foi levantada nem
comparada**, e as Fases 2 a 4 não foram executadas.

As lacunas foram procuradas só em fontes abertas:

| Fonte | Licença | Situação no TweakMaxing |
|---|---|---|
| WinUtil (`reference/winutil/config`) | MIT | **Importado inteiro**: 67/67 tweaks, 33/33 recursos e correções, 236/236 apps, 34/34 appx, 8/8 DNS (`tools/Convert-WinUtilCatalog.ps1`, teste de contagem em `tests/Tools.Convert.Tests.ps1`) |
| CS2Tuner (mesmo autor) | própria | Importado como categoria "Jogos" (47 itens) |
| Políticas do Windows Update | documentação da Microsoft | 3 políticas reversíveis (UPD-001..003) |

## Resultado

| Função | TogsBoost | TweakMaxing | Ação |
|---|---|---|---|
| Qualquer tweak, recurso, app, appx ou DNS do WinUtil | não analisado | já existe | já existe |
| Categoria Jogos (CS2Tuner) | não analisado | já existe | já existe |
| Funções específicas do TogsBoost | não analisado (licença) | — | não implementar: a única forma de conhecê-las seria a análise que a licença proíbe |

**Nenhuma função nova de sistema** entra nesta rodada. O trabalho aprovado é de interface e apresentação:
paleta cinza e verde-azulado, menu lateral, cards didáticos com "Saiba mais" e logos dos apps
(`docs/specs/2026-09-23-visual-didatico-logos-design.md`).
