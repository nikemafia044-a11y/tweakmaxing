# Relatório final (Fase 9)

Data: 2026-09-24. Branch `feat/visual-logos`, integrada à `main`.

## O que foi feito

### Sobre o TogsBoost

- A licença é proprietária (`01-licenca-e-tecnologia.md`) e proíbe engenharia reversa, extração de componentes
  e uso para produto concorrente. Por decisão do usuário, **nada do TogsBoost foi analisado nem copiado**.
  A pasta dele não foi alterada. Os únicos arquivos lidos foram o `package.json` e o `LICENSE`, justamente para
  descobrir a licença.
- As lacunas de funções foram buscadas só em fontes abertas (`05-lacunas.md`). O WinUtil (MIT) já estava
  importado inteiro, então **nenhuma função nova de sistema** entrou.

### Interface (só layout; o método de execução não mudou)

| Item | Onde |
|---|---|
| Paleta cinza e verde-azulado, sem azul, contraste AA nos dois temas | `src/web/app.css` (tokens), `tests/Palette.Tests.ps1` |
| Menu lateral com logo próprio (monograma TM em SVG) e ícones próprios | `src/web/index.html`, `app.css` |
| Card de ajuste compacto: o que faz, selos de evidência, risco, reversibilidade e reinício, "Saiba mais" com por quê e evidência | `src/web/tweaks.js`, `tweaks.css` |
| Interruptores, presets e botão primário ativos em verde-azulado | `tweaks.css`, `configure.css`, `updates.css` |
| Logos na aba Instalar: exe instalado → ícone do site oficial (cache 64×64 em `%LOCALAPPDATA%\TweakMaxing\icons`) → iniciais | `src/functions/install/Get-TmxAppIcon.ps1`, ação `apps.icons`, `src/web/install.js` |

### Correções que surgiram no caminho

- **Disputa pelo slot único de job (problema que já existia antes):** clicar em "Iniciar sessão" enquanto as abas
  carregavam dava "já existe um trabalho em andamento", e a tela dizia que o ponto de restauração tinha falhado.
  Agora `tmx.bridge.callComEspera` espera até 30 s. Ele só repete quando a recusa é essa, e é seguro repetir
  porque nesse caso nenhum job chegou a ser criado. É usado por todas as ações de usuário e pelo `session.start`.
- **Logos sem atrapalhar o uso:**
  - Um lote de ícones por vez, só quando não há ação do usuário esperando.
  - Orçamento absoluto de 8 s por lote.
  - Download endurecido:
    - só https, com redirect seguido à mão (no máximo 3 saltos);
    - bloqueio de IP privado ou loopback, IPv4 e IPv6;
    - no máximo 512 KB;
    - no máximo 1024 px por lado, para evitar decompression bomb.
  - Cache negativo de 7 dias só quando não há ícone de verdade, nunca por falha de rede.
- **Testes de GUI:**
  - O Test-Updates passou a limpar a chave de teste dele (antes, rodadas anteriores faziam a política já aparecer aplicada).
  - A busca "firefox" no Test-Install passou a comparar com o catálogo real.
- **Catálogo de apps:** descrições de todos os 236 apps em pt-BR (commit anterior desta sessão).

## O que ficou de fora e por quê

| Item | Motivo |
|---|---|
| Funções do TogsBoost | A licença proíbe a análise necessária para conhecê-las |
| Descrição da organização de menu do TogsBoost (Fase 4) | Análise competitiva, proibida pela licença; a organização adotada é nossa (menu lateral pedido pelo usuário) |
| Tempo de DNS dentro do orçamento de ícones | O `HttpWebRequest` não limita a resolução de nome; está documentado no código |
| Tema claro com identidade própria | O tema claro só trocou o azul por cinza e verde-azulado escuro |

## Validação

- Pester: 839 passaram, 0 falharam, 1 pulado (DLL do SDK já presente).
- GUI com agent-browser (Shell, Ajustes, Instalar, Configurar, Atualizações, MicroWin e Sessão): os 7 testes passaram.
- Artefato compilado: `Compile.ps1` gera 2,36 MB ASCII. Executado como o `iex` executa
  (`& ([scriptblock]::Create(...)) -Headless -Preset notebook -DryRun`), sai com código 0.
  A GUI do artefato compilado abre com o layout novo (verificado por CDP).
- Logos: ícone extraído do exe instalado (AnyDesk), ícone do site oficial (7-Zip, download real fora do modo de
  teste) e iniciais para os demais.
- Busca por azul: `tests/Palette.Tests.ps1` varre `src/web/**` (css, js e html); não sobrou nenhum literal azul.
- Capturas: `docs/img/*.png`.

## Como desfazer

- **Interface:** reverter o merge da branch `feat/visual-logos`. O layout é só HTML, CSS e JS em `src/web`, e nenhum dado do
  usuário depende dele.
- **Logos:** apagar `%LOCALAPPDATA%\TweakMaxing\icons` (é só cache). Nenhuma chave de registro é escrita pelos logos.
- Nenhuma função nova altera o sistema, então não há ajuste novo para desfazer; o Desfazer dos ajustes existentes não mudou.
