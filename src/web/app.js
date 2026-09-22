/* app.js - casca da interface.
 *
 * Expõe window.tmx = { bridge, modal, toast, tabs, status }.
 * As abas (tasks 9-13) registram window.tmxTabs.<nome> = { init() {} } e são
 * inicializadas na primeira vez que ficam visíveis.
 *
 * Contrato da ponte (docs/specs 3):
 *   JS  -> PS : { id, action, payload }
 *   PS  -> JS : { id, ok, result } | { id, ok:false, error:{ message } }
 *   PS  -> JS : { event, payload, ts }   (sem id: notificação)
 */
(function () {
  'use strict';

  window.tmxTabs = window.tmxTabs || {};

  var TIMEOUT_MS = 120000;
  var pendentes = {};
  var ouvintes = {};
  var host = (window.chrome && window.chrome.webview) ? window.chrome.webview : null;

  function novoId() {
    if (window.crypto && typeof window.crypto.randomUUID === 'function') {
      return window.crypto.randomUUID();
    }
    return String(Date.now()) + '-' + String(Math.random()).slice(2);
  }

  /* ---------------- ponte ---------------- */

  var bridge = {
    disponivel: !!host,

    call: function (action, payload) {
      if (!host) {
        return Promise.reject(new Error('sem ponte (abra pelo TweakMaxing)'));
      }
      var id = novoId();
      return new Promise(function (resolve, reject) {
        var timer = setTimeout(function () {
          delete pendentes[id];
          reject(new Error('tempo esgotado: ' + action));
        }, TIMEOUT_MS);

        pendentes[id] = {
          resolve: function (v) { clearTimeout(timer); resolve(v); },
          reject: function (e) { clearTimeout(timer); reject(e); }
        };

        try {
          host.postMessage({ id: id, action: action, payload: payload === undefined ? null : payload });
        } catch (erro) {
          clearTimeout(timer);
          delete pendentes[id];
          reject(erro);
        }
      });
    },

    on: function (evento, fn) {
      (ouvintes[evento] = ouvintes[evento] || []).push(fn);
      return fn;
    },

    off: function (evento, fn) {
      var lista = ouvintes[evento];
      if (!lista) { return; }
      var i = lista.indexOf(fn);
      if (i >= 0) { lista.splice(i, 1); }
    }
  };

  function rotear(msg) {
    if (!msg || typeof msg !== 'object') { return; }

    if (msg.id && pendentes[msg.id]) {
      var p = pendentes[msg.id];
      delete pendentes[msg.id];
      if (msg.ok) {
        p.resolve(msg.result);
      } else {
        p.reject(new Error((msg.error && msg.error.message) || 'falha desconhecida'));
      }
      return;
    }

    if (msg.event) {
      var lista = ouvintes[msg.event] || [];
      for (var i = 0; i < lista.length; i++) {
        try { lista[i](msg.payload, msg); } catch (e) { console.error(e); }
      }
    }
  }

  if (host) {
    host.addEventListener('message', function (e) { rotear(e.data); });
  }

  /* ---------------- toasts ---------------- */

  function toast(mensagem, tipo) {
    var caixa = document.getElementById('toasts');
    if (!caixa) { return; }
    var el = document.createElement('div');
    el.className = 'toast' + (tipo ? ' toast-' + tipo : '');
    el.textContent = mensagem;
    caixa.appendChild(el);
    setTimeout(function () {
      if (el.parentNode) { el.parentNode.removeChild(el); }
    }, tipo === 'erro' ? 9000 : 5000);
  }

  /* ---------------- modal ---------------- */

  var modal = {
    open: function (opcoes) {
      var raiz = document.getElementById('modal');
      if (!raiz) { return; }
      opcoes = opcoes || {};

      document.getElementById('modal-title').textContent = opcoes.titulo || '';
      document.getElementById('modal-body').innerHTML = opcoes.html || '';

      var pe = document.getElementById('modal-buttons');
      pe.innerHTML = '';
      var botoes = opcoes.botoes || [{ rotulo: 'Fechar' }];
      botoes.forEach(function (b) {
        var el = document.createElement('button');
        el.type = 'button';
        el.className = 'btn ' + (b.classe || '');
        el.textContent = b.rotulo;
        el.addEventListener('click', function () {
          if (typeof b.onClick === 'function') { b.onClick(); }
          if (b.mantemAberto !== true) { modal.close(); }
        });
        pe.appendChild(el);
      });

      raiz.hidden = false;
      var primeiro = pe.querySelector('button');
      if (primeiro) { primeiro.focus(); }
    },

    close: function () {
      var raiz = document.getElementById('modal');
      if (raiz) { raiz.hidden = true; }
    }
  };

  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape') { modal.close(); }
  });

  /* ---------------- abas ---------------- */

  var iniciadas = {};

  var tabs = {
    atual: null,

    show: function (nome) {
      var secoes = document.querySelectorAll('main .tab');
      for (var i = 0; i < secoes.length; i++) {
        secoes[i].hidden = (secoes[i].id !== 'tab-' + nome);
      }
      var botoes = document.querySelectorAll('nav [data-tab]');
      for (var j = 0; j < botoes.length; j++) {
        botoes[j].classList.toggle('active', botoes[j].getAttribute('data-tab') === nome);
      }
      tabs.atual = nome;

      var mod = window.tmxTabs[nome];
      if (mod && typeof mod.init === 'function' && !iniciadas[nome]) {
        iniciadas[nome] = true;
        try { mod.init(); } catch (e) { console.error(e); toast('Falha ao abrir a aba ' + nome, 'erro'); }
      }
    }
  };

  /* ---------------- barra de status ---------------- */

  var TEXTO_RP = {
    nenhum: 'Nenhum ponto de restauração',
    criando: 'Criando ponto...',
    pulado: 'Ponto pulado'
  };

  function textoPonto(rp) {
    if (!rp || !rp.estado) { return TEXTO_RP.nenhum; }
    if (rp.estado === 'criado') { return 'Ponto #' + (rp.seq === null || rp.seq === undefined ? '?' : rp.seq) + ' criado'; }
    if (rp.estado === 'falhou') { return 'Falhou: ' + (rp.detalhe || 'ponto de restauração'); }
    return TEXTO_RP[rp.estado] || TEXTO_RP.nenhum;
  }

  var status = {
    ultimo: null,

    aplicar: function (s) {
      status.ultimo = s || {};
      document.getElementById('st-rp').textContent = textoPonto(status.ultimo.restorePoint);
      document.getElementById('st-run').textContent = status.ultimo.runId
        ? ('Sessão ' + status.ultimo.runId)
        : 'Sem sessão';

      var undo = status.ultimo.undoCommand || '';
      document.getElementById('st-undo-texto').textContent = undo || 'Nada a reverter';
      document.getElementById('st-undo-copy').disabled = !undo;
    },

    refresh: function () {
      return bridge.call('session.status').then(status.aplicar).catch(function (e) {
        console.warn('session.status falhou:', e.message);
      });
    }
  };

  function textoJob(p, fase) {
    if (fase === 'done') { return 'Concluído: ' + (p.name || ''); }
    var pedaco = (p.name || 'trabalho');
    if (p.status) { pedaco += ': ' + p.status; }
    if (typeof p.pct === 'number') { pedaco += ' ' + p.pct + '%'; }
    return pedaco;
  }

  /* ---------------- arranque ---------------- */

  function iniciar() {
    document.querySelectorAll('nav [data-tab]').forEach(function (b) {
      b.addEventListener('click', function () { tabs.show(b.getAttribute('data-tab')); });
    });

    var copiar = document.getElementById('st-undo-copy');
    if (copiar) {
      copiar.addEventListener('click', function () {
        var texto = document.getElementById('st-undo-texto').textContent;
        if (!texto) { return; }
        if (navigator.clipboard && navigator.clipboard.writeText) {
          navigator.clipboard.writeText(texto).then(function () { toast('Comando copiado', 'ok'); });
        }
      });
    }

    bridge.on('session.changed', function () { status.refresh(); });

    var celJob = document.getElementById('st-job');
    bridge.on('job.started', function (p) { celJob.textContent = textoJob(p || {}, 'started'); });
    bridge.on('job.progress', function (p) { celJob.textContent = textoJob(p || {}, 'progress'); });
    bridge.on('job.done', function (p) {
      celJob.textContent = textoJob(p || {}, 'done');
      if (p && p.ok === false) { toast((p.error && p.error.message) || 'O trabalho falhou', 'erro'); }
      setTimeout(function () { celJob.textContent = 'Ocioso'; }, 4000);
      status.refresh();
    });

    tabs.show('ajustes');

    bridge.call('shell.version').then(function (v) {
      // Só a versão: o "[modo de teste]" mora no título da janela, e os testes
      // de GUI comparam #versao com o conteúdo do arquivo VERSION.
      document.getElementById('versao').textContent = v.version || '';
      document.body.dataset.testmode = v.testMode ? '1' : '0';
      document.body.dataset.elevado = v.elevado ? '1' : '0';
    }).catch(function (e) {
      document.getElementById('versao').textContent = '—';
      console.warn('shell.version falhou:', e.message);
    });

    status.refresh();
  }

  window.tmx = { bridge: bridge, modal: modal, toast: toast, tabs: tabs, status: status };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', iniciar);
  } else {
    iniciar();
  }
})();
