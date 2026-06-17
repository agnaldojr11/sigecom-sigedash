// Camada de acesso ao backend. Token JWT guardado em memoria + sessionStorage.
const API = (() => {
  // Dev: backend em :5000 separado. Produção: mesmo origin (PWA servido pelo backend).
  const BASE = (window.location.hostname === "localhost" || window.location.hostname === "127.0.0.1")
    ? "http://localhost:5000"
    : "";
  let token = sessionStorage.getItem("sd_token") || null;

  async function login(cliente, login, senha) {
    const r = await fetch(`${BASE}/auth/login`, {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ cliente, login, senha })
    });
    if (!r.ok) throw new Error("Usuário ou senha inválidos");
    const data = await r.json();
    token = data.token; sessionStorage.setItem("sd_token", token);
    sessionStorage.setItem("sd_cliente", data.cliente);
    return data;
  }

  async function dashboards(codigoEmpresa = 1) {
    const r = await fetch(`${BASE}/dash/${codigoEmpresa}`, {
      headers: { "Authorization": `Bearer ${token}` }
    });
    if (r.status === 401) { sair(); throw new Error("Sessão expirada"); }
    return r.json();
  }

  async function queryIA(pergunta, contexto) {
    const r = await fetch(`${BASE}/ia/query`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "Authorization": `Bearer ${token}` },
      body: JSON.stringify({ pergunta, contexto })
    });
    if (r.status === 401) { sair(); throw new Error("Sessão expirada"); }
    if (!r.ok) {
      const d = await r.json().catch(() => ({}));
      throw new Error(d.detail || d.title || "Erro ao consultar IA");
    }
    return r.json();
  }

  function sair() { token = null; sessionStorage.clear(); }
  function logado() { return !!token; }

  return { login, dashboards, queryIA, sair, logado };
})();
