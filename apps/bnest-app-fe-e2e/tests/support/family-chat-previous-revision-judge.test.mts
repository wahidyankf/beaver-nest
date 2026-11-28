import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { register } from "node:module";
import path from "node:path";
import test from "node:test";
import type { Schema } from "./family-chat-previous-revision-judge.ts";

// The judge is a .ts file in a commonjs package, which node --test would load as CommonJS and fail on. This hook loads
// it as a TypeScript module, so the judge runs here as it runs in the wire.
const TS_MODULE_HOOK = `export async function load(url, context, nextLoad) {
  if (url.endsWith("/family-chat-previous-revision-judge.ts"))
    return nextLoad(url, { ...context, format: "module-typescript" });
  return nextLoad(url, context);
}`;
register(`data:text/javascript,${encodeURIComponent(TS_MODULE_HOOK)}`);
const { judgeDocument, liveProblems, replyRefusals, subscriptionRefusals } =
  await import("./family-chat-previous-revision-judge.ts");

// The frozen rolled-back schema, and the previous bundle's documents that the wire replays against it.
const FIXTURE = path.resolve(
  import.meta.dirname,
  "../../../bnest-app/assets/test/support/family_chat_previous_revision.json",
);
const fixture = JSON.parse(readFileSync(FIXTURE, "utf8")) as {
  previousClient: {
    documents: Record<string, { document: string; variables: string[] }>;
  };
  rolledBackSlot: { schema: Schema };
};
const frozen = fixture.rolledBackSlot.schema;

// A schema whose arguments differ in nullability and list wrapping, for the variable-position rule.
const typed: Schema = {
  objects: { Item: { id: "ID" } },
  roots: {
    item: {
      kind: "query",
      type: "Item",
      args: {
        limit: "Int",
        required: "Int!",
        ids: "[Int]",
        strictIds: "[Int!]",
      },
    },
  },
};

const judge = (
  query: string,
  variables: Record<string, unknown> = {},
  schema: Schema = frozen,
): string[] => judgeDocument(query, variables, schema);

test("the previous bundle's own documents are accepted by the rolled-back schema", () => {
  for (const [name, { document }] of Object.entries(
    fixture.previousClient.documents,
  ))
    assert.deepEqual(judge(document), [], name);
});

test("a non-null variable into a nullable argument is accepted", () => {
  assert.deepEqual(
    judge(
      "query Q($n: Int!) { item(required: 1, limit: $n) { id } }",
      { n: 1 },
      typed,
    ),
    [],
  );
});

test("a nullable variable into a non-null argument is refused", () => {
  const reasons = judge(
    "query Q($n: Int) { item(required: $n) { id } }",
    { n: 1 },
    typed,
  );
  assert.match(
    reasons.join("; "),
    /Variable "\$n" of type "Int" used in position expecting type "Int!"/u,
  );
});

test("a list variable into a list argument of the same nullability is accepted", () => {
  assert.deepEqual(
    judge(
      "query Q($ids: [Int]) { item(required: 1, ids: $ids) { id } }",
      { ids: [1] },
      typed,
    ),
    [],
  );
});

test("a nullable list item into a non-null list item is refused", () => {
  const reasons = judge(
    "query Q($ids: [Int]) { item(required: 1, strictIds: $ids) { id } }",
    { ids: [1] },
    typed,
  );
  assert.match(
    reasons.join("; "),
    /Variable "\$ids" of type "\[Int\]" used in position expecting type "\[Int!\]"/u,
  );
});

test("a declared but unused variable is refused", () => {
  const reasons = judge(
    "query FamilyChatMessages($roomSlug: String!, $unusedFlag: Boolean) { familyChatMessages(roomSlug: $roomSlug) { nodes { id } } }",
    { roomSlug: "ruang-keluarga" },
  );
  assert.match(reasons.join("; "), /\$unusedFlag/u);
});

test("a variable sent but not declared is refused", () => {
  const reasons = judge(
    "query FamilyChatMessages($roomSlug: String!) { familyChatMessages(roomSlug: $roomSlug) { nodes { id } } }",
    { roomSlug: "ruang-keluarga", limit: 5 },
  );
  assert.deepEqual(reasons, ["$limit is sent but not declared"]);
});

test("a non-null Int variable into the nullable limit argument is accepted, so it is not a refusal", () => {
  assert.deepEqual(
    judge(
      "query FamilyChatMessages($roomSlug: String!, $limit: Int!) { familyChatMessages(roomSlug: $roomSlug, limit: $limit) { nodes { id } } }",
      { roomSlug: "ruang-keluarga", limit: 5 },
    ),
    [],
  );
});

test("a nullable String variable into the non-null roomSlug argument is refused", () => {
  const reasons = judge(
    "query FamilyChatMessages($roomSlug: String) { familyChatMessages(roomSlug: $roomSlug) { nodes { id } } }",
    { roomSlug: "ruang-keluarga" },
  );
  assert.match(
    reasons.join("; "),
    /Variable "\$roomSlug" of type "String" used in position expecting type "String!"/u,
  );
});

