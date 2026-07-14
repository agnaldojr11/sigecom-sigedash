// SigeDash — Orquestrador v2: navegação, seções, dados, login/logout, assistente IA.
Chart.defaults.color = '#94a3b8';
Chart.defaults.font.family = 'system-ui, -apple-system, sans-serif';
Chart.defaults.font.size = 12;

let _snaps = {};
let _secAtiva = '';
let _timerRefresh = null;
let _timerHeartbeat = null;
let _encerrando = false;
const AUTO_REFRESH_MS = 5 * 60 * 1000; // 5 minutos
const HEARTBEAT_MS = 10 * 1000;        // checagem de sessão (queda rápida ao logar em outro lugar)

const TITULOS_SEC = {
  resumo: 'SigeDash',
  vendas: 'Vendas',
  estoque: 'Estoque',
  financeiro: 'Financeiro'
};

// Ordem das seções (para escolher a aba inicial) e rótulos p/ a tela de permissões
const ORDEM_SEC     = ['resumo', 'vendas', 'estoque', 'financeiro'];
const SECOES_LABEL  = { resumo: 'Resumo', vendas: 'Vendas', estoque: 'Estoque', financeiro: 'Financeiro' };
const TIPOS_USUARIO = { 1: 'Administrador', 2: 'Secretário(a)', 3: 'Vendedor(a)', 4: 'Técnico(a)' };

// Itens da tela de Permissões: seções (On/Off) e sub-permissões dentro de uma seção
const PERM_ITENS = [
  { key: 'resumo',     label: 'Resumo' },
  { key: 'vendas',     label: 'Vendas' },
  { key: 'estoque',    label: 'Estoque', subs: [ { key: 'estoque_custo', label: 'Ver preço de custo' } ] },
  { key: 'financeiro', label: 'Financeiro' }
];
// Seções que caracterizam acesso a BI (para exibir o assistente IA)
const SECOES_BI = ['resumo', 'vendas', 'financeiro'];

function _secaoPermitida(sec) { return API.secoes().indexOf(sec) >= 0; }

// ── Ícones de cabeçalho de grupo (sem deps externas) ──────────────────────
function _sgIco(d, cor) {
  var bg = {
    '#3b82f6': 'rgba(59,130,246,.14)',
    '#34d399': 'rgba(52,211,153,.14)',
    '#f97316': 'rgba(249,115,22,.14)',
    '#f87171': 'rgba(248,113,113,.14)',
    '#fbbf24': 'rgba(251,191,36,.14)',
    '#a78bfa': 'rgba(167,139,250,.14)',
  }[cor] || 'rgba(59,130,246,.14)';
  return '<span class="sec-grupo-ico" style="background:' + bg + ';color:' + cor + '">' +
    '<svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">' + d + '</svg>' +
  '</span>';
}

const GRUPOS_ICO = {
  'Hoje':                { d: '<polyline points="23 6 13.5 15.5 8.5 10.5 1 18"/><polyline points="17 6 23 6 23 12"/>',                           cor: '#3b82f6' },
  'Totais do Período':   { d: '<rect x="3" y="4" width="18" height="18" rx="2"/><line x1="16" y1="2" x2="16" y2="6"/><line x1="8" y1="2" x2="8" y2="6"/><line x1="3" y1="10" x2="21" y2="10"/>',  cor: '#3b82f6' },
  'Pico de Vendas':      { d: '<circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/>',                                            cor: '#3b82f6' },
  'Rankings do Mês':     { d: '<circle cx="12" cy="8" r="6"/><path d="M15.477 12.89 17 22l-5-3-5 3 1.523-9.11"/>',                               cor: '#fbbf24' },
  'Análise do Mês':      { d: '<line x1="18" y1="20" x2="18" y2="10"/><line x1="12" y1="20" x2="12" y2="4"/><line x1="6" y1="20" x2="6" y2="14"/>',  cor: '#a78bfa' },
  'Maiores Estoques':    { d: '<path d="M21 16V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16z"/><polyline points="3.27 6.96 12 12.01 20.73 6.96"/><line x1="12" y1="22.08" x2="12" y2="12"/>',  cor: '#34d399' },
  'Alertas':             { d: '<path d="M10.29 3.86 1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/>',  cor: '#f87171' },
  'Contas a Receber':    { d: '<circle cx="12" cy="12" r="10"/><polyline points="8 12 12 16 16 12"/><line x1="12" y1="8" x2="12" y2="16"/>',      cor: '#34d399' },
  'Contas a Pagar':      { d: '<circle cx="12" cy="12" r="10"/><polyline points="16 12 12 8 8 12"/><line x1="12" y1="16" x2="12" y2="8"/>',       cor: '#f97316' },
  'Alertas Financeiros': { d: '<polygon points="7.86 2 16.14 2 22 7.86 22 16.14 16.14 22 7.86 22 2 16.14 2 7.86 7.86 2"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/>',  cor: '#f87171' },
  'Saldo Diário':        { d: '<line x1="12" y1="1" x2="12" y2="23"/><path d="M17 5H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6"/>',            cor: '#a78bfa' },
};

