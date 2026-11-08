import assert from "node:assert/strict";
import {
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { runBaseLeaks, type TestRuntime } from "./test-runtime.mts";

const instanceId = "a1b2c3d4e5f6g7h8";

// Both roots live under a temporary directory, never under data/test or ~/bnest.
function temporaryRuntime(): { runtime: TestRuntime; cleanup: () => void } {
  const base = mkdtempSync(path.join(os.tmpdir(), "bnest-runtime-test-"));
  const runtimePath = path.join(base, "flat", "unit-run-1");
  const sqlitePath = path.join(base, "sqlite", "unit-run-1");
  mkdirSync(runtimePath, { recursive: true });
  mkdirSync(sqlitePath, { recursive: true });

  return {
    runtime: { path: runtimePath, sqlitePath, runId: "unit-run-1" },
    cleanup: () => rmSync(base, { recursive: true, force: true }),
  };
}

test("finds SQLite files and sidecars at any depth under either root", () => {
  const { runtime, cleanup } = temporaryRuntime();

  try {
    mkdirSync(path.join(runtime.path, "deep", "nested"), { recursive: true });
    writeFileSync(
      path.join(runtime.path, "deep", "nested", "x.sqlite3-wal"),
      "",
    );
    mkdirSync(path.join(runtime.sqlitePath, "db"), { recursive: true });
    writeFileSync(path.join(runtime.sqlitePath, "db", "bnest.sqlite3"), "");

    assert.deepEqual(
      runBaseLeaks(runtime).toSorted(),
      [
        path.join(runtime.path, "deep", "nested", "x.sqlite3-wal"),
        path.join(runtime.sqlitePath, "db", "bnest.sqlite3"),
      ].toSorted(),
    );
  } finally {
    cleanup();
  }
});

test("ignores SQLite files inside an instances directory at any depth", () => {
  const { runtime, cleanup } = temporaryRuntime();

  try {
    mkdirSync(path.join(runtime.sqlitePath, "instances", instanceId, "db"), {
      recursive: true,
    });
    writeFileSync(
      path.join(
        runtime.sqlitePath,
        "instances",
        instanceId,
        "db",
        "bnest.sqlite3",
      ),
      "",
    );
    mkdirSync(path.join(runtime.sqlitePath, "other", "instances", instanceId), {
      recursive: true,
    });
    writeFileSync(
      path.join(
        runtime.sqlitePath,
        "other",
        "instances",
        instanceId,
        "bnest.sqlite3",
      ),
      "",
    );

    assert.deepEqual(runBaseLeaks(runtime), []);
  } finally {
    cleanup();
  }
});

test("lists a symlink named like a database and never follows a symlinked directory", () => {
  const { runtime, cleanup } = temporaryRuntime();
  const outside = mkdtempSync(
    path.join(os.tmpdir(), "bnest-runtime-leak-out-"),
  );

  try {
    writeFileSync(path.join(outside, "hidden.sqlite3"), "");
    writeFileSync(path.join(outside, "sentinel"), "preserve");
    symlinkSync(outside, path.join(runtime.path, "escape"));
    symlinkSync(
      path.join(outside, "hidden.sqlite3"),
      path.join(runtime.path, "alias.sqlite3"),
    );

    assert.deepEqual(runBaseLeaks(runtime), [
      path.join(runtime.path, "alias.sqlite3"),
    ]);
    assert.equal(
      readFileSync(path.join(outside, "sentinel"), "utf8"),
      "preserve",
    );
  } finally {
    cleanup();
    rmSync(outside, { recursive: true, force: true });
  }
});
