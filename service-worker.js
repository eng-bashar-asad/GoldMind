const CACHE_NAME = 'goldmind-shell-v355';
// Inside the installed app (Capacitor serves the bundled files from https://localhost) the files are
// already on the phone, and this worker survives an app update: it kept serving the PREVIOUS version's
// cached theme.js / build-info.json on the first launch after updating, so the update bar came back
// once more right after installing (Bashar 2026-11-02). There it caches nothing and drops old copies.
const IN_APP = self.location.hostname === 'localhost';
// Pages and files needed to keep selling with no internet. Each is cached on
// its own so one missing file can't block the rest.
const SHELL_ASSETS = [
  './manifest.json',
  './icon-192.png',
  './icon-512.png',
  './supabase-config.js?v=55',
  './theme.js?v=89',
  './gm-invoice-edit.js?v=4',
  './index-ar.html',
  './new-sale-ar.html',
  './invoice-print-ar.html',
  './login-entry-ar.html',
  './customer-add-ar.html',
  './gm-logo.js?v=2',
  './favicon.png',
  './theme-royal-wood.webp?v=2',
  './gm-biometric.js?v=1',
  './gm-home-charts.js?v=3',
  './gm-home-tools.js?v=2',
  './gm-profit.js?v=7',
  './gm-report.js?v=4',
  './gm-nav.js?v=22'
];
// Versioned libraries and fonts from these CDNs are safe to keep offline.
// Supabase itself is NEVER cached here (live data must always be fresh; the
// app keeps its own offline copy of data, see supabase-config.js).
const CDN_HOSTS = ['cdn.jsdelivr.net', 'cdn.tailwindcss.com', 'fonts.googleapis.com', 'fonts.gstatic.com', 'cdnjs.cloudflare.com'];

self.addEventListener('install', (event) => {
  if (IN_APP) { self.skipWaiting(); return; }
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) =>
      Promise.all(SHELL_ASSETS.map((u) => cache.add(u).catch(() => {})))
    )
  );
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  // Only remove this worker's own old versions — other caches (like the
  // app's offline data copy) belong to the page and must survive updates.
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k.startsWith('goldmind-shell-') && (IN_APP || k !== CACHE_NAME)).map((k) => caches.delete(k)))
    )
  );
  self.clients.claim();
});

function staleWhileRevalidate(event) {
  event.respondWith(
    caches.match(event.request).then((cached) => {
      const network = fetch(event.request)
        .then((response) => {
          if (response && (response.ok || response.type === 'opaque')) {
            const copy = response.clone();
            caches.open(CACHE_NAME).then((cache) => cache.put(event.request, copy)).catch(() => {});
          }
          return response;
        })
        .catch(() => cached);
      return cached || network;
    })
  );
}

// HTML documents: network-first (deploys show up immediately), cached copy
// when offline. Same-origin static files and CDN libraries: served from cache
// instantly and refreshed in the background.
self.addEventListener('fetch', (event) => {
  if (event.request.method !== 'GET' || IN_APP) return;
  const url = new URL(event.request.url);
  if (url.pathname.endsWith('/build-info.json')) return; // version check: always the real file

  if (url.origin !== self.location.origin) {
    if (CDN_HOSTS.includes(url.hostname)) staleWhileRevalidate(event);
    return;
  }

  const isDocument = event.request.mode === 'navigate' || event.request.destination === 'document';
  if (isDocument) {
    event.respondWith(
      fetch(event.request, { cache: 'no-store' })
        .then((response) => {
          const copy = response.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(event.request, copy)).catch(() => {});
          return response;
        })
        .catch(() => caches.match(event.request, { ignoreSearch: true }))
    );
    return;
  }

  staleWhileRevalidate(event);
});