function secGrupo(texto) {
  var g = GRUPOS_ICO[texto];
  var h = document.createElement('div');
  h.className = 'sec-grupo';
  h.innerHTML = (g ? _sgIco(g.d, g.cor) : '') + texto;
  return h;
}

// ── Navegação ──────────────────────────────────────────────────────────────
function navegar(sec) {
  if (!_secaoPermitida(sec)) return;   // trava de navegação (UI); o /dash trava os dados
  if (_secAtiva === sec) return;
  _secAtiva = sec;
  document.querySelectorAll('.sec').forEach(function(s) { s.classList.remove('ativa'); });
  document.getElementById('sec-' + sec).classList.add('ativa');
  document.querySelectorAll('.nav-btn').forEach(function(b) {
    var ativo = b.dataset.sec === sec;
    b.classList.toggle('ativo', ativo);
    b.setAttribute('aria-current', ativo ? 'page' : 'false');
  });
  document.getElementById('topo-titulo').textContent = TITULOS_SEC[sec] || 'SigeDash';
  renderSecao(sec);
}

function renderSecao(sec) {
  var el = document.getElementById('sec-' + sec);
  if (!el) return;
  var fns = { resumo: renderResumo, vendas: renderVendas, estoque: renderEstoque, financeiro: renderFinanceiro };
  (fns[sec] || renderResumo)(el);
}

// ── Resumo ─────────────────────────────────────────────────────────────────
function renderResumo(el) {
  el.innerHTML = '';

  var hr = new Date().getHours();
  var sauda = hr < 12 ? 'Bom dia' : hr < 18 ? 'Boa tarde' : 'Boa noite';
  var usuario = (sessionStorage.getItem('sd_login') || 'usuário').toUpperCase();
  var data = new Date().toLocaleDateString('pt-BR', { weekday:'long', day:'2-digit', month:'short', year:'numeric' });

  var saud = document.createElement('div');
  saud.className = 'saudacao';
  saud.innerHTML =
    '<span class="saudacao-nome">' + sauda + ', <strong>' + usuario + '</strong></span>' +
    '<span class="saudacao-data">' + data + '</span>';
  el.appendChild(saud);

  var grid = document.createElement('div');
  grid.className = 'kpi-grid';

  // KPI: Vendas Hoje
  var sv = _snaps['vendas_total_hoje'];
  if (sv) {
    var vd = Render.parseSnap(sv).dados;
    var vv = vd[0] ? Number(vd[0].value != null ? vd[0].value : 0) : 0;
    grid.appendChild(Render.kpiCard('Vendas Hoje', Render.moeda(vv), 'hoje', 'azul', Render.ICO.trendingUp));
  } else {
    grid.appendChild(Render.kpiCard('Vendas Hoje', '—', 'sem dados', 'azul', Render.ICO.trendingUp));
  }

  // KPI: Pedidos Hoje
  var sq = _snaps['vendas_qtd_pedidos'];
  if (sq) {
    var qd = Render.parseSnap(sq).dados;
    var qq = qd[0] ? Number(qd[0].value != null ? qd[0].value : 0) : 0;
    grid.appendChild(Render.kpiCard('Pedidos Hoje', String(qq), 'pedidos realizados', 'azul', Render.ICO.cart));
  } else {
    grid.appendChild(Render.kpiCard('Pedidos Hoje', '—', 'sem dados', 'azul', Render.ICO.cart));
  }

  // KPI: Alertas Estoque
  var se = _snaps['estoque_abaixo_min'];
  if (se) {
    var ed = Render.parseSnap(se).dados;
    var eq = ed.length;
    var ecor = eq > 5 ? 'vermelho' : eq > 0 ? 'laranja' : 'verde';
    var esub = eq === 0 ? 'estoque OK' : eq === 1 ? '1 item abaixo do mín.' : eq + ' itens abaixo do mín.';
    grid.appendChild(Render.kpiCard('Alertas Estoque', String(eq), esub, ecor, Render.ICO.alertTri));
  } else {
    grid.appendChild(Render.kpiCard('Alertas Estoque', '—', 'sem dados', 'laranja', Render.ICO.alertTri));
  }

  // KPI: Inadimplência
  var si = _snaps['financeiro_inadimplencia'];
  if (si) {
    var id = Render.parseSnap(si).dados;
    var iv = id[0] ? Number(id[0].value != null ? id[0].value : 0) : 0;
    var icor = iv > 0 ? 'vermelho' : 'verde';
    var isub = iv > 0 ? (id[0].sub || 'vencidos') : 'sem inadimplência';
    grid.appendChild(Render.kpiCard('Inadimplência', Render.moeda(iv), isub, icor, Render.ICO.alertOct));
  } else {
    grid.appendChild(Render.kpiCard('Inadimplência', '—', 'sem dados', 'vermelho', Render.ICO.alertOct));
  }

  el.appendChild(grid);

  var sp = _snaps['vendas_top_produtos'];
  if (sp) el.appendChild(Render.indicador(sp));

  var ts = document.createElement('p');
  ts.className = 'atualizado-em';
  ts.textContent = 'Atualizado em ' + new Date().toLocaleString('pt-BR');
  el.appendChild(ts);
}

