/* restauracao.js - tela Restauração (v2, T5; spec §9).
 *
 * Monta #tab-restauracao a partir daqui. Ações da ponte (todas devolvem
 * {jobId}; o resultado chega em job.done):
 *   restore.list                           -> { pontos: [{ sequencia, nome, data }] }
 *   restore.create  { nome? }              -> { resultado, pontos }
 *   restore.delete  { sequencia }          -> { resultado, pontos }
 *   restore.restore { sequencia, confirmado:true } -> { resultado }
 *
 * restore.restore nunca reinicia sozinho: a tela confirma antes e, depois,
 * avisa para reiniciar. No modo de teste as quatro são simuladas pelo
 * back-end (lista falsa na home de teste).
 */
(function () {
  'use strict';
  window.tmxTabs = window.tmxTabs || {};

  if (window.tmx && tmx.i18n) {
    tmx.i18n.add('pt-BR', {
      'restauracao.eyebrow': 'Restauração',
      'restauracao.titulo': 'Pontos de restauração',
      'restauracao.subtitulo': 'Cópias do estado do Windows. Se algo der errado depois de uma alteração, volte a uma delas.',
      'restauracao.novo.titulo': 'Criar um ponto agora',
      'restauracao.novo.texto': 'Leva de alguns segundos a poucos minutos. Seus arquivos pessoais não entram no ponto.',
      'restauracao.novo.nome': 'Nome do ponto (opcional)',
      'restauracao.novo.placeholder': 'TweakMaxing {agora}',
      'restauracao.novo.criar': 'Criar ponto',
      'restauracao.novo.criando': 'Criando…',
      'restauracao.novo.criado': 'Ponto de restauração criado',
      'restauracao.lista.titulo': 'Pontos existentes',
      'restauracao.lista.contagem': '{n} pontos',
      'restauracao.lista.contagem1': '1 ponto',
      'restauracao.lista.vazia': 'Nenhum ponto de restauração encontrado. Crie um acima antes de alterar o sistema.',
      'restauracao.lista.lendo': 'Lendo os pontos de restauração…',
      'restauracao.lista.erro': 'Não foi possível ler os pontos: {msg}',
      'restauracao.lista.maisRecente': 'Mais recente',
      'restauracao.restaurar': 'Restaurar',
      'restauracao.excluir': 'Excluir',
      'restauracao.restaurar.titulo': 'Restaurar o sistema?',
      'restauracao.restaurar.texto': 'O Windows volta ao estado de "{nome}" ({data}).',
      'restauracao.restaurar.aviso1': 'Programas e drivers instalados depois desse ponto são removidos; os ajustes feitos depois dele são desfeitos.',
      'restauracao.restaurar.aviso2': 'Seus documentos, fotos e outros arquivos pessoais não são afetados.',
      'restauracao.restaurar.aviso3': 'A restauração só acontece quando você reiniciar o computador. Salve o que estiver aberto antes.',
      'restauracao.restaurar.confirmar': 'Restaurar para este ponto',
      'restauracao.restaurar.agendada.titulo': 'Restauração agendada',
      'restauracao.restaurar.agendada.texto': 'Reinicie o computador para concluir a restauração. O TweakMaxing não reinicia sozinho.',
      'restauracao.restaurar.simulada': 'Modo de teste: nada foi restaurado de verdade.',
      'restauracao.excluir.titulo': 'Excluir o ponto?',
      'restauracao.excluir.texto': 'O ponto "{nome}" ({data}) será apagado. Não dá para desfazer.',
      'restauracao.excluir.confirmar': 'Excluir ponto',
      'restauracao.excluido': 'Ponto excluído',
      'restauracao.trabalhando': 'Trabalhando…'
    });

    tmx.i18n.add('en', {
      'restauracao.eyebrow': 'Restore',
      'restauracao.titulo': 'Restore points',
      'restauracao.subtitulo': 'Snapshots of the Windows state. If something goes wrong after a change, go back to one of them.',
      'restauracao.novo.titulo': 'Create a point now',
      'restauracao.novo.texto': 'Takes from a few seconds to a couple of minutes. Your personal files are not part of the point.',
      'restauracao.novo.nome': 'Point name (optional)',
      'restauracao.novo.placeholder': 'TweakMaxing {agora}',
      'restauracao.novo.criar': 'Create point',
      'restauracao.novo.criando': 'Creating…',
      'restauracao.novo.criado': 'Restore point created',
      'restauracao.lista.titulo': 'Existing points',
      'restauracao.lista.contagem': '{n} points',
      'restauracao.lista.contagem1': '1 point',
      'restauracao.lista.vazia': 'No restore points found. Create one above before changing the system.',
      'restauracao.lista.lendo': 'Reading restore points…',
      'restauracao.lista.erro': 'Could not read the restore points: {msg}',
      'restauracao.lista.maisRecente': 'Latest',
      'restauracao.restaurar': 'Restore',
      'restauracao.excluir': 'Delete',
      'restauracao.restaurar.titulo': 'Restore the system?',
      'restauracao.restaurar.texto': 'Windows goes back to the state of "{nome}" ({data}).',
      'restauracao.restaurar.aviso1': 'Programs and drivers installed after this point are removed; changes made after it are undone.',
      'restauracao.restaurar.aviso2': 'Your documents, photos and other personal files are not affected.',
      'restauracao.restaurar.aviso3': 'The restore only happens when you restart the computer. Save your open work first.',
      'restauracao.restaurar.confirmar': 'Restore to this point',
      'restauracao.restaurar.agendada.titulo': 'Restore scheduled',
      'restauracao.restaurar.agendada.texto': 'Restart the computer to finish the restore. TweakMaxing does not restart on its own.',
      'restauracao.restaurar.simulada': 'Test mode: nothing was actually restored.',
      'restauracao.excluir.titulo': 'Delete the point?',
      'restauracao.excluir.texto': 'The point "{nome}" ({data}) will be deleted. This cannot be undone.',
      'restauracao.excluir.confirmar': 'Delete point',
      'restauracao.excluido': 'Point deleted',
      'restauracao.trabalhando': 'Working…'
    });
  }

  function t(chave, vars) { return tmx.i18n.t(chave, vars); }
  function esc(s) { return tmx.esc(s); }

  /* Mesmo padrão de painel.js: ouvinte antes da chamada, job.done de jobId
     ainda desconhecido fica guardado. */
  function chamarJob(nome, payload) {
    return new Promise(function (resolve, reject) {
      var jobId = null;
      var guardados = [];
      function fechar(p) {
        tmx.bridge.off('job.done', ouvinte);
        if (p.ok) { resolve(p.result); } else { reject(new Error((p.error && p.error.message) || 'o trabalho falhou')); }
      }
      function ouvinte(p) {
        if (!p) { return; }
        if (jobId === null) { guardados.push(p); return; }
        if (p.jobId === jobId) { fechar(p); }
      }
      tmx.bridge.on('job.done', ouvinte);
      tmx.bridge.callComEspera(nome, payload, 90000).then(function (r) {
        jobId = (r && r.jobId) || null;
        if (!jobId) { tmx.bridge.off('job.done', ouvinte); reject(new Error('resposta sem jobId')); return; }
        for (var i = 0; i < guardados.length; i++) {
          if (guardados[i].jobId === jobId) { fechar(guardados[i]); return; }
        }
        guardados = [];
      }).catch(function (e) {
        tmx.bridge.off('job.done', ouvinte);
        reject(e);
      });
    });
  }

  var estado = {
    montado: false,
    pontos: null,
    erro: null,
    ocupado: false,
    criando: false
  };

  /* ---------------- formatação ---------------- */

  function locale() { return tmx.i18n.lang === 'en' ? 'en-US' : 'pt-BR'; }

  function dataHora(iso) {
    var d = new Date(iso);
    if (isNaN(d.getTime())) { return String(iso || '—'); }
    return d.toLocaleDateString(locale(), { day: '2-digit', month: '2-digit', year: 'numeric' }) + ' ' +
      d.toLocaleTimeString(locale(), { hour: '2-digit', minute: '2-digit' });
  }

  function agoraPadrao() {
    var d = new Date();
    function z(n) { return (n < 10 ? '0' : '') + n; }
    return d.getFullYear() + '-' + z(d.getMonth() + 1) + '-' + z(d.getDate()) + ' ' + z(d.getHours()) + ':' + z(d.getMinutes());
  }

  var ICONE_ESCUDO = '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" ' +
    'stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false">' +
    '<path d="M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z"></path>' +
    '<path d="m9 12 2 2 4-4"></path></svg>';

  /* ---------------- esqueleto ---------------- */

  function montar() {
    var sec = document.getElementById('tab-restauracao');
    if (!sec) { return; }
    sec.classList.add('tmx-tela');
    sec.innerHTML =
      '<header class="tmx-cab">' +
        '<p class="tmx-eyebrow" data-i18n="restauracao.eyebrow"></p>' +
        '<h1 class="tmx-titulo" data-i18n="restauracao.titulo"></h1>' +
        '<p class="tmx-subtitulo" data-i18n="restauracao.subtitulo"></p>' +
      '</header>' +
      '<article class="tmx-card rs-novo">' +
        '<span class="rs-novo-icone">' + ICONE_ESCUDO + '</span>' +
        '<div class="rs-novo-corpo">' +
          '<h2 class="rs-h" data-i18n="restauracao.novo.titulo"></h2>' +
          '<p class="rs-nota" data-i18n="restauracao.novo.texto"></p>' +
          '<div class="rs-novo-linha">' +
            '<input type="text" id="rs-nome" class="campo rs-nome" maxlength="64" autocomplete="off" spellcheck="false">' +
            '<button type="button" id="rs-criar" class="btn btn-primary"></button>' +
          '</div>' +
        '</div>' +
      '</article>' +
      '<article class="tmx-card rs-lista-card">' +
        '<div class="rs-lista-cab">' +
          '<h2 class="rs-h" data-i18n="restauracao.lista.titulo"></h2>' +
          '<span class="rs-contagem" id="rs-contagem"></span>' +
        '</div>' +
        '<div id="rs-lista" class="rs-lista"></div>' +
      '</article>';

    tmx.i18n.apply(sec);
    sec.querySelector('#rs-criar').addEventListener('click', criar);
    sec.querySelector('#rs-nome').addEventListener('keydown', function (e) { if (e.key === 'Enter') { criar(); } });
    estado.montado = true;
  }

  /* ---------------- pintura ---------------- */

  function pintarNovo() {
    var nome = document.getElementById('rs-nome');
    if (nome) {
      nome.placeholder = t('restauracao.novo.placeholder', { agora: agoraPadrao() });
      nome.setAttribute('aria-label', t('restauracao.novo.nome'));
      nome.disabled = estado.criando;
    }
    var b = document.getElementById('rs-criar');
    if (b) {
      b.disabled = estado.criando || estado.ocupado;
      b.textContent = t(estado.criando ? 'restauracao.novo.criando' : 'restauracao.novo.criar');
    }
  }

  function pintarLista() {
    var raiz = document.getElementById('rs-lista');
    var cont = document.getElementById('rs-contagem');
    if (!raiz) { return; }
    if (estado.pontos === null) {
      raiz.innerHTML = '<p class="vazio">' + esc(estado.erro ? t('restauracao.lista.erro', { msg: estado.erro }) : t('restauracao.lista.lendo')) + '</p>';
      if (cont) { cont.textContent = ''; }
      return;
    }
    var n = estado.pontos.length;
    if (cont) { cont.textContent = n === 1 ? t('restauracao.lista.contagem1') : t('restauracao.lista.contagem', { n: n }); }
    if (!n) {
      raiz.innerHTML = '<p class="vazio" id="rs-vazia">' + esc(t('restauracao.lista.vazia')) + '</p>';
      return;
    }
    raiz.innerHTML = '';
    estado.pontos.forEach(function (p, i) {
      var linha = document.createElement('div');
      linha.className = 'rs-ponto';
      linha.id = 'rs-ponto-' + p.sequencia;
      linha.setAttribute('data-seq', p.sequencia);
      linha.innerHTML =
        '<span class="rs-seq">#' + esc(p.sequencia) + '</span>' +
        '<span class="rs-ponto-texto">' +
          '<span class="rs-ponto-nome">' + esc(p.nome || '—') +
            (i === 0 ? ' <span class="rs-selo">' + esc(t('restauracao.lista.maisRecente')) + '</span>' : '') +
          '</span>' +
          '<span class="rs-ponto-data">' + esc(dataHora(p.data)) + '</span>' +
        '</span>' +
        '<span class="rs-ponto-acoes"></span>';
      var acoes = linha.querySelector('.rs-ponto-acoes');

      var restaurar = document.createElement('button');
      restaurar.type = 'button';
      restaurar.className = 'btn rs-restaurar';
      restaurar.textContent = t('restauracao.restaurar');
      restaurar.disabled = estado.ocupado;
      restaurar.addEventListener('click', function () { confirmarRestaurar(p); });
      acoes.appendChild(restaurar);

      var excluir = document.createElement('button');
      excluir.type = 'button';
      excluir.className = 'btn btn-danger rs-excluir';
      excluir.textContent = t('restauracao.excluir');
      excluir.disabled = estado.ocupado;
      excluir.addEventListener('click', function () { confirmarExcluir(p); });
      acoes.appendChild(excluir);

      raiz.appendChild(linha);
    });
  }

  function pintarTudo() {
    if (!estado.montado) { return; }
    pintarNovo();
    pintarLista();
  }

  /* ---------------- ações ---------------- */

  function carregar() {
    estado.erro = null;
    return chamarJob('restore.list', null).then(function (r) {
      estado.pontos = (r && r.pontos) || [];
      pintarTudo();
    }).catch(function (e) {
      estado.pontos = null;
      estado.erro = e.message;
      pintarTudo();
      throw e;
    });
  }

  function criar() {
    if (estado.criando || estado.ocupado) { return; }
    var campo = document.getElementById('rs-nome');
    var nome = campo ? campo.value.trim() : '';
    estado.criando = true;
    estado.ocupado = true;
    pintarTudo();
    chamarJob('restore.create', nome ? { nome: nome } : {}).then(function (r) {
      if (r && r.pontos) { estado.pontos = r.pontos; }
      if (campo) { campo.value = ''; }
      tmx.toast(t('restauracao.novo.criado'), 'ok');
    }).catch(function (e) {
      tmx.toast(e.message, 'erro');
    }).then(function () {
      estado.criando = false;
      estado.ocupado = false;
      pintarTudo();
    });
  }

  function travarModal() {
    var b = document.querySelectorAll('#modal-buttons button');
    for (var i = 0; i < b.length; i++) { b[i].disabled = true; }
  }

  function progressoModal(texto) {
    var el = document.getElementById('modal-progresso');
    if (el) { el.textContent = texto; }
  }

  function confirmarRestaurar(p) {
    var vars = { nome: p.nome || ('#' + p.sequencia), data: dataHora(p.data) };
    tmx.modal.open({
      titulo: t('restauracao.restaurar.titulo'),
      html: '<p>' + esc(t('restauracao.restaurar.texto', vars)) + '</p>' +
            '<ul class="rs-avisos">' +
              '<li class="rs-aviso-forte">' + esc(t('restauracao.restaurar.aviso1')) + '</li>' +
              '<li>' + esc(t('restauracao.restaurar.aviso2')) + '</li>' +
              '<li class="rs-aviso-forte">' + esc(t('restauracao.restaurar.aviso3')) + '</li>' +
            '</ul>' +
            '<p id="modal-progresso" class="sessao-progresso"></p>',
      botoes: [
        {
          rotulo: t('restauracao.restaurar.confirmar'),
          classe: 'btn-danger rs-confirmar-restaurar',
          mantemAberto: true,
          onClick: function () {
            if (estado.ocupado) { return; }
            estado.ocupado = true;
            travarModal();
            progressoModal(t('restauracao.trabalhando'));
            chamarJob('restore.restore', { sequencia: p.sequencia, confirmado: true }).then(function (r) {
              var simulado = r && r.resultado && r.resultado.simulado;
              tmx.modal.open({
                titulo: t('restauracao.restaurar.agendada.titulo'),
                html: '<p class="rs-agendada">' + esc(t('restauracao.restaurar.agendada.texto')) + '</p>' +
                      (simulado ? '<p class="rs-nota">' + esc(t('restauracao.restaurar.simulada')) + '</p>' : ''),
                botoes: [{ rotulo: t('shell.fechar'), classe: 'btn-primary' }]
              });
            }).catch(function (e) {
              tmx.modal.close();
              tmx.toast(e.message, 'erro');
            }).then(function () {
              estado.ocupado = false;
              pintarTudo();
            });
          }
        },
        { rotulo: t('shell.cancelar') }
      ]
    });
  }

  function confirmarExcluir(p) {
    var vars = { nome: p.nome || ('#' + p.sequencia), data: dataHora(p.data) };
    tmx.modal.open({
      titulo: t('restauracao.excluir.titulo'),
      html: '<p>' + esc(t('restauracao.excluir.texto', vars)) + '</p>' +
            '<p id="modal-progresso" class="sessao-progresso"></p>',
      botoes: [
        {
          rotulo: t('restauracao.excluir.confirmar'),
          classe: 'btn-danger rs-confirmar-excluir',
          mantemAberto: true,
          onClick: function () {
            if (estado.ocupado) { return; }
            estado.ocupado = true;
            travarModal();
            progressoModal(t('restauracao.trabalhando'));
            chamarJob('restore.delete', { sequencia: p.sequencia }).then(function (r) {
              if (r && r.pontos) { estado.pontos = r.pontos; }
              tmx.modal.close();
              tmx.toast(t('restauracao.excluido'), 'ok');
            }).catch(function (e) {
              tmx.modal.close();
              tmx.toast(e.message, 'erro');
            }).then(function () {
              estado.ocupado = false;
              pintarTudo();
            });
          }
        },
        { rotulo: t('shell.cancelar') }
      ]
    });
  }

  var globaisLigados = false;

  function ligarGlobais() {
    document.addEventListener('tmx:lang', function () {
      if (!estado.montado) { return; }
      tmx.i18n.apply(document.getElementById('tab-restauracao'));
      pintarTudo();
    });
    // Outra tela criou/excluiu um ponto (Painel, sessão): a lista acompanha.
    tmx.bridge.on('job.done', function (p) {
      if (!estado.montado || !p || !p.ok || estado.ocupado) { return; }
      if ((p.name === 'restore.create' || p.name === 'restore.delete') && p.result && p.result.pontos) {
        estado.pontos = p.result.pontos;
        pintarLista();
      } else if (p.name === 'session.start') {
        carregar().catch(function () { });
      }
    });
  }

  window.tmxTabs.restauracao = {
    init: function () {
      if (!globaisLigados) { ligarGlobais(); globaisLigados = true; }
      estado.pontos = null;
      montar();
      pintarTudo();
      return carregar();
    }
  };
})();
