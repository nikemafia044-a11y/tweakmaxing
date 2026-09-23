/* updates.js - aba "Atualizações": três políticas de Windows Update
 * mutuamente exclusivas (grupo windows-update), lidas de updates.list.
 *
 * updates.list é assíncrona (job); updates.apply e updates.undo devolvem
 * {jobId} e o resultado real chega pelo evento job.done, correlacionado
 * aqui pelo jobId - mesmo padrão de configure.js.
 *
 * Tudo que entra em HTML passa por escapar(): nome, descrição, porquê e as
 * chaves de registro/serviço vêm do catálogo (que outra pessoa pode editar),
 * não de uma constante fixa do próprio JS.
 */
(function () {
  'use strict';
  window.tmxTabs = window.tmxTabs || {};

  var estado = {
    itens: [],
    ocupado: false
  };

  /* ---------------- texto ---------------- */

  function escapar(s) {
    return String(s === null || s === undefined ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }

  function listaHtml(itens) {
    return '<ul class="upd-chaves">' + (itens || []).map(function (t) {
      return '<li>' + escapar(t) + '</li>';
    }).join('') + '</ul>';
  }

  /* ---------------- ponte: correlaciona job.done pelo jobId ---------------- */

  function chamarJob(nome, payload, aoProgredir) {
    return tmx.bridge.callComEspera(nome, payload).then(function (resp) {
      var jobId = resp && resp.jobId;
      if (!jobId) { throw new Error('resposta sem jobId'); }
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

  /* A ponte aceita um job por vez em todo o aplicativo: a carga inicial pode
     cair atrás de um catalog.get/features.list que já estava rodando. */
  function chamarJobComEspera(nome, payload, aoProgredir, aoEsperar) {
    var limite = Date.now() + 90000;

    function tentar() {
      return chamarJob(nome, payload, aoProgredir).catch(function (e) {
        if (!/trabalho em andamento/i.test(e.message) || Date.now() > limite) { throw e; }
        if (typeof aoEsperar === 'function') { aoEsperar(); }
        return new Promise(function (resolve) { setTimeout(resolve, 700); }).then(tentar);
      });
    }
    return tentar();
  }

  function ocupar() {
    if (estado.ocupado) {
      tmx.toast('Espere o trabalho atual terminar', 'aviso');
      return false;
    }
    estado.ocupado = true;
    return true;
  }

  function liberar() { estado.ocupado = false; }

  function pintarProgresso(p) {
    var el = document.getElementById('modal-progresso');
    if (!el) { return; }
    var t = (p && p.status) || 'Trabalhando…';
    if (p && typeof p.pct === 'number') { t += ' (' + p.pct + '%)'; }
    el.textContent = t;
  }

  function travarModal() {
    var b = document.querySelectorAll('#modal-buttons button');
    for (var i = 0; i < b.length; i++) { b[i].disabled = true; }
  }

  /* ---------------- render ---------------- */

  function renderCartoes() {
    var raiz = document.getElementById('upd-cartoes');
    if (!raiz) { return; }
    raiz.innerHTML = '';

    if (!estado.itens.length) {
      raiz.innerHTML = '<p class="vazio">Nenhuma política de atualização disponível.</p>';
      return;
    }

    estado.itens.forEach(function (item) {
      var card = document.createElement('div');
      card.className = 'upd-card' + (item.ativo ? ' upd-card-ativa' : '');
      card.id = 'upd-' + item.id;
      card.setAttribute('data-id', item.id);

      var idRadio = 'upd-radio-' + item.id;
      card.innerHTML =
        '<label class="upd-card-topo" for="' + escapar(idRadio) + '">' +
          '<input type="radio" name="upd" id="' + escapar(idRadio) + '" value="' + escapar(item.id) + '"' +
            (item.ativo ? ' checked' : '') + '>' +
          '<span class="upd-nome">' + escapar(item.nome) + '</span>' +
          '<span class="estado upd-selo-ativa"' + (item.ativo ? '' : ' hidden') + '>' + (item.ativo ? 'Ativa' : '') + '</span>' +
        '</label>' +
        '<p class="upd-desc">' + escapar(item.descricao) + '</p>' +
        '<details class="upd-detalhes">' +
          '<summary>O que muda (' + item.chaves.length + ')</summary>' +
          listaHtml(item.chaves) +
        '</details>' +
        '<p class="upd-porque"><strong>Por quê:</strong> ' + escapar(item.porque) + '</p>' +
        '<div class="upd-rodape"></div>';

      var rodape = card.querySelector('.upd-rodape');

      var aplicar = document.createElement('button');
      aplicar.type = 'button';
      aplicar.className = 'btn btn-primary upd-aplicar';
      aplicar.textContent = 'Aplicar política';
      aplicar.setAttribute('aria-label', 'Aplicar: ' + item.nome);
      aplicar.addEventListener('click', function () { aplicarPolitica(item); });
      rodape.appendChild(aplicar);

      if (item.temUndo) {
        var desfazer = document.createElement('button');
        desfazer.type = 'button';
        desfazer.className = 'btn upd-desfazer';
        desfazer.textContent = 'Desfazer';
        desfazer.setAttribute('aria-label', 'Desfazer: ' + item.nome);
        desfazer.addEventListener('click', function () { desfazerPolitica(item); });
        rodape.appendChild(desfazer);
      }

      var radio = card.querySelector('input[type=radio]');
      radio.addEventListener('change', function () { marcarSelecionada(item.id); });

      raiz.appendChild(card);
    });
  }

  function marcarSelecionada(id) {
    var raiz = document.getElementById('upd-cartoes');
    if (!raiz) { return; }
    raiz.querySelectorAll('.upd-card').forEach(function (c) {
      c.classList.toggle('upd-card-selecionada', c.getAttribute('data-id') === id);
    });
  }

  /* ---------------- aplicar / desfazer ---------------- */

  function aplicarPolitica(item) {
    tmx.session.ensure().then(function (ok) {
      if (!ok) { return; }

      tmx.modal.open({
        titulo: 'Aplicar: ' + item.nome,
        html:
          '<p>' + escapar(item.descricao) + '</p>' +
          '<p>O que será gravado/alterado:</p>' + listaHtml(item.chaves) +
          '<p>Qualquer outra política deste grupo, se estiver aplicada nesta sessão, é desfeita antes.</p>' +
          '<p id="modal-progresso" class="sessao-progresso"></p>',
        botoes: [
          {
            rotulo: 'Aplicar política',
            classe: 'btn-primary',
            mantemAberto: true,
            onClick: function () {
              if (!ocupar()) { return; }
              travarModal();
              pintarProgresso({ status: 'Aplicando…', pct: 0 });
              chamarJob('updates.apply', { id: item.id }, pintarProgresso)
                .then(function (res) {
                  liberar();
                  tmx.modal.close();
                  aplicarLista(res && res.lista);
                  mostrarResultado(item, res);
                })
                .catch(function (e) {
                  liberar();
                  tmx.modal.close();
                  tmx.toast(e.message, 'erro');
                });
            }
          },
          { rotulo: 'Cancelar' }
        ]
      });
    });
  }

  function mostrarResultado(item, res) {
    var linha = res && res.resultado && res.resultado.itens && res.resultado.itens[0];
    var status = linha ? linha.status : '';
    if (status === 'aplicado' || status === 'aplicadoNaoVerificado' || status === 'jaAplicado') {
      tmx.toast(item.nome + ': aplicada', 'ok');
    } else {
      tmx.toast(item.nome + ': ' + (status || 'sem resultado') + (linha && linha.detalhe ? ' — ' + linha.detalhe : ''), 'erro');
    }
  }

  function desfazerPolitica(item) {
    tmx.modal.open({
      titulo: 'Desfazer: ' + item.nome,
      html: '<p>Restaura o que esta política mudou nesta sessão (registro e serviços voltam ao valor anterior).</p>' +
            '<p id="modal-progresso" class="sessao-progresso"></p>',
      botoes: [
        {
          rotulo: 'Desfazer',
          classe: 'btn-danger',
          mantemAberto: true,
          onClick: function () {
            if (!ocupar()) { return; }
            travarModal();
            pintarProgresso({ status: 'Revertendo…', pct: 0 });
            chamarJob('updates.undo', { id: item.id }, pintarProgresso)
              .then(function (res) {
                liberar();
                tmx.modal.close();
                aplicarLista(res && res.lista);
                var s = (res && res.resumo) || {};
                tmx.toast(item.nome + ': ' + (s.revertidos || 0) + ' item(ns) revertido(s)', (s.falhas ? 'erro' : 'ok'));
              })
              .catch(function (e) {
                liberar();
                tmx.modal.close();
                tmx.toast(e.message, 'erro');
              });
          }
        },
        { rotulo: 'Cancelar' }
      ]
    });
  }

  function aplicarLista(lista) {
    if (!lista) { return; }
    estado.itens = lista.itens || [];
    renderCartoes();
    var sec = document.getElementById('tab-atualizacoes');
    if (sec) { sec.setAttribute('aria-busy', 'false'); }
  }

  function carregarLista() {
    var esperando = false;
    return chamarJobComEspera('updates.list', null, null, function () {
      if (esperando) { return; }
      esperando = true;
      var raiz = document.getElementById('upd-cartoes');
      if (raiz) { raiz.innerHTML = '<p class="vazio">Esperando o trabalho em andamento terminar…</p>'; }
    }).then(function (lista) {
      aplicarLista(lista);
    }).catch(function (e) {
      var raiz = document.getElementById('upd-cartoes');
      if (raiz) { raiz.innerHTML = '<p class="vazio">Não foi possível ler as políticas de atualização: ' + escapar(e.message) + '</p>'; }
      // Repropaga: a mensagem inline acima (e o toast) já avisaram o
      // usuário, mas tabs.show precisa SABER que a carga falhou para
      // deixar a aba como não iniciada e tentar de novo na próxima
      // abertura. Engolir o erro aqui deixava a aba vazia para sempre.
      throw e;
    });
  }

  /* ---------------- arranque ---------------- */

  window.tmxTabs.atualizacoes = {
    init: function () {
      return carregarLista();
    }
  };
})();