// ── Vendas ─────────────────────────────────────────────────────────────────
function renderVendas(el) {
  el.innerHTML = '';
  var grupos = [
    { titulo: 'Hoje',            handles: ['vendas_total_hoje','vendas_qtd_pedidos','vendas_ticket_medio'] },
    { titulo: 'Totais do Período', handles: ['vendas_total_mes','vendas_total_semana'] },
    { titulo: 'Pico de Vendas',  handles: ['vendas_pico_horario'] },
    { titulo: 'Rankings do Mês', handles: ['vendas_top_clientes','vendas_top_produtos','vendas_top_vendedores'] },
    { titulo: 'Análise do Mês',  handles: ['vendas_forma_pagamento','vendas_custo_venda'] },
  ];
  var temAlgum = false;
  grupos.forEach(function(g) {
    var disp = g.handles.filter(function(h) { return _snaps[h]; });
    if (!disp.length) return;
    temAlgum = true;
    el.appendChild(secGrupo(g.titulo));
    disp.forEach(function(h) { el.appendChild(Render.indicador(_snaps[h])); });
  });
  if (!temAlgum) el.appendChild(Render.emptyState('Sem dados de vendas', 'Execute o agente para carregar os indicadores de vendas.'));
}

// ── Estoque ────────────────────────────────────────────────────────────────
var _estTopN  = 10;
var _estBuscaQ = '';

function renderEstoque(el) {
  el.innerHTML = '';
  _estTopN = 10;

  var buscaWrap = document.createElement('div');
  buscaWrap.className = 'sec-busca-wrap';
  buscaWrap.innerHTML =
    '<div class="sec-busca-inner">' +
      '<svg class="sec-busca-ico" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' +
        '<circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/>' +
      '</svg>' +
      '<input id="est-busca" class="sec-busca-input" type="search" ' +
        'placeholder="Pesquisar produto…" value="' + _escHtml(_estBuscaQ) + '" ' +
        'autocomplete="off" inputmode="search" aria-label="Pesquisar produto">' +
    '</div>';
  el.appendChild(buscaWrap);

  var conteudoEl = document.createElement('div');
  el.appendChild(conteudoEl);

  document.getElementById('est-busca').addEventListener('input', function() {
    _estBuscaQ = this.value.trim();
    _estTopN = 10;
    _estRenderConteudo(conteudoEl);
  });

  _estRenderConteudo(conteudoEl);
}

function _estRenderConteudo(el) {
  el.innerHTML = '';
  if (_estBuscaQ.length > 0) {
    _estRenderBusca(el, _estBuscaQ);
  } else {
    _estRenderCards(el);
  }
}

function _estRenderCards(el) {
  var snapTop = _snaps['estoque_top_produtos'];
  var temAlgum = false;

  if (snapTop) {
    temAlgum = true;
    var dados = Render.parseSnap(snapTop).dados;
    el.appendChild(secGrupo('Maiores Estoques'));
    el.appendChild(Render.indicador(snapTop, { limit: _estTopN }));
    if (_estTopN < dados.length) {
      var restante = Math.min(10, dados.length - _estTopN);
      var btnMais = document.createElement('button');
      btnMais.className = 'btn-carregar-mais';
      btnMais.textContent = 'Carregar mais ' + restante + ' produtos';
      btnMais.addEventListener('click', function() {
        _estTopN += 10;
        _estRenderConteudo(el);
      });
      el.appendChild(btnMais);
    }
  }

  var alertasDisp = ['estoque_sem_estoque', 'estoque_abaixo_min'].filter(function(h) { return _snaps[h]; });
  if (alertasDisp.length) {
    temAlgum = true;
    el.appendChild(secGrupo('Alertas'));
    alertasDisp.forEach(function(h) { el.appendChild(Render.indicador(_snaps[h])); });
  }

  if (!temAlgum) {
    el.appendChild(Render.emptyState('Sem dados de estoque', 'Execute o agente para carregar os indicadores de estoque.'));
  }
}

