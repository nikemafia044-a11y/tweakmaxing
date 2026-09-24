/* microwin.js - tela "MicroWin" (spec v2 §11, docs/design/04-microwin.png):
 * gera uma ISO enxuta do Windows a partir de uma ISO oficial. Nao grava
 * pendrive: o produto final e um arquivo .iso. Nunca mexe no Windows em uso:
 * a imagem e sempre copiada para a pasta de trabalho.
 *
 * Fluxo: microwin.check (pre-requisitos e espaco) -> microwin.pickIso ->
 * microwin.info (job, le as edicoes) -> opcoes -> microwin.build (job com
 * progresso por etapa e log visivel) -> microwin.cancel (opcional).
 *
 * O esqueleto e montado aqui dentro de #tab-microwin (o index.html so tem a
 * section). Textos: chaves 'microwin.*' registradas neste arquivo. As
 * mensagens de progresso e de erro que vem do PowerShell continuam em pt-BR
 * (limitacao documentada no spec, §3).
 *
 * Tudo que entra em HTML passa por escapar(): nome e descricao dos
 * aplicativos vem de src/config/appx.json, caminhos vem do disco do usuario e
 * mensagens de erro vem do PowerShell.
 *
 * A senha nunca e guardada em estado nem registrada: sai do input direto para
 * a chamada da ponte.
 */
