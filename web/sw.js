// Service worker de la app web (PWA). Guarda los archivos de la app para que
// abra al instante y sin internet. Solo toca archivos de este mismo dominio:
// la API y Google no pasan por aquí.
//
// - Código de la app (index, main.dart.*, bootstrap, version.json): primero la
//   red (si hay versión nueva llega enseguida) y, sin red, lo guardado.
// - Motor gráfico, fuentes, íconos y logo: primero lo guardado y se refresca
//   en segundo plano.
const CACHE = "yankees-web-v1";

const NETWORK_FIRST = [
  /\/$/,
  /\/index\.html$/,
  /\/flutter_bootstrap\.js$/,
  /\/main\.dart\.(js|wasm|mjs)$/,
  /\/version\.json$/,
  /\/manifest\.json$/,
];

self.addEventListener("install", () => self.skipWaiting());

self.addEventListener("activate", (event) => {
  event.waitUntil(
    (async () => {
      for (const key of await caches.keys()) {
        if (key !== CACHE) await caches.delete(key);
      }
      await self.clients.claim();
    })(),
  );
});

async function networkFirst(request) {
  const cache = await caches.open(CACHE);
  try {
    const response = await fetch(request);
    if (response.ok) cache.put(request, response.clone());
    return response;
  } catch (e) {
    const cached = await cache.match(request, { ignoreSearch: true });
    if (cached) return cached;
    // Sin red y sin copia: la app (index) maneja la ruta.
    const shell = await cache.match("./");
    if (shell && request.mode === "navigate") return shell;
    throw e;
  }
}

async function cacheFirst(request, event) {
  const cache = await caches.open(CACHE);
  const cached = await cache.match(request);
  const refresh = fetch(request)
    .then((response) => {
      if (response.ok) cache.put(request, response.clone());
      return response;
    })
    .catch(() => undefined);
  if (cached) {
    event.waitUntil(refresh);
    return cached;
  }
  const response = await refresh;
  if (response) return response;
  throw new Error("Sin conexión");
}

self.addEventListener("fetch", (event) => {
  const request = event.request;
  if (request.method !== "GET") return;
  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;
  if (request.mode === "navigate" || NETWORK_FIRST.some((r) => r.test(url.pathname))) {
    event.respondWith(networkFirst(request));
  } else {
    event.respondWith(cacheFirst(request, event));
  }
});