// Agrupa as linhas do snapshot (uma por produto x tabela de preço) em produtos
// com uma lista de preços. Memoizado pelo timestamp do snapshot (evita reagrupar a cada tecla).
var _estCache = null;
function _estProdutos(snap) {
  if (_estCache && _estCache.key === snap.geradoEm) return _estCache.lista;
  var dados = Render.parseSnap(snap).dados || [];
  var mapa = {}, ordem = [];
  dados.forEach(function(d) {
    var nome = d.label || '';
    var g = mapa[nome];
    if (!g) { g = mapa[nome] = { label: nome, estoque: 0, custo: 0, precos: [] }; ordem.push(g); }
    var est = Number(d.estoque != null ? d.estoque : 0);
    var cus = Number(d.custo   != null ? d.custo   : 0);
    if (est > g.estoque) g.estoque = est;
    if (cus > g.custo)   g.custo   = cus;
    var venda = Number(d.venda != null ? d.venda : 0);
    if (venda > 0) g.precos.push({ cod: Number(d.codTabela || 0), tabela: d.tabela || '', venda: venda });
  });
  ordem.forEach(function(g) { g.precos.sort(function(a, b) { return a.cod - b.cod; }); });
  _estCache = { key: snap.geradoEm, lista: ordem };
  return ordem;
}

function _estRenderBusca(el, q) {
  var snap = _snaps['estoque_pesquisa_produto'];
  if (!snap) {
    el.appendChild(Render.emptyState('Dados ainda não sincronizados', 'O agente sincroniza a busca de produtos a cada 30 minutos.'));
    return;
  }

  var ql = q.toLowerCase();
  var filtrados = _estProdutos(snap).filter(function(p) {
    return (p.label || '').toLowerCase().indexOf(ql) >= 0;
  });

  if (!filtrados.length) {
    el.appendChild(Render.emptyState('Nenhum resultado', 'Nenhum produto com esse nome foi encontrado.'));
    return;
  }

  var cab = document.createElement('div');
  cab.className = 'busca-cabecalho';
  cab.textContent = filtrados.length + (filtrados.length === 1 ? ' produto' : ' produtos') + ' para "' + q + '"';
  el.appendChild(cab);

  // Teto de exibicao: o snapshot traz todos os produtos ativos (milhares); uma busca
  // curta pode casar com muitos itens. Mostramos os primeiros e pedimos para refinar.
  var MAX_EXIBIR = 100;
  var exibidos = filtrados.slice(0, MAX_EXIBIR);

  exibidos.forEach(function(p) {
    var estoque = p.estoque, custo = p.custo, precos = p.precos;
    var semEst  = estoque <= 0;
    var estStr  = estoque.toLocaleString('pt-BR', { maximumFractionDigits: 2 }) + ' un';

    var det = '<span class="' + (semEst ? 'tag-vencido' : 'tag-ok') + '">' + estStr + '</span>';
    if (custo > 0) det += ' &middot; Custo ' + Render.moeda(custo);
    // Preço único fica inline; múltiplas tabelas viram uma lista de chips abaixo
    if (precos.length === 1) det += ' &middot; Venda ' + Render.moeda(precos[0].venda);

    var precosHtml = '';
    if (precos.length > 1) {
      precosHtml = '<div class="busca-precos">' + precos.map(function(pr) {
        return '<span class="preco-chip"><span class="preco-tab">' + _escHtml(pr.tabela || 'Tabela') +
               '</span>' + Render.moeda(pr.venda) + '</span>';
      }).join('') + '</div>';
    }

    var item = document.createElement('div');
    item.className = 'busca-item';
    item.innerHTML =
      '<div class="busca-item-info">' +
        '<div class="busca-item-nome">' + _escHtml(p.label) + '</div>' +
        '<div class="busca-item-det">' + det + '</div>' +
        precosHtml +
      '</div>';
    el.appendChild(item);
  });

  if (filtrados.length > MAX_EXIBIR) {
    var aviso = document.createElement('div');
    aviso.className = 'busca-cabecalho';
    aviso.textContent = 'Mostrando os primeiros ' + MAX_EXIBIR + ' de ' + filtrados.length +
      ' — digite mais para refinar a busca.';
    el.appendChild(aviso);
  }
}

// ── Financeiro ─────────────────────────────────────────────────────────────
var _finBuscaQ = '';

function renderFinanceiro(el) {
  el.innerHTML = '';

  // Barra de busca
  var buscaWrap = document.createElement('div');
  buscaWrap.className = 'sec-busca-wrap';
  buscaWrap.innerHTML =
    '<div class="sec-busca-inner">' +
      '<svg class="sec-busca-ico" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' +
        '<circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/>' +
      '</svg>' +
      '<input id="fin-busca" class="sec-busca-input" type="search" ' +
        'placeholder="Buscar cliente ou fornecedor…" value="' + _escHtml(_finBuscaQ) + '" ' +
        'autocomplete="off" inputmode="search" aria-label="Pesquisar">' +
    '</div>';
  el.appendChild(buscaWrap);

  var conteudoEl = document.createElement('div');
  el.appendChild(conteudoEl);

  document.getElementById('fin-busca').addEventListener('input', function() {
    _finBuscaQ = this.value.trim();
    _finRenderConteudo(conteudoEl);
  });

  _finRenderConteudo(conteudoEl);
}

