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
import {
  generateTestControlSecret,
  listTestInstanceLeaks,
  runBaseLeaks,
  tearDownTestInstances,
  type TestRuntime,
} from "./test-runtime.mts";
import type { TestingState } from "./testing-control.mts";

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

function stateWith(
  instance: TestingState["instance"],
  runId = "unit-run-1",
): TestingState {
  return { schemaVersion: 1, runId, instance };
}

test("generates a fresh 32-byte secret as 64 hex characters for each run", () => {
  const first = generateTestControlSecret();
  const second = generateTestControlSecret();

  assert.match(first, /^[0-9a-f]{64}$/u);
  assert.match(second, /^[0-9a-f]{64}$/u);
  assert.notEqual(first, second);
});

test("lists instance entries in both roots and reports none for a clean run", () => {
  const { runtime, cleanup } = temporaryRuntime();

  try {
    assert.deepEqual(listTestInstanceLeaks(runtime), []);

    mkdirSync(path.join(runtime.path, "instances", instanceId), {
      recursive: true,
    });
    mkdirSync(path.join(runtime.sqlitePath, "instances", "0123456789abcdef"), {
      recursive: true,
    });

    assert.deepEqual(
      listTestInstanceLeaks(runtime).toSorted(),
      [
        path.join(runtime.path, "instances", instanceId),
        path.join(runtime.sqlitePath, "instances", "0123456789abcdef"),
      ].toSorted(),
    );
  } finally {
    cleanup();
  }
});

test("reports a symlinked instances directory without listing its target", () => {
  const { runtime, cleanup } = temporaryRuntime();
  const outside = mkdtempSync(path.join(os.tmpdir(), "bnest-runtime-out-"));

  try {
    writeFileSync(path.join(outside, "sentinel"), "preserve");
    symlinkSync(outside, path.join(runtime.path, "instances"));

    assert.deepEqual(listTestInstanceLeaks(runtime), [
      path.join(runtime.path, "instances"),
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

test("finds account files and SQLite files in the run base", () => {
  const { runtime, cleanup } = temporaryRuntime();

  try {
    assert.deepEqual(runBaseLeaks(runtime), []);

    mkdirSync(path.join(runtime.path, "users"), { recursive: true });
    writeFileSync(path.join(runtime.path, "users", "test-user-x.json"), "{}");
    mkdirSync(path.join(runtime.path, "system", "accounts"), {
      recursive: true,
    });
    writeFileSync(
      path.join(runtime.path, "system", "accounts", "test-user-x.json"),
      "{}",
    );
    writeFileSync(path.join(runtime.sqlitePath, "bnest.sqlite3"), "");

    assert.deepEqual(
      runBaseLeaks(runtime).toSorted(),
      [
        path.join(runtime.path, "users"),
        path.join(runtime.path, "system", "accounts"),
        path.join(runtime.sqlitePath, "bnest.sqlite3"),
      ].toSorted(),
    );
  } finally {
    cleanup();
  }
});

test("tears down the current instance and checks the base", async () => {
  const { runtime, cleanup } = temporaryRuntime();
  const deleted: string[] = [];
  const state = stateWith({
    instanceId,
    label: "smoke",
    phase: "sqlite_primary",
    generation: `test-${instanceId}`,
    createdAt: "2026-11-08T00:00:00.000Z",
  });

  try {
    await tearDownTestInstances({
      runtime,
      client: {
        state: () => Promise.resolve(state),
        deleteInstance: (id) => {
          deleted.push(id);
          return Promise.resolve();
        },
      },
    });
    assert.deepEqual(deleted, [instanceId]);
  } finally {
    cleanup();
  }
});

test("does not delete when no instance is current", async () => {
  const { runtime, cleanup } = temporaryRuntime();
  const deleted: string[] = [];

  try {
    await tearDownTestInstances({
      runtime,
      client: {
        state: () => Promise.resolve(stateWith(null)),
        deleteInstance: (id) => {
          deleted.push(id);
          return Promise.resolve();
        },
      },
    });
    assert.deepEqual(deleted, []);
  } finally {
    cleanup();
  }
});

test("refuses teardown when the server serves another run", async () => {
  const { runtime, cleanup } = temporaryRuntime();
  const deleted: string[] = [];

  try {
    await assert.rejects(
      tearDownTestInstances({
        runtime,
        client: {
          state: () => Promise.resolve(stateWith(null, "other-run")),
          deleteInstance: (id) => {
            deleted.push(id);
            return Promise.resolve();
          },
        },
      }),
      /other-run/u,
    );
    assert.deepEqual(deleted, []);
  } finally {
    cleanup();
  }
});

test("fails teardown when the run base is not data-free", async () => {
  const { runtime, cleanup } = temporaryRuntime();

  try {
    mkdirSync(path.join(runtime.path, "users"), { recursive: true });
    writeFileSync(path.join(runtime.path, "users", "test-user-x.json"), "{}");

    await assert.rejects(
      tearDownTestInstances({
        runtime,
        client: {
          state: () => Promise.resolve(stateWith(null)),
          deleteInstance: () => Promise.resolve(),
        },
      }),
      /not data-free/u,
    );
  } finally {
    cleanup();
  }
});

test("the runtime no longer creates a backup repository outside the run roots", () => {
  const source = readFileSync(
    new URL("./test-runtime.mts", import.meta.url),
    "utf8",
  );

  assert.equal(source.includes("backup-repository"), false);
  assert.equal(/\bgit\b/u.test(source), false);
});

test("global teardown no longer removes the roots while the server may write", () => {
  const source = readFileSync(
    new URL("./test-runtime.mts", import.meta.url),
    "utf8",
  );
  const teardown = source.slice(source.indexOf("export default"));

  assert.equal(teardown.includes("cleanupTestRuntime("), false);
});
