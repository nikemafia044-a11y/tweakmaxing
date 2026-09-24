/* configuracoes.js - tela Configurações (v2, T5; spec §4 e §12).
 *
 * Monta #tab-configuracoes a partir daqui. Seções: Perfil, Aparência,
 * Sistema e Privacidade e dados. Ações da ponte:
 *   settings.get / settings.set / settings.windowsName  (síncronas)
 *   shell.version, app.paths, app.openLogs              (síncronas)
 *   app.checkUpdate, app.clearCache, app.oldBackups     (job)
 *   app.deleteOldBackups { confirmado:true }            (job, depois de confirmar)
 *
 * Depois de salvar algo, dispara 'tmx:settings' (detail = settings novos)
 * para o Painel repintar o nome sem reler.
 *
 * "Menu recolhido" não reimplementa o recolher: clica no #sidebar-collapse
 * da casca (que já aplica e persiste) e acompanha body[data-sidebar] por
 * MutationObserver, então os dois controles nunca divergem.
 */
(function () {
  'use strict';
  window.tmxTabs = window.tmxTabs || {};

  if (window.tmx && tmx.i18n) {
    tmx.i18n.add('pt-BR', {
      'config.eyebrow': 'Configurações',
      'config.titulo': 'Configurações',
      'config.subtitulo': 'Seu perfil, a aparência do app e os dados que ele guarda neste PC.',
      'config.perfil.titulo': 'Perfil',
      'config.perfil.nome': 'Nome de exibição',
      'config.perfil.nomeAjuda': 'Aparece na saudação do Painel. Vazio usa o nome da sua conta ({usuario}).',
      'config.perfil.salvar': 'Salvar',
      'config.perfil.usarWindows': 'Usar o nome do Windows',
      'config.perfil.salvo': 'Nome salvo',
      'config.aparencia.titulo': 'Aparência',
      'config.aparencia.idioma': 'Idioma',
      'config.aparencia.idiomaAjuda': 'Também dá para trocar pelo globo na barra de título.',
      'config.aparencia.menu': 'Menu recolhido',
      'config.aparencia.menuAjuda': 'Mostra só os ícones no menu lateral.',
      'config.sistema.titulo': 'Sistema',
      'config.sistema.versao': 'Versão instalada',
      'config.sistema.verificar': 'Verificar atualizações',
      'config.sistema.verificando': 'Verificando…',
      'config.sistema.emDia': 'Você está na versão mais recente ({versao}).',
      'config.sistema.nova': 'Nova versão disponível: {versao}.',
      'config.sistema.abrirRelease': 'Ver no GitHub',
      'config.sistema.erro': 'Não foi possível verificar: {msg}',
      'config.dados.titulo': 'Privacidade e dados',
      'config.dados.cache': 'Limpar o cache do app',
      'config.dados.cacheAjuda': 'Ícones baixados e interfaces de versões antigas. Tudo é refeito quando precisar.',
      'config.dados.cacheBotao': 'Limpar cache',
      'config.dados.cacheFeito': 'Cache limpo: {n} itens removidos',
      'config.dados.logs': 'Pasta de logs',
      'config.dados.logsAjuda': 'Registro do que o app fez, útil para relatar um problema.',
      'config.dados.logsBotao': 'Abrir pasta',
      'config.dados.logsSimulado': 'Modo de teste: a pasta não foi aberta ({caminho})',
      'config.dados.backups': 'Excluir backups antigos',
      'config.dados.backupsAjuda': 'Execuções com mais de 30 dias. A mais recente sempre fica. Sem o backup, o Desfazer daquela execução deixa de existir.',
      'config.dados.backupsBotao': 'Procurar backups antigos',
      'config.dados.backupsNenhum': 'Nenhum backup com mais de 30 dias.',
      'config.dados.backupsConfirmarTitulo': 'Excluir {n} backups antigos?',
      'config.dados.backupsConfirmarTexto': 'Estas execuções serão apagadas, com o Desfazer que elas guardam:',
      'config.dados.backupsConfirmar': 'Excluir backups',
      'config.dados.backupsFeito': '{n} backups excluídos',
      'config.dados.caminho': 'Caminho',
      'config.trabalhando': 'Trabalhando…'
    });

    tmx.i18n.add('en', {
      'config.eyebrow': 'Settings',
      'config.titulo': 'Settings',
      'config.subtitulo': 'Your profile, the app appearance and the data it keeps on this PC.',
      'config.perfil.titulo': 'Profile',
      'config.perfil.nome': 'Display name',
      'config.perfil.nomeAjuda': 'Shown in the Dashboard greeting. Empty uses your account name ({usuario}).',
      'config.perfil.salvar': 'Save',
      'config.perfil.usarWindows': 'Use the Windows name',
      'config.perfil.salvo': 'Name saved',
      'config.aparencia.titulo': 'Appearance',
      'config.aparencia.idioma': 'Language',
      'config.aparencia.idiomaAjuda': 'You can also switch it with the globe in the title bar.',
      'config.aparencia.menu': 'Collapsed menu',
      'config.aparencia.menuAjuda': 'Shows only the icons in the side menu.',
      'config.sistema.titulo': 'System',
      'config.sistema.versao': 'Installed version',
      'config.sistema.verificar': 'Check for updates',
      'config.sistema.verificando': 'Checking…',
      'config.sistema.emDia': 'You are on the latest version ({versao}).',
      'config.sistema.nova': 'New version available: {versao}.',
      'config.sistema.abrirRelease': 'View on GitHub',
      'config.sistema.erro': 'Could not check: {msg}',
      'config.dados.titulo': 'Privacy and data',
      'config.dados.cache': 'Clear the app cache',
      'config.dados.cacheAjuda': 'Downloaded icons and interfaces from old versions. Everything is rebuilt when needed.',
      'config.dados.cacheBotao': 'Clear cache',
      'config.dados.cacheFeito': 'Cache cleared: {n} items removed',
      'config.dados.logs': 'Logs folder',
      'config.dados.logsAjuda': 'A record of what the app did, useful when reporting a problem.',
      'config.dados.logsBotao': 'Open folder',
      'config.dados.logsSimulado': 'Test mode: the folder was not opened ({caminho})',
      'config.dados.backups': 'Delete old backups',
      'config.dados.backupsAjuda': 'Runs older than 30 days. The latest one is always kept. Without the backup, that run can no longer be undone.',
      'config.dados.backupsBotao': 'Find old backups',
      'config.dados.backupsNenhum': 'No backups older than 30 days.',
      'config.dados.backupsConfirmarTitulo': 'Delete {n} old backups?',
      'config.dados.backupsConfirmarTexto': 'These runs will be deleted, along with the Undo they hold:',
      'config.dados.backupsConfirmar': 'Delete backups',
      'config.dados.backupsFeito': '{n} backups deleted',
      'config.dados.caminho': 'Path',
      'config.trabalhando': 'Working…'
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
    settings: {},
    versao: null,
    paths: null,
    update: null,        // resultado de app.checkUpdate
    updateErro: null,
    verificando: false,
    ocupado: {}          // botão -> true enquanto o job roda
  };

  /* ---------------- esqueleto ---------------- */

  function linha(id, rotuloChave, ajudaHtml, controleHtml) {
    return '<div class="cf-linha" id="' + id + '">' +
      '<div class="cf-linha-texto">' +
        '<span class="cf-rotulo" data-i18n="' + rotuloChave + '"></span>' +
        ajudaHtml +
      '</div>' +
      '<div class="cf-linha-controle">' + controleHtml + '</div>' +
    '</div>';
  }

  function montar() {
    var sec = document.getElementById('tab-configuracoes');
    if (!sec) { return; }
    sec.classList.add('tmx-tela');
    sec.innerHTML =
      '<header class="tmx-cab">' +
        '<p class="tmx-eyebrow" data-i18n="config.eyebrow"></p>' +
        '<h1 class="tmx-titulo" data-i18n="config.titulo"></h1>' +
        '<p class="tmx-subtitulo" data-i18n="config.subtitulo"></p>' +
      '</header>' +

      '<section class="tmx-card cf-secao" id="cf-perfil" aria-labelledby="cf-h-perfil">' +
        '<h2 class="cf-h" id="cf-h-perfil" data-i18n="config.perfil.titulo"></h2>' +
        '<label class="cf-rotulo" for="cf-nome" data-i18n="config.perfil.nome"></label>' +
        '<div class="cf-nome-linha">' +
          '<input type="text" id="cf-nome" class="campo cf-nome" maxlength="40" autocomplete="off" spellcheck="false">' +
          '<button type="button" id="cf-nome-salvar" class="btn btn-primary" data-i18n="config.perfil.salvar"></button>' +
          '<button type="button" id="cf-nome-windows" class="btn" data-i18n="config.perfil.usarWindows"></button>' +
        '</div>' +
        '<p class="cf-ajuda" id="cf-nome-ajuda"></p>' +
      '</section>' +

      '<section class="tmx-card cf-secao" id="cf-aparencia" aria-labelledby="cf-h-aparencia">' +
        '<h2 class="cf-h" id="cf-h-aparencia" data-i18n="config.aparencia.titulo"></h2>' +
        linha('cf-linha-idioma', 'config.aparencia.idioma',
          '<span class="cf-ajuda" data-i18n="config.aparencia.idiomaAjuda"></span>',
          '<div class="cf-segmentado" role="group">' +
            '<button type="button" class="cf-seg" id="cf-lang-pt-BR" data-lang="pt-BR">Português (Brasil)</button>' +
            '<button type="button" class="cf-seg" id="cf-lang-en" data-lang="en">English</button>' +
          '</div>') +
        linha('cf-linha-menu', 'config.aparencia.menu',
          '<span class="cf-ajuda" data-i18n="config.aparencia.menuAjuda"></span>',
          '<button type="button" class="switch" id="cf-sidebar" role="switch" aria-checked="false"></button>') +
      '</section>' +

      '<section class="tmx-card cf-secao" id="cf-sistema" aria-labelledby="cf-h-sistema">' +
        '<h2 class="cf-h" id="cf-h-sistema" data-i18n="config.sistema.titulo"></h2>' +
        linha('cf-linha-versao', 'config.sistema.versao',
          '<span class="cf-versao" id="cf-versao">…</span>',
          '<button type="button" class="btn" id="cf-update"></button>') +
        '<div class="cf-update-resultado" id="cf-update-resultado" role="status" hidden></div>' +
      '</section>' +

      '<section class="tmx-card cf-secao" id="cf-dados" aria-labelledby="cf-h-dados">' +
        '<h2 class="cf-h" id="cf-h-dados" data-i18n="config.dados.titulo"></h2>' +
        linha('cf-linha-cache', 'config.dados.cache',
          '<span class="cf-ajuda" data-i18n="config.dados.cacheAjuda"></span><code class="cf-caminho" id="cf-caminho-cache"></code>',
          '<button type="button" class="btn" id="cf-cache" data-i18n="config.dados.cacheBotao"></button>') +
        linha('cf-linha-logs', 'config.dados.logs',
          '<span class="cf-ajuda" data-i18n="config.dados.logsAjuda"></span><code class="cf-caminho" id="cf-caminho-logs"></code>',
          '<button type="button" class="btn" id="cf-logs" data-i18n="config.dados.logsBotao"></button>') +
        linha('cf-linha-backups', 'config.dados.backups',
          '<span class="cf-ajuda" data-i18n="config.dados.backupsAjuda"></span><code class="cf-caminho" id="cf-caminho-runs"></code>',
          '<button type="button" class="btn btn-danger" id="cf-backups" data-i18n="config.dados.backupsBotao"></button>') +
      '</section>';

    tmx.i18n.apply(sec);
    ligar(sec);
    estado.montado = true;
  }

  function ligar(sec) {
    var nome = sec.querySelector('#cf-nome');
    sec.querySelector('#cf-nome-salvar').addEventListener('click', function () { salvarNome(nome.value.trim()); });
    nome.addEventListener('keydown', function (e) { if (e.key === 'Enter') { salvarNome(nome.value.trim()); } });
    sec.querySelector('#cf-nome-windows').addEventListener('click', usarNomeWindows);

    sec.querySelectorAll('.cf-seg[data-lang]').forEach(function (b) {
      b.addEventListener('click', function () {
        var lang = b.getAttribute('data-lang');
        if (lang !== tmx.i18n.lang) { tmx.i18n.set(lang); }
      });
    });

    sec.querySelector('#cf-sidebar').addEventListener('click', function () {
      var casca = document.getElementById('sidebar-collapse');
      if (casca) { casca.click(); }
    });

    sec.querySelector('#cf-update').addEventListener('click', verificarUpdate);
    sec.querySelector('#cf-cache').addEventListener('click', limparCache);
    sec.querySelector('#cf-logs').addEventListener('click', abrirLogs);
    sec.querySelector('#cf-backups').addEventListener('click', procurarBackups);
  }

  /* ---------------- pintura ---------------- */

  function pintarPerfil(sobrescreverCampo) {
    var nome = document.getElementById('cf-nome');
    var s = estado.settings || {};
    if (nome) {
      if (sobrescreverCampo) { nome.value = s.displayName || ''; }
      nome.placeholder = s.displayNameEfetivo || '';
      nome.setAttribute('aria-describedby', 'cf-nome-ajuda');
    }
    var ajuda = document.getElementById('cf-nome-ajuda');
    if (ajuda) {
      // Sem displayName salvo, displayNameEfetivo é o $env:USERNAME.
      var usuario = (!s.displayName && s.displayNameEfetivo) ? s.displayNameEfetivo : '';
      ajuda.textContent = t('config.perfil.nomeAjuda', { usuario: usuario || 'Windows' });
    }
    var bs = document.getElementById('cf-nome-salvar');
    var bw = document.getElementById('cf-nome-windows');
    if (bs) { bs.disabled = !!estado.ocupado.nome; }
    if (bw) { bw.disabled = !!estado.ocupado.nome; }
  }

  function pintarAparencia() {
    document.querySelectorAll('#cf-aparencia .cf-seg[data-lang]').forEach(function (b) {
      b.setAttribute('aria-pressed', b.getAttribute('data-lang') === tmx.i18n.lang ? 'true' : 'false');
    });
    var sw = document.getElementById('cf-sidebar');
    if (sw) {
      sw.setAttribute('aria-checked', document.body.dataset.sidebar === 'collapsed' ? 'true' : 'false');
      sw.setAttribute('aria-label', t('config.aparencia.menu'));
    }
  }

  function pintarSistema() {
    texto('cf-versao', estado.versao || '…');
    var b = document.getElementById('cf-update');
    if (b) {
      b.disabled = estado.verificando;
      b.textContent = t(estado.verificando ? 'config.sistema.verificando' : 'config.sistema.verificar');
    }
    var res = document.getElementById('cf-update-resultado');
    if (!res) { return; }
    res.className = 'cf-update-resultado';
    if (estado.updateErro || (estado.update && estado.update.erro)) {
      res.hidden = false;
      res.classList.add('cf-update-erro');
      res.textContent = t('config.sistema.erro', { msg: estado.updateErro || estado.update.erro });
      return;
    }
    var u = estado.update;
    if (!u) { res.hidden = true; res.textContent = ''; return; }
    res.hidden = false;
    if (u.novaDisponivel) {
      res.classList.add('cf-update-nova');
      res.innerHTML = '<span>' + esc(t('config.sistema.nova', { versao: u.ultima })) + '</span>';
      if (u.url) {
        var link = document.createElement('button');
        link.type = 'button';
        link.className = 'btn btn-primary btn-mini cf-release';
        link.id = 'cf-release';
        link.textContent = t('config.sistema.abrirRelease');
        link.addEventListener('click', function () {
          tmx.bridge.call('shell.openUrl', { url: u.url }).catch(function (e) { tmx.toast(e.message, 'erro'); });
        });
        res.appendChild(link);
      }
    } else {
      res.classList.add('cf-update-ok');
      res.textContent = t('config.sistema.emDia', { versao: u.atual || estado.versao || '' });
    }
  }

  function pintarDados() {
    var p = estado.paths || {};
    texto('cf-caminho-cache', p.cache || '');
    texto('cf-caminho-logs', p.logs || '');
    texto('cf-caminho-runs', p.runs || '');
    ['cache', 'logs', 'backups'].forEach(function (k) {
      var b = document.getElementById('cf-' + k);
      if (b) { b.disabled = !!estado.ocupado[k]; }
    });
  }

  function texto(id, v) {
    var el = document.getElementById(id);
    if (el) { el.textContent = v; }
  }

  function pintarTudo(sobrescreverCampo) {
    if (!estado.montado) { return; }
    pintarPerfil(sobrescreverCampo);
    pintarAparencia();
    pintarSistema();
    pintarDados();
  }

  /* ---------------- ações ---------------- */

  function avisarSettings() {
    document.dispatchEvent(new CustomEvent('tmx:settings', { detail: estado.settings }));
  }

  function salvarNome(valor) {
    if (estado.ocupado.nome) { return Promise.resolve(); }
    estado.ocupado.nome = true;
    pintarPerfil(false);
    return tmx.bridge.call('settings.set', { displayName: valor }).then(function (s) {
      estado.settings = s || estado.settings;
      tmx.toast(t('config.perfil.salvo'), 'ok');
      avisarSettings();
    }).catch(function (e) {
      tmx.toast(e.message, 'erro');
    }).then(function () {
      estado.ocupado.nome = false;
      pintarPerfil(true);
    });
  }

  function usarNomeWindows() {
    tmx.bridge.call('settings.windowsName').then(function (r) {
      var nome = (r && r.nome) || '';
      var campo = document.getElementById('cf-nome');
      if (campo) { campo.value = nome.slice(0, 40); }
      return salvarNome(nome.slice(0, 40));
    }).catch(function (e) { tmx.toast(e.message, 'erro'); });
  }

  function verificarUpdate() {
    if (estado.verificando) { return; }
    estado.verificando = true;
    estado.update = null;
    estado.updateErro = null;
    pintarSistema();
    chamarJob('app.checkUpdate', null).then(function (r) {
      estado.update = r || {};
    }).catch(function (e) {
      estado.updateErro = e.message;
    }).then(function () {
      estado.verificando = false;
      pintarSistema();
    });
  }

  function limparCache() {
    if (estado.ocupado.cache) { return; }
    estado.ocupado.cache = true;
    pintarDados();
    chamarJob('app.clearCache', null).then(function (r) {
      tmx.toast(t('config.dados.cacheFeito', { n: ((r && r.removidos) || []).length }), 'ok');
    }).catch(function (e) {
      tmx.toast(e.message, 'erro');
    }).then(function () {
      estado.ocupado.cache = false;
      pintarDados();
    });
  }

  function abrirLogs() {
    tmx.bridge.call('app.openLogs').then(function (r) {
      if (r && r.simulado) { tmx.toast(t('config.dados.logsSimulado', { caminho: r.caminho || '' }), 'aviso'); }
    }).catch(function (e) { tmx.toast(e.message, 'erro'); });
  }

  function nomeDaPasta(caminho) {
    var partes = String(caminho || '').split(/[\\/]/);
    return partes[partes.length - 1] || caminho;
  }

  function procurarBackups() {
    if (estado.ocupado.backups) { return; }
    estado.ocupado.backups = true;
    pintarDados();
    chamarJob('app.oldBackups', null).then(function (r) {
      var pastas = (r && r.pastas) || [];
      if (!pastas.length) {
        tmx.toast(t('config.dados.backupsNenhum'), 'ok');
        return;
      }
      confirmarBackups(pastas);
    }).catch(function (e) {
      tmx.toast(e.message, 'erro');
    }).then(function () {
      estado.ocupado.backups = false;
      pintarDados();
    });
  }

  function confirmarBackups(pastas) {
    var lista = pastas.map(function (p) { return '<li><code>' + esc(nomeDaPasta(p)) + '</code></li>'; }).join('');
    tmx.modal.open({
      titulo: t('config.dados.backupsConfirmarTitulo', { n: pastas.length }),
      html: '<p>' + esc(t('config.dados.backupsConfirmarTexto')) + '</p>' +
            '<ul class="cf-lista-backups" id="cf-lista-backups">' + lista + '</ul>' +
            '<p id="modal-progresso" class="sessao-progresso"></p>',
      botoes: [
        {
          rotulo: t('config.dados.backupsConfirmar'),
          classe: 'btn-danger cf-confirmar-backups',
          mantemAberto: true,
          onClick: function () {
            var bs = document.querySelectorAll('#modal-buttons button');
            for (var i = 0; i < bs.length; i++) { bs[i].disabled = true; }
            var prog = document.getElementById('modal-progresso');
            if (prog) { prog.textContent = t('config.trabalhando'); }
            chamarJob('app.deleteOldBackups', { confirmado: true }).then(function (r) {
              tmx.toast(t('config.dados.backupsFeito', { n: ((r && r.removidos) || []).length }), 'ok');
            }).catch(function (e) {
              tmx.toast(e.message, 'erro');
            }).then(function () { tmx.modal.close(); });
          }
        },
        { rotulo: t('shell.cancelar') }
      ]
    });
  }

  /* ---------------- cargas ---------------- */

  function carregar() {
    var pSettings = tmx.bridge.call('settings.get').then(function (s) { estado.settings = s || {}; });
    var pVersao = tmx.bridge.call('shell.version').then(function (v) { estado.versao = (v && v.version) || '—'; })
      .catch(function () { estado.versao = '—'; });
    var pPaths = tmx.bridge.call('app.paths').then(function (p) { estado.paths = p || {}; })
      .catch(function (e) { console.warn('app.paths falhou:', e.message); estado.paths = {}; });
    return tmx.aguardarTodas([pSettings, pVersao, pPaths]).then(function () {
      pintarTudo(true);
    }, function (e) {
      pintarTudo(true);
      tmx.toast(e.message, 'erro');
      throw e;
    });
  }

  var globaisLigados = false;

  function ligarGlobais() {
    document.addEventListener('tmx:lang', function () {
      if (!estado.montado) { return; }
      tmx.i18n.apply(document.getElementById('tab-configuracoes'));
      pintarTudo(false);
    });
    if (window.MutationObserver) {
      new MutationObserver(function () { if (estado.montado) { pintarAparencia(); } })
        .observe(document.body, { attributes: true, attributeFilter: ['data-sidebar'] });
    }
    // Voltar à aba relê as configurações (outra tela pode ter mudado algo).
    var nav = document.querySelector('nav [data-tab="configuracoes"]');
    if (nav) {
      nav.addEventListener('click', function () {
        if (!estado.montado) { return; }
        tmx.bridge.call('settings.get').then(function (s) {
          estado.settings = s || estado.settings;
          pintarPerfil(document.activeElement !== document.getElementById('cf-nome'));
          pintarAparencia();
        }).catch(function () { });
      });
    }
  }

  window.tmxTabs.configuracoes = {
    init: function () {
      if (!globaisLigados) { ligarGlobais(); globaisLigados = true; }
      montar();
      pintarTudo(true);
      return carregar();
    }
  };
})();
