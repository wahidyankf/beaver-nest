import assert from "node:assert/strict";
import test from "node:test";
import {
  accountPlan,
  newInstanceId,
  phaseForTags,
  runConfigPaths,
  scenarioLabel,
  shortIdOf,
  testUsername,
} from "./test-instance-lifecycle.mts";

// The lifecycle state machine and the cleanup helper are tested in test-instance-lifecycle-state.test.mts.

const instanceId = "a1b2c3d4e5f6g7h8";
const labelPattern = /^[a-z0-9]+(-[a-z0-9]+)*$/u;

test("scenario labels are lowercase slugs of at most 60 characters", () => {
  const titles = [
    "A visitor opens a fresh chat",
    "Initial setup warns about unavailable recovery and closes registration",
    "A press that turns into a scroll does not open the menu (Shift+Enter)!",
    "!!!",
  ];

  for (const title of titles) {
    const label = scenarioLabel(title);
    assert.match(label, labelPattern);
    assert.ok(label.length <= 60, `${label} is longer than 60 characters`);
  }
  assert.equal(
    scenarioLabel("A visitor opens a fresh chat"),
    "a-visitor-opens-a-fresh-chat",
  );
  assert.equal(scenarioLabel("!!!"), "scenario");
  // The slug is cut to 60 characters, so this 67-character slug keeps its first 60.
  assert.equal(
    scenarioLabel(
      "A press that turns into a scroll does not open the menu (Shift+Enter)!",
    ),
    "a-press-that-turns-into-a-scroll-does-not-open-the-menu-shif",
  );
});

test("the phase is flat_primary only for a scenario tagged @flat-primary", () => {
  assert.equal(phaseForTags([]), "sqlite_primary");
  assert.equal(phaseForTags(["@chromium"]), "sqlite_primary");
  assert.equal(phaseForTags(["@flat-primary"]), "flat_primary");
  assert.equal(phaseForTags(["@chromium", "@flat-primary"]), "flat_primary");
});

test("a generated instance id is 16 lowercase letters or digits", () => {
  const indexes = [0, 35, 0, 35, 10, 20, 30, 1, 2, 3, 4, 5, 6, 7, 8, 9];
  const id = newInstanceId((exclusiveMax) => {
    assert.equal(exclusiveMax, 36);
    return indexes.shift() ?? 0;
  });

  // Indexes 0, 35, 0, 35, 10, 20, 30, 1..9 over "a..z0..9" spell this id.
  assert.equal(id, "a9a9ku4bcdefghij");
  assert.match(newInstanceId(), /^[a-z0-9]{16}$/u);
});

test("the username carries the first eight characters of the instance id", () => {
  assert.equal(shortIdOf(instanceId), "a1b2c3d4");
  assert.equal(testUsername("admin", instanceId), "test-user-admin-a1b2c3d4");
  assert.equal(
    testUsername("child-admin", instanceId),
    "test-user-child-admin-a1b2c3d4",
  );
  assert.throws(() => testUsername("Admin", instanceId), /role/u);
  // The load identities of the recovery journey carry a number: `load-1` to `load-10`.
  assert.equal(testUsername("load-1", instanceId), "test-user-load-1-a1b2c3d4");
  assert.equal(
    testUsername("load-10", instanceId),
    "test-user-load-10-a1b2c3d4",
  );
  assert.throws(() => testUsername("-load", instanceId), /role/u);
  assert.throws(() => testUsername("load-", instanceId), /role/u);
  assert.throws(
    () => testUsername("a-role-name-that-is-far-too-long", instanceId),
    /32/u,
  );
  assert.throws(() => testUsername("admin", "short"), /instance id/u);
});

test("the account plan names every role with a synthetic test username", () => {
  const plan = accountPlan(instanceId);

  assert.deepEqual(
    plan.map((account) => [account.role, account.username, account.roles]),
    [
      ["admin", "test-user-admin-a1b2c3d4", ["admin", "parents"]],
      ["child", "test-user-child-a1b2c3d4", ["children"]],
      ["child-admin", "test-user-child-admin-a1b2c3d4", ["children", "admin"]],
      ["parent", "test-user-parent-a1b2c3d4", ["parents"]],
    ],
  );
  for (const account of plan) {
    assert.ok(account.username.startsWith("test-user-"));
    assert.ok(account.username.length <= 32);
    assert.ok(account.password.length > 0);
    assert.notEqual(account.password, account.username);
  }
});

test("the run's storage pointer and backup config sit under the SQLite run root, never the flat one", () => {
  const paths = runConfigPaths({ runId: "fe-e2e-abc", home: "/synthetic/tester" });

  assert.deepEqual(paths, {
    sqliteRunRoot: "/synthetic/tester/bnest/data/test/runs/fe-e2e-abc",
    storageConfig:
      "/synthetic/tester/bnest/data/test/runs/fe-e2e-abc/storage-config/storage.json",
    backupConfig:
      "/synthetic/tester/bnest/data/test/runs/fe-e2e-abc/storage-config/backup.json",
  });
});
