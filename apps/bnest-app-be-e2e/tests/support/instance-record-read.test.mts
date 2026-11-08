import assert from "node:assert/strict";
import test from "node:test";
import {
  instanceReadMarker,
  markedPayload,
  parseRecordState,
  recordReadExpression,
} from "./instance-record-read.mts";

test("reads one record through the production routed records repository", () => {
  const expression = recordReadExpression("account", "user-abc_1");

  assert.match(
    expression,
    /BnestApp\.Storage\.Records\.read\(:account, "user-abc_1"\)/u,
  );
  // The repository routes by the instance's phase: SQLite for a SQLite-primary instance, its flat root otherwise.
  assert.doesNotMatch(expression, /SqliteRecordBackend/u);
  assert.ok(expression.includes(instanceReadMarker));
});

test("refuses a user id that could reach the code text", () => {
  assert.throws(
    () => recordReadExpression("chat", 'x"; System.halt(); "'),
    /not a safe record key/u,
  );
});

test("refuses a record kind that this module does not read", () => {
  assert.throws(
    () => recordReadExpression("family_chat" as "chat", "user-1"),
    /not readable/u,
  );
});

test("parses a present record from the marked line", () => {
  const stdout = `warning: compiling\n${instanceReadMarker}{"present":true,"record":{"state":{"thread_id":null}}}\n`;

  assert.deepEqual(parseRecordState(stdout), {
    present: true,
    record: { state: { thread_id: null } },
  });
});

test("keeps the server's reason when a record is absent", () => {
  const stdout = `${instanceReadMarker}{"present":false,"reason":"missing"}`;

  assert.deepEqual(parseRecordState(stdout), {
    present: false,
    reason: "missing",
  });
});

test("fails when the marked line is absent", () => {
  assert.throws(
    () => markedPayload("no marker here\n"),
    /marker was absent/u,
  );
});

test("fails when the state is not a record state", () => {
  assert.throws(
    () => parseRecordState(`${instanceReadMarker}{"present":"yes"}`),
    /did not report a record state/u,
  );
  assert.throws(
    () => parseRecordState(`${instanceReadMarker}{"present":true,"record":[1]}`),
    /did not report a record state/u,
  );
});

test("returns the payload of a count line for a numeric read", () => {
  assert.equal(markedPayload(`${instanceReadMarker}3\n`), "3");
});
