const CACHE_NAME = "beaver-nest-shell-v1";
const APP_SHELL = [
  "/",
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

self.addEventListener("fetch", (event) => {
  if (event.request.method !== "GET") return;

  // Only true static build assets are ever written to or read from Cache
  // Storage (Family Chat plan requirement: authenticated GraphQL/page
  // responses must never be cached). This is a literal copy of
  // `assets/js/family_chat/cache_policy.js`'s `shouldCachePathname`
  // predicate -- this classic, unbundled worker script cannot `import` that
  // ES module (registered without `{type: "module"}`), so it keeps its own
  // copy of the same one-line rule rather than importing it (see that
  // file's matching comment).
  const pathname = new URL(event.request.url).pathname;
  const cacheable =
    pathname.startsWith("/assets/") || pathname.startsWith("/images/");

  if (cacheable) {
    event.respondWith(
      fetch(event.request)
        .then((response) => {
          if (response.ok) {
            caches
              .open(CACHE_NAME)
              .then((cache) => cache.put(event.request, response.clone()));
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
  // offline still falls back to the pre-installed app shell (`/`) rather
  // than a bare browser error, but nothing dynamic is ever read back from
  // Cache Storage.
  if (event.request.mode === "navigate") {
    event.respondWith(fetch(event.request).catch(() => caches.match("/")));
  }
});

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
// -- this classic, unbundled worker script cannot `import` that ES module
// (see this file's matching comment on the `fetch` handler above), so it
// keeps its own copy of the same bounded-parse rule rather than importing
// it. Keep both copies in sync when either changes.
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
