import assert from "node:assert/strict";
import {
  existsSync,
  mkdtempSync,
  readdirSync,
  rmSync,
  statSync,
  utimesSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { EventEmitter } from "node:events";
import test from "node:test";

import { cleanupEvidence, EvidenceWriter } from "./evidence.mjs";
import { runGuardedCommand } from "./guard.mjs";
import {
  cpuUtilizationPercent,
  parseAvailableNonCompressedEstimate,
  parseSwapUsage,
  parseVmStat,
} from "./metrics.mjs";
import {
  admissionReady,
  developmentPolicy,
  developmentMemoryState,
  releaseResourceHeadroomAvailable,
} from "./policy.mjs";
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

test("parses supported macOS aggregate outputs without calling them free RAM", () => {
  assert.equal(
    parseAvailableNonCompressedEstimate(
      "System-wide memory free percentage: 65%",
      32 * gib,
    ),
    20.8 * gib,
  );
  assert.deepEqual(
    parseSwapUsage("total = 4096.00M  used = 2562.38M  free = 1533.62M"),
    {
      swapTotalBytes: 4096 * 1024 ** 2,
      swapUsedBytes: 2562.38 * 1024 ** 2,
      swapFreeBytes: 1533.62 * 1024 ** 2,
    },
  );
  assert.deepEqual(
    parseVmStat(
      "Mach Virtual Memory Statistics: (page size of 16384 bytes)\n" +
        "Pages stored in compressor: 10.\nPages occupied by compressor: 5.\n" +
        "Swapins: 3.\nSwapouts: 4.\n",
    ),
    {
      pageSizeBytes: 16_384,
      compressorStoredPages: 10,
      compressorOccupiedPages: 5,
      swapIns: 3,
      swapOuts: 4,
    },
  );
});

test("derives normalized CPU from cumulative time deltas", () => {
  const before = [{ user: 10, nice: 0, sys: 10, idle: 70, irq: 10 }];
  const after = [{ user: 20, nice: 0, sys: 20, idle: 140, irq: 20 }];
  assert.equal(cpuUtilizationPercent(before, after), 30);
});

test("classifies platform warning, critical, compressor, memory, and invalid state", () => {
  assert.equal(developmentMemoryState(sample()), "normal");
  assert.equal(
    developmentMemoryState(sample({ memoryPressureLevel: 2 })),
    "warning",
  );
  assert.equal(
    developmentMemoryState(sample({ memoryPressureLevel: 4 })),
    "critical",
  );
  assert.equal(
    developmentMemoryState(sample({ compressorAvailable: false })),
    "critical",
  );
  assert.equal(
    developmentMemoryState(
      sample({ availableNonCompressedEstimateBytes: 3 * gib }),
    ),
    "critical",
  );
  assert.equal(
    developmentMemoryState(sample({ memoryPressureLevel: null })),
    "critical",
  );
});

test("requires three safe interval CPU samples for admission", () => {
  assert.equal(admissionReady([sample(), sample()]), false);
  assert.equal(admissionReady([sample(), sample(), sample()]), true);
  assert.equal(
    admissionReady([sample(), sample({ cpuUtilizationPercent: 84 }), sample()]),
    false,
  );
});

test("keeps the documented warning grace periods distinct by task class", () => {
  assert.equal(developmentPolicy.ephemeralWarningGraceMs, 10_000);
  assert.equal(developmentPolicy.serviceWarningGraceMs, 30_000);
});

test("release proof uses compressor availability and swap-qualified memory", () => {
  const healthy = {
    availableParallelism: 12,
    availableNonCompressedEstimateMinBytes: 12 * gib,
    memoryPressureLevelMax: 1,
    compressorAvailableAll: true,
    cpuUtilizationP95Percent: 80,
    swapInsDelta: 20,
    swapOutsDelta: 30,
    healthFailures: 0,
  };
  assert.equal(releaseResourceHeadroomAvailable(healthy), true);
  assert.equal(
    releaseResourceHeadroomAvailable({
      ...healthy,
      availableNonCompressedEstimateMinBytes: 3 * gib,
    }),
    false,
  );
  assert.equal(
    releaseResourceHeadroomAvailable({
      ...healthy,
      compressorAvailableAll: false,
    }),
    false,
  );
});

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
