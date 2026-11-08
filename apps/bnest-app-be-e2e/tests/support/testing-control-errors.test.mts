import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import {
  TestingControlError,
  backendOrigin,
  createTestingControlClient,
  type TestingControlClient,
} from "./testing-control.mts";
import {
  errorOf,
  instanceId,
  rotated,
  secret,
  withStandIn,
  type Reply,
} from "./testing-control-stand-in.mts";

const typedCases = [
  {
    status: 409,
    code: "instance_active",
    detail: "An instance is already current.",
    path: null,
  },
  {
    status: 422,
    code: "seed_invalid",
    detail: "invalid_username",
    path: "accounts.0.username",
  },
  {
    status: 500,
    code: "spawn_failed",
    detail: "migration failed",
    path: null,
  },
] as const;

// Runs one client call against a stand-in that always answers with `reply`.
async function failureOf(
  reply: Reply,
  action: (client: TestingControlClient) => Promise<unknown>,
): Promise<unknown> {
  let failure: unknown;
  await withStandIn(
    () => reply,
    async (origin) => {
      const client = createTestingControlClient({
        origin,
        env: { BNEST_TEST_CONTROL_SECRET: secret },
      });
      failure = await errorOf(action(client));
    },
  );
  return failure;
}

function assertNoSecret(error: unknown): void {
  assert.ok(error instanceof Error);
  const text = [
    error.message,
    error.stack ?? "",
    JSON.stringify(error),
    error instanceof TestingControlError ? error.detail : "",
  ].join("\n");
  assert.equal(text.includes(secret), false);
  assert.equal(text.includes(rotated), false);
}

test("maps each testing error body to a typed error", async () => {
  const failures = await Promise.all(
    typedCases.map((expected) =>
      failureOf(
        {
          status: expected.status,
          body: {
            error: {
              code: expected.code,
              detail: expected.detail,
              path: expected.path,
            },
          },
        },
        (client) => client.deleteInstance(instanceId),
      ),
    ),
  );

  for (const [index, failure] of failures.entries()) {
    const expected = typedCases[index];
    assert.ok(failure instanceof TestingControlError);
    assert.equal(failure.code, expected?.code);
    assert.equal(failure.status, expected?.status);
    assert.equal(failure.detail, expected?.detail);
    assert.equal(failure.path, expected?.path);
  }
});

test("maps an error code the client does not know to unexpected_response", async () => {
  const failure = await failureOf(
    {
      status: 418,
      body: {
        error: { code: "teapot", detail: "short and stout", path: null },
      },
    },
    (client) => client.state(),
  );

  assert.ok(failure instanceof TestingControlError);
  assert.equal(failure.code, "unexpected_response");
  assert.equal(failure.status, 418);
});

test("maps the stock not-found body to not_found", async () => {
  const failure = await failureOf(
    { status: 404, body: { errors: { detail: "Not Found" } } },
    (client) => client.state(),
  );

  assert.ok(failure instanceof TestingControlError);
  assert.equal(failure.code, "not_found");
  assert.equal(failure.status, 404);
  assert.equal(failure.detail, "Not Found");
  assert.equal(failure.path, null);
});

test("never puts the secret into a thrown error, even when the server echoes it", async () => {
  const failure = await failureOf(
    {
      status: 500,
      body: {
        error: {
          code: "spawn_failed",
          detail: `echoed header ${secret}`,
          path: null,
        },
      },
    },
    (client) => client.state(),
  );

  assert.ok(failure instanceof TestingControlError);
  assert.equal(failure.code, "spawn_failed");
  assert.equal(failure.detail, "echoed header [redacted]");
  assertNoSecret(failure);
});

test("maps a dropped connection to unreachable without the secret", async () => {
  const failure = await failureOf({ status: 200, destroy: true }, (client) =>
    client.state(),
  );

  assert.ok(failure instanceof TestingControlError);
  assert.equal(failure.code, "unreachable");
  assertNoSecret(failure);
});

test("maps a success body that does not match the record to unexpected_response", async () => {
  const failure = await failureOf(
    { status: 200, body: { schemaVersion: 2 } },
    (client) => client.state(),
  );

  assert.ok(failure instanceof TestingControlError);
  assert.equal(failure.code, "unexpected_response");
  assert.equal(failure.status, 200);
});

test("accepts only 204 from the delete route", async () => {
  const failure = await failureOf(
    { status: 200, body: { deleted: true } },
    (client) => client.deleteInstance(instanceId),
  );

  assert.ok(failure instanceof TestingControlError);
  assert.equal(failure.code, "unexpected_response");
});

test("builds only loopback origins", () => {
  assert.equal(backendOrigin("4030"), "http://127.0.0.1:4030");
  assert.equal(backendOrigin(4031), "http://127.0.0.1:4031");

  for (const port of ["0", "65536", "abc", "4030.5"]) {
    assert.throws(() => backendOrigin(port), TestingControlError);
  }

  assert.throws(
    () =>
      createTestingControlClient({
        origin: "http://192.0.2.5:4030",
        env: { BNEST_TEST_CONTROL_SECRET: secret },
      }),
    (error: unknown) =>
      error instanceof TestingControlError && error.code === "invalid_origin",
  );
});

test("the client module has no Playwright request context and never logs", () => {
  const source = readFileSync(
    new URL("./testing-control.mts", import.meta.url),
    "utf8",
  );

  assert.equal(source.includes("@playwright"), false);
  assert.equal(source.includes("console."), false);
  assert.equal(source.includes("process.stdout"), false);
  assert.equal(source.includes("process.stderr"), false);
});
