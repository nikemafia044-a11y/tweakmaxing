# Testes manuais (não automatizáveis)

Itens que exigem elevação real, hardware real ou muito tempo. Preencher "Observado" a cada rodada.

| # | Cenário | Como executar | Esperado | Observado (data) |
|---|---|---|---|---|
| 1 | Ponto de restauração real | Abrir a GUI elevada, aba Ajustes, marcar 1 tweak, Aplicar | Barra de status mostra "Ponto #N criado"; `Get-ComputerRestorePoint` lista o ponto com a descrição TweakMaxing | |
| 2 | Falha do ponto | Desabilitar Proteção do Sistema por política (`DisableSR=1`), Aplicar | Modal de erro; nada aplicado; `state.json` sem registros `aplicado` | |
| 3 | Pular ponto | Na falha, escolher "Prosseguir sem ponto" e digitar `SEM PONTO DE RESTAURACAO` | Status "pulado"; aplicação segue | |
| 4 | winget real | Aba Instalar, instalar `7zip.7zip` | Resultado "ok"; `winget list --id 7zip.7zip` encontra | |
| 5 | Atualizar tudo | Botão "Atualizar tudo" | Job termina com tabela de resultados | |
| 6 | Recurso DISM | Configurar → ativar "Windows Sandbox" e desfazer | Estado volta ao anterior sem reboot forçado | |
| 7 | Política de update | Atualizações → "Só segurança" → "Padrão" | Chaves de política criadas e removidas; `wuauserv` nunca Disabled | |
| 8 | Desfazer sessão | Após aplicar 3 tweaks, "Desfazer tudo desta sessão" | Todos revertidos; `state.json` com `status: revertido` | |
| 9 | Desfazer headless | `TweakMaxing.ps1 -Headless -Undo <runId>` | Mesmo resultado do item 8 | |
| 10 | MicroWin | ISO oficial do Windows 11, remover 5 apps, gerar | ISO gerada; original intacta | |
