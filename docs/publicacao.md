# Publicação de uma release

Guia para quem mantém o repositório. Cobre a primeira publicação (repositório ainda não existe no GitHub) e as seguintes (bump de versão).

## Pré-requisitos

- `git` instalado e o repositório local limpo (`git status --porcelain` vazio).
- GitHub CLI: use o portátil já versionado em `tools\gh\bin\gh.exe`, ou um `gh` no PATH.
- Autenticar uma vez por máquina:

  ```powershell
  tools\gh\bin\gh.exe auth login
  ```

  Segue o fluxo interativo pelo navegador. Depois disso, confira:

  ```powershell
  tools\gh\bin\gh.exe auth status
  ```

## Primeira publicação (repositório remoto ainda não existe)

```powershell
.\tools\Publish-Release.ps1 -Repo SEU_USUARIO/tweakmaxing -CreateRepo
```

Isso, em ordem:

1. Valida `SEU_USUARIO/tweakmaxing` e grava em `REPO`.
2. Lê `VERSION` (por padrão `0.1.0`).
3. Exige a árvore de trabalho limpa; comita `REPO`/`VERSION` como `chore(release): v0.1.0` se algo mudou.
4. Roda `gh repo create SEU_USUARIO/tweakmaxing --public --source . --push` (só porque `origin` ainda não existe — com `-CreateRepo` e um `origin` já configurado, esse passo é pulado).
5. Compila (`Compile.ps1 -Repo SEU_USUARIO/tweakmaxing`), gera `TweakMaxing.ps1` e `SHA256SUMS.txt`.
6. Confere que `docs\release-notes\v0.1.0.md` existe.
7. Cria a tag anotada `v0.1.0`.
8. Empurra `main` e a tag, depois publica a release com `gh release create v0.1.0 TweakMaxing.ps1 SHA256SUMS.txt --title "TweakMaxing v0.1.0" --notes-file docs/release-notes/v0.1.0.md`.

Ao final, o script imprime o comando do lançador (`irm .../TweakMaxing.ps1 | iex`) e o SHA256 publicado.

## O que é publicado

Exatamente dois arquivos como *assets* da release, além do código-fonte (que o GitHub já anexa automaticamente a cada tag): `TweakMaxing.ps1` (o artefato único, ~poucos MB, gerado por `Compile.ps1`) e `SHA256SUMS.txt` (uma linha, `<hash>  TweakMaxing.ps1`). Nenhum dos dois entra no histórico do git — ambos estão no `.gitignore` e são gerados a cada publicação.

## Publicações seguintes (bump de versão)

1. Edite `VERSION` (ou passe `-Version` direto no comando) e escreva `docs\release-notes\v<nova-versao>.md` com as notas dessa versão.
2. Publique:

   ```powershell
   .\tools\Publish-Release.ps1 -Repo SEU_USUARIO/tweakmaxing -Version 0.2.0
   ```

   (Sem `-Version`, o script usa o que já estiver em `VERSION` — nesse caso edite o arquivo à mão antes de rodar.)

3. `-CreateRepo` não é necessário de novo: o script detecta que `origin` já existe e aponta para o repositório certo, e só segue com compilação/tag/push/release.

## Testar sem publicar

```powershell
.\tools\Publish-Release.ps1 -Repo SEU_USUARIO/tweakmaxing -DryRun
```

Compila, calcula o SHA256 e cria a tag local de verdade, mas só *imprime* os comandos `git push` e `gh release create` em vez de rodá-los — nenhum acesso de rede acontece.

```powershell
.\tools\Publish-Release.ps1 -Repo SEU_USUARIO/tweakmaxing -NoPush
```

Igual, mas sem sequer criar movimento de rede planejado além do que já rodou (compilação e tag local); também só imprime os comandos que faltariam.

## Como verificar o SHA256 de uma release já publicada

```powershell
irm https://github.com/SEU_USUARIO/tweakmaxing/releases/download/v0.1.0/TweakMaxing.ps1 -OutFile TweakMaxing.ps1
irm https://github.com/SEU_USUARIO/tweakmaxing/releases/download/v0.1.0/SHA256SUMS.txt -OutFile SHA256SUMS.txt
(Get-FileHash .\TweakMaxing.ps1).Hash -eq (Get-Content .\SHA256SUMS.txt).Split(' ')[0]   # True
```

## Rollback (apagar uma release publicada por engano)

```powershell
tools\gh\bin\gh.exe release delete v0.1.0 --yes     # apaga a release e os assets no GitHub
git push origin :refs/tags/v0.1.0                    # remove a tag do remoto
git tag -d v0.1.0                                     # remove a tag local
```

Se `REPO`/`VERSION` foram commitados por engano numa versão que não deveria ter sido publicada, reverta esse commit específico (`git revert <sha>`) em vez de reescrever o histórico de `main`.
