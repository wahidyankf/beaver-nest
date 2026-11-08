import assert from "node:assert/strict";
import test from "node:test";
import { deleteWhenIdle, type DeletingClient } from "./delete-when-idle.mts";
import { TestingControlError } from "./testing-control-error.mts";

const instanceId = "a1b2c3d4e5f6g7h8";

function busy(): Error {
  return new TestingControlError("instance_busy", 409, "a scheduler task is running", null);
}

// A client that refuses the first `refusals` deletes with the given error, then accepts.
function clientRefusing(refusals: number, error: () => Error = busy) {
  const deletes: string[] = [];
  let remaining = refusals;
  const client: DeletingClient = {
    deleteInstance: (id) => {
      deletes.push(id);
      if (remaining > 0) {
        remaining -= 1;
        return Promise.reject(error());
      }
      return Promise.resolve();
    },
  };
  return { client, deletes };
}

function recordingWait(attempts: number) {
  const waits: number[] = [];
  const wait = {
    attempts,
    intervalMs: 250,
    sleep: (ms: number) => {
      waits.push(ms);
      return Promise.resolve();
    },
  };
  return { wait, waits };
}

test("a delete waits while the server reports a running scheduler task, then succeeds", async () => {
  const { client, deletes } = clientRefusing(2);
  const { wait, waits } = recordingWait(5);

  await deleteWhenIdle(client, instanceId, wait);

  assert.deepEqual(deletes, [instanceId, instanceId, instanceId]);
  assert.deepEqual(waits, [250, 250]);
});

test("a delete stops waiting after the bounded attempts and rethrows the last refusal", async () => {
  const { client, deletes } = clientRefusing(100);
  const { wait } = recordingWait(3);

  await assert.rejects(deleteWhenIdle(client, instanceId, wait), /instance_busy/u);

  assert.equal(deletes.length, 3);
});

test("a delete does not wait for a failure that is not a busy refusal", async () => {
  const { client, deletes } = clientRefusing(1, () => new Error("delete failed"));
  const { wait, waits } = recordingWait(5);

  await assert.rejects(deleteWhenIdle(client, instanceId, wait), /delete failed/u);

  assert.deepEqual(waits, []);
  assert.equal(deletes.length, 1);
});
