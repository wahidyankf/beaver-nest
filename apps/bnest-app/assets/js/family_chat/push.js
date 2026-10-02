// Web Push permission UX (tech-doc 005's control-text table), and the
// notification payload rules the service worker keeps a copy of. The device
// state itself is read from the browser by `push_ux.js`.

export const CONTROL_TEXT = Object.freeze({
  UNSUPPORTED: "Notifications unavailable in this browser",
  REQUIRES_INSTALL: "Install Beaver Nest first",
  DENIED: "Notifications blocked",
  ON: "Notifications on",
  OFF: "Enable notifications",
});

// The one room this plan seeds; tech-doc 004 fixes both the payload's `url`
// and the generic fallback notification to this exact same-origin path.
const ROOM_PATH = "/family-chat/ruang-keluarga";

const GENERIC_NOTIFICATION_PAYLOAD = Object.freeze({
  title: "New family message",
  body: "",
  tag: "family-chat-message",
  url: ROOM_PATH,
});

/**
 * Parses a service worker `push` event's decoded JSON data into the bounded
 * notification payload tech-doc 004 specifies, ignoring unknown keys and
 * never throwing. Anything that is not exactly the expected
 * `family-chat-message` shape (including no data at all, non-object data,
 * or a mismatched `url`) resolves to the generic same-room fallback rather
 * than displaying unvalidated content.
 *
 * `priv/static/service-worker.js` is a classic (non-module) worker script
 * and cannot `import` this function -- it keeps its own literal copy of
 * this exact logic. Keep both copies in sync when either changes.
 *
 * @param {unknown} rawData
 */
export function resolveNotificationPayload(rawData) {
  if (rawData === null || typeof rawData !== "object")
    return GENERIC_NOTIFICATION_PAYLOAD;

  const data =
    /** @type {Record<string, unknown>} */
    (rawData);

  if (
    data["type"] === "family-chat-message" &&
    typeof data["title"] === "string" &&
    typeof data["body"] === "string" &&
    typeof data["tag"] === "string" &&
    data["url"] === ROOM_PATH
  ) {
    return {
      title: data["title"],
      body: data["body"],
      tag: data["tag"],
      url: data["url"],
    };
  }

  return GENERIC_NOTIFICATION_PAYLOAD;
}

/** @param {unknown} rawData @returns {unknown} */
function readUrlField(rawData) {
  if (rawData === null || typeof rawData !== "object") return;
  const record =
    /** @type {Record<string, unknown>} */
    (rawData);
  return record["url"];
}

/**
 * Validates a `notificationclick` event's stored `notification.data` against
 * the one same-origin fixed room path this plan supports. Never trusts
 * arbitrary stored data as a navigation target -- anything that is not
 * exactly the known room path resolves to that same fixed path. See
 * `resolveNotificationPayload`'s comment for why the service worker keeps
 * its own literal copy of this logic instead of importing it.
 *
 * @param {unknown} rawData
 */
export function resolveNotificationClickTarget(rawData) {
  const allowedPaths =
    /** @type {ReadonlySet<string>} */
    (new Set([ROOM_PATH]));
  const url = readUrlField(rawData);

  // v1 seeds exactly one room, so `allowedPaths` has exactly one member
  // today; this still validates against the allowlist itself (not a
  // hardcoded equality check) so a future additional room's path does not
  // require rewriting this function's logic, only extending the set.
  return typeof url === "string" && allowedPaths.has(url) ? url : ROOM_PATH;
}

/**
 * Converts a VAPID public key (URL-safe base64, as returned by
 * `webPushConfiguration`) into the raw `Uint8Array` shape
 * `PushManager.subscribe`'s `applicationServerKey` option requires. Pure and
 * side-effect-free -- unit-tested directly (`atob` is available in both a
 * real browser and Vitest's Node environment).
 *
 * @param {string} base64String
 */
export function urlBase64ToUint8Array(base64String) {
  const padding = "=".repeat((4 - (base64String.length % 4)) % 4);
  const base64 = (base64String + padding)
    .replaceAll("-", "+")
    .replaceAll("_", "/");
  const rawData = atob(base64);
  const outputArray = new Uint8Array(rawData.length);
  for (let index = 0; index < rawData.length; index += 1) {
    outputArray[index] = rawData.codePointAt(index) ?? 0;
  }
  return outputArray;
}

/**
 * The room's push control: what it says for this device, and whether this
 * session is subscribed. Only the server decides the latter -- `enable` is
 * called once it confirms a binding -- while the device state decides
 * whether there is anything to enable at all.
 * @param {{devicePushState?: string | undefined}} options
 */
export function createPush({ devicePushState } = {}) {
  const state = { enabled: false };

  return {
    controlText() {
      if (devicePushState === "unsupported") return CONTROL_TEXT.UNSUPPORTED;
      if (devicePushState === "requires installation")
        return CONTROL_TEXT.REQUIRES_INSTALL;
      if (devicePushState === "permission denied") return CONTROL_TEXT.DENIED;
      return state.enabled ? CONTROL_TEXT.ON : CONTROL_TEXT.OFF;
    },

    /** @param {string} control */
    async select(control) {
      await Promise.resolve();
      if (control === "Turn off") state.enabled = false;
    },

    // Called only after a real `upsertWebPushSubscription` mutation (or an
    // initial `currentWebPushSubscription` read) confirms this session
    // genuinely has an active binding -- never optimistically, before the
    // server has agreed.
    enable() {
      state.enabled = true;
    },
  };
}
