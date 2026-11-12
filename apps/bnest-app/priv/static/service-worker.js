// v2 drops the "/" entry v1 precached: `cache.addAll` sends the session
// cookie, so v1 could hold a signed-in page. Bumping the name is what makes
// `activate` delete that older cache on every device that still has it.
const CACHE_NAME = "beaver-nest-shell-v2";
// Static files only -- never a page. A page is per-visitor and may be signed
// in, so no navigation response is ever written to Cache Storage.
const APP_SHELL = [
  "/manifest.webmanifest",
  "/assets/css/app.css",
  "/assets/js/app.js",
  "/images/beaver-nest-192.png",
  "/images/beaver-nest-512.png",
];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches
      .open(CACHE_NAME)
      .then((cache) => cache.addAll(APP_SHELL))
      .then(() => self.skipWaiting()),
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) =>
        Promise.all(
          keys
            .filter((key) => key !== CACHE_NAME)
            .map((key) => caches.delete(key)),
        ),
      )
      .then(() => self.clients.claim()),
  );
});

// Diagram chunks have content-hashed names, so every release adds new ones.
// Each is cached as it is used; once more than DIAGRAM_CACHE_LIMIT sit under
// the prefix, the oldest are deleted. Cache Storage lists entries in the order
// they were written, so the first matching keys are the oldest.
const DIAGRAM_PREFIX = "/assets/js/diagrams/";
const DIAGRAM_CACHE_LIMIT = 120;

// Best effort: a failed delete leaves extra entries for a later write to trim,
// and must never change the response that was already sent.
async function trimDiagramChunks(cache) {
  try {
    const keys = (await cache.keys()).filter((request) =>
      new URL(request.url).pathname.startsWith(DIAGRAM_PREFIX),
    );
    const excess = keys.length - DIAGRAM_CACHE_LIMIT;
    if (excess <= 0) return;
    await Promise.all(
      keys.slice(0, excess).map((request) => cache.delete(request)),
    );
  } catch {
    // Left for the next diagram write to trim again.
  }
}

self.addEventListener("fetch", (event) => {
  if (event.request.method !== "GET") return;

  // Only true static build assets of this origin are ever written to or read
  // from Cache Storage (Family Chat plan requirement: authenticated GraphQL/page
  // responses must never be cached). A third-party image with a static-looking
  // path is never answered here either (ADR 003, Decision 3).
  // `assets/test/unit/service_worker.test.ts` runs this file to prove it.
  const url = new URL(event.request.url);
  const sameOrigin = url.origin === self.location.origin;
  const cacheable =
    sameOrigin &&
    (url.pathname.startsWith("/assets/") ||
      url.pathname.startsWith("/images/"));

  if (cacheable) {
    event.respondWith(
      fetch(event.request)
        .then((response) => {
          if (response.ok) {
            const diagramChunk = url.pathname.startsWith(DIAGRAM_PREFIX);
            const copy = response.clone();
            // The write is handed to waitUntil. A write left unawaited can
            // stay unfinished once the browser suspends the idle worker.
            event.waitUntil(
              caches
                .open(CACHE_NAME)
                .then((cache) =>
                  cache
                    .put(event.request, copy)
                    .then(() =>
                      diagramChunk ? trimDiagramChunks(cache) : undefined,
                    ),
                )
                .catch(() => {
                  // A failed write only means the next load fetches again.
                }),
            );
          }

          return response;
        })
        .catch(() => caches.match(event.request)),
    );
    return;
  }

  // Every other request -- every authenticated page and every GraphQL
  // response included -- always goes straight to the network, never cached
  // and never served from cache. A failed top-level navigation while
  // offline gets a page built here rather than a bare browser error; it
  // carries nothing about the visitor, and is never stored.
  if (sameOrigin && event.request.mode === "navigate") {
    event.respondWith(fetch(event.request).catch(() => offlinePage()));
  }
});

const OFFLINE_PAGE = `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Beaver Nest</title>
    <link rel="stylesheet" href="/assets/css/app.css" />
  </head>
  <body>
    <main>
      <h1>Beaver Nest</h1>
      <p>You are offline. Reconnect to open this page.</p>
    </main>
  </body>
</html>`;

function offlinePage() {
  return new Response(OFFLINE_PAGE, {
    status: 503,
    headers: { "content-type": "text/html; charset=utf-8" },
  });
}

// The one room this plan seeds; tech-doc 004 fixes both the payload's `url`
// and the generic fallback notification to this exact same-origin path.
const ROOM_PATH = "/family-chat/ruang-keluarga";

const GENERIC_NOTIFICATION_PAYLOAD = {
  title: "New family message",
  body: "",
  tag: "family-chat-message",
  url: ROOM_PATH,
};

// Literal copy of `assets/js/family_chat/push.js`'s `resolveNotificationPayload`
// -- this classic, unbundled worker script (registered without
// `{type: "module"}`) cannot `import` that ES module, so it keeps its own
// copy of the same bounded-parse rule rather than importing it. Keep both
// copies in sync when either changes.
function resolveNotificationPayload(rawData) {
  if (
    rawData !== null &&
    typeof rawData === "object" &&
    rawData.type === "family-chat-message" &&
    typeof rawData.title === "string" &&
    typeof rawData.body === "string" &&
    typeof rawData.tag === "string" &&
    rawData.url === ROOM_PATH
  ) {
    return {
      title: rawData.title,
      body: rawData.body,
      tag: rawData.tag,
      url: rawData.url,
    };
  }

  return GENERIC_NOTIFICATION_PAYLOAD;
}

// Literal copy of `assets/js/family_chat/push.js`'s
// `resolveNotificationClickTarget` -- same import boundary as above. Never
// trusts arbitrary stored notification data as a navigation target.
function resolveNotificationClickTarget(rawData) {
  if (
    rawData !== null &&
    typeof rawData === "object" &&
    rawData.url === ROOM_PATH
  ) {
    return rawData.url;
  }

  return ROOM_PATH;
}

// A bounded JSON object is parsed defensively -- `event.data.json()` itself
// throws on non-JSON bytes, and `resolveNotificationPayload` rejects
// anything that is not exactly the expected shape -- so invalid or missing
// push data always displays the generic same-room notification rather than
// unvalidated content or a thrown error (tech-doc 004).
self.addEventListener("push", (event) => {
  let rawData = null;
  try {
    rawData = event.data ? event.data.json() : null;
  } catch {
    rawData = null;
  }

  const payload = resolveNotificationPayload(rawData);

  event.waitUntil(
    self.registration.showNotification(payload.title, {
      body: payload.body,
      tag: payload.tag,
      data: { url: payload.url },
    }),
  );
});

// Accepts only the one same-origin fixed room path (never arbitrary stored
// data), closes the notification, and focuses an existing Bnest client when
// one is already open on that path, focuses-then-navigates an existing
// client on a different path, or opens a new client only when none exists
// (tech-doc 004).
self.addEventListener("notificationclick", (event) => {
  const targetUrl = resolveNotificationClickTarget(event.notification.data);
  event.notification.close();

  event.waitUntil(
    self.clients
      .matchAll({ type: "window", includeUncontrolled: true })
      .then((clientList) => {
        for (const client of clientList) {
          if (new URL(client.url).pathname === targetUrl) {
            return "focus" in client ? client.focus() : undefined;
          }
        }

        for (const client of clientList) {
          if ("focus" in client) {
            return Promise.resolve(client.focus()).then(() =>
              "navigate" in client ? client.navigate(targetUrl) : undefined,
            );
          }
        }

        return self.clients.openWindow
          ? self.clients.openWindow(targetUrl)
          : undefined;
      }),
  );
});
