/* limpeza.js - tela Limpeza (v2, T5; spec §8).
 *
 * Monta #tab-limpeza a partir daqui. Ações da ponte:
 *   cleanup.scan  (job) -> { itens: [{ id, bytes, arquivos }] }  só mede
 *   cleanup.run   (job) { ids } -> { liberado, porItem, pulados }
 *   settings.get  (síncrona) lastCleanup / lastCleanupFreed
 *
 * Nada é apagado sem o modal de confirmação. 'lixeira' é marcada Perigoso e
 * 'prefetch' Não recomendado: as duas começam desmarcadas e o modal repete
 * o aviso quando estão na seleção.
 */
(function () {
  'use strict';
  window.tmxTabs = window.tmxTabs || {};

  if (window.tmx && tmx.i18n) {
    tmx.i18n.add('pt-BR', {
      'limpeza.eyebrow': 'Limpeza',
      'limpeza.titulo': 'Libere espaço no disco',
      'limpeza.subtitulo': 'Arquivos temporários e caches que o Windows recria sozinho. Nada é apagado antes de você confirmar.',
      'limpeza.selecionado': 'Selecionado para limpar',
      'limpeza.resumo': '{itens} de {total} itens · {arquivos} arquivos',
      'limpeza.analisar': 'Analisar de novo',
      'limpeza.analisando': 'Analisando…',
      'limpeza.limpar': 'Limpar selecionados',
      'limpeza.limpando': 'Limpando…',
      'limpeza.ultima': 'Última limpeza: {quando}, liberou {tamanho}',
      'limpeza.nunca': 'Nenhuma limpeza feita por aqui ainda.',
      'limpeza.arquivos': '{n} arquivos',
      'limpeza.arquivos1': '1 arquivo',
      'limpeza.medindo': 'medindo…',
      'limpeza.selo.perigoso': 'Perigoso',
      'limpeza.selo.naoRecomendado': 'Não recomendado',
      'limpeza.item.temp-usuario': 'Temporários do usuário',
      'limpeza.item.temp-usuario.desc': 'Pasta %TEMP% da sua conta: sobras de instaladores e programas.',
      'limpeza.item.temp-sistema': 'Temporários do sistema',
      'limpeza.item.temp-sistema.desc': 'Pasta Temp do Windows (%WINDIR%\\Temp).',
      'limpeza.item.wu-cache': 'Cache do Windows Update',
      'limpeza.item.wu-cache.desc': 'Atualizações já baixadas e instaladas. O serviço é parado durante a limpeza e religado no fim.',
      'limpeza.item.miniaturas': 'Miniaturas do Explorer',
      'limpeza.item.miniaturas.desc': 'Cache de miniaturas (thumbcache). O Explorer recria conforme você abre as pastas.',
      'limpeza.item.lixeira': 'Lixeira',
      'limpeza.item.lixeira.desc': 'Esvazia a Lixeira de todas as unidades. Os arquivos não podem ser recuperados depois.',
      'limpeza.item.prefetch': 'Prefetch',
      'limpeza.item.prefetch.desc': 'Dados que o Windows usa para abrir programas mais rápido. Apagar deixa as próximas aberturas mais lentas.',
      'limpeza.confirmar.titulo': 'Limpar {n} itens?',
      'limpeza.confirmar.texto': 'Estes itens serão apagados ({tamanho}). Arquivos em uso são pulados.',
      'limpeza.confirmar.aviso.lixeira': 'A Lixeira será esvaziada de vez: o que está nela não volta.',
      'limpeza.confirmar.aviso.prefetch': 'Limpar o Prefetch não acelera nada: os programas abrem mais devagar até o Windows reconstruí-lo.',
      'limpeza.confirmar.botao': 'Limpar agora',
      'limpeza.nadaSelecionado': 'Marque pelo menos um item.',
      'limpeza.resultado.titulo': 'Limpeza concluída',
      'limpeza.resultado.liberado': 'Liberado: {tamanho}',
      'limpeza.resultado.pulados': '{n} arquivos em uso foram pulados.',
      'limpeza.erro.scan': 'Não foi possível analisar: {msg}'
    });

    tmx.i18n.add('en', {
      'limpeza.eyebrow': 'Cleanup',
      'limpeza.titulo': 'Free up disk space',
      'limpeza.subtitulo': 'Temporary files and caches that Windows rebuilds on its own. Nothing is deleted until you confirm.',
      'limpeza.selecionado': 'Selected to clean',
      'limpeza.resumo': '{itens} of {total} items · {arquivos} files',
      'limpeza.analisar': 'Scan again',
      'limpeza.analisando': 'Scanning…',
      'limpeza.limpar': 'Clean selected',
      'limpeza.limpando': 'Cleaning…',
      'limpeza.ultima': 'Last cleanup: {quando}, freed {tamanho}',
      'limpeza.nunca': 'No cleanup done here yet.',
      'limpeza.arquivos': '{n} files',
      'limpeza.arquivos1': '1 file',
      'limpeza.medindo': 'measuring…',
      'limpeza.selo.perigoso': 'Dangerous',
      'limpeza.selo.naoRecomendado': 'Not recommended',
      'limpeza.item.temp-usuario': 'User temporary files',
      'limpeza.item.temp-usuario.desc': 'Your account %TEMP% folder: leftovers from installers and programs.',
      'limpeza.item.temp-sistema': 'System temporary files',
      'limpeza.item.temp-sistema.desc': 'Windows Temp folder (%WINDIR%\\Temp).',
      'limpeza.item.wu-cache': 'Windows Update cache',
      'limpeza.item.wu-cache.desc': 'Updates already downloaded and installed. The service is stopped during cleanup and started again at the end.',
      'limpeza.item.miniaturas': 'Explorer thumbnails',
      'limpeza.item.miniaturas.desc': 'Thumbnail cache (thumbcache). Explorer rebuilds it as you open folders.',
      'limpeza.item.lixeira': 'Recycle Bin',
      'limpeza.item.lixeira.desc': 'Empties the Recycle Bin on every drive. Files cannot be recovered afterwards.',
      'limpeza.item.prefetch': 'Prefetch',
      'limpeza.item.prefetch.desc': 'Data Windows uses to open programs faster. Deleting it makes the next launches slower.',
      'limpeza.confirmar.titulo': 'Clean {n} items?',
      'limpeza.confirmar.texto': 'These items will be deleted ({tamanho}). Files in use are skipped.',
      'limpeza.confirmar.aviso.lixeira': 'The Recycle Bin will be emptied for good: what is in it does not come back.',
      'limpeza.confirmar.aviso.prefetch': 'Cleaning Prefetch does not speed anything up: programs open slower until Windows rebuilds it.',
      'limpeza.confirmar.botao': 'Clean now',
      'limpeza.nadaSelecionado': 'Select at least one item.',
      'limpeza.resultado.titulo': 'Cleanup finished',
      'limpeza.resultado.liberado': 'Freed: {tamanho}',
      'limpeza.resultado.pulados': '{n} files in use were skipped.',
      'limpeza.erro.scan': 'Could not scan: {msg}'
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

  var ITENS = [
    { id: 'temp-usuario', marcado: true },
    { id: 'temp-sistema', marcado: true },
    { id: 'wu-cache', marcado: true },
    { id: 'miniaturas', marcado: true },
    { id: 'lixeira', marcado: false, selo: 'perigoso' },
    { id: 'prefetch', marcado: false, selo: 'naoRecomendado' }
  ];

  var estado = {
    montado: false,
    medidas: null,          // id -> { bytes, arquivos }
    marcados: {},
    settings: null,
    ocupado: false,
    fase: null,             // 'scan' | 'run' | null
    erro: null,
    resultado: null
  };
  ITENS.forEach(function (i) { estado.marcados[i.id] = i.marcado; });

  /* ---------------- formatação ---------------- */

  function locale() { return tmx.i18n.lang === 'en' ? 'en-US' : 'pt-BR'; }

  function tamanho(bytes) {
    var n = Number(bytes) || 0;
    var unidades = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    while (n >= 1024 && i < unidades.length - 1) { n /= 1024; i++; }
    return n.toLocaleString(locale(), { maximumFractionDigits: i === 0 ? 0 : 1 }) + ' ' + unidades[i];
  }

  function inteiro(n) { return (Number(n) || 0).toLocaleString(locale()); }

  function dataHora(iso) {
    var d = new Date(iso);
    if (isNaN(d.getTime())) { return String(iso || ''); }
    return d.toLocaleDateString(locale(), { day: '2-digit', month: '2-digit', year: 'numeric' }) + ' ' +
      d.toLocaleTimeString(locale(), { hour: '2-digit', minute: '2-digit' });
  }

  /* ---------------- esqueleto ---------------- */

  function montar() {
    var sec = document.getElementById('tab-limpeza');
    if (!sec) { return; }
    sec.classList.add('tmx-tela');
    sec.innerHTML =
      '<header class="tmx-cab">' +
        '<p class="tmx-eyebrow" data-i18n="limpeza.eyebrow"></p>' +
        '<h1 class="tmx-titulo" data-i18n="limpeza.titulo"></h1>' +
        '<p class="tmx-subtitulo" data-i18n="limpeza.subtitulo"></p>' +
      '</header>' +
      '<article class="lp-resumo">' +
        '<div class="lp-resumo-texto">' +
          '<span class="lp-resumo-rotulo" data-i18n="limpeza.selecionado"></span>' +
          '<strong class="lp-total" id="lp-total">…</strong>' +
          '<span class="lp-resumo-sub" id="lp-resumo-sub"></span>' +
          '<span class="lp-ultima" id="lp-ultima"></span>' +
        '</div>' +
        '<div class="lp-resumo-acoes">' +
          '<button type="button" class="btn" id="lp-analisar"></button>' +
          '<button type="button" class="btn btn-primary" id="lp-limpar"></button>' +
        '</div>' +
      '</article>' +
      '<div id="lp-resultado" class="lp-resultado" role="status" hidden></div>' +
      '<div id="lp-itens" class="lp-itens" role="group"></div>';

    tmx.i18n.apply(sec);
    sec.querySelector('#lp-analisar').addEventListener('click', function () { analisar(); });
    sec.querySelector('#lp-limpar').addEventListener('click', confirmar);
    montarItens();
    estado.montado = true;
  }

  function montarItens() {
    var raiz = document.getElementById('lp-itens');
    if (!raiz) { return; }
    raiz.innerHTML = '';
    ITENS.forEach(function (item) {
      var el = document.createElement('label');
      el.className = 'lp-item' + (item.selo ? ' lp-item-' + item.selo : '');
      el.id = 'lp-item-' + item.id;
      el.setAttribute('for', 'lp-chk-' + item.id);
      el.innerHTML =
        '<input type="checkbox" class="lp-chk" id="lp-chk-' + item.id + '" value="' + item.id + '">' +
        '<span class="lp-item-texto">' +
          '<span class="lp-item-nome">' + esc(t('limpeza.item.' + item.id)) +
            (item.selo ? ' <span class="lp-selo lp-selo-' + item.selo + '">' + esc(t('limpeza.selo.' + item.selo)) + '</span>' : '') +
          '</span>' +
          '<span class="lp-item-desc">' + esc(t('limpeza.item.' + item.id + '.desc')) + '</span>' +
        '</span>' +
        '<span class="lp-item-medida">' +
          '<strong class="lp-tamanho" id="lp-tam-' + item.id + '"></strong>' +
          '<span class="lp-arquivos" id="lp-arq-' + item.id + '"></span>' +
        '</span>';
      var chk = el.querySelector('input');
      chk.checked = !!estado.marcados[item.id];
      chk.addEventListener('change', function () {
        estado.marcados[item.id] = chk.checked;
        el.classList.toggle('lp-item-marcado', chk.checked);
        pintarResumo();
      });
      el.classList.toggle('lp-item-marcado', chk.checked);
      raiz.appendChild(el);
    });
  }

  /* ---------------- pintura ---------------- */

  function selecionados() {
    return ITENS.filter(function (i) { return estado.marcados[i.id]; }).map(function (i) { return i.id; });
  }

  function pintarMedidas() {
    ITENS.forEach(function (item) {
      var tam = document.getElementById('lp-tam-' + item.id);
      var arq = document.getElementById('lp-arq-' + item.id);
      if (!tam || !arq) { return; }
      var m = estado.medidas && estado.medidas[item.id];
      if (!m) {
        tam.textContent = estado.fase === 'scan' || !estado.medidas ? t('limpeza.medindo') : '—';
        arq.textContent = '';
        return;
      }
      tam.textContent = tamanho(m.bytes);
      arq.textContent = Number(m.arquivos) === 1 ? t('limpeza.arquivos1') : t('limpeza.arquivos', { n: inteiro(m.arquivos) });
    });
  }

  function pintarResumo() {
    var ids = selecionados();
    var bytes = 0, arquivos = 0;
    ids.forEach(function (id) {
      var m = estado.medidas && estado.medidas[id];
      if (m) { bytes += Number(m.bytes) || 0; arquivos += Number(m.arquivos) || 0; }
    });
    var total = document.getElementById('lp-total');
    if (total) { total.textContent = estado.medidas ? tamanho(bytes) : '…'; }
    var sub = document.getElementById('lp-resumo-sub');
    if (sub) {
      sub.textContent = estado.erro ? t('limpeza.erro.scan', { msg: estado.erro })
        : t('limpeza.resumo', { itens: ids.length, total: ITENS.length, arquivos: inteiro(arquivos) });
      sub.classList.toggle('lp-erro', !!estado.erro);
    }
    var ultima = document.getElementById('lp-ultima');
    if (ultima) {
      var s = estado.settings || {};
      ultima.textContent = s.lastCleanup
        ? t('limpeza.ultima', { quando: dataHora(s.lastCleanup), tamanho: tamanho(s.lastCleanupFreed) })
        : t('limpeza.nunca');
    }
    var analisarBtn = document.getElementById('lp-analisar');
    if (analisarBtn) {
      analisarBtn.disabled = estado.ocupado;
      analisarBtn.textContent = t(estado.fase === 'scan' ? 'limpeza.analisando' : 'limpeza.analisar');
    }
    var limparBtn = document.getElementById('lp-limpar');
    if (limparBtn) {
      limparBtn.disabled = estado.ocupado || !estado.medidas || ids.length === 0;
      limparBtn.textContent = t(estado.fase === 'run' ? 'limpeza.limpando' : 'limpeza.limpar');
    }
  }

  function pintarResultado() {
    var el = document.getElementById('lp-resultado');
    if (!el) { return; }
    var r = estado.resultado;
    if (!r) { el.hidden = true; el.innerHTML = ''; return; }
    var linhas = '';
    var porItem = r.porItem || {};
    Object.keys(porItem).forEach(function (id) {
      linhas += '<li><span>' + esc(t('limpeza.item.' + id)) + '</span><strong>' + esc(tamanho(porItem[id])) + '</strong></li>';
    });
    el.innerHTML =
      '<strong class="lp-resultado-titulo">' + esc(t('limpeza.resultado.titulo')) + '</strong>' +
      '<span class="lp-resultado-liberado" id="lp-liberado">' + esc(t('limpeza.resultado.liberado', { tamanho: tamanho(r.liberado) })) + '</span>' +
      (Number(r.pulados) > 0 ? '<span class="lp-resultado-pulados">' + esc(t('limpeza.resultado.pulados', { n: inteiro(r.pulados) })) + '</span>' : '') +
      (linhas ? '<ul class="lp-resultado-lista">' + linhas + '</ul>' : '');
    el.hidden = false;
  }

  function pintarTudo() {
    if (!estado.montado) { return; }
    pintarMedidas();
    pintarResumo();
    pintarResultado();
  }

  /* ---------------- ações ---------------- */

  function carregarSettings() {
    return tmx.bridge.call('settings.get').then(function (s) { estado.settings = s || {}; })
      .catch(function () { estado.settings = estado.settings || {}; })
      .then(pintarResumo);
  }

  function analisar() {
    if (estado.ocupado) { return Promise.resolve(); }
    estado.ocupado = true;
    estado.fase = 'scan';
    estado.erro = null;
    pintarTudo();
    return chamarJob('cleanup.scan', null).then(function (r) {
      var medidas = {};
      ((r && r.itens) || []).forEach(function (i) { medidas[i.id] = { bytes: i.bytes, arquivos: i.arquivos }; });
      estado.medidas = medidas;
    }).catch(function (e) {
      estado.erro = e.message;
      estado.medidas = estado.medidas || {};
      throw e;
    }).then(function () {
      estado.ocupado = false;
      estado.fase = null;
      pintarTudo();
    }, function (e) {
      estado.ocupado = false;
      estado.fase = null;
      pintarTudo();
      throw e;
    });
  }

  function confirmar() {
    var ids = selecionados();
    if (!ids.length) { tmx.toast(t('limpeza.nadaSelecionado'), 'aviso'); return; }
    var bytes = 0;
    var lista = ids.map(function (id) {
      var m = estado.medidas && estado.medidas[id];
      if (m) { bytes += Number(m.bytes) || 0; }
      return '<li><span>' + esc(t('limpeza.item.' + id)) + '</span><strong>' + esc(m ? tamanho(m.bytes) : '—') + '</strong></li>';
    }).join('');
    var avisos = '';
    if (ids.indexOf('lixeira') >= 0) { avisos += '<p class="lp-aviso lp-aviso-perigoso">' + esc(t('limpeza.confirmar.aviso.lixeira')) + '</p>'; }
    if (ids.indexOf('prefetch') >= 0) { avisos += '<p class="lp-aviso">' + esc(t('limpeza.confirmar.aviso.prefetch')) + '</p>'; }
    var perigoso = ids.indexOf('lixeira') >= 0;

    tmx.modal.open({
      titulo: t('limpeza.confirmar.titulo', { n: ids.length }),
      html: '<p>' + esc(t('limpeza.confirmar.texto', { tamanho: tamanho(bytes) })) + '</p>' +
            '<ul class="lp-confirmar-lista">' + lista + '</ul>' + avisos,
      botoes: [
        { rotulo: t('limpeza.confirmar.botao'), classe: perigoso ? 'btn-danger lp-confirmar' : 'btn-primary lp-confirmar', onClick: function () { executar(ids); } },
        { rotulo: t('shell.cancelar') }
      ]
    });
  }

  function executar(ids) {
    if (estado.ocupado) { return; }
    estado.ocupado = true;
    estado.fase = 'run';
    estado.resultado = null;
    pintarTudo();
    chamarJob('cleanup.run', { ids: ids }).then(function (r) {
      estado.resultado = r || { liberado: 0, porItem: {}, pulados: 0 };
      tmx.toast(t('limpeza.resultado.liberado', { tamanho: tamanho(estado.resultado.liberado) }), 'ok');
    }).catch(function (e) {
      tmx.toast(e.message, 'erro');
    }).then(function () {
      estado.ocupado = false;
      estado.fase = null;
      pintarTudo();
      // Remede e relê lastCleanup: o back-end já gravou os dois.
      return carregarSettings().then(function () { return analisar(); }).catch(function () { });
    });
  }

  var globaisLigados = false;

  window.tmxTabs.limpeza = {
    init: function () {
      if (!globaisLigados) {
        globaisLigados = true;
        document.addEventListener('tmx:lang', function () {
          if (!estado.montado) { return; }
          tmx.i18n.apply(document.getElementById('tab-limpeza'));
          montarItens();
          pintarTudo();
        });
      }
      montar();
      pintarTudo();
      return carregarSettings().then(function () { return analisar(); });
    }
  };
})();