function _finRenderConteudo(el) {
  el.innerHTML = '';
  if (_finBuscaQ.length > 0) {
    _finRenderBusca(el, _finBuscaQ);
  } else {
    _finRenderCards(el);
  }
}

function _finRenderCards(el) {
  var grupos = [
    { titulo: 'Contas a Receber',    handles: ['financeiro_receber_mes','financeiro_receber_semana','financeiro_receber_hoje'] },
    { titulo: 'Contas a Pagar',      handles: ['financeiro_pagar_mes','financeiro_pagar_semana','financeiro_pagar_hoje'] },
    { titulo: 'Alertas Financeiros', handles: ['financeiro_inadimplencia','financeiro_vencimentos_proximos'] },
    { titulo: 'Saldo Diário',        handles: ['saldo_caixas','saldo_bancario'] },
  ];
  var temAlgum = false;
  grupos.forEach(function(g) {
    var disp = g.handles.filter(function(h) { return _snaps[h]; });
    if (!disp.length) return;
    temAlgum = true;
    el.appendChild(secGrupo(g.titulo));
    disp.forEach(function(h) { el.appendChild(Render.indicador(_snaps[h])); });
  });
  if (!temAlgum) el.appendChild(Render.emptyState('Aguardando sincronização', 'Execute o agente para carregar os indicadores financeiros.'));
}

function _finRenderBusca(el, q) {
  var snap = _snaps['receber_por_cliente'];
  if (!snap) {
    el.appendChild(Render.emptyState('Dados ainda não sincronizados', 'O agente sincroniza contas a receber a cada 15 minutos.'));
    return;
  }

  var dados = Render.parseSnap(snap).dados;
  var hoje = new Date(); hoje.setHours(0, 0, 0, 0);
  var ql = q.toLowerCase();

  var filtrados = dados.filter(function(d) {
    return (d.label || '').toLowerCase().indexOf(ql) >= 0;
  });

  if (!filtrados.length) {
    el.appendChild(Render.emptyState('Nenhum resultado', 'Nenhum cliente com esse nome possui contas em aberto.'));
    return;
  }

  var cab = document.createElement('div');
  cab.className = 'busca-cabecalho';
  cab.textContent = filtrados.length + (filtrados.length === 1 ? ' resultado' : ' resultados') + ' para "' + q + '"';
  el.appendChild(cab);

  filtrados.forEach(function(d) {
    var nome     = d.label || '';
    var total    = Number(d.value || 0);
    var parcelas = Number(d.parcelas || 1);
    var vencDate = d.venc_mais_antigo ? new Date(d.venc_mais_antigo) : null;
    if (vencDate) vencDate.setHours(0, 0, 0, 0);
    var vencido  = vencDate && vencDate < hoje;
    var vencFmt  = vencDate ? vencDate.toLocaleDateString('pt-BR', { day:'2-digit', month:'2-digit', year:'numeric' }) : '';

    var parStr = parcelas === 1 ? '1 parcela' : parcelas + ' parcelas';
    var vencTag = vencDate
      ? ' &middot; <span class="' + (vencido ? 'tag-vencido' : 'tag-ok') + '">' +
          (vencido ? 'Venceu ' : 'Vence ') + vencFmt + '</span>'
      : '';

    var item = document.createElement('div');
    item.className = 'busca-item';
    item.innerHTML =
      '<div class="busca-item-info">' +
        '<div class="busca-item-nome">' + _escHtml(nome) + '</div>' +
        '<div class="busca-item-det">' + parStr + vencTag + '</div>' +
      '</div>' +
      '<div class="busca-item-valor' + (vencido ? ' vencido' : '') + '">' + Render.moeda(total) + '</div>';
    el.appendChild(item);
  });
}

// ── Dados ──────────────────────────────────────────────────────────────────
async function carregarDados() {
  try {
    var lista = await API.dashboards(1);
    _snaps = {};
    lista.forEach(function(s) { _snaps[s.indicadorHandle] = s; });
    renderSecao(_secAtiva);
  } catch (e) {
    if (e && e.sessaoEncerrada) { tratarQuedaSessao(e); return; }
    var el = document.getElementById('sec-' + _secAtiva);
    if (el) { el.innerHTML = ''; el.appendChild(Render.emptyState('Erro ao carregar', e.message)); }
  }
}

// ── Assistente IA ──────────────────────────────────────────────────────────
var fabIA       = document.getElementById('btn-ia');
var overlayIA   = document.getElementById('overlay-ia');
var btnFecharIA = document.getElementById('btn-fechar-ia');
var iaMsgsEl    = document.getElementById('ia-msgs');
var iaInputEl   = document.getElementById('ia-input');
var iaSendBtn   = document.getElementById('ia-send');
var iaSugestoes = document.getElementById('ia-sugestoes');

