// Cache do app shell (offline do ultimo carregamento). Dados vem sempre da rede.
const CACHE = "sigedash-v17";
const SHELL = ["./index.html","./css/app.css","./js/api.js","./js/render.js","./js/app.js","./js/sw-register.js","./manifest.webmanifest","./logo-sigedash.png","./bg-login.png"];

self.addEventListener("install", e => {
  self.skipWaiting();  // aplica a nova versao sem esperar todas as abas fecharem
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL)));
});

self.addEventListener("activate", e =>
  e.waitUntil(
    caches.keys()
      .then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  ));

self.addEventListener("fetch", e => {
  const url = new URL(e.request.url);
  // NAO intercepta cross-origin: Chart.js (cdnjs) e o beacon da Cloudflare carregam direto
  // pelo browser (regidos por script-src). Interceptar re-fetch cai em connect-src e quebra.
  if (url.origin !== self.location.origin) return;
  // chamadas de API: sempre rede (nao cacheia dado)
  if (url.pathname.startsWith("/dash") || url.pathname.startsWith("/auth")) return;
  // app shell (mesma origem): cache-first
  e.respondWith(caches.match(e.request).then(r => r || fetch(e.request)));
});
