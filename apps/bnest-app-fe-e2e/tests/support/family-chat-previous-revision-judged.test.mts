import assert from "node:assert/strict";
import test from "node:test";
import {
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

// What the held page's judged documents are counted as, and what the rollback keeps of the traffic before it. The
// rollback scenario arms judging before the page loads its history, so the Then can prove the history query and the
// subscription were judged, and the rollback itself forgets only the answers, never a refusal.

const SUBSCRIPTION =
  "subscription FamilyChatMessageCommitted($roomSlug: String!) { familyChatMessageCommitted(roomSlug: $roomSlug) { id } }";

const cleanAnswer: FakeLive = {
  ok: () => true,
  status: () => 200,
  text: () => Promise.resolve(JSON.stringify({ data: {} })),
};

/** A page whose wire is installed and judging armed, with its socket connected and its HTTP route captured. */
async function judgedPage() {
  const { page, routes } = fakePage();
  await wire.routeGraphqlWire(page);
  wire.judgeAgainstRolledBackSlot(page);
  const ws = fakeSocket();
  assert.ok(routes.socket, "the socket route was not registered");
  await routes.socket(ws.socket);
  assert.ok(routes.http, "the GraphQL route was not registered");
  return { http: routes.http, page, ws };
}

/** The route the page's HTTP request reaches: it carries the document, and the live server answers cleanly. */
function httpRequest(query: string): FakeRoute {
  return {
    request: () => ({
      postData: () => JSON.stringify({ query, variables: { roomSlug: ROOM } }),
    }),
    fetch: () => Promise.resolve(cleanAnswer),
    fulfill: () => "fulfilled",
    continue: () => "continued",
    abort: () => "aborted",
  };
}

test("each document judged is counted by its operation, over HTTP and the socket", async () => {
  const { http, ws } = await judgedPage();
  assert.deepEqual([...wire.previousRevisionTraffic.judged], []);
  await http(httpRequest(documentOf("FamilyChatMessages")));
  ws.fromPage(
    frame("1", "5", CONTROL_TOPIC, "doc", {
      query: SUBSCRIPTION,
      variables: { roomSlug: ROOM },
    }),
  );
  ws.fromPage(
    frame("1", "6", CONTROL_TOPIC, "doc", {
      query: SUBSCRIPTION,
      variables: { roomSlug: ROOM },
    }),
  );
  assert.equal(
    wire.previousRevisionTraffic.judged.get("FamilyChatMessages"),
    1,
  );
  assert.equal(
    wire.previousRevisionTraffic.judged.get("FamilyChatMessageCommitted"),
    2,
  );
});

test("a page that is not judging counts no judged document", async () => {
  const { page, routes } = fakePage();
  await wire.routeGraphqlWire(page);
  assert.ok(routes.http, "the GraphQL route was not registered");
  const before = new Map(wire.previousRevisionTraffic.judged);
  await routes.http(httpRequest(documentOf("FamilyChatMessages")));
  assert.deepEqual([...wire.previousRevisionTraffic.judged], [...before]);
});

test("arming the judge again starts the judged count over", async () => {
  const { http, page } = await judgedPage();
  await http(httpRequest(documentOf("FamilyChatMessages")));
  assert.equal(
    wire.previousRevisionTraffic.judged.get("FamilyChatMessages"),
    1,
  );
  wire.judgeAgainstRolledBackSlot(page);
  assert.deepEqual([...wire.previousRevisionTraffic.judged], []);
});

/** The traffic before a rollback: the history and the subscription judged and answered, one refused document, one live error. */
async function trafficBeforeRollback() {
  const page = await judgedPage();
  await page.http(httpRequest(documentOf("FamilyChatMessages")));
  page.ws.fromPage(
    frame("1", "5", CONTROL_TOPIC, "doc", {
      query: SUBSCRIPTION,
      variables: { roomSlug: ROOM },
    }),
  );
  page.ws.fromServer(
    frame("1", "5", CONTROL_TOPIC, "phx_reply", { status: "ok", response: {} }),
  );
  page.ws.fromPage(
    frame("1", "7", CONTROL_TOPIC, "doc", {
      query: "query Unknown { notInTheFrozenSchema }",
      variables: {},
    }),
  );
  page.ws.fromServer(
    frame(null, null, "subscription-1", "subscription:data", {
      subscriptionId: "subscription-1",
      result: { errors: [{ message: "boom" }] },
    }),
  );
  return page.ws;
}

test("the rollback forgets the answers so far and keeps every refusal and judged count", async () => {
  await trafficBeforeRollback();
  assert.equal(
    wire.previousRevisionTraffic.answered.has("FamilyChatMessageCommitted"),
    true,
  );
  assert.equal(wire.refusals().length, 1);
  assert.equal(wire.liveRefusals().length, 1);

  wire.forgetAnsweredBeforeRollback();

  assert.equal(wire.previousRevisionTraffic.answered.size, 0);
  assert.equal(wire.refusals().length, 1);
  assert.equal(wire.liveRefusals().length, 1);
  assert.equal(
    wire.previousRevisionTraffic.judged.get("FamilyChatMessages"),
    1,
  );
});

test("after the rollback, only the re-subscribed subscription's answer satisfies the wait", async () => {
  const ws = await trafficBeforeRollback();
  wire.forgetAnsweredBeforeRollback();
  assert.equal(
    wire.previousRevisionTraffic.answered.has("FamilyChatMessageCommitted"),
    false,
  );
  ws.fromPage(
    frame("1", "8", CONTROL_TOPIC, "doc", {
      query: SUBSCRIPTION,
      variables: { roomSlug: ROOM },
    }),
  );
  ws.fromServer(
    frame("1", "8", CONTROL_TOPIC, "phx_reply", { status: "ok", response: {} }),
  );
  assert.equal(
    wire.previousRevisionTraffic.answered.has("FamilyChatMessageCommitted"),
    true,
  );
});