fabIA.addEventListener('click', function() {
  overlayIA.hidden = false;
  iaInputEl.focus();
});

btnFecharIA.addEventListener('click', function() { overlayIA.hidden = true; });

iaSugestoes.addEventListener('click', function(e) {
  var chip = e.target.closest('.ia-chip');
  if (chip) enviarPerguntaIA(chip.textContent.trim());
});

iaSendBtn.addEventListener('click', function() { enviarPerguntaIA(iaInputEl.value.trim()); });

iaInputEl.addEventListener('keydown', function(e) {
  if (e.key === 'Enter') enviarPerguntaIA(iaInputEl.value.trim());
});

function adicionarMsgIA(texto, tipo) {
  var chips = iaMsgsEl.querySelector('.ia-chips');
  if (tipo === 'usuario' && chips) chips.remove();
  var msg = document.createElement('div');
  msg.className = 'ia-msg ' + tipo;
  msg.textContent = texto;
  iaMsgsEl.appendChild(msg);
  iaMsgsEl.scrollTop = iaMsgsEl.scrollHeight;
  return msg;
}

function formatarContextoIA() {
  return Object.values(_snaps).map(function(snap) {
    var parsed = Render.parseSnap(snap);
    var resumo = parsed.dados.slice(0, 5).map(function(d) {
      var label = (d.label || d.nome || '').trim();
      var val = Number(d.value != null ? d.value : (d.valor != null ? d.valor : 0));
      var fmt = val.toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });
      return label ? label + ': ' + fmt : fmt;
    }).join(' | ');
    return { titulo: parsed.titulo, resumo: resumo || '(sem dados)' };
  });
}

async function enviarPerguntaIA(pergunta) {
  if (!pergunta) return;
  iaInputEl.value = '';
  iaSendBtn.disabled = true;
  adicionarMsgIA(pergunta, 'usuario');
  var loadingMsg = adicionarMsgIA('Consultando…', 'ia loading');
  try {
    var ctx = formatarContextoIA();
    var result = await API.queryIA(pergunta, ctx);
    loadingMsg.textContent = result.resposta;
    loadingMsg.classList.remove('loading');
  } catch (e) {
    if (e && e.sessaoEncerrada) { overlayIA.hidden = true; tratarQuedaSessao(e); return; }
    loadingMsg.textContent = 'Erro: ' + e.message;
    loadingMsg.classList.remove('loading');
  } finally {
    iaSendBtn.disabled = false;
    iaInputEl.focus();
  }
}

// ── Utilitários ────────────────────────────────────────────────────────────
function _escHtml(s) {
  return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}

// ── Permissões (admin) ───────────────────────────────────────────────────────
var overlayPerm = document.getElementById('overlay-perm');
document.getElementById('btn-permissoes').addEventListener('click', abrirPermissoes);
document.getElementById('btn-fechar-perm').addEventListener('click', function() { overlayPerm.hidden = true; });

function abrirPermissoes() {
  var body = document.getElementById('perm-body');
  body.innerHTML = '<p class="perm-aviso">Carregando usuários…</p>';
  overlayPerm.hidden = false;
  API.listarUsuarios().then(function(usuarios) {
    body.innerHTML = '';
    if (!usuarios || !usuarios.length) {
      body.appendChild(Render.emptyState('Nenhum usuário', 'Os usuários são sincronizados do SIGECOM pelo agente.'));
      return;
    }
    usuarios.forEach(function(u) { body.appendChild(_permCard(u)); });
  }).catch(function(e) {
    if (e && e.sessaoEncerrada) { overlayPerm.hidden = true; tratarQuedaSessao(e); return; }
    body.innerHTML = '<p class="perm-aviso erro">' + _escHtml(e.message) + '</p>';
  });
}

