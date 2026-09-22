# Avisos de terceiros (THIRD-PARTY NOTICES)

O TweakMaxing é uma **obra derivada** do WinUtil e embute o SDK do WebView2. Os textos de licença abaixo são reproduzidos integralmente, como exigido.

## 1. WinUtil — Chris Titus Tech (MIT)

Repositório: https://github.com/ChrisTitusTech/winutil

O que foi derivado: catálogos (`config/tweaks.json`, `applications.json`, `feature.json`, `appx.json`, `dns.json`, `preset.json`), arquitetura de compilação em arquivo único e de runspaces (UI em STA + pool de trabalho), lógica de instalação via winget/choco, recursos do Windows via DISM, correções (rede, winget, Windows Update, DISM/SFC, NTP), políticas de atualização e o gerador de ISO (MicroWin). Nenhum logotipo, nome ou identidade visual do WinUtil é usado.

```
MIT License

Copyright (c) 2022 CT Tech Group LLC

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## 2. Microsoft.Web.WebView2 1.0.3240.44 (BSD-3-Clause)

Pacote: https://www.nuget.org/packages/Microsoft.Web.WebView2/1.0.3240.44
SHA256 do .nupkg: 8a8841b6d78c40010d7340287fd55e1355c717568aca7abcc3a14a86280babf7

Arquivos embutidos (base64) no `TweakMaxing.ps1`: `lib/net462/Microsoft.Web.WebView2.Core.dll`, `lib/net462/Microsoft.Web.WebView2.Wpf.dll`, `runtimes/win-x64/native/WebView2Loader.dll`.

```
Copyright (C) Microsoft Corporation. All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

   * Redistributions of source code must retain the above copyright
notice, this list of conditions and the following disclaimer.
   * Redistributions in binary form must reproduce the above
copyright notice, this list of conditions and the following disclaimer
in the documentation and/or other materials provided with the
distribution.
   * The name of Microsoft Corporation, or the names of its contributors 
may not be used to endorse or promote products derived from this
software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.```

## 3. CS2Tuner

Mesmo autor do TweakMaxing. `src/Core` e `src/Engine` são portas do Core/Engine do CS2Tuner (ponto de restauração verificado, `state.json` antes da escrita, rollback por estratégia, avaliador de condições sem `Invoke-Expression`).
