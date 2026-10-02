// Cache do app shell (offline do ultimo carregamento). Dados vem sempre da rede.
const CACHE = "sigedash-v35";
const SHELL = ["./index.html","./css/app.css","./js/api.js","./js/render.js","./js/app.js","./js/sw-register.js","./manifest.webmanifest","./logo-sigedash.png","./bg-login.png"];

self.addEventListener("install", e => {
  self.skipWaiting();  // aplica a nova versao sem esperar todas as abas fecharem
  // addAll falha inteiro se um item 404; cacheia item a item (best-effort) para o install nunca quebrar.
  e.waitUntil(caches.open(CACHE).then(c => Promise.all(
    SHELL.map(u => c.add(u).catch(() => {}))
  )));
});

self.addEventListener("activate", e =>
  e.waitUntil(
    caches.keys()
      .then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  ));

self.addEventListener("fetch", e => {
  const req = e.request;
  const url = new URL(req.url);
  // NAO intercepta cross-origin: Chart.js (cdnjs) e o beacon da Cloudflare carregam direto
  // pelo browser (regidos por script-src). Interceptar re-fetch cai em connect-src e quebra.
  if (url.origin !== self.location.origin) return;
  // chamadas de API: sempre rede (nao cacheia dado)
  if (url.pathname.startsWith("/dash") || url.pathname.startsWith("/auth")) return;

  // Navegacao (HTML): NETWORK-FIRST. Sempre pega o index.html fresco quando online e so cai no
  // cache quando offline. Evita "tela branca" por shell antigo preso no cache (comum no iOS/Safari
  // apos uma atualizacao).
  if (req.mode === "navigate") {
    e.respondWith(
      fetch(req)
        .then(r => {
          const copia = r.clone();
          caches.open(CACHE).then(c => c.put("./index.html", copia)).catch(() => {});
          return r;
        })
        .catch(() => caches.match("./index.html").then(r => r || caches.match(req)))
    );
    return;
  }

  // Demais assets da mesma origem: cache-first (rapido), com rede como fallback.
  e.respondWith(caches.match(req).then(r => r || fetch(req)));
});
