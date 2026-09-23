/* configure.js - aba "Configurar": recursos do Windows (DISM), correções de
 * manutenção, painéis legados e DNS.
 *
 * Ações síncronas: fixes.list, panels.list, panels.open, dns.list.
 * Ações que devolvem { jobId }: features.list, features.apply, features.undo,
 * fixes.run, dns.apply, dns.benchmark - o resultado real chega depois pelo
 * evento job.done, correlacionado aqui pelo jobId (a ponte não amarra id de
 * pedido a evento).
 *
 * Tudo que entra em HTML passa por escapar(): nome de adaptador, saída de
 * comando e descrição de recurso vêm do sistema, não de uma constante nossa.
 */
(function () {
  'use strict';
  window.tmxTabs = window.tmxTabs || {};

  var estado = {
    recursos: [],
    correcoes: [],
    paineis: [],
    dns: null,
    ocupado: false
  };

  /* ---------------- texto ---------------- */

  function escapar(s) {
    return String(s === null || s === undefined ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }

  function listaHtml(itens) {
    return '<ul class="cfg-lista-limpa">' + (itens || []).map(function (t) {
      return '<li>' + escapar(t) + '</li>';
    }).join('') + '</ul>';
  }

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

  /* A ponte aceita UM job por vez em todo o aplicativo, não só nesta aba: ao
     abrir a janela a aba Ajustes já dispara catalog.get, que lê o catálogo, o
     perfil e o estado do sistema e demora vários segundos. O primeiro
     features.list cairia direto em "já existe um trabalho em andamento" e a
     coluna de recursos nasceria com uma mensagem de erro. Aqui a carga
     inicial espera a vez em vez de desistir. */
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

  /* Um trabalho por vez é regra da própria ponte: sem esta trava dois cliques
     seguidos viram "já existe um trabalho em andamento" em vez de um aviso. */
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

  /* ---------------- recursos ---------------- */

  function selosRecurso(r) {
    var html = '';
    if (r.requerReboot) { html += '<span class="selo selo-reboot">Reboot</span>'; }
    if (r.reversivel === 'parcial') { html += '<span class="selo selo-parcial">Reversão parcial</span>'; }
    if (r.estado === 'desconhecido') { html += '<span class="selo selo-folclore">Estado desconhecido</span>'; }
    return html;
  }

  function renderRecursos() {
    var raiz = document.getElementById('cfg-recursos');
    if (!raiz) { return; }
    raiz.innerHTML = '';

    if (!estado.recursos.length) {
      raiz.innerHTML = '<p class="vazio">Nenhum recurso opcional disponível.</p>';
      return;
    }

    estado.recursos.forEach(function (r) {
      var ligado = (r.estado === 'Enabled');
      var linha = document.createElement('div');
      linha.className = 'feature';
      linha.id = 'feature-' + r.id;

      var idNome = 'feature-nome-' + r.id;
      linha.innerHTML =
        '<div class="feature-texto">' +
          '<span class="feature-nome" id="' + escapar(idNome) + '">' + escapar(r.nome) + '</span>' +
          '<span class="feature-desc">' + escapar(r.descricao) + '</span>' +
          (r.nota ? '<span class="feature-desc">' + escapar(r.nota) + '</span>' : '') +
          '<span class="feature-selos">' + selosRecurso(r) + '</span>' +
        '</div>' +
        '<div class="feature-acoes"></div>';

      var acoes = linha.querySelector('.feature-acoes');

      var sw = document.createElement('button');
      sw.type = 'button';
      sw.className = 'switch';
      sw.id = 'sw-' + r.id;
      sw.setAttribute('role', 'switch');
      sw.setAttribute('aria-checked', ligado ? 'true' : 'false');
      sw.setAttribute('aria-labelledby', idNome);
      sw.setAttribute('data-estado', r.estado);
      sw.addEventListener('click', function () { alternarRecurso(r, !ligado); });
      acoes.appendChild(sw);

      if (r.temUndo) {
        var undo = document.createElement('button');
        undo.type = 'button';
        undo.className = 'btn btn-mini';
        undo.id = 'undo-' + r.id;
        undo.textContent = 'Desfazer';
        undo.setAttribute('aria-label', 'Desfazer ' + r.nome);
        undo.addEventListener('click', function () { desfazerRecurso(r); });
        acoes.appendChild(undo);
      }

      raiz.appendChild(linha);
    });
  }

  function alternarRecurso(r, ligar) {
    tmx.session.ensure().then(function (ok) {
      if (!ok) { return; }

      var verbo = ligar ? 'Ativar' : 'Desativar';
      var oQue = (r.recursos && r.recursos.length)
        ? 'O DISM vai ' + (ligar ? 'habilitar' : 'desabilitar') + ' ' + r.recursos.length + ' componente(s): ' + r.recursos.join(', ') + '.'
        : 'O TweakMaxing vai ' + (ligar ? 'aplicar' : 'reverter') + ' a configuração deste recurso.';

      tmx.modal.open({
        titulo: verbo + ' ' + r.nome,
        html:
          '<p>' + escapar(oQue) + '</p>' +
          (r.requerReboot ? '<p>Pode pedir reinício do computador para concluir.</p>' : '') +
          (r.nota ? '<p>' + escapar(r.nota) + '</p>' : '') +
          '<p id="modal-progresso" class="sessao-progresso"></p>',
        botoes: [
          {
            rotulo: verbo,
            classe: 'btn-primary',
            mantemAberto: true,
            onClick: function () {
              if (!ocupar()) { return; }
              travarModal();
              pintarProgresso({ status: verbo + '…', pct: 0 });
              chamarJob('features.apply', { id: r.id, ligado: ligar }, pintarProgresso)
                .then(function (res) {
                  liberar();
                  tmx.modal.close();
                  aplicarCatalogoRecursos(res && res.catalogo);
                  mostrarResultadoRecurso(r, res);
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

  function mostrarResultadoRecurso(r, res) {
    var item = res && res.resultado && res.resultado.itens && res.resultado.itens[0];
    var status = item ? item.status : '';
    if (status === 'aplicado' || status === 'aplicadoNaoVerificado' || status === 'jaAplicado') {
      tmx.toast(r.nome + ': ' + status, 'ok');
    } else {
      tmx.toast(r.nome + ': ' + (status || 'sem resultado') + (item && item.detalhe ? ' — ' + item.detalhe : ''), 'erro');
    }
    if (res && res.resultado && res.resultado.requerReboot) {
      tmx.toast('Reinicie o computador para concluir', 'aviso');
    }
  }

  function desfazerRecurso(r) {
    tmx.modal.open({
      titulo: 'Desfazer ' + r.nome,
      html: '<p>Restaura o estado que este recurso tinha antes desta sessão.</p>' +
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
            chamarJob('features.undo', { id: r.id }, pintarProgresso)
              .then(function (res) {
                liberar();
                tmx.modal.close();
                aplicarCatalogoRecursos(res && res.catalogo);
                var s = (res && res.resumo) || {};
                tmx.toast(r.nome + ': ' + (s.revertidos || 0) + ' item(ns) revertido(s)', (s.falhas ? 'erro' : 'ok'));
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

  function aplicarCatalogoRecursos(c) {
    if (!c) { return; }
    estado.recursos = (c.recursos || []);
    renderRecursos();
  }

  function carregarRecursos() {
    var esperando = false;
    return chamarJobComEspera('features.list', null, null, function () {
      if (esperando) { return; }
      esperando = true;
      var raiz = document.getElementById('cfg-recursos');
      if (raiz) { raiz.innerHTML = '<p class="vazio">Esperando o trabalho em andamento terminar…</p>'; }
    }).then(function (c) {
      aplicarCatalogoRecursos(c);
      var sec = document.getElementById('tab-configurar');
      if (sec) { sec.setAttribute('aria-busy', 'false'); }
    }).catch(function (e) {
      var raiz = document.getElementById('cfg-recursos');
      if (raiz) { raiz.innerHTML = '<p class="vazio">Não foi possível ler os recursos: ' + escapar(e.message) + '</p>'; }
      // Repropaga: a mensagem inline acima (e o toast) já avisaram o
      // usuário, mas tabs.show precisa SABER que a carga falhou para
      // deixar a aba como não iniciada e tentar de novo na próxima
      // abertura. Engolir o erro aqui deixava a aba vazia para sempre.
      throw e;
    });
  }

  /* ---------------- correções ---------------- */

  function renderCorrecoes() {
    var raiz = document.getElementById('cfg-correcoes');
    if (!raiz) { return; }
    raiz.innerHTML = '';

    estado.correcoes.forEach(function (f) {
      var card = document.createElement('div');
      card.className = 'fix-card';
      card.id = 'fix-' + f.id;
      card.innerHTML =
        '<h4 class="fix-nome">' + escapar(f.nome) + '</h4>' +
        '<p class="fix-desc">' + escapar(f.descricao) + '</p>' +
        '<div class="fix-rodape"></div>';

      var rodape = card.querySelector('.fix-rodape');

      var botao = document.createElement('button');
      botao.type = 'button';
      botao.className = 'btn';
      botao.textContent = 'Executar';
      botao.setAttribute('aria-label', 'Executar: ' + f.nome);
      botao.addEventListener('click', function () { confirmarCorrecao(f); });
      rodape.appendChild(botao);

      if (f.requerSessao) {
        var selo = document.createElement('span');
        selo.className = 'selo selo-reboot';
        selo.textContent = 'Exige sessão';
        rodape.appendChild(selo);
      }

      raiz.appendChild(card);
    });
  }

  function confirmarCorrecao(f) {
    var abrir = function () {
      tmx.modal.open({
        titulo: f.nome,
        html:
          '<p>' + escapar(f.descricao) + '</p>' +
          '<p>O que será feito:</p>' + listaHtml(f.aviso) +
          (f.opcaoAgressiva
            ? '<p><label class="cfg-checkbox"><input type="checkbox" id="fix-agressivo"> Modo agressivo (renomeia SoftwareDistribution e catroot2)</label></p>'
            : '') +
          '<p id="modal-progresso" class="sessao-progresso"></p>',
        botoes: [
          {
            rotulo: 'Executar',
            classe: 'btn-primary',
            mantemAberto: true,
            onClick: function () {
              if (!ocupar()) { return; }
              var campo = document.getElementById('fix-agressivo');
              var agressivo = !!(campo && campo.checked);
              travarModal();
              pintarProgresso({ status: 'Executando…', pct: 0 });
              chamarJob('fixes.run', { id: f.id, aggressive: agressivo }, pintarProgresso)
                .then(function (res) {
                  liberar();
                  tmx.modal.close();
                  mostrarResultadoCorrecao(f, res);
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
    };

    if (f.requerSessao) {
      tmx.session.ensure().then(function (ok) { if (ok) { abrir(); } });
      return;
    }
    abrir();
  }

  function mostrarResultadoCorrecao(f, res) {
    var passos = (res && res.passos) || [];
    var linhas = passos.map(function (p) {
      return '<tr class="' + (p.ok ? 'res-ok' : 'res-falha') + '">' +
        '<td>' + escapar(p.nome) + '</td>' +
        '<td>' + (p.ok ? 'ok' : 'falha') + '</td>' +
        '</tr>' +
        (p.saida ? '<tr><td colspan="2"><pre class="cfg-saida">' + escapar(p.saida) + '</pre></td></tr>' : '');
    }).join('');

    tmx.modal.open({
      titulo: f.nome + (res && res.ok ? ' — concluída' : ' — com falhas'),
      html:
        '<p>' + escapar((res && res.detalhe) || '') + '</p>' +
        '<table class="cfg-tabela"><caption class="fix-desc">Passos executados</caption>' +
        '<thead><tr><th scope="col">Passo</th><th scope="col">Resultado</th></tr></thead>' +
        '<tbody>' + linhas + '</tbody></table>',
      botoes: [{ rotulo: 'Fechar', classe: 'btn-primary' }]
    });
    tmx.toast(f.nome + (res && res.ok ? ': concluída' : ': terminou com falhas'), (res && res.ok) ? 'ok' : 'erro');
  }

  function carregarCorrecoes() {
    return tmx.bridge.call('fixes.list').then(function (r) {
      estado.correcoes = (r && r.correcoes) || [];
      renderCorrecoes();
    }).catch(function (e) {
      var raiz = document.getElementById('cfg-correcoes');
      if (raiz) { raiz.innerHTML = '<p class="vazio">' + escapar(e.message) + '</p>'; }
      // Repropaga: a mensagem inline acima (e o toast) já avisaram o
      // usuário, mas tabs.show precisa SABER que a carga falhou para
      // deixar a aba como não iniciada e tentar de novo na próxima
      // abertura. Engolir o erro aqui deixava a aba vazia para sempre.
      throw e;
    });
  }

  /* ---------------- painéis ---------------- */

  function renderPaineis() {
    var raiz = document.getElementById('cfg-paineis');
    if (!raiz) { return; }
    raiz.innerHTML = '';

    estado.paineis.forEach(function (p) {
      var b = document.createElement('button');
      b.type = 'button';
      b.className = 'btn painel-btn';
      b.id = 'painel-' + p.id;
      b.textContent = p.nome;
      b.title = p.nome;
      b.setAttribute('aria-label', 'Abrir ' + p.nome);
      b.addEventListener('click', function () {
        tmx.bridge.call('panels.open', { id: p.id }).then(function (r) {
          tmx.toast((r && r.simulado) ? (p.nome + ': abertura simulada (modo de teste)') : ('Abrindo ' + p.nome), 'ok');
        }).catch(function (e) { tmx.toast(e.message, 'erro'); });
      });
      raiz.appendChild(b);
    });
  }

  function carregarPaineis() {
    return tmx.bridge.call('panels.list').then(function (r) {
      estado.paineis = (r && r.paineis) || [];
      renderPaineis();
    }).catch(function (e) {
      var raiz = document.getElementById('cfg-paineis');
      if (raiz) { raiz.innerHTML = '<p class="vazio">' + escapar(e.message) + '</p>'; }
      // Repropaga: a mensagem inline acima (e o toast) já avisaram o
      // usuário, mas tabs.show precisa SABER que a carga falhou para
      // deixar a aba como não iniciada e tentar de novo na próxima
      // abertura. Engolir o erro aqui deixava a aba vazia para sempre.
      throw e;
    });
  }

  /* ---------------- DNS ---------------- */

  function renderDns() {
    var raiz = document.getElementById('cfg-dns');
    if (!raiz) { return; }
    var d = estado.dns || { provedores: [], atual: [] };

    var opcoes = '<option value="dhcp">Padrão (DHCP)</option>' +
      (d.provedores || []).map(function (p) {
        return '<option value="' + escapar(p.id) + '">' + escapar(p.nome) + ' (' + escapar(p.primario) + ')</option>';
      }).join('');

    var atual = (d.atual || []).map(function (a) {
      var servidores = (a.v4 || []).concat(a.v6 || []);
      return a.nome + ': ' + (servidores.length ? servidores.join(', ') : 'DHCP');
    });

    raiz.innerHTML =
      '<div class="cfg-dns-linha">' +
        '<select id="dns-select" class="cfg-select" aria-label="Provedor de DNS">' + opcoes + '</select>' +
        '<button type="button" class="btn btn-primary" id="dns-aplicar" aria-label="Aplicar o provedor de DNS escolhido">Aplicar</button>' +
        '<button type="button" class="btn" id="dns-benchmark" aria-label="Medir a latência dos provedores de DNS">Testar latência</button>' +
      '</div>' +
      '<div class="cfg-dns-atual"><strong>Em uso agora:</strong>' +
        (atual.length ? listaHtml(atual) : ' nenhum adaptador conectado') +
      '</div>' +
      '<div id="dns-resultado"></div>';

    document.getElementById('dns-aplicar').addEventListener('click', aplicarDns);
    document.getElementById('dns-benchmark').addEventListener('click', medirDns);
  }

  function aplicarDns() {
    var campo = document.getElementById('dns-select');
    var provedor = campo ? campo.value : 'dhcp';
    var rotulo = (campo && campo.options[campo.selectedIndex]) ? campo.options[campo.selectedIndex].text : provedor;

    tmx.session.ensure().then(function (ok) {
      if (!ok) { return; }
      tmx.modal.open({
        titulo: 'Trocar o DNS',
        html:
          '<p>Todos os adaptadores conectados passarão a usar <strong>' + escapar(rotulo) + '</strong>.</p>' +
          '<p>Os servidores atuais de cada adaptador vão para o registro da sessão, então o Undo consegue devolvê-los.</p>' +
          '<p id="modal-progresso" class="sessao-progresso"></p>',
        botoes: [
          {
            rotulo: 'Aplicar',
            classe: 'btn-primary',
            mantemAberto: true,
            onClick: function () {
              if (!ocupar()) { return; }
              travarModal();
              pintarProgresso({ status: 'Aplicando…', pct: 0 });
              chamarJob('dns.apply', { provedor: provedor }, pintarProgresso)
                .then(function (res) {
                  liberar();
                  tmx.modal.close();
                  if (res && res.dns) { estado.dns = res.dns; renderDns(); }
                  var item = res && res.resultado && res.resultado.itens && res.resultado.itens[0];
                  tmx.toast('DNS: ' + ((item && item.status) || 'aplicado'), (item && item.status === 'falha') ? 'erro' : 'ok');
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

  function medirDns() {
    if (!ocupar()) { return; }
    var caixa = document.getElementById('dns-resultado');
    if (caixa) { caixa.innerHTML = '<p class="cfg-nota">Medindo…</p>'; }

    chamarJob('dns.benchmark', null, function (p) {
      if (caixa && p && p.status) { caixa.innerHTML = '<p class="cfg-nota">' + escapar(p.status) + '</p>'; }
    }).then(function (r) {
      liberar();
      var itens = (r && r.itens) || [];
      if (!caixa) { return; }
      if (!itens.length) {
        caixa.innerHTML = '<p class="cfg-nota">Nenhum provedor elegível para medição.</p>';
        return;
      }
      caixa.innerHTML =
        '<table class="cfg-tabela"><caption class="cfg-nota">Latência média, do mais rápido ao mais lento</caption>' +
        '<thead><tr><th scope="col">Provedor</th><th scope="col">Média</th><th scope="col">Falhas</th></tr></thead><tbody>' +
        itens.map(function (i) {
          var semResposta = (i.medioMs === null || i.medioMs === undefined);
          return '<tr' + (semResposta ? ' class="res-falha"' : '') + '>' +
            '<td>' + escapar(i.nome) + '</td>' +
            '<td class="num">' + (semResposta ? '—' : escapar(i.medioMs) + ' ms') + '</td>' +
            '<td class="num">' + escapar(i.falhas) + '</td>' +
            '</tr>';
        }).join('') +
        '</tbody></table>';
    }).catch(function (e) {
      liberar();
      if (caixa) { caixa.innerHTML = '<p class="cfg-nota">' + escapar(e.message) + '</p>'; }
      tmx.toast(e.message, 'erro');
    });
  }

  function carregarDns() {
    return tmx.bridge.call('dns.list').then(function (r) {
      estado.dns = r || { provedores: [], atual: [] };
      renderDns();
    }).catch(function (e) {
      var raiz = document.getElementById('cfg-dns');
      if (raiz) { raiz.innerHTML = '<p class="vazio">' + escapar(e.message) + '</p>'; }
      // Repropaga: a mensagem inline acima (e o toast) já avisaram o
      // usuário, mas tabs.show precisa SABER que a carga falhou para
      // deixar a aba como não iniciada e tentar de novo na próxima
      // abertura. Engolir o erro aqui deixava a aba vazia para sempre.
      throw e;
    });
  }

  /* ---------------- arranque ---------------- */

  window.tmxTabs.configurar = {
    init: function () {
      /* As três síncronas primeiro: a ponte serializa um job por vez, e
         features.list (que lê o DISM) pode demorar segundos - deixar as
         colunas de painéis e correções esperando por ela seria tela vazia
         à toa. A ordem de disparo continua a mesma: aguardarTodas só espera
         o desfecho, não serializa nada. */
      return tmx.aguardarTodas([
        carregarCorrecoes(),
        carregarPaineis(),
        carregarDns(),
        carregarRecursos()
      ]);
    }
  };
})();
