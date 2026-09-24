/* install.js - aba "Instalar".
 *
 * Catalogo (apps.catalog) e gerenciadores (apps.managers) sao acoes sincronas;
 * instalar/desinstalar/atualizar tudo/listar instalados/reparar winget/
 * instalar choco sao assincronas (bridge.call devolve so { jobId } na hora -
 * o resultado de verdade chega depois via evento job.done, correlacionado
 * aqui pelo jobId porque a ponte nao amarra id de pedido a evento).
 */
(function () {
  'use strict';
  window.tmxTabs = window.tmxTabs || {};

  var estado = {
    catalogo: null,
    selecionados: {},
    instalados: null,
    mostrarInstalados: false,
    termoBusca: ''
  };

  /* ---------------- estilo (app.css nao e desta aba: injeta o proprio) ---------------- */

  function injetarEstilo() {
    if (document.getElementById('estilo-instalar')) { return; }
    var style = document.createElement('style');
    style.id = 'estilo-instalar';
    style.textContent = [
      '#tab-aplicativos .toolbar { display:flex; flex-wrap:wrap; gap:8px; align-items:center; margin-bottom:14px; }',
      '#tab-aplicativos .toolbar input[type=search] { flex:1 1 220px; min-width:160px; padding:6px 10px; border:1px solid var(--linha); border-radius:6px; background:var(--panel-2); color:var(--fg); font:inherit; }',
      '#tab-aplicativos .painel-gerenciadores { display:flex; flex-wrap:wrap; gap:10px 20px; align-items:center; padding:10px 14px; margin-bottom:14px; border:1px solid var(--linha); border-radius:var(--raio); background:var(--panel-2); }',
      '#tab-aplicativos .painel-gerenciadores .gm { display:inline-flex; align-items:center; gap:6px; }',
      '#tab-aplicativos .painel-gerenciadores .gm .ok { color:var(--ok); font-weight:700; }',
      '#tab-aplicativos .painel-gerenciadores .gm .falta { color:var(--danger); font-weight:700; }',
      '#tab-aplicativos details.categoria { border:1px solid var(--linha); border-radius:var(--raio); margin-bottom:8px; background:var(--panel); }',
      '#tab-aplicativos details.categoria > summary { cursor:pointer; padding:10px 14px; font-weight:650; }',
      '#tab-aplicativos .lista-apps { display:grid; grid-template-columns:repeat(auto-fill,minmax(230px,1fr)); gap:2px 10px; padding:4px 14px 12px; }',
      '#tab-aplicativos .app-row { display:flex; align-items:center; gap:4px; padding:5px 4px; border-radius:6px; }',
      '#tab-aplicativos .app-row:hover { background:var(--panel-2); }',
      '#tab-aplicativos .app-row.app-oculto { display:none; }',
      '#tab-aplicativos .app-row label { display:flex; align-items:center; gap:6px; flex:1 1 auto; cursor:pointer; overflow:hidden; min-width:0; }',
      '#tab-aplicativos .app-row .nome-app { overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }',
      '#tab-aplicativos .app-row .link-app { color:var(--muted); text-decoration:none; padding:2px 4px; flex:0 0 auto; }',
      '#tab-aplicativos .app-row .link-app:hover { color:var(--accent); }',
      '#tab-aplicativos .selo-foss { color:var(--ok); flex:0 0 auto; }',
      '#tab-aplicativos .selo-instalado { color:var(--accent); flex:0 0 auto; }',
      '#tab-aplicativos .rodape-nota { margin-top:10px; color:var(--muted); font-size:12px; }',
      '#tab-aplicativos table.resultado-instalacao { width:100%; border-collapse:collapse; font-size:13px; }',
      '#tab-aplicativos table.resultado-instalacao th, #tab-aplicativos table.resultado-instalacao td { text-align:left; padding:5px 8px; border-bottom:1px solid var(--linha); }',
      '#tab-aplicativos table.resultado-instalacao tr.res-ok td:nth-child(3) { color:var(--ok); }',
      '#tab-aplicativos table.resultado-instalacao tr.res-pulado td:nth-child(3) { color:var(--warn); }',
      '#tab-aplicativos table.resultado-instalacao tr.res-falha td:nth-child(3) { color:var(--danger); }',
      '#tab-aplicativos .app-icone { display:inline-flex; align-items:center; justify-content:center; width:32px; height:32px; min-width:32px; border-radius:50%; background:var(--elevated); color:var(--fg); font-weight:600; font-size:11px; letter-spacing:0.02em; flex:0 0 auto; overflow:hidden; }',
      '#tab-aplicativos .app-icone.tem-imagem { background:transparent; border-radius:6px; }',
      '#tab-aplicativos .app-icone img { width:32px; height:32px; object-fit:contain; border-radius:6px; display:block; }'
    ].join('\n');
    document.head.appendChild(style);
  }

  /* ---------------- helpers de texto ---------------- */

  function escapeHtml(s) {
    return String(s === null || s === undefined ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }

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

  /* A ponte aceita UM job por vez em todo o aplicativo, nao so nesta aba: um
     lote de apps.icons rodando em segundo plano (disparado pelo
     IntersectionObserver, sem o usuario pedir) pode estar ocupando o unico
     slot bem na hora em que o usuario clica em Instalar/Desinstalar/etc.
     Sem espera, esse clique falharia na hora com "ja existe um trabalho em
     andamento" por causa de um lote de icone que nem apareceu na tela.
     Usa tmx.bridge.callComEspera (src/web/app.js) em vez de reimplementar a
     mesma espera aqui: alem de nao duplicar a logica, isso incrementa
     tmx.bridge.esperandoUsuario emquanto espera - e o mesmo contador que o
     lote de icones (mais abaixo) consulta pra dar prioridade a uma acao de
     usuario tentando pegar o slot. */
  function chamarAcaoAssincronaComEspera(nome, payload) {
    return tmx.bridge.callComEspera(nome, payload).then(function (resp) {
      var jobId = resp && resp.jobId;
      if (!jobId) { throw new Error('resposta sem jobId'); }
      return aguardarJobDone(jobId);
    });
  }

  /* ---------------- esqueleto ---------------- */

  function montarEsqueleto() {
    var raiz = document.getElementById('tab-aplicativos');
    raiz.innerHTML =
      '<h2>Instalar</h2>' +
      '<div class="painel-gerenciadores" id="app-gerenciadores" aria-live="polite"></div>' +
      '<div class="toolbar">' +
        '<input type="search" id="app-busca" placeholder="Buscar por nome ou descrição" aria-label="Buscar aplicativo por nome ou descrição">' +
        '<button type="button" class="btn btn-primary" id="app-btn-instalar" aria-label="Instalar aplicativos selecionados" disabled>Instalar selecionados (<span id="app-selecionados">0</span>)</button>' +
        '<button type="button" class="btn btn-danger" id="app-btn-desinstalar" aria-label="Desinstalar aplicativos selecionados" disabled>Desinstalar</button>' +
        '<button type="button" class="btn" id="app-btn-atualizar" aria-label="Atualizar todos os aplicativos instalados">Atualizar tudo</button>' +
        '<button type="button" class="btn" id="app-btn-instalados" aria-label="Mostrar somente aplicativos já instalados" aria-pressed="false">Mostrar instalados</button>' +
        '<button type="button" class="btn btn-mini" id="app-btn-limpar" aria-label="Limpar seleção de aplicativos">Limpar seleção</button>' +
        '<button type="button" class="btn btn-mini" id="app-btn-expandir" aria-label="Expandir todas as categorias">Expandir tudo</button>' +
        '<button type="button" class="btn btn-mini" id="app-btn-recolher" aria-label="Recolher todas as categorias">Recolher tudo</button>' +
      '</div>' +
      '<div id="app-categorias"></div>' +
      '<p class="rodape-nota">Instalações não exigem ponto de restauração: desinstalar é a reversão natural.</p>';
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

  function renderGerenciadores(r) {
    r = r || { winget: {}, choco: {} };
    var cont = document.getElementById('app-gerenciadores');
    if (!cont) { return; }
    cont.innerHTML = '';
    cont.appendChild(criarItemGerenciador('winget', r.winget));
    cont.appendChild(criarItemGerenciador('choco', r.choco));

    if (!r.winget || !r.winget.disponivel) {
      var btnReparar = document.createElement('button');
      btnReparar.type = 'button';
      btnReparar.className = 'btn btn-mini';
      btnReparar.id = 'app-btn-reparar-winget';
      btnReparar.textContent = 'Reparar winget';
      btnReparar.setAttribute('aria-label', 'Reparar a instalação do winget');
      btnReparar.addEventListener('click', confirmarRepararWinget);
      cont.appendChild(btnReparar);
    }

    if (!r.choco || !r.choco.disponivel) {
      var btnChoco = document.createElement('button');
      btnChoco.type = 'button';
      btnChoco.className = 'btn btn-mini';
      btnChoco.id = 'app-btn-instalar-choco';
      btnChoco.textContent = 'Instalar Chocolatey';
      btnChoco.setAttribute('aria-label', 'Instalar o Chocolatey');
      btnChoco.addEventListener('click', confirmarInstalarChoco);
      cont.appendChild(btnChoco);
    }
  }

  function atualizarGerenciadores() {
    return tmx.bridge.call('apps.managers').then(renderGerenciadores).catch(function (e) {
      tmx.toast('Falha ao consultar winget/choco: ' + e.message, 'erro');
      // Repropaga: a mensagem inline acima (e o toast) já avisaram o
      // usuário, mas tabs.show precisa SABER que a carga falhou para
      // deixar a aba como não iniciada e tentar de novo na próxima
      // abertura. Engolir o erro aqui deixava a aba vazia para sempre.
      throw e;
    });
  }

  function confirmarRepararWinget() {
    tmx.modal.open({
      titulo: 'Reparar o winget',
      html: '<p>Isso instala ou repara o winget usando o módulo <strong>Microsoft.WinGet.Client</strong> da PowerShell Gallery ' +
            '(<code>Install-Module</code> + <code>Repair-WinGetPackageManager</code>). Pode levar alguns minutos.</p>',
      botoes: [
        { rotulo: 'Cancelar', classe: 'btn' },
        {
          rotulo: 'Reparar', classe: 'btn btn-primary', onClick: function () {
            tmx.toast('Reparando o winget...', 'aviso');
            chamarAcaoAssincronaComEspera('apps.repairWinget', { consentido: true }).then(function (r) {
              tmx.toast(r && r.ok ? ('winget: ' + r.detalhe) : ('Falha ao reparar o winget: ' + (r && r.detalhe)), r && r.ok ? 'ok' : 'erro');
              return atualizarGerenciadores();
            }).catch(function (e) {
              tmx.toast('Falha ao reparar o winget: ' + e.message, 'erro');
            });
          }
        }
      ]
    });
  }

  function confirmarInstalarChoco() {
    tmx.modal.open({
      titulo: 'Instalar o Chocolatey',
      html: '<p>Isso baixa o instalador oficial de <code>https://community.chocolatey.org/install.ps1</code> e roda ele em um ' +
            'processo separado do PowerShell. O SHA-256 do arquivo baixado fica registrado no log.</p>',
      botoes: [
        { rotulo: 'Cancelar', classe: 'btn' },
        {
          rotulo: 'Instalar', classe: 'btn btn-primary', onClick: function () {
            tmx.toast('Instalando o Chocolatey...', 'aviso');
            chamarAcaoAssincronaComEspera('apps.installChoco', { consentido: true }).then(function (r) {
              tmx.toast(r && r.ok ? 'Chocolatey instalado' : ('Falha ao instalar o Chocolatey: ' + (r && r.detalhe)), r && r.ok ? 'ok' : 'erro');
              return atualizarGerenciadores();
            }).catch(function (e) {
              tmx.toast('Falha ao instalar o Chocolatey: ' + e.message, 'erro');
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
    img.width = 32;
    img.height = 32;
    img.alt = '';
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
    iconesEstado.elementos[app.id] = span;

    var cacheado = iconesEstado.cache[app.id];
    if (cacheado) {
      aplicarIconeNoElemento(span, cacheado);
    } else {
      span.textContent = calcularIniciais(app.nome);
      var obs = obterObserverIcones();
      if (obs) {
        obs.observe(span);
      } else {
        // Sem IntersectionObserver (ambiente muito antigo): pede direto, sem
        // esperar visibilidade - nunca deixa a linha sem tentativa de icone.
        enfileirarIcone(app.id);
      }
    }
    return span;
  }

  /* ---------------- catalogo ---------------- */

  function criarLinhaApp(app) {
    var linha = document.createElement('div');
    linha.className = 'app-row app';
    linha.dataset.id = app.id;
    linha.dataset.nome = (app.nome || '').toLowerCase();
    linha.dataset.descricao = (app.descricao || '').toLowerCase();

    var label = document.createElement('label');

    var cb = document.createElement('input');
    cb.type = 'checkbox';
    cb.id = 'app-' + app.id;
    cb.addEventListener('change', function () {
      if (cb.checked) { estado.selecionados[app.id] = true; } else { delete estado.selecionados[app.id]; }
      atualizarContagemSelecionados();
    });
    label.appendChild(cb);
    label.appendChild(criarIconeApp(app));

    var nomeSpan = document.createElement('span');
    nomeSpan.className = 'nome-app';
    nomeSpan.textContent = app.nome;
    label.appendChild(nomeSpan);

    if (app.foss) {
      var seloFoss = document.createElement('span');
      seloFoss.className = 'selo selo-foss';
      seloFoss.textContent = 'FOSS';
      seloFoss.title = 'Código aberto';
      label.appendChild(seloFoss);
    }

    var seloInstalado = document.createElement('span');
    seloInstalado.className = 'selo selo-instalado';
    seloInstalado.textContent = 'instalado';
    seloInstalado.dataset.role = 'selo-instalado';
    // Estilo inline, nao o atributo hidden: app.css define '.selo { display:
    // inline-block }' com a MESMA especificidade de '[hidden]' do UA
    // stylesheet, e o autor sempre vence esse empate - o selo ficaria visivel
    // mesmo com hidden=true. style.display inline tem especificidade maior e
    // realmente esconde.
    seloInstalado.style.display = 'none';
    label.appendChild(seloInstalado);

    linha.appendChild(label);

    if (app.link) {
      var a = document.createElement('a');
      a.href = '#';
      a.className = 'link-app';
      a.textContent = '↗';
      a.title = 'Abrir o site de ' + app.nome;
      a.setAttribute('aria-label', 'Abrir o site de ' + app.nome);
      a.addEventListener('click', function (e) {
        e.preventDefault();
        tmx.bridge.call('shell.openUrl', { url: app.link }).catch(function (err) {
          tmx.toast('Não foi possível abrir o link: ' + err.message, 'erro');
        });
      });
      linha.appendChild(a);
    }

    return linha;
  }

  function renderCategorias() {
    var cont = document.getElementById('app-categorias');
    if (!cont) { return; }

    // Re-render (recarga do catalogo): os elementos antigos vao sumir do
    // DOM - desconecta o observer deles antes (senao ele continua
    // "observando" nos vazios) e limpa o mapa de elementos, que sera
    // repovoado pelas novas linhas abaixo. cache/solicitados/fila
    // continuam (sao por id de app, nao por elemento DOM).
    if (iconesEstado.observer) { iconesEstado.observer.disconnect(); }
    iconesEstado.elementos = {};

    cont.innerHTML = '';

    var categorias = (estado.catalogo && estado.catalogo.categorias) || [];
    categorias.forEach(function (cat) {
      var det = document.createElement('details');
      det.className = 'categoria';
      det.open = true;

      var sum = document.createElement('summary');
      sum.textContent = cat.nome + ' (' + (cat.apps || []).length + ')';
      det.appendChild(sum);

      var lista = document.createElement('div');
      lista.className = 'lista-apps';
      (cat.apps || []).forEach(function (app) { lista.appendChild(criarLinhaApp(app)); });
      det.appendChild(lista);

      cont.appendChild(det);
    });

    aplicarFiltro();
  }

  function carregarCatalogo() {
    return tmx.bridge.call('apps.catalog').then(function (r) {
      estado.catalogo = r;
      renderCategorias();
    }).catch(function (e) {
      var cont = document.getElementById('app-categorias');
      if (cont) { cont.innerHTML = '<p class="vazio">Falha ao carregar o catálogo: ' + escapeHtml(e.message) + '</p>'; }
      // Repropaga: a mensagem inline acima (e o toast) já avisaram o
      // usuário, mas tabs.show precisa SABER que a carga falhou para
      // deixar a aba como não iniciada e tentar de novo na próxima
      // abertura. Engolir o erro aqui deixava a aba vazia para sempre.
      throw e;
    });
  }

  /* ---------------- filtro e selecao ---------------- */

  function aplicarFiltro() {
    var termo = estado.termoBusca || '';
    var linhas = document.querySelectorAll('#tab-aplicativos .app-row');
    linhas.forEach(function (linha) {
      var combinaBusca = !termo || linha.dataset.nome.indexOf(termo) >= 0 || linha.dataset.descricao.indexOf(termo) >= 0;
      var combinaInstalados = !estado.mostrarInstalados || linha.classList.contains('app-instalado');
      var visivel = combinaBusca && combinaInstalados;
      linha.classList.toggle('app-oculto', !visivel);
      // A classe 'app' (sem o '-row') so fica nas linhas visiveis: e o que os
      // testes de GUI contam para saber quantos apps a busca deixou na tela.
      linha.classList.toggle('app', visivel);
    });
  }

  function atualizarContagemSelecionados() {
    var n = Object.keys(estado.selecionados).length;
    var span = document.getElementById('app-selecionados');
    if (span) { span.textContent = String(n); }
    var btnInstalar = document.getElementById('app-btn-instalar');
    var btnDesinstalar = document.getElementById('app-btn-desinstalar');
    if (btnInstalar) { btnInstalar.disabled = (n === 0); }
    if (btnDesinstalar) { btnDesinstalar.disabled = (n === 0); }
  }

  /* ---------------- instalados ---------------- */

  function carregarInstalados() {
    return chamarAcaoAssincronaComEspera('apps.installed').then(function (r) {
      var mapa = {};
      var itens = (r && r.itens) || [];
      itens.forEach(function (it) {
        if (it.instalado && it.catalogId) { mapa[it.catalogId] = true; }
      });
      estado.instalados = mapa;

      document.querySelectorAll('#tab-aplicativos .app-row').forEach(function (linha) {
        var instalado = !!mapa[linha.dataset.id];
        linha.classList.toggle('app-instalado', instalado);
        var selo = linha.querySelector('[data-role="selo-instalado"]');
        if (selo) { selo.style.display = instalado ? '' : 'none'; }
      });

      aplicarFiltro();
      return mapa;
    }).catch(function (e) {
      tmx.toast('Falha ao consultar aplicativos instalados: ' + e.message, 'erro');
    });
  }

  /* ---------------- resultados de instalar/desinstalar/atualizar ---------------- */

  function mostrarResultados(titulo, itens) {
    itens = itens || [];
    var linhas = itens.map(function (it) {
      var classe = 'res-' + (it.resultado || 'falha');
      return '<tr class="' + classe + '">' +
        '<td>' + escapeHtml(it.pacote) + '</td>' +
        '<td>' + escapeHtml(it.gerenciador || '—') + '</td>' +
        '<td>' + escapeHtml(it.resultado || '') + '</td>' +
        '<td>' + escapeHtml(it.detalhe || '') + '</td>' +
        '</tr>';
    }).join('');

    var html = itens.length
      ? '<table class="resultado-instalacao"><thead><tr><th>Pacote</th><th>Gerenciador</th><th>Resultado</th><th>Detalhe</th></tr></thead><tbody>' + linhas + '</tbody></table>'
      : '<p class="vazio">Nada para mostrar.</p>';

    tmx.modal.open({ titulo: titulo, html: html, botoes: [{ rotulo: 'Fechar' }] });
  }

  function rodarAcaoPacotes(acao, ids, rotulo) {
    var payload = ids ? { ids: ids } : null;
    tmx.toast(rotulo + '...', 'aviso');
    chamarAcaoAssincronaComEspera(acao, payload).then(function (resultado) {
      mostrarResultados(rotulo, resultado);
      return carregarInstalados();
    }).catch(function (e) {
      tmx.toast(rotulo + ' falhou: ' + e.message, 'erro');
    });
  }

  /* ---------------- toolbar ---------------- */

  function ligarEventosToolbar() {
    document.getElementById('app-busca').addEventListener('input', function (e) {
      estado.termoBusca = e.target.value.trim().toLowerCase();
      aplicarFiltro();
    });

    document.getElementById('app-btn-limpar').addEventListener('click', function () {
      estado.selecionados = {};
      document.querySelectorAll('#tab-aplicativos input[type=checkbox]').forEach(function (cb) { cb.checked = false; });
      atualizarContagemSelecionados();
    });

    document.getElementById('app-btn-expandir').addEventListener('click', function () {
      document.querySelectorAll('#tab-aplicativos details.categoria').forEach(function (d) { d.open = true; });
    });

    document.getElementById('app-btn-recolher').addEventListener('click', function () {
      document.querySelectorAll('#tab-aplicativos details.categoria').forEach(function (d) { d.open = false; });
    });

    document.getElementById('app-btn-instalados').addEventListener('click', function (e) {
      estado.mostrarInstalados = !estado.mostrarInstalados;
      e.currentTarget.setAttribute('aria-pressed', estado.mostrarInstalados ? 'true' : 'false');
      e.currentTarget.classList.toggle('btn-primary', estado.mostrarInstalados);
      if (estado.mostrarInstalados && !estado.instalados) {
        carregarInstalados();
      } else {
        aplicarFiltro();
      }
    });

    document.getElementById('app-btn-instalar').addEventListener('click', function () {
      var ids = Object.keys(estado.selecionados);
      if (!ids.length) { tmx.toast('Selecione ao menos um aplicativo', 'aviso'); return; }
      rodarAcaoPacotes('apps.install', ids, 'Instalando');
    });

    document.getElementById('app-btn-desinstalar').addEventListener('click', function () {
      var ids = Object.keys(estado.selecionados);
      if (!ids.length) { tmx.toast('Selecione ao menos um aplicativo', 'aviso'); return; }
      rodarAcaoPacotes('apps.uninstall', ids, 'Desinstalando');
    });

    document.getElementById('app-btn-atualizar').addEventListener('click', function () {
      rodarAcaoPacotes('apps.upgradeAll', null, 'Atualizando tudo');
    });
  }

  /* ---------------- arranque da aba ---------------- */

  window.tmxTabs.aplicativos = {
    init: function () {
      injetarEstilo();
      montarEsqueleto();
      ligarEventosToolbar();
      ligarEsperaDeSlotLivreIcones();
      // aguardarTodas (e não Promise.all): espera as duas terminarem antes
      // de rejeitar, para que um retry de tabs.show não comece com a outra
      // carga ainda no ar.
      return tmx.aguardarTodas([atualizarGerenciadores(), carregarCatalogo()]);
    }
  };
})();
