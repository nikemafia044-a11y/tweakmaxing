/* tweaks.js - aba "Otimizações" (v2).
 *
 * Seletor de modos cumulativos (Leve ⊂ Moderado ⊂ Avançado ⊂ Ultimate), cards
 * didáticos (O que faz / Benefício / Atenção + "Saiba mais"), filtros por
 * categoria, barra fixa de ação e confirmação separada do Ultimate.
 *
 * Ações da ponte usadas aqui:
 *   catalog.get / mode.select / plan.preview / runs.list /
 *   tweaks.bloatwareList                                   -> assíncronas (job)
 *   plan.apply / plan.applyToggle / undo.tweak / undo.run   -> síncronas que
 *       validam (sessão, consentimento, ids) e SÓ ENTÃO disparam o job; a
 *       resposta imediata traz { jobId } e o resultado chega em job.done.
 *   plan.setSelection / plan.setConsent / plan.setOption / plan.setParams /
 *   undo.command / settings.get / settings.set             -> síncronas.
 *
 * Textos: chaves 'otim.*' registradas aqui com tmx.i18n.add. Os textos do
 * catálogo vêm em pt-BR com i18n.en.{nome,oQueFaz,beneficio,atencao}; o card
 * escolhe pelo idioma atual e cai em pt-BR quando falta tradução.
 *
 * Nada de texto do catálogo entra em innerHTML sem passar por esc().
 */
