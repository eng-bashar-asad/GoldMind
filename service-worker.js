const CACHE_NAME = 'goldmind-shell-v2';
const SHELL_ASSETS = [
  './manifest.json',
  './icon-192.png',
  './icon-512.png'
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(SHELL_ASSETS)).catch(() => {})
  );
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k)))
    )
  );
  self.clients.claim();
});

// Network-first: always try the network (so data/pages stay fresh), fall back
// to cache only if the network is unreachable (basic offline resilience).
//
// { cache: 'no-store' } is critical here — without it, fetch() still lets
// the BROWSER's own HTTP disk cache intercept the request before it ever
// reaches the network (a page load looking like it went "network-first"
// while actually being served a stale cached response, e.g. after every
// GitHub Pages deploy until that cache entry happened to expire). This
// forces every request straight to the network, bypassing that cache
// layer entirely, so a push is reflected on the very next load.
self.addEventListener('fetch', (event) => {
  if (event.request.method !== 'GET') return;
  event.respondWith(
    fetch(event.request, { cache: 'no-store' })
      .then((response) => {
        const copy = response.clone();
        caches.open(CACHE_NAME).then((cache) => cache.put(event.request, copy)).catch(() => {});
        return response;
      })
      .catch(() => caches.match(event.request))
  );
});
