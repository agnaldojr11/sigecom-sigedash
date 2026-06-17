// Componentes visuais v3: cabeçalho colorido por handle, timestamp de sincronização.
const Render = (() => {
  const CORES_CHART = ['#3b82f6','#34d399','#fbbf24','#f472b6','#a78bfa','#fb7185','#38bdf8','#4ade80','#facc15','#e879f9'];

  const moeda = v => Number(v || 0).toLocaleString('pt-BR', {style:'currency', currency:'BRL'});
  const num   = v => Number(v || 0).toLocaleString('pt-BR', {maximumFractionDigits: 2});

  // ── Cor do cabeçalho por handle (padrão do app legado) ────────────────────
  const CARD_CORES = {
    vendas_total_mes:               '#00897B',
    vendas_total_semana:            '#00897B',
    vendas_total_hoje:              '#00897B',
    vendas_qtd_pedidos:             '#0288D1',
    vendas_ticket_medio:            '#0288D1',
    vendas_pico_horario:            '#546E7A',
    vendas_top_clientes:            '#1976D2',
    vendas_top_produtos:            '#7B1FA2',
    vendas_top_vendedores:          '#388E3C',
    vendas_forma_pagamento:         '#5D4037',
    vendas_custo_venda:             '#455A64',
    estoque_top_produtos:           '#00796B',
    estoque_abaixo_min:             '#E65100',
    estoque_sem_estoque:            '#C62828',
    financeiro_receber_mes:         '#0277BD',
    financeiro_receber_semana:      '#0277BD',
    financeiro_receber_hoje:        '#0277BD',
    financeiro_pagar_mes:           '#BF360C',
    financeiro_pagar_semana:        '#BF360C',
    financeiro_pagar_hoje:          '#BF360C',
    financeiro_inadimplencia:       '#B71C1C',
    financeiro_vencimentos_proximos:'#E65100',
    saldo_caixas:                   '#6A1B9A',
    saldo_bancario:                 '#1A237E',
  };

  function corCard(handle) {
    return CARD_CORES[handle] || '#37474F';
  }

  const ICO_CLOCK =
    '<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' +
      '<circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/>' +
    '</svg>';

  function fmtDataHora(iso) {
    if (!iso) return '';
    var d = new Date(iso);
    var data = d.toLocaleDateString('pt-BR', {day:'2-digit', month:'2-digit', year:'numeric'});
    var hora = d.toLocaleTimeString('pt-BR', {hour:'2-digit', minute:'2-digit', second:'2-digit'});
    return data + ' às ' + hora;
  }

  function makeCardHeader(handle, titulo, geradoEm) {
    var h = document.createElement('div');
    h.className = 'card-header';
    h.style.background = corCard(handle);
    var ts = fmtDataHora(geradoEm);
    h.innerHTML =
      '<div class="card-header-titulo">' + titulo + '</div>' +
      (ts ? '<div class="card-header-sync">' + ICO_CLOCK + ' Dados sincronizados em ' + ts + '</div>' : '');
    return h;
  }

  function parseSnap(snap) {
    try {
      const p = JSON.parse(snap.payload);
      return {
        titulo: p.titulo || snap.indicadorHandle,
        tipo: (p.tipo || '').toLowerCase(),
        dados: Array.isArray(p.dados) ? p.dados : []
      };
    } catch {
      return { titulo: snap.indicadorHandle, tipo: '', dados: [] };
    }
  }

  // ── KPI Card (tela Resumo — sem cabeçalho colorido) ───────────────────────
  function _svg(d, w) {
    w = w || 14;
    return '<svg width="' + w + '" height="' + w + '" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">' + d + '</svg>';
  }

  const ICO = {
    trendingUp: _svg('<polyline points="23 6 13.5 15.5 8.5 10.5 1 18"/><polyline points="17 6 23 6 23 12"/>', 16),
    cart:       _svg('<circle cx="9" cy="21" r="1"/><circle cx="20" cy="21" r="1"/><path d="M1 1h4l2.68 13.39a2 2 0 0 0 2 1.61h9.72a2 2 0 0 0 2-1.61L23 6H6"/>', 16),
    alertTri:   _svg('<path d="M10.29 3.86 1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/>', 16),
    alertOct:   _svg('<polygon points="7.86 2 16.14 2 22 7.86 22 16.14 16.14 22 7.86 22 2 16.14 2 7.86 7.86 2"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/>', 16),
  };

  function kpiCard(titulo, valor, sub, variante, icone) {
    const d = document.createElement('div');
    d.className = 'kpi-card ' + (variante || 'azul');
    d.innerHTML =
      (icone ? '<div class="kpi-icon">' + icone + '</div>' : '') +
      '<span class="kpi-titulo">' + titulo + '</span>' +
      '<span class="kpi-valor">'  + valor  + '</span>' +
      (sub ? '<span class="kpi-sub">' + sub + '</span>' : '');
    return d;
  }

  // ── Info Card (card inteiro colorido, como no app legado) ────────────────
  function infoCard(snap) {
    const { titulo, dados } = parseSnap(snap);
    const row = dados[0] || {};
    const val = Number(row.value != null ? row.value : (row.valor != null ? row.valor : 0));
    const fmt = row.formato === 'qtd' ? num(val) : moeda(val);
    const sub = row.sub || null;
    const cor = corCard(snap.indicadorHandle);
    const ts  = fmtDataHora(snap.geradoEm);

    const card = document.createElement('div');
    card.className = 'card card-info-full';
    card.style.background = cor;
    card.innerHTML =
      '<div class="card-header">' +
        '<div class="card-header-titulo">' + titulo + '</div>' +
        (ts ? '<div class="card-header-sync">' + ICO_CLOCK + ' Dados sincronizados em ' + ts + '</div>' : '') +
      '</div>' +
      '<div class="card-body card-body-info">' +
        '<div class="info-valor">' + fmt + '</div>' +
        (sub ? '<div class="info-sub">' + sub + '</div>' : '') +
      '</div>';
    return card;
  }

  // ── Ranking Card ──────────────────────────────────────────────────────────
  function rankingCard(snap) {
    const { titulo, dados } = parseSnap(snap);

    const card = document.createElement('div');
    card.className = 'card';
    card.appendChild(makeCardHeader(snap.indicadorHandle, titulo, snap.geradoEm));

    const body = document.createElement('div');
    body.className = 'card-body';

    if (!dados.length) {
      body.innerHTML = '<p class="ranking-vazio">Nenhum registro encontrado!</p>';
      card.appendChild(body);
      return card;
    }

    dados.forEach(function(d, i) {
      const pos = i + 1;
      const medalha = pos === 1 ? 'ouro' : pos === 2 ? 'prata' : pos === 3 ? 'bronze' : '';
      const raw = Number(d.value != null ? d.value : (d.valor != null ? d.valor : 0));
      const valorFmt = d.minimo !== undefined ? num(raw) : moeda(raw);
      const nome = d.label || d.nome || '';
      const sub  = d.minimo !== undefined ? 'Mínimo: ' + num(d.minimo) : null;

      const item = document.createElement('div');
      item.className = 'ranking-item';
      item.innerHTML =
        '<span class="ranking-pos' + (medalha ? ' ' + medalha : '') + '">' + pos + '</span>' +
        '<span class="ranking-nome">' + nome + (sub ? '<small>' + sub + '</small>' : '') + '</span>' +
        '<span class="ranking-valor">' + valorFmt + '</span>';
      body.appendChild(item);
    });

    card.appendChild(body);
    return card;
  }

  // ── Lista Card ────────────────────────────────────────────────────────────
  function listaCard(snap) {
    const { titulo, dados } = parseSnap(snap);

    const card = document.createElement('div');
    card.className = 'card';
    card.appendChild(makeCardHeader(snap.indicadorHandle, titulo, snap.geradoEm));

    const body = document.createElement('div');
    body.className = 'card-body';

    if (!dados.length) {
      body.innerHTML = '<p class="ranking-vazio">Nenhum registro encontrado!</p>';
      card.appendChild(body);
      return card;
    }

    const lista = document.createElement('div');
    lista.className = 'lista';
    lista.innerHTML = dados.map(function(d) {
      return '<div class="lista-item">' +
        '<span class="lista-label">' + (d.label || d.nome || '').trim() + '</span>' +
        '<b class="lista-valor">' + moeda(d.value != null ? d.value : (d.valor != null ? d.valor : 0)) + '</b>' +
      '</div>';
    }).join('');
    body.appendChild(lista);
    card.appendChild(body);
    return card;
  }

  // ── Chart Card ────────────────────────────────────────────────────────────
  function chartCard(snap, horizontal) {
    const { titulo, dados } = parseSnap(snap);
    const handle = snap.indicadorHandle;

    const card = document.createElement('div');
    card.className = 'card';
    card.appendChild(makeCardHeader(handle, titulo, snap.geradoEm));

    const body = document.createElement('div');
    body.className = 'card-body';

    if (!dados.length) {
      body.innerHTML = '<p class="ranking-vazio">Nenhum registro encontrado!</p>';
      card.appendChild(body);
      return card;
    }

    const height = horizontal ? Math.max(180, dados.length * 44) : 220;
    const wrap = document.createElement('div');
    wrap.style.cssText = 'position:relative;height:' + height + 'px';

    const cid = 'chart-' + handle;
    const canvas = document.createElement('canvas');
    canvas.id = cid;
    wrap.appendChild(canvas);
    body.appendChild(wrap);
    card.appendChild(body);

    if (window._chartReg && window._chartReg[cid]) { window._chartReg[cid].destroy(); }
    if (!window._chartReg) window._chartReg = {};

    Promise.resolve().then(function() {
      if (!canvas.isConnected) return;
      window._chartReg[cid] = new Chart(canvas, {
        type: 'bar',
        data: {
          labels: dados.map(function(d) { return d.bar || d.label || d.nome || ''; }),
          datasets: [{
            data: dados.map(function(d) { return Number(d.value != null ? d.value : (d.valor != null ? d.valor : 0)); }),
            backgroundColor: dados.map(function(_, i) { return CORES_CHART[i % CORES_CHART.length]; }),
            borderRadius: 5,
            borderSkipped: false,
          }]
        },
        options: {
          indexAxis: horizontal ? 'y' : 'x',
          responsive: true,
          maintainAspectRatio: false,
          plugins: {
            legend: { display: false },
            tooltip: { callbacks: { label: function(ctx) { return ' ' + ctx.raw.toLocaleString('pt-BR'); } } }
          },
          scales: {
            x: { grid: { color: '#263348' }, ticks: { color: '#94a3b8', font: { size: 11 }, maxTicksLimit: 8 } },
            y: { grid: { color: '#263348' }, ticks: { color: '#94a3b8', font: { size: 11 } } }
          }
        }
      });
    });

    return card;
  }

  // ── Empty State ───────────────────────────────────────────────────────────
  function emptyState(titulo, desc) {
    const d = document.createElement('div');
    d.className = 'empty-state';
    d.innerHTML =
      '<svg width="44" height="44" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" opacity="0.35" aria-hidden="true">' +
        '<circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/>' +
        '<circle cx="12" cy="16" r=".5" fill="currentColor"/>' +
      '</svg>' +
      '<h3>' + titulo + '</h3><p>' + desc + '</p>';
    return d;
  }

  // ── Despacho principal ────────────────────────────────────────────────────
  function indicador(snap) {
    const { tipo } = parseSnap(snap);
    switch (tipo) {
      case 'info':          return infoCard(snap);
      case 'ranking':       return rankingCard(snap);
      case 'list':          return listaCard(snap);
      case 'bar':           return chartCard(snap, false);
      case 'barhorizontal': return chartCard(snap, true);
      default:              return rankingCard(snap);
    }
  }

  return { indicador, kpiCard, emptyState, moeda, parseSnap, ICO };
})();
