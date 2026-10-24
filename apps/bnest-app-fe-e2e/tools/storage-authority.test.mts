import assert from "node:assert/strict";
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readdirSync,
  readFileSync,
  realpathSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import os from "node:os";
import path from "node:path";
import test, { after } from "node:test";

// `storage-authority.mts` reads the marked runtime from the environment and
// from the working directory, so the fixture must exist before the import.
const runId = "fe-e2e-authority-fixture";
const workDirectory = realpathSync(
  mkdtempSync(path.join(os.tmpdir(), "bnest-authority-test-")),
);
const runtimeRoot = path.join(workDirectory, "data/test/runs", runId);
const lockRoot = path.join(runtimeRoot, "storage-config", "storage.json.lock");

mkdirSync(runtimeRoot, { recursive: true });
writeFileSync(
  path.join(runtimeRoot, ".bnest-test-run.json"),
  JSON.stringify({ recordType: "bnest-test-run", runId }),
);
process.chdir(workDirectory);
process.env["BNEST_E2E_RUNTIME_ROOT"] = runtimeRoot;
process.env["BNEST_E2E_RUN_ID"] = runId;
delete process.env["BNEST_STORAGE_CONFIG"];

const { captureStorageAuthority, restoreStorageAuthority } =
  await import("../tests/support/storage-authority.mts");

after(() => {
  rmSync(workDirectory, { recursive: true, force: true });
});

function entries(directory: string): string[] {
  return existsSync(directory) ? readdirSync(directory) : [];
}

test("restoring does not bring back a shared lease that was in flight at capture", () => {
  mkdirSync(path.join(lockRoot, "shared", "in-flight-lease"), {
    recursive: true,
  });

  captureStorageAuthority();
  // The operation that held the lease finishes before the scenario ends.
  rmSync(path.join(lockRoot, "shared", "in-flight-lease"), { recursive: true });
  restoreStorageAuthority();

  assert.deepEqual(entries(path.join(lockRoot, "shared")), []);
});

test("restoring does not bring back an exclusive lock that was held at capture", () => {
  mkdirSync(path.join(lockRoot, "exclusive"), { recursive: true });
  writeFileSync(path.join(lockRoot, "exclusive", "owner"), "1");

  captureStorageAuthority();
  rmSync(path.join(lockRoot, "exclusive"), { recursive: true });
  restoreStorageAuthority();

  assert.equal(existsSync(path.join(lockRoot, "exclusive")), false);
});

test("restoring still returns every other runtime file to its captured state", () => {
  const recordPath = path.join(runtimeRoot, "general", "record.json");
  mkdirSync(path.dirname(recordPath), { recursive: true });
  writeFileSync(recordPath, "captured");

  captureStorageAuthority();
  writeFileSync(recordPath, "changed by the scenario");
  writeFileSync(path.join(runtimeRoot, "general", "extra.json"), "extra");
  restoreStorageAuthority();

  assert.equal(readFileSync(recordPath, "utf8"), "captured");
  assert.equal(
    existsSync(path.join(runtimeRoot, "general", "extra.json")),
    false,
  );
});