function _permCard(u) {
  var card = document.createElement('div');
  card.className = 'perm-card';
  var tipo = TIPOS_USUARIO[u.codigoTipo] || 'Usuário';

  var head = document.createElement('div');
  head.className = 'perm-card-head';
  head.innerHTML =
    '<div class="perm-user">' +
      '<span class="perm-user-nome">' + _escHtml(u.login) + '</span>' +
      '<span class="perm-user-tipo">' + _escHtml(tipo) + '</span>' +
    '</div>' +
    '<span class="perm-status" aria-live="polite"></span>';
  card.appendChild(head);

  if (u.admin) {
    var nota = document.createElement('div');
    nota.className = 'perm-admin-nota';
    nota.textContent = 'Administrador — vê todas as seções.';
    card.appendChild(nota);
    return card;
  }

  var atuais = u.secoes || [];
  var opts = document.createElement('div');
  opts.className = 'perm-opts';
  PERM_ITENS.forEach(function(it) {
    opts.appendChild(_permLinha(it.key, it.label, atuais.indexOf(it.key) >= 0, null));
    if (it.subs) it.subs.forEach(function(sub) {
      opts.appendChild(_permLinha(sub.key, sub.label, atuais.indexOf(sub.key) >= 0, it.key));
    });
  });
  card.appendChild(opts);

  // Sub-permissão só vale com a seção pai ligada: habilita/desabilita conforme o pai
  function sincronizarSubs() {
    opts.querySelectorAll('input[data-parent]').forEach(function(sub) {
      var pai = opts.querySelector('input[value="' + sub.getAttribute('data-parent') + '"]');
      var ligado = pai && pai.checked;
      sub.disabled = !ligado;
      if (!ligado) sub.checked = false;
      sub.closest('.perm-opt').classList.toggle('desabilitado', !ligado);
    });
  }
  sincronizarSubs();

  opts.addEventListener('change', function() {
    sincronizarSubs();
    var marcadas = Array.prototype.slice.call(opts.querySelectorAll('input:checked'))
      .map(function(i) { return i.value; });
    var status = head.querySelector('.perm-status');
    status.textContent = 'salvando…';
    status.className = 'perm-status salvando';
    API.salvarPermissoes(u.id, marcadas).then(function() {
      status.textContent = 'salvo';
      status.className = 'perm-status ok';
      setTimeout(function() { status.textContent = ''; status.className = 'perm-status'; }, 1800);
    }).catch(function(e) {
      if (e && e.sessaoEncerrada) { overlayPerm.hidden = true; tratarQuedaSessao(e); return; }
      status.textContent = 'erro ao salvar';
      status.className = 'perm-status erro';
    });
  });

  return card;
}

// Uma linha da tela de permissões: rótulo + toggle On/Off. parentKey != null => sub-permissão.
function _permLinha(key, label, marcado, parentKey) {
  var row = document.createElement('label');
  row.className = 'perm-opt' + (parentKey ? ' sub' : '');
  var attrs = 'type="checkbox" value="' + key + '"' + (marcado ? ' checked' : '') +
              (parentKey ? ' data-parent="' + parentKey + '"' : '');
  row.innerHTML =
    '<span class="perm-opt-lbl">' + label + '</span>' +
    '<span class="switch"><input ' + attrs + '><span class="slider"></span></span>';
  return row;
}

// ── Login ──────────────────────────────────────────────────────────────────
document.getElementById('btn-entrar').addEventListener('click', async function() {
  var erro = document.getElementById('login-erro');
  var btn  = document.getElementById('btn-entrar');
  erro.textContent = '';
  btn.disabled = true;
  btn.textContent = 'Entrando…';
  try {
    await API.login(
      document.getElementById('in-cliente').value.trim(),
      document.getElementById('in-login').value.trim(),
      document.getElementById('in-senha').value
    );
    sessionStorage.setItem('sd_login', document.getElementById('in-login').value.trim());
    mostrarApp();
  } catch (e) {
    erro.textContent = e.message;
    btn.disabled = false;
    btn.textContent = 'Entrar';
  }
});

document.getElementById('in-senha').addEventListener('keydown', function(e) {
  if (e.key === 'Enter') document.getElementById('btn-entrar').click();
});

document.getElementById('btn-ver-senha').addEventListener('click', function() {
  var inp = document.getElementById('in-senha');
  var reveal = inp.type === 'password';
  inp.type = reveal ? 'text' : 'password';
  var btn = document.getElementById('btn-ver-senha');
  btn.querySelector('.ico-eye').style.display     = reveal ? 'none' : '';
  btn.querySelector('.ico-eye-off').style.display = reveal ? ''     : 'none';
  btn.setAttribute('aria-label', reveal ? 'Ocultar senha' : 'Mostrar senha');
});

// ── Atualizar dados ────────────────────────────────────────────────────────
document.getElementById('btn-atualizar').addEventListener('click', function() {
  var btn = this;
  btn.classList.add('girando');
  btn.disabled = true;
  carregarDados().finally(function() {
    btn.classList.remove('girando');
    btn.disabled = false;
  });
});

// ── Logout ─────────────────────────────────────────────────────────────────
// Volta para a tela de login. msg (opcional) explica um logout involuntário (sessão encerrada/expirada).
function voltarParaLogin(msg) {
  clearInterval(_timerRefresh);
  _timerRefresh = null;
  clearInterval(_timerHeartbeat);
  _timerHeartbeat = null;
  _encerrando = false;
  _snaps = {};
  _secAtiva = '';
  overlayIA.hidden = true;
  overlayPerm.hidden = true;
  document.getElementById('overlay-sessao').hidden = true;
  document.getElementById('app').hidden = true;
  document.getElementById('tela-login').style.display = '';
  document.getElementById('in-senha').value = '';
  var btn = document.getElementById('btn-entrar');
  btn.disabled = false;
  btn.textContent = 'Entrar';
  document.getElementById('login-erro').textContent = msg || '';
}

document.getElementById('btn-sair').addEventListener('click', function() {
  API.sair();
  voltarParaLogin('');
});

