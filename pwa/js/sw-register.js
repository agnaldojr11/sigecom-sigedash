// Registro do service worker (externalizado do index.html para permitir CSP sem 'unsafe-inline').
if ('serviceWorker' in navigator) {
  navigator.serviceWorker.register('service-worker.js');
}
