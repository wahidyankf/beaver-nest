import assert from "node:assert/strict";
import test from "node:test";
import {
  accountPlan,
  createInstanceLifecycle,
  instanceEnvironment,
  type LifecycleClient,
} from "./test-instance-lifecycle.mts";
import { settleAll } from "./settle-all.mts";
import type { SpawnedInstance } from "./testing-control-records.mts";

const instanceId = "a1b2c3d4e5f6g7h8";
const otherInstanceId = "b1b2c3d4e5f6g7h8";
const oneScenario = {
  label: "one",
  phase: "sqlite_primary" as const,
  accounts: () => [],
};

function spawnedFor(id: string): SpawnedInstance {
  return {
    instanceId: id,
    label: "scenario",
    phase: "sqlite_primary",
    generation: `test-${id}`,
    accounts: [],
    environment: {
      BNEST_TEST_INSTANCE_ID: id,
      BNEST_RUNTIME_ROOT: "/synthetic/runs/run-1",
      BNEST_STORAGE_CONFIG:
        "/synthetic/sqlite/runs/run-1/storage-config/storage.json",
    },
  };
}

function lifecycleFor(
  client: LifecycleClient,
  ids: () => string = () => instanceId,
) {
  return createInstanceLifecycle({
    client,
    runId: "run-1",
    newInstanceId: ids,
  });
}

type Call = { name: string; args: unknown[] };

// A fake client records every call. Each step can be made to fail once, as a rejected request would.
function fakeClient(failures: Partial<Record<string, Error>> = {}) {
  const calls: Call[] = [];
  const failOnce = (name: string): Promise<void> => {
    const error = failures[name];
    if (error === undefined) return Promise.resolve();
    delete failures[name];
    return Promise.reject(error);
  };
  const client: LifecycleClient = {
    spawnInstance(request) {
      calls.push({ name: "spawn", args: [request] });
      return failOnce("spawn").then(() =>
        spawnedFor(request.instanceId ?? instanceId),
      );
    },
    seedInstance(id, request) {
      calls.push({ name: "seed", args: [id, request] });
      return failOnce("seed").then(() => ({
        seedKey: request.seedKey,
        applied: true,
      }));
    },
    deleteInstance(id) {
      calls.push({ name: "delete", args: [id] });
      return failOnce("delete");
    },
  };
  return { calls, client };
}

test("the instance environment is the one the spawn response reports", () => {
  assert.deepEqual(instanceEnvironment(spawnedFor(instanceId)), {
    BNEST_TEST_INSTANCE_ID: instanceId,
    BNEST_RUNTIME_ROOT: "/synthetic/runs/run-1",
    BNEST_STORAGE_CONFIG:
      "/synthetic/sqlite/runs/run-1/storage-config/storage.json",
  });
});

test("the instance environment refuses a response that disagrees with itself", () => {
  const mismatched = spawnedFor(instanceId);
  mismatched.environment.BNEST_TEST_INSTANCE_ID = otherInstanceId;
  assert.throws(() => instanceEnvironment(mismatched), /instance/u);

  const relative = spawnedFor(instanceId);
  relative.environment.BNEST_STORAGE_CONFIG = "storage-config/storage.json";
  assert.throws(() => instanceEnvironment(relative), /absolute/u);
});

test("begin spawns one instance with the plan's accounts and remembers it", async () => {
  const { client, calls } = fakeClient();
  const lifecycle = lifecycleFor(client);

  const spawned = await lifecycle.begin({
    label: "a-visitor-opens-a-fresh-chat",
    phase: "sqlite_primary",
    accounts: accountPlan,
  });

  assert.equal(spawned.instanceId, instanceId);
  assert.equal(lifecycle.current()?.instanceId, instanceId);
  assert.equal(calls.length, 1);
  assert.deepEqual(calls[0]?.args[0], {
    runId: "run-1",
    label: "a-visitor-opens-a-fresh-chat",
    instanceId,
    phase: "sqlite_primary",
    seed: {
      accounts: accountPlan(instanceId).map((account) => ({
        username: account.username,
        password: account.password,
        roles: account.roles,
      })),
    },
  });
});

test("begin refuses a second instance while one is current and makes no call", async () => {
  const { client, calls } = fakeClient();
  const lifecycle = lifecycleFor(client);
  await lifecycle.begin(oneScenario);

  await assert.rejects(
    lifecycle.begin({ ...oneScenario, label: "two" }),
    /already current/u,
  );
  assert.equal(calls.length, 1);
});