test("a mutation field under a query keyword is refused", () => {
  const reasons = judge(
    "query SendFamilyChatMessage($roomSlug: String!, $clientMessageId: ID!, $body: String!) { sendFamilyChatMessage(roomSlug: $roomSlug, clientMessageId: $clientMessageId, body: $body) { id } }",
    { roomSlug: "ruang-keluarga", clientMessageId: "c-1", body: "hi" },
  );
  assert.match(
    reasons.join("; "),
    /Cannot query field "sendFamilyChatMessage"/u,
  );
});

test("a subscription field under a query keyword is refused", () => {
  const reasons = judge(
    "query FamilyChatMessageCommitted($roomSlug: String!) { familyChatMessageCommitted(roomSlug: $roomSlug) { id } }",
    { roomSlug: "ruang-keluarga" },
  );
  assert.match(
    reasons.join("; "),
    /Cannot query field "familyChatMessageCommitted"/u,
  );
});

test("an unknown field on a selected object is refused", () => {
  const reasons = judge(
    "query FamilyChatMessages($roomSlug: String!) { familyChatMessages(roomSlug: $roomSlug) { nodes { bogusField } } }",
    { roomSlug: "ruang-keluarga" },
  );
  assert.match(reasons.join("; "), /bogusField/u);
});

test("two root fields are refused", () => {
  assert.deepEqual(
    judge(
      "query WebPushConfiguration { webPushConfiguration { available } currentWebPushSubscription { enabled } }",
    ),
    ["2 root fields, not one"],
  );
});

test("an object root field without a selection is refused", () => {
  const reasons = judge("query WebPushConfiguration { webPushConfiguration }");
  assert.match(reasons.join("; "), /must have a selection/u);
});

test("a document that does not parse is refused", () => {
  assert.notDeepEqual(judge("query {"), []);
});

test("a live answer with a non-OK status is refused", () => {
  assert.deepEqual(liveProblems(false, 500, "{}"), ["HTTP 500"]);
});

test("a live answer with an errors key is refused", () => {
  const reasons = liveProblems(
    true,
    200,
    JSON.stringify({ data: null, errors: [{ message: "boom" }] }),
  );
  assert.equal(reasons.length, 1);
  assert.match(reasons[0] ?? "", /errors/u);
});

test("a live answer with no data is refused", () => {
  assert.deepEqual(liveProblems(true, 200, JSON.stringify({})), ["no data"]);
});

test("a live answer that is not JSON is refused", () => {
  assert.deepEqual(liveProblems(true, 200, "not json"), [
    "the body is not JSON",
  ]);
});

test("a clean live answer is accepted", () => {
  assert.deepEqual(
    liveProblems(
      true,
      200,
      JSON.stringify({ data: { familyChatMessages: { nodes: [] } } }),
    ),
    [],
  );
});

const pushed = new Map([["7", "FamilyChatMessages"]]);
const reply = (ref: string, status: string, response: unknown): string =>
  JSON.stringify([
    "1",
    ref,
    "__absinthe__:control",
    "phx_reply",
    { status, response },
  ]);

test("a socket reply with status error to a watched push is refused", () => {
  const refusals = replyRefusals(
    reply("7", "error", { reason: "boom" }),
    pushed,
  );
  assert.equal(refusals.length, 1);
  assert.equal(refusals[0]?.operation, "FamilyChatMessages");
});

test("a socket reply with status ok and an errors key is refused", () => {
  const refusals = replyRefusals(
    reply("7", "ok", { errors: [{ message: "boom" }] }),
    pushed,
  );
  assert.equal(refusals.length, 1);
});

test("an ok socket reply is accepted, and so is a reply to a push that is not watched", () => {
  assert.deepEqual(
    replyRefusals(reply("7", "ok", { subscriptionId: "s" }), pushed),
    [],
  );
  assert.deepEqual(replyRefusals(reply("9", "error", {}), pushed), []);
});

const push = (result: unknown, event = "subscription:data"): string =>
  JSON.stringify([
    null,
    null,
    "subscription-1",
    event,
    { subscriptionId: "subscription-1", result },
  ]);

test("an errored subscription push is refused", () => {
  const reasons = subscriptionRefusals(push({ errors: [{ message: "boom" }] }));
  assert.equal(reasons.length, 1);
  assert.match(reasons[0] ?? "", /errors/u);
});

test("an errored subscription push sent as a Buffer is refused", () => {
  const reasons = subscriptionRefusals(Buffer.from(push({ errors: [] })));
  assert.equal(reasons.length, 1);
});

test("a data-only subscription push is accepted", () => {
  assert.deepEqual(
    subscriptionRefusals(
      push({ data: { familyChatMessageCommitted: { id: "1" } } }),
    ),
    [],
  );
});

test("an errors key outside a subscription push is not judged here", () => {
  assert.deepEqual(subscriptionRefusals(push({ errors: [] }, "phx_reply")), []);
});

test("a message that is not JSON returns nothing", () => {
  assert.deepEqual(subscriptionRefusals("not json"), []);
  assert.deepEqual(subscriptionRefusals(Buffer.from("{")), []);
});
