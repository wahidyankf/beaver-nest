import assert from "node:assert/strict";
import test from "node:test";
import {
  accountPlan,
  identitiesOf,
  instanceEnvironment,
  isScenarioPrecondition,
  newInstanceId,
  phaseForTags,
  scenarioLabel,
  seedsAccountsForTags,
  settleAll,
  shortIdOf,
  storageForTags,
  testUsername,
} from "./test-instance-lifecycle.mts";
import { instanceId, otherId, spawnedFor } from "./test-instance-lifecycle-fakes.mts";

test("slugs a scenario title into a lowercase label of at most 60 characters", () => {
  assert.equal(scenarioLabel("Login persists across reload!"), "login-persists-across-reload");
  assert.equal(scenarioLabel("  --Hello   World--  "), "hello-world");
  assert.equal(scenarioLabel("!!!"), "scenario");
  const long = scenarioLabel(`${"word ".repeat(30)}end`);
  assert.ok(long.length <= 60, `label has ${long.length} characters`);
  assert.doesNotMatch(long, /-$/u);
});

test("chooses the phase from the scenario tags and seeds accounts unless setup must stay open", () => {
  assert.equal(phaseForTags(["@flat-primary"]), "flat_primary");
  assert.equal(phaseForTags(["@flat-primary", "@open-setup"]), "flat_primary");
  assert.equal(phaseForTags([]), "sqlite_primary");
  assert.equal(phaseForTags(["@e2e"]), "sqlite_primary");
  assert.equal(seedsAccountsForTags(["@flat-primary", "@open-setup"]), false);
  assert.equal(seedsAccountsForTags(["@flat-primary"]), true);
  assert.equal(seedsAccountsForTags([]), true);
});

test("leaves the storage unconfigured only for a scenario tagged for it", () => {
  assert.equal(storageForTags(["@flat-primary", "@storage-unconfigured"]), "unconfigured");
  assert.equal(storageForTags(["@flat-primary"]), "configured");
  assert.equal(storageForTags([]), "configured");
});

test("builds a 16 character instance id from the lowercase letters and digits", () => {
  assert.equal(newInstanceId(() => 0), "aaaaaaaaaaaaaaaa");
  assert.equal(newInstanceId(() => 35), "9999999999999999");
  assert.match(newInstanceId(), /^[a-z0-9]{16}$/u);
});

test("keeps the first eight characters of an instance id as its short id", () => {
  assert.equal(shortIdOf(instanceId), "a1b2c3d4");
  assert.throws(() => shortIdOf("SHORT"), /16 lowercase letters or digits/u);
});

test("builds a test-user username that carries the instance short id", () => {
  assert.equal(testUsername("admin", instanceId), "test-user-admin-a1b2c3d4");
  assert.equal(testUsername("child-admin", instanceId), "test-user-child-admin-a1b2c3d4");
  assert.throws(() => testUsername("Admin", instanceId), /not a lowercase username segment/u);
  assert.throws(
    () => testUsername(`${"a".repeat(40)}`, instanceId),
    /longer than 32 characters/u,
  );
});

// The login field and the production username rule allow 32 characters in all, which is 22 after `test-user-`.
test("accepts a username of exactly 32 characters and refuses one of 33", () => {
  // test-user- (10) + role + "-" + short id (8) = 32 for a 13-letter role.
  assert.equal(testUsername("a".repeat(13), instanceId).length, 32);
  assert.throws(
    () => testUsername("a".repeat(14), instanceId),
    /longer than 32 characters/u,
  );
});

// The initial-setup and login forms cap a username at 32 characters (maxlength="32"), and the browser truncates a
// longer value without an error, so a longer username breaks the scenario at the first field check.
test("keeps the password-length account username inside the 32-character login field", () => {
  assert.ok(testUsername("short-pass", instanceId).length <= 32);
});

test("plans the four accounts of a scenario with their roles and synthetic passwords", () => {
  const plan = accountPlan(instanceId);
  assert.deepEqual(
    plan.map(({ role, username, roles }) => ({ role, username, roles })),
    [
      { role: "admin", username: "test-user-admin-a1b2c3d4", roles: ["admin", "parents"] },
      { role: "child", username: "test-user-child-a1b2c3d4", roles: ["children"] },
      {
        role: "child-admin",
        username: "test-user-child-admin-a1b2c3d4",
        roles: ["children", "admin"],
      },
      { role: "parent", username: "test-user-parent-a1b2c3d4", roles: ["parents"] },
    ],
  );
  for (const account of plan) {
    assert.match(account.password, /^Synthetic E2E /u);
  }
  const identities = identitiesOf(plan);
  assert.equal(identities.admin.username, "test-user-admin-a1b2c3d4");
  assert.equal(identities.childAdmin.username, "test-user-child-admin-a1b2c3d4");
});

test("builds the environment a secondary process needs from the spawn response", () => {
  const spawned = spawnedFor(instanceId, { runId: "run-1", label: "x" });
  assert.deepEqual(instanceEnvironment(spawned), {
    BNEST_TEST_INSTANCE_ID: instanceId,
    BNEST_RUNTIME_ROOT: "/data/test/runs/run-1",
    BNEST_STORAGE_CONFIG: "/synthetic/x/bnest/data/test/runs/run-1/storage-config/storage.json",
  });
});

test("refuses an environment that names another instance or a relative path", () => {
  const spawned = spawnedFor(instanceId, { runId: "run-1", label: "x" });
  assert.throws(
    () => instanceEnvironment({ ...spawned, instanceId: otherId }),
    /names a different instance/u,
  );
  assert.throws(
    () =>
      instanceEnvironment({
        ...spawned,
        environment: { ...spawned.environment, BNEST_RUNTIME_ROOT: "relative/root" },
      }),
    /BNEST_RUNTIME_ROOT must be an absolute path/u,
  );
});

test("settles every cleanup step even after one fails, then rethrows the failure", async () => {
  const ran: string[] = [];
  await assert.rejects(
    settleAll([
      () => {
        ran.push("close");
        return Promise.reject(new Error("close failed"));
      },
      () => {
        ran.push("delete");
        return Promise.resolve();
      },
    ]),
    /close failed/u,
  );
  assert.deepEqual(ran, ["close", "delete"]);
});

test("reports several cleanup failures together", async () => {
  await assert.rejects(
    settleAll([
      () => Promise.reject(new Error("one")),
      () => Promise.reject(new Error("two")),
    ]),
    AggregateError,
  );
});

test("only the scenario's first step is its precondition, so a later step never ends an instance", () => {
  assert.equal(isScenarioPrecondition(1), true);
  assert.equal(isScenarioPrecondition(2), false);
  assert.equal(isScenarioPrecondition(0), false);
});
