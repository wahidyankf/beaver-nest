// The real browser transport: `fetch`-based query/mutation over
// `/api/graphql`, and GraphQL subscriptions over Absinthe's control-topic
// protocol on the bare `phoenix` channel client (tech-doc 008; `@absinthe/
// socket` is abandoned upstream -- see Phase 0/3 -- so this implements the
// documented Absinthe.Phoenix wire protocol directly):
//
//   1. Join the `__absinthe__:control` channel once per socket.
//   2. Push a `"doc"` event with `{query, variables}`; the reply carries
//      `{subscriptionId}`.
//   3. Join a channel named after that `subscriptionId`; every commit is
//      pushed to it as a `"subscription:data"` event with `{result}`.
//
// Only constructed by `family_chat.js` when a real browser (`document`)
// exists -- FE_UNIT (Vitest, `environment: "node"`) never imports this
// module's socket path, matching this codebase's established "optional
// real-DOM binding only when `document` exists" pattern.

/** @typedef {import("phoenix").Socket} PhxSocket */
/** @typedef {import("phoenix").Channel} PhxChannel */

const GRAPHQL_PATH = "/api/graphql";
const SOCKET_PATH = "/api/graphql/socket";
const CONTROL_TOPIC = "__absinthe__:control";

function csrfToken() {
  const meta = document.querySelector("meta[name='csrf-token']");
  return meta instanceof HTMLMetaElement ? meta.content : "";
}

/**
 * Real HTTP query/mutation transport used by the outbox and room load.
 * @param {string} query
 * @param {Record<string, unknown>} variables
 */
export async function request(query, variables) {
  const response = await fetch(GRAPHQL_PATH, {
    method: "POST",
    credentials: "same-origin",
    headers: {
      "content-type": "application/json",
      "x-csrf-token": csrfToken(),
    },
    body: JSON.stringify({ query, variables }),
  });
  return response.json();
}

/**
 * @typedef {{
 *   socket: PhxSocket | null,
 *   controlChannel: PhxChannel | null,
 *   hasOpenedBefore: boolean,
 *   reconnectListeners: Set<() => void>,
 * }} SubscriptionState
 */

/** @returns {SubscriptionState} */
function createSubscriptionState() {
  return {
    socket: null,
    controlChannel: null,
    hasOpenedBefore: false,
    reconnectListeners: new Set(),
  };
}

/** @param {SubscriptionState} state */
async function ensureControlChannel(state) {
  if (state.controlChannel) return state.controlChannel;

  const { Socket } = await import("phoenix");
  const socket = new Socket(SOCKET_PATH);
  state.socket = socket;
  // `phoenix`'s own exponential-backoff reconnect fires `onOpen` again after
  // any drop (including a Caddy cutover to a replacement slot) -- every open
  // after the first is exactly the "promoted slot" signal tech-doc 003's
  // reconnect sequence needs to trigger on.
  socket.onOpen(() => {
    if (state.hasOpenedBefore) {
      for (const listener of state.reconnectListeners) listener();
    }
    state.hasOpenedBefore = true;
  });
  socket.connect();

  const joinedChannel = socket.channel(CONTROL_TOPIC, {});
  state.controlChannel = joinedChannel;
  await new Promise((resolve, reject) => {
    joinedChannel.join().receive("ok", resolve).receive("error", reject);
  });
  return joinedChannel;
}

/** @param {SubscriptionState} state */
function createSubscribeMethod(state) {
  /**
   * @param {string} query a GraphQL subscription document.
   * @param {Record<string, unknown>} variables
   * @param {(result: unknown) => void} onData
   * @returns {Promise<{unsubscribe: () => void}>}
   */
  return async function subscribe(query, variables, onData) {
    const channel = await ensureControlChannel(state);
    // `ensureControlChannel` always sets `socket` together with
    // `controlChannel` (never one without the other); this narrows the
    // mutable state field to a `const` the callback below can safely
    // capture, since control-flow narrowing does not persist across an
    // async callback boundary on its own.
    const activeSocket = state.socket;
    if (!activeSocket) {
      throw new Error("family chat socket missing after control channel join");
    }

    return new Promise((resolve, reject) => {
      channel
        .push("doc", { query, variables })
        .receive("ok", ({ subscriptionId }) => {
          const dataChannel = activeSocket.channel(subscriptionId, {});
          dataChannel.on("subscription:data", ({ result }) => onData(result));
          dataChannel
            .join()
            .receive("ok", () =>
              resolve({ unsubscribe: () => dataChannel.leave() }),
            )
            .receive("error", reject);
        })
        .receive("error", reject);
    });
  };
}

/** @param {SubscriptionState} state */
function createLifecycleMethods(state) {
  return {
    /** @param {() => void} callback @returns {() => void} unsubscribe */
    onReconnect(callback) {
      state.reconnectListeners.add(callback);
      return () => state.reconnectListeners.delete(callback);
    },

    close() {
      state.socket?.disconnect();
      state.socket = null;
      state.controlChannel = null;
      // A fresh socket's very next open is a genuine first connect, not a
      // reconnect -- closing must not leave a stale "already open once"
      // memory behind for it.
      state.hasOpenedBefore = false;
    },

    /**
     * Forces a fresh connection attempt, bypassing phoenix's own `connect()`
     * no-op guard (it skips connecting whenever a connection object still
     * exists, even if the underlying transport silently died -- exactly
     * what a mobile PWA's background suspension does). Deliberately does
     * not reset `hasOpenedBefore`, unlike `close()`: the next `onOpen` must
     * still be recognized as a reconnect, so the existing reconnect
     * listeners (and the catch-up sequence they run) fire for it.
     */
    reconnectNow() {
      state.socket?.disconnect(() => state.socket?.connect());
    },
  };
}

/**
 * Lazily builds one `phoenix` Socket and one control-channel join per page,
 * shared by every subscription this room opens.
 */
export function createSubscriptionClient() {
  const state = createSubscriptionState();
  return {
    subscribe: createSubscribeMethod(state),
    ...createLifecycleMethods(state),
  };
}
