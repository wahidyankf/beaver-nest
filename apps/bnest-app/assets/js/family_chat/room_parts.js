// The collaborators a Family Chat room is built from, and how each one is
// resolved for the environment it runs in -- a real browser (fetch, a real
// `phoenix` socket, real IndexedDB, the shipped `room.html.heex` DOM) or the
// deterministic in-memory doubles the FE_UNIT harness uses. Split out of
// `family_chat.js` purely to stay under this project's max-lines lint
// budget; `family_chat.js` is the only importer.
//
// Real IndexedDB binding (tech-doc 003's promised cross-reload queue
// durability, and tech-doc 007's Release Invariants table, which marks
// IndexedDB "Active for authenticated room" once the Experience stage
// begins): `createRoomPushAndOutbox` below is the "attached separately by
// `family_chat.js`" seam `outbox.js`'s own header comment describes -- see
// `persistence_indexeddb.js` for the real implementation, only ever
// constructed on the `hasDocument` branch.

import { createOutbox } from "./outbox.js";
import { createRealPageSource, createTestPageSource } from "./page_source.js";
import { resolvePersistence } from "./persistence_indexeddb.js";
import { createReconnect } from "./reconnect.js";
import { createStore } from "./store.js";
import { createPush } from "./push.js";
import { createSubscriptionClient } from "./graphql.js";
import { createRealTransport, createTestTransport } from "./transport.js";
import { detectDevicePushState } from "./push_ux.js";
import { createRealStore } from "./real_store.js";

/**
 * @param {import("./elements.js").FamilyChatElements | null} elements
 * @param {{remediationMessage: string | null}} composerState
 */
export function handleQueueFull(elements, composerState) {
  composerState.remediationMessage =
    "Keep waiting messages under 100, or retry/discard one first.";
  if (elements) {
    elements.remediation.hidden = false;
    elements.remediation.textContent = composerState.remediationMessage;
  }
}

/**
 * @param {string} roomSlug
 * @param {boolean} hasDocument
 * @param {import("./elements.js").FamilyChatElements | null} elements
 * @param {{user?: {id: string}, activePushSubscription?: boolean, devicePushState?: string, persistence?: import("./outbox_send.js").Persistence | undefined}} options
 * @param {import("./clock.js").Clock} clock
 * @param {{remediationMessage: string | null}} composerState
 */
export async function createRoomPushAndOutbox(
  roomSlug,
  hasDocument,
  elements,
  options,
  clock,
  composerState,
) {
  const transport = hasDocument
    ? createRealTransport(roomSlug)
    : createTestTransport(clock);

  const push = createPush({
    devicePushState: hasDocument
      ? detectDevicePushState()
      : options.devicePushState,
    activePushSubscription: options.activePushSubscription,
    onDisable: () => {},
  });

  const userId = options.user?.id ?? "anonymous";
  const persistence = await resolvePersistence(
    hasDocument,
    userId,
    roomSlug,
    options.persistence,
  );

  const outbox = createOutbox({
    userId,
    roomSlug,
    clock,
    transport,
    persistence,
    onQueueFull: () => handleQueueFull(elements, composerState),
    onLogout: () => {
      push.disable();
    },
    onAuthExpired: () => {
      if (elements?.room)
        elements.room.dataset["connectionState"] = "auth-expired";
    },
  });

  return { push, outbox };
}

/**
 * @param {string} roomSlug
 * @param {boolean} hasDocument
 * @param {import("./elements.js").FamilyChatElements | null} elements
 * @param {{user?: {id: string}, scrolledToOlderMessage?: boolean, focusInComposer?: boolean}} options
 * @param {import("./clock.js").Clock} clock
 */
export function createRoomStoreAndReconnect(
  roomSlug,
  hasDocument,
  elements,
  options,
  clock,
) {
  // `hasDocument` and `elements` are always both-true or both-false together
  // (`elements` is set from `findElements()` exactly when `hasDocument`
  // is), but TS tracks them as two independent variables; the `elements`
  // check alone is what narrows the branch below, `hasDocument` is kept for
  // readability at the call site.
  const store =
    hasDocument && elements
      ? createRealStore({
          roomSlug,
          elements,
          currentUserId: options.user?.id ?? null,
        })
      : createStore({
          scrolledToOlderMessage: options.scrolledToOlderMessage,
          focusInComposer: options.focusInComposer,
        });

  const subscriptionClient = hasDocument ? createSubscriptionClient() : null;
  // `store`/`roomSlug` are deliberately not passed here: `createReconnect`
  // (see `family_chat/reconnect.js`) only ever reads `clock`/`socketClient`
  // from its options; the real store/room wiring happens later, through
  // `bindBrowserCallbacks` in `mount_browser.js`.
  const reconnect = createReconnect({
    clock,
    socketClient: subscriptionClient,
  });

  return { store, subscriptionClient, reconnect };
}

/**
 * `accessibility.js` reads the shipped template/stylesheet from disk via
 * `node:fs` -- meaningful only for FE_UNIT's Vitest (Node) process, never
 * for a real browser (no such module exists there, and no browser code path
 * ever calls it -- see `family_chat.steps.ts`, its only caller).
 * Dynamically importing it only on this branch (never reached with a real
 * `document`) keeps that Node-only dependency out of the browser bundle
 * entirely, rather than a top-level import that esbuild would otherwise
 * have to resolve for every page.
 * @param {boolean} hasDocument
 * @param {{viewport?: string}} options
 */
export async function createRoomAccessibility(hasDocument, options) {
  if (hasDocument) return;
  const { createAccessibility } = await import("./accessibility.js");
  return createAccessibility({ viewport: options.viewport });
}

/**
 * The room's own page source: the real GraphQL query in a browser, and the
 * deterministic in-memory room the FE_UNIT harness seeds otherwise. A caller
 * that already has one (a scenario reopening the same room a second time)
 * passes it back in, exactly as it does for the outbox's `persistence`.
 * @param {string} roomSlug
 * @param {boolean} hasDocument
 * @param {{pageSource?: ReturnType<typeof createTestPageSource> | undefined, messages?: import("./real_store.js").RenderableMessage[] | undefined}} options
 */
export function resolvePageSource(roomSlug, hasDocument, options) {
  if (hasDocument) return createRealPageSource(roomSlug);
  return options.pageSource ?? createTestPageSource(options.messages ?? []);
}
