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
      '#tab-instalar .toolbar { display:flex; flex-wrap:wrap; gap:8px; align-items:center; margin-bottom:14px; }',
      '#tab-instalar .toolbar input[type=search] { flex:1 1 220px; min-width:160px; padding:6px 10px; border:1px solid var(--linha); border-radius:6px; background:var(--panel-2); color:var(--fg); font:inherit; }',
      '#tab-instalar .painel-gerenciadores { display:flex; flex-wrap:wrap; gap:10px 20px; align-items:center; padding:10px 14px; margin-bottom:14px; border:1px solid var(--linha); border-radius:var(--raio); background:var(--panel-2); }',
      '#tab-instalar .painel-gerenciadores .gm { display:inline-flex; align-items:center; gap:6px; }',
      '#tab-instalar .painel-gerenciadores .gm .ok { color:var(--ok); font-weight:700; }',
      '#tab-instalar .painel-gerenciadores .gm .falta { color:var(--danger); font-weight:700; }',
      '#tab-instalar details.categoria { border:1px solid var(--linha); border-radius:var(--raio); margin-bottom:8px; background:var(--panel); }',
      '#tab-instalar details.categoria > summary { cursor:pointer; padding:10px 14px; font-weight:650; }',
      '#tab-instalar .lista-apps { display:grid; grid-template-columns:repeat(auto-fill,minmax(230px,1fr)); gap:2px 10px; padding:4px 14px 12px; }',
      '#tab-instalar .app-row { display:flex; align-items:center; gap:4px; padding:5px 4px; border-radius:6px; }',
      '#tab-instalar .app-row:hover { background:var(--panel-2); }',
      '#tab-instalar .app-row.app-oculto { display:none; }',
      '#tab-instalar .app-row label { display:flex; align-items:center; gap:6px; flex:1 1 auto; cursor:pointer; overflow:hidden; min-width:0; }',
      '#tab-instalar .app-row .nome-app { overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }',
      '#tab-instalar .app-row .link-app { color:var(--muted); text-decoration:none; padding:2px 4px; flex:0 0 auto; }',
      '#tab-instalar .app-row .link-app:hover { color:var(--accent); }',
      '#tab-instalar .selo-foss { color:var(--ok); flex:0 0 auto; }',
      '#tab-instalar .selo-instalado { color:var(--accent); flex:0 0 auto; }',
      '#tab-instalar .rodape-nota { margin-top:10px; color:var(--muted); font-size:12px; }',
      '#tab-instalar table.resultado-instalacao { width:100%; border-collapse:collapse; font-size:13px; }',
      '#tab-instalar table.resultado-instalacao th, #tab-instalar table.resultado-instalacao td { text-align:left; padding:5px 8px; border-bottom:1px solid var(--linha); }',
      '#tab-instalar table.resultado-instalacao tr.res-ok td:nth-child(3) { color:var(--ok); }',
      '#tab-instalar table.resultado-instalacao tr.res-pulado td:nth-child(3) { color:var(--warn); }',
      '#tab-instalar table.resultado-instalacao tr.res-falha td:nth-child(3) { color:var(--danger); }'
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

  function chamarAcaoAssincrona(nome, payload) {
    return tmx.bridge.call(nome, payload).then(function (resp) {
      var jobId = resp && resp.jobId;
      if (!jobId) { throw new Error('resposta sem jobId'); }
      return new Promise(function (resolve, reject) {
        var ouvinte = tmx.bridge.on('job.done', function (p) {
          if (!p || p.jobId !== jobId) { return; }
          tmx.bridge.off('job.done', ouvinte);
          if (p.ok) { resolve(p.result); } else { reject(new Error((p.error && p.error.message) || 'o trabalho falhou')); }
        });
      });
    });
  }

  /* ---------------- esqueleto ---------------- */

  function montarEsqueleto() {
    var raiz = document.getElementById('tab-instalar');
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
            chamarAcaoAssincrona('apps.repairWinget', { consentido: true }).then(function (r) {
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
            chamarAcaoAssincrona('apps.installChoco', { consentido: true }).then(function (r) {
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
    });
  }

  /* ---------------- filtro e selecao ---------------- */

  function aplicarFiltro() {
    var termo = estado.termoBusca || '';
    var linhas = document.querySelectorAll('#tab-instalar .app-row');
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
    return chamarAcaoAssincrona('apps.installed').then(function (r) {
      var mapa = {};
      var itens = (r && r.itens) || [];
      itens.forEach(function (it) {
        if (it.instalado && it.catalogId) { mapa[it.catalogId] = true; }
      });
      estado.instalados = mapa;

      document.querySelectorAll('#tab-instalar .app-row').forEach(function (linha) {
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
    chamarAcaoAssincrona(acao, payload).then(function (resultado) {
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
      document.querySelectorAll('#tab-instalar input[type=checkbox]').forEach(function (cb) { cb.checked = false; });
      atualizarContagemSelecionados();
    });

    document.getElementById('app-btn-expandir').addEventListener('click', function () {
      document.querySelectorAll('#tab-instalar details.categoria').forEach(function (d) { d.open = true; });
    });

    document.getElementById('app-btn-recolher').addEventListener('click', function () {
      document.querySelectorAll('#tab-instalar details.categoria').forEach(function (d) { d.open = false; });
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

  window.tmxTabs.instalar = {
    init: function () {
      injetarEstilo();
      montarEsqueleto();
      ligarEventosToolbar();
      atualizarGerenciadores();
      carregarCatalogo();
    }
  };
})();
