/* app.js - casca da interface.
 *
 * Expõe window.tmx = { bridge, modal, toast, tabs, status, session, esc,
 * aguardarTodas }.
 * As abas (tasks 9-13) registram window.tmxTabs.<nome> = { init() {} } e são
 * inicializadas na primeira vez que ficam visíveis. init() pode ser síncrono
 * ou devolver uma Promise; quando devolve, ela TEM que rejeitar se a carga
 * falhou - é assim que tabs.show sabe que precisa tentar de novo na próxima
 * vez que a aba for aberta (a mensagem inline e o toast continuam sendo
 * responsabilidade da aba).
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

    /* Quantas chamadas callComEspera estao PENDURADAS agora (incrementado no
       inicio, decrementado so quando a chamada finalmente resolve OU rejeita
       - inclusive as que ainda estao no meio de uma espera/retentativa).
       Outras partes do app (o lote de icones de install.js, por exemplo)
       consultam isso pra dar prioridade a uma acao de usuario esperando o
       slot em vez de disparar mais um lote de fundo bem na hora em que o
       usuario clicou em algo. */
    esperandoUsuario: 0,

    /* Como call(), mas quando a ponte recusa porque o unico slot de job esta
       ocupado ("ja existe um trabalho em andamento") espera e tenta de novo
       ate esperaMs. Repetir e seguro: nessa recusa nenhum job chegou a nascer.
       Qualquer outro erro sobe na hora. */
    callComEspera: function (action, payload, esperaMs) {
      var limite = Date.now() + (esperaMs || 30000);
      bridge.esperandoUsuario++;
      function tentar() {
        return bridge.call(action, payload).catch(function (e) {
          if (!/trabalho em andamento/i.test((e && e.message) || '') || Date.now() > limite) { throw e; }
          return new Promise(function (r) { setTimeout(r, 400); }).then(tentar);
        });
      }
      return tentar().then(
        function (v) { bridge.esperandoUsuario--; return v; },
        function (e) { bridge.esperandoUsuario--; throw e; }
      );
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
    /* open({ titulo, html, botoes })
     *
     * ATENÇÃO — `html` é injetado com innerHTML, sem sanitização: aceita
     * HTML CONFIÁVEL APENAS, isto é, marcação escrita aqui no código da
     * interface. Todo texto que vem de fora (nome, descrição, detalhe ou
     * erro do catálogo, saída de um job, mensagem do PowerShell) tem que
     * passar por tmx.esc() antes de entrar nessa string.
     *
     *   modal.open({ html: '<p>' + tmx.esc(item.detalhe) + '</p>' });
     *
     * `titulo` e o rótulo dos botões vão por textContent e já são seguros.
     */
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
  var iniciando = {};

  function tentarIniciarModulo(nome) {
    var mod = window.tmxTabs[nome];
    if (mod && typeof mod.init === 'function' && !iniciadas[nome] && !iniciando[nome]) {
      // A marca só entra quando a carga TERMINA bem. Quase todo init() é
      // assíncrono (pede catálogo à ponte), então o retorno é tratado como
      // possível Promise: marcar no retorno síncrono de um init assíncrono
      // seria marcar antes de saber se deu certo, e uma aba que falhou na
      // primeira abertura (ponte fora do ar, catálogo quebrado) ficaria
      // vazia para sempre - a segunda visita já encontraria
      // iniciadas[nome] === true e não tentaria de novo.
      //
      // iniciando[nome] cobre a janela entre o disparo e o desfecho: sem
      // ele, dois cliques rápidos na mesma aba iniciariam a carga duas
      // vezes. init() é idempotente (o esqueleto é remontado), então o
      // retry de uma visita seguinte é seguro.
      iniciando[nome] = true;
      var encerrar = function () { iniciando[nome] = false; };
      var falhar = function (e) {
        console.error(e);
        toast('Falha ao abrir a aba ' + nome + ': ' + ((e && e.message) || e), 'erro');
      };
      try {
        Promise.resolve(mod.init())
          .then(function () { iniciadas[nome] = true; })
          .catch(falhar)
          .then(encerrar, encerrar);
      } catch (e) {
        // init() que lança de forma síncrona nem chega a virar Promise.
        encerrar();
        falhar(e);
      }
    }
  }

  var tabs = {
    atual: null,

    show: function (nome) {
      // 'main > .tab': só os filhos DIRETOS de <main> são abas de primeiro
      // nível. #tab-configurar e #tab-atualizacoes moram dentro de
      // #tab-sistema (sub-abas, ids internos preservados) e não podem ser
      // escondidos por este laço - quem cuida deles é o clique em .subaba,
      // logo abaixo.
      var secoes = document.querySelectorAll('main > .tab');
      for (var i = 0; i < secoes.length; i++) {
        secoes[i].hidden = (secoes[i].id !== 'tab-' + nome);
      }
      var botoes = document.querySelectorAll('nav [data-tab]');
      for (var j = 0; j < botoes.length; j++) {
        botoes[j].classList.toggle('active', botoes[j].getAttribute('data-tab') === nome);
      }
      tabs.atual = nome;

      tentarIniciarModulo(nome);

      // 'sistema' hospeda dois módulos que configure.js e updates.js já
      // registram com o nome antigo (tmxTabs.configurar / tmxTabs.atualizacoes)
      // - eles não foram reescritos nesta onda, e os ids internos
      // (#tab-configurar, #tab-atualizacoes) continuam os mesmos.
      if (nome === 'sistema') {
        tentarIniciarModulo('configurar');
        tentarIniciarModulo('atualizacoes');
      }
    }
  };

  /* ---------------- sub-abas (usado por #tab-sistema) ---------------- */

  function ligarSubAbas() {
    var botoes = document.querySelectorAll('.subaba[data-subtab]');
    botoes.forEach(function (botao) {
      botao.addEventListener('click', function () {
        var alvo = botao.getAttribute('data-subtab');
        var grupo = botao.closest('.tab');
        if (!grupo) { return; }
        grupo.querySelectorAll(':scope > .subabas .subaba').forEach(function (b) {
          b.setAttribute('aria-selected', b === botao ? 'true' : 'false');
        });
        grupo.querySelectorAll(':scope > .tab').forEach(function (sec) {
          sec.hidden = (sec.id !== 'tab-' + alvo);
        });
      });
    });
  }

  /* ---------------- barra de status ---------------- */

  // traduzir(): atalho para tmx.i18n.t com fallback pt-BR embutido - cobre a
  // janela (curtíssima, mas real) antes do i18n.js aplicar o idioma salvo, e
  // qualquer ambiente onde i18n.js não tenha carregado.
  function traduzir(chave, vars, fallback) {
    if (window.tmx && tmx.i18n && typeof tmx.i18n.t === 'function') {
      var r = tmx.i18n.t(chave, vars);
      if (r && r !== chave) { return r; }
    }
    return fallback;
  }

  var TEXTO_RP = {
    nenhum: function () { return traduzir('shell.status.semPonto', null, 'Nenhum ponto de restauração'); },
    criando: function () { return traduzir('shell.status.criandoPonto', null, 'Criando ponto…'); },
    pulado: function () { return traduzir('shell.status.pontoPulado', null, 'Ponto pulado (sem proteção)'); }
  };

  function textoPonto(rp) {
    if (!rp || !rp.estado) { return TEXTO_RP.nenhum(); }
    if (rp.estado === 'criado') {
      return traduzir('shell.status.pontoCriado', { seq: (rp.seq === null || rp.seq === undefined ? '?' : rp.seq) },
        'Ponto #' + (rp.seq === null || rp.seq === undefined ? '?' : rp.seq) + ' criado');
    }
    if (rp.estado === 'falhou') {
      var motivo = rp.mensagem || rp.detalhe || traduzir('shell.status.pontoDeRestauracao', null, 'ponto de restauração');
      return traduzir('shell.status.falhou', { motivo: motivo }, 'Falhou: ' + motivo);
    }
    var f = TEXTO_RP[rp.estado];
    return f ? f() : TEXTO_RP.nenhum();
  }

  var status = {
    ultimo: null,

    aplicar: function (s) {
      status.ultimo = s || {};
      document.getElementById('st-rp').textContent = textoPonto(status.ultimo.restorePoint);
      document.getElementById('st-run').textContent = status.ultimo.runId || traduzir('shell.status.semSessao', null, 'Sem sessão');

      var undo = status.ultimo.undoCommand || '';
      document.getElementById('st-undo-texto').textContent = undo || traduzir('shell.status.nadaAReverter', null, 'Nada a reverter');
      document.getElementById('st-undo-copy').disabled = !undo;
    },

    refresh: function () {
      return bridge.call('session.status').then(status.aplicar).catch(function (e) {
        console.warn('session.status falhou:', e.message);
      });
    }
  };

  /* aguardarTodas([p1, p2, ...])
   *
   * Como Promise.all, com uma diferença que importa para init() de aba:
   * espera TODAS terminarem antes de decidir, e só então rejeita com o
   * primeiro erro. Promise.all rejeita no primeiro tropeço e deixa as irmãs
   * correndo - o que faria tabs.show liberar um retry enquanto a carga
   * anterior ainda estava no ar, com duas chamadas da mesma ação na ponte.
   */
  function aguardarTodas(promessas) {
    var primeiroErro = null;
    return Promise.all((promessas || []).map(function (p) {
      return Promise.resolve(p).catch(function (e) {
        if (!primeiroErro) { primeiroErro = e; }
      });
    })).then(function () {
      if (primeiroErro) { throw primeiroErro; }
    });
  }

  function textoJob(p, fase) {
    if (fase === 'done') { return traduzir('shell.status.concluido', { nome: p.name || '' }, 'Concluído: ' + (p.name || '')); }
    var pedaco = (p.name || traduzir('shell.status.trabalho', null, 'trabalho'));
    if (p.status) { pedaco += ': ' + p.status; }
    if (typeof p.pct === 'number') { pedaco += ' ' + p.pct + '%'; }
    return pedaco;
  }

  /* ---------------- sessão: pasta da execução + ponto de restauração ----------------
   * tmx.session.ensure() é a porta por onde toda aba passa antes de alterar
   * qualquer coisa: resolve true só quando existe sessão pronta (ponto criado
   * ou pulado com a frase digitada), e false quando o usuário desistiu.
   */

  var EXPLICACAO_PONTO_PT =
    '<p>Antes de alterar qualquer coisa o TweakMaxing abre uma <strong>sessão</strong>: ' +
    'uma pasta com o registro de tudo que for mexido (é dela que o Undo vive) e um ' +
    '<strong>ponto de restauração</strong> do próprio Windows.</p>' +
    '<p>A criação do ponto leva de alguns segundos a poucos minutos. Nada é aplicado ' +
    'no sistema enquanto ele não existir.</p>';

  // A tradução mora no dicionário como HTML de confiança (é texto escrito
  // aqui no código da interface, nunca dado externo) - mesma regra do
  // modal.open({html}) descrita acima.
  function explicacaoPonto() { return traduzir('shell.sessao.explicacao', null, EXPLICACAO_PONTO_PT); }

  function escaparHtml(t) {
    return String(t === null || t === undefined ? '' : t)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  function copiar_texto(texto) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(texto).then(function () {
        toast(traduzir('shell.status.comandoCopiado', null, 'Comando copiado'), 'ok');
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
    toast(ok ? traduzir('shell.status.comandoCopiado', null, 'Comando copiado')
             : traduzir('shell.status.naoFoiPossivelCopiar', null, 'Não foi possível copiar'), ok ? 'ok' : 'erro');
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
      var jobId = null;      // só conhecido quando session.start responde
      var fechado = false;
      var guardados = [];    // job.* que chegaram antes disso

      function soltar() {
        bridge.off('job.progress', aoProgredir);
        bridge.off('job.done', aoTerminar);
      }

      function aplicar(tipo, p) {
        if (tipo === 'progresso') {
          pintarProgresso(p.status || 'Trabalhando…', p.pct);
          return;
        }
        if (fechado) { return; }
        fechado = true;
        soltar();
        resolve(p);
      }

      /* Um evento sem jobId conhecido NÃO é assumido como deste trabalho: a
         ponte só aceita um job por vez, mas a resposta com o jobId pode chegar
         depois do primeiro job.progress. Guarda e reprocessa. */
      function receber(tipo, p) {
        if (!p || fechado) { return; }
        if (jobId === null) { guardados.push({ tipo: tipo, p: p }); return; }
        if (p.jobId !== jobId) {
          console.warn('evento ' + tipo + ' de outro job ignorado:', p.jobId);
          return;
        }
        aplicar(tipo, p);
      }

      function aoProgredir(p) { receber('progresso', p); }
      function aoTerminar(p) { receber('done', p); }

      bridge.on('job.progress', aoProgredir);
      bridge.on('job.done', aoTerminar);

      /* A ponte aceita um job por vez e as abas carregam dados por job logo na
         abertura (catalogo, recursos, atualizacoes, apps, icones). Um "Iniciar
         sessao" nesse intervalo recebia "ja existe um trabalho em andamento" e
         o usuario via o ponto de restauracao "falhar". Mesmo padrao de
         configure.js (chamarJobComEspera): espera e tenta de novo, ate 30 s. */
      var limite = Date.now() + 30000;
      function chamarComEspera() {
        return bridge.call('session.start', payload).catch(function (e) {
          if (!/trabalho em andamento/i.test((e && e.message) || '') || Date.now() > limite) { throw e; }
          pintarProgresso('Esperando outro trabalho terminar…');
          return new Promise(function (r) { setTimeout(r, 500); }).then(chamarComEspera);
        });
      }

      chamarComEspera().then(function (r) {
        jobId = (r && r.jobId) || null;
        if (!jobId) {
          fechado = true;
          soltar();
          reject(new Error('a ponte não devolveu o identificador do trabalho'));
          return;
        }
        var fila = guardados;
        guardados = [];
        fila.forEach(function (item) {
          if (item.p.jobId === jobId) {
            aplicar(item.tipo, item.p);
          } else {
            console.warn('evento ' + item.tipo + ' de outro job descartado:', item.p.jobId);
          }
        });
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
      titulo: traduzir('shell.sessao.titulo', null, 'Ponto de restauração'),
      html: explicacaoPonto() + '<p id="modal-progresso" class="sessao-progresso"></p>',
      botoes: [
        {
          rotulo: traduzir('shell.sessao.criarEContinuar', null, 'Criar ponto e continuar'),
          classe: 'btn-primary',
          mantemAberto: true,
          onClick: function () {
            travarBotoesModal();
            pintarProgresso(traduzir('shell.sessao.criando', null, 'Criando ponto de restauração…'), 0);
            abrirSessao({ skip: false }).then(function (p) {
              if (p && p.ok) {
                status.refresh();
                modal.close();
                toast(traduzir('shell.sessao.abertaComPonto', null, 'Sessão aberta com ponto de restauração'), 'ok');
                fim(true);
                return;
              }
              modalPontoFalhou((p && p.error && p.error.message) ||
                traduzir('shell.sessao.naoFoiPossivelCriar', null, 'não foi possível criar o ponto'), fim);
            }).catch(function (e) {
              modalPontoFalhou(e.message, fim);
            });
          }
        },
        { rotulo: traduzir('shell.cancelar', null, 'Cancelar'), onClick: function () { fim(false); } }
      ]
    });
  }

  function modalPontoFalhou(mensagem, fim) {
    status.refresh();
    modal.open({
      titulo: traduzir('shell.sessao.falhouTitulo', null, 'O ponto de restauração falhou'),
      html: '<p class="sessao-erro">' + escaparHtml(mensagem) + '</p>' +
            '<p>' + traduzir('shell.sessao.falhouTexto', null,
              'Nada foi alterado no sistema. Você pode fechar e resolver o motivo ' +
              '(Proteção do Sistema desligada, disco cheio, política de grupo) ou ' +
              'prosseguir assumindo o risco.') + '</p>',
      botoes: [
        { rotulo: traduzir('shell.fechar', null, 'Fechar'), onClick: function () { fim(false); } },
        {
          rotulo: traduzir('shell.sessao.prosseguirSemPonto', null, 'Prosseguir sem ponto'),
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
        titulo: traduzir('shell.sessao.pularTitulo', null, 'Prosseguir sem ponto de restauração'),
        html: '<p>' + traduzir('shell.sessao.pularTexto', null,
              'Sem ponto de restauração você perde a rede de segurança do próprio ' +
              'Windows. Os ajustes continuam reversíveis pelo Undo, mas nada mais ' +
              'protege o sistema se algo externo der errado.') + '</p>' +
              '<p>' + traduzir('shell.sessao.pularConfirmar', null, 'Para confirmar, digite exatamente:') + '</p>' +
              '<p class="sessao-frase">' + escaparHtml(frase) + '</p>' +
              '<input type="text" id="modal-frase" class="campo" autocomplete="off" spellcheck="false" ' +
              'aria-label="' + escaparHtml(traduzir('shell.sessao.fraseLabel', null, 'Frase de confirmação')) + '">' +
              '<p id="modal-progresso" class="sessao-progresso"></p>',
        botoes: [
          {
            rotulo: traduzir('shell.sessao.confirmar', null, 'Confirmar'),
            classe: 'btn-danger',
            mantemAberto: true,
            onClick: function () {
              var campo = document.getElementById('modal-frase');
              var digitado = campo ? campo.value : '';
              travarBotoesModal();
              pintarProgresso(traduzir('shell.sessao.abrindoSemPonto', null, 'Abrindo a sessão sem ponto…'), 0);
              abrirSessao({ skip: true, frase: digitado }).then(function (p) {
                if (p && p.ok) {
                  status.refresh();
                  modal.close();
                  toast(traduzir('shell.sessao.abertaSemPonto', null, 'Sessão aberta SEM ponto de restauração'), 'aviso');
                  fim(true);
                  return;
                }
                destravarBotoesModal();
                pintarProgresso('', null);
                toast((p && p.error && p.error.message) ||
                  traduzir('shell.sessao.naoFoiPossivelAbrir', null, 'não foi possível abrir a sessão'), 'erro');
              }).catch(function (e) {
                // Frase errada: a ponte recusa antes de criar job, o modal fica.
                destravarBotoesModal();
                pintarProgresso('', null);
                toast(e.message, 'erro');
              });
            }
          },
          { rotulo: traduzir('shell.cancelar', null, 'Cancelar'), onClick: function () { fim(false); } }
        ]
      });
      var campo = document.getElementById('modal-frase');
      if (campo) { campo.focus(); }
    }).catch(function (e) {
      toast(e.message, 'erro');
      fim(false);
    });
  }

  // Fluxo em andamento: duas abas (ou dois cliques) pedindo sessão ao mesmo
  // tempo compartilham a MESMA promessa, senão abririam dois modais e dois
  // session.start - e o segundo morreria com "ja existe um trabalho".
  var fluxoSessao = null;

  function executarEnsure() {
    return bridge.call('session.status').then(function (s) {
      status.aplicar(s);
      if (s && s.pronto) { return true; }

      return new Promise(function (resolve) {
        var terminado = false;

        function fim(valor) {
          if (terminado) { return; }
          terminado = true;
          document.removeEventListener('keydown', aoEscapar);
          // Resolver aqui é o que libera o cache: quem zera fluxoSessao é o
          // handler de encerramento abaixo, que confere a identidade da
          // promessa (zerar direto daqui apagaria um fluxo novo já iniciado).
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
      toast(traduzir('shell.sessao.naoFoiPossivelConsultar', null, 'Não foi possível consultar a sessão: ') + e.message, 'erro');
      return false;
    });
  }

  var session = {
    ensure: function () {
      if (fluxoSessao) { return fluxoSessao; }

      // Libera o cache quando o fluxo termina (fim(), atalho de sessão já
      // pronta ou falha), e só se ninguém tiver começado outro nesse meio-tempo.
      var meu = executarEnsure().then(function (v) {
        if (fluxoSessao === meu) { fluxoSessao = null; }
        return v;
      }, function (e) {
        if (fluxoSessao === meu) { fluxoSessao = null; }
        throw e;
      });
      fluxoSessao = meu;
      return meu;
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

  /* ---------------- barra de titulo (janela sem moldura) ----------------
   * A janela roda com WindowStyle=None (WindowChrome cuida do redimensionar
   * pela borda); quem desenha minimizar/maximizar/fechar e a area de arrasto
   * e esta barra HTML de 40px. Duas camadas fazem o arrasto funcionar:
   *   1. CSS app-region:drag + CoreWebView2Settings.IsNonClientRegionSupportEnabled
   *      (quando o SDK do WebView2 suporta - e o caminho normal).
   *   2. Fallback: mousedown na area de arrasto chama a acao window.drag da
   *      ponte, que roda DragMove() na thread da UI (funciona mesmo sem o
   *      suporte a regiao nao-cliente do passo 1).
   */
  function ligarTitlebar() {
    var arrasto = document.getElementById('titlebar-drag');
    if (arrasto) {
      arrasto.addEventListener('mousedown', function (e) {
        if (e.button !== 0 || e.target !== arrasto) { return; }
        bridge.call('window.drag').catch(function () { /* SDK sem suporte: ignora */ });
      });
      arrasto.addEventListener('dblclick', function (e) {
        if (e.target !== arrasto) { return; }
        bridge.call('window.maximizeToggle').then(atualizarIconeMaximizar).catch(function () { });
      });
    }

    var min = document.getElementById('win-min');
    if (min) { min.addEventListener('click', function () { bridge.call('window.minimize').catch(function () { }); }); }

    var max = document.getElementById('win-max');
    if (max) {
      max.addEventListener('click', function () {
        bridge.call('window.maximizeToggle').then(atualizarIconeMaximizar).catch(function () { });
      });
    }

    var fechar = document.getElementById('win-close');
    if (fechar) { fechar.addEventListener('click', function () { bridge.call('window.close').catch(function () { }); }); }

    bridge.call('window.state').then(atualizarIconeMaximizar).catch(function () { });
  }

  function atualizarIconeMaximizar(estado) {
    var max = document.getElementById('win-max');
    if (!max) { return; }
    var maximizada = !!(estado && estado.maximized);
    max.title = traduzir(maximizada ? 'shell.janela.restaurar' : 'shell.janela.maximizar', null,
      maximizada ? 'Restaurar' : 'Maximizar');
    max.setAttribute('aria-label', max.title);
  }

  /* ---------------- menu lateral: recolher/expandir ---------------- */

  function ligarSidebarCollapse() {
    var botao = document.getElementById('sidebar-collapse');
    if (!botao) { return; }

    function aplicarEstado(recolhido) {
      document.body.dataset.sidebar = recolhido ? 'collapsed' : 'expanded';
      botao.setAttribute('aria-pressed', recolhido ? 'true' : 'false');
      botao.title = traduzir(recolhido ? 'shell.expandir' : 'shell.recolher', null,
        recolhido ? 'Expandir menu' : 'Recolher menu');
      botao.setAttribute('aria-label', botao.title);
    }

    botao.addEventListener('click', function () {
      var recolhido = document.body.dataset.sidebar !== 'collapsed';
      aplicarEstado(recolhido);
      bridge.call('settings.set', { sidebarCollapsed: recolhido }).catch(function () { /* T4 pode nao existir ainda */ });
    });

    // Le o estado salvo; se a acao ainda nao existir (T4 nao rodou nesta
    // onda) ou nao houver preferencia, comeca expandido.
    bridge.call('settings.get').then(function (s) {
      aplicarEstado(!!(s && s.sidebarCollapsed));
    }).catch(function () { aplicarEstado(false); });
  }

  /* ---------------- seletor de idioma da barra de titulo ---------------- */

  var BANDEIRA_LANG = { 'pt-BR': String.fromCodePoint(0x1F1E7, 0x1F1F7), en: String.fromCodePoint(0x1F1FA, 0x1F1F8) };
  var CODIGO_LANG = { 'pt-BR': 'PT', en: 'EN' };

  function pintarSeletorIdioma(lang) {
    var bandeira = document.getElementById('lang-bandeira');
    var codigo = document.getElementById('lang-codigo');
    if (bandeira) { bandeira.textContent = BANDEIRA_LANG[lang] || BANDEIRA_LANG['pt-BR']; }
    if (codigo) { codigo.textContent = CODIGO_LANG[lang] || CODIGO_LANG['pt-BR']; }
  }

  function ligarSeletorIdioma() {
    var botao = document.getElementById('lang-toggle');
    if (botao) {
      botao.addEventListener('click', function () {
        if (!window.tmx || !tmx.i18n) { return; }
        tmx.i18n.set(tmx.i18n.lang === 'en' ? 'pt-BR' : 'en');
      });
    }
    document.addEventListener('tmx:lang', function (e) {
      pintarSeletorIdioma((e.detail && e.detail.lang) || 'pt-BR');
      // Textos dinamicos ja pintados na tela (barra de status, botao
      // maximizar/restaurar) precisam ser repintados: nao tem data-i18n
      // porque sao montados em JS, entao tmx.i18n.apply() nao os alcanca.
      if (status.ultimo) { status.aplicar(status.ultimo); }
      var celJob = document.getElementById('st-job');
      if (celJob && celJob.textContent === 'Ocioso' || (celJob && !celJob.textContent)) {
        celJob.textContent = traduzir('shell.status.ocioso', null, 'Ocioso');
      }
      var recolhido = document.body.dataset.sidebar === 'collapsed';
      var colBotao = document.getElementById('sidebar-collapse');
      if (colBotao) {
        colBotao.title = traduzir(recolhido ? 'shell.expandir' : 'shell.recolher', null,
          recolhido ? 'Expandir menu' : 'Recolher menu');
        colBotao.setAttribute('aria-label', colBotao.title);
      }
      bridge.call('window.state').then(atualizarIconeMaximizar).catch(function () { });
    });
    pintarSeletorIdioma((window.tmx && tmx.i18n && tmx.i18n.lang) || 'pt-BR');
  }

  /* ---------------- link "Novidades" (release notes no GitHub) ----------------
   * O slug do repositório ('usuario/repositorio') vem no MESMO shell.version
   * que já monta #versao - Actions.Shell.ps1 devolve 'repo' ali. Sem depender
   * de nenhuma ação nova nem de Actions.System.ps1 (outro agente, outra onda).
   */
  var repoAtual = '';

  function ligarLinksExternos() {
    document.querySelectorAll('#sidebar a[href="#"]').forEach(function (a) {
      a.addEventListener('click', function (e) {
        e.preventDefault();
        var abrir = function (repo) {
          if (!repo) { return; }
          bridge.call('shell.openUrl', { url: 'https://github.com/' + repo + '/releases' })
            .catch(function (e2) { toast(e2.message, 'erro'); });
        };
        if (repoAtual) { abrir(repoAtual); return; }
        bridge.call('shell.version').then(function (v) {
          repoAtual = (v && v.repo) || '';
          abrir(repoAtual);
        }).catch(function (e2) { toast(e2.message, 'erro'); });
      });
    });
  }

  /* ---------------- arranque ---------------- */

  function iniciar() {
    document.querySelectorAll('nav [data-tab]').forEach(function (b) {
      b.addEventListener('click', function () { tabs.show(b.getAttribute('data-tab')); });
    });

    ligarSubAbas();
    ligarTitlebar();
    ligarSidebarCollapse();
    ligarSeletorIdioma();
    ligarLinksExternos();

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
      if (p && p.ok === false) { toast((p.error && p.error.message) || traduzir('shell.status.trabalhoFalhou', null, 'O trabalho falhou'), 'erro'); }
      setTimeout(function () { celJob.textContent = traduzir('shell.status.ocioso', null, 'Ocioso'); }, 4000);
      status.refresh();
    });

    tabs.show('painel');

    bridge.call('shell.version').then(function (v) {
      // Só a versão: o "[modo de teste]" mora no título da janela, e os testes
      // de GUI comparam #versao com o conteúdo do arquivo VERSION.
      document.getElementById('versao').textContent = v.version || '';
      document.body.dataset.testmode = v.testMode ? '1' : '0';
      document.body.dataset.elevado = v.elevado ? '1' : '0';
      repoAtual = v.repo || repoAtual;
      // Controle de desenvolvimento: só no modo de teste, para a suite de GUI
      // disparar o fluxo da sessão sem depender de uma aba.
      if (v.testMode) { montarBotaoSessaoDev(); }
    }).catch(function (e) {
      document.getElementById('versao').textContent = '—';
      console.warn('shell.version falhou:', e.message);
    });

    status.refresh();
  }

  /* ---------------- textos da casca (shell.*) ---------------- */
  // Cada tela registra as próprias chaves no próprio arquivo (spec §3); a
  // casca (esta tela) registra as dela aqui. tmx.i18n já existe neste ponto
  // porque i18n.js carrega ANTES de app.js (ver index.html).
  if (window.tmx && tmx.i18n) {
    tmx.i18n.add('pt-BR', {
      'shell.subtitulo': 'Otimizador para jogos',
      'shell.nav.painel': 'Painel',
      'shell.nav.otimizacoes': 'Otimizações',
      'shell.nav.limpeza': 'Limpeza',
      'shell.nav.restauracao': 'Restauração',
      'shell.nav.aplicativos': 'Aplicativos',
      'shell.nav.microwin': 'MicroWin',
      'shell.nav.sistema': 'Sistema',
      'shell.nav.configuracoes': 'Configurações',
      'shell.protecao.titulo': 'Proteção ativa',
      'shell.protecao.legenda': 'Um ponto de restauração é criado antes de cada alteração.',
      'shell.versaoPrefixo': 'Versão',
      'shell.novidades': 'Novidades',
      'shell.github': 'GitHub',
      'shell.recolher': 'Recolher menu',
      'shell.expandir': 'Expandir menu',
      'shell.idioma.trocar': 'Trocar idioma',
      'shell.janela.minimizar': 'Minimizar',
      'shell.janela.maximizar': 'Maximizar',
      'shell.janela.restaurar': 'Restaurar',
      'shell.janela.fechar': 'Fechar',
      'shell.sistema.recursos': 'Recursos e manutenção',
      'shell.sistema.updates': 'Windows Update',
      'shell.cancelar': 'Cancelar',
      'shell.fechar': 'Fechar',
      'shell.status.semPonto': 'Nenhum ponto de restauração',
      'shell.status.criandoPonto': 'Criando ponto…',
      'shell.status.pontoPulado': 'Ponto pulado (sem proteção)',
      'shell.status.pontoCriado': 'Ponto #{seq} criado',
      'shell.status.pontoDeRestauracao': 'ponto de restauração',
      'shell.status.falhou': 'Falhou: {motivo}',
      'shell.status.semSessao': 'Sem sessão',
      'shell.status.nadaAReverter': 'Nada a reverter',
      'shell.status.concluido': 'Concluído: {nome}',
      'shell.status.trabalho': 'trabalho',
      'shell.status.ocioso': 'Ocioso',
      'shell.status.trabalhoFalhou': 'O trabalho falhou',
      'shell.status.comandoCopiado': 'Comando copiado',
      'shell.status.naoFoiPossivelCopiar': 'Não foi possível copiar',
      'shell.sessao.titulo': 'Ponto de restauração',
      'shell.sessao.explicacao': EXPLICACAO_PONTO_PT,
      'shell.sessao.criarEContinuar': 'Criar ponto e continuar',
      'shell.sessao.criando': 'Criando ponto de restauração…',
      'shell.sessao.abertaComPonto': 'Sessão aberta com ponto de restauração',
      'shell.sessao.naoFoiPossivelCriar': 'não foi possível criar o ponto',
      'shell.sessao.falhouTitulo': 'O ponto de restauração falhou',
      'shell.sessao.falhouTexto': 'Nada foi alterado no sistema. Você pode fechar e resolver o motivo ' +
        '(Proteção do Sistema desligada, disco cheio, política de grupo) ou prosseguir assumindo o risco.',
      'shell.sessao.prosseguirSemPonto': 'Prosseguir sem ponto',
      'shell.sessao.pularTitulo': 'Prosseguir sem ponto de restauração',
      'shell.sessao.pularTexto': 'Sem ponto de restauração você perde a rede de segurança do próprio ' +
        'Windows. Os ajustes continuam reversíveis pelo Undo, mas nada mais protege o sistema se algo externo der errado.',
      'shell.sessao.pularConfirmar': 'Para confirmar, digite exatamente:',
      'shell.sessao.fraseLabel': 'Frase de confirmação',
      'shell.sessao.confirmar': 'Confirmar',
      'shell.sessao.abrindoSemPonto': 'Abrindo a sessão sem ponto…',
      'shell.sessao.abertaSemPonto': 'Sessão aberta SEM ponto de restauração',
      'shell.sessao.naoFoiPossivelAbrir': 'não foi possível abrir a sessão',
      'shell.sessao.naoFoiPossivelConsultar': 'Não foi possível consultar a sessão: ',
      'painel.emConstrucao': 'Em construção',
      'limpeza.emConstrucao': 'Em construção',
      'restauracao.emConstrucao': 'Em construção',
      'configuracoes.emConstrucao': 'Em construção'
    });

    tmx.i18n.add('en', {
      'shell.subtitulo': 'Gaming optimizer',
      'shell.nav.painel': 'Dashboard',
      'shell.nav.otimizacoes': 'Optimizations',
      'shell.nav.limpeza': 'Cleanup',
      'shell.nav.restauracao': 'Restore',
      'shell.nav.aplicativos': 'Applications',
      'shell.nav.microwin': 'MicroWin',
      'shell.nav.sistema': 'System',
      'shell.nav.configuracoes': 'Settings',
      'shell.protecao.titulo': 'Protection active',
      'shell.protecao.legenda': 'A restore point is created before every change.',
      'shell.versaoPrefixo': 'Version',
      'shell.novidades': "What's new",
      'shell.github': 'GitHub',
      'shell.recolher': 'Collapse menu',
      'shell.expandir': 'Expand menu',
      'shell.idioma.trocar': 'Switch language',
      'shell.janela.minimizar': 'Minimize',
      'shell.janela.maximizar': 'Maximize',
      'shell.janela.restaurar': 'Restore',
      'shell.janela.fechar': 'Close',
      'shell.sistema.recursos': 'Resources & maintenance',
      'shell.sistema.updates': 'Windows Update',
      'shell.cancelar': 'Cancel',
      'shell.fechar': 'Close',
      'shell.status.semPonto': 'No restore point',
      'shell.status.criandoPonto': 'Creating restore point…',
      'shell.status.pontoPulado': 'Restore point skipped (unprotected)',
      'shell.status.pontoCriado': 'Restore point #{seq} created',
      'shell.status.pontoDeRestauracao': 'restore point',
      'shell.status.falhou': 'Failed: {motivo}',
      'shell.status.semSessao': 'No session',
      'shell.status.nadaAReverter': 'Nothing to undo',
      'shell.status.concluido': 'Done: {nome}',
      'shell.status.trabalho': 'job',
      'shell.status.ocioso': 'Idle',
      'shell.status.trabalhoFalhou': 'The job failed',
      'shell.status.comandoCopiado': 'Command copied',
      'shell.status.naoFoiPossivelCopiar': 'Could not copy',
      'shell.sessao.titulo': 'Restore point',
      'shell.sessao.explicacao':
        '<p>Before changing anything TweakMaxing opens a <strong>session</strong>: a folder ' +
        'that logs everything that gets touched (that is where Undo lives) and a Windows ' +
        '<strong>restore point</strong>.</p>' +
        '<p>Creating the restore point takes from a few seconds to a couple of minutes. Nothing ' +
        'is applied to the system until it exists.</p>',
      'shell.sessao.criarEContinuar': 'Create point and continue',
      'shell.sessao.criando': 'Creating restore point…',
      'shell.sessao.abertaComPonto': 'Session opened with a restore point',
      'shell.sessao.naoFoiPossivelCriar': 'could not create the restore point',
      'shell.sessao.falhouTitulo': 'The restore point failed',
      'shell.sessao.falhouTexto': 'Nothing was changed on the system. You can close and fix the cause ' +
        '(System Protection disabled, disk full, group policy) or proceed at your own risk.',
      'shell.sessao.prosseguirSemPonto': 'Proceed without a restore point',
      'shell.sessao.pularTitulo': 'Proceed without a restore point',
      'shell.sessao.pularTexto': "Without a restore point you lose Windows' own safety net. Tweaks " +
        'remain reversible through Undo, but nothing else protects the system if something external goes wrong.',
      'shell.sessao.pularConfirmar': 'To confirm, type exactly:',
      'shell.sessao.fraseLabel': 'Confirmation phrase',
      'shell.sessao.confirmar': 'Confirm',
      'shell.sessao.abrindoSemPonto': 'Opening the session without a restore point…',
      'shell.sessao.abertaSemPonto': 'Session opened WITHOUT a restore point',
      'shell.sessao.naoFoiPossivelAbrir': 'could not open the session',
      'shell.sessao.naoFoiPossivelConsultar': 'Could not check the session: ',
      'painel.emConstrucao': 'Under construction',
      'limpeza.emConstrucao': 'Under construction',
      'restauracao.emConstrucao': 'Under construction',
      'configuracoes.emConstrucao': 'Under construction'
    });
  }

  // esc: o escapador que modal.open({html}) exige para qualquer texto vindo
  // do catálogo, de um job ou de uma mensagem de erro do PowerShell.
  // aguardarTodas: usado pelo init() das abas que carregam várias coisas em
  // paralelo e precisam rejeitar se QUALQUER uma falhar (ver tabs.show).
  // i18n: preserva o objeto que i18n.js já colocou em window.tmx.i18n -
  // i18n.js carrega ANTES deste arquivo (ver index.html) exatamente para
  // que este objeto já exista aqui.
  var tmxPrevio = window.tmx || {};
  window.tmx = {
    bridge: bridge, modal: modal, toast: toast, tabs: tabs,
    status: status, session: session, esc: escaparHtml,
    aguardarTodas: aguardarTodas,
    i18n: tmxPrevio.i18n
  };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', iniciar);
  } else {
    iniciar();
  }
})();