(function () {
  'use strict';
  window.tmxTabs = window.tmxTabs || {};

  /* ---------------- textos (otim.*) ---------------- */

  var TXT_PT = {
    'otim.eyebrow': 'Otimizações',
    'otim.titulo': 'Ajustes de desempenho',
    'otim.subtitulo': 'Escolha um modo. Cada modo inclui os ajustes dos modos anteriores.',
    'otim.ligados.1': '1 ajuste ligado',
    'otim.ligados.n': '{n} ajustes ligados',
    'otim.historico': 'Histórico',
    'otim.undoSessao': 'Desfazer sessão',
    'otim.carregando': 'Lendo o catálogo e o estado atual do sistema…',
    'otim.erroCatalogo': 'Não foi possível ler o catálogo: {msg}',
    'otim.vazio': 'Nenhum ajuste no catálogo.',
    'otim.nenhumFiltro': 'Nenhum ajuste combina com a busca ou o filtro.',
    'otim.busca': 'Buscar por nome, benefício ou categoria',
    'otim.limpar': 'Limpar seleção',
    'otim.filtros': 'Filtrar por categoria',
    'otim.modos': 'Modo de otimização',

    'otim.modo.leve': 'Leve',
    'otim.modo.moderado': 'Moderado',
    'otim.modo.avancado': 'Avançado',
    'otim.modo.ultimate': 'Ultimate',
    'otim.modo.extras': 'Extras',
    'otim.modoTag': 'Modo {modo}',
    'otim.modo.leve.desc': 'Seguro para qualquer PC. Conforto, privacidade básica e precisão do mouse.',
    'otim.modo.moderado.desc': 'Para quem joga. Soma rede, CPU, GPU e apps em segundo plano.',
    'otim.modo.avancado.desc': 'Limpeza profunda: serviços, bloatware, OneDrive e Copilot.',
    'otim.modo.ultimate.desc': 'Máximo desempenho, trocando proteção por velocidade.',
    'otim.modo.leve.reinicio': 'Sem reinício',
    'otim.modo.moderado.reinicio': 'Alguns reinícios',
    'otim.modo.avancado.reinicio': 'Reinício necessário',
    'otim.modo.ultimate.reinicio': 'Reinício necessário',
    'otim.modo.aplicado': 'Aplicado',

    'otim.explica.faz': 'O que o modo {modo} faz',
    'otim.explica.quem': 'Para quem é',
    'otim.explica.antes': 'Antes de aplicar',
    'otim.modo.leve.faz': 'Ajustes de conforto e privacidade básica: menus sem atraso, sem dicas na tela de bloqueio, mouse sem aceleração, Modo de Jogo e plano de energia certo para o seu PC.',
    'otim.modo.leve.quem': 'Qualquer PC, inclusive notebooks e computadores de trabalho.',
    'otim.modo.leve.antes': 'Nada aqui pede reinício. Tudo volta com Desfazer.',
    'otim.modo.moderado.faz': 'Tudo do Leve, mais: ajustes de rede para ping estável, prioridade da CPU para o jogo em primeiro plano, HAGS, otimização para jogos em janela e bloqueio de apps da Store em segundo plano.',
    'otim.modo.moderado.quem': 'Desktops usados para jogar. É o modo recomendado para a maioria das pessoas.',
    'otim.modo.moderado.antes': 'HAGS só vale depois de reiniciar. Em drivers de vídeo antigos, atualize o driver antes.',
    'otim.modo.avancado.faz': 'Tudo do Moderado, mais: serviços e tarefas em segundo plano, remoção de bloatware (você escolhe o que manter), OneDrive e Copilot.',
    'otim.modo.avancado.quem': 'Quem quer um Windows enxuto e sabe reinstalar um app pela Microsoft Store se precisar.',
    'otim.modo.avancado.antes': 'Pede reinício. Apps removidos voltam pela Microsoft Store, não pelo Desfazer.',
    'otim.modo.ultimate.faz': 'Tudo do Avançado, mais: ajustes que trocam camadas de proteção do Windows (como o isolamento do núcleo) por desempenho.',
    'otim.modo.ultimate.quem': 'PCs dedicados a jogos, de quem entende o risco de cada item.',
    'otim.modo.ultimate.antes': 'Cada item de risco alto pede uma confirmação separada. Pede reinício.',

    'otim.cat.todos': 'Todos',
    'otim.cat.geral': 'Geral',
    'otim.cat.aparencia': 'Aparência',
    'otim.cat.desempenho': 'Desempenho',
    'otim.cat.privacidade': 'Privacidade',
    'otim.cat.jogos': 'Jogos',
    'otim.cat.rede': 'Rede',
    'otim.cat.gpu': 'GPU',

    'otim.card.oQueFaz': 'O que faz',
    'otim.card.beneficio': 'Benefício',
    'otim.card.atencao': 'Atenção',
    'otim.card.entraNoModo': 'Entra no modo {modo}',
    'otim.card.naoSeAplica': 'Não se aplica a este PC',
    'otim.card.folclore': 'Sem evidência de ganho. Desmarcado por padrão.',
    'otim.card.saibaMais': 'Saiba mais',
    'otim.card.porque': 'Por quê',
    'otim.card.evidencia': 'Evidência',
    'otim.card.folcloreTitulo': 'Por que está entre os extras',
    'otim.card.folcloreOQueE': 'O que é',
    'otim.card.folcloreCircula': 'Por que circula',
    'otim.card.folcloreNao': 'Por que não recomendamos',
    'otim.card.instrucoes': 'Instruções',
    'otim.card.situacao': 'Situação',
    'otim.card.estadoAtual': 'Estado atual',
    'otim.card.estado.sim': 'aplicado',
    'otim.card.estado.nao': 'não aplicado',
    'otim.card.estado.nd': 'não verificado',
    'otim.card.origem': 'Abrir a origem',
    'otim.card.desfazer': 'Desfazer',
    'otim.card.desfazerAria': 'Desfazer {nome}',
    'otim.card.opcao': 'Opção',
    'otim.card.escolha': 'Escolha…',
    'otim.card.verGuia': 'Ver guia',
    'otim.card.aplicarSo': 'Aplicar só este',
    'otim.card.ligarAgora': 'Ligar agora',
    'otim.card.desligarAgora': 'Desligar agora',
    'otim.card.id': 'ID',

    'otim.selo.risco.baixo': 'Risco baixo',
    'otim.selo.risco.medio': 'Risco médio',
    'otim.selo.risco.alto': 'Risco alto',
    'otim.selo.MEDIDO': 'Efeito medido',
    'otim.selo.TECNICO': 'Efeito técnico',
    'otim.selo.FOLCLORE': 'Folclore',
    'otim.selo.total': 'Reversível',
    'otim.selo.parcial': 'Reversão parcial',
    'otim.selo.nenhuma': 'Irreversível',
    'otim.selo.reboot': 'Pede reinício',
    'otim.selo.semReboot': 'Sem reinício',

    'otim.extras.titulo': 'Extras: fora dos modos',
    'otim.extras.texto': 'Estes ajustes nunca entram num modo: não têm evidência de ganho, não têm volta, são guias manuais ou dependem de uma escolha sua. Ligue um por um, se quiser.',

    'otim.barra.modo': 'Modo {modo} · {ligados}',
    'otim.barra.semModo': '{ligados}',
    'otim.barra.reboot0': 'Nada pede reinício.',
    'otim.barra.reboot1': '1 pede reinício.',
    'otim.barra.rebootN': '{n} pedem reinício.',
    'otim.barra.ponto': 'Um ponto de restauração é criado antes de aplicar.',
    'otim.barra.ver': 'Ver o que vai mudar',
    'otim.barra.aplicar': 'Aplicar modo {modo}',
    'otim.barra.aplicarSel': 'Aplicar selecionados',

    'otim.ult.titulo': 'Ativar o modo Ultimate?',
    'otim.ult.texto': 'O Ultimate troca proteção por desempenho. Estes ajustes de risco alto entram na seleção:',
    'otim.ult.nenhum': 'Nenhum ajuste de risco alto disponível neste PC.',
    'otim.ult.consent': 'Cada um ainda pede uma confirmação separada (uma frase) antes de ser aplicado. Um ponto de restauração é criado antes, e o que for reversível volta com Desfazer.',
    'otim.ult.check': 'Entendo os riscos e quero ver os ajustes do Ultimate.',
    'otim.ult.ok': 'Usar o Ultimate',
    'otim.cancelar': 'Cancelar',
    'otim.fechar': 'Fechar',
    'otim.continuar': 'Continuar',

    'otim.bloat.titulo': 'Remover bloatware: o que manter?',
    'otim.bloat.texto': 'Marque os aplicativos que você quer MANTER. Os demais, se estiverem instalados, serão removidos. Eles voltam pela Microsoft Store.',
    'otim.bloat.lendo': 'Lendo os aplicativos instalados…',
    'otim.bloat.nenhum': 'Nenhum aplicativo do catálogo está instalado.',
    'otim.gp.titulo': 'Você usa o Xbox Game Pass?',
    'otim.gp.texto': 'Se usa, o app Xbox e a Game Bar ficam instalados. Os outros apps de jogos da Microsoft são removidos.',
    'otim.gp.sim': 'Sim, manter Xbox e Game Bar',
    'otim.gp.nao': 'Não, remover todos',

    'otim.previa.titulo': 'Prévia: antes → depois',
    'otim.previa.tituloVer': 'O que vai mudar: antes → depois',
    'otim.previa.texto': 'Confira o que será alterado. Antes é o valor lido agora; Depois é o valor que será gravado.',
    'otim.previa.alvo': 'Alvo',
    'otim.previa.antes': 'Antes',
    'otim.previa.depois': 'Depois',
    'otim.previa.reversao': 'Reversão',
    'otim.previa.confirmar': 'Confirmar e aplicar',
    'otim.previa.semOpcao': 'Fora da aplicação por falta de opção escolhida: {lista}',
    'otim.consent.titulo': 'Confirmação obrigatória: {nome}',
    'otim.consent.tradeoff': 'Este ajuste pede confirmação separada.',
    'otim.consent.digite': 'Para liberar, digite exatamente:',
    'otim.consent.aria': 'Frase de confirmação de {nome}',
    'otim.consent.ok': 'Confirmar frase',
    'otim.consent.registrado': 'Consentimento registrado para {id}',
    'otim.consent.errado': 'frase incorreta',

    'otim.res.titulo': 'Resultado da aplicação',
    'otim.res.resumo': '{a} aplicados · {j} já aplicados · {f} falhas · {p} pulados',
    'otim.res.reboot': 'Reinicie o Windows para que todos os ajustes valham.',
    'otim.res.ajuste': 'Ajuste',
    'otim.res.status': 'Status',
    'otim.res.detalhe': 'Detalhe',
    'otim.aplicando': 'Aplicando…',
    'otim.revertendo': 'Revertendo…',
    'otim.trabalhando': 'Trabalhando…',

    'otim.st.aplicado': 'aplicado',
    'otim.st.aplicadoNaoVerificado': 'aplicado (não verificado)',
    'otim.st.jaAplicado': 'já aplicado',
    'otim.st.falha': 'falha',
    'otim.st.naoAplicavel': 'não aplicável',
    'otim.st.naoSuportado': 'não suportado',
    'otim.st.semConsentimento': 'sem consentimento',
    'otim.st.simulado': 'simulado',
    'otim.st.pulado': 'pulado',
    'otim.st.revertido': 'revertido',
    'otim.st.nadaReverter': 'nada a reverter',

    'otim.undo.titulo': 'Desfazer tudo desta sessão',
    'otim.undo.texto': 'Todos os ajustes aplicados nesta sessão voltam ao valor anterior, na ordem inversa da aplicação.',
    'otim.undo.botao': 'Desfazer tudo',
    'otim.undo.resumo': '{r} revertidos · {f} falhas · {p} pulados',
    'otim.undo.tituloSessao': 'Reversão da sessão',
    'otim.undo.tituloRun': 'Reversão de {id}',
    'otim.undo.run': 'Desfazer a execução {id}',
    'otim.undo.runTexto': 'Todos os registros dessa execução voltam ao valor anterior.',
    'otim.undo.item': '{id}: {n} registro(s) revertido(s)',
    'otim.undo.resultado': 'Resultado',

    'otim.hist.titulo': 'Histórico de execuções',
    'otim.hist.texto': 'Cada execução guarda o valor anterior de tudo que tocou. A contagem é registros / aplicados / revertidos.',
    'otim.hist.execucao': 'Execução',
    'otim.hist.criada': 'Criada em',
    'otim.hist.contagem': 'Reg. / apl. / rev.',
    'otim.hist.atual': 'atual',
    'otim.hist.nenhuma': 'Nenhuma execução registrada.',
    'otim.hist.terminal': 'Reverter pelo terminal',
    'otim.hist.copiar': 'Copiar comando',
    'otim.hist.copiado': 'Comando copiado',
    'otim.hist.naoCopiou': 'Não foi possível copiar',

    'otim.toast.modo': 'Modo {modo} selecionado',
    'otim.toast.nenhum': 'Nenhum ajuste selecionado',
    'otim.toast.escolhaOpcao': 'Escolha uma opção antes de aplicar',
    'otim.toast.ligado': '{id} ligado',
    'otim.toast.desligado': '{id} desligado',
    'otim.toast.selecao': 'não foi possível alterar a seleção',
    'otim.toast.opcao': 'opção inválida'
  };

  var TXT_EN = {
    'otim.eyebrow': 'Optimizations',
    'otim.titulo': 'Performance tweaks',
    'otim.subtitulo': 'Pick a mode. Each mode includes the tweaks of the modes before it.',
    'otim.ligados.1': '1 tweak on',
    'otim.ligados.n': '{n} tweaks on',
    'otim.historico': 'History',
    'otim.undoSessao': 'Undo session',
    'otim.carregando': 'Reading the catalog and the current system state…',
    'otim.erroCatalogo': 'Could not read the catalog: {msg}',
    'otim.vazio': 'No tweaks in the catalog.',
    'otim.nenhumFiltro': 'No tweak matches the search or the filter.',
    'otim.busca': 'Search by name, benefit or category',
    'otim.limpar': 'Clear selection',
    'otim.filtros': 'Filter by category',
    'otim.modos': 'Optimization mode',

    'otim.modo.leve': 'Light',
    'otim.modo.moderado': 'Moderate',
    'otim.modo.avancado': 'Advanced',
    'otim.modo.ultimate': 'Ultimate',
    'otim.modo.extras': 'Extras',
    'otim.modoTag': '{modo} mode',
    'otim.modo.leve.desc': 'Safe for any PC. Comfort, basic privacy and mouse precision.',
    'otim.modo.moderado.desc': 'For gamers. Adds network, CPU, GPU and background apps.',
    'otim.modo.avancado.desc': 'Deep cleanup: services, bloatware, OneDrive and Copilot.',
    'otim.modo.ultimate.desc': 'Maximum performance, trading protection for speed.',
    'otim.modo.leve.reinicio': 'No restart',
    'otim.modo.moderado.reinicio': 'Some restarts',
    'otim.modo.avancado.reinicio': 'Restart required',
    'otim.modo.ultimate.reinicio': 'Restart required',
    'otim.modo.aplicado': 'Applied',

    'otim.explica.faz': 'What {modo} mode does',
    'otim.explica.quem': 'Who it is for',
    'otim.explica.antes': 'Before applying',
    'otim.modo.leve.faz': 'Comfort and basic privacy tweaks: no menu delay, no lock screen tips, no mouse acceleration, Game Mode and the right power plan for your PC.',
    'otim.modo.leve.quem': 'Any PC, including laptops and work computers.',
    'otim.modo.leve.antes': 'Nothing here needs a restart. Everything comes back with Undo.',
    'otim.modo.moderado.faz': 'Everything in Light, plus: network tweaks for a steady ping, CPU priority for the foreground game, HAGS, windowed game optimizations and blocking Store apps in the background.',
    'otim.modo.moderado.quem': 'Desktops used for gaming. It is the recommended mode for most people.',
    'otim.modo.moderado.antes': 'HAGS only takes effect after a restart. With old video drivers, update the driver first.',
    'otim.modo.avancado.faz': 'Everything in Moderate, plus: background services and tasks, bloatware removal (you choose what to keep), OneDrive and Copilot.',
    'otim.modo.avancado.quem': 'People who want a lean Windows and can reinstall an app from the Microsoft Store if needed.',
    'otim.modo.avancado.antes': 'Needs a restart. Removed apps come back from the Microsoft Store, not from Undo.',
    'otim.modo.ultimate.faz': 'Everything in Advanced, plus: tweaks that trade Windows protection layers (such as core isolation) for performance.',
    'otim.modo.ultimate.quem': 'Dedicated gaming PCs, for people who understand the risk of each item.',
    'otim.modo.ultimate.antes': 'Each high-risk item asks for a separate confirmation. Needs a restart.',

    'otim.cat.todos': 'All',
    'otim.cat.geral': 'General',
    'otim.cat.aparencia': 'Appearance',
    'otim.cat.desempenho': 'Performance',
    'otim.cat.privacidade': 'Privacy',
    'otim.cat.jogos': 'Gaming',
    'otim.cat.rede': 'Network',
    'otim.cat.gpu': 'GPU',

    'otim.card.oQueFaz': 'What it does',
    'otim.card.beneficio': 'Benefit',
    'otim.card.atencao': 'Watch out',
    'otim.card.entraNoModo': 'Part of {modo} mode',
    'otim.card.naoSeAplica': 'Does not apply to this PC',
    'otim.card.folclore': 'No evidence of gain. Off by default.',
    'otim.card.saibaMais': 'Learn more',
    'otim.card.porque': 'Why',
    'otim.card.evidencia': 'Evidence',
    'otim.card.folcloreTitulo': 'Why it is among the extras',
    'otim.card.folcloreOQueE': 'What it is',
    'otim.card.folcloreCircula': 'Why it spreads',
    'otim.card.folcloreNao': 'Why we do not recommend it',
    'otim.card.instrucoes': 'Instructions',
    'otim.card.situacao': 'Status',
    'otim.card.estadoAtual': 'Current state',
    'otim.card.estado.sim': 'applied',
    'otim.card.estado.nao': 'not applied',
    'otim.card.estado.nd': 'not checked',
    'otim.card.origem': 'Open the source',
    'otim.card.desfazer': 'Undo',
    'otim.card.desfazerAria': 'Undo {nome}',
    'otim.card.opcao': 'Option',
    'otim.card.escolha': 'Choose…',
    'otim.card.verGuia': 'View guide',
    'otim.card.aplicarSo': 'Apply only this',
    'otim.card.ligarAgora': 'Turn on now',
    'otim.card.desligarAgora': 'Turn off now',
    'otim.card.id': 'ID',

    'otim.selo.risco.baixo': 'Low risk',
    'otim.selo.risco.medio': 'Medium risk',
    'otim.selo.risco.alto': 'High risk',
    'otim.selo.MEDIDO': 'Measured effect',
    'otim.selo.TECNICO': 'Technical effect',
    'otim.selo.FOLCLORE': 'Folklore',
    'otim.selo.total': 'Reversible',
    'otim.selo.parcial': 'Partly reversible',
    'otim.selo.nenhuma': 'Irreversible',
    'otim.selo.reboot': 'Needs restart',
    'otim.selo.semReboot': 'No restart',

    'otim.extras.titulo': 'Extras: outside the modes',
    'otim.extras.texto': 'These tweaks never join a mode: no evidence of gain, no way back, manual guides or they depend on a choice of yours. Turn them on one by one if you want.',

    'otim.barra.modo': '{modo} mode · {ligados}',
    'otim.barra.semModo': '{ligados}',
    'otim.barra.reboot0': 'Nothing needs a restart.',
    'otim.barra.reboot1': '1 needs a restart.',
    'otim.barra.rebootN': '{n} need a restart.',
    'otim.barra.ponto': 'A restore point is created before applying.',
    'otim.barra.ver': 'See what will change',
    'otim.barra.aplicar': 'Apply {modo} mode',
    'otim.barra.aplicarSel': 'Apply selected',

    'otim.ult.titulo': 'Turn on Ultimate mode?',
    'otim.ult.texto': 'Ultimate trades protection for performance. These high-risk tweaks join the selection:',
    'otim.ult.nenhum': 'No high-risk tweak is available on this PC.',
    'otim.ult.consent': 'Each one still asks for a separate confirmation (a phrase) before it is applied. A restore point is created first, and whatever is reversible comes back with Undo.',
    'otim.ult.check': 'I understand the risks and want to see the Ultimate tweaks.',
    'otim.ult.ok': 'Use Ultimate',
    'otim.cancelar': 'Cancel',
    'otim.fechar': 'Close',
    'otim.continuar': 'Continue',

    'otim.bloat.titulo': 'Remove bloatware: what to keep?',
    'otim.bloat.texto': 'Check the apps you want to KEEP. The others, if installed, will be removed. They come back from the Microsoft Store.',
    'otim.bloat.lendo': 'Reading the installed apps…',
    'otim.bloat.nenhum': 'No app from the catalog is installed.',
    'otim.gp.titulo': 'Do you use Xbox Game Pass?',
    'otim.gp.texto': 'If you do, the Xbox app and Game Bar stay installed. The other Microsoft gaming apps are removed.',
    'otim.gp.sim': 'Yes, keep Xbox and Game Bar',
    'otim.gp.nao': 'No, remove them all',

    'otim.previa.titulo': 'Preview: before → after',
    'otim.previa.tituloVer': 'What will change: before → after',
    'otim.previa.texto': 'Check what will change. Before is the value read now; After is the value that will be written.',
    'otim.previa.alvo': 'Target',
    'otim.previa.antes': 'Before',
    'otim.previa.depois': 'After',
    'otim.previa.reversao': 'Undo',
    'otim.previa.confirmar': 'Confirm and apply',
    'otim.previa.semOpcao': 'Left out because no option was chosen: {lista}',
    'otim.consent.titulo': 'Confirmation required: {nome}',
    'otim.consent.tradeoff': 'This tweak asks for a separate confirmation.',
    'otim.consent.digite': 'To unlock it, type exactly:',
    'otim.consent.aria': 'Confirmation phrase for {nome}',
    'otim.consent.ok': 'Confirm phrase',
    'otim.consent.registrado': 'Consent recorded for {id}',
    'otim.consent.errado': 'wrong phrase',

    'otim.res.titulo': 'Apply result',
    'otim.res.resumo': '{a} applied · {j} already applied · {f} failed · {p} skipped',
    'otim.res.reboot': 'Restart Windows so that every tweak takes effect.',
    'otim.res.ajuste': 'Tweak',
    'otim.res.status': 'Status',
    'otim.res.detalhe': 'Detail',
    'otim.aplicando': 'Applying…',
    'otim.revertendo': 'Reverting…',
    'otim.trabalhando': 'Working…',

    'otim.st.aplicado': 'applied',
    'otim.st.aplicadoNaoVerificado': 'applied (not verified)',
    'otim.st.jaAplicado': 'already applied',
    'otim.st.falha': 'failed',
    'otim.st.naoAplicavel': 'not applicable',
    'otim.st.naoSuportado': 'not supported',
    'otim.st.semConsentimento': 'no consent',
    'otim.st.simulado': 'simulated',
    'otim.st.pulado': 'skipped',
    'otim.st.revertido': 'reverted',
    'otim.st.nadaReverter': 'nothing to undo',

    'otim.undo.titulo': 'Undo everything in this session',
    'otim.undo.texto': 'Every tweak applied in this session goes back to its previous value, in reverse order.',
    'otim.undo.botao': 'Undo everything',
    'otim.undo.resumo': '{r} reverted · {f} failed · {p} skipped',
    'otim.undo.tituloSessao': 'Session undo',
    'otim.undo.tituloRun': 'Undo of {id}',
    'otim.undo.run': 'Undo run {id}',
    'otim.undo.runTexto': 'Every record of this run goes back to its previous value.',
    'otim.undo.item': '{id}: {n} record(s) reverted',
    'otim.undo.resultado': 'Result',

    'otim.hist.titulo': 'Run history',
    'otim.hist.texto': 'Each run keeps the previous value of everything it touched. The count is records / applied / reverted.',
    'otim.hist.execucao': 'Run',
    'otim.hist.criada': 'Created at',
    'otim.hist.contagem': 'Rec. / appl. / rev.',
    'otim.hist.atual': 'current',
    'otim.hist.nenhuma': 'No run recorded.',
    'otim.hist.terminal': 'Undo from the terminal',
    'otim.hist.copiar': 'Copy command',
    'otim.hist.copiado': 'Command copied',
    'otim.hist.naoCopiou': 'Could not copy',

    'otim.toast.modo': '{modo} mode selected',
    'otim.toast.nenhum': 'No tweak selected',
    'otim.toast.escolhaOpcao': 'Choose an option before applying',
    'otim.toast.ligado': '{id} turned on',
    'otim.toast.desligado': '{id} turned off',
    'otim.toast.selecao': 'could not change the selection',
    'otim.toast.opcao': 'invalid option'
  };

  if (window.tmx && tmx.i18n) {
    tmx.i18n.add('pt-BR', TXT_PT);
    tmx.i18n.add('en', TXT_EN);
  }

  function t(chave, vars) {
    if (window.tmx && tmx.i18n) { return tmx.i18n.t(chave, vars); }
    var s = TXT_PT[chave] || chave;
    if (vars) { s = s.replace(/\{(\w+)\}/g, function (m, n) { return vars[n] === undefined ? m : String(vars[n]); }); }
    return s;
  }

  function lang() { return (window.tmx && tmx.i18n && tmx.i18n.lang) || 'pt-BR'; }

  /* ---------------- estado ---------------- */

  var MODOS = ['leve', 'moderado', 'avancado', 'ultimate'];
  var CATEGORIAS = ['geral', 'aparencia', 'desempenho', 'privacidade', 'jogos', 'rede', 'gpu'];
  var MODO_PADRAO = 'moderado';

  var estado = {
    dados: null,        // payload de catalog.get / mode.select
    preset: MODO_PADRAO,
    aplicado: '',       // appliedMode salvo nas configurações
    busca: '',
    filtro: 'todos',
    acoes: {},          // id -> { status } (resultado da última ação)
    ocupado: false
  };

  // Pendências de consentimento do modal de prévia aberto no momento. O
  // ouvinte de #modal-body é instalado UMA vez (ligarOuvinteModal): o
  // elemento sobrevive a todo modal.open().
  var pendentesConsentimento = [];

  var ICONE_BUSCA = '<svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" ' +
    'stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' +
    '<circle cx="11" cy="11" r="8"></circle><path d="m21 21-4.3-4.3"></path></svg>';

  /* ---------------- utilitários ---------------- */

  function esc(s) {
    return String(s === null || s === undefined ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }

  function idxModo(m) { return MODOS.indexOf(m); }
  function ehModo(m) { return idxModo(m) >= 0; }
  function nomeModo(m) { return t('otim.modo.' + (m || 'extras')); }

  /* Texto localizado de um campo do tweak: i18n.en quando o idioma é inglês e
     a tradução existe; senão o campo em pt-BR. */
  function tx(item, campo) {
    if (lang() === 'en' && item.i18n && item.i18n.en && item.i18n.en[campo]) { return item.i18n.en[campo]; }
    return item[campo] || '';
  }

  function rotuloStatus(status) {
    var k = 'otim.st.' + status;
    var r = t(k);
    return r === k ? status : r;
  }

  function classeStatus(status) {
    if (status === 'aplicado' || status === 'aplicadoNaoVerificado' || status === 'jaAplicado') { return 'estado-ok'; }
    if (status === 'revertido') { return 'estado-undo'; }
    if (status === 'falha') { return 'estado-falha'; }
    return 'estado-pulado';
  }

  function textoLigados(n) { return n === 1 ? t('otim.ligados.1') : t('otim.ligados.n', { n: n }); }

  function copiarTexto(texto) {
    // O WebView2 nega navigator.clipboard sem gesto reconhecido; o textarea
    // fora da tela + execCommand continua funcionando.
    var ta = document.createElement('textarea');
    ta.value = texto;
    ta.setAttribute('readonly', '');
    ta.style.position = 'fixed';
    ta.style.left = '-9999px';
    document.body.appendChild(ta);
    ta.select();
    var ok = false;
    try { ok = document.execCommand('copy'); } catch (e) { ok = false; }
    document.body.removeChild(ta);
    tmx.toast(ok ? t('otim.hist.copiado') : t('otim.hist.naoCopiou'), ok ? 'ok' : 'erro');
  }

  /* ---------------- ponte: jobs ---------------- */

  /* Dispara uma ação que roda no pool e resolve com o resultado do job.done
     correspondente (correlacionado pelo jobId). onProgresso recebe { pct, status }. */
  function chamarJob(nome, payload, onProgresso) {
    // callComEspera: o slot de job pode estar com uma carga de outra aba; a
    // ação do usuário espera em vez de falhar.
    return tmx.bridge.callComEspera(nome, payload).then(function (resp) {
      var jobId = resp && resp.jobId;
      if (!jobId) { return resp; }
      return new Promise(function (resolve, reject) {
        var aoProgredir = tmx.bridge.on('job.progress', function (p) {
          if (!p || p.jobId !== jobId) { return; }
          if (typeof onProgresso === 'function') { onProgresso(p); }
        });
        var aoTerminar = tmx.bridge.on('job.done', function (p) {
          if (!p || p.jobId !== jobId) { return; }
          tmx.bridge.off('job.progress', aoProgredir);
          tmx.bridge.off('job.done', aoTerminar);
          if (p.ok) { resolve(p.result); }
          else { reject(new Error((p.error && p.error.message) || 'o trabalho falhou')); }
        });
      });
    });
  }

  /* ---------------- coleta de itens ---------------- */

  /* Itens desenhados nesta aba. Os de controle 'radio' (política do Windows
     Update) moram em Sistema › Atualizações e ficam fora daqui: são um grupo
     de escolha única e não somam num modo. */
  function todosItens() {
    var fora = [];
    var cats = (estado.dados && estado.dados.categorias) || [];
    for (var i = 0; i < cats.length; i++) {
      var itens = cats[i].itens || [];
      for (var j = 0; j < itens.length; j++) {
        if (itens[j].controle !== 'radio') { fora.push(itens[j]); }
      }
    }
    return fora;
  }

  function acharItem(id) {
    var todos = todosItens();
    for (var i = 0; i < todos.length; i++) { if (todos[i].id === id) { return todos[i]; } }
    return null;
  }

  function selecionaveis() {
    return todosItens().filter(function (x) { return x.selecionado && x.controle !== 'info'; });
  }

  function idsSelecionados() { return selecionaveis().map(function (x) { return x.id; }); }

  function modoDoItem(item) { return ehModo(item.modo) ? item.modo : 'extras'; }

  function acimaDoModo(item) {
    var atual = idxModo(estado.preset);
    var m = idxModo(item.modo);
    return atual >= 0 && m > atual;
  }

  /* ---------------- esqueleto ---------------- */

  function montarEsqueleto() {
    var raiz = document.getElementById('tab-otimizacoes');
    var modos = MODOS.map(function (m, i) {
      var barras = '';
      for (var b = 0; b < 4; b++) { barras += '<span class="' + (b <= i ? 'on' : '') + '"></span>'; }
      return '<button type="button" class="otim-modo otim-modo-' + m + '" id="tw-modo-' + m + '" data-modo="' + m + '" ' +
               'role="radio" aria-checked="false">' +
               '<span class="otim-modo-topo"><span class="otim-modo-nome" data-i18n="otim.modo.' + m + '"></span>' +
                 '<span class="otim-barras" aria-hidden="true">' + barras + '</span></span>' +
               '<span class="otim-modo-desc" data-i18n="otim.modo.' + m + '.desc"></span>' +
               '<span class="otim-modo-tags">' +
                 '<span class="selo selo-risco-' + (i < 2 ? 'baixo' : (i === 2 ? 'medio' : 'alto')) + '" data-i18n="otim.selo.risco.' +
                   (i < 2 ? 'baixo' : (i === 2 ? 'medio' : 'alto')) + '"></span>' +
                 '<span class="selo selo-neutro" data-i18n="otim.modo.' + m + '.reinicio"></span>' +
                 '<span class="selo selo-aplicado" data-aplicado="' + m + '" data-i18n="otim.modo.aplicado" hidden></span>' +
               '</span>' +
             '</button>';
    }).join('');

    var chips = ['todos'].concat(CATEGORIAS).map(function (c) {
      return '<button type="button" class="otim-chip" data-filtro="' + c + '" aria-pressed="' +
             (c === estado.filtro ? 'true' : 'false') + '" data-i18n="otim.cat.' + c + '"></button>';
    }).join('');

    raiz.innerHTML =
      '<div class="otim">' +
        '<header class="otim-topo">' +
          '<div class="otim-titulos">' +
            '<p class="otim-eyebrow" data-i18n="otim.eyebrow"></p>' +
            '<h2 class="otim-h" data-i18n="otim.titulo"></h2>' +
            '<p class="otim-sub" data-i18n="otim.subtitulo"></p>' +
          '</div>' +
          '<div class="otim-topo-acoes">' +
            '<button type="button" class="otim-link" id="tw-historico" data-i18n="otim.historico"></button>' +
            '<button type="button" class="otim-link" id="tw-undo-sessao" data-i18n="otim.undoSessao"></button>' +
            '<span class="otim-pill" id="tw-ligados" data-n="0" aria-live="polite">—</span>' +
          '</div>' +
        '</header>' +
        '<div class="otim-modos" role="radiogroup" id="tw-modos">' + modos + '</div>' +
        '<section class="otim-explica" id="tw-explica" aria-live="polite"></section>' +
        '<label class="otim-busca">' + ICONE_BUSCA +
          '<input type="search" id="tw-busca" data-i18n-placeholder="otim.busca" autocomplete="off" spellcheck="false">' +
        '</label>' +
        '<div class="otim-ferramentas">' +
          '<div class="otim-chips" role="group" id="tw-filtros">' + chips + '</div>' +
          '<button type="button" class="otim-link" id="tw-limpar" data-i18n="otim.limpar"></button>' +
        '</div>' +
        '<div id="tw-categorias"><p class="vazio" data-i18n="otim.carregando"></p></div>' +
        '<div class="otim-barra" id="tw-barra-fixa">' +
          '<div class="otim-barra-texto">' +
            '<strong id="tw-resumo-modo">—</strong>' +
            '<span id="tw-resumo-nota"></span>' +
          '</div>' +
          '<div class="otim-barra-botoes">' +
            '<button type="button" class="btn otim-btn-sec" id="tw-ver" data-i18n="otim.barra.ver" disabled></button>' +
            '<button type="button" class="btn btn-primary otim-btn-pri" id="tw-aplicar" disabled></button>' +
          '</div>' +
        '</div>' +
      '</div>';

    if (tmx.i18n) { tmx.i18n.apply(raiz); }
    var busca = document.getElementById('tw-busca');
    rotularAcessibilidade();

    busca.addEventListener('input', function (e) {
      estado.busca = String(e.target.value || '').toLowerCase();
      filtrar();
    });
    document.getElementById('tw-filtros').addEventListener('click', function (e) {
      var b = e.target.closest ? e.target.closest('[data-filtro]') : null;
      if (!b) { return; }
      estado.filtro = b.getAttribute('data-filtro');
      var todos = document.querySelectorAll('#tw-filtros [data-filtro]');
      for (var i = 0; i < todos.length; i++) {
        todos[i].setAttribute('aria-pressed', todos[i] === b ? 'true' : 'false');
      }
      filtrar();
    });
    document.getElementById('tw-limpar').addEventListener('click', limparSelecao);
    document.getElementById('tw-aplicar').addEventListener('click', function () {
      iniciarAplicacao(idsSelecionados(), { titulo: t('otim.previa.titulo') });
    });
    document.getElementById('tw-ver').addEventListener('click', function () {
      iniciarAplicacao(idsSelecionados(), { titulo: t('otim.previa.tituloVer') });
    });
    document.getElementById('tw-undo-sessao').addEventListener('click', confirmarUndoSessao);
    document.getElementById('tw-historico').addEventListener('click', abrirHistorico);

    MODOS.forEach(function (m) {
      document.getElementById('tw-modo-' + m).addEventListener('click', function () { pedirModo(m); });
    });

    var lista = document.getElementById('tw-categorias');
    lista.addEventListener('click', aoClicarNaLista);
    lista.addEventListener('change', aoMudarNaLista);
  }

  function rotularAcessibilidade() {
    var pares = [['tw-busca', 'otim.busca'], ['tw-modos', 'otim.modos'], ['tw-filtros', 'otim.filtros']];
    pares.forEach(function (p) {
      var el = document.getElementById(p[0]);
      if (el) { el.setAttribute('aria-label', t(p[1])); }
    });
  }

  /* ---------------- desenho ---------------- */

  function selosDe(item) {
    var risco = item.risco || 'baixo';
    var html = '<span class="selo selo-risco-' + esc(risco) + '">' + esc(t('otim.selo.risco.' + risco)) + '</span>';
    if (item.tier === 'MEDIDO') { html += '<span class="selo selo-medido">' + esc(t('otim.selo.MEDIDO')) + '</span>'; }
    else if (item.tier === 'TECNICO') { html += '<span class="selo selo-neutro selo-tecnico">' + esc(t('otim.selo.TECNICO')) + '</span>'; }
    else if (item.tier === 'FOLCLORE') { html += '<span class="selo selo-folclore">' + esc(t('otim.selo.FOLCLORE')) + '</span>'; }

    if (item.reversivel === 'nenhuma') { html += '<span class="selo selo-irreversivel">' + esc(t('otim.selo.nenhuma')) + '</span>'; }
    else if (item.reversivel === 'parcial') { html += '<span class="selo selo-parcial">' + esc(t('otim.selo.parcial')) + '</span>'; }
    else { html += '<span class="selo selo-neutro">' + esc(t('otim.selo.total')) + '</span>'; }

    html += '<span class="selo selo-neutro' + (item.requerReboot ? ' selo-reboot' : '') + '">' +
            esc(t(item.requerReboot ? 'otim.selo.reboot' : 'otim.selo.semReboot')) + '</span>';
    return html;
  }

  function blocosSaibaMais(item) {
    var html = '<div class="tw-bloco"><h4>' + esc(t('otim.card.porque')) + '</h4><p>' + esc(item.porque) + '</p></div>' +
               '<div class="tw-bloco"><h4>' + esc(t('otim.card.evidencia')) + '</h4><p>' + esc(item.evidencia) + '</p></div>';
    if (item.folclore) {
      html += '<div class="tw-consentimento">' +
                '<h4>' + esc(t('otim.card.folcloreTitulo')) + '</h4>' +
                '<div class="tw-bloco"><h4>' + esc(t('otim.card.folcloreOQueE')) + '</h4><p>' + esc(item.folclore.oQueE) + '</p></div>' +
                '<div class="tw-bloco"><h4>' + esc(t('otim.card.folcloreCircula')) + '</h4><p>' + esc(item.folclore.porqueCircula) + '</p></div>' +
                '<div class="tw-bloco"><h4>' + esc(t('otim.card.folcloreNao')) + '</h4><p>' +
                  esc(item.folclore.porqueNaoRecomendamos) + '</p></div>' +
              '</div>';
    }
    if (item.instrucoes) {
      html += '<div class="tw-bloco"><h4>' + esc(t('otim.card.instrucoes')) + '</h4><p>' + esc(item.instrucoes) + '</p></div>';
    }
    if ((item.motivos || []).length) {
      html += '<div class="tw-bloco"><h4>' + esc(t('otim.card.situacao')) + '</h4><p>' + esc(item.motivos.join(' · ')) + '</p></div>';
    }
    var est = item.estadoAtual === true ? 'sim' : (item.estadoAtual === false ? 'nao' : 'nd');
    html += '<div class="tw-bloco"><h4>' + esc(t('otim.card.estadoAtual')) + '</h4><p>' + esc(t('otim.card.estado.' + est)) +
            ' · <span class="tw-id">' + esc(item.id) + '</span></p></div>';
    return html;
  }

  function botoesSaibaMais(item) {
    var html = '';
    if (item.controle === 'toggle' && item.alternavel) {
      html += '<button type="button" class="btn btn-mini" data-acao="toggle-agora" data-ligar="' +
              (item.estadoAtual === true ? '0' : '1') + '">' +
              esc(t(item.estadoAtual === true ? 'otim.card.desligarAgora' : 'otim.card.ligarAgora')) + '</button>';
    }
    if (item.alternavel && item.controle !== 'info') {
      html += '<button type="button" class="btn btn-mini" data-acao="aplicar-item">' + esc(t('otim.card.aplicarSo')) + '</button>';
    }
    if (item.origem && item.origem.link) {
      html += '<button type="button" class="btn btn-mini" data-acao="origem">' + esc(t('otim.card.origem')) + '</button>';
    }
    return html ? '<p class="tw-mais-botoes">' + html + '</p>' : '';
  }

  function controleDe(item) {
    var nome = tx(item, 'nome');
    if (item.controle === 'info') {
      return '<button type="button" class="btn btn-mini" data-acao="info" id="tw-' + esc(item.id) + '">' +
             esc(t('otim.card.verGuia')) + '</button>';
    }
    var travado = !item.alternavel || acimaDoModo(item) || estado.ocupado;
    return '<button type="button" class="tw-switch" role="switch" id="tw-' + esc(item.id) + '" data-acao="selecao" ' +
           'aria-checked="' + (item.selecionado ? 'true' : 'false') + '" aria-label="' + esc(nome) + '"' +
           (travado ? ' disabled' : '') + '></button>';
  }

  function cardHtml(item) {
    var modo = modoDoItem(item);
    var acima = acimaDoModo(item);
    var classes = ['tweak', 'otim-card'];
    if (acima) { classes.push('is-acima'); }
    if (item.tier === 'FOLCLORE') { classes.push('tw-folclore'); }
    if (item.status === 'bloqueado') { classes.push('tw-bloqueado'); }
    if (item.selecionado) { classes.push('is-ligado'); }

    var tags = (item.categoriasV2 || []).map(function (c) {
      return '<span class="otim-tag">' + esc(t('otim.cat.' + c)) + '</span>';
    }).join('');
    tags += '<span class="otim-tag otim-tag-modo otim-tag-' + esc(modo) + '">' +
            esc(modo === 'extras' ? nomeModo('extras') : t('otim.modoTag', { modo: nomeModo(modo) })) + '</span>';

    var oQueFaz = tx(item, 'oQueFaz') || tx(item, 'descricao');
    var beneficio = tx(item, 'beneficio');
    var atencao = tx(item, 'atencao');

    var corpo = '<div class="otim-rotulo">' + esc(t('otim.card.oQueFaz')) + '</div><p>' + esc(oQueFaz) + '</p>';
    if (beneficio) { corpo += '<div class="otim-rotulo otim-rotulo-beneficio">' + esc(t('otim.card.beneficio')) + '</div><p>' + esc(beneficio) + '</p>'; }
    if (atencao) { corpo += '<div class="otim-rotulo otim-rotulo-atencao">' + esc(t('otim.card.atencao')) + '</div><p>' + esc(atencao) + '</p>'; }

    var aviso = '';
    var titulo = '';
    if (item.status === 'bloqueado') {
      aviso = t('otim.card.naoSeAplica') + ((item.motivos || []).length ? ': ' + item.motivos.join(' · ') : '');
    } else if (acima) {
      aviso = t('otim.card.entraNoModo', { modo: nomeModo(modo) });
    } else if (item.tier === 'FOLCLORE') {
      aviso = t('otim.card.folclore');
      titulo = aviso;
    }

    var opcao = '';
    if (item.controle === 'combobox') {
      var opcoes = (item.opcoes || []).map(function (o) {
        return '<option value="' + esc(o.valor) + '"' + (o.valor === item.opcaoSelecionada ? ' selected' : '') + '>' +
               esc(o.rotulo) + '</option>';
      }).join('');
      opcao = '<label class="otim-opcao"><span>' + esc(t('otim.card.opcao')) + '</span>' +
              '<select class="tw-opcoes campo" data-acao="opcao"' + (acima ? ' disabled' : '') + '>' +
              '<option value="">' + esc(t('otim.card.escolha')) + '</option>' + opcoes + '</select></label>';
    }

    var chip = estado.acoes[item.id];
    var estadoHtml = chip ? '<span class="estado ' + classeStatus(chip.status) + '">' +
      esc(chip.status === 'nadaReverter' ? t('otim.st.nadaReverter') : rotuloStatus(chip.status)) + '</span>' : '';
    var undo = item.temUndo
      ? '<button type="button" class="btn btn-mini tw-undo" data-acao="undo" aria-label="' +
        esc(t('otim.card.desfazerAria', { nome: tx(item, 'nome') })) + '">' + esc(t('otim.card.desfazer')) + '</button>'
      : '';

    return '<article class="' + classes.join(' ') + '" data-id="' + esc(item.id) + '"' +
             (titulo ? ' title="' + esc(titulo) + '"' : '') + '>' +
             '<div class="otim-card-topo"><div class="otim-tags">' + tags + '</div>' +
               '<span class="tw-controle">' + controleDe(item) + '</span></div>' +
             '<h3 class="tw-nome">' + esc(tx(item, 'nome')) + '</h3>' +
             '<div class="otim-card-corpo">' + corpo + '</div>' +
             (aviso ? '<p class="tw-motivo">' + esc(aviso) + '</p>' : '') +
             opcao +
             '<details class="tw-mais"><summary>' + esc(t('otim.card.saibaMais')) + '</summary>' +
               blocosSaibaMais(item) + botoesSaibaMais(item) + '</details>' +
             '<div class="otim-card-pe"><div class="tw-badges">' + selosDe(item) + '</div>' +
               '<div class="tw-acoes">' + estadoHtml + undo + '</div></div>' +
           '</article>';
  }

  /* Ordem: os do modo atual (do mais leve ao mais pesado), depois os acima do
     modo, e por fim os extras numa seção à parte. */
  function ordenar(itens) {
    return itens.slice().sort(function (a, b) {
      var ma = idxModo(a.modo), mb = idxModo(b.modo);
      if (ma !== mb) { return ma - mb; }
      return 0;
    });
  }

  function render() {
    var alvo = document.getElementById('tw-categorias');
    if (!alvo) { return; }
    var todos = todosItens();
    if (!todos.length) {
      alvo.innerHTML = '<p class="vazio">' + esc(t('otim.vazio')) + '</p>';
      atualizarResumo();
      return;
    }

    var doModo = ordenar(todos.filter(function (x) { return ehModo(x.modo); }));
    var extras = todos.filter(function (x) { return !ehModo(x.modo); });

    alvo.innerHTML =
      '<div class="otim-grid" id="tw-grid-modos">' + doModo.map(cardHtml).join('') + '</div>' +
      '<section class="otim-extras" id="tw-extras"' + (extras.length ? '' : ' hidden') + '>' +
        '<h3 class="otim-sec">' + esc(t('otim.extras.titulo')) + '</h3>' +
        '<p class="otim-sec-texto">' + esc(t('otim.extras.texto')) + '</p>' +
        '<div class="otim-grid">' + extras.map(cardHtml).join('') + '</div>' +
      '</section>' +
      '<p class="vazio" id="tw-nada" hidden>' + esc(t('otim.nenhumFiltro')) + '</p>';

    pintarModos();
    atualizarResumo();
    filtrar();
  }

  function pintarModos() {
    MODOS.forEach(function (m) {
      var b = document.getElementById('tw-modo-' + m);
      if (!b) { return; }
      b.setAttribute('aria-checked', m === estado.preset ? 'true' : 'false');
      b.disabled = estado.ocupado;
      var sel = b.querySelector('[data-aplicado]');
      if (sel) { sel.hidden = (estado.aplicado !== m); }
    });

    var ex = document.getElementById('tw-explica');
    if (!ex) { return; }
    var m2 = ehModo(estado.preset) ? estado.preset : MODO_PADRAO;
    ex.innerHTML =
      '<div><h4 class="otim-rotulo">' + esc(t('otim.explica.faz', { modo: nomeModo(m2) })) + '</h4>' +
        '<p>' + esc(t('otim.modo.' + m2 + '.faz')) + '</p></div>' +
      '<div><h4 class="otim-rotulo">' + esc(t('otim.explica.quem')) + '</h4>' +
        '<p>' + esc(t('otim.modo.' + m2 + '.quem')) + '</p></div>' +
      '<div><h4 class="otim-rotulo otim-rotulo-atencao">' + esc(t('otim.explica.antes')) + '</h4>' +
        '<p>' + esc(t('otim.modo.' + m2 + '.antes')) + '</p></div>';
  }

  function atualizarResumo() {
    var sel = selecionaveis();
    var n = sel.length;
    var reboot = sel.filter(function (x) { return x.requerReboot; }).length;

    var pill = document.getElementById('tw-ligados');
    if (pill) { pill.textContent = textoLigados(n); pill.setAttribute('data-n', String(n)); }

    var resumo = document.getElementById('tw-resumo-modo');
    if (resumo) {
      resumo.textContent = ehModo(estado.preset)
        ? t('otim.barra.modo', { modo: nomeModo(estado.preset), ligados: textoLigados(n) })
        : t('otim.barra.semModo', { ligados: textoLigados(n) });
    }
    var nota = document.getElementById('tw-resumo-nota');
    if (nota) {
      var r = reboot === 0 ? t('otim.barra.reboot0') : (reboot === 1 ? t('otim.barra.reboot1') : t('otim.barra.rebootN', { n: reboot }));
      nota.textContent = r + ' ' + t('otim.barra.ponto');
    }

    var aplicar = document.getElementById('tw-aplicar');
    if (aplicar) {
      aplicar.textContent = ehModo(estado.preset) ? t('otim.barra.aplicar', { modo: nomeModo(estado.preset) }) : t('otim.barra.aplicarSel');
      aplicar.disabled = (n === 0) || estado.ocupado;
    }
    var ver = document.getElementById('tw-ver');
    if (ver) { ver.disabled = (n === 0) || estado.ocupado; }
  }

  function casaBusca(item, termo) {
    if (!termo) { return true; }
    var campos = [item.id, item.nome, item.descricao, item.oQueFaz, item.beneficio, item.categoria];
    if (item.i18n && item.i18n.en) {
      campos.push(item.i18n.en.nome, item.i18n.en.oQueFaz, item.i18n.en.beneficio);
    }
    (item.categoriasV2 || []).forEach(function (c) { campos.push(t('otim.cat.' + c)); });
    for (var i = 0; i < campos.length; i++) {
      if (campos[i] && String(campos[i]).toLowerCase().indexOf(termo) >= 0) { return true; }
    }
    return false;
  }

  function filtrar() {
    var termo = estado.busca;
    var filtro = estado.filtro;
    var cards = document.querySelectorAll('#tw-categorias .tweak');
    var visiveisExtras = 0, visiveis = 0;
    for (var i = 0; i < cards.length; i++) {
      var item = acharItem(cards[i].getAttribute('data-id'));
      var ok = !!item && casaBusca(item, termo) &&
               (filtro === 'todos' || (item.categoriasV2 || []).indexOf(filtro) >= 0);
      cards[i].hidden = !ok;
      if (ok) {
        visiveis++;
        if (!ehModo(item.modo)) { visiveisExtras++; }
      }
    }
    var ex = document.getElementById('tw-extras');
    if (ex) { ex.hidden = visiveisExtras === 0; }
    var nada = document.getElementById('tw-nada');
    if (nada) { nada.hidden = visiveis > 0 || cards.length === 0; }
  }

  /* ---------------- carregamento e modo ---------------- */

  function ocupar(valor) {
    estado.ocupado = !!valor;
    var secao = document.getElementById('tab-otimizacoes');
    if (secao) { secao.setAttribute('aria-busy', valor ? 'true' : 'false'); }
    ['tw-limpar', 'tw-undo-sessao', 'tw-historico'].forEach(function (id) {
      var b = document.getElementById(id);
      if (b) { b.disabled = !!valor; }
    });
    var sw = document.querySelectorAll('#tw-categorias .tw-switch');
    for (var i = 0; i < sw.length; i++) {
      var item = acharItem((sw[i].id || '').replace(/^tw-/, ''));
      sw[i].disabled = !!valor || !item || !item.alternavel || acimaDoModo(item);
    }
    pintarModos();
    atualizarResumo();
  }

  function aplicarPayload(payload) {
    if (!payload) { return; }
    estado.dados = payload;
    estado.preset = payload.preset || estado.preset;
    render();
  }

  function lerModoSalvo() {
    return tmx.bridge.call('settings.get').then(function (s) {
      estado.aplicado = (s && ehModo(s.appliedMode)) ? s.appliedMode : '';
      return estado.aplicado || MODO_PADRAO;
    }).catch(function () { return MODO_PADRAO; });
  }

  function carregar() {
    ocupar(true);
    return lerModoSalvo().then(function (modo) {
      return chamarJob('catalog.get', { preset: modo });
    }).then(function (r) {
      aplicarPayload(r);
      ocupar(false);
    }).catch(function (e) {
      ocupar(false);
      var alvo = document.getElementById('tw-categorias');
      if (alvo) { alvo.innerHTML = '<p class="vazio">' + esc(t('otim.erroCatalogo', { msg: e.message })) + '</p>'; }
      tmx.toast(t('otim.erroCatalogo', { msg: e.message }), 'erro');
      // Repropaga: tabs.show precisa SABER que a carga falhou para tentar de
      // novo na próxima abertura.
      throw e;
    });
  }

  function pedirModo(modo) {
    if (estado.ocupado || !ehModo(modo)) { return; }
    if (modo === 'ultimate' && estado.preset !== 'ultimate') { confirmarUltimate(); return; }
    trocarModo(modo);
  }

  function trocarModo(modo) {
    ocupar(true);
    chamarJob('mode.select', { mode: modo }).then(function (r) {
      aplicarPayload(r);
      ocupar(false);
      tmx.toast(t('otim.toast.modo', { modo: nomeModo(modo) }), 'ok');
    }).catch(function (e) {
      ocupar(false);
      tmx.toast(e.message, 'erro');
    });
  }

  /* Confirmação separada do Ultimate: lista os ajustes de risco alto que o
     modo vai somar e só libera o botão com a caixa marcada. */
  function confirmarUltimate() {
    var altos = todosItens().filter(function (x) {
      return x.modo === 'ultimate' && x.risco === 'alto' && x.status !== 'bloqueado';
    });
    var lista = altos.length
      ? '<ul class="otim-ult-lista">' + altos.map(function (x) {
          return '<li><strong>' + esc(tx(x, 'nome')) + '</strong>' +
                 (tx(x, 'atencao') ? '<span>' + esc(tx(x, 'atencao')) + '</span>' : '') + '</li>';
        }).join('') + '</ul>'
      : '<p>' + esc(t('otim.ult.nenhum')) + '</p>';

    tmx.modal.open({
      titulo: t('otim.ult.titulo'),
      html: '<div class="otim-ult" id="tw-ult">' +
              '<p>' + esc(t('otim.ult.texto')) + '</p>' + lista +
              '<p class="otim-ult-nota">' + esc(t('otim.ult.consent')) + '</p>' +
              '<label class="otim-check"><input type="checkbox" id="tw-ult-check"> <span>' + esc(t('otim.ult.check')) + '</span></label>' +
            '</div>',
      botoes: [
        { rotulo: t('otim.ult.ok'), classe: 'btn-danger', onClick: function () { trocarModo('ultimate'); } },
        { rotulo: t('otim.cancelar') }
      ]
    });

    var ok = document.querySelector('#modal-buttons .btn-danger');
    if (ok) { ok.disabled = true; ok.id = 'tw-ult-ok'; }
    var check = document.getElementById('tw-ult-check');
    if (check) {
      check.addEventListener('change', function () { if (ok) { ok.disabled = !check.checked; } });
      check.focus();
    }
  }

  function limparSelecao() {
    var ids = idsSelecionados();
    if (!ids.length) { return; }
    ocupar(true);
    Promise.all(ids.map(function (id) {
      return tmx.bridge.call('plan.setSelection', { id: id, selecionado: false }).then(function (r) {
        var item = acharItem(id);
        if (item && r && r.ok) { item.selecionado = false; }
      }).catch(function () { });
    })).then(function () {
      ocupar(false);
      render();
    });
  }

  /* ---------------- eventos da lista ---------------- */

  function cardDe(el) {
    while (el && el !== document) {
      if (el.classList && el.classList.contains('tweak')) { return el; }
      el = el.parentNode;
    }
    return null;
  }

  function alvoComAcao(el) {
    while (el && el !== document) {
      if (el.getAttribute && el.getAttribute('data-acao')) { return el; }
      if (el.classList && el.classList.contains('tweak')) { return null; }
      el = el.parentNode;
    }
    return null;
  }

  function aoMudarNaLista(ev) {
    var alvo = ev.target;
    if (!alvo || !alvo.getAttribute || alvo.getAttribute('data-acao') !== 'opcao') { return; }
    var card = cardDe(alvo);
    if (!card) { return; }
    var id = card.getAttribute('data-id');
    var valor = alvo.value;
    if (!valor) { return; }
    tmx.bridge.call('plan.setOption', { id: id, valor: valor }).then(function (r) {
      if (!r || !r.ok) { tmx.toast((r && r.mensagem) || t('otim.toast.opcao'), 'aviso'); return; }
      var item = acharItem(id);
      if (item) { item.opcaoSelecionada = valor; }
    }).catch(function (e) { tmx.toast(e.message, 'erro'); });
  }

  function aoClicarNaLista(ev) {
    var alvo = alvoComAcao(ev.target);
    var card = cardDe(ev.target);
    if (!alvo || !card) { return; }
    var acao = alvo.getAttribute('data-acao');
    var id = card.getAttribute('data-id');

    if (acao === 'selecao') { alternarSelecao(id, alvo); return; }
    if (acao === 'info') { abrirGuia(id); return; }
    if (acao === 'undo') { desfazerItem(id); return; }
    if (acao === 'aplicar-item') { aplicarItemUnico(id); return; }
    if (acao === 'toggle-agora') { alternarAgora(id, alvo.getAttribute('data-ligar') === '1'); return; }
    if (acao === 'origem') {
      var item = acharItem(id);
      if (item && item.origem && item.origem.link) {
        tmx.bridge.call('shell.openUrl', { url: item.origem.link }).catch(function (e) { tmx.toast(e.message, 'erro'); });
      }
    }
  }

  function alternarSelecao(id, botao) {
    if (botao.disabled || estado.ocupado) { return; }
    var ligar = botao.getAttribute('aria-checked') !== 'true';
    botao.disabled = true;
    tmx.bridge.call('plan.setSelection', { id: id, selecionado: ligar }).then(function (r) {
      botao.disabled = false;
      if (!r || !r.ok) {
        tmx.toast((r && r.mensagem) || t('otim.toast.selecao'), 'aviso');
        return;
      }
      var item = acharItem(id);
      if (item) { item.selecionado = ligar; }
      botao.setAttribute('aria-checked', ligar ? 'true' : 'false');
      var card = cardDe(botao);
      if (card) { card.classList.toggle('is-ligado', ligar); }
      atualizarResumo();
    }).catch(function (e) {
      botao.disabled = false;
      tmx.toast(e.message, 'erro');
    });
  }

  function abrirGuia(id) {
    var item = acharItem(id);
    if (!item) { return; }
    var html = '<p class="tw-titulo">' + selosDe(item) + '</p>' +
               '<div class="tw-bloco"><h4>' + esc(t('otim.card.oQueFaz')) + '</h4><p>' +
                 esc(tx(item, 'oQueFaz') || tx(item, 'descricao')) + '</p></div>' +
               blocosSaibaMais(item);
    var botoes = [{ rotulo: t('otim.fechar') }];
    if (item.origem && item.origem.link) {
      botoes.unshift({
        rotulo: t('otim.card.origem'),
        mantemAberto: true,
        onClick: function () {
          tmx.bridge.call('shell.openUrl', { url: item.origem.link }).catch(function (e) { tmx.toast(e.message, 'erro'); });
        }
      });
    }
    tmx.modal.open({ titulo: tx(item, 'nome'), html: html, botoes: botoes });
  }

  /* ---------------- aplicação ---------------- */

  function aplicarItemUnico(id) {
    var item = acharItem(id);
    if (!item) { return; }
    if (item.controle === 'combobox' && !item.opcaoSelecionada) {
      tmx.toast(t('otim.toast.escolhaOpcao'), 'aviso');
      return;
    }
    tmx.bridge.call('plan.setSelection', { id: id, selecionado: true }).then(function (r) {
      if (r && r.ok) { item.selecionado = true; }
      iniciarAplicacao([id], { titulo: t('otim.previa.titulo') });
    }).catch(function (e) { tmx.toast(e.message, 'erro'); });
  }

  function alternarAgora(id, ligar) {
    tmx.session.ensure().then(function (ok) {
      if (!ok) { return null; }
      ocupar(true);
      return chamarJob('plan.applyToggle', { id: id, ligado: ligar }).then(function (r) {
        ocupar(false);
        var linha = (r && r.resultado && r.resultado.itens && r.resultado.itens[0]) || null;
        if (linha) { estado.acoes[id] = { status: linha.status }; }
        if (r && r.catalogo) { aplicarPayload(r.catalogo); }
        tmx.toast(t(ligar ? 'otim.toast.ligado' : 'otim.toast.desligado', { id: id }), 'ok');
      });
    }).catch(function (e) {
      ocupar(false);
      tmx.toast(e.message, 'erro');
    });
  }

  /* Perguntas que precisam de resposta ANTES da prévia (spec 7):
     APM-006 (o que manter do bloatware) e APM-007 (usa Game Pass?). Resolve
     true para seguir; false se a pessoa cancelou. */
  function perguntarAntes(ids) {
    var passos = [];
    if (ids.indexOf('APM-006') >= 0) { passos.push(perguntarBloatware); }
    if (ids.indexOf('APM-007') >= 0) { passos.push(perguntarGamePass); }
    return passos.reduce(function (p, passo) {
      return p.then(function (seguir) { return seguir ? passo() : false; });
    }, Promise.resolve(true));
  }

  function perguntarBloatware() {
    return new Promise(function (resolve) {
      var decidido = false;
      function fim(v) { if (!decidido) { decidido = true; resolve(v); } }

      tmx.modal.open({
        titulo: t('otim.bloat.titulo'),
        html: '<p>' + esc(t('otim.bloat.texto')) + '</p><div id="tw-bloat" class="otim-bloat">' +
              '<p class="vazio">' + esc(t('otim.bloat.lendo')) + '</p></div>',
        botoes: [
          {
            rotulo: t('otim.continuar'), classe: 'btn-primary', mantemAberto: true,
            onClick: function () {
              var marcados = document.querySelectorAll('#tw-bloat input[type=checkbox]:checked');
              var manter = [];
              for (var i = 0; i < marcados.length; i++) { manter.push(marcados[i].value); }
              tmx.bridge.call('plan.setParams', { id: 'APM-006', parametros: { manter: manter } }).then(function () {
                tmx.modal.close();
                fim(true);
              }).catch(function (e) { tmx.toast(e.message, 'erro'); });
            }
          },
          { rotulo: t('otim.cancelar'), onClick: function () { fim(false); } }
        ]
      });
      var cont = document.querySelector('#modal-buttons .btn-primary');
      if (cont) { cont.disabled = true; }

      chamarJob('tweaks.bloatwareList', {}).then(function (r) {
        var apps = ((r && r.apps) || []).filter(function (a) { return a.instalado !== false; });
        var alvo = document.getElementById('tw-bloat');
        if (!alvo) { return; }
        alvo.innerHTML = apps.length
          ? apps.map(function (a) {
              return '<label class="otim-check"><input type="checkbox" value="' + esc(a.id) + '"> ' +
                     '<span><strong>' + esc(a.nome) + '</strong> <span class="tw-id">' + esc(a.pacote) + '</span></span></label>';
            }).join('')
          : '<p class="vazio">' + esc(t('otim.bloat.nenhum')) + '</p>';
        if (cont) { cont.disabled = false; }
      }).catch(function (e) {
        tmx.toast(e.message, 'erro');
        tmx.modal.close();
        fim(false);
      });
    });
  }

  function perguntarGamePass() {
    return new Promise(function (resolve) {
      function responder(usa) {
        tmx.bridge.call('plan.setParams', { id: 'APM-007', parametros: { usaGamePass: usa } }).then(function () {
          tmx.modal.close();
          resolve(true);
        }).catch(function (e) { tmx.toast(e.message, 'erro'); });
      }
      tmx.modal.open({
        titulo: t('otim.gp.titulo'),
        html: '<p>' + esc(t('otim.gp.texto')) + '</p>',
        botoes: [
          { rotulo: t('otim.gp.sim'), classe: 'btn-primary', mantemAberto: true, onClick: function () { responder(true); } },
          { rotulo: t('otim.gp.nao'), mantemAberto: true, onClick: function () { responder(false); } },
          { rotulo: t('otim.cancelar'), onClick: function () { resolve(false); } }
        ]
      });
    });
  }

  function iniciarAplicacao(ids, opcoes) {
    opcoes = opcoes || {};
    if (!ids || !ids.length) { tmx.toast(t('otim.toast.nenhum'), 'aviso'); return; }

    // Um combobox sem opção escolhida não tem o que gravar: fica fora e a
    // prévia diz isso.
    var semOpcao = [];
    ids = ids.filter(function (id) {
      var item = acharItem(id);
      if (item && item.controle === 'combobox' && !item.opcaoSelecionada) { semOpcao.push(tx(item, 'nome')); return false; }
      return true;
    });
    if (!ids.length) { tmx.toast(t('otim.toast.escolhaOpcao'), 'aviso'); return; }

    tmx.session.ensure().then(function (ok) {
      if (!ok) { return null; }
      return perguntarAntes(ids).then(function (seguir) {
        if (!seguir) { return null; }
        ocupar(true);
        return chamarJob('plan.preview', { ids: ids }).then(function (previa) {
          ocupar(false);
          abrirModalPrevia(ids, previa, opcoes.titulo, semOpcao);
        });
      });
    }).catch(function (e) {
      ocupar(false);
      tmx.toast(e.message, 'erro');
    });
  }

  function tabelaPrevia(itens) {
    var html = '<table class="tw-tabela"><thead><tr>' +
               '<th>' + esc(t('otim.previa.alvo')) + '</th><th>' + esc(t('otim.previa.antes')) + '</th>' +
               '<th>' + esc(t('otim.previa.depois')) + '</th><th>' + esc(t('otim.previa.reversao')) + '</th>' +
               '</tr></thead><tbody>';
    var atual = null;
    (itens || []).forEach(function (l) {
      if (l.tweakId !== atual) {
        atual = l.tweakId;
        var item = acharItem(l.tweakId);
        html += '<tr class="tw-grupo"><td colspan="4">' + esc(item ? tx(item, 'nome') : l.nome) + ' (' + esc(l.tweakId) + ')</td></tr>';
      }
      html += '<tr>' +
                '<td class="tw-cel-mono">' + esc(l.alvo) + '</td>' +
                '<td class="tw-antes tw-cel-mono">' + esc(l.antes) + '</td>' +
                '<td class="tw-depois tw-cel-mono">' + esc(l.depois) + '</td>' +
                '<td>' + esc(l.reversao) + '</td>' +
              '</tr>';
    });
    return html + '</tbody></table>';
  }

  function blocoConsentimento(item) {
    var nome = tx(item, 'nome');
    var c = item.consentimento || {};
    return '<div class="tw-consentimento" data-consent="' + esc(item.id) + '">' +
             '<h4>' + esc(c.titulo || t('otim.consent.titulo', { nome: nome })) + '</h4>' +
             '<p class="tw-tradeoff">' + esc(c.tradeoff || t('otim.consent.tradeoff')) + '</p>' +
             '<p>' + esc(t('otim.consent.digite')) + '</p>' +
             '<p class="tw-mono">' + esc(c.frase) + '</p>' +
             '<input type="text" class="campo" data-frase="' + esc(item.id) + '" autocomplete="off" spellcheck="false" ' +
               'aria-label="' + esc(t('otim.consent.aria', { nome: nome })) + '">' +
             '<p><button type="button" class="btn btn-mini" data-consent-ok="' + esc(item.id) + '">' +
               esc(t('otim.consent.ok')) + '</button></p>' +
           '</div>';
  }

  function abrirModalPrevia(ids, previa, titulo, semOpcao) {
    previa = previa || { itens: [], faltaConsentimento: [] };
    pendentesConsentimento = (previa.faltaConsentimento || []).slice();

    var html = '<p>' + esc(t('otim.previa.texto')) + '</p>' + tabelaPrevia(previa.itens);
    if (semOpcao && semOpcao.length) {
      html += '<p class="tw-motivo">' + esc(t('otim.previa.semOpcao', { lista: semOpcao.join(', ') })) + '</p>';
    }
    pendentesConsentimento.forEach(function (id) {
      var item = acharItem(id);
      if (item) { html += blocoConsentimento(item); }
    });
    html += '<div class="tw-barra" id="tw-barra" hidden><span></span></div>' +
            '<p id="tw-progresso" class="sessao-progresso"></p>';

    tmx.modal.open({
      titulo: titulo || t('otim.previa.titulo'),
      html: html,
      botoes: [
        { rotulo: t('otim.previa.confirmar'), classe: 'btn-primary', mantemAberto: true, onClick: function () { executarAplicacao(ids); } },
        { rotulo: t('otim.cancelar') }
      ]
    });
    revalidarConsentimento();
  }

  function revalidarConsentimento() {
    var b = document.querySelector('#modal-buttons .btn-primary');
    if (b) { b.disabled = pendentesConsentimento.length > 0; }
  }

  function confirmarFrase(id) {
    var corpo = document.getElementById('modal-body');
    var campo = corpo.querySelector('[data-frase="' + id + '"]');
    tmx.bridge.call('plan.setConsent', { id: id, frase: campo ? campo.value : '' }).then(function (r) {
      if (!r || !r.ok) { tmx.toast((r && r.mensagem) || t('otim.consent.errado'), 'erro'); return; }
      var item = acharItem(id);
      if (item) { item.consentido = true; }
      var bloco = corpo.querySelector('[data-consent="' + id + '"]');
      if (bloco) { bloco.parentNode.removeChild(bloco); }
      pendentesConsentimento = pendentesConsentimento.filter(function (x) { return x !== id; });
      revalidarConsentimento();
      tmx.toast(t('otim.consent.registrado', { id: id }), 'ok');
    }).catch(function (e) { tmx.toast(e.message, 'erro'); });
  }

  /* Um único ouvinte para o corpo do modal (ver pendentesConsentimento). */
  function ligarOuvinteModal() {
    var corpo = document.getElementById('modal-body');
    if (!corpo || corpo.getAttribute('data-tw-ligado') === '1') { return; }
    corpo.setAttribute('data-tw-ligado', '1');
    corpo.addEventListener('click', function (ev) {
      var alvo = ev.target;
      if (!alvo || !alvo.getAttribute) { return; }
      var idConsent = alvo.getAttribute('data-consent-ok');
      if (idConsent) { confirmarFrase(idConsent); return; }
      var runId = alvo.getAttribute('data-undo-run');
      if (runId) { confirmarUndoRun(runId); }
    });
  }

  function pintarProgresso(p) {
    var texto = document.getElementById('tw-progresso');
    var barra = document.getElementById('tw-barra');
    if (barra) {
      barra.hidden = false;
      var interno = barra.querySelector('span');
      if (interno && typeof p.pct === 'number') { interno.style.width = Math.max(0, Math.min(100, p.pct)) + '%'; }
    }
    if (texto) {
      texto.textContent = (p.status || t('otim.trabalhando')) + (typeof p.pct === 'number' ? ' (' + p.pct + '%)' : '');
    }
  }

  function travarModal() {
    var botoes = document.querySelectorAll('#modal-buttons button');
    for (var i = 0; i < botoes.length; i++) { botoes[i].disabled = true; }
  }

  function executarAplicacao(ids) {
    travarModal();
    pintarProgresso({ status: t('otim.aplicando'), pct: 0 });
    ocupar(true);
    var modo = estado.preset;

    chamarJob('plan.apply', { ids: ids }, pintarProgresso).then(function (r) {
      ocupar(false);
      var res = (r && r.resultado) || {};
      (res.itens || []).forEach(function (l) { estado.acoes[l.id] = { status: l.status }; });
      if (r && r.catalogo) { aplicarPayload(r.catalogo); }
      if (ehModo(modo) && !(res.falhas > 0) && ((res.aplicados || 0) + (res.jaAplicados || 0)) > 0) {
        gravarModoAplicado(modo);
      }
      mostrarResultado(res);
    }).catch(function (e) {
      ocupar(false);
      tmx.modal.close();
      tmx.toast(e.message, 'erro');
    });
  }

  /* Spec 6: ao terminar uma aplicação bem-sucedida, grava appliedMode e
     appliedModeAt (o Painel lê daí o modo atual). */
  function gravarModoAplicado(modo) {
    estado.aplicado = modo;
    pintarModos();
    tmx.bridge.call('settings.set', { appliedMode: modo, appliedModeAt: new Date().toISOString() }).catch(function (e) {
      console.warn('settings.set appliedMode falhou:', e && e.message);
    });
  }

  function mostrarResultado(res) {
    var linhas = (res.itens || []).map(function (l) {
      var item = acharItem(l.id);
      var avisos = (l.avisos || []).join(' · ');
      return '<tr>' +
               '<td class="tw-cel-mono">' + esc(l.id) + '</td>' +
               '<td>' + esc(item ? tx(item, 'nome') : l.nome) + '</td>' +
               '<td><span class="estado ' + classeStatus(l.status) + '">' + esc(rotuloStatus(l.status)) + '</span></td>' +
               '<td>' + esc(l.detalhe) + (avisos ? '<br><em>' + esc(avisos) + '</em>' : '') + '</td>' +
             '</tr>';
    }).join('');

    var html = '<div id="tw-resultado">' +
                 '<p>' + esc(t('otim.res.resumo', { a: res.aplicados || 0, j: res.jaAplicados || 0, f: res.falhas || 0, p: res.pulados || 0 })) + '</p>' +
                 (res.requerReboot ? '<p class="tw-aviso-reboot">' + esc(t('otim.res.reboot')) + '</p>' : '') +
                 '<table class="tw-tabela"><thead><tr><th>ID</th><th>' + esc(t('otim.res.ajuste')) + '</th>' +
                 '<th>' + esc(t('otim.res.status')) + '</th><th>' + esc(t('otim.res.detalhe')) + '</th></tr></thead>' +
                 '<tbody>' + linhas + '</tbody></table>' +
               '</div>';

    tmx.modal.open({ titulo: t('otim.res.titulo'), html: html, botoes: [{ rotulo: t('otim.fechar') }] });
  }

  /* ---------------- reversão ---------------- */

  function desfazerItem(id) {
    ocupar(true);
    chamarJob('undo.tweak', { id: id }).then(function (r) {
      ocupar(false);
      var resumo = (r && r.resumo) || {};
      estado.acoes[id] = { status: resumo.revertidos > 0 ? 'revertido' : 'nadaReverter' };
      if (r && r.catalogo) { aplicarPayload(r.catalogo); } else { render(); }
      tmx.toast(t('otim.undo.item', { id: id, n: resumo.revertidos || 0 }), 'ok');
    }).catch(function (e) {
      ocupar(false);
      tmx.toast(e.message, 'erro');
    });
  }

  function mostrarResumoUndo(titulo, resumo) {
    var linhas = ((resumo && resumo.itens) || []).map(function (l) {
      return '<tr>' +
               '<td class="tw-cel-mono">' + esc(l.tweakId) + '</td>' +
               '<td class="tw-cel-mono">' + esc(l.alvo) + '</td>' +
               '<td>' + esc(l.resultado) + '</td>' +
               '<td>' + esc(l.detalhe) + '</td>' +
             '</tr>';
    }).join('');

    tmx.modal.open({
      titulo: titulo,
      html: '<div id="tw-resultado"><p>' +
            esc(t('otim.undo.resumo', { r: (resumo && resumo.revertidos) || 0, f: (resumo && resumo.falhas) || 0, p: (resumo && resumo.pulados) || 0 })) +
            '</p><table class="tw-tabela"><thead><tr><th>' + esc(t('otim.res.ajuste')) + '</th><th>' + esc(t('otim.previa.alvo')) +
            '</th><th>' + esc(t('otim.undo.resultado')) + '</th><th>' + esc(t('otim.res.detalhe')) + '</th></tr></thead>' +
            '<tbody>' + linhas + '</tbody></table></div>',
      botoes: [{ rotulo: t('otim.fechar') }]
    });
  }

  function confirmarUndoSessao() {
    tmx.modal.open({
      titulo: t('otim.undo.titulo'),
      html: '<p>' + esc(t('otim.undo.texto')) + '</p><p class="sessao-progresso" id="tw-progresso"></p>',
      botoes: [
        {
          rotulo: t('otim.undo.botao'), classe: 'btn-danger', mantemAberto: true,
          onClick: function () {
            travarModal();
            pintarProgresso({ status: t('otim.revertendo'), pct: 0 });
            ocupar(true);
            chamarJob('undo.run', {}, pintarProgresso).then(function (r) {
              ocupar(false);
              estado.acoes = {};
              ((r && r.resumo && r.resumo.itens) || []).forEach(function (l) {
                if (l.resultado === 'revertido') { estado.acoes[l.tweakId] = { status: 'revertido' }; }
              });
              if (r && r.catalogo) { aplicarPayload(r.catalogo); } else { render(); }
              mostrarResumoUndo(t('otim.undo.tituloSessao'), r && r.resumo);
            }).catch(function (e) {
              ocupar(false);
              tmx.modal.close();
              tmx.toast(e.message, 'erro');
            });
          }
        },
        { rotulo: t('otim.cancelar') }
      ]
    });
  }

  /* ---------------- histórico ---------------- */

  function abrirHistorico() {
    ocupar(true);
    Promise.all([chamarJob('runs.list', {}), tmx.bridge.call('undo.command')]).then(function (rs) {
      ocupar(false);
      var execucoes = (rs[0] && rs[0].execucoes) || [];
      var comando = (rs[1] && rs[1].comando) || '';

      var linhas = execucoes.map(function (e) {
        return '<tr>' +
                 '<td class="tw-cel-mono">' + esc(e.runId) + (e.atual ? ' <span class="selo selo-neutro">' + esc(t('otim.hist.atual')) + '</span>' : '') + '</td>' +
                 '<td>' + esc(String(e.criadoEm).replace('T', ' ').slice(0, 19)) + '</td>' +
                 '<td>' + esc(e.registros + ' / ' + e.aplicados + ' / ' + e.revertidos) + '</td>' +
                 '<td><button type="button" class="btn btn-mini" data-undo-run="' + esc(e.runId) + '">' + esc(t('otim.card.desfazer')) + '</button></td>' +
               '</tr>';
      }).join('');

      var html = '<p>' + esc(t('otim.hist.texto')) + '</p>' +
                 '<table class="tw-tabela"><thead><tr><th>' + esc(t('otim.hist.execucao')) + '</th><th>' + esc(t('otim.hist.criada')) + '</th>' +
                 '<th>' + esc(t('otim.hist.contagem')) + '</th><th></th></tr></thead><tbody>' +
                 (linhas || '<tr><td colspan="4">' + esc(t('otim.hist.nenhuma')) + '</td></tr>') +
                 '</tbody></table>';
      if (comando) {
        html += '<div class="tw-bloco"><h4>' + esc(t('otim.hist.terminal')) + '</h4>' +
                '<p class="tw-mono" id="tw-comando">' + esc(comando) + '</p>' +
                '<p><button type="button" class="btn btn-mini" id="tw-copiar-comando">' + esc(t('otim.hist.copiar')) + '</button></p></div>';
      }

      tmx.modal.open({ titulo: t('otim.hist.titulo'), html: html, botoes: [{ rotulo: t('otim.fechar') }] });
      var copiar = document.getElementById('tw-copiar-comando');
      if (copiar) { copiar.addEventListener('click', function () { copiarTexto(comando); }); }
    }).catch(function (e) {
      ocupar(false);
      tmx.toast(e.message, 'erro');
    });
  }

  function confirmarUndoRun(runId) {
    tmx.modal.open({
      titulo: t('otim.undo.run', { id: runId }),
      html: '<p>' + esc(t('otim.undo.runTexto')) + '</p><p class="sessao-progresso" id="tw-progresso"></p>',
      botoes: [
        {
          rotulo: t('otim.card.desfazer'), classe: 'btn-danger', mantemAberto: true,
          onClick: function () {
            travarModal();
            pintarProgresso({ status: t('otim.revertendo'), pct: 0 });
            ocupar(true);
            chamarJob('undo.run', { runId: runId }, pintarProgresso).then(function (r) {
              ocupar(false);
              if (r && r.catalogo) { aplicarPayload(r.catalogo); }
              mostrarResumoUndo(t('otim.undo.tituloRun', { id: runId }), r && r.resumo);
            }).catch(function (e) {
              ocupar(false);
              tmx.modal.close();
              tmx.toast(e.message, 'erro');
            });
          }
        },
        { rotulo: t('otim.cancelar') }
      ]
    });
  }

  /* ---------------- idioma ---------------- */

  document.addEventListener('tmx:lang', function () {
    var raiz = document.getElementById('tab-otimizacoes');
    if (!raiz || !raiz.querySelector('.otim')) { return; }
    if (tmx.i18n) { tmx.i18n.apply(raiz); }
    rotularAcessibilidade();
    if (estado.dados) { render(); } else { pintarModos(); atualizarResumo(); }
  });

  /* ---------------- registro da aba ---------------- */

  window.tmxTabs.otimizacoes = {
    init: function () {
      montarEsqueleto();
      ligarOuvinteModal();
      // Devolve a Promise: tabs.show (app.js) só marca a aba como iniciada
      // quando o catálogo chega.
      return carregar();
    }
  };
})();
