import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { flatAccountFiles } from "./test-runtime.mts";

// Only this project audits a flat-primary instance root, so these tests live here and not in the shared
// run-base-leaks suite. Each test uses a temporary directory, never data/test or ~/bnest.
function temporaryFlatRoot(): { root: string; cleanup: () => void } {
  const base = mkdtempSync(path.join(os.tmpdir(), "bnest-flat-root-test-"));
  return {
    root: path.join(base, "instance"),
    cleanup: () => rmSync(base, { recursive: true, force: true }),
  };
}

test("lists every account, username, and user file under a flat root", () => {
  const { root, cleanup } = temporaryFlatRoot();

  try {
    mkdirSync(path.join(root, "system", "accounts"), { recursive: true });
    mkdirSync(path.join(root, "system", "usernames"), { recursive: true });
    mkdirSync(path.join(root, "users", "user-x", "chat"), { recursive: true });
    const account = path.join(root, "system", "accounts", "user-x.json");
    const username = path.join(root, "system", "usernames", "test-user-x.json");
    const chat = path.join(root, "users", "user-x", "chat", "current.json");
    writeFileSync(account, "{}");
    writeFileSync(username, "{}");
    writeFileSync(chat, "{}");

    assert.deepEqual(
      flatAccountFiles(root).toSorted(),
      [account, username, chat].toSorted(),
    );
  } finally {
    cleanup();
  }
});

test("an empty flat root has no account files, and an absent root is refused", () => {
  const { root, cleanup } = temporaryFlatRoot();

  try {
    mkdirSync(root, { recursive: true });
    assert.deepEqual(flatAccountFiles(root), []);
    assert.throws(
      () => flatAccountFiles(path.join(root, "absent")),
      /flat root is not a directory/u,
    );
  } finally {
    cleanup();
  }
});
