import assert from "node:assert/strict";
import test from "node:test";
import {
  armedPage,
  CONTROL_TOPIC,
  documentOf,
  type FakeLive,
  type FakeRoute,
  fakePage,
  fakeSocket,
  frame,
  ROOM,
  wire,
} from "./family-chat-wire-harness.mts";

// The earlier-revision wire, driven without a browser (see the harness). It covers the late refusals the rollback-floor
// Thens must wait for, and the subscription pushes that carry errors.

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
