// Camada de acesso ao backend. Token JWT guardado em memoria + sessionStorage.
const API = (() => {
  // Dev: backend em :5000 separado. Produção: mesmo origin (PWA servido pelo backend).
  const BASE = (window.location.hostname === "localhost" || window.location.hostname === "127.0.0.1")
    ? "http://localhost:5000"
    : "";
  let token = sessionStorage.getItem("sd_token") || null;

  // fetch com timeout (AbortController) + retry em falha de rede/timeout (nao retenta HTTP 4xx/5xx).
  // Conexoes instaveis (ex.: tunnel oscilando) deixam de exigir refresh manual: o app se recupera sozinho.
  async function _fetchRetry(url, opts) {
    const maxTent = 3, timeoutMs = 12000;
    let ultimoErro;
    for (let i = 1; i <= maxTent; i++) {
      const ctrl = new AbortController();
      const timer = setTimeout(() => ctrl.abort(), timeoutMs);
      try {
        const r = await fetch(url, Object.assign({}, opts || {}, { signal: ctrl.signal }));
        clearTimeout(timer);
        return r;                       // resposta HTTP (mesmo 4xx/5xx) - nao retenta
      } catch (e) {
        clearTimeout(timer);
        ultimoErro = e;                 // erro de rede ou timeout (abort) - retenta com backoff
        if (i < maxTent) await new Promise(res => setTimeout(res, 700 * i));
      }
    }
    throw ultimoErro;
  }

  async function login(cliente, login, senha) {
    let r;
    try {
      r = await _fetchRetry(`${BASE}/auth/login`, {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ cliente, login, senha })
      });
    } catch (e) {
      throw new Error("Falha de conexão. Verifique a internet e tente novamente.");
    }
    if (!r.ok) {
      const d = await r.json().catch(() => ({}));
      throw new Error(d.erro || "Usuário ou senha inválidos");
    }
    const data = await r.json();
    token = data.token; sessionStorage.setItem("sd_token", token);
    sessionStorage.setItem("sd_cliente", data.cliente);
    sessionStorage.setItem("sd_admin", data.admin ? "1" : "0");
    sessionStorage.setItem("sd_secoes", JSON.stringify(data.secoes || []));
    return data;
  }

  function ehAdmin() { return sessionStorage.getItem("sd_admin") === "1"; }
  function secoes() {
    try { return JSON.parse(sessionStorage.getItem("sd_secoes") || "[]"); }
    catch { return []; }
  }

  async function listarUsuarios() {
    const r = await fetch(`${BASE}/admin/usuarios`, {
      headers: { "Authorization": `Bearer ${token}` }
    });
    if (r.status === 401) throw _erro401(r);
    if (!r.ok) throw new Error("Erro ao carregar usuários");
    return r.json();
  }

  async function salvarPermissoes(usuarioId, listaSecoes) {
    const r = await fetch(`${BASE}/admin/usuarios/${usuarioId}/permissoes`, {
      method: "PUT",
      headers: { "Content-Type": "application/json", "Authorization": `Bearer ${token}` },
      body: JSON.stringify({ secoes: listaSecoes })
    });
    if (r.status === 401) throw _erro401(r);
    if (!r.ok) throw new Error("Erro ao salvar permissões");
    return r.json();
  }

  // Troca da propria senha (primeiro acesso ou por escolha). Requer estar logado.
  async function trocarSenha(senhaAtual, senhaNova) {
    const r = await fetch(`${BASE}/auth/trocar-senha`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "Authorization": `Bearer ${token}` },
      body: JSON.stringify({ senhaAtual, senhaNova })
    });
    if (r.status === 401) throw _erro401(r);
    if (!r.ok) throw new Error((await r.json().catch(() => ({}))).erro || "Erro ao trocar a senha");
    return r.json();
  }

  // --- Gestao de usuarios (somente admin) ---
  async function criarUsuario(dto) {
    const r = await fetch(`${BASE}/admin/usuarios`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "Authorization": `Bearer ${token}` },
      body: JSON.stringify(dto)
    });
    if (r.status === 401) throw _erro401(r);
    if (!r.ok) throw new Error((await r.json().catch(() => ({}))).erro || "Erro ao criar usuário");
    return r.json();
  }

  async function editarUsuario(id, dto) {
    const r = await fetch(`${BASE}/admin/usuarios/${id}`, {
      method: "PUT",
      headers: { "Content-Type": "application/json", "Authorization": `Bearer ${token}` },
      body: JSON.stringify(dto)
    });
    if (r.status === 401) throw _erro401(r);
    if (!r.ok) throw new Error((await r.json().catch(() => ({}))).erro || "Erro ao editar usuário");
    return r.json();
  }

  async function resetarSenha(id) {
    const r = await fetch(`${BASE}/admin/usuarios/${id}/resetar-senha`, {
      method: "POST", headers: { "Authorization": `Bearer ${token}` }
    });
    if (r.status === 401) throw _erro401(r);
    if (!r.ok) throw new Error((await r.json().catch(() => ({}))).erro || "Erro ao resetar senha");
    return r.json();
  }

  async function excluirUsuario(id) {
    const r = await fetch(`${BASE}/admin/usuarios/${id}`, {
      method: "DELETE", headers: { "Authorization": `Bearer ${token}` }
    });
    if (r.status === 401) throw _erro401(r);
    if (!r.ok) throw new Error((await r.json().catch(() => ({}))).erro || "Erro ao excluir usuário");
    return r.json();
  }

  async function dashboards(codigoEmpresa = 1) {
    const r = await _fetchRetry(`${BASE}/dash/${codigoEmpresa}`, {
      headers: { "Authorization": `Bearer ${token}` }
    });
    if (r.status === 401) throw _erro401(r);
    return r.json();
  }

  async function queryIA(pergunta, contexto) {
    const r = await fetch(`${BASE}/ia/query`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "Authorization": `Bearer ${token}` },
      body: JSON.stringify({ pergunta, contexto })
    });
    if (r.status === 401) throw _erro401(r);
    if (!r.ok) {
      const d = await r.json().catch(() => ({}));
      throw new Error(d.detail || d.title || "Erro ao consultar IA");
    }
    return r.json();
  }

  // Plano do cliente: limite de dispositivos (seats) e usuarios ativos (somente admin).
  async function plano() {
    const r = await fetch(`${BASE}/admin/plano`, { headers: { "Authorization": `Bearer ${token}` } });
    if (r.status === 401) throw _erro401(r);
    if (!r.ok) throw new Error("Erro ao carregar o plano");
    return r.json();
  }

  // --- Atualizacao in-app (somente admin) ---
  async function statusAtualizacao() {
    const r = await fetch(`${BASE}/admin/atualizacao/status`, {
      headers: { "Authorization": `Bearer ${token}` }
    });
    if (r.status === 401) throw _erro401(r);
    if (!r.ok) throw new Error("Erro ao verificar atualização");
    return r.json();
  }

  async function aplicarAtualizacao() {
    const r = await fetch(`${BASE}/admin/atualizacao/aplicar`, {
      method: "POST", headers: { "Authorization": `Bearer ${token}` }
    });
    if (r.status === 401) throw _erro401(r);
    if (!r.ok) throw new Error((await r.json().catch(() => ({}))).detail || "Erro ao iniciar atualização");
    return r.json();
  }

  async function empresas() {
    try {
      const r = await _fetchRetry(`${BASE}/auth/empresas`);
      if (!r.ok) return [];
      return r.json();
    } catch (e) { return []; }
  }

  // Probe leve: backend respondendo? (usado para detectar o reinicio durante a atualizacao)
  async function online() {
    try { const r = await fetch(`${BASE}/auth/empresas`, { cache: "no-store" }); return r.ok; }
    catch { return false; }
  }

  function sair() { token = null; sessionStorage.clear(); }
  function logado() { return !!token; }

  // 401: encerra a sessão local e devolve um erro marcado (com mensagem conforme o motivo)
  function _erro401(r) {
    var superada = r.headers.get("X-Sessao") === "encerrada";
    sair();
    var e = new Error(superada
      ? "Sua sessão foi encerrada porque este usuário entrou em outro dispositivo."
      : "Sua sessão expirou. Entre novamente.");
    e.sessaoEncerrada = true;
    e.superada = superada;
    return e;
  }

  // Heartbeat: confirma se esta ainda é a sessão ativa (401 => foi substituída)
  async function ping() {
    const r = await fetch(`${BASE}/auth/sessao`, { headers: { "Authorization": `Bearer ${token}` } });
    if (r.status === 401) throw _erro401(r);
    return true;
  }

  return { login, dashboards, queryIA, empresas, sair, logado, ping,
           ehAdmin, secoes, listarUsuarios, salvarPermissoes,
           trocarSenha, criarUsuario, editarUsuario, resetarSenha, excluirUsuario,
           statusAtualizacao, aplicarAtualizacao, online, plano };
})();
