/* painel.js - tela Painel (v2, T5; spec §5).
 *
 * Monta #tab-painel inteiro a partir daqui (o index.html só traz o
 * placeholder). Fontes de dados:
 *   settings.get               (síncrona) nome de exibição e modo aplicado
 *   system.info                (job) hardware + recomendações (chaves painel.rec.*)
 *   restore.list               (job) último ponto de restauração
 *   system.optimizationStatus  (job) {disponiveis, ativos}
 *   restore.create             (job) botão "Criar ponto agora"
 *
 * A ponte aceita um job por vez: as cargas vão em fila (uma termina, a
 * próxima começa) e cada chamada usa callComEspera para esperar um job de
 * outra aba que já estivesse no ar.
 *
 * Tudo que vem do sistema (modelo da CPU, nome do ponto, nome de exibição)
 * passa por tmx.esc (ou textContent) antes de entrar na página.
 *
 * Eventos que esta tela emite/ouve (sem editar arquivos de outras telas):
 *   'tmx:modo'     (emite)  { modo } depois de abrir Otimizações por um chip
 *   'tmx:settings' (ouve)   configuracoes.js avisa quando salvou algo
 */
(function () {
  'use strict';
  window.tmxTabs = window.tmxTabs || {};

  /* ---------------- textos ---------------- */

  if (window.tmx && tmx.i18n) {
    tmx.i18n.add('pt-BR', {
      'painel.eyebrow': 'Painel',
      'painel.bemVindo': 'Bem-vindo de volta,',
      'painel.subtitulo': 'Seu hardware e o estado das otimizações, num só lugar.',
      'painel.ultimoPonto': 'Último ponto de restauração: {quando}',
      'painel.semPonto': 'Nenhum ponto de restauração',
      'painel.lendoPonto': 'Lendo pontos de restauração…',
      'painel.hoje': 'hoje, {hora}',
      'painel.ontem': 'ontem, {hora}',
      'painel.criarPonto': 'Criar ponto agora',
      'painel.criandoPonto': 'Criando…',
      'painel.pontoCriado': 'Ponto de restauração criado',
      'painel.hero.titulo': 'Deixe o PC pronto para jogar',
      'painel.hero.texto': 'Escolha um modo de otimização e veja exatamente o que muda antes de aplicar. Tudo pode ser desfeito com um clique.',
      'painel.hero.abrir': 'Abrir otimizações',
      'painel.modo.leve': 'Leve',
      'painel.modo.moderado': 'Moderado',
      'painel.modo.avancado': 'Avançado',
      'painel.modo.ultimate': 'Ultimate',
      'painel.modo.nenhum': 'Nenhum',
      'painel.status.titulo': 'Status de otimização',
      'painel.status.otimizado': 'otimizado',
      'painel.status.disponiveis': 'Disponíveis',
      'painel.status.ativos': 'Ativos',
      'painel.status.modoAtual': 'Modo atual',
      'painel.hw.cpu': 'Processador',
      'painel.hw.gpu': 'Placa de vídeo',
      'painel.hw.ram': 'Memória',
      'painel.hw.disco': 'Armazenamento',
      'painel.hw.nucleos': '{n} núcleos',
      'painel.hw.vram': '{n} GB VRAM',
      'painel.hw.gb': '{n} GB',
      'painel.hw.desconhecido': 'Não identificado',
      'painel.hw.lendo': 'Lendo…',
      'painel.os.titulo': 'Sistema operacional',
      'painel.os.legenda': 'Informações do Windows',
      'painel.os.sistema': 'Sistema',
      'painel.os.versao': 'Versão',
      'painel.os.disco': 'Disco do sistema',
      'painel.rec.titulo': 'Recomendações para este PC',
      'painel.rec.nenhuma': 'Nenhuma recomendação para este PC agora.',
      'painel.rec.tipo.bios': 'Faça na BIOS',
      'painel.rec.tipo.app': 'Disponível no app',
      'painel.rec.verGuia': 'Ver passo a passo',
      'painel.rec.xmp': 'Confira se o perfil DOCP/XMP da memória está ativo',
      'painel.rec.xmp.texto': 'Sem ele, a memória {tipo} roda abaixo da velocidade anunciada ({config} de {nominal} MT/s). O app mostra o passo a passo.',
      'painel.rec.xmp.guia':
        '<ol class="pn-guia">' +
        '<li>Reinicie o PC e entre na BIOS/UEFI (normalmente tecla <kbd>Del</kbd> ou <kbd>F2</kbd> na tela do fabricante).</li>' +
        '<li>Procure o perfil de memória: <strong>XMP</strong> (Intel), <strong>DOCP</strong> (ASUS) ou <strong>EXPO</strong> (AMD). Costuma ficar em "Ai Tweaker", "OC" ou "Extreme Tweaker".</li>' +
        '<li>Troque de <em>Auto/Disabled</em> para <em>Profile 1</em>.</li>' +
        '<li>Salve e saia (<kbd>F10</kbd>). O primeiro boot pode demorar um pouco mais (treino de memória).</li>' +
        '<li>Se o PC não ligar ou ficar instável, volte à BIOS e desligue o perfil: nada fica danificado.</li>' +
        '</ol>',
      'painel.rec.hags': 'Agendamento de GPU acelerado (HAGS)',
      'painel.rec.hags.texto': 'Sua placa suporta. Faz parte do modo Moderado e pede reinício.',
      'painel.rec.hags.guia':
        '<p>O agendamento de GPU acelerado por hardware deixa a própria placa de vídeo gerenciar a fila de trabalho, o que pode reduzir a latência.</p>' +
        '<ol class="pn-guia"><li>Abra <strong>Otimizações</strong> e escolha o modo <strong>Moderado</strong> (ou superior).</li>' +
        '<li>Revise a prévia e aplique. Reinicie o PC para o ajuste valer.</li></ol>',
      'painel.rec.powerplan.desktop': 'Plano de energia de desempenho máximo',
      'painel.rec.powerplan.desktop.texto': 'Desktop detectado: seguro de aplicar. Faz parte do modo Leve.',
      'painel.rec.powerplan.desktop.guia':
        '<p>O plano de desempenho máximo mantém a CPU pronta para responder, sem as economias de energia que atrasam a subida de clock.</p>' +
        '<ol class="pn-guia"><li>Abra <strong>Otimizações</strong> e escolha o modo <strong>Leve</strong> (ou superior).</li>' +
        '<li>Revise a prévia e aplique. Dá para desfazer a qualquer momento.</li></ol>',
      'painel.rec.powerplan.notebook': 'Plano de energia: mantido no notebook',
      'painel.rec.powerplan.notebook.texto': 'Notebook detectado: o plano de desempenho máximo não será aplicado, para poupar bateria e temperatura.',
      'painel.rec.powerplan.notebook.guia':
        '<p>Em notebook, o plano de desempenho máximo esquenta o aparelho e drena a bateria sem ganho real em jogos. Por isso os modos de otimização não o aplicam aqui.</p>' +
        '<p>Na tomada, prefira o modo de energia "Melhor desempenho" nas Configurações do Windows.</p>',
      'painel.erro.info': 'Não foi possível ler o hardware: {msg}'
    });

    tmx.i18n.add('en', {
      'painel.eyebrow': 'Dashboard',
      'painel.bemVindo': 'Welcome back,',
      'painel.subtitulo': 'Your hardware and optimization status, in one place.',
      'painel.ultimoPonto': 'Last restore point: {quando}',
      'painel.semPonto': 'No restore point',
      'painel.lendoPonto': 'Reading restore points…',
      'painel.hoje': 'today, {hora}',
      'painel.ontem': 'yesterday, {hora}',
      'painel.criarPonto': 'Create point now',
      'painel.criandoPonto': 'Creating…',
      'painel.pontoCriado': 'Restore point created',
      'painel.hero.titulo': 'Get your PC ready to play',
      'painel.hero.texto': 'Pick an optimization mode and see exactly what changes before applying. Everything can be undone with one click.',
      'painel.hero.abrir': 'Open optimizations',
      'painel.modo.leve': 'Light',
      'painel.modo.moderado': 'Moderate',
      'painel.modo.avancado': 'Advanced',
      'painel.modo.ultimate': 'Ultimate',
      'painel.modo.nenhum': 'None',
      'painel.status.titulo': 'Optimization status',
      'painel.status.otimizado': 'optimized',
      'painel.status.disponiveis': 'Available',
      'painel.status.ativos': 'Active',
      'painel.status.modoAtual': 'Current mode',
      'painel.hw.cpu': 'Processor',
      'painel.hw.gpu': 'Graphics card',
      'painel.hw.ram': 'Memory',
      'painel.hw.disco': 'Storage',
      'painel.hw.nucleos': '{n} cores',
      'painel.hw.vram': '{n} GB VRAM',
      'painel.hw.gb': '{n} GB',
      'painel.hw.desconhecido': 'Unknown',
      'painel.hw.lendo': 'Reading…',
      'painel.os.titulo': 'Operating system',
      'painel.os.legenda': 'Windows information',
      'painel.os.sistema': 'System',
      'painel.os.versao': 'Version',
      'painel.os.disco': 'System drive',
      'painel.rec.titulo': 'Recommendations for this PC',
      'painel.rec.nenhuma': 'No recommendations for this PC right now.',
      'painel.rec.tipo.bios': 'Do it in the BIOS',
      'painel.rec.tipo.app': 'Available in the app',
      'painel.rec.verGuia': 'Show steps',
      'painel.rec.xmp': 'Check that the memory DOCP/XMP profile is enabled',
      'painel.rec.xmp.texto': 'Without it, your {tipo} memory runs below its rated speed ({config} of {nominal} MT/s). The app shows you how.',
      'painel.rec.xmp.guia':
        '<ol class="pn-guia">' +
        '<li>Restart the PC and enter the BIOS/UEFI (usually <kbd>Del</kbd> or <kbd>F2</kbd> on the vendor screen).</li>' +
        '<li>Find the memory profile: <strong>XMP</strong> (Intel), <strong>DOCP</strong> (ASUS) or <strong>EXPO</strong> (AMD). It is often under "Ai Tweaker", "OC" or "Extreme Tweaker".</li>' +
        '<li>Change it from <em>Auto/Disabled</em> to <em>Profile 1</em>.</li>' +
        '<li>Save and exit (<kbd>F10</kbd>). The first boot may take a little longer (memory training).</li>' +
        '<li>If the PC does not boot or becomes unstable, go back and disable the profile: nothing gets damaged.</li>' +
        '</ol>',
      'painel.rec.hags': 'Hardware-accelerated GPU scheduling (HAGS)',
      'painel.rec.hags.texto': 'Your card supports it. Part of the Moderate mode; needs a restart.',
      'painel.rec.hags.guia':
        '<p>Hardware-accelerated GPU scheduling lets the graphics card manage its own work queue, which can reduce latency.</p>' +
        '<ol class="pn-guia"><li>Open <strong>Optimizations</strong> and pick the <strong>Moderate</strong> mode (or higher).</li>' +
        '<li>Review the preview and apply. Restart the PC for it to take effect.</li></ol>',
      'painel.rec.powerplan.desktop': 'Ultimate performance power plan',
      'painel.rec.powerplan.desktop.texto': 'Desktop detected: safe to apply. Part of the Light mode.',
      'painel.rec.powerplan.desktop.guia':
        '<p>The ultimate performance plan keeps the CPU ready to respond, without the power savings that delay clock ramp-up.</p>' +
        '<ol class="pn-guia"><li>Open <strong>Optimizations</strong> and pick the <strong>Light</strong> mode (or higher).</li>' +
        '<li>Review the preview and apply. You can undo it at any time.</li></ol>',
      'painel.rec.powerplan.notebook': 'Power plan: kept on laptops',
      'painel.rec.powerplan.notebook.texto': 'Laptop detected: the ultimate performance plan will not be applied, to spare battery and heat.',
      'painel.rec.powerplan.notebook.guia':
        '<p>On a laptop, the ultimate performance plan heats the device and drains the battery with no real gain in games. That is why the optimization modes skip it here.</p>' +
        '<p>When plugged in, prefer the "Best performance" power mode in Windows Settings.</p>',
      'painel.erro.info': 'Could not read the hardware: {msg}'
    });
  }

  function t(chave, vars) { return tmx.i18n.t(chave, vars); }
  function esc(s) { return tmx.esc(s); }

  /* ---------------- ponte: job com correlação por jobId ----------------
   * O ouvinte entra ANTES da chamada e guarda job.done de jobId ainda
   * desconhecido: um job curto pode terminar antes de a resposta com o
   * jobId chegar (mesmo cuidado de abrirSessao em app.js). */
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

  /* ---------------- estado ---------------- */

  var estado = {
    montado: false,
    settings: null,
    info: null,
    infoErro: null,
    pontos: null,
    status: null,
    criando: false,
    statusSujo: false
  };

  /* ---------------- formatação ---------------- */

  function locale() { return tmx.i18n.lang === 'en' ? 'en-US' : 'pt-BR'; }

  function numero(n, casas) {
    if (n === null || n === undefined || isNaN(Number(n))) { return null; }
    return Number(n).toLocaleString(locale(), { maximumFractionDigits: casas || 0 });
  }

  function hora(d) {
    return d.toLocaleTimeString(locale(), { hour: '2-digit', minute: '2-digit' });
  }

  function quando(iso) {
    var d = new Date(iso);
    if (isNaN(d.getTime())) { return String(iso || ''); }
    var hoje = new Date();
    var ontem = new Date(hoje.getFullYear(), hoje.getMonth(), hoje.getDate() - 1);
    if (d.toDateString() === hoje.toDateString()) { return t('painel.hoje', { hora: hora(d) }); }
    if (d.toDateString() === ontem.toDateString()) { return t('painel.ontem', { hora: hora(d) }); }
    return d.toLocaleDateString(locale(), { day: '2-digit', month: '2-digit', year: 'numeric' }) + ' ' + hora(d);
  }

  /* "AMD Ryzen 7 5700X3D 8-Core Processor" -> "AMD Ryzen 7 5700X3D";
     "Intel(R) Core(TM) i5-9600K CPU @ 3.70GHz" -> "Intel Core i5-9600K".
     Só enfeite de exibição: o nome completo fica no title do cartão. */
  function limparCpu(nome) {
    return String(nome || '')
      .replace(/\((R|TM|C)\)/gi, '')
      .replace(/\s+CPU\s*@.*$/i, '')
      .replace(/\s+\d+-Core\s+Processor\s*$/i, '')
      .replace(/\s+Processor\s*$/i, '')
      .replace(/\s+/g, ' ')
      .trim();
  }

  function nomeModo(m) {
    if (!m) { return t('painel.modo.nenhum'); }
    var chave = 'painel.modo.' + m;
    var r = t(chave);
    return r === chave ? m : r;
  }

  /* ---------------- ícones (Lucide, ISC) ---------------- */

  function svg(corpo, tam) {
    tam = tam || 20;
    return '<svg width="' + tam + '" height="' + tam + '" viewBox="0 0 24 24" fill="none" stroke="currentColor" ' +
      'stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false">' + corpo + '</svg>';
  }

  var ICONE = {
    raio: '<path d="M4 14a1 1 0 0 1-.78-1.63l9.9-10.2a.5.5 0 0 1 .86.46l-1.92 6.02A1 1 0 0 0 13 10h7a1 1 0 0 1 .78 1.63l-9.9 10.2a.5.5 0 0 1-.86-.46l1.92-6.02A1 1 0 0 0 11 14z"></path>',
    cpu: '<rect x="4" y="4" width="16" height="16" rx="2"></rect><rect x="9" y="9" width="6" height="6"></rect>' +
      '<path d="M15 2v2"></path><path d="M15 20v2"></path><path d="M2 15h2"></path><path d="M2 9h2"></path>' +
      '<path d="M20 15h2"></path><path d="M20 9h2"></path><path d="M9 2v2"></path><path d="M9 20v2"></path>',
    gpu: '<rect x="2" y="6" width="20" height="12" rx="2"></rect><circle cx="8" cy="12" r="2"></circle>' +
      '<path d="M14 10h4"></path><path d="M14 14h4"></path>',
    ram: '<path d="M6 19v-3"></path><path d="M10 19v-3"></path><path d="M14 19v-3"></path><path d="M18 19v-3"></path>' +
      '<path d="M8 11V9"></path><path d="M16 11V9"></path><path d="M12 11V9"></path>' +
      '<path d="M2 15h20"></path><path d="M2 7a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v1.1a2 2 0 0 0 0 3.837V17a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2v-5.1a2 2 0 0 0 0-3.837Z"></path>',
    disco: '<path d="M22 12H2"></path><path d="M5.45 5.11 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z"></path>' +
      '<path d="M6 16h.01"></path><path d="M10 16h.01"></path>',
    monitor: '<rect width="20" height="14" x="2" y="3" rx="2"></rect><path d="M8 21h8"></path><path d="M12 17v4"></path>',
    seta: '<path d="M5 12h14"></path><path d="m12 5 7 7-7 7"></path>'
  };

  /* ---------------- esqueleto ---------------- */

  function cartaoHw(id, icone, rotulo) {
    return '<article class="pn-card pn-hw-card" id="pn-hw-' + id + '">' +
      '<div class="pn-hw-topo"><span class="pn-icone-caixa">' + svg(icone, 18) + '</span>' +
      '<span class="pn-chip" id="pn-hw-' + id + '-chip" hidden></span></div>' +
      '<span class="pn-hw-rotulo" data-i18n="' + rotulo + '"></span>' +
      '<strong class="pn-hw-valor" id="pn-hw-' + id + '-valor"></strong>' +
    '</article>';
  }

  function montar() {
    var sec = document.getElementById('tab-painel');
    if (!sec) { return; }
    sec.innerHTML =
      '<header class="pn-topo">' +
        '<div class="pn-topo-texto">' +
          '<p class="pn-eyebrow" data-i18n="painel.eyebrow"></p>' +
          '<h1 class="pn-titulo"><span data-i18n="painel.bemVindo"></span> <span id="pn-nome" class="pn-nome"></span></h1>' +
          '<p class="pn-subtitulo" data-i18n="painel.subtitulo"></p>' +
        '</div>' +
        '<div class="pn-topo-acoes">' +
          '<span id="pn-ponto" class="pn-pilula"><span class="pn-ponto-bola" aria-hidden="true"></span><span id="pn-ponto-texto"></span></span>' +
          '<button type="button" id="pn-criar-ponto" class="btn pn-btn-contorno"></button>' +
        '</div>' +
      '</header>' +

      '<div class="pn-linha1">' +
        '<article class="pn-card pn-hero">' +
          '<div class="pn-hero-icone">' + svg(ICONE.raio, 24) + '</div>' +
          '<div class="pn-hero-corpo">' +
            '<h2 class="pn-hero-titulo" data-i18n="painel.hero.titulo"></h2>' +
            '<p class="pn-hero-texto" data-i18n="painel.hero.texto"></p>' +
            '<div class="pn-hero-rodape">' +
              '<div class="pn-modos" id="pn-modos">' +
                ['leve', 'moderado', 'avancado', 'ultimate'].map(function (m) {
                  return '<button type="button" class="pn-modo" data-modo="' + m + '" data-i18n="painel.modo.' + m + '"></button>';
                }).join('') +
              '</div>' +
              '<button type="button" id="pn-abrir-otim" class="btn btn-primary pn-abrir">' +
                '<span data-i18n="painel.hero.abrir"></span>' + svg(ICONE.seta, 16) +
              '</button>' +
            '</div>' +
          '</div>' +
        '</article>' +

        '<article class="pn-card pn-status" id="pn-status">' +
          '<div class="pn-anel" aria-hidden="true">' +
            '<svg viewBox="0 0 100 100" class="pn-anel-svg">' +
              '<circle class="pn-anel-fundo" cx="50" cy="50" r="42"></circle>' +
              '<circle class="pn-anel-valor" id="pn-anel-valor" cx="50" cy="50" r="42" pathLength="100" stroke-dasharray="0 100"></circle>' +
            '</svg>' +
            '<div class="pn-anel-texto"><strong id="pn-pct">…</strong><span data-i18n="painel.status.otimizado"></span></div>' +
          '</div>' +
          '<div class="pn-status-corpo">' +
            '<h2 class="pn-status-titulo" data-i18n="painel.status.titulo"></h2>' +
            '<dl class="pn-status-lista">' +
              '<div><dt data-i18n="painel.status.disponiveis"></dt><dd id="pn-disponiveis">…</dd></div>' +
              '<div><dt data-i18n="painel.status.ativos"></dt><dd id="pn-ativos" class="pn-destaque">…</dd></div>' +
              '<div><dt data-i18n="painel.status.modoAtual"></dt><dd id="pn-modo-atual">…</dd></div>' +
            '</dl>' +
          '</div>' +
        '</article>' +
      '</div>' +

      '<div class="pn-hw" id="pn-hw">' +
        cartaoHw('cpu', ICONE.cpu, 'painel.hw.cpu') +
        cartaoHw('gpu', ICONE.gpu, 'painel.hw.gpu') +
        cartaoHw('ram', ICONE.ram, 'painel.hw.ram') +
        cartaoHw('disco', ICONE.disco, 'painel.hw.disco') +
      '</div>' +

      '<article class="pn-card pn-os">' +
        '<div class="pn-os-cab">' +
          '<span class="pn-icone-caixa">' + svg(ICONE.monitor, 18) + '</span>' +
          '<span class="pn-os-cab-texto"><strong class="pn-os-titulo" data-i18n="painel.os.titulo"></strong>' +
          '<span class="pn-os-legenda" data-i18n="painel.os.legenda"></span></span>' +
        '</div>' +
        '<div class="pn-os-campo"><span data-i18n="painel.os.sistema"></span><strong id="pn-os-edicao">…</strong></div>' +
        '<div class="pn-os-campo"><span data-i18n="painel.os.versao"></span><strong id="pn-os-versao">…</strong></div>' +
        '<div class="pn-os-campo"><span data-i18n="painel.os.disco"></span><strong id="pn-os-disco">…</strong></div>' +
      '</article>' +

      '<h2 class="pn-secao-titulo" data-i18n="painel.rec.titulo"></h2>' +
      '<div class="pn-recs" id="pn-recs"></div>';

    tmx.i18n.apply(sec);
    ligar(sec);
    estado.montado = true;
  }

  function ligar(sec) {
    sec.querySelector('#pn-abrir-otim').addEventListener('click', function () { abrirOtimizacoes(null); });
    sec.querySelectorAll('.pn-modo').forEach(function (b) {
      b.addEventListener('click', function () { abrirOtimizacoes(b.getAttribute('data-modo')); });
    });
    sec.querySelector('#pn-criar-ponto').addEventListener('click', criarPonto);
  }

  /* A tela de Otimizações (outra tarefa) pode ouvir 'tmx:modo' para já
     abrir com o modo escolhido aqui marcado. */
  function abrirOtimizacoes(modo) {
    tmx.tabs.show('otimizacoes');
    if (modo) {
      setTimeout(function () {
        document.dispatchEvent(new CustomEvent('tmx:modo', { detail: { modo: modo } }));
      }, 0);
    }
  }

  /* ---------------- pintura ---------------- */

  function texto(id, valor) {
    var el = document.getElementById(id);
    if (el) { el.textContent = valor; }
  }

  function chip(id, valor) {
    var el = document.getElementById(id);
    if (!el) { return; }
    el.hidden = !valor;
    el.textContent = valor || '';
  }

  function pintarNome() {
    var s = estado.settings || {};
    texto('pn-nome', s.displayNameEfetivo || s.displayName || '');
  }

  function pintarPonto() {
    var el = document.getElementById('pn-ponto-texto');
    var pilula = document.getElementById('pn-ponto');
    if (!el || !pilula) { return; }
    if (estado.pontos === null) {
      el.textContent = t('painel.lendoPonto');
      pilula.classList.remove('pn-pilula-vazia');
      return;
    }
    var ultimo = estado.pontos[0];
    pilula.classList.toggle('pn-pilula-vazia', !ultimo);
    el.textContent = ultimo ? t('painel.ultimoPonto', { quando: quando(ultimo.data) }) : t('painel.semPonto');
    pilula.title = ultimo ? (ultimo.nome || '') : '';
  }

  function pintarBotaoPonto() {
    var b = document.getElementById('pn-criar-ponto');
    if (!b) { return; }
    b.disabled = estado.criando;
    b.textContent = t(estado.criando ? 'painel.criandoPonto' : 'painel.criarPonto');
  }

  function pintarStatus() {
    var s = estado.status;
    var modo = estado.settings ? estado.settings.appliedMode : null;
    texto('pn-modo-atual', estado.settings ? nomeModo(modo) : '…');
    document.querySelectorAll('#pn-modos .pn-modo').forEach(function (b) {
      b.classList.toggle('pn-modo-ativo', !!modo && b.getAttribute('data-modo') === modo);
    });
    if (!s) {
      texto('pn-pct', '…');
      texto('pn-disponiveis', '…');
      texto('pn-ativos', '…');
      return;
    }
    var disp = Number(s.disponiveis) || 0;
    var ativos = Number(s.ativos) || 0;
    var pct = disp > 0 ? Math.round(Math.min(ativos, disp) * 100 / disp) : 0;
    texto('pn-pct', pct + '%');
    texto('pn-disponiveis', numero(disp));
    texto('pn-ativos', numero(ativos));
    var anel = document.getElementById('pn-anel-valor');
    if (anel) { anel.setAttribute('stroke-dasharray', pct + ' ' + (100 - pct)); }
  }

  function pintarHardware() {
    var info = estado.info;
    var lendo = t('painel.hw.lendo');
    var desc = t('painel.hw.desconhecido');
    if (!info) {
      var msg = estado.infoErro ? t('painel.erro.info', { msg: estado.infoErro }) : lendo;
      ['cpu', 'gpu', 'ram', 'disco'].forEach(function (id) { texto('pn-hw-' + id + '-valor', estado.infoErro ? desc : lendo); });
      ['pn-os-edicao', 'pn-os-versao', 'pn-os-disco'].forEach(function (id) { texto(id, estado.infoErro ? desc : '…'); });
      var recs = document.getElementById('pn-recs');
      if (recs) { recs.innerHTML = '<p class="vazio">' + esc(msg) + '</p>'; }
      return;
    }

    var cpu = info.cpu || {}, gpu = info.gpu || {}, ram = info.ram || {}, disco = info.disco || {}, os = info.os || {};

    texto('pn-hw-cpu-valor', cpu.modelo ? limparCpu(cpu.modelo) : desc);
    var cartaoCpu = document.getElementById('pn-hw-cpu');
    if (cartaoCpu) { cartaoCpu.title = cpu.modelo || ''; }
    chip('pn-hw-cpu-chip', cpu.nucleos ? t('painel.hw.nucleos', { n: cpu.nucleos }) : '');

    texto('pn-hw-gpu-valor', gpu.modelo || desc);
    chip('pn-hw-gpu-chip', gpu.vramGB ? t('painel.hw.vram', { n: numero(gpu.vramGB, 1) }) : '');

    texto('pn-hw-ram-valor', ram.totalGB ? t('painel.hw.gb', { n: numero(ram.totalGB, 2) }) : desc);
    chip('pn-hw-ram-chip', ram.tipo && ram.tipo !== '?' ? ram.tipo : '');

    texto('pn-hw-disco-valor', disco.tamanhoGB ? t('painel.hw.gb', { n: numero(disco.tamanhoGB) }) : desc);
    chip('pn-hw-disco-chip', disco.tipo && disco.tipo !== 'Desconhecido' ? disco.tipo : '');

    texto('pn-os-edicao', os.edicao || desc);
    texto('pn-os-versao', os.displayVersion || (os.build ? String(os.build) : desc));
    texto('pn-os-disco', disco.modelo || desc);

    pintarRecomendacoes(info);
  }

  function pintarRecomendacoes(info) {
    var raiz = document.getElementById('pn-recs');
    if (!raiz) { return; }
    var lista = (info.recomendacoes || []).slice(0, 3);
    if (!lista.length) {
      raiz.innerHTML = '<p class="vazio">' + esc(t('painel.rec.nenhuma')) + '</p>';
      return;
    }
    var ram = info.ram || {};
    var vars = {
      tipo: ram.tipo && ram.tipo !== '?' ? ram.tipo : 'RAM',
      config: ram.velocidadeConfigurada || '?',
      nominal: ram.velocidadeNominal || '?'
    };
    raiz.innerHTML = '';
    lista.forEach(function (rec, i) {
      var chave = rec.chave || rec.titulo || '';
      var tipo = rec.tipo === 'bios' ? 'bios' : 'app';
      var card = document.createElement('article');
      card.className = 'pn-card pn-rec pn-rec-' + tipo;
      card.id = 'pn-rec-' + i;
      card.setAttribute('data-chave', chave);
      card.innerHTML =
        '<p class="pn-rec-tipo">' + esc(t('painel.rec.tipo.' + tipo)) + '</p>' +
        '<h3 class="pn-rec-titulo">' + esc(t(chave, vars)) + '</h3>' +
        '<p class="pn-rec-texto">' + esc(t(chave + '.texto', vars)) + '</p>';
      if (rec.guia) {
        var b = document.createElement('button');
        b.type = 'button';
        b.className = 'pn-rec-guia';
        b.textContent = t('painel.rec.verGuia');
        b.addEventListener('click', function () {
          // O guia é HTML de confiança escrito neste arquivo (dicionário
          // painel.rec.*.guia); o back-end só manda a CHAVE, nunca o texto.
          var html = t(rec.guia, vars);
          if (html === rec.guia) { html = '<p>' + esc(t(chave + '.texto', vars)) + '</p>'; }
          tmx.modal.open({ titulo: t(chave, vars), html: html, botoes: [{ rotulo: t('shell.fechar') }] });
        });
        card.appendChild(b);
      }
      raiz.appendChild(card);
    });
  }

  function pintarTudo() {
    if (!estado.montado) { return; }
    pintarNome();
    pintarPonto();
    pintarBotaoPonto();
    pintarStatus();
    pintarHardware();
  }

  /* ---------------- cargas ---------------- */

  function carregarSettings() {
    return tmx.bridge.call('settings.get').then(function (s) {
      estado.settings = s || {};
    }).catch(function (e) {
      estado.settings = {};
      console.warn('settings.get falhou:', e.message);
    }).then(function () {
      pintarNome();
      pintarStatus();
    });
  }

  function carregarInfo() {
    return chamarJob('system.info', null).then(function (info) {
      estado.info = info || {};
      estado.infoErro = null;
      pintarHardware();
    }).catch(function (e) {
      estado.infoErro = e.message;
      pintarHardware();
      throw e;
    });
  }

  function carregarPontos() {
    return chamarJob('restore.list', null).then(function (r) {
      estado.pontos = (r && r.pontos) || [];
    }).catch(function (e) {
      estado.pontos = [];
      console.warn('restore.list falhou:', e.message);
    }).then(pintarPonto);
  }

  function carregarStatus() {
    return chamarJob('system.optimizationStatus', null).then(function (s) {
      estado.status = s || { disponiveis: 0, ativos: 0 };
      estado.statusSujo = false;
    }).catch(function (e) {
      estado.status = { disponiveis: 0, ativos: 0 };
      console.warn('system.optimizationStatus falhou:', e.message);
    }).then(pintarStatus);
  }

  function criarPonto() {
    if (estado.criando) { return; }
    estado.criando = true;
    pintarBotaoPonto();
    chamarJob('restore.create', {}).then(function (r) {
      estado.pontos = (r && r.pontos) || estado.pontos || [];
      tmx.toast(t('painel.pontoCriado'), 'ok');
    }).catch(function (e) {
      tmx.toast(e.message, 'erro');
    }).then(function () {
      estado.criando = false;
      pintarBotaoPonto();
      pintarPonto();
    });
  }

  /* Ao voltar para o Painel: settings (nome/modo) é barato e síncrono; o
     status só é refeito se algo aplicou/desfez ajustes nesse meio-tempo. */
  function aoVoltar() {
    if (!estado.montado) { return; }
    carregarSettings();
    if (estado.statusSujo) { carregarStatus(); }
  }

  var JOBS_QUE_MUDAM_STATUS = /^(plan\.(apply|undo)|tweaks?\.|mode\.|session\.undo|undo\.)/;
  var JOBS_QUE_MUDAM_PONTOS = /^(restore\.(create|delete)|session\.start)$/;

  function ligarGlobais() {
    document.addEventListener('tmx:lang', function () {
      if (!estado.montado) { return; }
      tmx.i18n.apply(document.getElementById('tab-painel'));
      pintarTudo();
    });
    document.addEventListener('tmx:settings', function (e) {
      if (!estado.montado || !e.detail) { return; }
      estado.settings = e.detail;
      pintarNome();
      pintarStatus();
    });
    tmx.bridge.on('job.done', function (p) {
      if (!estado.montado || !p || !p.name) { return; }
      if (JOBS_QUE_MUDAM_STATUS.test(p.name)) { estado.statusSujo = true; }
      if (p.ok && JOBS_QUE_MUDAM_PONTOS.test(p.name)) {
        if (p.result && p.result.pontos) {
          estado.pontos = p.result.pontos;
          pintarPonto();
        } else if (p.name === 'session.start') {
          carregarPontos();
        }
      }
    });
    var nav = document.querySelector('nav [data-tab="painel"]');
    if (nav) { nav.addEventListener('click', aoVoltar); }
  }

  var globaisLigados = false;

  window.tmxTabs.painel = {
    init: function () {
      if (!globaisLigados) { ligarGlobais(); globaisLigados = true; }
      estado.info = null;
      estado.infoErro = null;
      montar();
      pintarTudo();
      // Em fila: a ponte só roda um job por vez. O hardware é o que a
      // pessoa mais quer ver, então vem primeiro; o status (que relê o
      // estado de todo o catálogo) fica por último.
      var erroInfo = null;
      return carregarSettings()
        .then(carregarInfo)
        .catch(function (e) { erroInfo = e; })
        .then(carregarPontos)
        .then(carregarStatus)
        .then(function () { if (erroInfo) { throw erroInfo; } });
    }
  };
})();
