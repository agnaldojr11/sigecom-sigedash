// SigeDash Central — painel da frota (vanilla JS).
(function () {
  var token = sessionStorage.getItem("sgc_token") || null;
  var timer = null;

  var $ = function (id) { return document.getElementById(id); };
  function esc(s) { return String(s == null ? "" : s).replace(/[&<>"]/g, function (c) {
    return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]; }); }

  async function api(path, opts) {
    opts = opts || {};
    opts.headers = Object.assign({ "Content-Type": "application/json" }, opts.headers || {});
    if (token) opts.headers["Authorization"] = "Bearer " + token;
    var r = await fetch(path, opts);
    if (r.status === 401) { sair(); throw new Error("Sessão expirada."); }
    if (!r.ok) { var d = await r.json().catch(function () { return {}; }); throw new Error(d.erro || ("Erro " + r.status)); }
    return r.status === 204 ? null : r.json();
  }

  // ── Login ──
  async function entrar() {
    var erro = $("login-erro"); erro.textContent = "";
    var btn = $("btn-entrar"); btn.disabled = true; btn.textContent = "Entrando…";
    try {
      var r = await fetch("/painel/login", {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ login: $("in-login").value.trim(), senha: $("in-senha").value })
      });
      if (!r.ok) { var d = await r.json().catch(function () { return {}; }); throw new Error(d.erro || "Falha no login"); }
      var data = await r.json();
      token = data.token; sessionStorage.setItem("sgc_token", token);
      mostrarApp();
    } catch (e) { erro.textContent = e.message; }
    finally { btn.disabled = false; btn.textContent = "Entrar"; }
  }

  function sair() {
    token = null; sessionStorage.removeItem("sgc_token");
    if (timer) clearInterval(timer);
    $("app").hidden = true; $("tela-login").style.display = "flex";
  }

  function mostrarApp() {
    $("tela-login").style.display = "none";
    $("app").hidden = false;
    carregar();
    if (timer) clearInterval(timer);
    timer = setInterval(carregar, 30000); // atualiza a cada 30s
  }

  // ── Frota ──
  async function carregar() {
    try {
      var data = await api("/painel/frota");
      renderResumo(data.resumo);
      renderFrota(data.clientes);
      $("atualizado").textContent = "atualizado " + new Date().toLocaleTimeString("pt-BR");
    } catch (e) { /* silencioso no polling */ }
  }

  function renderResumo(r) {
    $("resumo").innerHTML =
      kpi(r.total, "Clientes", "") +
      kpi(r.online, "Online", "on") +
      kpi(r.offline, "Offline", r.offline > 0 ? "off" : "") +
      kpi(r.desatualizados, "Desatualizados", r.desatualizados > 0 ? "alerta" : "") +
      kpi(r.comAlertas, "Com alertas", r.comAlertas > 0 ? "alerta" : "");
  }
  function kpi(n, l, cls) {
    return '<div class="kpi ' + cls + '"><div class="n">' + n + '</div><div class="l">' + l + '</div></div>';
  }

  function renderFrota(cli) {
    var body = $("frota-body");
    $("frota-vazio").hidden = cli.length > 0;
    body.innerHTML = cli.map(function (c) {
      var status = c.online ? '<span class="pill ok">online</span>' : '<span class="pill crit">offline</span>';
      var ver = c.versao
        ? (c.desatualizado ? '<span class="pill warn">v' + esc(c.versao) + '</span>' : '<span class="pill ok">v' + esc(c.versao) + '</span>')
        : '<span class="pill neutro">—</span>';
      var disp = c.limite > 0 ? (c.usuariosAtivos + " / " + c.limite) : (c.usuariosAtivos + " / ∞");
      var dispCls = (c.limite > 0 && c.usuariosAtivos >= c.limite) ? "warn" : "acc";
      var ind = c.indicadoresErro > 0
        ? '<span class="pill warn">' + c.indicadoresErro + ' c/ erro</span>'
        : '<span class="pill ok">ok</span>';
      return '<tr data-id="' + c.id + '">' +
        '<td><div class="cli-nome">' + esc(c.nome) + '</div>' + (c.cnpj ? '<div class="cli-cnpj">' + esc(c.cnpj) + '</div>' : '') + '</td>' +
        '<td>' + status + '</td>' +
        '<td>' + ver + '</td>' +
        '<td><span class="pill ' + dispCls + '">' + disp + '</span></td>' +
        '<td>' + ind + '</td>' +
        '<td class="mono">' + tempo(c.ultimoHeartbeat) + '</td>' +
        '</tr>';
    }).join("");
    Array.prototype.forEach.call(body.querySelectorAll("tr"), function (tr) {
      tr.addEventListener("click", function () { abrirDetalhe(tr.getAttribute("data-id")); });
    });
  }

  function tempo(iso) {
    if (!iso) return "nunca";
    var s = Math.max(0, Math.floor((Date.now() - new Date(iso).getTime()) / 1000));
    if (s < 60) return "há " + s + "s";
    if (s < 3600) return "há " + Math.floor(s / 60) + "min";
    if (s < 86400) return "há " + Math.floor(s / 3600) + "h";
    return "há " + Math.floor(s / 86400) + "d";
  }
  function uptime(seg) {
    if (!seg) return "—";
    var d = Math.floor(seg / 86400), h = Math.floor((seg % 86400) / 3600);
    return d > 0 ? (d + "d " + h + "h") : (h + "h");
  }

  // ── Detalhe ──
  async function abrirDetalhe(id) {
    try {
      var c = await api("/painel/clientes/" + id);
      $("det-nome").textContent = c.nome;
      $("det-sub").textContent = (c.cnpj ? c.cnpj + " · " : "") + (c.online ? "online" : "offline");
      var hb = c.heartbeat || {};
      var body =
        '<div class="kv">' +
          item("Versão", hb.versao ? "v" + esc(hb.versao) : "—") +
          item("Dispositivos", (hb.usuariosAtivos != null ? hb.usuariosAtivos : "—") + (c.limiteDispositivos > 0 ? " / " + c.limiteDispositivos : " / ∞")) +
          item("Uptime", uptime(hb.uptimeSeg)) +
          item("PostgreSQL", esc(hb.statusPg || "—")) +
          item("Backend", esc(hb.statusBackend || "—")) +
          item("Sistema", esc(hb.os || "—")) +
          item("Último sinal", tempo(hb.recebidoEm)) +
          item("Registrado", c.criadoEm ? new Date(c.criadoEm).toLocaleDateString("pt-BR") : "—") +
        '</div>';
      var inds = (c.indicadores || []);
      body += '<div class="ind-titulo">Indicadores (' + inds.length + ')</div>';
      if (inds.length === 0) body += '<div class="ind"><span class="t">Nenhum indicador reportado ainda.</span></div>';
      body += inds.map(function (i) {
        var cls = i.status === "erro" ? "crit" : (i.status === "atrasado" ? "warn" : "ok");
        var quando = i.status === "erro" ? tempo(i.ultimoErro) : tempo(i.ultimoSucesso);
        return '<div class="ind"><div><div class="h">' + esc(i.handle) + '</div>' +
          (i.mensagem ? '<div class="t">' + esc(i.mensagem) + '</div>' : '') + '</div>' +
          '<div style="text-align:right"><span class="pill ' + cls + '">' + esc(i.status || "—") + '</span>' +
          '<div class="t">' + quando + '</div></div></div>';
      }).join("");
      $("det-body").innerHTML = body;
      $("overlay").hidden = false;
    } catch (e) { alert(e.message); }
  }
  function item(l, v) { return '<div class="item"><div class="l">' + l + '</div><div class="v">' + v + '</div></div>'; }

  // ── Eventos ──
  $("btn-entrar").addEventListener("click", entrar);
  $("in-senha").addEventListener("keydown", function (e) { if (e.key === "Enter") entrar(); });
  $("btn-sair").addEventListener("click", sair);
  $("btn-refresh").addEventListener("click", carregar);
  $("btn-fechar").addEventListener("click", function () { $("overlay").hidden = true; });
  $("overlay").addEventListener("click", function (e) { if (e.target === $("overlay")) $("overlay").hidden = true; });

  if (token) mostrarApp();
})();
