import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { register } from "node:module";
import path from "node:path";
import test from "node:test";
import type { Page } from "@playwright/test";

// The earlier-revision wire, driven without a browser: the page is a fake whose route handlers are captured, so the
// socket and HTTP handlers run against scripted frames. It covers the late refusals the rollback-floor Thens must wait
// for, and the subscription pushes that carry errors.

// The wire imports extensionless TypeScript siblings, and this package is commonjs, so node --test needs a loader that
// resolves those names and loads the app's TypeScript as modules. The judge test has the narrower form of this hook.
const TS_MODULE_HOOK = `export async function resolve(specifier, context, nextResolve) {
  try {
    return await nextResolve(specifier, context);
  } catch (error) {
    if (error.code !== "ERR_MODULE_NOT_FOUND" || !specifier.startsWith(".")) throw error;
    for (const extension of [".ts", ".mts"]) {
      try {
        return await nextResolve(specifier + extension, context);
      } catch {
        // Not this extension: try the next one.
      }
    }
    throw error;
  }
}
export async function load(url, context, nextLoad) {
  if (/\\/apps\\/bnest-app-fe-e2e\\/.*\\.m?ts$/u.test(url))
    return nextLoad(url, { ...context, format: "module-typescript" });
  return nextLoad(url, context);
}`;
register(`data:text/javascript,${encodeURIComponent(TS_MODULE_HOOK)}`);
const wire = await import("./family-chat-previous-revision.ts");

// The frozen previous bundle's documents: the wire replays these in place of what the page sends.
const FIXTURE = path.resolve(
  import.meta.dirname,
  "../../../bnest-app/assets/test/support/family_chat_previous_revision.json",
);
const fixture = JSON.parse(readFileSync(FIXTURE, "utf8")) as {
  previousClient: { documents: Record<string, { document: string }> };
};
const documentOf = (operation: string): string => {
  const entry = fixture.previousClient.documents[operation];
  assert.ok(entry, `the frozen bundle has no ${operation} document`);
  return entry.document;
};

const CONTROL_TOPIC = "__absinthe__:control";
const ROOM = "ruang-keluarga";
const frame = (...parts: unknown[]): string => JSON.stringify(parts);

type Message = string | Buffer;
type Handler = (message: Message) => void;

/** A socket the wire takes over: its page side, and the server side it connects to. */
function fakeSocket() {
  const handlers: { fromPage?: Handler; fromServer?: Handler } = {};
  const sent = { toServer: [] as Message[], toPage: [] as Message[] };
  const socket = {
    onMessage: (handler: Handler) => {
      handlers.fromPage = handler;
    },
    connectToServer: () => ({
      onMessage: (handler: Handler) => {
        handlers.fromServer = handler;
      },
      send: (message: Message) => {
        sent.toServer.push(message);
      },
    }),
    send: (message: Message) => {
      sent.toPage.push(message);
    },
  };
  return {
    socket,
    sent,
    fromPage: (message: Message) => handlers.fromPage?.(message),
    fromServer: (message: Message) => handlers.fromServer?.(message),
  };
}
type FakeWebSocket = ReturnType<typeof fakeSocket>["socket"];

type FakeLive = { ok(): boolean; status(): number; text(): Promise<string> };
type FakeRoute = {
  request(): { postData(): string };
  fetch(options: { postData: string }): Promise<FakeLive>;
  fulfill(options: { response: FakeLive }): string;
  continue(options?: { postData: string }): string;
  abort(): string;
};

/** A page that keeps the handlers the wire registers, so a test can call them as the browser would. */
function fakePage() {
  const routes: {
    http?: (route: FakeRoute) => unknown;
    socket?: (socket: FakeWebSocket) => unknown;
  } = {};
  const page = {
    route: (_pattern: string, handler: (route: FakeRoute) => unknown) => {
      routes.http = handler;
      return Promise.resolve();
    },
    routeWebSocket: (
      _pattern: RegExp,
      handler: (socket: FakeWebSocket) => unknown,
    ) => {
      routes.socket = handler;
      return Promise.resolve();
    },
  };
  return { page: page as unknown as Page, routes };
}

/** A page armed as the rollback floor arms it: the previous bundle's documents replayed, and every document judged. */
async function armedPage() {
  const { page, routes } = fakePage();
  await wire.sendPreviousBundleDocuments(page);
  wire.judgeAgainstRolledBackSlot(page);
  const ws = fakeSocket();
  assert.ok(routes.socket, "the socket route was not registered");
  await routes.socket(ws.socket);
  return { routes, ws };
}

test("judging a page whose wire was not installed before it loaded fails loudly", () => {
  // Playwright routes a socket through the patch it injects into each new document, so a route added to an already
  // loaded page never sees that page's reconnects: the held page would run unjudged and the Thens would time out.
  const { page, routes } = fakePage();
  assert.throws(
    () => wire.judgeAgainstRolledBackSlot(page),
    /install the wire before the page loads/u,
  );
  assert.equal(routes.socket, undefined, "judging installed a late route");
});

