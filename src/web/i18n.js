/* i18n.js - framework de internacionalizacao (tmx.i18n).
 *
 * Carrega ANTES de app.js (ver index.html) para que window.tmx.i18n já
 * exista quando app.js registra as strings da casca (shell.*) e quando
 * qualquer outra tela (tweaks.js, install.js, ...) fizer o mesmo.
 *
 * Cada tela registra as PRÓPRIAS strings no PRÓPRIO arquivo, com chaves
 * prefixadas ('shell.*', 'painel.*', 'otim.*', ...):
 *
 *   tmx.i18n.add('pt-BR', { 'minhaTela.titulo': 'Título' });
 *   tmx.i18n.add('en',    { 'minhaTela.titulo': 'Title' });
 *
 * API:
 *   tmx.i18n.add(lang, mapa)   - funde 'mapa' (chave -> texto) no dicionário
 *                                de 'lang'. Chamadas repetidas para o mesmo
 *                                idioma se acumulam (não substituem o
 *                                dicionário inteiro).
 *   tmx.i18n.t(chave, vars)    - texto no idioma atual; cai para pt-BR se
 *                                faltar tradução, e devolve a própria chave
 *                                se não existir em nenhum dos dois. 'vars' é
 *                                um objeto para substituição {nome} -> valor.
 *   tmx.i18n.lang              - idioma atual ('pt-BR' | 'en'), leitura.
 *   tmx.i18n.set(lang)         - troca o idioma: aplica data-i18n/
 *                                data-i18n-title/data-i18n-placeholder em
 *                                todo o documento, dispara o evento
 *                                'tmx:lang' ({ detail: { lang } }) e salva
 *                                via settings.set (ignora falha - a ação
 *                                pode não existir ainda).
 *   tmx.i18n.apply(raiz)       - reaplica data-i18n* dentro de 'raiz' (usado
 *                                por uma tela depois de remontar seu próprio
 *                                esqueleto via innerHTML).
 *
 * Primeira abertura: sem 'language' salvo, mostra #welcome (dois botões
 * grandes, ver index.html) e só esconde quando a pessoa escolhe um idioma.
 * Se settings.get falhar (ação ainda não existe nesta onda), o idioma vira
 * pt-BR e a tela de boas-vindas aparece mesmo assim, mas só uma vez por
 * sessão - sem isso ela voltaria toda vez que algo chamasse tmx.i18n de novo.
 */
(function () {
  'use strict';

  window.tmx = window.tmx || {};

  var dict = { 'pt-BR': {}, en: {} };
  var langAtual = 'pt-BR';
  var welcomeJaMostrada = false;

  function add(lang, mapa) {
    if (!lang || !mapa) { return; }
    if (!dict[lang]) { dict[lang] = {}; }
    for (var chave in mapa) {
      if (Object.prototype.hasOwnProperty.call(mapa, chave)) { dict[lang][chave] = mapa[chave]; }
    }
  }

  function t(chave, vars) {
    var texto = dict[langAtual] ? dict[langAtual][chave] : undefined;
    if (texto === undefined && dict['pt-BR']) { texto = dict['pt-BR'][chave]; }
    if (texto === undefined) { return chave; }
    if (vars) {
      texto = texto.replace(/\{(\w+)\}/g, function (m, nome) {
        var v = vars[nome];
        return (v === undefined || v === null) ? m : String(v);
      });
    }
    return texto;
  }

  function aplicar(raiz) {
    raiz = raiz || document;
    var i, els;

    els = raiz.querySelectorAll('[data-i18n]');
    for (i = 0; i < els.length; i++) { els[i].textContent = t(els[i].getAttribute('data-i18n')); }

    els = raiz.querySelectorAll('[data-i18n-title]');
    for (i = 0; i < els.length; i++) { els[i].title = t(els[i].getAttribute('data-i18n-title')); }

    els = raiz.querySelectorAll('[data-i18n-placeholder]');
    for (i = 0; i < els.length; i++) { els[i].placeholder = t(els[i].getAttribute('data-i18n-placeholder')); }
  }

  function persistir(lang) {
    if (!window.tmx || !tmx.bridge || !tmx.bridge.disponivel) { return; }
    tmx.bridge.call('settings.set', { language: lang }).catch(function () {
      // settings.set pode nao existir ainda (T4/Actions.System.ps1 fora
      // desta onda): a troca de idioma continua valendo so nesta sessao.
    });
  }

  function set(lang, opcoes) {
    if (lang !== 'pt-BR' && lang !== 'en') { lang = 'pt-BR'; }
    langAtual = lang;
    document.documentElement.setAttribute('lang', lang);
    aplicar(document);
    document.dispatchEvent(new CustomEvent('tmx:lang', { detail: { lang: lang } }));
    if (!opcoes || opcoes.persistir !== false) { persistir(lang); }
  }

  function esconderWelcome() {
    var el = document.getElementById('welcome');
    if (el) { el.hidden = true; }
  }

  function mostrarWelcome() {
    if (welcomeJaMostrada) { return; }
    welcomeJaMostrada = true;
    var el = document.getElementById('welcome');
    if (el) { el.hidden = false; }
  }

  function ligarBotoesWelcome() {
    var botoes = document.querySelectorAll('#welcome [data-lang]');
    for (var i = 0; i < botoes.length; i++) {
      botoes[i].addEventListener('click', function (e) {
        var lang = e.currentTarget.getAttribute('data-lang');
        set(lang);
        esconderWelcome();
      });
    }
  }

  function iniciar() {
    ligarBotoesWelcome();

    if (!window.tmx || !tmx.bridge || !tmx.bridge.disponivel) {
      set('pt-BR', { persistir: false });
      mostrarWelcome();
      return;
    }

    tmx.bridge.call('settings.get').then(function (s) {
      var lang = s && s.language;
      if (lang === 'pt-BR' || lang === 'en') {
        set(lang, { persistir: false });
        return;
      }
      set('pt-BR', { persistir: false });
      mostrarWelcome();
    }).catch(function () {
      // settings.get pode nao existir ainda (T4 fora desta onda): trata como
      // primeira abertura, sem persistir a escolha de volta (nao ha onde).
      set('pt-BR', { persistir: false });
      mostrarWelcome();
    });
  }

  window.tmx.i18n = {
    add: add,
    t: t,
    set: set,
    apply: aplicar,
    get lang() { return langAtual; }
  };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', iniciar);
  } else {
    iniciar();
  }
})();
