const CACHE_NAME = 'goldmind-shell-v4';
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

// Only HTML documents go network-first/no-store (deploys must show up
// immediately). Static assets (JS/CSS/images/fonts) use stale-while-
// revalidate: serve instantly from cache if we have it, then quietly
// refresh the cache in the background — this is what actually keeps the
// app fast, since re-fetching every single asset from the network on every
// navigation (the previous blanket behavior) made every page feel slow.
self.addEventListener('fetch', (event) => {
  if (event.request.method !== 'GET') return;

  const isDocument = event.request.mode === 'navigate' || event.request.destination === 'document';

  if (isDocument) {
    event.respondWith(
      fetch(event.request, { cache: 'no-store' })
        .then((response) => {
          const copy = response.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(event.request, copy)).catch(() => {});
          return response;
        })
        .catch(() => caches.match(event.request))
    );
    return;
  }

  event.respondWith(
    caches.match(event.request).then((cached) => {
      const network = fetch(event.request)
        .then((response) => {
          const copy = response.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(event.request, copy)).catch(() => {});
          return response;
        })
        .catch(() => cached);
      return cached || network;
    })
  );
});
