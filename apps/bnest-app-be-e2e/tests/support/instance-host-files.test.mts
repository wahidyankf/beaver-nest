import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { instanceHostFiles, presentHostFiles } from "./instance-host-files.mts";

const instanceId = "a1b2c3d4e5f6g7h8";

// Both roots live under a temporary directory, never under data/test or ~/bnest.
function temporaryRoots() {
  const base = mkdtempSync(path.join(os.tmpdir(), "bnest-host-files-test-"));
  const roots = {
    flatRunRoot: path.join(base, "flat", "unit-run-1"),
    sqliteRunRoot: path.join(base, "sqlite", "unit-run-1"),
    runId: "unit-run-1",
  };
  return { base, roots };
}

test("names the instance roots, the storage pointer, and the backup configuration", () => {
  const { base, roots } = temporaryRoots();

  try {
    assert.deepEqual(instanceHostFiles(roots, instanceId), {
      instanceRoots: [
        path.join(roots.flatRunRoot, "instances", instanceId),
        path.join(roots.sqliteRunRoot, "instances", instanceId),
      ],
      storagePointer: path.join(
        roots.sqliteRunRoot,
        "storage-config",
        "storage.json",
      ),
      backupConfiguration: path.join(
        roots.sqliteRunRoot,
        "storage-config",
        "backup.json",
      ),
    });
  } finally {
    rmSync(base, { recursive: true, force: true });
  }
});

test("lists only the instance host files that exist", () => {
  const { base, roots } = temporaryRoots();

  try {
    const files = instanceHostFiles(roots, instanceId);
    assert.deepEqual(presentHostFiles(files), []);

    mkdirSync(files.instanceRoots[1] ?? "", { recursive: true });
    mkdirSync(path.dirname(files.storagePointer), { recursive: true });
    writeFileSync(files.storagePointer, "{}");

    assert.deepEqual(presentHostFiles(files), [
      files.instanceRoots[1],
      files.storagePointer,
    ]);
  } finally {
    rmSync(base, { recursive: true, force: true });
  }
});

test("refuses an instance ID that is not a test instance ID", () => {
  const { base, roots } = temporaryRoots();

  try {
    assert.throws(
      () => instanceHostFiles(roots, "../escape"),
      /invalid_instance_id/u,
    );
  } finally {
    rmSync(base, { recursive: true, force: true });
  }
});
