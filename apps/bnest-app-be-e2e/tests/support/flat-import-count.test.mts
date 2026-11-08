import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { countFlatImports } from "./flat-import-count.mts";

// Each test uses a temporary directory, never data/test or ~/bnest.
function temporaryRoot(): { root: string; cleanup: () => void } {
  const base = mkdtempSync(path.join(os.tmpdir(), "bnest-flat-imports-test-"));
  return {
    root: path.join(base, "instance"),
    cleanup: () => rmSync(base, { recursive: true, force: true }),
  };
}

test("counts only the envelope files of one user's imports directory", () => {
  const { root, cleanup } = temporaryRoot();

  try {
    const imports = path.join(root, "users", "user-a", "imports");
    mkdirSync(imports, { recursive: true });
    writeFileSync(path.join(imports, "import-1.json"), "{}");
    writeFileSync(path.join(imports, "import-2.json"), "{}");
    writeFileSync(path.join(imports, "import-2.json.tmp"), "{}");
    mkdirSync(path.join(imports, "nested.json"));
    const other = path.join(root, "users", "user-b", "imports");
    mkdirSync(other, { recursive: true });
    writeFileSync(path.join(other, "import-9.json"), "{}");

    assert.equal(countFlatImports(root, "user-a"), 2);
    assert.equal(countFlatImports(root, "user-b"), 1);
  } finally {
    cleanup();
  }
});

test("counts zero when the user has no imports directory yet", () => {
  const { root, cleanup } = temporaryRoot();

  try {
    mkdirSync(path.join(root, "users", "user-a"), { recursive: true });
    assert.equal(countFlatImports(root, "user-a"), 0);
  } finally {
    cleanup();
  }
});

test("refuses a user id that could name another directory", () => {
  const { root, cleanup } = temporaryRoot();

  try {
    for (const userId of [
      "",
      "../user-a",
      "user/a",
      "user.a",
      "a".repeat(129),
    ]) {
      assert.throws(
        () => countFlatImports(root, userId),
        /not a safe record key/u,
      );
    }
  } finally {
    cleanup();
  }
});
