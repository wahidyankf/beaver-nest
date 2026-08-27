import assert from "node:assert/strict";
import test from "node:test";

import { ResumableSessionStore } from "./continuity-contract.mjs";

test("two clients resume the same ordered state without duplicating a cutover command", () => {
  const store = new ResumableSessionStore();
  const first = store.apply("family-game", "client-a-1", { move: "one" });
  const nearCutover = store.apply("family-game", "client-b-1", { move: "two" });
  const retried = store.apply("family-game", "client-b-1", { move: "two" });
  assert.deepEqual(retried, nearCutover);

  const clientA = store.resume("family-game", first.sequence);
  const clientB = store.resume("family-game", 0);
  assert.equal(clientA.version, 2);
  assert.deepEqual(clientA.snapshot, clientB.snapshot);
  assert.deepEqual(
    clientA.events.map(({ sequence }) => sequence),
    [2],
  );
  assert.deepEqual(
    clientB.events.map(({ sequence }) => sequence),
    [1, 2],
  );
});

test("ten clients across three groups preserve ordered state through three release cycles", () => {
  const store = new ResumableSessionStore();
  const clients = Array.from({ length: 10 }, (_, index) => ({
    id: `client-${index + 1}`,
    sessionId: `group-${(index % 3) + 1}`,
    acknowledged: 0,
  }));

  for (let release = 1; release <= 3; release += 1) {
    for (const client of clients) {
      const commandId = `${client.id}-release-${release}`;
      const event = store.apply(client.sessionId, commandId, { release });
      assert.deepEqual(
        store.apply(client.sessionId, commandId, { release }),
        event,
      );
      client.acknowledged = event.sequence;
    }

    for (const client of clients) {
      const resumed = store.resume(client.sessionId, client.acknowledged);
      assert.deepEqual(
        resumed.events.map(({ sequence }) => sequence),
        Array.from(
          { length: resumed.version - client.acknowledged },
          (_, index) => client.acknowledged + index + 1,
        ),
      );
      assert.equal(resumed.snapshot.at(-1)?.sequence, resumed.version);
      assert.deepEqual(
        resumed.snapshot.map(({ sequence }) => sequence),
        Array.from({ length: resumed.version }, (_, index) => index + 1),
      );
      client.acknowledged = resumed.version;
      assert.equal(
        store.resume(client.sessionId, client.acknowledged).events.length,
        0,
      );
    }
  }
});
