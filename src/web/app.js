/* app.js - casca da interface.
 *
 * Expõe window.tmx = { bridge, modal, toast, tabs, status, session }.
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
    criando: 'Criando ponto…',
    pulado: 'Ponto pulado (sem proteção)'
  };

  function textoPonto(rp) {
    if (!rp || !rp.estado) { return TEXTO_RP.nenhum; }
    if (rp.estado === 'criado') { return 'Ponto #' + (rp.seq === null || rp.seq === undefined ? '?' : rp.seq) + ' criado'; }
    if (rp.estado === 'falhou') { return 'Falhou: ' + (rp.mensagem || rp.detalhe || 'ponto de restauração'); }
    return TEXTO_RP[rp.estado] || TEXTO_RP.nenhum;
  }

  var status = {
    ultimo: null,

    aplicar: function (s) {
      status.ultimo = s || {};
      document.getElementById('st-rp').textContent = textoPonto(status.ultimo.restorePoint);
      document.getElementById('st-run').textContent = status.ultimo.runId || 'Sem sessão';

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

  /* ---------------- sessão: pasta da execução + ponto de restauração ----------------
   * tmx.session.ensure() é a porta por onde toda aba passa antes de alterar
   * qualquer coisa: resolve true só quando existe sessão pronta (ponto criado
   * ou pulado com a frase digitada), e false quando o usuário desistiu.
   */

  var EXPLICACAO_PONTO =
    '<p>Antes de alterar qualquer coisa o TweakMaxing abre uma <strong>sessão</strong>: ' +
    'uma pasta com o registro de tudo que for mexido (é dela que o Undo vive) e um ' +
    '<strong>ponto de restauração</strong> do próprio Windows.</p>' +
    '<p>A criação do ponto leva de alguns segundos a poucos minutos. Nada é aplicado ' +
    'no sistema enquanto ele não existir.</p>';

  function escaparHtml(t) {
    return String(t === null || t === undefined ? '' : t)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  function copiar_texto(texto) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(texto).then(function () {
        toast('Comando copiado', 'ok');
      }).catch(function () { copiarPorTextarea(texto); });
      return;
    }
    copiarPorTextarea(texto);
  }

  function copiarPorTextarea(texto) {
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
    toast(ok ? 'Comando copiado' : 'Não foi possível copiar', ok ? 'ok' : 'erro');
  }

  function pintarProgresso(texto, pct) {
    var el = document.getElementById('modal-progresso');
    if (!el) { return; }
    var t = texto || '';
    if (typeof pct === 'number' && t) { t += ' (' + pct + '%)'; }
    el.textContent = t;
  }

  function travarBotoesModal() {
    var botoes = document.querySelectorAll('#modal-buttons button');
    for (var i = 0; i < botoes.length; i++) { botoes[i].disabled = true; }
  }

  function destravarBotoesModal() {
    var botoes = document.querySelectorAll('#modal-buttons button');
    for (var i = 0; i < botoes.length; i++) { botoes[i].disabled = false; }
  }

  /* Dispara session.start e resolve com o payload do job.done correspondente.
     Rejeita quando a própria chamada falha (ex.: frase incorreta), caso em que
     nenhum job chegou a existir. */
  function abrirSessao(payload) {
    return new Promise(function (resolve, reject) {
      var jobId = null;
      var fechado = false;

      function soltar() {
        bridge.off('job.progress', aoProgredir);
        bridge.off('job.done', aoTerminar);
      }
      function aoProgredir(p) {
        if (!p || (jobId && p.jobId !== jobId)) { return; }
        pintarProgresso(p.status || 'Trabalhando…', p.pct);
      }
      function aoTerminar(p) {
        if (fechado || !p || (jobId && p.jobId !== jobId)) { return; }
        fechado = true;
        soltar();
        resolve(p);
      }

      bridge.on('job.progress', aoProgredir);
      bridge.on('job.done', aoTerminar);

      bridge.call('session.start', payload).then(function (r) {
        jobId = (r && r.jobId) || null;
      }).catch(function (e) {
        if (fechado) { return; }
        fechado = true;
        soltar();
        reject(e);
      });
    });
  }

  function modalCriarPonto(fim) {
    modal.open({
      titulo: 'Ponto de restauração',
      html: EXPLICACAO_PONTO + '<p id="modal-progresso" class="sessao-progresso"></p>',
      botoes: [
        {
          rotulo: 'Criar ponto e continuar',
          classe: 'btn-primary',
          mantemAberto: true,
          onClick: function () {
            travarBotoesModal();
            pintarProgresso('Criando ponto de restauração…', 0);
            abrirSessao({ skip: false }).then(function (p) {
              if (p && p.ok) {
                status.refresh();
                modal.close();
                toast('Sessão aberta com ponto de restauração', 'ok');
                fim(true);
                return;
              }
              modalPontoFalhou((p && p.error && p.error.message) || 'não foi possível criar o ponto', fim);
            }).catch(function (e) {
              modalPontoFalhou(e.message, fim);
            });
          }
        },
        { rotulo: 'Cancelar', onClick: function () { fim(false); } }
      ]
    });
  }

  function modalPontoFalhou(mensagem, fim) {
    status.refresh();
    modal.open({
      titulo: 'O ponto de restauração falhou',
      html: '<p class="sessao-erro">' + escaparHtml(mensagem) + '</p>' +
            '<p>Nada foi alterado no sistema. Você pode fechar e resolver o motivo ' +
            '(Proteção do Sistema desligada, disco cheio, política de grupo) ou ' +
            'prosseguir assumindo o risco.</p>',
      botoes: [
        { rotulo: 'Fechar', onClick: function () { fim(false); } },
        {
          rotulo: 'Prosseguir sem ponto',
          classe: 'btn-danger',
          mantemAberto: true,
          onClick: function () { modalPularPonto(fim); }
        }
      ]
    });
  }

  function modalPularPonto(fim) {
    bridge.call('session.skipPhrase').then(function (r) {
      var frase = (r && r.frase) || '';
      modal.open({
        titulo: 'Prosseguir sem ponto de restauração',
        html: '<p>Sem ponto de restauração você perde a rede de segurança do próprio ' +
              'Windows. Os ajustes continuam reversíveis pelo Undo, mas nada mais ' +
              'protege o sistema se algo externo der errado.</p>' +
              '<p>Para confirmar, digite exatamente:</p>' +
              '<p class="sessao-frase">' + escaparHtml(frase) + '</p>' +
              '<input type="text" id="modal-frase" class="campo" autocomplete="off" spellcheck="false" ' +
              'aria-label="Frase de confirmação">' +
              '<p id="modal-progresso" class="sessao-progresso"></p>',
        botoes: [
          {
            rotulo: 'Confirmar',
            classe: 'btn-danger',
            mantemAberto: true,
            onClick: function () {
              var campo = document.getElementById('modal-frase');
              var digitado = campo ? campo.value : '';
              travarBotoesModal();
              pintarProgresso('Abrindo a sessão sem ponto…', 0);
              abrirSessao({ skip: true, frase: digitado }).then(function (p) {
                if (p && p.ok) {
                  status.refresh();
                  modal.close();
                  toast('Sessão aberta SEM ponto de restauração', 'aviso');
                  fim(true);
                  return;
                }
                destravarBotoesModal();
                pintarProgresso('', null);
                toast((p && p.error && p.error.message) || 'não foi possível abrir a sessão', 'erro');
              }).catch(function (e) {
                // Frase errada: a ponte recusa antes de criar job, o modal fica.
                destravarBotoesModal();
                pintarProgresso('', null);
                toast(e.message, 'erro');
              });
            }
          },
          { rotulo: 'Cancelar', onClick: function () { fim(false); } }
        ]
      });
      var campo = document.getElementById('modal-frase');
      if (campo) { campo.focus(); }
    }).catch(function (e) {
      toast(e.message, 'erro');
      fim(false);
    });
  }

  var session = {
    ensure: function () {
      return bridge.call('session.status').then(function (s) {
        status.aplicar(s);
        if (s && s.pronto) { return true; }

        return new Promise(function (resolve) {
          var terminado = false;
          function fim(valor) {
            if (terminado) { return; }
            terminado = true;
            document.removeEventListener('keydown', aoEscapar);
            resolve(!!valor);
          }
          function aoEscapar(e) {
            // O Escape fecha o modal: a promessa não pode ficar pendurada.
            if (e.key === 'Escape') { fim(false); }
          }
          document.addEventListener('keydown', aoEscapar);
          modalCriarPonto(fim);
        });
      }).catch(function (e) {
        toast('Não foi possível consultar a sessão: ' + e.message, 'erro');
        return false;
      });
    }
  };

  function montarBotaoSessaoDev() {
    if (document.getElementById('st-session-start')) { return; }
    var rodape = document.getElementById('status');
    if (!rodape) { return; }

    var cel = document.createElement('span');
    cel.className = 'cel';

    var botao = document.createElement('button');
    botao.type = 'button';
    botao.id = 'st-session-start';
    botao.className = 'btn btn-mini';
    botao.textContent = 'Iniciar sessão';
    botao.addEventListener('click', function () { session.ensure(); });

    cel.appendChild(botao);
    rodape.insertBefore(cel, document.getElementById('st-job'));
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
        copiar_texto(texto);
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
      // Controle de desenvolvimento: só no modo de teste, para a suite de GUI
      // disparar o fluxo da sessão sem depender de uma aba.
      if (v.testMode) { montarBotaoSessaoDev(); }
    }).catch(function (e) {
      document.getElementById('versao').textContent = '—';
      console.warn('shell.version falhou:', e.message);
    });

    status.refresh();
  }

  window.tmx = { bridge: bridge, modal: modal, toast: toast, tabs: tabs, status: status, session: session };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', iniciar);
  } else {
    iniciar();
  }
})();
