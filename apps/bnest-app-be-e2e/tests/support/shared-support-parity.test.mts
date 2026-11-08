import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

// Support files that both E2E projects keep as byte-identical copies. Each project owns its copy, so an edit
// to one must be made to the other. Shared code is not moved into a library here: the copies are kept equal.
const sharedNames = [
  "backup-repository.mts",
  "backup-repository.test.mts",
  "browser-environment.mts",
  "browser-environment.test.mts",
  "delete-when-idle.mts",
  "delete-when-idle.test.mts",
  "instance-record-read.mts",
  "instance-record-read.test.mts",
  "run-base-leaks.test.mts",
  "secondary-environment.mts",
  "secondary-environment.test.mts",
  "test-instance-paths.mts",
  "test-instance-paths.test.mts",
  "test-runtime.test.mts",
  "testing-control-error.mts",
  "testing-control-errors.test.mts",
  "testing-control-records.mts",
  "testing-control-stand-in.mts",
  "testing-control.mts",
  "testing-control.test.mts",
];

test("keeps the shared support files byte-identical in both E2E projects", () => {
  for (const name of sharedNames) {
    const backend = readFileSync(new URL(`./${name}`, import.meta.url));
    const frontend = readFileSync(
      new URL(
        `../../../bnest-app-fe-e2e/tests/support/${name}`,
        import.meta.url,
      ),
    );

    assert.ok(
      backend.equals(frontend),
      `${name} differs between bnest-app-be-e2e and bnest-app-fe-e2e`,
    );
  }
});
