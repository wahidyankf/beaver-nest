import assert from "node:assert/strict";
import test from "node:test";
import {
  accountPlan,
  createInstanceLifecycle,
  type LifecycleClient,
} from "./test-instance-lifecycle.mts";
import type { SpawnRequest } from "./testing-control-records.mts";
import { createTestingControlClient } from "./testing-control.mts";
import { errorOf, withStandIn } from "./testing-control-stand-in.mts";
import {
  beginWith,
  fakeClient,
  instanceId,
  otherId,
  spawnedFor,
} from "./test-instance-lifecycle-fakes.mts";

test("spawns one instance with the chosen id, phase, and the plan's accounts", async () => {
  const { client, calls } = fakeClient();
  const lifecycle = createInstanceLifecycle({
    client,
    runId: "run-1",
    newInstanceId: () => instanceId,
  });

  const spawned = await lifecycle.begin({
    label: "login",
    phase: "sqlite_primary",
    accounts: accountPlan,
  });

  assert.equal(spawned.instanceId, instanceId);
  assert.equal(lifecycle.current()?.instanceId, instanceId);
  assert.equal(calls.spawns.length, 1);
  const [request] = calls.spawns;
  assert.equal(request?.runId, "run-1");
  assert.equal(request?.label, "login");
  assert.equal(request?.instanceId, instanceId);
  assert.equal(request?.phase, "sqlite_primary");
  assert.deepEqual(
    request?.seed?.accounts?.map((account) => account.username),
    accountPlan(instanceId).map((account) => account.username),
  );
});

test("sends no seed for an empty account plan", async () => {
  const { client, calls } = fakeClient();
  const lifecycle = createInstanceLifecycle({
    client,
    runId: "run-1",
    newInstanceId: () => instanceId,
  });

  await lifecycle.begin({
    label: "setup",
    phase: "flat_primary",
    accounts: () => [],
  });

  assert.equal(calls.spawns[0]?.seed, undefined);
  assert.equal(calls.spawns[0]?.phase, "flat_primary");
});

test("sends the unconfigured storage choice to the server, and nothing when it is not chosen", async () => {
  const { client, calls } = fakeClient();
  const lifecycle = createInstanceLifecycle({
    client,
    runId: "run-1",
    newInstanceId: () => instanceId,
  });

  await lifecycle.begin({
    label: "choose",
    phase: "flat_primary",
    storage: "unconfigured",
    accounts: accountPlan,
  });
  await lifecycle.end();
  await lifecycle.begin({
    label: "plain",
    phase: "flat_primary",
    accounts: accountPlan,
  });

  assert.equal(calls.spawns[0]?.storage, "unconfigured");
  assert.equal(calls.spawns[1]?.storage, undefined);
});

test("refuses a second begin while an instance is current, without a second spawn", async () => {
  const { client, calls } = fakeClient();
  const lifecycle = createInstanceLifecycle({
    client,
    runId: "run-1",
    newInstanceId: () => instanceId,
  });
  await lifecycle.begin(beginWith(() => []));

  await assert.rejects(
    lifecycle.begin(beginWith(() => [])),
    /already current/u,
  );
  assert.equal(calls.spawns.length, 1);
});

test("keeps no instance current when the spawn is refused", async () => {
  const { client, calls } = fakeClient({ spawnFails: true });
  const lifecycle = createInstanceLifecycle({
    client,
    runId: "run-1",
    newInstanceId: () => instanceId,
  });

  await assert.rejects(lifecycle.begin(beginWith(() => [])), /spawn refused/u);
  assert.equal(lifecycle.current(), undefined);
  assert.deepEqual(calls.deletes, []);
});

test("deletes a spawned instance that answers a different id, then fails", async () => {
  const { client, calls } = fakeClient({ returnId: otherId });
  const lifecycle = createInstanceLifecycle({
    client,
    runId: "run-1",
    newInstanceId: () => instanceId,
  });

  await assert.rejects(
    lifecycle.begin(beginWith(() => [])),
    /different instance/u,
  );
  assert.equal(lifecycle.current(), undefined);
  assert.deepEqual(calls.deletes, [otherId]);
});

test("ends the current instance once, and ending with none is a no-op", async () => {
  const { client, calls } = fakeClient();
  const lifecycle = createInstanceLifecycle({
    client,
    runId: "run-1",
    newInstanceId: () => instanceId,
  });
  await lifecycle.begin(beginWith(() => []));

  await lifecycle.end();
  await lifecycle.end();

  assert.equal(lifecycle.current(), undefined);
  assert.deepEqual(calls.deletes, [instanceId]);
});

