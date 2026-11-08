import assert from "node:assert/strict";
import test from "node:test";
import {
  TestingControlError,
  createTestingControlClient,
} from "./testing-control.mts";
import {
  errorOf,
  instanceId,
  rotated,
  secret,
  stateBody,
  withStandIn,
} from "./testing-control-stand-in.mts";

const spawned = {
  instanceId,
  label: "smoke",
  phase: "sqlite_primary",
  generation: `test-${instanceId}`,
  accounts: [
    { username: "test-user-a1b2c3d4", userId: "u-1", roles: ["admin"] },
  ],
  environment: {
    BNEST_TEST_INSTANCE_ID: instanceId,
    BNEST_RUNTIME_ROOT: "/synthetic/runtime",
    BNEST_STORAGE_CONFIG: "/synthetic/runtime/storage.json",
  },
};

test("sends the secret header read from the environment at call time", async () => {
  const environment: Record<string, string | undefined> = {
    BNEST_TEST_CONTROL_SECRET: secret,
  };

  await withStandIn(
    () => ({ status: 200, body: stateBody }),
    async (origin, requests) => {
      const client = createTestingControlClient({ origin, env: environment });
      await client.state();
      environment["BNEST_TEST_CONTROL_SECRET"] = rotated;
      await client.state();

      assert.deepEqual(
        requests.map((request) => request.secretHeader),
        [secret, rotated],
      );
      assert.equal(requests[0]?.method, "GET");
      assert.equal(requests[0]?.url, "/__bnest_testing/v1/state");
    },
  );
});

test("refuses to send when the secret is unset or shorter than 32 bytes", async () => {
  await withStandIn(
    () => ({ status: 200, body: stateBody }),
    async (origin, requests) => {
      const environments = [{}, { BNEST_TEST_CONTROL_SECRET: "short-secret" }];
      const failures = await Promise.all(
        environments.map((env) =>
          errorOf(createTestingControlClient({ origin, env }).state()),
        ),
      );

      for (const failure of failures) {
        assert.ok(failure instanceof TestingControlError);
        assert.equal(failure.code, "missing_secret");
        assert.equal(failure.message.includes("short-secret"), false);
      }
      assert.equal(requests.length, 0);
    },
  );
});

test("GET state sends no body and parses the state record", async () => {
  await withStandIn(
    () => ({ status: 200, body: stateBody }),
    async (origin, requests) => {
      const client = createTestingControlClient({
        origin,
        env: { BNEST_TEST_CONTROL_SECRET: secret },
      });

      assert.deepEqual(await client.state(), stateBody);
      assert.equal(requests[0]?.contentType, undefined);
      assert.equal(requests[0]?.body, "");
    },
  );
});

test("POST instances sends the spawn body as JSON and parses the created record", async () => {
  await withStandIn(
    () => ({ status: 201, body: spawned }),
    async (origin, requests) => {
      const client = createTestingControlClient({
        origin,
        env: { BNEST_TEST_CONTROL_SECRET: secret },
      });
      const request = {
        runId: "unit-run-1",
        label: "smoke",
        phase: "sqlite_primary" as const,
        seed: {
          accounts: [
            {
              username: "test-user-a1b2c3d4",
              password: "synthetic-password-1",
              roles: ["admin"],
            },
          ],
        },
      };

      assert.deepEqual(await client.spawnInstance(request), spawned);

      const [call] = requests;
      assert.equal(call?.method, "POST");
      assert.equal(call?.url, "/__bnest_testing/v1/instances");
      assert.equal(call?.contentType, "application/json");
      assert.deepEqual(JSON.parse(call?.body ?? "null"), request);
    },
  );
});

test("POST instances sends the storage choice when one is given", async () => {
  await withStandIn(
    () => ({ status: 201, body: spawned }),
    async (origin, requests) => {
      const client = createTestingControlClient({
        origin,
        env: { BNEST_TEST_CONTROL_SECRET: secret },
      });

      await client.spawnInstance({
        runId: "unit-run-1",
        label: "choose",
        phase: "flat_primary",
        storage: "unconfigured",
      });

      const [call] = requests;
      assert.equal(JSON.parse(call?.body ?? "null").storage, "unconfigured");
    },
  );
});

test("POST instances sends a client-chosen instanceId when one is given", async () => {
  await withStandIn(
    () => ({ status: 201, body: spawned }),
    async (origin, requests) => {
      const client = createTestingControlClient({
        origin,
        env: { BNEST_TEST_CONTROL_SECRET: secret },
      });
      const request = {
        runId: "unit-run-1",
        label: "smoke",
        instanceId,
      };

      await client.spawnInstance(request);

      assert.deepEqual(JSON.parse(requests[0]?.body ?? "null"), request);
    },
  );
});

test("refuses a malformed instanceId before any request is sent", async () => {
  await withStandIn(
    () => ({ status: 201, body: spawned }),
    async (origin, requests) => {
      const client = createTestingControlClient({
        origin,
        env: { BNEST_TEST_CONTROL_SECRET: secret },
      });
      const malformed = ["A1B2C3D4E5F6G7H8", "a1b2c3d4", "a1b2c3d4e5f6g7h8-"];

      const failures = await Promise.all(
        malformed.map((candidate) =>
          errorOf(
            client.spawnInstance({
              runId: "unit-run-1",
              label: "smoke",
              instanceId: candidate,
            }),
          ),
        ),
      );

      for (const failure of failures) {
        assert.ok(failure instanceof TestingControlError);
        assert.equal(failure.code, "invalid_request");
        assert.equal(failure.status, null);
      }
      assert.equal(requests.length, 0);
    },
  );
});

test("POST seed sends seedKey and seed to the instance seed route", async () => {
  const seeded = { seedKey: "messages-1", applied: true };

  await withStandIn(
    () => ({ status: 200, body: seeded }),
    async (origin, requests) => {
      const client = createTestingControlClient({
        origin,
        env: { BNEST_TEST_CONTROL_SECRET: secret },
      });
      const seed = {
        familyChat: {
          messages: [{ sender: "system", body: "hello", idempotencyKey: "k1" }],
        },
      };

      assert.deepEqual(
        await client.seedInstance(instanceId, { seedKey: "messages-1", seed }),
        seeded,
      );

      const [call] = requests;
      assert.equal(
        call?.url,
        `/__bnest_testing/v1/instances/${instanceId}/seed`,
      );
      assert.deepEqual(JSON.parse(call?.body ?? "null"), {
        seedKey: "messages-1",
        seed,
      });
    },
  );
});

test("DELETE instance sends no body and accepts 204", async () => {
  await withStandIn(
    () => ({ status: 204 }),
    async (origin, requests) => {
      const client = createTestingControlClient({
        origin,
        env: { BNEST_TEST_CONTROL_SECRET: secret },
      });

      assert.equal(await client.deleteInstance(instanceId), undefined);

      const [call] = requests;
      assert.equal(call?.method, "DELETE");
      assert.equal(call?.url, `/__bnest_testing/v1/instances/${instanceId}`);
      assert.equal(call?.body, "");
      assert.equal(call?.secretHeader, secret);
    },
  );
});
