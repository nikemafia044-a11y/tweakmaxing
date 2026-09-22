/* microwin.js - aba "MicroWin": gera uma ISO enxuta do Windows a partir de
 * uma ISO oficial. Não grava pendrive: o produto final é um arquivo .iso.
 *
 * Fluxo: microwin.check (pré-requisitos) -> microwin.pickIso -> microwin.info
 * (job, lê as edições) -> escolhas -> microwin.build (job com progresso).
 *
 * Tudo que entra em HTML passa por escapar(): nome e descrição dos aplicativos
 * vêm de src/config/appx.json, caminhos vêm do disco do usuário e mensagens de
 * erro vêm do PowerShell - nada disso é constante confiável deste arquivo.
 *
 * A senha nunca é guardada em estado nem registrada: sai do input direto para
 * a chamada da ponte.
 */
(function () {
  'use strict';
  window.tmxTabs = window.tmxTabs || {};

  /* Preset "recomendados": os mesmos aplicativos que o AppxDefault do WinUtil
     marca. src/config/preset.json não tem esse grupo, então a lista mora aqui,
     casada por pedaço do campo 'pacote' (ou do 'id', para o Dev Home, cujo
     pacote é Microsoft.Windows.DevHome). Calculadora, Bloco de Notas,
     Ferramenta de Captura e Paint ficam de fora de propósito. */
  var RECOMENDADOS = [
    'WindowsFeedbackHub', 'GetHelp', 'MicrosoftOfficeHub', 'Clipchamp',
    'WindowsAlarms', 'QuickAssist', 'WindowsSoundRecorder', 'MicrosoftStickyNotes',
    'Todos', 'MicrosoftSolitaireCollection', 'PowerAutomateDesktop', 'WindowsDevHome',
    'BingWeather', 'StartExperiencesApp', 'BingNews', 'Copilot', 'BingSearch'
  ];

  var RE_USUARIO = /^[A-Za-z][A-Za-z0-9_-]{0,19}$/;

  var estado = {
    apps: [],
    edicoes: [],
    prereq: null,
    ocupado: false
  };

  /* ---------------- texto ---------------- */

  function escapar(s) {
    return String(s === null || s === undefined ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }

  function el(id) { return document.getElementById(id); }

  function testMode() { return document.body.dataset.testmode === '1'; }

  /* ---------------- ponte: correlaciona job.done pelo jobId ---------------- */

  function chamarJob(nome, payload, aoProgredir) {
    return tmx.bridge.call(nome, payload).then(function (resp) {
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

  /* A ponte aceita um job por vez em todo o aplicativo: a leitura da ISO pode
     cair atrás de um features.list que já estava rodando. */
  function chamarJobComEspera(nome, payload, aoProgredir) {
    var limite = Date.now() + 90000;

    function tentar() {
      return chamarJob(nome, payload, aoProgredir).catch(function (e) {
        if (!/trabalho em andamento/i.test(e.message) || Date.now() > limite) { throw e; }
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
    el('mw-gerar').disabled = true;
    el('mw-ler').disabled = true;
    return true;
  }

  function liberar() {
    estado.ocupado = false;
    el('mw-gerar').disabled = false;
    el('mw-ler').disabled = false;
  }

  /* ---------------- pré-requisitos ---------------- */

  function itemPrereq(ok, texto, detalhe) {
    return '<div class="mw-pre-item ' + (ok ? 'mw-pre-ok' : 'mw-pre-nao') + '">' +
      '<span class="mw-pre-marca" aria-hidden="true">' + (ok ? '✓' : '✗') + '</span>' +
      '<span class="mw-pre-texto">' + escapar(texto) +
      (detalhe ? '<span class="mw-pre-detalhe">' + escapar(detalhe) + '</span>' : '') +
      '</span></div>';
  }

  function pintarPrereq(c) {
    c = c || {};
    estado.prereq = c;
    var caixa = el('mw-prereq');
    var html = '';

    html += itemPrereq(!!c.oscdimg, 'Windows ADK (oscdimg.exe)',
      c.oscdimg ? c.oscdimgPath : 'não encontrado - instale o ADK (Deployment Tools)');

    var espaco = (typeof c.espacoLivreGB === 'number' && c.espacoLivreGB >= 0)
      ? c.espacoLivreGB + ' GB livres'
      : 'espaço livre não medido';
    html += itemPrereq(!!c.espacoOk, 'Espaço em disco (mínimo ' + (c.espacoMinGB || 20) + ' GB)', espaco);

    html += itemPrereq(!!c.elevado || !!c.testMode, 'TweakMaxing como administrador',
      c.elevado ? 'sessão elevada' : (c.testMode ? 'modo de teste: verificação dispensada' : 'reabra como administrador'));

    if (!c.oscdimg) {
      html += '<button type="button" id="mw-adk" class="mw-adk">Abrir a página de download do Windows ADK</button>';
    }

    caixa.innerHTML = html;

    var botao = el('mw-adk');
    if (botao) {
      botao.addEventListener('click', function () {
        tmx.bridge.call('shell.openUrl', { url: c.urlAdk }).catch(function (e) {
          tmx.toast(e.message, 'erro');
        });
      });
    }
  }

  function carregarPrereq() {
    return tmx.bridge.call('microwin.check').then(pintarPrereq).catch(function (e) {
      el('mw-prereq').innerHTML = '<p class="mw-erro">' + escapar(e.message) + '</p>';
    });
  }

  /* ---------------- aplicativos ---------------- */

  function ehRecomendado(app) {
    var alvo = (String(app.pacote || '') + ' ' + String(app.id || '')).toLowerCase();
    for (var i = 0; i < RECOMENDADOS.length; i++) {
      if (alvo.indexOf(RECOMENDADOS[i].toLowerCase()) >= 0) { return true; }
    }
    return false;
  }

  function pintarApps() {
    var caixa = el('mw-apps');
    if (!estado.apps.length) {
      caixa.innerHTML = '<p class="vazio">Nenhum aplicativo no catálogo.</p>';
      return;
    }
    caixa.innerHTML = estado.apps.map(function (a, i) {
      var id = 'mw-app-' + i;
      return '<label class="mw-app" for="' + id + '" title="' + escapar(a.descricao) + '">' +
        '<input type="checkbox" id="' + id + '" data-pacote="' + escapar(a.pacote) + '">' +
        '<span><span class="mw-app-nome">' + escapar(a.nome) + '</span>' +
        '<span class="mw-app-pacote">' + escapar(a.pacote) + '</span></span>' +
        '</label>';
    }).join('');
    atualizarContagem();
  }

  function marcados() {
    var caixas = document.querySelectorAll('#mw-apps input[type=checkbox]');
    var fora = [];
    for (var i = 0; i < caixas.length; i++) {
      if (caixas[i].checked) { fora.push(caixas[i].getAttribute('data-pacote')); }
    }
    return fora;
  }

  function atualizarContagem() {
    el('mw-apps-contagem').textContent = marcados().length + ' de ' + estado.apps.length + ' marcados';
  }

  function carregarApps() {
    return tmx.bridge.call('microwin.apps').then(function (r) {
      estado.apps = (r && r.apps) || [];
      pintarApps();
    }).catch(function (e) {
      el('mw-apps').innerHTML = '<p class="mw-erro">' + escapar(e.message) + '</p>';
    });
  }

  function marcarRecomendados() {
    var caixas = document.querySelectorAll('#mw-apps input[type=checkbox]');
    for (var i = 0; i < caixas.length; i++) {
      if (ehRecomendado(estado.apps[i] || {})) { caixas[i].checked = true; }
    }
    atualizarContagem();
  }

  function limparApps() {
    var caixas = document.querySelectorAll('#mw-apps input[type=checkbox]');
    for (var i = 0; i < caixas.length; i++) { caixas[i].checked = false; }
    atualizarContagem();
  }

  /* ---------------- ISO e edições ---------------- */

  function escolherIso() {
    // No modo de teste o PowerShell não abre diálogo nativo (ele travaria a
    // thread da janela): devolve de volta o que já estiver digitado.
    return tmx.bridge.call('microwin.pickIso', { simular: el('mw-iso').value }).then(function (r) {
      if (r && r.caminho) {
        el('mw-iso').value = r.caminho;
        validarIso();
      }
    }).catch(function (e) { tmx.toast(e.message, 'erro'); });
  }

  function pintarEdicoes(lista) {
    estado.edicoes = lista || [];
    var sel = el('mw-edicao');
    if (!estado.edicoes.length) {
      sel.innerHTML = '<option value="">Leia a ISO primeiro</option>';
      sel.disabled = true;
      return;
    }
    sel.innerHTML = estado.edicoes.map(function (e) {
      var rotulo = e.nome + (e.arquitetura ? ' (' + e.arquitetura + ')' : '');
      return '<option value="' + escapar(e.index) + '">' + escapar(rotulo) + '</option>';
    }).join('');
    sel.disabled = false;
  }

  function lerIso() {
    if (!validarIso()) { return; }
    if (!ocupar()) { return; }

    el('mw-progresso').textContent = 'Lendo a ISO…';
    chamarJobComEspera('microwin.info', { iso: el('mw-iso').value.trim() }, function (p) {
      el('mw-progresso').textContent = (p.status || 'Lendo…') + (typeof p.pct === 'number' ? ' (' + p.pct + '%)' : '');
    }).then(function (r) {
      el('mw-progresso').textContent = '';
      if (!r || !r.ok) {
        pintarEdicoes([]);
        el('mw-iso-erro').textContent = (r && r.mensagem) || 'não foi possível ler a ISO';
        return;
      }
      el('mw-iso-erro').textContent = '';
      pintarEdicoes(r.edicoes);
      tmx.toast(r.edicoes.length + ' edição(ões) encontrada(s) — ' + r.tamanhoGB + ' GB', 'ok');
    }).catch(function (e) {
      el('mw-progresso').textContent = '';
      el('mw-iso-erro').textContent = e.message;
    }).then(liberar, liberar);
  }

  /* ---------------- validação ---------------- */

  function validarIso() {
    var v = el('mw-iso').value.trim();
    var erro = '';
    if (!v) { erro = 'escolha a ISO de origem'; }
    else if (!/\.iso$/i.test(v)) { erro = 'o arquivo precisa terminar em .iso'; }
    el('mw-iso-erro').textContent = erro;
    return !erro;
  }

  function validarUsuario() {
    var v = el('mw-usuario').value;
    var erro = '';
    if (!v) { erro = 'informe o nome de usuário'; }
    else if (!RE_USUARIO.test(v)) {
      erro = 'comece com letra e use até 20 caracteres entre letras, números, hífen e sublinhado';
    }
    el('mw-erro-usuario').textContent = erro;
    return !erro;
  }

  function validarSenha() {
    var a = el('mw-senha').value;
    var b = el('mw-senha2').value;
    var erro = '';
    if (!a) { erro = 'informe uma senha'; }
    else if (a !== b) { erro = 'as senhas não conferem'; }
    el('mw-erro-senha').textContent = erro;
    return !erro;
  }

  function validarDestino() {
    var v = el('mw-destino').value.trim();
    el('mw-erro-destino').textContent = v ? '' : 'escolha a pasta de destino';
    return !!v;
  }

  function pacotesDigitados() {
    return el('mw-pacotes').value.split(/\r?\n/).map(function (s) {
      return s.trim();
    }).filter(function (s) { return s.length > 0; });
  }

  /* ---------------- geração ---------------- */

  function resumoHtml(dados) {
    var sel = el('mw-edicao');
    var edicao = sel.options[sel.selectedIndex] ? sel.options[sel.selectedIndex].text : '';
    return '<ul class="mw-resumo">' +
      '<li>ISO de origem: <span class="mw-caminho">' + escapar(dados.iso) + '</span> (não será alterada)</li>' +
      '<li>Edição: ' + escapar(edicao) + '</li>' +
      '<li>Aplicativos a remover: ' + dados.appx.length + '</li>' +
      '<li>Pacotes a remover: ' + dados.pacotes.length + '</li>' +
      '<li>Conta local: ' + escapar(dados.usuario) + '</li>' +
      '<li>Destino: <span class="mw-caminho">' + escapar(dados.destino) + '</span></li>' +
      '</ul>' +
      '<p>A geração leva de 20 a 60 minutos e usa até 20 GB temporários. Continuar?</p>' +
      '<p id="mw-modal-progresso" class="mw-progresso"></p>';
  }

  function passosHtml(passos) {
    if (!passos || !passos.length) { return ''; }
    return '<ul class="mw-passos">' + passos.map(function (p) {
      return '<li class="' + (p.ok ? '' : 'mw-passo-falhou') + '">' +
        escapar(p.nome) + ' — ' + escapar(p.detalhe) + '</li>';
    }).join('') + '</ul>';
  }

  function modalResultado(r) {
    tmx.modal.open({
      titulo: r.ok ? 'ISO gerada' : 'A geração falhou',
      html: (r.ok
        ? '<p>Arquivo: <span class="mw-caminho">' + escapar(r.arquivo) + '</span></p>' +
          '<p>Tamanho: ' + escapar(r.tamanhoGB) + ' GB</p>'
        : '<p class="mw-erro">' + escapar(r.mensagem) + '</p>' +
          '<p>Pasta de trabalho preservada para diagnóstico:<br>' +
          '<span class="mw-caminho">' + escapar(r.pastaTrabalho) + '</span></p>') +
        passosHtml(r.passos),
      botoes: [{ rotulo: 'Fechar' }]
    });
  }

  function gerar() {
    var ok = [validarIso(), validarUsuario(), validarSenha(), validarDestino()];
    for (var i = 0; i < ok.length; i++) {
      if (!ok[i]) { tmx.toast('Corrija os campos marcados', 'aviso'); return; }
    }
    if (el('mw-edicao').disabled || !el('mw-edicao').value) {
      el('mw-iso-erro').textContent = 'leia a ISO e escolha a edição';
      return;
    }
    if (estado.prereq && !estado.prereq.pronto) {
      tmx.toast('Resolva os pré-requisitos antes de gerar a ISO', 'aviso');
      return;
    }

    var dados = {
      iso: el('mw-iso').value.trim(),
      edicao: parseInt(el('mw-edicao').value, 10),
      appx: marcados(),
      pacotes: pacotesDigitados(),
      usuario: el('mw-usuario').value,
      destino: el('mw-destino').value.trim()
    };

    tmx.modal.open({
      titulo: 'Gerar a ISO enxuta',
      html: resumoHtml(dados),
      botoes: [
        {
          rotulo: 'Gerar ISO',
          classe: 'btn-primary',
          mantemAberto: true,
          onClick: function () { disparar(dados); }
        },
        { rotulo: 'Cancelar' }
      ]
    });
  }

  function disparar(dados) {
    if (!ocupar()) { return; }

    var botoes = document.querySelectorAll('#modal-buttons button');
    for (var i = 0; i < botoes.length; i++) { botoes[i].disabled = true; }

    // A senha sai do input direto para a chamada: não passa pelo estado.
    var payload = {
      iso: dados.iso,
      edicao: dados.edicao,
      appx: dados.appx,
      pacotes: dados.pacotes,
      usuario: dados.usuario,
      senha: el('mw-senha').value,
      destino: dados.destino
    };
    if (testMode()) { payload.simular = true; }

    function progresso(p) {
      var t = (p.status || 'Trabalhando…') + (typeof p.pct === 'number' ? ' (' + p.pct + '%)' : '');
      var alvo = el('mw-modal-progresso');
      if (alvo) { alvo.textContent = t; }
      el('mw-progresso').textContent = t;
    }

    chamarJobComEspera('microwin.build', payload, progresso).then(function (r) {
      el('mw-progresso').textContent = '';
      tmx.modal.close();
      modalResultado(r || { ok: false, mensagem: 'resposta vazia' });
      if (r && r.ok) { tmx.toast(r.simulado ? 'Build simulada concluída' : 'ISO gerada', 'ok'); }
    }).catch(function (e) {
      el('mw-progresso').textContent = '';
      tmx.modal.close();
      tmx.toast(e.message, 'erro');
    }).then(liberar, liberar);
  }

  /* ---------------- arranque ---------------- */

  window.tmxTabs.microwin = {
    init: function () {
      el('mw-escolher').addEventListener('click', escolherIso);
      el('mw-ler').addEventListener('click', lerIso);
      el('mw-recomendados').addEventListener('click', marcarRecomendados);
      el('mw-limpar-apps').addEventListener('click', limparApps);
      el('mw-gerar').addEventListener('click', gerar);
      el('mw-apps').addEventListener('change', atualizarContagem);

      // 'input', 'change' e 'blur': o preenchimento programático das suites de
      // GUI dispara um deles, e nem sempre o mesmo.
      [['mw-iso', validarIso], ['mw-usuario', validarUsuario],
       ['mw-senha', validarSenha], ['mw-senha2', validarSenha],
       ['mw-destino', validarDestino]].forEach(function (par) {
        el(par[0]).addEventListener('input', par[1]);
        el(par[0]).addEventListener('change', par[1]);
        el(par[0]).addEventListener('blur', par[1]);
      });

      carregarPrereq();
      carregarApps();
    }
  };
})();
