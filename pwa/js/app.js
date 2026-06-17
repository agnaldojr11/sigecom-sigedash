// SigeDash — Orquestrador v2: navegação, seções, dados, login/logout, assistente IA.
Chart.defaults.color = '#94a3b8';
Chart.defaults.font.family = 'system-ui, -apple-system, sans-serif';
Chart.defaults.font.size = 12;

let _snaps = {};
let _secAtiva = '';
let _timerRefresh = null;
const AUTO_REFRESH_MS = 5 * 60 * 1000; // 5 minutos

const TITULOS_SEC = {
  resumo: 'SigeDash',
  vendas: 'Vendas',
  estoque: 'Estoque',
  financeiro: 'Financeiro'
};

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
function renderEstoque(el) {
  el.innerHTML = '';
  var grupos = [
    { titulo: 'Maiores Estoques', handles: ['estoque_top_produtos'] },
    { titulo: 'Alertas',          handles: ['estoque_sem_estoque','estoque_abaixo_min'] },
  ];
  var temAlgum = false;
  grupos.forEach(function(g) {
    var disp = g.handles.filter(function(h) { return _snaps[h]; });
    if (!disp.length) return;
    temAlgum = true;
    el.appendChild(secGrupo(g.titulo));
    disp.forEach(function(h) { el.appendChild(Render.indicador(_snaps[h])); });
  });
  if (!temAlgum) el.appendChild(Render.emptyState('Sem dados de estoque', 'Execute o agente para carregar os indicadores de estoque.'));
}

// ── Financeiro ─────────────────────────────────────────────────────────────
function renderFinanceiro(el) {
  el.innerHTML = '';
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

// ── Dados ──────────────────────────────────────────────────────────────────
async function carregarDados() {
  try {
    var lista = await API.dashboards(1);
    _snaps = {};
    lista.forEach(function(s) { _snaps[s.indicadorHandle] = s; });
    renderSecao(_secAtiva);
  } catch (e) {
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
    loadingMsg.textContent = 'Erro: ' + e.message;
    loadingMsg.classList.remove('loading');
  } finally {
    iaSendBtn.disabled = false;
    iaInputEl.focus();
  }
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
document.getElementById('btn-sair').addEventListener('click', function() {
  API.sair();
  clearInterval(_timerRefresh);
  _timerRefresh = null;
  _snaps = {};
  _secAtiva = '';
  overlayIA.hidden = true;
  document.getElementById('app').hidden = true;
  document.getElementById('tela-login').style.display = '';
  document.getElementById('in-senha').value = '';
  var btn = document.getElementById('btn-entrar');
  btn.disabled = false;
  btn.textContent = 'Entrar';
  document.getElementById('login-erro').textContent = '';
});

// ── Navegação (bottom nav) ─────────────────────────────────────────────────
document.querySelectorAll('.nav-btn').forEach(function(btn) {
  btn.addEventListener('click', function() { navegar(btn.dataset.sec); });
});

// ── Inicializar ────────────────────────────────────────────────────────────
function mostrarApp() {
  document.getElementById('tela-login').style.display = 'none';
  document.getElementById('app').hidden = false;
  document.getElementById('topo-cliente').textContent = sessionStorage.getItem('sd_cliente') || '';
  _secAtiva = '';
  navegar('resumo');
  carregarDados();
  clearInterval(_timerRefresh);
  _timerRefresh = setInterval(carregarDados, AUTO_REFRESH_MS);
}

if (API.logado()) mostrarApp();