(function () {
  'use strict';
  window.tmxTabs = window.tmxTabs || {};

  /* ---------------- textos ---------------- */

  var TEXTOS_PT = {
    'microwin.eyebrow': 'Ferramenta avançada',
    'microwin.titulo': 'MicroWin',
    'microwin.sub': 'Crie um instalador do Windows mais leve, já sem os apps e recursos que você não usa.',
    'microwin.info.titulo': 'O MicroWin não mexe no Windows que você está usando agora.',
    'microwin.info.texto': 'Ele pega uma imagem oficial do Windows (arquivo .iso), remove componentes e gera um arquivo .iso novo. ' +
      'Esse arquivo serve para uma instalação limpa, neste PC ou em outro, quando você quiser.',
    'microwin.como.titulo': 'Como funciona',
    'microwin.como.1t': 'Você escolhe a ISO oficial',
    'microwin.como.1d': 'Baixada do site da Microsoft. O app confere se o arquivo é válido.',
    'microwin.como.2t': 'A imagem é aberta numa pasta de trabalho',
    'microwin.como.2d': 'O Windows dentro da ISO é montado com o DISM, a ferramenta oficial da Microsoft para editar imagens.',
    'microwin.como.3t': 'Os componentes marcados são removidos',
    'microwin.como.3d': 'Apps pré-instalados, Edge, OneDrive, telemetria e o que mais você escolher ao lado.',
    'microwin.como.4t': 'Drivers e ajustes entram na imagem',
    'microwin.como.4d': 'Opcional: os drivers deste PC e os ajustes do modo escolhido já vêm aplicados no primeiro boot.',
    'microwin.como.5t': 'Uma ISO nova é gerada',
    'microwin.como.5d': 'Grave num pendrive com Rufus ou Ventoy e instale como qualquer Windows.',
    'microwin.config.titulo': 'Configurar',
    'microwin.iso.rotulo': 'Arquivo ISO do Windows',
    'microwin.iso.placeholder': 'C:\\ISOs\\Windows11.iso',
    'microwin.iso.escolher': 'Escolher',
    'microwin.iso.lendo': 'Lendo a ISO…',
    'microwin.iso.lida': '{n} edição(ões) encontrada(s) · {gb} GB',
    'microwin.edicao.rotulo': 'Edição',
    'microwin.edicao.vazia': 'Escolha a ISO primeiro',
    'microwin.opcoes.titulo': 'O que remover ou incluir',
    'microwin.op.apps': 'Remover apps pré-instalados',
    'microwin.op.onedrive': 'Remover OneDrive',
    'microwin.op.edge': 'Remover Microsoft Edge',
    'microwin.op.telemetria': 'Desativar telemetria',
    'microwin.op.conta': 'Permitir conta local na instalação',
    'microwin.op.drivers': 'Incluir os drivers deste PC',
    'microwin.op.defender': 'Remover o Windows Defender (o PC fica sem antivírus)',
    'microwin.apps.resumo': 'Escolher os apps ({n} de {total} marcados)',
    'microwin.apps.recomendados': 'Marcar recomendados',
    'microwin.apps.limpar': 'Limpar',
    'microwin.apps.vazio': 'Nenhum aplicativo no catálogo.',
    'microwin.apps.carregando': 'Carregando…',
    'microwin.conta.usuario': 'Usuário da conta local',
    'microwin.conta.senha': 'Senha',
    'microwin.conta.senha2': 'Confirmar senha',
    'microwin.conta.avisoSenha': 'A senha fica em <strong>texto puro</strong> dentro do <code>autounattend.xml</code> ' +
      'da ISO gerada — é assim que o Windows Setup a lê. Guarde a ISO como dado sensível ' +
      '(não compartilhe nem envie para nuvem pública) e troque a senha depois da instalação.',
    'microwin.destino.rotulo': 'Pasta onde gravar a ISO nova',
    'microwin.destino.placeholder': 'C:\\ISOs',
    'microwin.pacotes.resumo': 'Pacotes do Windows (avançado)',
    'microwin.pacotes.nota': 'Um nome por linha. Cada linha é casada por pedaço do nome do pacote (ex.: Microsoft-Windows-InternetExplorer). Deixe vazio se não souber.',
    'microwin.gerar': 'Gerar ISO',
    'microwin.ganha.titulo': 'O que você ganha',
    'microwin.ganha.1': 'Windows limpo desde o primeiro boot, sem apagar nada depois.',
    'microwin.ganha.2': 'Menos processos e serviços rodando em segundo plano.',
    'microwin.ganha.3': 'Instalação menor e mais rápida.',
    'microwin.ganha.4': 'Conta local, sem exigir conta Microsoft.',
    'microwin.riscos.titulo': 'Riscos e limites',
    'microwin.riscos.1': 'O que foi removido só volta reinstalando o Windows.',
    'microwin.riscos.2': 'Algumas atualizações grandes do Windows podem falhar ou trazer apps de volta.',
    'microwin.riscos.3': 'Apps que dependem do que foi removido (Edge, Store) podem não abrir.',
    'microwin.riscos.4': 'Sem o Defender, o PC fica sem antivírus até você instalar outro.',
    'microwin.antes.titulo': 'Antes de começar',
    'microwin.antes.1': 'ISO oficial baixada do site da Microsoft.',
    'microwin.antes.2': 'Espaço livre no disco: {gb} GB.',
    'microwin.antes.3': 'Pendrive de 8 GB ou mais para gravar a ISO.',
    'microwin.antes.4': 'Backup dos seus arquivos: instalar o Windows apaga o disco escolhido.',
    'microwin.pre.adk': 'Windows ADK (oscdimg.exe)',
    'microwin.pre.adkFalta': 'não encontrado - instale o ADK (Deployment Tools)',
    'microwin.pre.adkBaixar': 'Abrir a página de download do Windows ADK',
    'microwin.pre.espaco': 'Espaço em disco (mínimo {gb} GB)',
    'microwin.pre.espacoLivre': '{gb} GB livres',
    'microwin.pre.espacoNaoMedido': 'espaço livre não medido',
    'microwin.pre.admin': 'TweakMaxing como administrador',
    'microwin.pre.adminOk': 'sessão elevada',
    'microwin.pre.adminTeste': 'modo de teste: verificação dispensada',
    'microwin.pre.adminFalta': 'reabra como administrador',
    'microwin.pre.verificando': 'Verificando…',
    'microwin.trabalho.pasta': 'Pasta de trabalho: {pasta}',
    'microwin.trabalho.limpar': 'Limpar pastas de trabalho',
    'microwin.trabalho.modalTitulo': 'Limpar pastas de trabalho',
    'microwin.trabalho.modalTexto1': 'Apaga as cópias temporárias que builds anteriores deixaram em:',
    'microwin.trabalho.modalTexto2': 'As ISOs já geradas não são tocadas: só a área de trabalho temporária é apagada.',
    'microwin.trabalho.limparBotao': 'Limpar',
    'microwin.trabalho.nada': 'Nada a limpar',
    'microwin.trabalho.apagadas': '{n} pasta(s) de trabalho apagada(s)',
    'microwin.trabalho.resistiram': '{n} pasta(s) apagada(s); {e} resistiram',
    'microwin.prog.titulo': 'Progresso',
    'microwin.prog.cancelar': 'Cancelar',
    'microwin.prog.cancelando': 'Cancelando: a imagem será descartada e a pasta de trabalho apagada…',
    'microwin.prog.log': 'Log',
    'microwin.prog.etapas': 'Etapas',
    'microwin.erro.iso': 'escolha a ISO de origem',
    'microwin.erro.isoExt': 'o arquivo precisa terminar em .iso',
    'microwin.erro.lerIso': 'não foi possível ler a ISO',
    'microwin.erro.edicao': 'escolha a ISO e a edição',
    'microwin.erro.usuario': 'informe o nome de usuário',
    'microwin.erro.usuarioFormato': 'comece com letra e use até 20 caracteres entre letras, números, hífen e sublinhado',
    'microwin.erro.senha': 'informe uma senha',
    'microwin.erro.senhaConfere': 'as senhas não conferem',
    'microwin.erro.destino': 'escolha a pasta de destino',
    'microwin.aviso.corrija': 'Corrija os campos marcados',
    'microwin.aviso.prereq': 'Resolva os pré-requisitos antes de gerar a ISO',
    'microwin.aviso.ocupado': 'Espere o trabalho atual terminar',
    'microwin.resumo.titulo': 'Gerar a ISO enxuta',
    'microwin.resumo.origem': 'ISO de origem: {iso} (não será alterada)',
    'microwin.resumo.edicao': 'Edição: {edicao}',
    'microwin.resumo.apps': 'Aplicativos a remover: {n}',
    'microwin.resumo.pacotes': 'Pacotes a remover: {n}',
    'microwin.resumo.opcoes': 'Opções: {lista}',
    'microwin.resumo.nenhuma': 'nenhuma',
    'microwin.resumo.conta': 'Conta local: {usuario}',
    'microwin.resumo.semConta': 'Conta local: não (o Windows Setup pede a conta normalmente)',
    'microwin.resumo.destino': 'Destino: {destino}',
    'microwin.resumo.tempo': 'A geração leva de 20 a 60 minutos e usa até {gb} GB temporários. Continuar?',
    'microwin.resumo.defender': 'Você marcou "Remover o Windows Defender": o Windows instalado com esta ISO fica SEM antivírus até você instalar outro.',
    'microwin.resumo.gerar': 'Gerar ISO',
    'microwin.resumo.cancelar': 'Cancelar',
    'microwin.res.ok': 'ISO gerada',
    'microwin.res.falhou': 'A geração falhou',
    'microwin.res.cancelado': 'Geração cancelada',
    'microwin.res.arquivo': 'Arquivo: {arquivo}',
    'microwin.res.tamanho': 'Tamanho: {gb} GB',
    'microwin.res.preservada': 'Pasta de trabalho preservada para diagnóstico:',
    'microwin.res.canceladoTexto': 'A imagem foi descartada e a pasta de trabalho apagada. Nada foi gravado no destino.',
    'microwin.res.fechar': 'Fechar',
    'microwin.toast.simulada': 'Build simulada concluída',
    'microwin.toast.gerada': 'ISO gerada',
    'microwin.toast.cancelada': 'Geração cancelada',
    'microwin.toast.semBuild': 'Nenhuma geração em andamento'
  };

  var TEXTOS_EN = {
    'microwin.eyebrow': 'Advanced tool',
    'microwin.titulo': 'MicroWin',
    'microwin.sub': 'Build a lighter Windows installer, already without the apps and features you do not use.',
    'microwin.info.titulo': 'MicroWin does not touch the Windows you are running right now.',
    'microwin.info.texto': 'It takes an official Windows image (.iso file), removes components and writes a new .iso file. ' +
      'Use that file for a clean install, on this PC or another one, whenever you want.',
    'microwin.como.titulo': 'How it works',
    'microwin.como.1t': 'You pick the official ISO',
    'microwin.como.1d': 'Downloaded from the Microsoft website. The app checks that the file is valid.',
    'microwin.como.2t': 'The image is opened in a work folder',
    'microwin.como.2d': 'The Windows inside the ISO is mounted with DISM, the official Microsoft tool for editing images.',
    'microwin.como.3t': 'The selected components are removed',
    'microwin.como.3d': 'Preinstalled apps, Edge, OneDrive, telemetry and anything else you choose on the right.',
    'microwin.como.4t': 'Drivers and tweaks go into the image',
    'microwin.como.4d': 'Optional: this PC\'s drivers and the chosen mode\'s tweaks are already applied on first boot.',
    'microwin.como.5t': 'A new ISO is generated',
    'microwin.como.5d': 'Write it to a USB drive with Rufus or Ventoy and install it like any Windows.',
    'microwin.config.titulo': 'Configure',
    'microwin.iso.rotulo': 'Windows ISO file',
    'microwin.iso.placeholder': 'C:\\ISOs\\Windows11.iso',
    'microwin.iso.escolher': 'Browse',
    'microwin.iso.lendo': 'Reading the ISO…',
    'microwin.iso.lida': '{n} edition(s) found · {gb} GB',
    'microwin.edicao.rotulo': 'Edition',
    'microwin.edicao.vazia': 'Pick the ISO first',
    'microwin.opcoes.titulo': 'What to remove or include',
    'microwin.op.apps': 'Remove preinstalled apps',
    'microwin.op.onedrive': 'Remove OneDrive',
    'microwin.op.edge': 'Remove Microsoft Edge',
    'microwin.op.telemetria': 'Disable telemetry',
    'microwin.op.conta': 'Allow a local account during setup',
    'microwin.op.drivers': 'Include this PC\'s drivers',
    'microwin.op.defender': 'Remove Windows Defender (the PC is left without antivirus)',
    'microwin.apps.resumo': 'Choose the apps ({n} of {total} selected)',
    'microwin.apps.recomendados': 'Select recommended',
    'microwin.apps.limpar': 'Clear',
    'microwin.apps.vazio': 'No apps in the catalog.',
    'microwin.apps.carregando': 'Loading…',
    'microwin.conta.usuario': 'Local account user name',
    'microwin.conta.senha': 'Password',
    'microwin.conta.senha2': 'Confirm password',
    'microwin.conta.avisoSenha': 'The password is stored in <strong>plain text</strong> inside the <code>autounattend.xml</code> ' +
      'of the generated ISO — that is how Windows Setup reads it. Treat the ISO as sensitive data ' +
      '(do not share it or upload it to a public cloud) and change the password after installing.',
    'microwin.destino.rotulo': 'Folder where the new ISO is saved',
    'microwin.destino.placeholder': 'C:\\ISOs',
    'microwin.pacotes.resumo': 'Windows packages (advanced)',
    'microwin.pacotes.nota': 'One name per line. Each line matches part of the package name (e.g. Microsoft-Windows-InternetExplorer). Leave empty if unsure.',
    'microwin.gerar': 'Generate ISO',
    'microwin.ganha.titulo': 'What you get',
    'microwin.ganha.1': 'Clean Windows from the first boot, with nothing to delete later.',
    'microwin.ganha.2': 'Fewer processes and services running in the background.',
    'microwin.ganha.3': 'A smaller, faster install.',
    'microwin.ganha.4': 'Local account, no Microsoft account required.',
    'microwin.riscos.titulo': 'Risks and limits',
    'microwin.riscos.1': 'Whatever was removed only comes back by reinstalling Windows.',
    'microwin.riscos.2': 'Some big Windows updates may fail or bring apps back.',
    'microwin.riscos.3': 'Apps that depend on what was removed (Edge, Store) may not open.',
    'microwin.riscos.4': 'Without Defender, the PC has no antivirus until you install another one.',
    'microwin.antes.titulo': 'Before you start',
    'microwin.antes.1': 'Official ISO downloaded from the Microsoft website.',
    'microwin.antes.2': 'Free disk space: {gb} GB.',
    'microwin.antes.3': 'An 8 GB or larger USB drive to write the ISO.',
    'microwin.antes.4': 'A backup of your files: installing Windows wipes the chosen disk.',
    'microwin.pre.adk': 'Windows ADK (oscdimg.exe)',
    'microwin.pre.adkFalta': 'not found - install the ADK (Deployment Tools)',
    'microwin.pre.adkBaixar': 'Open the Windows ADK download page',
    'microwin.pre.espaco': 'Disk space (at least {gb} GB)',
    'microwin.pre.espacoLivre': '{gb} GB free',
    'microwin.pre.espacoNaoMedido': 'free space not measured',
    'microwin.pre.admin': 'TweakMaxing running as administrator',
    'microwin.pre.adminOk': 'elevated session',
    'microwin.pre.adminTeste': 'test mode: check skipped',
    'microwin.pre.adminFalta': 'reopen as administrator',
    'microwin.pre.verificando': 'Checking…',
    'microwin.trabalho.pasta': 'Work folder: {pasta}',
    'microwin.trabalho.limpar': 'Clean up work folders',
    'microwin.trabalho.modalTitulo': 'Clean up work folders',
    'microwin.trabalho.modalTexto1': 'Deletes the temporary copies that previous builds left in:',
    'microwin.trabalho.modalTexto2': 'ISOs already generated are not touched: only the temporary work area is deleted.',
    'microwin.trabalho.limparBotao': 'Clean up',
    'microwin.trabalho.nada': 'Nothing to clean up',
    'microwin.trabalho.apagadas': '{n} work folder(s) deleted',
    'microwin.trabalho.resistiram': '{n} folder(s) deleted; {e} could not be removed',
    'microwin.prog.titulo': 'Progress',
    'microwin.prog.cancelar': 'Cancel',
    'microwin.prog.cancelando': 'Cancelling: the image will be discarded and the work folder deleted…',
    'microwin.prog.log': 'Log',
    'microwin.prog.etapas': 'Steps',
    'microwin.erro.iso': 'pick the source ISO',
    'microwin.erro.isoExt': 'the file must end in .iso',
    'microwin.erro.lerIso': 'could not read the ISO',
    'microwin.erro.edicao': 'pick the ISO and the edition',
    'microwin.erro.usuario': 'enter the user name',
    'microwin.erro.usuarioFormato': 'start with a letter and use up to 20 letters, digits, hyphens and underscores',
    'microwin.erro.senha': 'enter a password',
    'microwin.erro.senhaConfere': 'the passwords do not match',
    'microwin.erro.destino': 'pick the destination folder',
    'microwin.aviso.corrija': 'Fix the highlighted fields',
    'microwin.aviso.prereq': 'Fix the prerequisites before generating the ISO',
    'microwin.aviso.ocupado': 'Wait for the current job to finish',
    'microwin.resumo.titulo': 'Generate the slim ISO',
    'microwin.resumo.origem': 'Source ISO: {iso} (will not be changed)',
    'microwin.resumo.edicao': 'Edition: {edicao}',
    'microwin.resumo.apps': 'Apps to remove: {n}',
    'microwin.resumo.pacotes': 'Packages to remove: {n}',
    'microwin.resumo.opcoes': 'Options: {lista}',
    'microwin.resumo.nenhuma': 'none',
    'microwin.resumo.conta': 'Local account: {usuario}',
    'microwin.resumo.semConta': 'Local account: no (Windows Setup asks for the account as usual)',
    'microwin.resumo.destino': 'Destination: {destino}',
    'microwin.resumo.tempo': 'Generation takes 20 to 60 minutes and uses up to {gb} GB of temporary space. Continue?',
    'microwin.resumo.defender': 'You selected "Remove Windows Defender": Windows installed from this ISO has NO antivirus until you install another one.',
    'microwin.resumo.gerar': 'Generate ISO',
    'microwin.resumo.cancelar': 'Cancel',
    'microwin.res.ok': 'ISO generated',
    'microwin.res.falhou': 'Generation failed',
    'microwin.res.cancelado': 'Generation cancelled',
    'microwin.res.arquivo': 'File: {arquivo}',
    'microwin.res.tamanho': 'Size: {gb} GB',
    'microwin.res.preservada': 'Work folder kept for troubleshooting:',
    'microwin.res.canceladoTexto': 'The image was discarded and the work folder deleted. Nothing was written to the destination.',
    'microwin.res.fechar': 'Close',
    'microwin.toast.simulada': 'Simulated build finished',
    'microwin.toast.gerada': 'ISO generated',
    'microwin.toast.cancelada': 'Generation cancelled',
    'microwin.toast.semBuild': 'No generation in progress'
  };

  if (window.tmx && tmx.i18n) {
    tmx.i18n.add('pt-BR', TEXTOS_PT);
    tmx.i18n.add('en', TEXTOS_EN);
  }

  function t(chave, vars) {
    if (window.tmx && tmx.i18n && typeof tmx.i18n.t === 'function') { return tmx.i18n.t(chave, vars); }
    var s = TEXTOS_PT[chave] || chave;
    return vars ? s.replace(/\{(\w+)\}/g, function (m, k) { return vars[k] === undefined ? m : String(vars[k]); }) : s;
  }

  /* Preset "recomendados": casado por pedaco do campo 'pacote' (ou do 'id',
     para o Dev Home). Calculadora, Bloco de Notas, Ferramenta de Captura e
     Paint ficam de fora de proposito. */
  var RECOMENDADOS = [
    'WindowsFeedbackHub', 'GetHelp', 'MicrosoftOfficeHub', 'Clipchamp',
    'WindowsAlarms', 'QuickAssist', 'WindowsSoundRecorder', 'MicrosoftStickyNotes',
    'Todos', 'MicrosoftSolitaireCollection', 'PowerAutomateDesktop', 'WindowsDevHome',
    'BingWeather', 'StartExperiencesApp', 'BingNews', 'Copilot', 'BingSearch'
  ];

  var RE_USUARIO = /^[A-Za-z][A-Za-z0-9_-]{0,19}$/;

  /* Opcoes do build: id do checkbox -> campo do payload, com o padrao da
     imagem 04-microwin.png. 'apps' nao vai no payload: desligado, a lista de
     appx sai vazia. */
  var OPCOES = [
    { id: 'mw-op-apps', campo: null, chave: 'microwin.op.apps', padrao: true },
    { id: 'mw-op-onedrive', campo: 'removerOneDrive', chave: 'microwin.op.onedrive', padrao: true },
    { id: 'mw-op-edge', campo: 'removerEdge', chave: 'microwin.op.edge', padrao: true },
    { id: 'mw-op-telemetria', campo: 'desativarTelemetria', chave: 'microwin.op.telemetria', padrao: true },
    { id: 'mw-op-conta', campo: 'contaLocal', chave: 'microwin.op.conta', padrao: true },
    { id: 'mw-op-drivers', campo: 'incluirDrivers', chave: 'microwin.op.drivers', padrao: false },
    { id: 'mw-op-defender', campo: 'removerDefender', chave: 'microwin.op.defender', padrao: false, perigo: true }
  ];

  var estado = {
    apps: [],
    edicoes: [],
    prereq: null,
    isoGB: null,
    espacoGB: 20,
    ocupado: false,
    buildJobId: null,
    montado: false
  };

  /* ---------------- helpers ---------------- */

  function escapar(s) {
    return String(s === null || s === undefined ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }

  function el(id) { return document.getElementById(id); }

  function testMode() { return document.body.dataset.testmode === '1'; }

  function marcado(id) { var c = el(id); return !!(c && c.checked); }

  var SVG_INFO = '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="12" cy="12" r="10"/><path d="M12 16v-4"/><path d="M12 8h.01"/></svg>';

  /* ---------------- ponte: correlaciona job.done pelo jobId ---------------- */

  function chamarJob(nome, payload, aoProgredir, aoIniciar) {
    return tmx.bridge.callComEspera(nome, payload).then(function (resp) {
      var jobId = resp && resp.jobId;
      if (!jobId) { throw new Error('resposta sem jobId'); }
      if (typeof aoIniciar === 'function') { aoIniciar(jobId); }
      return new Promise(function (resolve, reject) {
        var ouvinteProgresso = null;
        if (typeof aoProgredir === 'function') {
          ouvinteProgresso = tmx.bridge.on('job.progress', function (p) {
            if (p && p.jobId === jobId) { aoProgredir(p); }
          });
        }
        var ouvinte = tmx.bridge.on('job.done', function (p) {
          if (!p || p.jobId !== jobId) { return; }
          tmx.bridge.off('job.done', ouvinte);
          if (ouvinteProgresso) { tmx.bridge.off('job.progress', ouvinteProgresso); }
          if (p.ok) { resolve(p.result); } else { reject(new Error((p.error && p.error.message) || 'o trabalho falhou')); }
        });
      });
    });
  }

  /* A ponte aceita um job por vez em todo o aplicativo: a leitura da ISO pode
     cair atras de um job de outra aba que ja estava rodando. */
  function chamarJobComEspera(nome, payload, aoProgredir, aoIniciar) {
    var limite = Date.now() + 90000;
    function tentar() {
      return chamarJob(nome, payload, aoProgredir, aoIniciar).catch(function (e) {
        if (!/trabalho em andamento/i.test(e.message) || Date.now() > limite) { throw e; }
        return new Promise(function (resolve) { setTimeout(resolve, 700); }).then(tentar);
      });
    }
    return tentar();
  }

  function ocupar() {
    if (estado.ocupado) {
      tmx.toast(t('microwin.aviso.ocupado'), 'aviso');
      return false;
    }
    estado.ocupado = true;
    el('mw-gerar').disabled = true;
    el('mw-escolher').disabled = true;
    return true;
  }

  function liberar() {
    estado.ocupado = false;
    el('mw-gerar').disabled = false;
    el('mw-escolher').disabled = false;
  }

  /* ---------------- esqueleto ---------------- */

  function opcaoHtml(o) {
    return '<label class="mw-op' + (o.perigo ? ' mw-op-perigo' : '') + '" for="' + o.id + '">' +
      '<input type="checkbox" id="' + o.id + '"' + (o.padrao ? ' checked' : '') +
      (o.campo ? ' data-campo="' + o.campo + '"' : '') + '>' +
      '<span data-i18n="' + o.chave + '"></span></label>';
  }

  function listaHtml(prefixo, n) {
    var html = '<ul class="mw-lista">';
    for (var i = 1; i <= n; i++) {
      html += '<li' + (prefixo === 'microwin.antes' && i === 2 ? ' id="mw-antes-espaco"' : '') +
        ' data-i18n="' + prefixo + '.' + i + '"></li>';
    }
    return html + '</ul>';
  }

  function comoHtml() {
    var html = '<ol class="mw-como">';
    for (var i = 1; i <= 5; i++) {
      html += '<li><span class="mw-como-num" aria-hidden="true">' + i + '</span><div>' +
        '<strong data-i18n="microwin.como.' + i + 't"></strong>' +
        '<span data-i18n="microwin.como.' + i + 'd"></span></div></li>';
    }
    return html + '</ol>';
  }

  function montarEsqueleto() {
    var raiz = el('tab-microwin');
    raiz.innerHTML =
      '<header class="mw-topo">' +
        '<p class="mw-eyebrow" data-i18n="microwin.eyebrow"></p>' +
        '<h1 class="mw-titulo" data-i18n="microwin.titulo"></h1>' +
        '<p class="mw-sub" data-i18n="microwin.sub"></p>' +
      '</header>' +
      '<div class="mw-info" role="note">' + SVG_INFO +
        '<div><strong data-i18n="microwin.info.titulo"></strong><p data-i18n="microwin.info.texto"></p></div></div>' +
      '<div class="mw-grade2" id="mw-grid">' +
        '<section class="mw-card" aria-labelledby="mw-h-como">' +
          '<h2 id="mw-h-como" data-i18n="microwin.como.titulo"></h2>' + comoHtml() +
        '</section>' +
        '<section class="mw-card mw-config" aria-labelledby="mw-h-config">' +
          '<h2 id="mw-h-config" data-i18n="microwin.config.titulo"></h2>' +
          '<label class="mw-rotulo" for="mw-iso" data-i18n="microwin.iso.rotulo"></label>' +
          '<div class="mw-linha">' +
            '<input type="text" id="mw-iso" class="campo mw-mono" spellcheck="false" autocomplete="off" data-i18n-placeholder="microwin.iso.placeholder">' +
            '<button type="button" id="mw-escolher" class="btn" data-i18n="microwin.iso.escolher"></button>' +
          '</div>' +
          '<p id="mw-iso-erro" class="mw-erro" role="alert"></p>' +
          '<p id="mw-iso-status" class="mw-nota" aria-live="polite"></p>' +
          '<label class="mw-rotulo" for="mw-edicao" data-i18n="microwin.edicao.rotulo"></label>' +
          '<select id="mw-edicao" class="campo" disabled><option value="" data-i18n="microwin.edicao.vazia"></option></select>' +
          '<p class="mw-rotulo" id="mw-h-opcoes" data-i18n="microwin.opcoes.titulo"></p>' +
          '<div class="mw-opcoes" role="group" aria-labelledby="mw-h-opcoes">' + OPCOES.map(opcaoHtml).join('') + '</div>' +
          '<details id="mw-apps-bloco" class="mw-bloco">' +
            '<summary id="mw-apps-contagem"></summary>' +
            '<div class="mw-linha mw-linha-mini">' +
              '<button type="button" id="mw-recomendados" class="btn btn-mini" data-i18n="microwin.apps.recomendados"></button>' +
              '<button type="button" id="mw-limpar-apps" class="btn btn-mini" data-i18n="microwin.apps.limpar"></button>' +
            '</div>' +
            '<div id="mw-apps" role="group" aria-labelledby="mw-apps-contagem"><p class="mw-nota" data-i18n="microwin.apps.carregando"></p></div>' +
          '</details>' +
          '<div id="mw-conta-bloco" class="mw-bloco-conta">' +
            '<label class="mw-rotulo" for="mw-usuario" data-i18n="microwin.conta.usuario"></label>' +
            '<input type="text" id="mw-usuario" class="campo" spellcheck="false" autocomplete="off" maxlength="20" placeholder="usuario">' +
            '<p id="mw-erro-usuario" class="mw-erro" role="alert"></p>' +
            '<div class="mw-duas">' +
              '<div><label class="mw-rotulo" for="mw-senha" data-i18n="microwin.conta.senha"></label>' +
              '<input type="password" id="mw-senha" class="campo" autocomplete="new-password"></div>' +
              '<div><label class="mw-rotulo" for="mw-senha2" data-i18n="microwin.conta.senha2"></label>' +
              '<input type="password" id="mw-senha2" class="campo" autocomplete="new-password"></div>' +
            '</div>' +
            '<p id="mw-erro-senha" class="mw-erro" role="alert"></p>' +
            '<p class="mw-aviso-senha" role="note" id="mw-aviso-senha"></p>' +
          '</div>' +
          '<label class="mw-rotulo" for="mw-destino" data-i18n="microwin.destino.rotulo"></label>' +
          '<input type="text" id="mw-destino" class="campo mw-mono" spellcheck="false" autocomplete="off" data-i18n-placeholder="microwin.destino.placeholder">' +
          '<p id="mw-erro-destino" class="mw-erro" role="alert"></p>' +
          '<details id="mw-pacotes-bloco" class="mw-bloco">' +
            '<summary data-i18n="microwin.pacotes.resumo"></summary>' +
            '<p class="mw-nota" data-i18n="microwin.pacotes.nota"></p>' +
            '<textarea id="mw-pacotes" class="campo mw-mono" rows="4" spellcheck="false" data-i18n-title="microwin.pacotes.resumo"></textarea>' +
          '</details>' +
          '<button type="button" id="mw-gerar" class="btn btn-primary mw-gerar" data-i18n="microwin.gerar"></button>' +
        '</section>' +
      '</div>' +
      '<section class="mw-card mw-prog" id="mw-prog" hidden aria-labelledby="mw-h-prog">' +
        '<div class="mw-prog-cab">' +
          '<h2 id="mw-h-prog" data-i18n="microwin.prog.titulo"></h2>' +
          '<button type="button" id="mw-cancelar" class="btn mw-btn-cancelar" data-i18n="microwin.prog.cancelar"></button>' +
        '</div>' +
        '<div class="mw-barra" role="progressbar" aria-valuemin="0" aria-valuemax="100" aria-valuenow="0" id="mw-barra"><div id="mw-barra-fill"></div></div>' +
        '<p id="mw-progresso" class="mw-progresso" aria-live="polite"></p>' +
        '<ul id="mw-etapas" class="mw-etapas" hidden></ul>' +
        '<details class="mw-bloco" open><summary data-i18n="microwin.prog.log"></summary><pre id="mw-log" class="mw-log"></pre></details>' +
      '</section>' +
      '<div class="mw-grade3">' +
        '<section class="mw-card mw-mini"><h3 class="mw-mini-titulo mw-ganha" data-i18n="microwin.ganha.titulo"></h3>' + listaHtml('microwin.ganha', 4) + '</section>' +
        '<section class="mw-card mw-mini"><h3 class="mw-mini-titulo mw-riscos" data-i18n="microwin.riscos.titulo"></h3>' + listaHtml('microwin.riscos', 4) + '</section>' +
        '<section class="mw-card mw-mini"><h3 class="mw-mini-titulo mw-antes" data-i18n="microwin.antes.titulo"></h3>' + listaHtml('microwin.antes', 4) +
          '<div id="mw-prereq" class="mw-prereq"><p class="mw-nota" data-i18n="microwin.pre.verificando"></p></div>' +
          '<p id="mw-trabalho" class="mw-nota mw-caminho"></p>' +
          '<button type="button" id="mw-limpar-trabalho" class="btn btn-mini" data-i18n="microwin.trabalho.limpar"></button>' +
        '</section>' +
      '</div>';
    traduzir();
  }

  function traduzir() {
    var raiz = el('tab-microwin');
    if (!raiz) { return; }
    if (window.tmx && tmx.i18n && typeof tmx.i18n.apply === 'function') {
      tmx.i18n.apply(raiz);
    } else {
      raiz.querySelectorAll('[data-i18n]').forEach(function (n) { n.textContent = t(n.getAttribute('data-i18n')); });
      raiz.querySelectorAll('[data-i18n-placeholder]').forEach(function (n) { n.placeholder = t(n.getAttribute('data-i18n-placeholder')); });
    }
    // Chaves com HTML/variaveis: fora do data-i18n (que usa textContent).
    var aviso = el('mw-aviso-senha');
    if (aviso) { aviso.innerHTML = t('microwin.conta.avisoSenha'); }
    var espaco = el('mw-antes-espaco');
    if (espaco) { espaco.textContent = t('microwin.antes.2', { gb: estado.espacoGB }); }
    atualizarContagem();
    if (estado.prereq) { pintarPrereq(estado.prereq); }
    if (!estado.edicoes.length) { pintarEdicoes([]); }
  }

  document.addEventListener('tmx:lang', function () { if (estado.montado) { traduzir(); } });

  /* ---------------- pre-requisitos ---------------- */

  function itemPrereq(ok, texto, detalhe) {
    return '<div class="mw-pre-item ' + (ok ? 'mw-pre-ok' : 'mw-pre-nao') + '">' +
      '<span class="mw-pre-marca" aria-hidden="true">' + (ok ? '✓' : '✗') + '</span>' +
      '<span class="mw-pre-texto">' + escapar(texto) +
      (detalhe ? '<span class="mw-pre-detalhe">' + escapar(detalhe) + '</span>' : '') +
      '</span></div>';
  }

  function pintarPrereq(c) {
    c = c || {};
    estado.prereq = c;
    if (typeof c.espacoMinGB === 'number' && c.espacoMinGB > 0) { estado.espacoGB = c.espacoMinGB; }
    var espacoAntes = el('mw-antes-espaco');
    if (espacoAntes) { espacoAntes.textContent = t('microwin.antes.2', { gb: estado.espacoGB }); }

    var html = '';
    html += itemPrereq(!!c.oscdimg, t('microwin.pre.adk'), c.oscdimg ? c.oscdimgPath : t('microwin.pre.adkFalta'));
    var espaco = (typeof c.espacoLivreGB === 'number' && c.espacoLivreGB >= 0)
      ? t('microwin.pre.espacoLivre', { gb: c.espacoLivreGB })
      : t('microwin.pre.espacoNaoMedido');
    html += itemPrereq(!!c.espacoOk, t('microwin.pre.espaco', { gb: estado.espacoGB }), espaco);
    html += itemPrereq(!!c.elevado || !!c.testMode, t('microwin.pre.admin'),
      c.elevado ? t('microwin.pre.adminOk') : (c.testMode ? t('microwin.pre.adminTeste') : t('microwin.pre.adminFalta')));
    if (!c.oscdimg) {
      html += '<button type="button" id="mw-adk" class="mw-adk">' + escapar(t('microwin.pre.adkBaixar')) + '</button>';
    }
    el('mw-prereq').innerHTML = html;

    var alvo = el('mw-trabalho');
    if (alvo) { alvo.textContent = c.pastaTrabalho ? t('microwin.trabalho.pasta', { pasta: c.pastaTrabalho }) : ''; }

    var botao = el('mw-adk');
    if (botao) {
      botao.addEventListener('click', function () {
        tmx.bridge.call('shell.openUrl', { url: c.urlAdk }).catch(function (e) { tmx.toast(e.message, 'erro'); });
      });
    }
  }

  function carregarPrereq() {
    var iso = el('mw-iso') ? el('mw-iso').value.trim() : '';
    var payload = (iso && /\.iso$/i.test(iso)) ? { iso: iso } : null;
    return tmx.bridge.call('microwin.check', payload).then(pintarPrereq).catch(function (e) {
      el('mw-prereq').innerHTML = '<p class="mw-erro">' + escapar(e.message) + '</p>';
    });
  }

  /* Um build que falha deixa para tras uma copia inteira do Windows (varios
     GB). O botao existe para recuperar o espaco sem cacar a pasta no disco. */
  function limparPastasTrabalho() {
    tmx.modal.open({
      titulo: t('microwin.trabalho.modalTitulo'),
      html: '<p>' + escapar(t('microwin.trabalho.modalTexto1')) + '</p>' +
            '<p class="mw-caminho">' + escapar((estado.prereq && estado.prereq.pastaTrabalho) || '') + '</p>' +
            '<p>' + escapar(t('microwin.trabalho.modalTexto2')) + '</p>',
      botoes: [
        {
          rotulo: t('microwin.trabalho.limparBotao'),
          classe: 'btn-danger',
          onClick: function () {
            tmx.bridge.call('microwin.cleanupWorkDirs', { manterUltimas: 0 }).then(function (r) {
              var n = (r && r.removidas) || 0;
              if (r && r.erros && r.erros.length) {
                tmx.toast(t('microwin.trabalho.resistiram', { n: n, e: r.erros.length }), 'aviso');
              } else {
                tmx.toast(n === 0 ? t('microwin.trabalho.nada') : t('microwin.trabalho.apagadas', { n: n }), 'ok');
              }
              carregarPrereq();
            }).catch(function (e) { tmx.toast(e.message, 'erro'); });
          }
        },
        { rotulo: t('microwin.resumo.cancelar') }
      ]
    });
  }

  /* ---------------- aplicativos ---------------- */

  function ehRecomendado(app) {
    var alvo = (String(app.pacote || '') + ' ' + String(app.id || '')).toLowerCase();
    for (var i = 0; i < RECOMENDADOS.length; i++) {
      if (alvo.indexOf(RECOMENDADOS[i].toLowerCase()) >= 0) { return true; }
    }
    return false;
  }

  function pintarApps() {
    var caixa = el('mw-apps');
    if (!estado.apps.length) {
      caixa.innerHTML = '<p class="mw-nota">' + escapar(t('microwin.apps.vazio')) + '</p>';
      atualizarContagem();
      return;
    }
    caixa.innerHTML = estado.apps.map(function (a, i) {
      var id = 'mw-app-' + i;
      return '<label class="mw-app" for="' + id + '" title="' + escapar(a.descricao) + '">' +
        '<input type="checkbox" id="' + id + '" data-pacote="' + escapar(a.pacote) + '">' +
        '<span><span class="mw-app-nome">' + escapar(a.nome) + '</span>' +
        '<span class="mw-app-pacote">' + escapar(a.pacote) + '</span></span>' +
        '</label>';
    }).join('');
    // "Remover apps pre-instalados" vem ligado: a lista nasce com os recomendados.
    marcarRecomendados();
  }

  function appsMarcados() {
    var caixas = document.querySelectorAll('#mw-apps input[type=checkbox]');
    var fora = [];
    for (var i = 0; i < caixas.length; i++) {
      if (caixas[i].checked) { fora.push(caixas[i].getAttribute('data-pacote')); }
    }
    return fora;
  }

  function atualizarContagem() {
    var alvo = el('mw-apps-contagem');
    if (alvo) { alvo.textContent = t('microwin.apps.resumo', { n: appsMarcados().length, total: estado.apps.length }); }
  }

  function carregarApps() {
    return tmx.bridge.call('microwin.apps').then(function (r) {
      estado.apps = (r && r.apps) || [];
      pintarApps();
    }).catch(function (e) {
      el('mw-apps').innerHTML = '<p class="mw-erro">' + escapar(e.message) + '</p>';
    });
  }

  function marcarRecomendados() {
    var caixas = document.querySelectorAll('#mw-apps input[type=checkbox]');
    for (var i = 0; i < caixas.length; i++) {
      if (ehRecomendado(estado.apps[i] || {})) { caixas[i].checked = true; }
    }
    atualizarContagem();
  }

  function limparApps() {
    var caixas = document.querySelectorAll('#mw-apps input[type=checkbox]');
    for (var i = 0; i < caixas.length; i++) { caixas[i].checked = false; }
    atualizarContagem();
  }

  /* ---------------- opcoes ---------------- */

  function sincronizarOpcoes() {
    // Os blocos dependentes somem com a opcao desligada.
    el('mw-apps-bloco').hidden = !marcado('mw-op-apps');
    el('mw-conta-bloco').hidden = !marcado('mw-op-conta');
    if (!marcado('mw-op-conta')) {
      el('mw-erro-usuario').textContent = '';
      el('mw-erro-senha').textContent = '';
    }
  }

  /* ---------------- ISO e edicoes ---------------- */

  function escolherIso() {
    // No modo de teste o PowerShell nao abre dialogo nativo (ele travaria a
    // thread da janela): devolve de volta o que ja estiver digitado.
    return tmx.bridge.call('microwin.pickIso', { simular: el('mw-iso').value }).then(function (r) {
      if (r && r.caminho) {
        el('mw-iso').value = r.caminho;
        lerIso();
      }
    }).catch(function (e) { tmx.toast(e.message, 'erro'); });
  }

  function pintarEdicoes(lista) {
    estado.edicoes = lista || [];
    var sel = el('mw-edicao');
    if (!estado.edicoes.length) {
      sel.innerHTML = '<option value="">' + escapar(t('microwin.edicao.vazia')) + '</option>';
      sel.disabled = true;
      return;
    }
    // Pro por padrao, quando existe (e a edicao que a imagem de referencia mostra).
    var escolhida = 0;
    estado.edicoes.forEach(function (e, i) { if (!escolhida && / Pro$/i.test(String(e.nome || ''))) { escolhida = i; } });
    sel.innerHTML = estado.edicoes.map(function (e, i) {
      var rotulo = e.nome + (e.arquitetura ? ' (' + e.arquitetura + ')' : '');
      return '<option value="' + escapar(e.index) + '"' + (i === escolhida ? ' selected' : '') + '>' + escapar(rotulo) + '</option>';
    }).join('');
    sel.disabled = false;
  }

  function lerIso() {
    if (!validarIso()) { return; }
    if (!ocupar()) { return; }

    var status = el('mw-iso-status');
    status.textContent = t('microwin.iso.lendo');
    var payload = { iso: el('mw-iso').value.trim() };
    if (testMode()) { payload.simular = true; }
    chamarJobComEspera('microwin.info', payload).then(function (r) {
      if (!r || !r.ok) {
        pintarEdicoes([]);
        status.textContent = '';
        el('mw-iso-erro').textContent = (r && r.mensagem) || t('microwin.erro.lerIso');
        return;
      }
      el('mw-iso-erro').textContent = '';
      estado.isoGB = r.tamanhoGB;
      pintarEdicoes(r.edicoes);
      status.textContent = t('microwin.iso.lida', { n: (r.edicoes || []).length, gb: r.tamanhoGB });
      carregarPrereq();
    }).catch(function (e) {
      status.textContent = '';
      el('mw-iso-erro').textContent = e.message;
    }).then(liberar, liberar);
  }

  /* ---------------- validacao ---------------- */

  function validarIso() {
    var v = el('mw-iso').value.trim();
    var erro = '';
    if (!v) { erro = t('microwin.erro.iso'); }
    else if (!/\.iso$/i.test(v)) { erro = t('microwin.erro.isoExt'); }
    el('mw-iso-erro').textContent = erro;
    return !erro;
  }

  function validarUsuario() {
    if (!marcado('mw-op-conta')) { el('mw-erro-usuario').textContent = ''; return true; }
    var v = el('mw-usuario').value;
    var erro = '';
    if (!v) { erro = t('microwin.erro.usuario'); }
    else if (!RE_USUARIO.test(v)) { erro = t('microwin.erro.usuarioFormato'); }
    el('mw-erro-usuario').textContent = erro;
    return !erro;
  }

  function validarSenha() {
    if (!marcado('mw-op-conta')) { el('mw-erro-senha').textContent = ''; return true; }
    var a = el('mw-senha').value;
    var b = el('mw-senha2').value;
    var erro = '';
    if (!a) { erro = t('microwin.erro.senha'); }
    else if (a !== b) { erro = t('microwin.erro.senhaConfere'); }
    el('mw-erro-senha').textContent = erro;
    return !erro;
  }

  function validarDestino() {
    var v = el('mw-destino').value.trim();
    el('mw-erro-destino').textContent = v ? '' : t('microwin.erro.destino');
    return !!v;
  }

  function pacotesDigitados() {
    return el('mw-pacotes').value.split(/\r?\n/).map(function (s) {
      return s.trim();
    }).filter(function (s) { return s.length > 0; });
  }

  /* ---------------- geracao ---------------- */

  function opcoesLigadas() {
    return OPCOES.filter(function (o) { return marcado(o.id); }).map(function (o) { return t(o.chave); });
  }

  function resumoHtml(dados) {
    var sel = el('mw-edicao');
    var edicao = sel.options[sel.selectedIndex] ? sel.options[sel.selectedIndex].text : '';
    var ligadas = opcoesLigadas();
    return (dados.removerDefender ? '<p class="mw-alerta-defender">' + escapar(t('microwin.resumo.defender')) + '</p>' : '') +
      '<ul class="mw-resumo">' +
      '<li>' + escapar(t('microwin.resumo.origem', { iso: dados.iso })) + '</li>' +
      '<li>' + escapar(t('microwin.resumo.edicao', { edicao: edicao })) + '</li>' +
      '<li>' + escapar(t('microwin.resumo.apps', { n: dados.appx.length })) + '</li>' +
      '<li>' + escapar(t('microwin.resumo.pacotes', { n: dados.pacotes.length })) + '</li>' +
      '<li>' + escapar(t('microwin.resumo.opcoes', { lista: ligadas.length ? ligadas.join(', ') : t('microwin.resumo.nenhuma') })) + '</li>' +
      '<li>' + escapar(dados.contaLocal ? t('microwin.resumo.conta', { usuario: dados.usuario }) : t('microwin.resumo.semConta')) + '</li>' +
      '<li>' + escapar(t('microwin.resumo.destino', { destino: dados.destino })) + '</li>' +
      '</ul>' +
      '<p>' + escapar(t('microwin.resumo.tempo', { gb: estado.espacoGB })) + '</p>';
  }

  function passosHtml(passos) {
    if (!passos || !passos.length) { return ''; }
    return '<ul class="mw-passos">' + passos.map(function (p) {
      return '<li class="' + (p.ok ? 'mw-passo-ok' : 'mw-passo-falhou') + '">' +
        '<span aria-hidden="true">' + (p.ok ? '✓' : '✗') + '</span> ' +
        escapar(p.nome) + ' — ' + escapar(p.detalhe) + '</li>';
    }).join('') + '</ul>';
  }

  function modalResultado(r) {
    var titulo = r.ok ? t('microwin.res.ok') : (r.cancelado ? t('microwin.res.cancelado') : t('microwin.res.falhou'));
    var corpo;
    if (r.ok) {
      corpo = '<p>' + escapar(t('microwin.res.arquivo', { arquivo: r.arquivo })) + '</p>' +
              '<p>' + escapar(t('microwin.res.tamanho', { gb: r.tamanhoGB })) + '</p>';
    } else if (r.cancelado) {
      corpo = '<p>' + escapar(t('microwin.res.canceladoTexto')) + '</p>';
    } else {
      corpo = '<p class="mw-erro">' + escapar(r.mensagem) + '</p>' +
              '<p>' + escapar(t('microwin.res.preservada')) + '<br><span class="mw-caminho">' + escapar(r.pastaTrabalho) + '</span></p>';
    }
    tmx.modal.open({ titulo: titulo, html: corpo + passosHtml(r.passos), botoes: [{ rotulo: t('microwin.res.fechar') }] });
  }

  function gerar() {
    var ok = [validarIso(), validarUsuario(), validarSenha(), validarDestino()];
    for (var i = 0; i < ok.length; i++) {
      if (!ok[i]) { tmx.toast(t('microwin.aviso.corrija'), 'aviso'); return; }
    }
    if (el('mw-edicao').disabled || !el('mw-edicao').value) {
      el('mw-iso-erro').textContent = t('microwin.erro.edicao');
      return;
    }
    // No modo de teste a build e sempre simulada (nada de oscdimg/DISM): os
    // pre-requisitos nao se aplicam.
    if (!testMode() && estado.prereq && !estado.prereq.pronto) {
      tmx.toast(t('microwin.aviso.prereq'), 'aviso');
      return;
    }

    var dados = {
      iso: el('mw-iso').value.trim(),
      edicao: parseInt(el('mw-edicao').value, 10),
      appx: marcado('mw-op-apps') ? appsMarcados() : [],
      pacotes: pacotesDigitados(),
      contaLocal: marcado('mw-op-conta'),
      usuario: marcado('mw-op-conta') ? el('mw-usuario').value : '',
      destino: el('mw-destino').value.trim()
    };
    OPCOES.forEach(function (o) { if (o.campo && o.campo !== 'contaLocal') { dados[o.campo] = marcado(o.id); } });

    tmx.modal.open({
      titulo: t('microwin.resumo.titulo'),
      html: resumoHtml(dados),
      botoes: [
        { rotulo: t('microwin.resumo.gerar'), classe: dados.removerDefender ? 'btn-danger' : 'btn-primary', onClick: function () { disparar(dados); } },
        { rotulo: t('microwin.resumo.cancelar') }
      ]
    });
  }

  function registrarLog(texto) {
    var log = el('mw-log');
    if (!log || !texto) { return; }
    var agora = new Date();
    var hh = ('0' + agora.getHours()).slice(-2) + ':' + ('0' + agora.getMinutes()).slice(-2) + ':' + ('0' + agora.getSeconds()).slice(-2);
    log.textContent += '[' + hh + '] ' + texto + '\n';
    log.scrollTop = log.scrollHeight;
  }

  function pintarBarra(pct) {
    if (typeof pct !== 'number') { return; }
    var p = Math.max(0, Math.min(100, pct));
    el('mw-barra-fill').style.width = p + '%';
    el('mw-barra').setAttribute('aria-valuenow', String(p));
  }

  function abrirProgresso() {
    var card = el('mw-prog');
    card.hidden = false;
    el('mw-log').textContent = '';
    el('mw-etapas').hidden = true;
    el('mw-etapas').innerHTML = '';
    el('mw-progresso').textContent = '';
    el('mw-cancelar').hidden = false;
    el('mw-cancelar').disabled = false;
    pintarBarra(0);
    card.scrollIntoView({ block: 'start', behavior: 'smooth' });
  }

  function fecharProgresso(r) {
    el('mw-cancelar').hidden = true;
    estado.buildJobId = null;
    if (r && r.passos) {
      var lista = el('mw-etapas');
      lista.innerHTML = passosHtml(r.passos).replace(/^<ul class="mw-passos">|<\/ul>$/g, '');
      lista.hidden = false;
    }
  }

  function cancelar() {
    if (!estado.buildJobId) { tmx.toast(t('microwin.toast.semBuild'), 'aviso'); return; }
    el('mw-cancelar').disabled = true;
    tmx.bridge.call('microwin.cancel').then(function (r) {
      if (r && r.cancelando) {
        el('mw-progresso').textContent = t('microwin.prog.cancelando');
        registrarLog(t('microwin.prog.cancelando'));
      } else {
        el('mw-cancelar').disabled = false;
        tmx.toast((r && r.mensagem) || t('microwin.toast.semBuild'), 'aviso');
      }
    }).catch(function (e) {
      el('mw-cancelar').disabled = false;
      tmx.toast(e.message, 'erro');
    });
  }

  function disparar(dados) {
    if (!ocupar()) { return; }

    // A senha sai do input direto para a chamada: nao passa pelo estado.
    var payload = {
      iso: dados.iso,
      edicao: dados.edicao,
      appx: dados.appx,
      pacotes: dados.pacotes,
      contaLocal: dados.contaLocal,
      usuario: dados.usuario,
      senha: dados.contaLocal ? el('mw-senha').value : '',
      destino: dados.destino
    };
    OPCOES.forEach(function (o) { if (o.campo && o.campo !== 'contaLocal') { payload[o.campo] = !!dados[o.campo]; } });
    if (testMode()) {
      payload.simular = true;
      if (typeof window.tmxMicroWinAtrasoMs === 'number') { payload.simularAtrasoMs = window.tmxMicroWinAtrasoMs; }
    }

    abrirProgresso();
    var ultimoStatus = '';

    function progresso(p) {
      var texto = (p.status || '…') + (typeof p.pct === 'number' ? ' (' + p.pct + '%)' : '');
      el('mw-progresso').textContent = texto;
      pintarBarra(p.pct);
      if (p.status && p.status !== ultimoStatus) { ultimoStatus = p.status; registrarLog(p.status); }
    }

    chamarJobComEspera('microwin.build', payload, progresso, function (jobId) {
      estado.buildJobId = jobId;
    }).then(function (r) {
      r = r || { ok: false, mensagem: 'resposta vazia' };
      el('mw-progresso').textContent = r.ok ? '' : (r.mensagem || '');
      if (r.ok) { pintarBarra(100); }
      registrarLog(r.ok ? (r.arquivo || '') : (r.mensagem || ''));
      fecharProgresso(r);
      modalResultado(r);
      if (r.ok) { tmx.toast(r.simulado ? t('microwin.toast.simulada') : t('microwin.toast.gerada'), 'ok'); }
      else if (r.cancelado) { tmx.toast(t('microwin.toast.cancelada'), 'aviso'); }
    }).catch(function (e) {
      el('mw-progresso').textContent = e.message;
      registrarLog(e.message);
      fecharProgresso(null);
      tmx.toast(e.message, 'erro');
    }).then(liberar, liberar);
  }

  /* ---------------- arranque ---------------- */

  window.tmxTabs.microwin = {
    init: function () {
      montarEsqueleto();
      estado.montado = true;
      sincronizarOpcoes();

      el('mw-escolher').addEventListener('click', escolherIso);
      el('mw-iso').addEventListener('change', function () { if (validarIso()) { lerIso(); } });
      el('mw-recomendados').addEventListener('click', marcarRecomendados);
      el('mw-limpar-apps').addEventListener('click', limparApps);
      el('mw-gerar').addEventListener('click', gerar);
      el('mw-cancelar').addEventListener('click', cancelar);
      el('mw-limpar-trabalho').addEventListener('click', limparPastasTrabalho);
      el('mw-apps').addEventListener('change', atualizarContagem);
      OPCOES.forEach(function (o) { el(o.id).addEventListener('change', sincronizarOpcoes); });

      // 'input', 'change' e 'blur': o preenchimento programatico das suites de
      // GUI dispara um deles, e nem sempre o mesmo.
      [['mw-usuario', validarUsuario], ['mw-senha', validarSenha], ['mw-senha2', validarSenha],
       ['mw-destino', validarDestino]].forEach(function (par) {
        el(par[0]).addEventListener('input', par[1]);
        el(par[0]).addEventListener('change', par[1]);
        el(par[0]).addEventListener('blur', par[1]);
      });

      return tmx.aguardarTodas([carregarPrereq(), carregarApps()]);
    }
  };
})();
