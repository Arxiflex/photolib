// The app's offline shell (WEB-07, docs/10 §7): what the page loaded is kept, so that the installed app opens without a
// network and its library, kept in the browser's own store, shows. Everything the server answers as data goes to the
// network, never into the cache: API calls, media, uploads, hints, and the page's own downloads (download_sw.js).
// A copy of a file is replaced by each answer that comes, and used when none does; the page's copy of index.html
// keeps the Content-Security-Policy and nonce it came with.
const CACHE = 'photolib-shell-1';
const DATA = /^\/(photolib\.|media\/|upload|events|healthz|readyz|metrics|diagnostics|passkey|setup\.|download\/|models\/)/;

self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) =>
  event.waitUntil(
    (async () => {
      for (const name of await caches.keys()) if (name !== CACHE) await caches.delete(name);
      await self.clients.claim();
    })(),
  ),
);

// The page says what it loaded, once the worker controls it: the files of a first visit.
self.addEventListener('message', (event) => {
  if (!Array.isArray(event.data?.shell)) return;
  event.waitUntil(
    (async () => {
      const cache = await caches.open(CACHE);
      for (const url of event.data.shell) {
        const { origin, pathname } = new URL(url);
        if (origin !== self.location.origin || DATA.test(pathname)) continue;
        if (!(await cache.match(url))) await cache.add(url).catch(() => {});
      }
    })(),
  );
});

self.addEventListener('fetch', (event) => {
  const { request } = event;
  const url = new URL(request.url);
  if (request.method !== 'GET' || url.origin !== self.location.origin || DATA.test(url.pathname)) return;
  event.respondWith(
    (async () => {
      const cache = await caches.open(CACHE);
      try {
        const answer = await fetch(request);
        if (answer.ok) event.waitUntil(cache.put(request, answer.clone()));
        return answer;
      } catch (error) {
        const kept = (await cache.match(request, { ignoreSearch: true })) ?? (request.mode === 'navigate' ? await cache.match(new URL('./', self.location)) : undefined);
        if (kept) return kept;
        throw error;
      }
    })(),
  );
});
