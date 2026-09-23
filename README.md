# TweakMaxing

Utilitário de otimização e manutenção do Windows 10/11, em português, com interface gráfica e um único comando para abrir.

**Obra derivada do [WinUtil](https://github.com/ChrisTitusTech/winutil)** (Chris Titus Tech, licença MIT) — não afiliado. Catálogos, arquitetura de compilação e várias funções vêm de lá; veja `LICENSE` e `THIRD-PARTY-NOTICES.md`. Nome, marca e visual são próprios.

## O que muda em relação ao WinUtil

1. **Ponto de restauração obrigatório e bloqueante** antes da primeira alteração da sessão. Se não puder ser criado e verificado, nada é alterado (pular exige digitar uma frase).
2. **Desfazer de verdade.** Cada alteração grava o valor anterior em `state.json` *antes* de escrever, exporta `.reg` das chaves tocadas e pode ser desfeita por item, por sessão ou por execução antiga.
3. **Selo de evidência** em todo item: `MEDIDO` (efeito verificável), `TECNICO` (mecanismo plausível, ganho depende do contexto) ou `FOLCLORE` (sem sustentação — continua no catálogo, mas desmarcado e com aviso). Itens sem reversão possível levam o selo `Irreversível` e exigem confirmação digitada.
4. **Prévia antes de aplicar:** cada ação mostra chave/valor `antes → depois`, lidos ao vivo.

## Lançador

(publicado na fase 10)

## Rodar a partir do código-fonte

```powershell
git clone https://github.com/ChrisTitusTech/winutil reference/winutil   # referência de estudo (não vai para o repositório)
.\tools\Get-WebView2Sdk.ps1                                              # baixa e confere o SDK do WebView2 em packages\
.\Start-TmxDev.ps1                                                       # abre a GUI direto do fonte (pede elevação)
```

## Compilar

```powershell
.\Compile.ps1                                  # gera TweakMaxing.ps1 (arquivo único, ~2,3 MB)
.\Compile.ps1 -Run                             # gera e executa
.\Compile.ps1 -SkipSdk                         # não baixa o SDK do WebView2 se packages\webview2 faltar
.\Compile.ps1 -Out C:\temp\TweakMaxing.ps1 -Repo usuario/repo
```

O artefato é a concatenação, nesta ordem, de: cabeçalho de licença → `scripts/start.ps1` (com `#{version}`/`#{repo}` substituídos por `VERSION` e pelo arquivo `REPO`) → todo `src/Core`, `src/Engine` e `src/functions/**` na mesma ordem do `Start-TmxDev.ps1` → os JSONs de `src/config` em `$sync.configs['<nome>']` → os arquivos de `src/web` em `$sync.embedded.web` → `tools/microwin/autounattend.template.xml` em `$sync.embedded.microwinTemplate` → as três DLLs do WebView2 em base64 em `$sync.embedded.webview2` → `scripts/main.ps1` (sem o `param()`, que seria erro de sintaxe no meio do script).

Detalhes que importam:

- **Nada passa por `ConvertTo-Json`**: no PS 5.1 ele escaparia todo acento como `\uXXXX` e reindentaria o documento. O texto de cada arquivo entra verbatim dentro de `@'…'@` e é parseado em tempo de execução. Se algum ativo tiver uma linha começando com `'@` (que fecharia a here-string), a compilação falha apontando arquivo e linha.
- **UTF-8 com BOM**, ao contrário dos `.ps1` do repositório (que são ASCII puro e sem BOM): o conteúdo embutido é em português e sem BOM o PS 5.1 leria tudo como ANSI.
- Em tempo de execução o artefato extrai a interface e o modelo do MicroWin para `%LOCALAPPDATA%\TweakMaxing\ui\<versão>\` e as DLLs para `...\lib\<versão>\` (arquivo de mesmo tamanho é considerado igual e não é reescrito).
- Com `-SkipSdk` e `packages\webview2` ausente o artefato sai **sem** as DLLs: o modo headless continua funcionando, mas a GUI falha com `SDK do WebView2 não encontrado...`.
- No fim a compilação confere o parser (zero erros), o tamanho (< 8 MB) e imprime o SHA256, que também vai para `SHA256SUMS.txt`. `TweakMaxing.ps1` e `SHA256SUMS.txt` não entram no repositório.

## Executar o artefato

```powershell
.\TweakMaxing.ps1                                                  # abre a GUI (pede elevação)
.\TweakMaxing.ps1 -Headless -Preset desktop -DryRun -NoElevate     # simula; não altera nada, não eleva
.\TweakMaxing.ps1 -Headless -Preset desktop                        # aplica (eleva sozinho)
.\TweakMaxing.ps1 -Headless -Undo latest                           # desfaz a última execução
.\TweakMaxing.ps1 -Headless -Undo 20260922-120000-1a2b             # desfaz uma execução específica
```

Códigos de saída: `0` sucesso, `1` falha (preset ausente, plano impossível, algum item falhou), `2` abortado antes de alterar qualquer coisa.

## Testes

```powershell
.\tests\Invoke-Tests.ps1              # Pester (sem elevação; usa HKCU:\Software\TweakMaxing_Tests)
.\tests\Invoke-Tests.ps1 -Tag Rollback
.\tests\Invoke-Tests.ps1 -Tag Compile # compila e roda o artefato num processo separado
.\tests\gui\Test-Shell.ps1            # GUI via agent-browser (CDP)
.\tests\gui\Test-Shell.ps1 -Port 9343 -ScriptPath .\TweakMaxing.ps1   # a mesma GUI, a partir do artefato
```

## Requisitos

- Windows 10 1909+ ou Windows 11, x64
- Windows PowerShell 5.1 (ou PowerShell 7)
- Runtime do WebView2 (já vem com o Windows 11 e com o Edge; o app oferece instalar se faltar)

## Licença

MIT. Veja `LICENSE` (inclui o aviso de copyright do WinUtil) e `THIRD-PARTY-NOTICES.md`.
