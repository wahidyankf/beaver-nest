import type { Page } from "@playwright/test";

// A minimal Absinthe/Phoenix channel subscription client, run *inside* the
// real browser page (via page.evaluate) so the WebSocket handshake carries
// the page's own session cookies automatically -- exactly as a real family
// chat client would connect, and exactly what tech-doc 008 requires (socket
// identity resolves only from the server session, never from client-sent
// params). A Node-side `ws` client would need to forge a Cookie header by
// hand; this avoids that entirely by reusing the browser's real cookie jar.
//
// Wire protocol: Phoenix channels v2 JSON-array serializer
// `[joinRef, ref, topic, event, payload]`, joining the reserved
// `__absinthe__:control` topic, then sending a `doc` event carrying the
// subscription's GraphQL document. Absinthe pushes each event as
// `subscription:data` on the topic equal to the `doc` reply's
// `subscriptionId`.
//
// `runFamilyChatHandshake` executes inside the browser (Playwright
// serializes the function's own source and re-evaluates it in page
// context), so it cannot close over anything outside its own body -- not a
// module-scope const, not a sibling function -- everything it needs (incl.
// `CONTROL_TOPIC`) must be declared inside it. A previous revision hoisted
// `CONTROL_TOPIC` out to shorten a line and broke the handshake with a
// silent in-page `ReferenceError` on every real run; kept as one flat
// listener rather than split across named helpers, which would each need
// the same closured `state`/`resolve`/`reject` passed by hand.

declare global {
  interface Window {
    familyChatSocketState?: {
      socket: WebSocket;
      events: unknown[];
      subscriptionId: string | null;
      ref: number;
    };
  }
}

type ControlReply = { status: string; response?: { subscriptionId?: string } };
type PhoenixFrame = [
  string | null,
  string | null,
  string,
  string,
  Record<string, unknown>,
];
type HandshakeArgs = { query: string; variables: Record<string, unknown> };

function runFamilyChatHandshake({
  query: doc,
  variables: docVariables,
}: HandshakeArgs): Promise<void> {
  return new Promise<void>((resolve, reject) => {
    const CONTROL_TOPIC = "__absinthe__:control";
    const socket = new WebSocket(
      `${window.location.origin.replace(/^http/u, "ws")}/api/graphql/socket/websocket?vsn=2.0.0`,
    );
    const state = {
      socket,
      events: [] as unknown[],
      subscriptionId: null as string | null,
      ref: 1,
    };
    window.familyChatSocketState = state;
    const timeout = setTimeout(
      () => reject(new Error("family chat socket handshake timed out")),
      10_000,
    );
    const send = (event: string, payload: unknown) =>
      socket.send(
        JSON.stringify(["1", String(state.ref), CONTROL_TOPIC, event, payload]),
      );
    socket.addEventListener("open", () => send("phx_join", {}));
    socket.addEventListener("error", () => {
      clearTimeout(timeout);
      reject(new Error("family chat socket connection failed"));
    });
    socket.addEventListener("message", (event: MessageEvent<string>) => {
      const [, , topic, kind, payload] = JSON.parse(event.data) as PhoenixFrame;
      if (topic !== CONTROL_TOPIC || kind !== "phx_reply") {
        if (kind === "subscription:data") state.events.push(payload);
        return;
      }
      const reply = payload as ControlReply;
      if (reply.response?.subscriptionId) {
        state.subscriptionId = reply.response.subscriptionId;
        clearTimeout(timeout);
        resolve();
      } else if (reply.status !== "ok" && state.subscriptionId === null) {
        clearTimeout(timeout);
        reject(new Error(`join/doc rejected: ${JSON.stringify(reply)}`));
      } else {
        state.ref += 1;
        send("doc", { query: doc, variables: docVariables });
      }
    });
  });
}

export async function connectFamilyChatSubscription(
  page: Page,
  query: string,
  variables: Record<string, unknown>,
): Promise<void> {
  await page.evaluate(runFamilyChatHandshake, { query, variables });
}

export function familyChatSubscriptionEvents(page: Page): Promise<unknown[]> {
  return page.evaluate(() => window.familyChatSocketState?.events ?? []);
}

export async function closeFamilyChatSubscription(page: Page): Promise<void> {
  await page.evaluate(() => {
    window.familyChatSocketState?.socket.close();
    delete window.familyChatSocketState;
  });
}