test("a page whose wire was installed before it loaded can then be judged", async () => {
  const { page, routes } = fakePage();
  await wire.routeGraphqlWire(page);
  assert.ok(routes.socket, "the socket route was not registered");
  wire.judgeAgainstRolledBackSlot(page);
  const ws = fakeSocket();
  await routes.socket(ws.socket);
  ws.fromPage(
    frame("1", "5", CONTROL_TOPIC, "doc", {
      query:
        "subscription FamilyChatMessageCommitted($roomSlug: String!) { familyChatMessageCommitted(roomSlug: $roomSlug) { id } }",
      variables: { roomSlug: ROOM },
    }),
  );
  ws.fromServer(
    frame("1", "5", CONTROL_TOPIC, "phx_reply", { status: "ok", response: {} }),
  );
  assert.equal(
    wire.previousRevisionTraffic.answered.has("FamilyChatMessageCommitted"),
    true,
  );
});

/**
 * The step's bounded poll, as a loop: resolves once the condition holds, and rejects with the message when it does not
 * within the timeout. It checks on a timer, so no await sits inside a loop.
 */
function settle(
  condition: () => boolean,
  timeoutMs: number,
  message: string,
): Promise<void> {
  const deadline = Date.now() + timeoutMs;
  return new Promise((resolve, reject) => {
    const check = () => {
      if (condition()) resolve();
      else if (Date.now() >= deadline) reject(new Error(message));
      else setTimeout(check, 25);
    };
    check();
  });
}

test("a subscription push that carries errors is recorded as a live refusal", async () => {
  const { ws } = await armedPage();
  ws.fromServer(
    frame(null, null, "subscription-1", "subscription:data", {
      subscriptionId: "subscription-1",
      result: { data: { familyChatMessageCommitted: { id: "1" } } },
    }),
  );
  assert.deepEqual(wire.liveRefusals(), []);
  ws.fromServer(
    frame(null, null, "subscription-1", "subscription:data", {
      subscriptionId: "subscription-1",
      result: { errors: [{ message: "boom" }] },
    }),
  );
  assert.deepEqual(wire.liveRefusals(), [
    'subscription: subscription:data errors [{"message":"boom"}]',
  ]);
});

test("a refused subscription reply that lands after ready is recorded, and the bounded wait on its record sees it", async () => {
  const { ws } = await armedPage();
  // The page's own text is replaced by the frozen one, so the replayed subscription is judged as the bundle sends it.
  ws.fromPage(
    frame("1", "5", CONTROL_TOPIC, "doc", {
      query:
        "subscription FamilyChatMessageCommitted($roomSlug: String!) { familyChatMessageCommitted(roomSlug: $roomSlug) { id } }",
      variables: { roomSlug: ROOM },
    }),
  );
  const [sentToServer] = ws.sent.toServer;
  assert.ok(sentToServer !== undefined, "the subscription was not sent");
  const [, , , , sentPayload] = JSON.parse(String(sentToServer)) as [
    unknown,
    unknown,
    unknown,
    unknown,
    { query: string },
  ];
  assert.equal(sentPayload.query, documentOf("FamilyChatMessageCommitted"));

  // The ready point: the step's single read happens here, before the late reply arrives.
  assert.deepEqual(wire.liveRefusals(), []);

  const lateReply = frame("1", "5", CONTROL_TOPIC, "phx_reply", {
    status: "error",
    response: { errors: [{ message: "boom" }] },
  });
  setTimeout(() => ws.fromServer(lateReply), 50);

  await settle(
    () =>
      wire.previousRevisionTraffic.answered.has("FamilyChatMessageCommitted"),
    15_000,
    "the live server never answered the replayed FamilyChatMessageCommitted subscription",
  );
  assert.deepEqual(wire.liveRefusals(), [
    `FamilyChatMessageCommitted: socket reply error ${JSON.stringify({ errors: [{ message: "boom" }] })}`,
  ]);
});

test("a live HTTP answer to a watched operation is recorded, and a clean answer is not a refusal", async () => {
  const { routes } = await armedPage();
  const answer: FakeLive = {
    ok: () => true,
    status: () => 200,
    text: () =>
      Promise.resolve(
        JSON.stringify({ data: { familyChatMessages: { nodes: [] } } }),
      ),
  };
  const delivered: FakeLive[] = [];
  const route: FakeRoute = {
    request: () => ({
      postData: () =>
        JSON.stringify({
          query: documentOf("FamilyChatMessages"),
          variables: { roomSlug: ROOM },
        }),
    }),
    fetch: () => Promise.resolve(answer),
    fulfill: ({ response }) => {
      delivered.push(response);
      return "fulfilled";
    },
    continue: () => "continued",
    abort: () => "aborted",
  };
  assert.ok(routes.http, "the GraphQL route was not registered");
  await routes.http(route);
  assert.equal(
    wire.previousRevisionTraffic.answered.has("FamilyChatMessages"),
    true,
  );
  assert.equal(
    wire.previousRevisionTraffic.answered.has("FamilyChatMessageCommitted"),
    false,
  );
  assert.deepEqual(wire.liveRefusals(), []);
  assert.deepEqual(delivered, [answer]);
});
