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
.\Compile.ps1          # gera TweakMaxing.ps1 (arquivo único)
.\Compile.ps1 -Run     # gera e executa
```

## Testes

```powershell
.\tests\Invoke-Tests.ps1              # Pester (sem elevação; usa HKCU:\Software\TweakMaxing_Tests)
.\tests\Invoke-Tests.ps1 -Tag Rollback
.\tests\gui\Test-Shell.ps1            # GUI via agent-browser (CDP)
```

## Requisitos

- Windows 10 1909+ ou Windows 11, x64
- Windows PowerShell 5.1 (ou PowerShell 7)
- Runtime do WebView2 (já vem com o Windows 11 e com o Edge; o app oferece instalar se faltar)

## Licença

MIT. Veja `LICENSE` (inclui o aviso de copyright do WinUtil) e `THIRD-PARTY-NOTICES.md`.
