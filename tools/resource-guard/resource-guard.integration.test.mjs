import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { EventEmitter } from "node:events";
import {
  chmodSync,
  existsSync,
  mkdtempSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  rmSync,
  statSync,
  truncateSync,
  utimesSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import {
  cleanupEvidence,
  EvidenceWriter,
  evidenceIdentifier,
  safeEvidenceName,
} from "./evidence.mjs";
import { runGuardedCommand } from "./guard.mjs";
import {
  acquireSession,
  inheritedSession,
  releaseSession,
} from "./session.mjs";

const gib = 1024 ** 3;

function temporaryRoot(testContext, prefix) {
  const root = mkdtempSync(join(tmpdir(), prefix));
  testContext.after(() => rmSync(root, { force: true, recursive: true }));
  return root;
}

function sample(overrides = {}) {
  return {
    schemaVersion: 2,
    measuredAt: "2026-08-29T00:00:00.000Z",
    availableNonCompressedEstimateBytes: 12 * gib,
    memoryPressureLevel: 1,
    compressorAvailable: true,
    compressorPayloadBytes: 7 * gib,
    physicalMemoryBytes: 32 * gib,
    availableParallelism: 12,
    cpuUtilizationPercent: 40,
    diskFreeBytes: 20 * gib,
    pageSizeBytes: 16_384,
    compressorStoredPages: 1,
    compressorOccupiedPages: 1,
    swapIns: 10,
    swapOuts: 20,
    swapTotalBytes: 4 * gib,
    swapUsedBytes: 2 * gib,
    swapFreeBytes: 2 * gib,
    ...overrides,
  };
}

test("writes private schema-v2 evidence and removes expired raw samples", (t) => {
  const root = temporaryRoot(t, "bnest-resource-evidence-");
  const writer = new EvidenceWriter(root, "fixture");
  writer.append(sample());
  const summary = writer.finalize({
    taskClass: "ephemeral",
    outcome: "passed",
  });
  assert.equal(summary.schemaVersion, 2);
  assert.equal(statSync(writer.outputPath).mode & 0o777, 0o600);
  const expired = join(root, "expired.jsonl");
  writeFileSync(expired, "{}\n", { mode: 0o600 });
  const old = new Date(Date.now() - 8 * 24 * 60 * 60 * 1000);
  utimesSync(expired, old, old);
  cleanupEvidence(root);
  assert.equal(readdirSync(root).includes("expired.jsonl"), false);
});

test("bounds evidence size while preserving the active artifact", (t) => {
  const root = temporaryRoot(t, "bnest-resource-bounds-");
  const preserved = join(root, "active.jsonl");
  const removable = join(root, "old.jsonl");
  writeFileSync(preserved, "");
  writeFileSync(removable, "");
  truncateSync(preserved, 30 * 1024 ** 2);
  truncateSync(removable, 30 * 1024 ** 2);
  const older = new Date(Date.now() - 60_000);
  const newer = new Date(Date.now() - 30_000);
  utimesSync(preserved, older, older);
  utimesSync(removable, newer, newer);

  cleanupEvidence(root, { preserve: [preserved] });

  assert.equal(existsSync(preserved), true);
  assert.equal(existsSync(removable), false);
});

test("summarizes empty evidence and sanitizes public artifact names", (t) => {
  const root = temporaryRoot(t, "bnest-resource-empty-");
  const writer = new EvidenceWriter(root, "empty");
  const summary = writer.finalize({
    taskClass: "transactional",
    outcome: "capacity-deferred",
    healthFailures: 2,
  });
  assert.equal(summary.sampleCount, 0);
  assert.equal(summary.availableParallelism, 0);
  assert.equal(summary.diskFreeMinBytes, null);
  assert.equal(summary.swapFreeMinBytes, null);
  assert.equal(summary.healthFailures, 2);
  assert.equal(
    evidenceIdentifier("unsafe prefix", 10, 20),
    "unsafe-prefix-10-20",
  );
  assert.equal(safeEvidenceName("/private/path/report.json"), "report.json");
});

test("sheds only the guarded child after sustained warning", async (t) => {
  const root = temporaryRoot(t, "bnest-resource-guard-");
  let count = 0;
  const collect = () => ({
    cpuTimes: [{ idle: count }],
    sample: sample(
      count++ < 3
        ? {}
        : {
            memoryPressureLevel: 2,
          },
    ),
  });
  const exitCode = await runGuardedCommand({
    command: process.execPath,
    arguments_: ["-e", "setInterval(() => {}, 1000)"],
    evidenceRoot: root,
    taskClass: "ephemeral",
    dependencies: {
      collect,
      policy: {
        admissionWindowMs: 100,
        ephemeralWarningGraceMs: 5,
        sampleIntervalMs: 2,
        terminationGraceMs: 20,
      },
      sleep: async () => {},
    },
  });
  assert.equal(exitCode, 75);
  assert.equal(existsSync(join(root, "heavy.lock")), false);
  const summary = readdirSync(root).find((entry) =>
    entry.endsWith(".summary.json"),
  );
  assert.ok(summary);
});

test("accepts only a verified live nested session and releases its exact owner", async (t) => {
  const root = temporaryRoot(t, "bnest-resource-session-");
  const owner = await acquireSession(root, {
    waitMs: 0,
    sleep: async () => {},
  });
  assert.ok(owner);
  assert.equal(inheritedSession(root, owner.token), true);
  assert.equal(inheritedSession(root, "forged"), false);
  assert.equal(inheritedSession(root, null), false);
  const nested = await acquireSession(root, {
    token: owner.token,
    waitMs: 0,
    sleep: async () => {},
  });
  assert.equal(nested.inherited, true);
  releaseSession(root, nested);
  assert.equal(existsSync(join(root, "heavy.lock")), true);
  releaseSession(root, owner);
  assert.equal(existsSync(join(root, "heavy.lock")), false);
});

test("reclaims stale sessions and times out behind a live owner", async (t) => {
  const root = temporaryRoot(t, "bnest-resource-stale-");
  const lockPath = join(root, "heavy.lock");
  mkdirSync(lockPath, { recursive: true });
  writeFileSync(
    join(lockPath, "owner.json"),
    `${JSON.stringify({ schemaVersion: 1, pid: 99_999_999, token: "stale" })}\n`,
  );
  assert.equal(inheritedSession(root, "stale"), false);
  const owner = await acquireSession(root, {
    waitMs: 100,
    sleep: async () => {},
  });
  assert.ok(owner);
  const contender = await acquireSession(root, {
    waitMs: 0,
    sleep: async () => {},
  });
  assert.equal(contender, null);
  releaseSession(root, owner);
});

test("refuses to release a lease after its ownership record changes", async (t) => {
  const root = temporaryRoot(t, "bnest-resource-owner-");
  const owner = await acquireSession(root, { waitMs: 0 });
  writeFileSync(
    join(root, "heavy.lock", "owner.json"),
    `${JSON.stringify({ schemaVersion: 1, pid: process.pid, token: "other" })}\n`,
  );
  assert.throws(() => releaseSession(root, owner), /another process/u);
});

test("surfaces non-contention lease filesystem failures", async (t) => {
  const root = temporaryRoot(t, "bnest-resource-permission-");
  chmodSync(root, 0o500);
  try {
    await assert.rejects(acquireSession(root, { waitMs: 0 }));
  } finally {
    chmodSync(root, 0o700);
  }
});

test("defers immediately when the admission window cannot become safe", async (t) => {
  const root = temporaryRoot(t, "bnest-resource-deferred-");
  let clock = 0;
  const exitCode = await runGuardedCommand({
    command: "unused",
    arguments_: [],
    evidenceRoot: root,
    dependencies: {
      collect: () => ({ cpuTimes: [], sample: sample() }),
      now: () => (clock += 100),
      policy: { admissionWindowMs: 1 },
      sleep: async () => {},
    },
  });
  assert.equal(exitCode, 75);
  assert.equal(existsSync(join(root, "heavy.lock")), false);
});

test("defers while another live heavy lease owns capacity", async (t) => {
  const root = temporaryRoot(t, "bnest-resource-busy-");
  const owner = await acquireSession(root, { waitMs: 0 });
  const exitCode = await runGuardedCommand({
    command: "unused",
    arguments_: [],
    evidenceRoot: root,
    dependencies: { policy: { leaseWaitMs: 0 }, sleep: async () => {} },
  });
  assert.equal(exitCode, 75);
  releaseSession(root, owner);
});

test("executes nested work under its verified inherited session", async (t) => {
  const root = temporaryRoot(t, "bnest-resource-nested-");
  const owner = await acquireSession(root, { waitMs: 0 });
  const exitCode = await runGuardedCommand({
    command: process.execPath,
    arguments_: ["-e", "process.exit(7)"],
    environment: { BNEST_RESOURCE_SESSION: owner.token },
    evidenceRoot: root,
  });
  assert.equal(exitCode, 7);
  assert.equal(existsSync(join(root, "heavy.lock")), true);
  releaseSession(root, owner);
});

test("forwards terminal signals to the guarded child and removes listeners", async (t) => {
  const root = temporaryRoot(t, "bnest-resource-signal-");
  const signalSource = new EventEmitter();
  let count = 0;
  const guarded = runGuardedCommand({
    command: process.execPath,
    arguments_: ["-e", "setInterval(() => {}, 1000)"],
    evidenceRoot: root,
    dependencies: {
      collect: () => ({
        cpuTimes: [{ idle: count }],
        sample: sample({ cpuUtilizationPercent: count++ === 0 ? null : 1 }),
      }),
      policy: { admissionWindowMs: 100, sampleIntervalMs: 50 },
      signalSource,
      sleep: async () => {},
    },
  });
  await new Promise((resolvePromise) => setTimeout(resolvePromise, 20));
  signalSource.emit("SIGINT");
  assert.equal(await guarded, 130);
  assert.equal(signalSource.listenerCount("SIGINT"), 0);
  assert.equal(signalSource.listenerCount("SIGTERM"), 0);
  assert.equal(existsSync(join(root, "heavy.lock")), false);
});

test("records critical pressure without shedding transactional work", async (t) => {
  const root = temporaryRoot(t, "bnest-resource-transaction-");
  let count = 0;
  const collect = () => ({
    cpuTimes: [{ idle: count }],
    sample: sample(
      count++ < 3
        ? {}
        : {
            compressorAvailable: false,
          },
    ),
  });
  const exitCode = await runGuardedCommand({
    command: process.execPath,
    arguments_: ["-e", "setTimeout(() => process.exit(0), 20)"],
    evidenceRoot: root,
    taskClass: "transactional",
    dependencies: {
      collect,
      policy: { admissionWindowMs: 100, sampleIntervalMs: 2 },
      sleep: async () => {},
    },
  });
  assert.equal(exitCode, 0);
});

test("records ordinary child failure without translating it to capacity", async (t) => {
  const root = temporaryRoot(t, "bnest-resource-task-failure-");
  const exitCode = await runGuardedCommand({
    command: process.execPath,
    arguments_: ["-e", "process.exit(9)"],
    evidenceRoot: root,
    dependencies: {
      collect: () => ({ cpuTimes: [{ idle: 1 }], sample: sample() }),
      policy: { admissionWindowMs: 100 },
      sleep: async () => {},
    },
  });
  assert.equal(exitCode, 9);
  const summaryPath = readdirSync(root)
    .filter((entry) => entry.endsWith(".summary.json"))
    .map((entry) => join(root, entry))
    .at(-1);
  assert.equal(
    JSON.parse(readFileSync(summaryPath, "utf8")).outcome,
    "task-failed",
  );
});

test("releases its lease when child startup fails", async (t) => {
  const root = temporaryRoot(t, "bnest-resource-spawn-error-");
  const child = new EventEmitter();
  child.pid = null;
  await assert.rejects(
    runGuardedCommand({
      command: "missing",
      arguments_: [],
      evidenceRoot: root,
      dependencies: {
        collect: () => ({ cpuTimes: [{ idle: 1 }], sample: sample() }),
        policy: { admissionWindowMs: 100 },
        sleep: async () => {},
        spawn: () => {
          queueMicrotask(() => child.emit("error", new Error("spawn failed")));
          return child;
        },
      },
    }),
    /spawn failed/u,
  );
  assert.equal(existsSync(join(root, "heavy.lock")), false);
});

test("falls back to signaling the child when its process group is absent", async (t) => {
  const root = temporaryRoot(t, "bnest-resource-signal-fallback-");
  const child = new EventEmitter();
  child.pid = 99_999_999;
  const signals = [];
  child.kill = (signal) => {
    signals.push(signal);
    if (signal === "SIGTERM")
      queueMicrotask(() => child.emit("exit", null, "SIGTERM"));
  };
  let count = 0;
  const exitCode = await runGuardedCommand({
    command: "fixture",
    arguments_: [],
    evidenceRoot: root,
    dependencies: {
      clearInterval: () => {},
      clearTimeout: () => {},
      collect: () => ({
        cpuTimes: [{ idle: count }],
        sample: sample(count++ < 3 ? {} : { memoryPressureLevel: 4 }),
      }),
      policy: { admissionWindowMs: 100, terminationGraceMs: 10 },
      setInterval: (callback) => {
        queueMicrotask(callback);
        return 1;
      },
      setTimeout: () => 2,
      sleep: async () => {},
      spawn: () => child,
    },
  });
  assert.equal(exitCode, 75);
  assert.deepEqual(signals, ["SIGTERM"]);
});

test("the process adapter reports errors and preserves nested exit codes", async (t) => {
  const root = temporaryRoot(t, "bnest-resource-cli-");
  const invalid = spawnSync(
    process.execPath,
    [join(import.meta.dirname, "cli.mjs"), "bad"],
    {
      encoding: "utf8",
    },
  );
  assert.equal(invalid.status, 1);
  assert.match(invalid.stderr, /Expected status, monitor, or run/u);

  const owner = await acquireSession(root, { waitMs: 0 });
  const nested = spawnSync(
    process.execPath,
    [
      join(import.meta.dirname, "cli.mjs"),
      "run",
      "--",
      process.execPath,
      "-e",
      "process.exit(7)",
    ],
    {
      encoding: "utf8",
      env: {
        ...process.env,
        BNEST_RESOURCE_ROOT: root,
        BNEST_RESOURCE_SESSION: owner.token,
      },
    },
  );
  assert.equal(nested.status, 7);
  releaseSession(root, owner);
});
