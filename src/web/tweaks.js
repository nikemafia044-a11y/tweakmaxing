/* tweaks.js - aba "Ajustes".
 *
 * Catálogo com selos de evidência, preset, prévia antes->depois, aplicação e
 * reversão (por item e por sessão).
 *
 * Ações da ponte usadas aqui:
 *   catalog.get / preset.apply / plan.preview / runs.list  -> assíncronas
 *   plan.apply / plan.applyToggle / undo.tweak / undo.run   -> síncronas que
 *       validam (sessão, consentimento, ids) e SÓ ENTÃO disparam o job; a
 *       resposta imediata traz { jobId } e o resultado chega em job.done.
 *   plan.setSelection / plan.setConsent / plan.setOption / undo.command
 *       -> síncronas, mexem apenas no plano em memória.
 *
 * Nada de texto do catálogo entra em innerHTML sem passar por esc().
 */
(function () {
  'use strict';
  window.tmxTabs = window.tmxTabs || {};

  var estado = {
    dados: null,      // payload de catalog.get
    preset: 'desktop',
    busca: '',
    acoes: {},        // id -> { texto, classe } (resultado da última ação)
    ocupado: false
  };

  // Pendências de consentimento do modal de prévia aberto no momento. Fica no
  // escopo do módulo porque o ouvinte de #modal-body é instalado UMA vez: o
  // elemento sobrevive a todo modal.open(), e um addEventListener por abertura
  // acumularia ouvintes que disparariam de novo no modal seguinte.
  var pendentesConsentimento = [];

  var PRESETS = [
    { id: 'desktop', rotulo: 'Desktop' },
    { id: 'notebook', rotulo: 'Notebook' },
    { id: 'minimo', rotulo: 'Mínimo' }
  ];

  var AVISO_FOLCLORE = 'Sem evidência de ganho. Desmarcado por padrão.';

  var ROTULO_STATUS = {
    aplicado: 'aplicado',
    aplicadoNaoVerificado: 'aplicado (não verificado)',
    jaAplicado: 'já aplicado',
    falha: 'falha',
    naoAplicavel: 'não aplicável',
    naoSuportado: 'não suportado',
    semConsentimento: 'sem consentimento',
    simulado: 'simulado',
    revertido: 'revertido'
  };

  /* ---------------- texto ---------------- */

  function esc(s) {
    return String(s === null || s === undefined ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }

  function classeStatus(status) {
    if (status === 'aplicado' || status === 'aplicadoNaoVerificado' || status === 'jaAplicado') { return 'estado-ok'; }
    if (status === 'revertido') { return 'estado-undo'; }
    if (status === 'falha') { return 'estado-falha'; }
    return 'estado-pulado';
  }

  function copiarTexto(texto) {
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
    tmx.toast(ok ? 'Comando copiado' : 'Não foi possível copiar', ok ? 'ok' : 'erro');
  }

  /* ---------------- ponte: jobs ---------------- */

  /* Dispara uma ação que roda no pool e resolve com o resultado do job.done
     correspondente (correlacionado pelo jobId, porque a ponte não amarra id de
     pedido a evento). onProgresso recebe { pct, status }. */
  function chamarJob(nome, payload, onProgresso) {
    // callComEspera: o slot de job pode estar com uma carga de outra aba ou
    // com um lote de icones; a acao do usuario espera em vez de falhar.
    return tmx.bridge.callComEspera(nome, payload).then(function (resp) {
      var jobId = resp && resp.jobId;
      if (!jobId) { return resp; }
      return new Promise(function (resolve, reject) {
        var aoProgredir = tmx.bridge.on('job.progress', function (p) {
          if (!p || p.jobId !== jobId) { return; }
          if (typeof onProgresso === 'function') { onProgresso(p); }
        });
        var aoTerminar = tmx.bridge.on('job.done', function (p) {
          if (!p || p.jobId !== jobId) { return; }
          tmx.bridge.off('job.progress', aoProgredir);
          tmx.bridge.off('job.done', aoTerminar);
          if (p.ok) { resolve(p.result); }
          else { reject(new Error((p.error && p.error.message) || 'o trabalho falhou')); }
        });
      });
    });
  }

  /* ---------------- coleta de itens ---------------- */

  function todosItens() {
    var fora = [];
    var cats = (estado.dados && estado.dados.categorias) || [];
    for (var i = 0; i < cats.length; i++) {
      for (var j = 0; j < cats[i].itens.length; j++) { fora.push(cats[i].itens[j]); }
    }
    return fora;
  }

  function acharItem(id) {
    var todos = todosItens();
    for (var i = 0; i < todos.length; i++) { if (todos[i].id === id) { return todos[i]; } }
    return null;
  }

  function idsSelecionados() {
    return todosItens().filter(function (t) { return t.selecionado; }).map(function (t) { return t.id; });
  }

  /* ---------------- esqueleto ---------------- */

  function montarEsqueleto() {
    var raiz = document.getElementById('tab-ajustes');
    var botoesPreset = PRESETS.map(function (p) {
      return '<button type="button" class="tw-preset" id="tw-preset-' + p.id + '" data-preset="' + p.id +
             '" aria-pressed="false">' + esc(p.rotulo) + '</button>';
    }).join('');

    raiz.innerHTML =
      '<h2>Ajustes</h2>' +
      '<div class="tw-topo">' +
        '<div class="tw-presets" role="group" aria-label="Preset de ajustes">' + botoesPreset + '</div>' +
        '<input type="search" id="tw-busca" placeholder="Buscar por nome, descrição ou ID" ' +
          'aria-label="Buscar ajuste por nome, descrição ou ID">' +
        '<button type="button" class="btn btn-mini" id="tw-limpar">Limpar seleção</button>' +
        '<span id="tw-contadores" aria-live="polite">—</span>' +
      '</div>' +
      '<p class="tw-legenda">' +
        '<span><span class="selo selo-medido">MEDIDO</span>efeito verificável e medido</span>' +
        '<span><span class="selo selo-tecnico">TÉCNICO</span>fundamento técnico documentado</span>' +
        '<span><span class="selo selo-folclore">FOLCLORE</span>sem evidência: nunca entra em preset</span>' +
        '<span><span class="selo selo-parcial">Parcial</span>reversão incompleta</span>' +
        '<span><span class="selo selo-irreversivel">Irreversível</span>não tem volta</span>' +
        '<span><span class="selo selo-reboot">Reinício</span>exige reiniciar</span>' +
      '</p>' +
      '<div id="tw-categorias"><p class="vazio">Lendo o catálogo e o estado atual do sistema…</p></div>' +
      '<div class="tw-rodape">' +
        '<button type="button" class="btn btn-primary" id="tw-aplicar" disabled>' +
          'Aplicar selecionados (<span id="tw-n">0</span>)</button>' +
        '<button type="button" class="btn btn-danger" id="tw-undo-sessao">Desfazer tudo desta sessão</button>' +
        '<button type="button" class="btn" id="tw-historico">Histórico</button>' +
        '<span class="tw-nota">Nada é aplicado sem sessão aberta (pasta da execução + ponto de restauração).</span>' +
      '</div>';

    document.getElementById('tw-busca').addEventListener('input', function (e) {
      estado.busca = String(e.target.value || '').toLowerCase();
      filtrar();
    });
    document.getElementById('tw-limpar').addEventListener('click', limparSelecao);
    document.getElementById('tw-aplicar').addEventListener('click', function () {
      iniciarAplicacao(idsSelecionados());
    });
    document.getElementById('tw-undo-sessao').addEventListener('click', confirmarUndoSessao);
    document.getElementById('tw-historico').addEventListener('click', abrirHistorico);

    PRESETS.forEach(function (p) {
      document.getElementById('tw-preset-' + p.id).addEventListener('click', function () { trocarPreset(p.id); });
    });

    var lista = document.getElementById('tw-categorias');
    lista.addEventListener('click', aoClicarNaLista);
    lista.addEventListener('change', aoMudarNaLista);
  }

  /* ---------------- desenho da lista ---------------- */

  var ROTULO_RISCO = { baixo: 'Risco baixo', medio: 'Risco médio', alto: 'Risco alto' };

  function selosDe(t) {
    var html = '';
    if (t.tier === 'MEDIDO') { html += '<span class="selo selo-medido">MEDIDO</span>'; }
    else if (t.tier === 'TECNICO') { html += '<span class="selo selo-tecnico">TÉCNICO</span>'; }
    else if (t.tier === 'FOLCLORE') { html += '<span class="selo selo-folclore">FOLCLORE</span>'; }

    html += '<span class="selo selo-risco-' + esc(t.risco || 'baixo') + '">' +
            esc(ROTULO_RISCO[t.risco] || ('Risco ' + t.risco)) + '</span>';

    if (t.reversivel === 'nenhuma') { html += '<span class="selo selo-irreversivel">Irreversível</span>'; }
    else if (t.reversivel === 'parcial') { html += '<span class="selo selo-parcial">Parcial</span>'; }
    else { html += '<span class="selo selo-reversivel">Reversível</span>'; }

    if (t.requerReboot) { html += '<span class="selo selo-reboot">Reinício</span>'; }
    return html;
  }

  /* Blocos de "por quê" / evidência / folclore, reusados tanto no <details>
     compacto de cada cartão quanto no modal de detalhes (abrirDetalhes). */
  function blocosPorQueEvidencia(t) {
    var html = '<div class="tw-bloco"><h4>Por quê</h4><p>' + esc(t.porque) + '</p></div>' +
               '<div class="tw-bloco"><h4>Evidência</h4><p>' + esc(t.evidencia) + '</p></div>';
    if (t.folclore) {
      html += '<div class="tw-consentimento">' +
                '<h4>Por que está na seção anti-folclore</h4>' +
                '<div class="tw-bloco"><h4>O que é</h4><p>' + esc(t.folclore.oQueE) + '</p></div>' +
                '<div class="tw-bloco"><h4>Por que circula</h4><p>' + esc(t.folclore.porqueCircula) + '</p></div>' +
                '<div class="tw-bloco"><h4>Por que não recomendamos</h4><p>' +
                  esc(t.folclore.porqueNaoRecomendamos) + '</p></div>' +
              '</div>';
    }
    return html;
  }

  function controleDe(t) {
    var motivos = esc((t.motivos || []).join(' · '));
    var idAttr = 'tw-' + esc(t.id);
    var desabilitado = t.alternavel ? '' : ' disabled';

    if (t.controle === 'toggle') {
      return '<button type="button" class="tw-switch" id="' + idAttr + '" role="switch" data-acao="toggle" ' +
             'aria-checked="' + (t.estadoAtual === true ? 'true' : 'false') + '" ' +
             'aria-label="' + esc(t.nome) + '" title="' + motivos + '"' + desabilitado + '></button>';
    }
    if (t.controle === 'radio') {
      return '<input type="radio" id="' + idAttr + '" name="tw-grupo-' + esc(t.grupo || t.categoria) + '" ' +
             'data-acao="radio" aria-label="' + esc(t.nome) + '" title="' + motivos + '"' +
             (t.estadoAtual === true ? ' checked' : '') + desabilitado + '>';
    }
    if (t.controle === 'combobox' || t.controle === 'button' || t.controle === 'info') {
      return '';
    }
    return '<input type="checkbox" id="' + idAttr + '" data-acao="selecao" aria-label="' + esc(t.nome) + '" ' +
           'title="' + motivos + '"' + (t.selecionado ? ' checked' : '') + desabilitado + '>';
  }

  function acoesDe(t) {
    var html = '';
    var chip = estado.acoes[t.id];
    if (chip) {
      html += '<span class="estado ' + chip.classe + '">' + esc(chip.texto) + '</span>';
    }

    if (t.controle === 'combobox') {
      var opcoes = (t.opcoes || []).map(function (o) {
        return '<option value="' + esc(o.valor) + '"' + (o.valor === t.opcaoSelecionada ? ' selected' : '') + '>' +
               esc(o.rotulo) + '</option>';
      }).join('');
      html += '<select class="tw-opcoes" id="tw-' + esc(t.id) + '" data-acao="opcao" aria-label="Opção de ' +
              esc(t.nome) + '"><option value="">Escolha…</option>' + opcoes + '</select>' +
              '<button type="button" class="btn btn-mini" data-acao="aplicar-item"' +
              (t.alternavel ? '' : ' disabled') + '>Aplicar</button>';
    } else if (t.controle === 'button') {
      html += '<button type="button" class="btn btn-mini" id="tw-' + esc(t.id) + '" data-acao="aplicar-item"' +
              (t.alternavel ? '' : ' disabled') + '>Executar</button>';
    }

    html += '<button type="button" class="btn btn-mini tw-undo" data-acao="undo"' + (t.temUndo ? '' : ' disabled') +
            ' aria-label="Desfazer ' + esc(t.nome) + '">Desfazer</button>';
    html += '<button type="button" class="btn btn-mini tw-info" data-acao="info" aria-label="Detalhes de ' +
            esc(t.nome) + '" title="Detalhes, evidência e origem">?</button>';
    return html;
  }

  function itemHtml(t) {
    var classes = ['tweak'];
    var titulo = '';
    if (t.tier === 'FOLCLORE') { classes.push('tw-folclore'); titulo = AVISO_FOLCLORE; }
    if (t.status === 'bloqueado') { classes.push('tw-bloqueado'); }

    var semRotulo = (t.controle === 'combobox' || t.controle === 'button' || t.controle === 'info');
    var rotulo = semRotulo
      ? '<span class="tw-nome">' + esc(t.nome) + '</span>'
      : '<label class="tw-nome" for="tw-' + esc(t.id) + '">' + esc(t.nome) + '</label>';

    var extra = '';
    var motivo = (t.tier === 'FOLCLORE') ? AVISO_FOLCLORE : ((t.status === 'bloqueado') ? (t.motivos || []).join(' · ') : '');
    if (motivo) { extra += '<p class="tw-motivo">' + esc(motivo) + '</p>'; }
    if (t.controle === 'info' && t.instrucoes) {
      extra += '<p class="tw-desc">' + esc(t.instrucoes) + '</p>';
    }

    // Cartão compacto e didático: linha 1 = controle + nome + ações; linha 2 =
    // descrição (uma linha, com reticências — texto completo no title); linha
    // 3 = selos (evidência, risco, reversibilidade, reinício); e um <details>
    // "Saiba mais" com os blocos de por-quê/evidência/folclore (mesmo builder
    // usado no modal de abrirDetalhes, sem duplicar texto).
    return '<div class="' + classes.join(' ') + '" data-id="' + esc(t.id) + '"' +
             (titulo ? ' title="' + esc(titulo) + '"' : '') + '>' +
             '<div class="tw-cabecalho">' +
               '<span class="tw-controle">' + controleDe(t) + '</span>' +
               rotulo + '<span class="tw-id">' + esc(t.id) + '</span>' +
               '<span class="tw-acoes">' + acoesDe(t) + '</span>' +
             '</div>' +
             '<p class="tw-desc tw-desc-principal" title="' + esc(t.descricao) + '">' + esc(t.descricao) + '</p>' + extra +
             '<div class="tw-badges">' + selosDe(t) + '</div>' +
             '<details class="tw-mais"><summary>Saiba mais</summary>' + blocosPorQueEvidencia(t) + '</details>' +
           '</div>';
  }

  function render() {
    var alvo = document.getElementById('tw-categorias');
    var cats = (estado.dados && estado.dados.categorias) || [];
    if (!cats.length) {
      alvo.innerHTML = '<p class="vazio">Nenhum ajuste no catálogo.</p>';
      return;
    }

    alvo.innerHTML = cats.map(function (c) {
      return '<details class="tw-cat" open>' +
               '<summary>' + esc(c.nome) +
                 '<span class="tw-cat-conta">' + c.itens.length + ' ajuste(s)</span></summary>' +
               '<div class="tw-lista">' + c.itens.map(itemHtml).join('') + '</div>' +
             '</details>';
    }).join('');

    PRESETS.forEach(function (p) {
      var b = document.getElementById('tw-preset-' + p.id);
      if (b) { b.setAttribute('aria-pressed', p.id === estado.preset ? 'true' : 'false'); }
    });

    atualizarContadores();
    filtrar();
  }

  function atualizarContadores() {
    var resumo = (estado.dados && estado.dados.resumo) || {};
    var n = idsSelecionados().length;
    var cont = document.getElementById('tw-contadores');
    if (cont) {
      cont.textContent = n + ' selecionados · ' + (resumo.planejados || 0) + ' planejados · ' +
                         (resumo.folclore || 0) + ' folclore';
    }
    var span = document.getElementById('tw-n');
    if (span) { span.textContent = String(n); }
    var botao = document.getElementById('tw-aplicar');
    if (botao) { botao.disabled = (n === 0) || estado.ocupado; }
  }

  function filtrar() {
    var termo = estado.busca;
    var cats = document.querySelectorAll('#tw-categorias details.tw-cat');
    for (var i = 0; i < cats.length; i++) {
      var linhas = cats[i].querySelectorAll('.tweak');
      var visiveis = 0;
      for (var j = 0; j < linhas.length; j++) {
        var t = acharItem(linhas[j].getAttribute('data-id'));
        var casa = !termo || !t || (
          (t.nome || '').toLowerCase().indexOf(termo) >= 0 ||
          (t.descricao || '').toLowerCase().indexOf(termo) >= 0 ||
          (t.id || '').toLowerCase().indexOf(termo) >= 0);
        linhas[j].hidden = !casa;
        if (casa) { visiveis++; }
      }
      cats[i].hidden = (visiveis === 0);
    }
  }

  /* ---------------- carregamento ---------------- */

  function ocupar(valor) {
    estado.ocupado = !!valor;
    var secao = document.getElementById('tab-ajustes');
    if (secao) { secao.setAttribute('aria-busy', valor ? 'true' : 'false'); }
    ['tw-limpar', 'tw-undo-sessao', 'tw-historico'].forEach(function (id) {
      var b = document.getElementById(id);
      if (b) { b.disabled = !!valor; }
    });
    PRESETS.forEach(function (p) {
      var b = document.getElementById('tw-preset-' + p.id);
      if (b) { b.disabled = !!valor; }
    });
    atualizarContadores();
  }

  function aplicarPayload(payload) {
    if (!payload) { return; }
    estado.dados = payload;
    estado.preset = payload.preset || estado.preset;
    render();
  }

  function carregar(preset) {
    ocupar(true);
    return chamarJob('catalog.get', { preset: preset || estado.preset }).then(function (r) {
      aplicarPayload(r);
      ocupar(false);
    }).catch(function (e) {
      ocupar(false);
      document.getElementById('tw-categorias').innerHTML =
        '<p class="vazio">Não foi possível ler o catálogo: ' + esc(e.message) + '</p>';
      tmx.toast('Catálogo: ' + e.message, 'erro');
      // Repropaga: a mensagem inline acima (e o toast) já avisaram o
      // usuário, mas tabs.show precisa SABER que a carga falhou para
      // deixar a aba como não iniciada e tentar de novo na próxima
      // abertura. Engolir o erro aqui deixava a aba vazia para sempre.
      throw e;
    });
  }

  function trocarPreset(preset) {
    if (estado.ocupado) { return; }
    ocupar(true);
    chamarJob('preset.apply', { preset: preset }).then(function (r) {
      aplicarPayload(r);
      ocupar(false);
      tmx.toast('Preset ' + preset + ' aplicado à seleção', 'ok');
    }).catch(function (e) {
      ocupar(false);
      tmx.toast('Preset: ' + e.message, 'erro');
    });
  }

  function limparSelecao() {
    var ids = idsSelecionados();
    if (!ids.length) { return; }
    ocupar(true);
    Promise.all(ids.map(function (id) {
      return tmx.bridge.call('plan.setSelection', { id: id, selecionado: false }).then(function (r) {
        var t = acharItem(id);
        if (t && r && r.ok) { t.selecionado = false; }
        if (r && r.resumo && estado.dados) { estado.dados.resumo = r.resumo; }
      }).catch(function () { });
    })).then(function () {
      ocupar(false);
      render();
    });
  }

  /* ---------------- eventos da lista ---------------- */

  function linhaDe(el) {
    while (el && el !== document) {
      if (el.classList && el.classList.contains('tweak')) { return el; }
      el = el.parentNode;
    }
    return null;
  }

  function aoMudarNaLista(ev) {
    var alvo = ev.target;
    var acao = alvo.getAttribute && alvo.getAttribute('data-acao');
    var linha = linhaDe(alvo);
    if (!linha || !acao) { return; }
    var id = linha.getAttribute('data-id');

    if (acao === 'selecao') {
      var marcado = !!alvo.checked;
      tmx.bridge.call('plan.setSelection', { id: id, selecionado: marcado }).then(function (r) {
        if (!r || !r.ok) {
          alvo.checked = !marcado;
          tmx.toast((r && r.mensagem) || 'não foi possível alterar a seleção', 'aviso');
          return;
        }
        var t = acharItem(id);
        if (t) { t.selecionado = marcado; }
        if (r.resumo && estado.dados) { estado.dados.resumo = r.resumo; }
        atualizarContadores();
      }).catch(function (e) {
        alvo.checked = !marcado;
        tmx.toast(e.message, 'erro');
      });
      return;
    }

    if (acao === 'opcao') {
      var valor = alvo.value;
      if (!valor) { return; }
      tmx.bridge.call('plan.setOption', { id: id, valor: valor }).then(function (r) {
        if (!r || !r.ok) { tmx.toast((r && r.mensagem) || 'opção inválida', 'aviso'); return; }
        var t = acharItem(id);
        if (t) { t.opcaoSelecionada = valor; }
      }).catch(function (e) { tmx.toast(e.message, 'erro'); });
      return;
    }

    if (acao === 'radio') { aplicarItemUnico(id); }
  }

  function aoClicarNaLista(ev) {
    var alvo = ev.target;
    var acao = alvo.getAttribute && alvo.getAttribute('data-acao');
    var linha = linhaDe(alvo);
    if (!linha || !acao) { return; }
    var id = linha.getAttribute('data-id');

    if (acao === 'info') { abrirDetalhes(id); return; }
    if (acao === 'undo') { desfazerItem(id); return; }
    if (acao === 'aplicar-item') { aplicarItemUnico(id); return; }
    if (acao === 'toggle') { alternarToggle(id, alvo); }
  }

  /* ---------------- detalhes de um ajuste ---------------- */

  function abrirDetalhes(id) {
    var t = acharItem(id);
    if (!t) { return; }

    var html = '<p class="tw-titulo">' + selosDe(t) + '</p>' +
               '<div class="tw-bloco"><h4>O que faz</h4><p>' + esc(t.descricao) + '</p></div>' +
               blocosPorQueEvidencia(t);

    if (t.instrucoes) {
      html += '<div class="tw-bloco"><h4>Instruções</h4><p>' + esc(t.instrucoes) + '</p></div>';
    }
    if ((t.motivos || []).length) {
      html += '<div class="tw-bloco"><h4>Situação</h4><p>' + esc(t.motivos.join(' · ')) + '</p></div>';
    }
    html += '<div class="tw-bloco"><h4>Estado atual</h4><p>' +
            (t.estadoAtual === true ? 'aplicado' : (t.estadoAtual === false ? 'não aplicado' : 'não verificado')) +
            '</p></div>';

    var botoes = [{ rotulo: 'Fechar' }];
    if (t.origem && t.origem.link) {
      botoes.unshift({
        rotulo: 'Abrir a origem',
        mantemAberto: true,
        onClick: function () {
          tmx.bridge.call('shell.openUrl', { url: t.origem.link }).catch(function (e) {
            tmx.toast(e.message, 'erro');
          });
        }
      });
    }

    tmx.modal.open({ titulo: t.nome + ' (' + t.id + ')', html: html, botoes: botoes });
  }

  /* ---------------- aplicação ---------------- */

  function aplicarItemUnico(id) {
    var t = acharItem(id);
    if (!t) { return; }
    if (t.controle === 'combobox' && !t.opcaoSelecionada) {
      tmx.toast('Escolha uma opção antes de aplicar', 'aviso');
      return;
    }
    tmx.bridge.call('plan.setSelection', { id: id, selecionado: true }).then(function (r) {
      if (r && r.ok) { t.selecionado = true; }
      iniciarAplicacao([id]);
    }).catch(function (e) { tmx.toast(e.message, 'erro'); });
  }

  function alternarToggle(id, botao) {
    var ligar = botao.getAttribute('aria-checked') !== 'true';
    tmx.session.ensure().then(function (ok) {
      if (!ok) { return null; }
      ocupar(true);
      return chamarJob('plan.applyToggle', { id: id, ligado: ligar }).then(function (r) {
        ocupar(false);
        var linha = (r && r.resultado && r.resultado.itens && r.resultado.itens[0]) || null;
        if (linha) {
          estado.acoes[id] = { texto: ROTULO_STATUS[linha.status] || linha.status, classe: classeStatus(linha.status) };
        }
        if (r && r.catalogo) { aplicarPayload(r.catalogo); }
        tmx.toast(id + (ligar ? ' ligado' : ' desligado'), 'ok');
      });
    }).catch(function (e) {
      ocupar(false);
      tmx.toast(e.message, 'erro');
    });
  }

  function tabelaPrevia(itens) {
    var html = '<table class="tw-tabela"><thead><tr>' +
               '<th>Alvo</th><th>Antes</th><th>Depois</th><th>Reversão</th>' +
               '</tr></thead><tbody>';
    var atual = null;
    (itens || []).forEach(function (l) {
      if (l.tweakId !== atual) {
        atual = l.tweakId;
        html += '<tr class="tw-grupo"><td colspan="4">' + esc(l.nome) + ' (' + esc(l.tweakId) + ')</td></tr>';
      }
      html += '<tr>' +
                '<td class="tw-cel-mono">' + esc(l.alvo) + '</td>' +
                '<td class="tw-antes tw-cel-mono">' + esc(l.antes) + '</td>' +
                '<td class="tw-depois tw-cel-mono">' + esc(l.depois) + '</td>' +
                '<td>' + esc(l.reversao) + '</td>' +
              '</tr>';
    });
    return html + '</tbody></table>';
  }

  function blocoConsentimento(t) {
    return '<div class="tw-consentimento" data-consent="' + esc(t.id) + '">' +
             '<h4>' + esc((t.consentimento && t.consentimento.titulo) || ('Confirmação obrigatória: ' + t.nome)) + '</h4>' +
             '<p class="tw-tradeoff">' +
               esc((t.consentimento && t.consentimento.tradeoff) || 'Este ajuste não tem reversão automática.') + '</p>' +
             '<p>Para liberar, digite exatamente:</p>' +
             '<p class="tw-mono">' + esc(t.consentimento && t.consentimento.frase) + '</p>' +
             '<input type="text" class="campo" data-frase="' + esc(t.id) + '" autocomplete="off" spellcheck="false" ' +
               'aria-label="Frase de confirmação de ' + esc(t.nome) + '">' +
             '<p><button type="button" class="btn btn-mini" data-consent-ok="' + esc(t.id) + '">Confirmar frase</button></p>' +
           '</div>';
  }

  function iniciarAplicacao(ids) {
    if (!ids || !ids.length) { tmx.toast('Nenhum ajuste selecionado', 'aviso'); return; }
    tmx.session.ensure().then(function (ok) {
      if (!ok) { return null; }
      ocupar(true);
      return chamarJob('plan.preview', { ids: ids }).then(function (previa) {
        ocupar(false);
        abrirModalPrevia(ids, previa);
      });
    }).catch(function (e) {
      ocupar(false);
      tmx.toast('Prévia: ' + e.message, 'erro');
    });
  }

  function abrirModalPrevia(ids, previa) {
    previa = previa || { itens: [], faltaConsentimento: [] };
    pendentesConsentimento = (previa.faltaConsentimento || []).slice();

    var html = '<p>Confira o que será alterado. <strong>Antes</strong> é o valor lido agora; ' +
               '<strong>Depois</strong> é o valor que será gravado.</p>' +
               tabelaPrevia(previa.itens);

    pendentesConsentimento.forEach(function (id) {
      var t = acharItem(id);
      if (t) { html += blocoConsentimento(t); }
    });

    html += '<div class="tw-barra" id="tw-barra" hidden><span></span></div>' +
            '<p id="tw-progresso" class="sessao-progresso"></p>';

    tmx.modal.open({
      titulo: 'Prévia: antes → depois',
      html: html,
      botoes: [
        {
          rotulo: 'Confirmar e aplicar',
          classe: 'btn-primary',
          mantemAberto: true,
          onClick: function () { executarAplicacao(ids); }
        },
        { rotulo: 'Cancelar' }
      ]
    });

    revalidarConsentimento();
  }

  function revalidarConsentimento() {
    var b = document.querySelector('#modal-buttons .btn-primary');
    if (b) { b.disabled = pendentesConsentimento.length > 0; }
  }

  function confirmarFrase(id) {
    var corpo = document.getElementById('modal-body');
    var campo = corpo.querySelector('[data-frase="' + id + '"]');
    tmx.bridge.call('plan.setConsent', { id: id, frase: campo ? campo.value : '' }).then(function (r) {
      if (!r || !r.ok) { tmx.toast((r && r.mensagem) || 'frase incorreta', 'erro'); return; }
      var t = acharItem(id);
      if (t) { t.consentido = true; }
      var bloco = corpo.querySelector('[data-consent="' + id + '"]');
      if (bloco) { bloco.parentNode.removeChild(bloco); }
      pendentesConsentimento = pendentesConsentimento.filter(function (x) { return x !== id; });
      revalidarConsentimento();
      tmx.toast('Consentimento registrado para ' + id, 'ok');
    }).catch(function (e) { tmx.toast(e.message, 'erro'); });
  }

  /* Um unico ouvinte para o corpo do modal (ver pendentesConsentimento). */
  function ligarOuvinteModal() {
    var corpo = document.getElementById('modal-body');
    if (!corpo || corpo.getAttribute('data-tw-ligado') === '1') { return; }
    corpo.setAttribute('data-tw-ligado', '1');
    corpo.addEventListener('click', function (ev) {
      var alvo = ev.target;
      if (!alvo || !alvo.getAttribute) { return; }
      var idConsent = alvo.getAttribute('data-consent-ok');
      if (idConsent) { confirmarFrase(idConsent); return; }
      var runId = alvo.getAttribute('data-undo-run');
      if (runId) { confirmarUndoRun(runId); }
    });
  }

  function pintarProgresso(p) {
    var texto = document.getElementById('tw-progresso');
    var barra = document.getElementById('tw-barra');
    if (barra) {
      barra.hidden = false;
      var interno = barra.querySelector('span');
      if (interno && typeof p.pct === 'number') { interno.style.width = Math.max(0, Math.min(100, p.pct)) + '%'; }
    }
    if (texto) {
      texto.textContent = (p.status || 'Trabalhando…') + (typeof p.pct === 'number' ? ' (' + p.pct + '%)' : '');
    }
  }

  function travarModal() {
    var botoes = document.querySelectorAll('#modal-buttons button');
    for (var i = 0; i < botoes.length; i++) { botoes[i].disabled = true; }
  }

  function executarAplicacao(ids) {
    travarModal();
    pintarProgresso({ status: 'Aplicando…', pct: 0 });
    ocupar(true);

    chamarJob('plan.apply', { ids: ids }, pintarProgresso).then(function (r) {
      ocupar(false);
      var res = (r && r.resultado) || {};
      (res.itens || []).forEach(function (l) {
        estado.acoes[l.id] = { texto: ROTULO_STATUS[l.status] || l.status, classe: classeStatus(l.status) };
      });
      if (r && r.catalogo) { aplicarPayload(r.catalogo); }
      mostrarResultado(res);
    }).catch(function (e) {
      ocupar(false);
      tmx.modal.close();
      tmx.toast('Aplicação: ' + e.message, 'erro');
    });
  }

  function mostrarResultado(res) {
    var linhas = (res.itens || []).map(function (l) {
      var avisos = (l.avisos || []).join(' · ');
      return '<tr>' +
               '<td class="tw-cel-mono">' + esc(l.id) + '</td>' +
               '<td>' + esc(l.nome) + '</td>' +
               '<td><span class="estado ' + classeStatus(l.status) + '">' +
                 esc(ROTULO_STATUS[l.status] || l.status) + '</span></td>' +
               '<td>' + esc(l.detalhe) + (avisos ? '<br><em>' + esc(avisos) + '</em>' : '') + '</td>' +
             '</tr>';
    }).join('');

    var html = '<div id="tw-resultado">' +
                 '<p>' +
                   '<strong>' + (res.aplicados || 0) + '</strong> aplicados · ' +
                   '<strong>' + (res.jaAplicados || 0) + '</strong> já aplicados · ' +
                   '<strong>' + (res.falhas || 0) + '</strong> falhas · ' +
                   '<strong>' + (res.pulados || 0) + '</strong> pulados' +
                 '</p>' +
                 (res.requerReboot ? '<p class="tw-aviso-reboot">Reinicie o Windows para que todos os ajustes valham.</p>' : '') +
                 '<table class="tw-tabela"><thead><tr><th>ID</th><th>Ajuste</th><th>Status</th><th>Detalhe</th></tr></thead>' +
                 '<tbody>' + linhas + '</tbody></table>' +
               '</div>';

    tmx.modal.open({ titulo: 'Resultado da aplicação', html: html, botoes: [{ rotulo: 'Fechar' }] });
  }

  /* ---------------- reversão ---------------- */

  function desfazerItem(id) {
    ocupar(true);
    chamarJob('undo.tweak', { id: id }).then(function (r) {
      ocupar(false);
      var resumo = (r && r.resumo) || {};
      estado.acoes[id] = (resumo.revertidos > 0)
        ? { texto: 'revertido', classe: 'estado-undo' }
        : { texto: 'nada a reverter', classe: 'estado-pulado' };
      if (r && r.catalogo) { aplicarPayload(r.catalogo); }
      tmx.toast(id + ': ' + (resumo.revertidos || 0) + ' registro(s) revertido(s)', 'ok');
    }).catch(function (e) {
      ocupar(false);
      tmx.toast('Desfazer: ' + e.message, 'erro');
    });
  }

  function mostrarResumoUndo(titulo, resumo) {
    var linhas = ((resumo && resumo.itens) || []).map(function (l) {
      return '<tr>' +
               '<td class="tw-cel-mono">' + esc(l.tweakId) + '</td>' +
               '<td class="tw-cel-mono">' + esc(l.alvo) + '</td>' +
               '<td>' + esc(l.resultado) + '</td>' +
               '<td>' + esc(l.detalhe) + '</td>' +
             '</tr>';
    }).join('');

    tmx.modal.open({
      titulo: titulo,
      html: '<div id="tw-resultado"><p><strong>' + ((resumo && resumo.revertidos) || 0) + '</strong> revertidos · ' +
            '<strong>' + ((resumo && resumo.falhas) || 0) + '</strong> falhas · ' +
            '<strong>' + ((resumo && resumo.pulados) || 0) + '</strong> pulados</p>' +
            '<table class="tw-tabela"><thead><tr><th>Ajuste</th><th>Alvo</th><th>Resultado</th><th>Detalhe</th></tr></thead>' +
            '<tbody>' + linhas + '</tbody></table></div>',
      botoes: [{ rotulo: 'Fechar' }]
    });
  }

  function confirmarUndoSessao() {
    tmx.modal.open({
      titulo: 'Desfazer tudo desta sessão',
      html: '<p>Todos os ajustes aplicados nesta sessão voltam ao valor anterior, na ordem inversa da aplicação.</p>' +
            '<p class="sessao-progresso" id="tw-progresso"></p>',
      botoes: [
        {
          rotulo: 'Desfazer tudo',
          classe: 'btn-danger',
          mantemAberto: true,
          onClick: function () {
            travarModal();
            pintarProgresso({ status: 'Revertendo…', pct: 0 });
            ocupar(true);
            chamarJob('undo.run', {}, pintarProgresso).then(function (r) {
              ocupar(false);
              estado.acoes = {};
              ((r && r.resumo && r.resumo.itens) || []).forEach(function (l) {
                if (l.resultado === 'revertido') {
                  estado.acoes[l.tweakId] = { texto: 'revertido', classe: 'estado-undo' };
                }
              });
              if (r && r.catalogo) { aplicarPayload(r.catalogo); } else { render(); }
              mostrarResumoUndo('Reversão da sessão', r && r.resumo);
            }).catch(function (e) {
              ocupar(false);
              tmx.modal.close();
              tmx.toast('Desfazer tudo: ' + e.message, 'erro');
            });
          }
        },
        { rotulo: 'Cancelar' }
      ]
    });
  }

  /* ---------------- histórico ---------------- */

  function abrirHistorico() {
    ocupar(true);
    Promise.all([chamarJob('runs.list', {}), tmx.bridge.call('undo.command')]).then(function (rs) {
      ocupar(false);
      var execucoes = (rs[0] && rs[0].execucoes) || [];
      var comando = (rs[1] && rs[1].comando) || '';

      var linhas = execucoes.map(function (e) {
        return '<tr>' +
                 '<td class="tw-cel-mono">' + esc(e.runId) + (e.atual ? ' <span class="selo">atual</span>' : '') + '</td>' +
                 '<td>' + esc(String(e.criadoEm).replace('T', ' ').slice(0, 19)) + '</td>' +
                 '<td>' + e.registros + ' / ' + e.aplicados + ' / ' + e.revertidos + '</td>' +
                 '<td><button type="button" class="btn btn-mini" data-undo-run="' + esc(e.runId) + '">Desfazer</button></td>' +
               '</tr>';
      }).join('');

      var html = '<p>Cada execução guarda o valor anterior de tudo que tocou. ' +
                 'A contagem é registros / aplicados / revertidos.</p>' +
                 '<table class="tw-tabela"><thead><tr><th>Execução</th><th>Criada em</th>' +
                 '<th>Reg. / apl. / rev.</th><th></th></tr></thead><tbody>' +
                 (linhas || '<tr><td colspan="4">Nenhuma execução registrada.</td></tr>') +
                 '</tbody></table>';

      if (comando) {
        html += '<div class="tw-bloco"><h4>Reverter pelo terminal</h4>' +
                '<p class="tw-mono" id="tw-comando">' + esc(comando) + '</p>' +
                '<p><button type="button" class="btn btn-mini" id="tw-copiar-comando">Copiar comando</button></p></div>';
      }

      tmx.modal.open({ titulo: 'Histórico de execuções', html: html, botoes: [{ rotulo: 'Fechar' }] });

      var copiar = document.getElementById('tw-copiar-comando');
      if (copiar) { copiar.addEventListener('click', function () { copiarTexto(comando); }); }
      // O botão "Desfazer" de cada execução é tratado pelo ouvinte único de #modal-body.
    }).catch(function (e) {
      ocupar(false);
      tmx.toast('Histórico: ' + e.message, 'erro');
    });
  }

  function confirmarUndoRun(runId) {
    tmx.modal.open({
      titulo: 'Desfazer a execução ' + runId,
      html: '<p>Todos os registros dessa execução voltam ao valor anterior.</p>' +
            '<p class="sessao-progresso" id="tw-progresso"></p>',
      botoes: [
        {
          rotulo: 'Desfazer',
          classe: 'btn-danger',
          mantemAberto: true,
          onClick: function () {
            travarModal();
            pintarProgresso({ status: 'Revertendo…', pct: 0 });
            ocupar(true);
            chamarJob('undo.run', { runId: runId }, pintarProgresso).then(function (r) {
              ocupar(false);
              if (r && r.catalogo) { aplicarPayload(r.catalogo); }
              mostrarResumoUndo('Reversão de ' + runId, r && r.resumo);
            }).catch(function (e) {
              ocupar(false);
              tmx.modal.close();
              tmx.toast('Desfazer: ' + e.message, 'erro');
            });
          }
        },
        { rotulo: 'Cancelar' }
      ]
    });
  }

  /* ---------------- registro da aba ---------------- */

  window.tmxTabs.ajustes = {
    init: function () {
      montarEsqueleto();
      ligarOuvinteModal();
      // Devolve a Promise: tabs.show (ver app.js) só marca a aba como
      // iniciada quando o catálogo chega.
      return carregar();
    }
  };
})();
