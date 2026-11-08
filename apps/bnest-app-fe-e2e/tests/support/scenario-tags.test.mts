import assert from "node:assert/strict";
import test from "node:test";
import { backupRepositoryOf, needsBackupRepository, seedsAccountsForTags } from "./scenario-tags.mts";

const instanceId = "a1b2c3d4e5f6g7h8";

test("only a scenario tagged @backup-repository needs the instance's backup repository", () => {
  assert.equal(needsBackupRepository(["@backup-repository"]), true);
  assert.equal(needsBackupRepository(["@flat-primary", "@backup-repository"]), true);
  assert.equal(needsBackupRepository(["@flat-primary"]), false);
  assert.equal(needsBackupRepository([]), false);
});

test("the instance's backup repository sits beside its database, under the SQLite run root", () => {
  assert.equal(
    backupRepositoryOf(
      "/synthetic/tester/bnest/data/test/runs/fe-e2e-abc/storage-config/storage.json",
      instanceId,
    ),
    "/synthetic/tester/bnest/data/test/runs/fe-e2e-abc/instances/a1b2c3d4e5f6g7h8/backup-repository",
  );
  assert.throws(() => backupRepositoryOf("storage.json", instanceId), /absolute/u);
  assert.throws(() => backupRepositoryOf("/x/storage-config/storage.json", "short"), /instance id/u);
});

test("only a scenario tagged @open-setup starts with no seeded account", () => {
  assert.equal(seedsAccountsForTags([]), true);
  assert.equal(seedsAccountsForTags(["@flat-primary"]), true);
  assert.equal(seedsAccountsForTags(["@flat-primary", "@open-setup"]), false);
});
