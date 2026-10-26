// World Clock service worker. Cache-first for the app shell, nothing else.
// Weather (api.open-meteo.com) and fonts are never cached here; both already fail soft offline.
// The shell is served from cache and refreshed in the background, so a new version shows on the next open.
const CACHE = "worldclock-shell-v1";
const SHELL = ["./", "./index.html", "./manifest.webmanifest"];

self.addEventListener("install", e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL)).then(() => self.skipWaiting()));
});

self.addEventListener("activate", e => {
  e.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", e => {
  const req = e.request;
  if (req.method !== "GET") return;
  const url = new URL(req.url);
  if (url.origin !== location.origin) return; // weather, fonts: straight to the network, never stored
  e.respondWith(
    caches.match(req, { ignoreSearch: true }).then(cached => {
      const fresh = fetch(req)
        .then(res => { if (res && res.ok) caches.open(CACHE).then(c => c.put(req, res.clone())); return res; })
        .catch(() => cached);
      return cached || fresh;
    })
  );
});
