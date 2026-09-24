/* install.js - tela "Aplicativos" (spec v2 §10, docs/design/03-aplicativos.png).
 *
 * Catalogo (apps.catalog) e gerenciadores (apps.managers) sao acoes sincronas;
 * instalar/desinstalar/atualizar tudo/listar instalados/reparar winget/
 * instalar choco/icones sao assincronas (bridge.call devolve so { jobId } na
 * hora - o resultado de verdade chega depois via evento job.done,
 * correlacionado aqui pelo jobId porque a ponte nao amarra id de pedido a
 * evento). Exportar/importar usam apps.export/apps.import + os dialogos
 * nativos shell.saveFile/shell.openFile (Actions.System.ps1).
 *
 * Todos os cards (236) ficam no DOM de uma vez: a categoria ativa e a busca
 * so escondem/mostram (classe app-oculto). A classe 'app' fica so nos cards
 * visiveis - e o que os testes de GUI contam.
 *
 * Textos: chaves 'apps.*' registradas aqui (tmx.i18n.add). Nome do app vem do
 * catalogo; descricao em ingles vem de descricaoEn (i18n.en.descricao do
 * catalogo), com pt-BR como reserva.
 */
(function () {
  'use strict';
  window.tmxTabs = window.tmxTabs || {};

  /* ---------------- textos ---------------- */

  var TEXTOS_PT = {
    'apps.eyebrow': 'Aplicativos',
    'apps.titulo': 'Gerenciador de apps',
    'apps.sub': 'Instale e desinstale em lote pelo winget. {n} apps em {c} categorias.',
    'apps.subCarregando': 'Instale e desinstale em lote pelo winget.',
    'apps.resumo': '{s} selecionados · {i} instalados',
    'apps.buscar': 'Pesquisar apps',
    'apps.buscarAria': 'Pesquisar aplicativo por nome, descrição ou ID do winget',
    'apps.instalar': 'Instalar selecionados',
    'apps.desinstalar': 'Desinstalar',
    'apps.exportar': 'Exportar lista',
    'apps.importar': 'Importar lista',
    'apps.avisoAntes': 'Quer remover os apps que vêm com o Windows? Isso fica em ',
    'apps.avisoLink': 'Otimizações › Remover bloatware',
    'apps.avisoDepois': ', com escolha do que manter.',
    'apps.atualizarTudo': 'Atualizar tudo',
    'apps.soInstalados': 'Só instalados',
    'apps.limparSelecao': 'Limpar seleção',
    'apps.repararWinget': 'Reparar winget',
    'apps.instalarChoco': 'Instalar Chocolatey',
    'apps.cat.navegadores': 'Navegadores',
    'apps.cat.comunicacao': 'Comunicação',
    'apps.cat.jogos': 'Jogos',
    'apps.cat.desenvolvimento': 'Desenvolvimento',
    'apps.cat.multimidia': 'Multimídia',
    'apps.cat.utilitarios': 'Utilitários',
    'apps.nApps': '{n} apps',
    'apps.resultados': 'Resultados da busca',
    'apps.nenhum': 'Nenhum app encontrado.',
    'apps.instalado': 'Instalado',
    'apps.siteOficial': 'Abrir o site oficial de {nome}',
    'apps.selecionar': 'Selecionar {nome}',
    'apps.rodape': 'Instalar e desinstalar não exigem ponto de restauração: desinstalar é a reversão natural.',
    'apps.carregando': 'Carregando o catálogo…',
    'apps.falhaCatalogo': 'Falha ao carregar o catálogo: {erro}',
    'apps.falhaGerenciadores': 'Falha ao consultar winget/choco: {erro}',
    'apps.falhaInstalados': 'Falha ao consultar os aplicativos instalados: {erro}',
    'apps.selecioneUm': 'Selecione ao menos um aplicativo',
    'apps.selecioneExportar': 'Selecione ao menos um aplicativo para exportar',
    'apps.exportado': 'Lista com {n} apps salva em {caminho}',
    'apps.importado': '{n} apps marcados',
    'apps.importadoDesconhecidos': '{n} apps marcados; {d} IDs fora do catálogo foram ignorados',
    'apps.falhaExportar': 'Falha ao exportar: {erro}',
    'apps.falhaImportar': 'Falha ao importar: {erro}',
    'apps.falhaLink': 'Não foi possível abrir o link: {erro}',
    'apps.instalando': 'Instalando',
    'apps.desinstalando': 'Desinstalando',
    'apps.atualizando': 'Atualizando tudo',
    'apps.acaoFalhou': '{acao} falhou: {erro}',
    'apps.res.pacote': 'Pacote',
    'apps.res.gerenciador': 'Gerenciador',
    'apps.res.resultado': 'Resultado',
    'apps.res.detalhe': 'Detalhe',
    'apps.res.vazio': 'Nada para mostrar.',
    'apps.fechar': 'Fechar',
    'apps.cancelar': 'Cancelar',
    'apps.reparar.titulo': 'Reparar o winget',
    'apps.reparar.texto': '<p>Isso instala ou repara o winget usando o módulo <strong>Microsoft.WinGet.Client</strong> da PowerShell Gallery ' +
      '(<code>Install-Module</code> + <code>Repair-WinGetPackageManager</code>). Pode levar alguns minutos.</p>',
    'apps.reparar.botao': 'Reparar',
    'apps.reparar.andamento': 'Reparando o winget...',
    'apps.reparar.falha': 'Falha ao reparar o winget: {erro}',
    'apps.choco.titulo': 'Instalar o Chocolatey',
    'apps.choco.texto': '<p>Isso baixa o instalador oficial de <code>https://community.chocolatey.org/install.ps1</code> e roda ele em um ' +
      'processo separado do PowerShell. O SHA-256 do arquivo baixado fica registrado no log.</p>',
    'apps.choco.botao': 'Instalar',
    'apps.choco.andamento': 'Instalando o Chocolatey...',
    'apps.choco.ok': 'Chocolatey instalado',
    'apps.choco.falha': 'Falha ao instalar o Chocolatey: {erro}'
  };

  var TEXTOS_EN = {
    'apps.eyebrow': 'Applications',
    'apps.titulo': 'App manager',
    'apps.sub': 'Install and uninstall in bulk with winget. {n} apps in {c} categories.',
    'apps.subCarregando': 'Install and uninstall in bulk with winget.',
    'apps.resumo': '{s} selected · {i} installed',
    'apps.buscar': 'Search apps',
    'apps.buscarAria': 'Search apps by name, description or winget ID',
    'apps.instalar': 'Install selected',
    'apps.desinstalar': 'Uninstall',
    'apps.exportar': 'Export list',
    'apps.importar': 'Import list',
    'apps.avisoAntes': 'Want to remove the apps that ship with Windows? That lives in ',
    'apps.avisoLink': 'Optimizations › Remove bloatware',
    'apps.avisoDepois': ', where you choose what to keep.',
    'apps.atualizarTudo': 'Update all',
    'apps.soInstalados': 'Installed only',
    'apps.limparSelecao': 'Clear selection',
    'apps.repararWinget': 'Repair winget',
    'apps.instalarChoco': 'Install Chocolatey',
    'apps.cat.navegadores': 'Browsers',
    'apps.cat.comunicacao': 'Communication',
    'apps.cat.jogos': 'Games',
    'apps.cat.desenvolvimento': 'Development',
    'apps.cat.multimidia': 'Multimedia',
    'apps.cat.utilitarios': 'Utilities',
    'apps.nApps': '{n} apps',
    'apps.resultados': 'Search results',
    'apps.nenhum': 'No apps found.',
    'apps.instalado': 'Installed',
    'apps.siteOficial': 'Open the official {nome} website',
    'apps.selecionar': 'Select {nome}',
    'apps.rodape': 'Installing and uninstalling need no restore point: uninstalling is the natural way back.',
    'apps.carregando': 'Loading the catalog…',
    'apps.falhaCatalogo': 'Failed to load the catalog: {erro}',
    'apps.falhaGerenciadores': 'Failed to check winget/choco: {erro}',
    'apps.falhaInstalados': 'Failed to list installed apps: {erro}',
    'apps.selecioneUm': 'Select at least one app',
    'apps.selecioneExportar': 'Select at least one app to export',
    'apps.exportado': 'List with {n} apps saved to {caminho}',
    'apps.importado': '{n} apps selected',
    'apps.importadoDesconhecidos': '{n} apps selected; {d} IDs not in the catalog were ignored',
    'apps.falhaExportar': 'Export failed: {erro}',
    'apps.falhaImportar': 'Import failed: {erro}',
    'apps.falhaLink': 'Could not open the link: {erro}',
    'apps.instalando': 'Installing',
    'apps.desinstalando': 'Uninstalling',
    'apps.atualizando': 'Updating everything',
    'apps.acaoFalhou': '{acao} failed: {erro}',
    'apps.res.pacote': 'Package',
    'apps.res.gerenciador': 'Manager',
    'apps.res.resultado': 'Result',
    'apps.res.detalhe': 'Detail',
    'apps.res.vazio': 'Nothing to show.',
    'apps.fechar': 'Close',
    'apps.cancelar': 'Cancel',
    'apps.reparar.titulo': 'Repair winget',
    'apps.reparar.texto': '<p>This installs or repairs winget using the <strong>Microsoft.WinGet.Client</strong> module from the PowerShell Gallery ' +
      '(<code>Install-Module</code> + <code>Repair-WinGetPackageManager</code>). It may take a few minutes.</p>',
    'apps.reparar.botao': 'Repair',
    'apps.reparar.andamento': 'Repairing winget...',
    'apps.reparar.falha': 'Failed to repair winget: {erro}',
    'apps.choco.titulo': 'Install Chocolatey',
    'apps.choco.texto': '<p>This downloads the official installer from <code>https://community.chocolatey.org/install.ps1</code> and runs it in a ' +
      'separate PowerShell process. The SHA-256 of the downloaded file is written to the log.</p>',
    'apps.choco.botao': 'Install',
    'apps.choco.andamento': 'Installing Chocolatey...',
    'apps.choco.ok': 'Chocolatey installed',
    'apps.choco.falha': 'Failed to install Chocolatey: {erro}'
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

  function idioma() { return (window.tmx && tmx.i18n && tmx.i18n.lang) || 'pt-BR'; }

  /* Ordem fixa das abas de categoria (a mesma de Get-TmxAppCategoryOrder). */
  var ORDEM_CATEGORIAS = ['navegadores', 'comunicacao', 'jogos', 'desenvolvimento', 'multimidia', 'utilitarios'];

  /* Modo de teste: a lista de "instalados" e simulada (nada de winget). Os
     testes de GUI podem trocar por window.tmxSimularInstalados antes de abrir
     a aba. */
  var SIMULAR_INSTALADOS_PADRAO = ['firefox', 'vivaldi'];

  var estado = {
    catalogo: null,
    apps: {},           // id -> app
    selecionados: {},
    instalados: null,   // id -> true
    soInstalados: false,
    termoBusca: '',
    categoria: 'navegadores'
  };

  /* ---------------- helpers ---------------- */

  function escapeHtml(s) {
    return String(s === null || s === undefined ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }

  function el(id) { return document.getElementById(id); }

  function testMode() { return document.body && document.body.dataset.testmode === '1'; }

  function descricaoDe(app) {
    if (idioma() === 'en' && app.descricaoEn) { return app.descricaoEn; }
    return app.descricao || '';
  }

  /* A folha install.css e desta tela; o index.html e de outro dono. Se a tag
     ainda nao estiver la, entra por aqui (uma vez so). */
  function garantirEstilo() {
    if (document.querySelector('link[href="install.css"]')) { return; }
    var link = document.createElement('link');
    link.rel = 'stylesheet';
    link.href = 'install.css';
    document.head.appendChild(link);
  }

  var SVG_BUSCA = '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/></svg>';
  var SVG_ALERTA = '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="12" cy="12" r="10"/><path d="M12 8v4"/><path d="M12 16h.01"/></svg>';
  var SVG_LINK = '<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M15 3h6v6"/><path d="M10 14 21 3"/><path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"/></svg>';

  /* ---------------- ponte: correlaciona job.done pelo jobId ---------------- */

  function aguardarJobDone(jobId) {
    return new Promise(function (resolve, reject) {
      var ouvinte = tmx.bridge.on('job.done', function (p) {
        if (!p || p.jobId !== jobId) { return; }
        tmx.bridge.off('job.done', ouvinte);
        if (p.ok) { resolve(p.result); } else { reject(new Error((p.error && p.error.message) || 'o trabalho falhou')); }
      });
    });
  }

  function chamarAcaoAssincrona(nome, payload) {
    return tmx.bridge.call(nome, payload).then(function (resp) {
      var jobId = resp && resp.jobId;
      if (!jobId) { throw new Error('resposta sem jobId'); }
      return aguardarJobDone(jobId);
    });
  }

  /* A ponte aceita UM job por vez em todo o aplicativo: um lote de
     apps.icons em segundo plano pode estar no unico slot bem na hora do
     clique em Instalar. callComEspera (app.js) espera o slot e incrementa
     tmx.bridge.esperandoUsuario, que o lote de icones consulta pra ceder a
     vez a uma acao do usuario. */
  function chamarAcaoAssincronaComEspera(nome, payload, esperaMs) {
    return tmx.bridge.callComEspera(nome, payload, esperaMs).then(function (resp) {
      var jobId = resp && resp.jobId;
      if (!jobId) { throw new Error('resposta sem jobId'); }
      return aguardarJobDone(jobId);
    });
  }

  /* ---------------- esqueleto ---------------- */

  function montarEsqueleto() {
    var raiz = el('tab-aplicativos');
    raiz.innerHTML =
      '<header class="ap-topo">' +
        '<div class="ap-topo-texto">' +
          '<p class="ap-eyebrow" data-i18n="apps.eyebrow"></p>' +
          '<h1 class="ap-titulo" data-i18n="apps.titulo"></h1>' +
          '<p class="ap-sub" id="app-sub"></p>' +
        '</div>' +
        '<div class="ap-resumo" id="app-resumo" aria-live="polite"><span class="ap-ponto" aria-hidden="true"></span>' +
          '<span id="app-resumo-texto"></span><span id="app-selecionados" hidden>0</span></div>' +
      '</header>' +
      '<div class="ap-barra">' +
        '<label class="ap-busca">' + SVG_BUSCA +
          '<input type="search" id="app-busca" data-i18n-placeholder="apps.buscar" autocomplete="off" spellcheck="false"></label>' +
        '<button type="button" class="btn btn-primary" id="app-btn-instalar" data-i18n="apps.instalar" disabled></button>' +
        '<button type="button" class="btn ap-btn-perigo" id="app-btn-desinstalar" data-i18n="apps.desinstalar" disabled></button>' +
        '<button type="button" class="btn" id="app-btn-exportar" data-i18n="apps.exportar"></button>' +
        '<button type="button" class="btn" id="app-btn-importar" data-i18n="apps.importar"></button>' +
      '</div>' +
      '<p class="ap-aviso" role="note">' + SVG_ALERTA +
        '<span><span data-i18n="apps.avisoAntes"></span><a href="#" id="app-link-bloatware" data-i18n="apps.avisoLink"></a>' +
        '<span data-i18n="apps.avisoDepois"></span></span></p>' +
      '<div class="ap-extras">' +
        '<div class="painel-gerenciadores" id="app-gerenciadores" aria-live="polite"></div>' +
        '<div class="ap-extras-acoes">' +
          '<button type="button" class="btn btn-mini" id="app-btn-atualizar" data-i18n="apps.atualizarTudo"></button>' +
          '<button type="button" class="btn btn-mini" id="app-btn-instalados" aria-pressed="false" data-i18n="apps.soInstalados"></button>' +
          '<button type="button" class="btn btn-mini" id="app-btn-limpar" data-i18n="apps.limparSelecao"></button>' +
        '</div>' +
      '</div>' +
      '<div class="ap-cats" id="app-cats" role="tablist"></div>' +
      '<div class="ap-secao-cab"><h2 id="app-cat-titulo"></h2><span class="ap-secao-contagem" id="app-cat-contagem"></span></div>' +
      '<div class="ap-grade" id="app-grade"><p class="vazio ap-nenhum" data-i18n="apps.carregando"></p></div>' +
      '<p class="ap-rodape" data-i18n="apps.rodape"></p>';
    traduzirEstatico();
  }

  function traduzirEstatico() {
    var raiz = el('tab-aplicativos');
    if (!raiz) { return; }
    if (window.tmx && tmx.i18n && typeof tmx.i18n.apply === 'function') {
      tmx.i18n.apply(raiz);
    } else {
      raiz.querySelectorAll('[data-i18n]').forEach(function (n) { n.textContent = t(n.getAttribute('data-i18n')); });
      raiz.querySelectorAll('[data-i18n-placeholder]').forEach(function (n) { n.placeholder = t(n.getAttribute('data-i18n-placeholder')); });
    }
    var busca = el('app-busca');
    if (busca) { busca.setAttribute('aria-label', t('apps.buscarAria')); }
  }

  /* ---------------- painel de gerenciadores ---------------- */

  function criarItemGerenciador(nome, dados) {
    var span = document.createElement('span');
    span.className = 'gm';
    dados = dados || {};
    var disponivel = !!dados.disponivel;
    var marca = disponivel ? '✓' : '✗';
    var classe = disponivel ? 'ok' : 'falta';
    var versao = disponivel && dados.versao ? (' ' + dados.versao) : '';
    span.innerHTML = '<strong>' + escapeHtml(nome) + '</strong> <span class="' + classe + '">' + marca + '</span>' + escapeHtml(versao);
    return span;
  }

  var ultimoGerenciadores = null;

  function renderGerenciadores(r) {
    r = r || { winget: {}, choco: {} };
    ultimoGerenciadores = r;
    var cont = el('app-gerenciadores');
    if (!cont) { return; }
    cont.innerHTML = '';
    cont.appendChild(criarItemGerenciador('winget', r.winget));
    cont.appendChild(criarItemGerenciador('choco', r.choco));

    if (!r.winget || !r.winget.disponivel) {
      var btnReparar = document.createElement('button');
      btnReparar.type = 'button';
      btnReparar.className = 'btn btn-mini';
      btnReparar.id = 'app-btn-reparar-winget';
      btnReparar.textContent = t('apps.repararWinget');
      btnReparar.addEventListener('click', confirmarRepararWinget);
      cont.appendChild(btnReparar);
    }

    if (!r.choco || !r.choco.disponivel) {
      var btnChoco = document.createElement('button');
      btnChoco.type = 'button';
      btnChoco.className = 'btn btn-mini';
      btnChoco.id = 'app-btn-instalar-choco';
      btnChoco.textContent = t('apps.instalarChoco');
      btnChoco.addEventListener('click', confirmarInstalarChoco);
      cont.appendChild(btnChoco);
    }
  }

  function atualizarGerenciadores() {
    return tmx.bridge.call('apps.managers').then(renderGerenciadores).catch(function (e) {
      tmx.toast(t('apps.falhaGerenciadores', { erro: e.message }), 'erro');
      // Repropaga: tabs.show precisa SABER que a carga falhou para tentar de
      // novo na proxima abertura da aba.
      throw e;
    });
  }

  function confirmarRepararWinget() {
    tmx.modal.open({
      titulo: t('apps.reparar.titulo'),
      html: t('apps.reparar.texto'),
      botoes: [
        { rotulo: t('apps.cancelar'), classe: 'btn' },
        {
          rotulo: t('apps.reparar.botao'), classe: 'btn btn-primary', onClick: function () {
            tmx.toast(t('apps.reparar.andamento'), 'aviso');
            chamarAcaoAssincronaComEspera('apps.repairWinget', { consentido: true }).then(function (r) {
              tmx.toast(r && r.ok ? ('winget: ' + r.detalhe) : t('apps.reparar.falha', { erro: r && r.detalhe }), r && r.ok ? 'ok' : 'erro');
              return atualizarGerenciadores();
            }).catch(function (e) {
              tmx.toast(t('apps.reparar.falha', { erro: e.message }), 'erro');
            });
          }
        }
      ]
    });
  }

  function confirmarInstalarChoco() {
    tmx.modal.open({
      titulo: t('apps.choco.titulo'),
      html: t('apps.choco.texto'),
      botoes: [
        { rotulo: t('apps.cancelar'), classe: 'btn' },
        {
          rotulo: t('apps.choco.botao'), classe: 'btn btn-primary', onClick: function () {
            tmx.toast(t('apps.choco.andamento'), 'aviso');
            chamarAcaoAssincronaComEspera('apps.installChoco', { consentido: true }).then(function (r) {
              tmx.toast(r && r.ok ? t('apps.choco.ok') : t('apps.choco.falha', { erro: r && r.detalhe }), r && r.ok ? 'ok' : 'erro');
              return atualizarGerenciadores();
            }).catch(function (e) {
              tmx.toast(t('apps.choco.falha', { erro: e.message }), 'erro');
            });
          }
        }
      ]
    });
  }

  /* ---------------- logos dos apps ----------------
   *
   * Regra central (decisao do time): icone NUNCA bloqueia acao do usuario e
   * NUNCA perde id. Isso significa:
   *   - no maximo UM lote de apps.icons em voo por vez (variavel local
   *     'processando' abaixo) - nunca dispara um segundo antes do primeiro
   *     terminar;
   *   - um id so vira 'solicitado' (nunca mais pedido de novo) quando o
   *     LOTE INTEIRO responde com sucesso - numa rejeicao (rede, ou "ja
   *     existe um trabalho em andamento" por causa de outra acao do
   *     usuario ocupando o slot), os ids voltam pra fila e a proxima
   *     tentativa espera um backoff crescente (1s, 2s, 4s, ... ate 15s);
   *   - dentro de um lote com sucesso, os ids que o back-end devolveu em
   *     'pendentes' (cortados pelo orcamento de tempo do LOTE, nao
   *     resolvidos) NAO viram 'solicitados' - continuam na fila pro proximo
   *     lote, so os processados de verdade saem;
   *   - se o MESMO CONJUNTO de ids (a assinatura do lote, nao um contador
   *     global) falhar de verdade 3 vezes seguidas (nao contando "trabalho
   *     em andamento", que e esperado e transitorio - ate a propria carga
   *     inicial da aba Ajustes pode segurar o slot por varios segundos),
   *     desiste desses ids por esta sessao (ficam com as iniciais) pra nao
   *     travar os ids atras deles pra sempre (bloqueio de cabeca de fila);
   *   - uma acao do USUARIO tentando pegar o slot (tmx.bridge.esperandoUsuario,
   *     de app.js) sempre tem prioridade: o lote de icone espera e tenta de
   *     novo em vez de competir; e entre lotes consecutivos ha sempre pelo
   *     menos 400ms de espaco, pro slot ficar livre tempo suficiente pra uma
   *     chamada do usuario conseguir a vez;
   *   - lote de 10 no front (o back-end aceita ate 40, mas um lote grande
   *     demora mais e atrasa a descoberta de que o slot esta ocupado).
   */

  var iconesEstado = {
    cache: {},        // id -> { src, origem }
    solicitados: {},  // id -> true (em sucesso, ou apos desistir - nunca em falha simples)
    fila: [],
    timer: null,
    observer: null,
    elementos: {},     // id -> elemento <span class="app-icone">
    processando: false,
    backoffMs: 1000,
    falhasConsecutivas: 0,
    assinaturaFalhas: null  // ids do ultimo lote que falhou, junto - ver ICONES_MAX_FALHAS_CONSECUTIVAS
  };

  var ICONES_LOTE_MAX = 10;
  var ICONES_BACKOFF_MAX_MS = 15000;
  var ICONES_MAX_FALHAS_CONSECUTIVAS = 3;
  var ICONES_ESPACAMENTO_MIN_MS = 400; // >= 400ms entre lotes: da tempo de uma acao do usuario pegar o slot

  function calcularIniciais(nome) {
    var partes = String(nome || '').trim().split(/\s+/).filter(Boolean);
    var texto = '';
    if (partes.length >= 2) {
      texto = (partes[0].charAt(0) || '') + (partes[1].charAt(0) || '');
    } else if (partes.length === 1) {
      texto = partes[0].substring(0, 2);
    }
    return texto.toUpperCase();
  }

  function aplicarIconeNoElemento(span, dados) {
    if (!span || !dados || typeof dados.src !== 'string') { return; }
    // So aceita data URI de PNG: nunca joga o que veio da ponte direto num
    // atributo src sem checar a forma esperada.
    if (dados.src.indexOf('data:image/png;base64,') !== 0) { return; }
    var img = document.createElement('img');
    img.width = 44;
    img.height = 44;
    img.alt = '';
    // Nunca aparece icone quebrado: se a imagem nao decodificar, volta para
    // as iniciais do app.
    img.onerror = function () {
      span.classList.remove('tem-imagem');
      span.textContent = span.dataset.iniciais || '';
    };
    img.src = dados.src;
    span.innerHTML = '';
    span.appendChild(img);
    span.classList.add('tem-imagem');
  }

  function obterObserverIcones() {
    if (iconesEstado.observer) { return iconesEstado.observer; }
    if (typeof IntersectionObserver === 'undefined') { return null; }
    iconesEstado.observer = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (!entry.isIntersecting) { return; }
        iconesEstado.observer.unobserve(entry.target);
        enfileirarIcone(entry.target.dataset.id);
      });
    }, { root: null, rootMargin: '200px 0px', threshold: 0.01 });
    return iconesEstado.observer;
  }

  function enfileirarIcone(id) {
    if (!id || iconesEstado.cache[id] || iconesEstado.solicitados[id]) { return; }
    if (iconesEstado.fila.indexOf(id) >= 0) { return; }
    iconesEstado.fila.push(id);
    agendarLoteIcones(150);
  }

  function agendarLoteIcones(atrasoMs) {
    if (iconesEstado.timer) { return; }
    iconesEstado.timer = window.setTimeout(function () {
      iconesEstado.timer = null;
      processarLoteIcones();
    }, atrasoMs);
  }

  function processarLoteIcones() {
    if (iconesEstado.processando) { return; } // no maximo um lote em voo
    if (!iconesEstado.fila.length) { return; }

    // Uma acao do USUARIO esta tentando pegar o slot unico da ponte agora
    // (tmx.bridge.esperandoUsuario, incrementado por bridge.callComEspera em
    // app.js) - o lote de icone e trabalho de fundo, sem usuario esperando
    // por ele; espera essa acao passar na frente em vez de competir pelo
    // slot bem na hora em que o usuario clicou em algo.
    if (window.tmx && tmx.bridge && tmx.bridge.esperandoUsuario > 0) {
      agendarLoteIcones(ICONES_ESPACAMENTO_MIN_MS);
      return;
    }

    var lote = iconesEstado.fila.slice(0, ICONES_LOTE_MAX);
    iconesEstado.processando = true;

    chamarAcaoAssincrona('apps.icons', { ids: lote }).then(function (r) {
      // Sucesso do LOTE: os ids que o back-end PROCESSOU (nao devolvidos em
      // 'pendentes' - cortados pelo orcamento de tempo do lote) saem da fila
      // e viram 'solicitados', mesmo sem icone (ausencia e resposta valida,
      // nao falha). Os 'pendentes' continuam na fila do jeito que estao -
      // nunca marcados, vao no proximo lote.
      var pendentesSet = {};
      ((r && r.pendentes) || []).forEach(function (id) { pendentesSet[id] = true; });

      iconesEstado.fila = iconesEstado.fila.filter(function (id) {
        return lote.indexOf(id) < 0 || pendentesSet[id];
      });
      lote.forEach(function (id) {
        if (!pendentesSet[id]) { iconesEstado.solicitados[id] = true; }
      });
      iconesEstado.backoffMs = 1000; // reseta o backoff apos um sucesso
      iconesEstado.falhasConsecutivas = 0;
      iconesEstado.assinaturaFalhas = null;

      var icons = (r && r.icons) || {};
      Object.keys(icons).forEach(function (id) {
        var dados = icons[id];
        if (!dados) { return; }
        iconesEstado.cache[id] = dados;
        aplicarIconeNoElemento(iconesEstado.elementos[id], dados);
      });

      iconesEstado.processando = false;
      // >= 400ms (nao mais 50ms): da tempo de uma chamada callComEspera
      // pendurada (contada em tmx.bridge.esperandoUsuario) conseguir a
      // vez no slot antes do proximo lote de icone tentar de novo.
      if (iconesEstado.fila.length) { agendarLoteIcones(ICONES_ESPACAMENTO_MIN_MS); }
    }).catch(function (e) {
      // Falha do LOTE: os ids CONTINUAM na fila (nunca saem - nada foi
      // marcado 'solicitado'), e a proxima tentativa espera um backoff
      // crescente. Silencioso de proposito: nunca vira toast, o app so
      // continua com as iniciais ate a proxima tentativa.
      iconesEstado.processando = false;

      // "Ja existe um trabalho em andamento" e uma rejeicao ESPERADA e
      // TRANSITORIA (outra acao - ate o carregamento inicial da propria
      // aba Ajustes - esta usando o unico slot de job da ponte no
      // momento; a doc do proprio chamarJobComEspera em configure.js
      // registra que isso pode levar "varios segundos"). Isso NUNCA conta
      // pro contador de desistencia - so um erro de verdade (bridge quebrada,
      // resposta malformada) e que indica que o LOTE em si tem algo errado.
      // Sem essa distincao, a contencao normal do slot no arranque da
      // janela sozinha ja bastava pra desistir de icones que teriam
      // funcionado com so mais um pouco de espera.
      var ocupado = e && /trabalho em andamento/i.test(e.message);
      if (!ocupado) {
        // O contador de desistencia e do LOTE (o conjunto de ids), nao
        // global: se a fila mudou desde a ultima falha (ex.: um lote
        // anterior desistiu, ou 'pendentes' devolveu um conjunto diferente),
        // 3 falhas de lotes DIFERENTES nunca deveriam se somar - cada
        // conjunto de ids merece suas proprias 3 chances.
        var assinatura = lote.join(',');
        if (assinatura !== iconesEstado.assinaturaFalhas) {
          iconesEstado.assinaturaFalhas = assinatura;
          iconesEstado.falhasConsecutivas = 0;
        }
        iconesEstado.falhasConsecutivas++;

        if (iconesEstado.falhasConsecutivas >= ICONES_MAX_FALHAS_CONSECUTIVAS) {
          // Bloqueio de cabeca de fila: o MESMO lote falhou (de verdade) 3
          // vezes seguidas. Desiste DESTA SESSAO (ficam com as iniciais,
          // nunca mais pedidos) pra nao travar os ids atras deles pra sempre.
          lote.forEach(function (id) { iconesEstado.solicitados[id] = true; });
          iconesEstado.fila = iconesEstado.fila.filter(function (id) { return lote.indexOf(id) < 0; });
          iconesEstado.falhasConsecutivas = 0;
          iconesEstado.assinaturaFalhas = null;
          iconesEstado.backoffMs = 1000;
          if (iconesEstado.fila.length) { agendarLoteIcones(ICONES_ESPACAMENTO_MIN_MS); }
          return;
        }
      }

      var espera = Math.max(ICONES_ESPACAMENTO_MIN_MS, iconesEstado.backoffMs);
      iconesEstado.backoffMs = Math.min(iconesEstado.backoffMs * 2, ICONES_BACKOFF_MAX_MS);
      agendarLoteIcones(espera);
    });
  }

  var iconesOuvinteSlotLigado = false;

  function ligarEsperaDeSlotLivreIcones() {
    // Assim que QUALQUER job termina (o global job.done - nao so os desta
    // aba), o slot unico da ponte fica livre: se ha ids esperando e nenhum
    // lote em voo, tenta na hora em vez de esperar o backoff todo. So
    // acelera - o backoff continua sendo a rede de seguranca se isso nunca
    // disparar (ex.: pagina carregada antes deste listener existir).
    if (iconesOuvinteSlotLigado || !window.tmx || !tmx.bridge || typeof tmx.bridge.on !== 'function') { return; }
    iconesOuvinteSlotLigado = true;
    tmx.bridge.on('job.done', function () {
      if (iconesEstado.processando || !iconesEstado.fila.length) { return; }
      if (iconesEstado.timer) { window.clearTimeout(iconesEstado.timer); iconesEstado.timer = null; }
      // Nao dispara na hora: uma acao do usuario encadeada (job A termina e a
      // chamada B sai num microtask depois) ainda nao incrementou
      // esperandoUsuario; o espacamento minimo deixa B pegar o slot primeiro.
      agendarLoteIcones(ICONES_ESPACAMENTO_MIN_MS);
    });
  }

  function criarIconeApp(app) {
    var span = document.createElement('span');
    span.className = 'app-icone';
    span.setAttribute('aria-hidden', 'true');
    span.dataset.id = app.id;
    span.dataset.iniciais = calcularIniciais(app.nome);
    iconesEstado.elementos[app.id] = span;

    var cacheado = iconesEstado.cache[app.id];
    if (cacheado) {
      aplicarIconeNoElemento(span, cacheado);
    } else {
      span.textContent = span.dataset.iniciais;
      var obs = obterObserverIcones();
      if (obs) {
        obs.observe(span);
      } else {
        // Sem IntersectionObserver: pede direto, sem esperar visibilidade.
        enfileirarIcone(app.id);
      }
    }
    return span;
  }

  /* ---------------- cards ---------------- */

  function corDasIniciais(id) {
    var h = 0;
    for (var i = 0; i < id.length; i++) { h = (h * 31 + id.charCodeAt(i)) | 0; }
    return 'cor-' + (Math.abs(h) % 5); // cor-0 = accent-text (classe padrao)
  }

  function criarCardApp(app) {
    // <label> no card inteiro: clicar em qualquer ponto marca a caixa. O link
    // do site faz preventDefault, o que tambem cancela a ativacao do label.
    var card = document.createElement('label');
    card.className = 'app-card app';
    card.dataset.id = app.id;
    card.dataset.cat = app.categoria;
    card.setAttribute('for', 'app-' + app.id);

    var cb = document.createElement('input');
    cb.type = 'checkbox';
    cb.id = 'app-' + app.id;
    cb.checked = !!estado.selecionados[app.id];
    cb.setAttribute('aria-label', t('apps.selecionar', { nome: app.nome }));
    cb.addEventListener('change', function () {
      if (cb.checked) { estado.selecionados[app.id] = true; } else { delete estado.selecionados[app.id]; }
      card.classList.toggle('app-marcado', cb.checked);
      atualizarContagemSelecionados();
    });
    card.classList.toggle('app-marcado', cb.checked);
    card.appendChild(cb);

    var icone = criarIconeApp(app);
    icone.classList.add(corDasIniciais(app.id));
    card.appendChild(icone);

    var corpo = document.createElement('div');
    corpo.className = 'app-corpo';

    var linha1 = document.createElement('div');
    linha1.className = 'app-linha1';

    var nome = document.createElement('span');
    nome.className = 'app-nome';
    nome.textContent = app.nome;
    linha1.appendChild(nome);

    var selo = document.createElement('span');
    selo.className = 'app-selo-instalado';
    selo.dataset.role = 'selo-instalado';
    selo.textContent = t('apps.instalado');
    // style.display e nao o atributo hidden: .app-selo-instalado define
    // display e ganharia do [hidden] do navegador.
    selo.style.display = (estado.instalados && estado.instalados[app.id]) ? '' : 'none';
    linha1.appendChild(selo);

    if (app.link) {
      var a = document.createElement('a');
      a.href = '#';
      a.className = 'app-link';
      a.innerHTML = SVG_LINK;
      a.title = t('apps.siteOficial', { nome: app.nome });
      a.setAttribute('aria-label', a.title);
      a.addEventListener('click', function (e) {
        e.preventDefault();
        e.stopPropagation();
        tmx.bridge.call('shell.openUrl', { url: app.link }).catch(function (err) {
          tmx.toast(t('apps.falhaLink', { erro: err.message }), 'erro');
        });
      });
      linha1.appendChild(a);
    }
    corpo.appendChild(linha1);

    var desc = document.createElement('p');
    desc.className = 'app-desc';
    desc.textContent = descricaoDe(app);
    corpo.appendChild(desc);

    if (app.winget) {
      var id = document.createElement('code');
      id.className = 'app-winget';
      id.textContent = app.winget;
      corpo.appendChild(id);
    }

    card.appendChild(corpo);
    return card;
  }

  function renderCatalogo() {
    var grade = el('app-grade');
    if (!grade) { return; }

    // Re-render: desconecta o observer dos elementos antigos e limpa o mapa
    // (cache/solicitados/fila continuam: sao por id de app).
    if (iconesEstado.observer) { iconesEstado.observer.disconnect(); }
    iconesEstado.elementos = {};

    grade.innerHTML = '';
    estado.apps = {};
    var categorias = (estado.catalogo && estado.catalogo.categorias) || [];
    categorias.forEach(function (cat) {
      (cat.apps || []).forEach(function (app) {
        if (!app.categoria) { app.categoria = cat.id; }
        estado.apps[app.id] = app;
        grade.appendChild(criarCardApp(app));
      });
    });

    var vazio = document.createElement('p');
    vazio.className = 'vazio ap-nenhum';
    vazio.id = 'app-nenhum';
    vazio.textContent = t('apps.nenhum');
    vazio.hidden = true;
    grade.appendChild(vazio);

    if (!categorias.some(function (c) { return c.id === estado.categoria; }) && categorias.length) {
      estado.categoria = categorias[0].id;
    }
    renderCategorias();
    atualizarSub();
    aplicarFiltro();
    atualizarContagemSelecionados();
  }

  function renderCategorias() {
    var cont = el('app-cats');
    if (!cont) { return; }
    cont.innerHTML = '';
    var categorias = (estado.catalogo && estado.catalogo.categorias) || [];
    categorias.slice().sort(function (a, b) {
      return ORDEM_CATEGORIAS.indexOf(a.id) - ORDEM_CATEGORIAS.indexOf(b.id);
    }).forEach(function (cat) {
      var b = document.createElement('button');
      b.type = 'button';
      b.className = 'ap-cat';
      b.setAttribute('role', 'tab');
      b.dataset.cat = cat.id;
      b.setAttribute('aria-selected', cat.id === estado.categoria ? 'true' : 'false');
      b.textContent = rotuloCategoria(cat);
      b.addEventListener('click', function () {
        estado.categoria = cat.id;
        // Trocar de categoria sai da busca: a busca olha o catalogo inteiro.
        if (estado.termoBusca) {
          estado.termoBusca = '';
          var busca = el('app-busca');
          if (busca) { busca.value = ''; }
        }
        cont.querySelectorAll('.ap-cat').forEach(function (x) {
          x.setAttribute('aria-selected', x === b ? 'true' : 'false');
        });
        aplicarFiltro();
      });
      cont.appendChild(b);
    });
  }

  function rotuloCategoria(cat) {
    var chave = 'apps.cat.' + cat.id;
    var r = t(chave);
    return r === chave ? (cat.nome || cat.id) : r;
  }

  function atualizarSub() {
    var sub = el('app-sub');
    if (!sub) { return; }
    var cats = (estado.catalogo && estado.catalogo.categorias) || [];
    if (!cats.length) { sub.textContent = t('apps.subCarregando'); return; }
    sub.textContent = t('apps.sub', { n: Object.keys(estado.apps).length, c: cats.length });
  }

  function carregarCatalogo() {
    return tmx.bridge.call('apps.catalog').then(function (r) {
      estado.catalogo = r;
      renderCatalogo();
    }).catch(function (e) {
      var grade = el('app-grade');
      if (grade) { grade.innerHTML = '<p class="vazio ap-nenhum">' + escapeHtml(t('apps.falhaCatalogo', { erro: e.message })) + '</p>'; }
      throw e;
    });
  }

  /* ---------------- filtro e selecao ---------------- */

  function combinaBusca(app, termo) {
    if (!termo) { return true; }
    var alvo = (app.nome + ' ' + (app.descricao || '') + ' ' + (app.descricaoEn || '') + ' ' + (app.winget || '')).toLowerCase();
    return alvo.indexOf(termo) >= 0;
  }

  function aplicarFiltro() {
    var termo = estado.termoBusca || '';
    var visiveis = 0;
    document.querySelectorAll('#tab-aplicativos .app-card').forEach(function (card) {
      var app = estado.apps[card.dataset.id];
      if (!app) { return; }
      var naCategoria = termo ? true : (app.categoria === estado.categoria);
      var ok = naCategoria && combinaBusca(app, termo) &&
        (!estado.soInstalados || !!(estado.instalados && estado.instalados[app.id]));
      card.classList.toggle('app-oculto', !ok);
      card.classList.toggle('app', ok);
      if (ok) { visiveis++; }
    });

    var titulo = el('app-cat-titulo');
    var contagem = el('app-cat-contagem');
    if (titulo) {
      if (termo) {
        titulo.textContent = t('apps.resultados');
      } else {
        var cat = ((estado.catalogo && estado.catalogo.categorias) || []).filter(function (c) { return c.id === estado.categoria; })[0];
        titulo.textContent = cat ? rotuloCategoria(cat) : '';
      }
    }
    if (contagem) { contagem.textContent = t('apps.nApps', { n: visiveis }); }
    var nenhum = el('app-nenhum');
    if (nenhum) { nenhum.hidden = visiveis > 0; }
    var cats = el('app-cats');
    if (cats) { cats.classList.toggle('ap-buscando', !!termo); }
  }

  function contarInstalados() {
    if (!estado.instalados) { return 0; }
    return Object.keys(estado.instalados).filter(function (id) { return !!estado.apps[id]; }).length;
  }

  function atualizarContagemSelecionados() {
    var n = Object.keys(estado.selecionados).length;
    var span = el('app-selecionados');
    if (span) { span.textContent = String(n); }
    var resumo = el('app-resumo-texto');
    if (resumo) { resumo.textContent = t('apps.resumo', { s: n, i: contarInstalados() }); }
    var btnInstalar = el('app-btn-instalar');
    var btnDesinstalar = el('app-btn-desinstalar');
    if (btnInstalar) { btnInstalar.disabled = (n === 0); }
    if (btnDesinstalar) { btnDesinstalar.disabled = (n === 0); }
  }

  function marcarSelecao(ids) {
    ids.forEach(function (id) {
      if (!estado.apps[id]) { return; }
      estado.selecionados[id] = true;
      var cb = el('app-' + id);
      if (cb) {
        cb.checked = true;
        var card = cb.closest('.app-card');
        if (card) { card.classList.add('app-marcado'); }
      }
    });
    atualizarContagemSelecionados();
  }

  function limparSelecao() {
    estado.selecionados = {};
    document.querySelectorAll('#tab-aplicativos .app-card input[type=checkbox]').forEach(function (cb) { cb.checked = false; });
    document.querySelectorAll('#tab-aplicativos .app-card.app-marcado').forEach(function (c) { c.classList.remove('app-marcado'); });
    atualizarContagemSelecionados();
  }

  /* ---------------- instalados (selo "Instalado") ---------------- */

  function carregarInstalados() {
    var payload = null;
    if (testMode()) {
      payload = { simular: Array.isArray(window.tmxSimularInstalados) ? window.tmxSimularInstalados : SIMULAR_INSTALADOS_PADRAO };
    }
    // winget list pode demorar e o slot pode estar com um lote de icones:
    // espera ate 90 s pelo slot.
    return chamarAcaoAssincronaComEspera('apps.installed', payload, 90000).then(function (r) {
      var mapa = {};
      ((r && r.itens) || []).forEach(function (it) {
        if (it && it.instalado && it.catalogId) { mapa[it.catalogId] = true; }
      });
      estado.instalados = mapa;
      pintarInstalados();
      return mapa;
    }).catch(function (e) {
      tmx.toast(t('apps.falhaInstalados', { erro: e.message }), 'erro');
    });
  }

  function pintarInstalados() {
    var mapa = estado.instalados || {};
    document.querySelectorAll('#tab-aplicativos .app-card').forEach(function (card) {
      var instalado = !!mapa[card.dataset.id];
      card.classList.toggle('app-instalado', instalado);
      var selo = card.querySelector('[data-role="selo-instalado"]');
      if (selo) { selo.style.display = instalado ? '' : 'none'; }
    });
    aplicarFiltro();
    atualizarContagemSelecionados();
  }

  /* ---------------- resultados de instalar/desinstalar/atualizar ---------------- */

  function mostrarResultados(titulo, itens) {
    itens = itens || [];
    var linhas = itens.map(function (it) {
      var classe = 'res-' + (it.resultado || 'falha');
      return '<tr class="' + escapeHtml(classe) + '">' +
        '<td>' + escapeHtml(it.pacote) + '</td>' +
        '<td>' + escapeHtml(it.gerenciador || '—') + '</td>' +
        '<td>' + escapeHtml(it.resultado || '') + '</td>' +
        '<td>' + escapeHtml(it.detalhe || '') + '</td>' +
        '</tr>';
    }).join('');

    var html = itens.length
      ? '<table class="resultado-instalacao"><thead><tr><th>' + escapeHtml(t('apps.res.pacote')) + '</th><th>' +
        escapeHtml(t('apps.res.gerenciador')) + '</th><th>' + escapeHtml(t('apps.res.resultado')) + '</th><th>' +
        escapeHtml(t('apps.res.detalhe')) + '</th></tr></thead><tbody>' + linhas + '</tbody></table>'
      : '<p class="vazio">' + escapeHtml(t('apps.res.vazio')) + '</p>';

    tmx.modal.open({ titulo: titulo, html: html, botoes: [{ rotulo: t('apps.fechar') }] });
  }

  function rodarAcaoPacotes(acao, ids, rotulo) {
    var payload = ids ? { ids: ids } : null;
    tmx.toast(rotulo + '...', 'aviso');
    chamarAcaoAssincronaComEspera(acao, payload).then(function (resultado) {
      mostrarResultados(rotulo, resultado);
      return carregarInstalados();
    }).catch(function (e) {
      tmx.toast(t('apps.acaoFalhou', { acao: rotulo, erro: e.message }), 'erro');
    });
  }

  /* ---------------- exportar / importar ---------------- */

  /* No modo de teste os dialogos nativos nao abrem: a suite de GUI informa o
     caminho/conteudo simulado por window.tmxSimularArquivo = { salvar,
     abrirCaminho, abrirConteudo }. Fora do modo de teste o back-end ignora. */
  function simulacaoArquivo() { return (testMode() && window.tmxSimularArquivo) || {}; }

  function exportarLista() {
    var ids = Object.keys(estado.selecionados);
    if (!ids.length) { tmx.toast(t('apps.selecioneExportar'), 'aviso'); return; }
    tmx.bridge.call('apps.export', { ids: ids }).then(function (r) {
      var doc = { formato: 'tweakmaxing-apps', versao: 1, geradoEm: r && r.geradoEm, apps: (r && r.apps) || [] };
      var payload = { conteudo: JSON.stringify(doc, null, 2), nomeSugerido: 'tweakmaxing-apps.json' };
      var sim = simulacaoArquivo();
      if (sim.salvar) { payload.simular = sim.salvar; }
      return tmx.bridge.call('shell.saveFile', payload).then(function (s) {
        if (!s || s.cancelado) { return; }
        tmx.toast(t('apps.exportado', { n: doc.apps.length, caminho: s.caminho }), 'ok');
      });
    }).catch(function (e) {
      tmx.toast(t('apps.falhaExportar', { erro: e.message }), 'erro');
    });
  }

  function importarLista() {
    var payload = { filtro: 'JSON (*.json)|*.json|*.*|*.*' };
    var sim = simulacaoArquivo();
    if (sim.abrirCaminho) { payload.simularCaminho = sim.abrirCaminho; payload.simularConteudo = sim.abrirConteudo || ''; }
    tmx.bridge.call('shell.openFile', payload).then(function (f) {
      if (!f || f.cancelado) { return null; }
      return tmx.bridge.call('apps.import', { conteudo: f.conteudo || '' }).then(function (r) {
        var ids = (r && r.ids) || [];
        var desconhecidos = (r && r.desconhecidos) || [];
        marcarSelecao(ids);
        // Mostra a categoria do primeiro app importado, para a marcacao
        // aparecer na tela.
        if (ids.length && estado.apps[ids[0]] && !estado.termoBusca) {
          var alvo = estado.apps[ids[0]].categoria;
          var botao = document.querySelector('#app-cats .ap-cat[data-cat="' + alvo + '"]');
          if (botao) { botao.click(); }
        }
        tmx.toast(desconhecidos.length
          ? t('apps.importadoDesconhecidos', { n: ids.length, d: desconhecidos.length })
          : t('apps.importado', { n: ids.length }), desconhecidos.length ? 'aviso' : 'ok');
      });
    }).catch(function (e) {
      tmx.toast(t('apps.falhaImportar', { erro: e.message }), 'erro');
    });
  }

  /* ---------------- link para Otimizacoes > Remover bloatware ---------------- */

  function irParaBloatware(e) {
    if (e) { e.preventDefault(); }
    if (!window.tmx || !tmx.tabs) { return; }
    tmx.tabs.show('otimizacoes');
    // A tela de Otimizacoes e de outro modulo: avisa por evento e, de
    // reserva, tenta rolar ate o card do APM-006 quando ele existir.
    document.dispatchEvent(new CustomEvent('tmx:focarAjuste', { detail: { id: 'APM-006', tab: 'otimizacoes' } }));
    var tentativas = 0;
    (function rolar() {
      var alvo = document.querySelector('#tab-otimizacoes [data-id="APM-006"]');
      if (alvo && typeof alvo.scrollIntoView === 'function') { alvo.scrollIntoView({ block: 'center' }); return; }
      if (++tentativas < 10) { setTimeout(rolar, 300); }
    })();
  }

  /* ---------------- idioma ---------------- */

  function retraduzir() {
    if (!el('app-grade')) { return; }
    traduzirEstatico();
    atualizarSub();
    if (ultimoGerenciadores) { renderGerenciadores(ultimoGerenciadores); }
    document.querySelectorAll('#app-cats .ap-cat').forEach(function (b) {
      var cat = ((estado.catalogo && estado.catalogo.categorias) || []).filter(function (c) { return c.id === b.dataset.cat; })[0];
      if (cat) { b.textContent = rotuloCategoria(cat); }
    });
    document.querySelectorAll('#tab-aplicativos .app-card').forEach(function (card) {
      var app = estado.apps[card.dataset.id];
      if (!app) { return; }
      var desc = card.querySelector('.app-desc');
      if (desc) { desc.textContent = descricaoDe(app); }
      var selo = card.querySelector('[data-role="selo-instalado"]');
      if (selo) { selo.textContent = t('apps.instalado'); }
      var link = card.querySelector('.app-link');
      if (link) { link.title = t('apps.siteOficial', { nome: app.nome }); link.setAttribute('aria-label', link.title); }
      var cb = card.querySelector('input[type=checkbox]');
      if (cb) { cb.setAttribute('aria-label', t('apps.selecionar', { nome: app.nome })); }
    });
    var nenhum = el('app-nenhum');
    if (nenhum) { nenhum.textContent = t('apps.nenhum'); }
    aplicarFiltro();
    atualizarContagemSelecionados();
  }

  document.addEventListener('tmx:lang', retraduzir);

  /* ---------------- barra de acoes ---------------- */

  function ligarEventos() {
    el('app-busca').addEventListener('input', function (e) {
      estado.termoBusca = e.target.value.trim().toLowerCase();
      aplicarFiltro();
    });

    el('app-btn-limpar').addEventListener('click', limparSelecao);

    el('app-btn-instalados').addEventListener('click', function (e) {
      estado.soInstalados = !estado.soInstalados;
      e.currentTarget.setAttribute('aria-pressed', estado.soInstalados ? 'true' : 'false');
      if (estado.soInstalados && !estado.instalados) {
        carregarInstalados();
      } else {
        aplicarFiltro();
      }
    });

    el('app-btn-instalar').addEventListener('click', function () {
      var ids = Object.keys(estado.selecionados);
      if (!ids.length) { tmx.toast(t('apps.selecioneUm'), 'aviso'); return; }
      rodarAcaoPacotes('apps.install', ids, t('apps.instalando'));
    });

    el('app-btn-desinstalar').addEventListener('click', function () {
      var ids = Object.keys(estado.selecionados);
      if (!ids.length) { tmx.toast(t('apps.selecioneUm'), 'aviso'); return; }
      rodarAcaoPacotes('apps.uninstall', ids, t('apps.desinstalando'));
    });

    el('app-btn-atualizar').addEventListener('click', function () {
      rodarAcaoPacotes('apps.upgradeAll', null, t('apps.atualizando'));
    });

    el('app-btn-exportar').addEventListener('click', exportarLista);
    el('app-btn-importar').addEventListener('click', importarLista);
    el('app-link-bloatware').addEventListener('click', irParaBloatware);
  }

  /* ---------------- arranque da aba ---------------- */

  window.tmxTabs.aplicativos = {
    init: function () {
      garantirEstilo();
      montarEsqueleto();
      ligarEventos();
      ligarEsperaDeSlotLivreIcones();
      atualizarContagemSelecionados();
      atualizarSub();
      // aguardarTodas (e nao Promise.all): espera as duas terminarem antes
      // de rejeitar, para um retry de tabs.show nao comecar com a outra carga
      // ainda no ar. Os instalados vem depois e nao seguram a abertura da
      // aba (winget list pode levar varios segundos).
      return tmx.aguardarTodas([atualizarGerenciadores(), carregarCatalogo()]).then(function () {
        carregarInstalados();
      });
    }
  };
})();