test("keeps the instance current when its delete fails, so the reaper can retry it", async () => {
  const { client, calls } = fakeClient({ deleteFails: true });
  const lifecycle = createInstanceLifecycle({
    client,
    runId: "run-1",
    newInstanceId: () => instanceId,
  });
  await lifecycle.begin(beginWith(() => []));

  await assert.rejects(lifecycle.end(), /delete refused/u);
  assert.equal(lifecycle.current()?.instanceId, instanceId);
  await assert.rejects(lifecycle.reap(), /delete refused/u);
  assert.deepEqual(calls.deletes, [instanceId, instanceId]);
});

test("seeds the current instance under a seed key and refuses a seed with none current", async () => {
  const { client, calls } = fakeClient();
  const lifecycle = createInstanceLifecycle({
    client,
    runId: "run-1",
    newInstanceId: () => instanceId,
  });

  await assert.rejects(
    lifecycle.seed("early", { accounts: [] }),
    /no test instance is current/u,
  );
  await lifecycle.begin(beginWith(() => []));
  const result = await lifecycle.seed("load-accounts-1", { accounts: [] });

  assert.deepEqual(result, { seedKey: "load-accounts-1", applied: true });
  assert.deepEqual(calls.seeds, [
    { id: instanceId, seedKey: "load-accounts-1" },
  ]);
});

test("replaces the current instance by ending it before the new spawn", async () => {
  const { client, calls } = fakeClient();
  const ids = [instanceId, otherId];
  const lifecycle = createInstanceLifecycle({
    client,
    runId: "run-1",
    newInstanceId: () => ids.shift() ?? otherId,
  });
  await lifecycle.begin(beginWith(() => []));

  const replacement = await lifecycle.replace(beginWith(() => []));

  assert.equal(replacement.instanceId, otherId);
  assert.deepEqual(calls.deletes, [instanceId]);
  assert.equal(lifecycle.current()?.instanceId, otherId);
});

test("refuses an operation that starts while another one is still running", async () => {
  const gate: { release?: () => void } = {};
  const { client } = fakeClient();
  const slow: LifecycleClient = {
    ...client,
    spawnInstance: (request) =>
      new Promise((resolve) => {
        gate.release = () => resolve(spawnedFor(instanceId, request));
      }),
  };
  const lifecycle = createInstanceLifecycle({
    client: slow,
    runId: "run-1",
    newInstanceId: () => instanceId,
  });

  const first = lifecycle.begin(beginWith(() => []));
  await assert.rejects(
    lifecycle.end(),
    /another test instance operation is running/u,
  );
  gate.release?.();
  await first;
  assert.equal(lifecycle.current()?.instanceId, instanceId);
});

test("runs the lifecycle through the real client against a stand-in server", async () => {
  await withStandIn(
    (request) => {
      if (request.method === "POST" && request.url.endsWith("/instances")) {
        const body = JSON.parse(request.body) as SpawnRequest;
        return {
          status: 201,
          body: spawnedFor(body.instanceId ?? instanceId, body),
        };
      }
      return { status: 204 };
    },
    async (origin, requests) => {
      const client = createTestingControlClient({
        origin,
        env: { BNEST_TEST_CONTROL_SECRET: "0123456789abcdef".repeat(4) },
      });
      const lifecycle = createInstanceLifecycle({
        client,
        runId: "run-1",
        newInstanceId: () => instanceId,
      });

      await lifecycle.begin(beginWith(accountPlan));
      await lifecycle.end();

      assert.deepEqual(
        requests.map((request) => `${request.method} ${request.url}`),
        [
          "POST /__bnest_testing/v1/instances",
          `DELETE /__bnest_testing/v1/instances/${instanceId}`,
        ],
      );
      assert.equal(requests[0]?.secretHeader, "0123456789abcdef".repeat(4));
    },
  );
});

test("reports a refused delete from the stand-in as its typed code", async () => {
  await withStandIn(
    () => ({
      status: 409,
      body: {
        error: { code: "not_current", detail: "not current", path: null },
      },
    }),
    async (origin) => {
      const client = createTestingControlClient({
        origin,
        env: { BNEST_TEST_CONTROL_SECRET: "0123456789abcdef".repeat(4) },
      });
      const error = await errorOf(client.deleteInstance(instanceId));
      assert.equal((error as { code?: string }).code, "not_current");
    },
  );
});
