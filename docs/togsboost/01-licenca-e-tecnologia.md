# TogsBoost — licença e tecnologia (Fase 1)

Data: 2026-09-23. Pasta inspecionada (somente leitura): `C:\Users\fantasy\AppData\Local\Programs\togsboost`.
Nada foi alterado, movido, extraído para disco ou executado.

## Estrutura

- 155 arquivos, ~461 MB.
- Raiz: `togsboost.exe` (~211 MB), runtime do Chromium/Electron (`*.pak`, `icudtl.dat`, `v8_context_snapshot.bin`,
  `libEGL.dll`, `libGLESv2.dll`, `vk_swiftshader.dll`, `ffmpeg.dll`, `d3dcompiler_47.dll`), `locales/`,
  `Uninstall togsboost.exe`, `LICENSE.electron.txt`, `LICENSES.chromium.html`.
- `resources/`: `app.asar` (~121 MB, 16.597 entradas), `app.asar.unpacked/`, `app-update.yml`, `elevate.exe`,
  `nvidiaProfileInspector.exe`, um perfil `.nip` da NVIDIA e uma pasta `tweaks/`.

## Tecnologia

- **Electron** com interface em React (react-router, Tailwind, headlessui, lucide), estado em zustand,
  `electron-store`, `electron-updater`.
- O processo principal é distribuído como **bytecode V8 compilado com `bytenode`** (`out/main/index.jsc`):
  uma medida deliberada para impedir a leitura do código.
- Telemetria e monitoramento de erros: `posthog-js` e `@sentry/electron`. Integração com Discord (`discord-rpc`).
- Elevação por um `elevate.exe` separado. Ajustes da NVIDIA aplicados pelo `nvidiaProfileInspector.exe` (ferramenta de terceiros).

## Licença

Só foram lidos dois arquivos de dentro do `app.asar`, pelo índice do pacote e sem extrair nada: o `package.json` e o `LICENSE`.

- `package.json`: `"license": "SEE LICENSE IN LICENSE"`, autor `EduContin`.
- `LICENSE`: **"TOGSBOOST PROPRIETARY LICENSE"**, Copyright (c) 2025 EduContin, todos os direitos reservados.
  Licença de uso pessoal e não comercial, que proíbe expressamente:
  - engenharia reversa, descompilação ou tentar obter o código-fonte;
  - extrair ou isolar componentes, funções ou partes;
  - usar o software para desenvolver, testar ou distribuir produto ou serviço concorrente;
  - análise competitiva ou benchmarking sem consentimento por escrito;
  - usar qualquer parte do código, do design ou da arquitetura em outro projeto, comercial ou não.
- Os únicos textos abertos são os dos componentes de terceiros (Electron, Chromium, Tailwind, bytenode, lightningcss),
  cada um sob a própria licença. Eles não cobrem o código, as configurações nem o design do TogsBoost.

## Modo de trabalho decidido

**Não é open source permissivo, então o modo seria sala limpa.** Mas o modo sala limpa descrito no pedido
(registrar fatos funcionais: chaves, valores, serviços, organização do menu) depende justamente de analisar o
software, e isso a licença proíbe expressamente em quatro pontos: engenharia reversa, extração de componentes,
uso para produto concorrente e análise competitiva.

Consequências:

1. **Fases 2, 3 e 5 (levantar e comparar as funções do TogsBoost):** não foram executadas. Ler os manifestos de
   ajustes ou o código compilado para portar funções para o TweakMaxing seria engenharia reversa voltada a produto
   concorrente, justamente o que a licença proíbe.
2. **Fase 4 (estudar a interface para reproduzir a organização):** também é análise competitiva, então não foi executada.
3. **Fases 7 e 8 (paleta cinza e verde-azulado, abordagem didática, logos dos apps):** não dependem do TogsBoost.
   A paleta e o conteúdo didático foram especificados pelo próprio usuário e podem ser feitos no TweakMaxing sem
   tocar no TogsBoost.
4. **Lacunas de funções:** para decidir o que falta no TweakMaxing, a fonte legítima são referências públicas e de
   licença aberta: o WinUtil, que já é a base do catálogo, sob licença MIT, e a documentação da Microsoft.
   O TogsBoost não entra nessa análise.

A decisão final sobre o risco contratual é do usuário, que é quem aceitou essa licença.
