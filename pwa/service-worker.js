// Cache do app shell (offline do ultimo carregamento). Dados vem sempre da rede.
const CACHE = "sigedash-v14";
const SHELL = ["./index.html","./css/app.css","./js/api.js","./js/render.js","./js/app.js","./manifest.webmanifest","./logo-sigedash.png","./bg-login.png"];

self.addEventListener("install", e =>
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL))));

self.addEventListener("activate", e =>
  e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k))))));

self.addEventListener("fetch", e => {
  const url = new URL(e.request.url);
  // chamadas de API: sempre rede (nao cacheia dado)
  if (url.pathname.startsWith("/dash") || url.pathname.startsWith("/auth")) return;
  // app shell: cache-first
  e.respondWith(caches.match(e.request).then(r => r || fetch(e.request)));
});
