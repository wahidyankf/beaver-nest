// Push permission UX (real browser only; never reached by FE_UNIT, which
// injects `devicePushState`/`activePushSubscription` directly instead) --
// split out of `family_chat.js` purely to stay under this project's
// max-lines lint budget.

import { request as graphqlRequest } from "./graphql.js";
import { urlBase64ToUint8Array } from "./push.js";
import {
  WEB_PUSH_CONFIGURATION_QUERY,
  CURRENT_WEB_PUSH_SUBSCRIPTION_QUERY,
  UPSERT_WEB_PUSH_SUBSCRIPTION_MUTATION,
  DISABLE_CURRENT_WEB_PUSH_SUBSCRIPTION_MUTATION,
} from "./operations.js";

/**
 * Feature-detects which of `push.js`'s five device states currently applies.
 * iOS/iPadOS Safari lacks `Notification`/`PushManager` entirely until
 * installed as a Home Screen web app (tech-doc 004, citing WebKit's "Web
 * Push for Web Apps on iOS and iPadOS"), so a non-standalone session on that
 * platform is asked to install first -- installing resolves the gap --
 * rather than told push is simply unsupported.
 */
export function detectDevicePushState() {
  const supported =
    typeof Notification !== "undefined" &&
    typeof navigator !== "undefined" &&
    "serviceWorker" in navigator &&
    typeof PushManager !== "undefined";

  if (!supported) return detectUnsupportedPushState();

  if (Notification.permission === "denied") return "permission denied";
  return "available, not yet decided";
}

function detectUnsupportedPushState() {
  const isIOSDevice = /iPad|iPhone|iPod/u.test(navigator.userAgent ?? "");
  // `navigator.standalone` is a non-standard iOS Safari extension absent
  // from the DOM lib's `Navigator` type; read it through a narrow cast
  // rather than widening the whole function to `any`.
  const opaqueNavigator =
    /** @type {unknown} */
    (navigator);
  const iosNavigator =
    /** @type {{standalone?: boolean}} */
    (opaqueNavigator);
  const isStandalone =
    iosNavigator.standalone === true ||
    (typeof window.matchMedia === "function" &&
      window.matchMedia("(display-mode: standalone)").matches);
  return isIOSDevice && !isStandalone ? "requires installation" : "unsupported";
}

/** Real read of whether this authenticated session already has a binding,
 * used only to set the control's initial rendered state on room load. */
export async function fetchCurrentSubscriptionActive() {
  try {
    const result = await graphqlRequest(
      CURRENT_WEB_PUSH_SUBSCRIPTION_QUERY,
      {},
    );
    return Boolean(result.data?.currentWebPushSubscription?.enabled);
  } catch {
    return false;
  }
}

/**
 * The one real subscribe attempt: reads the public VAPID key, requests
 * permission (must run inside this function's own caller, a click handler,
 * so the browser recognizes the required user gesture -- page load never
 * calls this), subscribes through the real Push API, and binds the result
 * server-side. Returns whether the session ends up genuinely enabled.
 */
export async function attemptPushSubscribe() {
  const configResult = await graphqlRequest(WEB_PUSH_CONFIGURATION_QUERY, {});
  const config = configResult.data?.webPushConfiguration;
  if (!config?.available || !config.publicKey) return false;

  const permission = await Notification.requestPermission();
  if (permission !== "granted") return false;

  const registration = await navigator.serviceWorker.ready;
  const subscription = await registration.pushManager.subscribe({
    userVisibleOnly: true,
    applicationServerKey: urlBase64ToUint8Array(config.publicKey),
  });
  const keys = subscription.toJSON().keys ?? {};
  if (!keys["p256dh"] || !keys["auth"]) return false;

  const upsertResult = await graphqlRequest(
    UPSERT_WEB_PUSH_SUBSCRIPTION_MUTATION,
    {
      endpoint: subscription.endpoint,
      p256dh: keys["p256dh"],
      auth: keys["auth"],
    },
  );
  return Boolean(upsertResult.data?.upsertWebPushSubscription?.enabled);
}

/** The one real disable attempt: server-side first (the source of truth for
 * whether delivery continues), then a best-effort browser-side unsubscribe
 * so a stale local subscription is not left registered either. */
export async function attemptPushDisable() {
  try {
    await graphqlRequest(DISABLE_CURRENT_WEB_PUSH_SUBSCRIPTION_MUTATION, {});
  } finally {
    try {
      const registration = await navigator.serviceWorker.ready;
      const subscription = await registration.pushManager.getSubscription();
      if (subscription) await subscription.unsubscribe();
    } catch {
      // Best-effort only; the server-side disable above already governs
      // whether delivery continues regardless of local cleanup success.
    }
  }
}