test("end deletes the current instance and forgets it", async () => {
  const { client, calls } = fakeClient();
  const lifecycle = lifecycleFor(client);
  await lifecycle.begin(oneScenario);

  await lifecycle.end();

  assert.equal(lifecycle.current(), undefined);
  assert.deepEqual(calls.at(-1), { name: "delete", args: [instanceId] });
});

test("end with no current instance makes no call", async () => {
  const { client, calls } = fakeClient();
  const lifecycle = lifecycleFor(client);

  await lifecycle.end();

  assert.equal(calls.length, 0);
});

test("a failed spawn leaves no instance current and deletes nothing", async () => {
  const { client, calls } = fakeClient({ spawn: new Error("spawn refused") });
  const lifecycle = lifecycleFor(client);

  await assert.rejects(lifecycle.begin(oneScenario), /spawn refused/u);

  assert.equal(lifecycle.current(), undefined);
  assert.deepEqual(
    calls.map((call) => call.name),
    ["spawn"],
  );
});

test("a seed goes to the current instance under its seed key", async () => {
  const { client, calls } = fakeClient();
  const lifecycle = lifecycleFor(client);
  await lifecycle.begin(oneScenario);

  const result = await lifecycle.seed("load-accounts-1", {
    accounts: [
      {
        username: "test-user-load-1-a1b2c3d4",
        password: "p",
        roles: ["children"],
      },
    ],
  });

  assert.deepEqual(result, { seedKey: "load-accounts-1", applied: true });
  assert.equal(calls.at(-1)?.name, "seed");
  assert.equal(calls.at(-1)?.args[0], instanceId);
});

test("a seed with no current instance is refused", async () => {
  const { client, calls } = fakeClient();
  const lifecycle = lifecycleFor(client);

  await assert.rejects(lifecycle.seed("late", {}), /no test instance/u);
  assert.equal(calls.length, 0);
});

test("a failed delete keeps the instance current so the reaper can retry", async () => {
  const { client, calls } = fakeClient({ delete: new Error("delete failed") });
  const lifecycle = lifecycleFor(client);
  await lifecycle.begin(oneScenario);

  await assert.rejects(lifecycle.end(), /delete failed/u);
  assert.equal(lifecycle.current()?.instanceId, instanceId);

  await lifecycle.reap();

  assert.equal(lifecycle.current(), undefined);
  assert.deepEqual(
    calls.map((call) => call.name),
    ["spawn", "delete", "delete"],
  );
});

test("reap deletes a leftover instance and does nothing when none remains", async () => {
  const { client, calls } = fakeClient();
  const lifecycle = lifecycleFor(client);
  await lifecycle.begin(oneScenario);

  await lifecycle.reap();
  await lifecycle.reap();

  assert.equal(lifecycle.current(), undefined);
  assert.deepEqual(
    calls.map((call) => call.name),
    ["spawn", "delete"],
  );
});

test("replace deletes the current instance before it spawns the next", async () => {
  const { client, calls } = fakeClient();
  const ids = [instanceId, otherInstanceId];
  const lifecycle = lifecycleFor(client, () => ids.shift() ?? instanceId);
  await lifecycle.begin(oneScenario);

  const next = await lifecycle.replace({ ...oneScenario, label: "two" });

  assert.equal(next.instanceId, otherInstanceId);
  assert.deepEqual(
    calls.map((call) => call.name),
    ["spawn", "delete", "spawn"],
  );
});

// A cleanup step that records its name, then fails with `failure` when one is given.
function recordingStep(
  ran: string[],
  name: string,
  failure?: Error,
): () => Promise<void> {
  return () => {
    ran.push(name);
    return failure === undefined ? Promise.resolve() : Promise.reject(failure);
  };
}

test("cleanup runs every step even after one fails, then reports the failure", async () => {
  const ran: string[] = [];
  const failure = new Error("page close failed");

  await assert.rejects(
    settleAll([
      recordingStep(ran, "route"),
      recordingStep(ran, "contexts", failure),
      recordingStep(ran, "delete"),
    ]),
    failure,
  );
  assert.deepEqual(ran, ["route", "contexts", "delete"]);
});

test("cleanup reports every failure when several steps fail", async () => {
  await assert.rejects(
    settleAll([
      () => Promise.reject(new Error("first")),
      () => Promise.reject(new Error("second")),
    ]),
    (error: unknown) =>
      error instanceof AggregateError && error.errors.length === 2,
  );
});

test("cleanup with no failure resolves", async () => {
  await assert.doesNotReject(settleAll([() => Promise.resolve()]));
});
