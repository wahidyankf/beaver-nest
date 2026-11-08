import assert from "node:assert/strict";
import {
  existsSync,
  mkdtempSync,
  mkdirSync,
  rmSync,
  symlinkSync,
  utimesSync,
  writeFileSync,
} from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { cleanupStaleTestData } from "./test-data-cleanup.mjs";

// Every call passes `legacyParents: []` unless it tests the legacy sweep on
// temporary directories. Without it the default would sweep the real
// ~/bnest/data/test legacy directories from a test run.
const now = Date.parse("2026-08-29T12:00:00.000Z");

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

function ageDirectory(directory, isoTime) {
  const date = new Date(isoTime);
  utimesSync(directory, date, date);
}

test("removes only stale marked direct children", () => {
  const root = mkdtempSync(path.join(os.tmpdir(), "bnest-cleanup-test-"));

  try {
    const old = markedRun(root, "old", "2026-01-01T00:00:00.000Z");
    const recent = markedRun(root, "recent", "2026-08-29T11:30:00.000Z");
    mkdirSync(path.join(root, "unmarked"));

    const result = cleanupStaleTestData({
      roots: [root],
      legacyParents: [],
      olderThanHours: 24,
      now,
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
      legacyParents: [],
      olderThanHours: 0,
      now,
    });

    assert.deepEqual(result, { removed: 0, retained: 1 });
    assert.equal(existsSync(active), true);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("retains a stale run whose owner pid exists under another user", () => {
  // Pid 1 is alive for every user. For a user who cannot signal it, kill(2)
  // answers EPERM, which means alive, not dead.
  const root = mkdtempSync(path.join(os.tmpdir(), "bnest-cleanup-eperm-test-"));

  try {
    const foreign = markedRun(
      root,
      "foreign-owner",
      "2026-01-01T00:00:00.000Z",
      {
        hostname: os.hostname(),
        pid: 1,
      },
    );

    const result = cleanupStaleTestData({
      roots: [root],
      legacyParents: [],
      olderThanHours: 0,
      now,
    });

    assert.deepEqual(result, { removed: 0, retained: 1 });
    assert.equal(existsSync(foreign), true);
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
      legacyParents: [],
      olderThanHours: 0,
      now,
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
      legacyParents: [],
      olderThanHours: 0,
      now,
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
      legacyParents: [],
      olderThanHours: 0,
      now,
    });

    assert.deepEqual(result, { removed: 0, retained: 0 });
    assert.equal(existsSync(path.join(outside, "sentinel")), true);
  } finally {
    rmSync(root, { recursive: true, force: true });
    rmSync(outside, { recursive: true, force: true });
  }
});

test("removes a stale run together with its test instances", () => {
  const root = mkdtempSync(
    path.join(os.tmpdir(), "bnest-cleanup-instance-test-"),
  );
  const instanceId = "a1b2c3d4e5f6g7h8";

  try {
    const run = markedRun(
      root,
      "stale-with-instance",
      "2026-01-01T00:00:00.000Z",
      {
        hostname: os.hostname(),
        pid: 99_999_999,
      },
    );
    const instance = path.join(run, "instances", instanceId);
    mkdirSync(path.join(instance, "db"), { recursive: true });
    writeFileSync(path.join(instance, "db", "bnest.sqlite3"), "");
    writeFileSync(
      path.join(instance, ".bnest-test-instance.json"),
      JSON.stringify({
        schemaVersion: 1,
        recordType: "bnest-test-instance",
        runId: "stale-with-instance",
        instanceId,
        owner: "bnest-test-harness",
        createdAt: "2026-01-01T00:00:00.000Z",
      }),
    );

    const result = cleanupStaleTestData({
      roots: [root],
      legacyParents: [],
      olderThanHours: 24,
      now,
    });

    assert.deepEqual(result, { removed: 1, retained: 0 });
    assert.equal(existsSync(instance), false);
    assert.equal(existsSync(run), false);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("retains a stale run with instances while its owner process is alive", () => {
  const root = mkdtempSync(
    path.join(os.tmpdir(), "bnest-cleanup-live-instance-test-"),
  );

  try {
    const run = markedRun(
      root,
      "live-with-instance",
      "2026-01-01T00:00:00.000Z",
      {
        hostname: os.hostname(),
        pid: process.pid,
      },
    );
    const instance = path.join(run, "instances", "a1b2c3d4e5f6g7h8");
    mkdirSync(instance, { recursive: true });

    const result = cleanupStaleTestData({
      roots: [root],
      legacyParents: [],
      olderThanHours: 24,
      now,
    });

    assert.deepEqual(result, { removed: 0, retained: 1 });
    assert.equal(existsSync(instance), true);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("sweeps only stale direct children of the three exact legacy parents", () => {
  const home = mkdtempSync(path.join(os.tmpdir(), "bnest-legacy-test-"));
  const [familyChat, backupConfig, backupRepository] = [
    "family-chat",
    "backup-config",
    "backup-repository",
  ].map((name) => path.join(home, "data", "test", name));

  try {
    for (const parent of [familyChat, backupConfig, backupRepository]) {
      mkdirSync(parent, { recursive: true });
    }

    const staleRun = path.join(familyChat, "run-old");
    mkdirSync(path.join(staleRun, "nested"), { recursive: true });
    writeFileSync(path.join(staleRun, "bnest.sqlite3"), "");
    ageDirectory(staleRun, "2026-01-01T00:00:00.000Z");

    const freshRun = path.join(familyChat, "run-new");
    mkdirSync(freshRun);
    ageDirectory(freshRun, "2026-08-29T11:30:00.000Z");

    const staleConfig = path.join(backupConfig, "config-old");
    mkdirSync(staleConfig);
    ageDirectory(staleConfig, "2026-01-01T00:00:00.000Z");

    const looseFile = path.join(backupConfig, "loose.json");
    writeFileSync(looseFile, "{}");
    ageDirectory(looseFile, "2026-01-01T00:00:00.000Z");

    const staleRepository = path.join(backupRepository, "repo-old");
    mkdirSync(staleRepository);
    ageDirectory(staleRepository, "2026-01-01T00:00:00.000Z");

    // A sibling that only shares a prefix, and a stale directory under a
    // parent that is not on the list, must both survive.
    const prefixSibling = path.join(home, "data", "test", "family-chat-old");
    mkdirSync(prefixSibling);
    ageDirectory(prefixSibling, "2026-01-01T00:00:00.000Z");
    const unlisted = path.join(home, "data", "test", "other", "stale");
    mkdirSync(unlisted, { recursive: true });
    ageDirectory(unlisted, "2026-01-01T00:00:00.000Z");

    const result = cleanupStaleTestData({
      roots: [],
      legacyParents: [familyChat, backupConfig, backupRepository],
      olderThanHours: 24,
      now,
    });

    assert.deepEqual(result, { removed: 3, retained: 2 });
    assert.equal(existsSync(staleRun), false);
    assert.equal(existsSync(staleConfig), false);
    assert.equal(existsSync(staleRepository), false);
    assert.equal(existsSync(freshRun), true);
    assert.equal(existsSync(looseFile), true);
    assert.equal(existsSync(prefixSibling), true);
    assert.equal(existsSync(unlisted), true);
  } finally {
    rmSync(home, { recursive: true, force: true });
  }
});

test("never follows a symlinked legacy parent or a symlinked legacy child", () => {
  const home = mkdtempSync(path.join(os.tmpdir(), "bnest-legacy-link-test-"));
  const outside = mkdtempSync(
    path.join(os.tmpdir(), "bnest-legacy-outside-test-"),
  );

  try {
    const outsideStale = path.join(outside, "stale");
    mkdirSync(outsideStale);
    ageDirectory(outsideStale, "2026-01-01T00:00:00.000Z");

    // A symlinked parent is skipped entirely.
    const linkedParent = path.join(home, "family-chat");
    symlinkSync(outside, linkedParent);

    // A symlinked child under a real parent is retained and never followed.
    const realParent = path.join(home, "backup-config");
    mkdirSync(realParent);
    symlinkSync(outside, path.join(realParent, "linked"));

    const result = cleanupStaleTestData({
      roots: [],
      legacyParents: [linkedParent, realParent],
      olderThanHours: 24,
      now,
    });

    assert.deepEqual(result, { removed: 0, retained: 1 });
    assert.equal(existsSync(outsideStale), true);
  } finally {
    rmSync(home, { recursive: true, force: true });
    rmSync(outside, { recursive: true, force: true });
  }
});