// ── Sessão única: heartbeat + encerramento com contagem ──────────────────────
function baterHeartbeat() {
  API.ping().catch(function(e) {
    if (e && e.sessaoEncerrada) tratarQuedaSessao(e);
  });
}

// Trata a queda de sessão: se foi substituída por outro dispositivo, mostra a contagem;
// se apenas expirou, volta direto ao login.
function tratarQuedaSessao(e) {
  if (_encerrando) return;
  _encerrando = true;
  clearInterval(_timerHeartbeat); _timerHeartbeat = null;
  clearInterval(_timerRefresh);   _timerRefresh = null;
  if (e && e.superada) {
    contarEEncerrar(e.message);
  } else {
    voltarParaLogin(e ? e.message : '');
  }
}

function contarEEncerrar(msg) {
  var ov   = document.getElementById('overlay-sessao');
  var cont = document.getElementById('sessao-contador');
  var n = 5;
  cont.textContent = n;
  ov.hidden = false;
  var t = setInterval(function() {
    n--;
    if (n <= 0) { clearInterval(t); voltarParaLogin(msg); }
    else { cont.textContent = n; }
  }, 1000);
}

// ── Navegação (bottom nav) ─────────────────────────────────────────────────
document.querySelectorAll('.nav-btn').forEach(function(btn) {
  btn.addEventListener('click', function() { navegar(btn.dataset.sec); });
});

// ── Popular dropdown de empresas no login ──────────────────────────────────
(function carregarEmpresas() {
  var sel = document.getElementById('in-cliente');

  function tentar(tentativas) {
    API.empresas().then(function(lista) {
      sel.innerHTML = '';
      if (!lista || lista.length === 0) {
        sel.innerHTML = '<option value="" disabled selected>Nenhuma empresa cadastrada</option>';
        sel.disabled = false;
        return;
      }
      lista.forEach(function(emp) {
        var opt = document.createElement('option');
        opt.value = emp.nome;
        opt.textContent = emp.nome;
        sel.appendChild(opt);
      });
      sel.selectedIndex = 0;
      sel.disabled = false;
    }).catch(function() {
      if (tentativas > 0) {
        setTimeout(function() { tentar(tentativas - 1); }, 2000);
      } else {
        sel.innerHTML = '<option value="" disabled selected>Erro — recarregue a página</option>';
        sel.disabled = false;
      }
    });
  }

  tentar(5); // até 5 tentativas com 2s de intervalo
}());

// ── Inicializar ────────────────────────────────────────────────────────────
// Ajusta a UI às permissões: abas visíveis, engrenagem de admin e FAB da IA
function _aplicarPermissoes() {
  var secoes = API.secoes();
  document.querySelectorAll('.nav-btn').forEach(function(b) {
    b.style.display = secoes.indexOf(b.dataset.sec) >= 0 ? '' : 'none';
  });
  document.getElementById('btn-permissoes').style.display = API.ehAdmin() ? '' : 'none';
  // IA é assistente de BI: só para quem tem alguma seção de BI (não só estoque)
  var temBI = SECOES_BI.some(function(s) { return secoes.indexOf(s) >= 0; });
  document.getElementById('btn-ia').style.display = temBI ? '' : 'none';
}

function _secaoInicial() {
  var secoes = API.secoes();
  for (var i = 0; i < ORDEM_SEC.length; i++)
    if (secoes.indexOf(ORDEM_SEC[i]) >= 0) return ORDEM_SEC[i];
  return null;
}

function _mostrarSemAcesso() {
  document.getElementById('nav-bottom').style.display = 'none';
  document.getElementById('btn-ia').style.display = 'none';
  document.querySelectorAll('.sec').forEach(function(s) { s.classList.remove('ativa'); });
  var el = document.getElementById('sec-resumo');
  el.classList.add('ativa');
  el.innerHTML = '';
  el.appendChild(Render.emptyState('Sem acesso liberado',
    'Seu usuário ainda não tem seções liberadas. Fale com o administrador.'));
  document.getElementById('topo-titulo').textContent = 'SigeDash';
}

function mostrarApp() {
  _encerrando = false;
  document.getElementById('tela-login').style.display = 'none';
  document.getElementById('app').hidden = false;
  document.getElementById('topo-cliente').textContent = sessionStorage.getItem('sd_cliente') || '';
  _aplicarPermissoes();
  _secAtiva = '';

  var inicial = _secaoInicial();
  if (!inicial) { _mostrarSemAcesso(); return; }

  document.getElementById('nav-bottom').style.display = '';
  navegar(inicial);
  carregarDados();
  clearInterval(_timerRefresh);
  _timerRefresh = setInterval(carregarDados, AUTO_REFRESH_MS);
  clearInterval(_timerHeartbeat);
  _timerHeartbeat = setInterval(baterHeartbeat, HEARTBEAT_MS);
}

if (API.logado()) mostrarApp();
