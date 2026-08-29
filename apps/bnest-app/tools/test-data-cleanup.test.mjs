import assert from "node:assert/strict";
import {
  existsSync,
  mkdtempSync,
  mkdirSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { cleanupStaleTestData } from "./test-data-cleanup.mjs";

function markedRun(root, runId, createdAt, extra = {}) {
  const directory = path.join(root, runId);
  mkdirSync(directory, { recursive: true });
  writeFileSync(
    path.join(directory, ".bnest-test-run.json"),
    JSON.stringify({
      schemaVersion: 1,
      recordType: "bnest-test-run",
      runId,
      createdAt,
      owner: "bnest-test-harness",
      ...extra,
    }),
  );
  return directory;
}

test("removes only stale marked direct children", () => {
  const root = mkdtempSync(path.join(os.tmpdir(), "bnest-cleanup-test-"));

  try {
    const old = markedRun(root, "old", "2026-01-01T00:00:00.000Z");
    const recent = markedRun(root, "recent", "2026-08-29T11:30:00.000Z");
    mkdirSync(path.join(root, "unmarked"));

    const result = cleanupStaleTestData({
      roots: [root],
      olderThanHours: 24,
      now: Date.parse("2026-08-29T12:00:00.000Z"),
    });

    assert.equal(result.removed, 1);
    assert.equal(result.retained, 2);
    assert.equal(path.dirname(old), root);
    assert.equal(existsSync(old), false);
    assert.equal(existsSync(recent), true);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("retains a stale run while its owner process is alive", () => {
  const root = mkdtempSync(
    path.join(os.tmpdir(), "bnest-cleanup-active-test-"),
  );

  try {
    const active = markedRun(root, "active", "2026-01-01T00:00:00.000Z", {
      hostname: os.hostname(),
      pid: process.pid,
    });

    const result = cleanupStaleTestData({
      roots: [root],
      olderThanHours: 0,
      now: Date.parse("2026-08-29T12:00:00.000Z"),
    });

    assert.deepEqual(result, { removed: 0, retained: 1 });
    assert.equal(existsSync(active), true);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("matches short and fully qualified forms of the local hostname", () => {
  const root = mkdtempSync(path.join(os.tmpdir(), "bnest-cleanup-host-test-"));

  try {
    const active = markedRun(
      root,
      "active-short-host",
      "2026-01-01T00:00:00.000Z",
      {
        hostname: os.hostname().split(".", 1)[0],
        pid: process.pid,
      },
    );

    const result = cleanupStaleTestData({
      roots: [root],
      olderThanHours: 0,
      now: Date.parse("2026-08-29T12:00:00.000Z"),
    });

    assert.deepEqual(result, { removed: 0, retained: 1 });
    assert.equal(existsSync(active), true);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("cleans an inactive legacy marker with an unavailable hostname", () => {
  const root = mkdtempSync(path.join(os.tmpdir(), "bnest-cleanup-local-test-"));

  try {
    const stale = markedRun(root, "stale-local", "2026-01-01T00:00:00.000Z", {
      hostname: "local",
      pid: 99_999_999,
    });

    const result = cleanupStaleTestData({
      roots: [root],
      olderThanHours: 0,
      now: Date.parse("2026-08-29T12:00:00.000Z"),
    });

    assert.deepEqual(result, { removed: 1, retained: 0 });
    assert.equal(existsSync(stale), false);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("never follows a symlinked run directory", () => {
  const root = mkdtempSync(path.join(os.tmpdir(), "bnest-cleanup-link-test-"));
  const outside = mkdtempSync(
    path.join(os.tmpdir(), "bnest-cleanup-outside-test-"),
  );

  try {
    writeFileSync(path.join(outside, "sentinel"), "preserve");
    symlinkSync(outside, path.join(root, "linked"));

    const result = cleanupStaleTestData({
      roots: [root],
      olderThanHours: 0,
      now: Date.parse("2026-08-29T12:00:00.000Z"),
    });

    assert.deepEqual(result, { removed: 0, retained: 0 });
    assert.equal(existsSync(path.join(outside, "sentinel")), true);
  } finally {
    rmSync(root, { recursive: true, force: true });
    rmSync(outside, { recursive: true, force: true });
  }
});
