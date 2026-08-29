import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import test from "node:test";

import { runCli } from "./cli-application.mjs";
import {
  cpuUtilizationPercent,
  defaultEvidenceRoot,
  parseAvailableNonCompressedEstimate,
  parseSwapUsage,
  parseVmStat,
  readHostSample,
} from "./metrics.mjs";
import {
  admissionReady,
  cpuAdmissionReady,
  developmentPolicy,
  developmentMemoryState,
  essentialReadingsValid,
  percentile,
  releaseResourceHeadroomAvailable,
} from "./policy.mjs";

const gib = 1024 ** 3;

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
  assert.equal(cpuUtilizationPercent(null, after), null);
  assert.equal(cpuUtilizationPercent([], after), null);
  assert.equal(cpuUtilizationPercent(after, before), null);
  assert.equal(cpuUtilizationPercent(before, before), null);
});

test("rejects malformed macOS aggregate outputs", () => {
  assert.equal(parseAvailableNonCompressedEstimate("missing", 32 * gib), null);
  assert.equal(
    parseAvailableNonCompressedEstimate(
      "System-wide memory free percentage: 101%",
      32 * gib,
    ),
    null,
  );
  assert.equal(parseSwapUsage("missing"), null);
  assert.equal(parseVmStat("missing"), null);
});

test("collects a complete host sample through deterministic platform seams", () => {
  const outputs = new Map([
    ["memory_pressure -Q", "System-wide memory free percentage: 50%"],
    [
      "vm_stat",
      "Mach Virtual Memory Statistics: (page size of 16384 bytes)\n" +
        "Pages stored in compressor: 10.\nPages occupied by compressor: 5.\n" +
        "Swapins: 3.\nSwapouts: 4.\n",
    ],
    [
      "sysctl -n vm.swapusage",
      "total = 4096.00M  used = 2560.00M  free = 1536.00M",
    ],
    ["sysctl -n kern.memorystatus_vm_pressure_level", "1\n"],
    ["sysctl -n vm.compressor_available", "1\n"],
    ["sysctl -n vm.compressor_bytes_used", `${7 * gib}\n`],
  ]);
  const previous = [{ user: 10, nice: 0, sys: 10, idle: 70, irq: 10 }];
  const current = [{ user: 20, nice: 0, sys: 20, idle: 140, irq: 20 }];
  const reading = readHostSample(previous, {
    diskPath: "/fixture",
    dependencies: {
      availableParallelism: () => 12,
      cpus: () => current.map((times) => ({ times })),
      now: () => new Date("2026-08-30T00:00:00.000Z"),
      spawnSync: (command, arguments_) => ({
        status: 0,
        stdout: outputs.get([command, ...arguments_].join(" ")),
      }),
      statfsSync: () => ({ bavail: 100, bsize: 4096 }),
      totalmem: () => 32 * gib,
    },
  });
  assert.deepEqual(reading.cpuTimes, current);
  assert.deepEqual(reading.sample, {
    schemaVersion: 2,
    measuredAt: "2026-08-30T00:00:00.000Z",
    availableNonCompressedEstimateBytes: 16 * gib,
    memoryPressureLevel: 1,
    compressorAvailable: true,
    compressorPayloadBytes: 7 * gib,
    physicalMemoryBytes: 32 * gib,
    availableParallelism: 12,
    cpuUtilizationPercent: 30,
    diskFreeBytes: 409_600,
    pageSizeBytes: 16_384,
    compressorStoredPages: 10,
    compressorOccupiedPages: 5,
    swapIns: 3,
    swapOuts: 4,
    swapTotalBytes: 4 * gib,
    swapUsedBytes: 2560 * 1024 ** 2,
    swapFreeBytes: 1536 * 1024 ** 2,
  });
});

test("degrades failed platform readings to explicit nulls", () => {
  const { sample: failed } = readHostSample(null, {
    diskPath: "/missing",
    dependencies: {
      availableParallelism: () => 4,
      cpus: () => [{ times: { user: 1, nice: 0, sys: 1, idle: 8, irq: 0 } }],
      now: () => new Date("2026-08-30T00:00:00.000Z"),
      spawnSync: () => ({ status: 1, stdout: "" }),
      statfsSync: () => {
        throw new Error("unavailable");
      },
      totalmem: () => 8 * gib,
    },
  });
  assert.equal(failed.availableNonCompressedEstimateBytes, null);
  assert.equal(failed.memoryPressureLevel, null);
  assert.equal(failed.compressorAvailable, null);
  assert.equal(failed.compressorPayloadBytes, null);
  assert.equal(failed.cpuUtilizationPercent, null);
  assert.equal(failed.diskFreeBytes, null);
  assert.equal(failed.pageSizeBytes, null);
  assert.equal(failed.swapTotalBytes, null);
});

test("resolves private evidence roots from configuration or the home default", () => {
  assert.equal(
    defaultEvidenceRoot({ BNEST_RESOURCE_ROOT: "/private/evidence" }),
    "/private/evidence",
  );
  assert.match(defaultEvidenceRoot({}), /bnest\/runtime\/resource-guard$/u);
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
  assert.equal(
    cpuAdmissionReady(sample({ cpuUtilizationPercent: null })),
    false,
  );
  assert.equal(
    essentialReadingsValid(sample({ availableParallelism: 0 })),
    false,
  );
});

test("computes finite nearest-rank percentiles", () => {
  assert.equal(percentile([3, Number.NaN, 1, 2], 0.95), 3);
  assert.equal(percentile([], 0.95), null);
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

test("orchestrates status output without real host sampling", async () => {
  const logs = [];
  const reading = {
    cpuTimes: [{ idle: 1 }],
    sample: sample({ cpuUtilizationPercent: 12.34 }),
  };
  const dependencies = {
    collect: () => reading,
    log: (message) => logs.push(message),
    sleep: async () => {},
  };
  assert.equal(
    await runCli({ arguments_: ["status", "--json"], dependencies }),
    0,
  );
  assert.equal(JSON.parse(logs.pop()).schemaVersion, 2);
  assert.equal(await runCli({ arguments_: ["status"], dependencies }), 0);
  assert.match(logs.pop(), /state=normal .*cpu=12\.3%/u);
});

test("monitors only state transitions and clears its interval on signal", async () => {
  const logs = [];
  const signalSource = new EventEmitter();
  const interval = Symbol("interval");
  let cleared = null;
  let intervalCallback;
  const monitored = runCli({
    arguments_: ["monitor"],
    dependencies: {
      clearInterval: (value) => {
        cleared = value;
      },
      collect: () => ({ cpuTimes: [{ idle: 1 }], sample: sample() }),
      log: (message) => logs.push(message),
      setInterval: (callback) => {
        intervalCallback = callback;
        return interval;
      },
      signalSource,
    },
  });
  intervalCallback();
  signalSource.emit("SIGTERM");
  assert.equal(await monitored, 0);
  assert.deepEqual(logs, ["2026-08-29T00:00:00.000Z state=normal"]);
  assert.equal(cleared, interval);
});

test("validates and delegates guarded run arguments", async () => {
  let invocation;
  const environment = { BNEST_RESOURCE_ROOT: "/private/root" };
  const exitCode = await runCli({
    arguments_: ["run", "--class", "service", "--", "tool", "one"],
    environment,
    dependencies: {
      run: async (options) => {
        invocation = options;
        return 23;
      },
    },
  });
  assert.equal(exitCode, 23);
  assert.deepEqual(invocation, {
    command: "tool",
    arguments_: ["one"],
    environment,
    evidenceRoot: "/private/root",
    taskClass: "service",
  });
  await assert.rejects(
    runCli({ arguments_: ["run", "--class", "invalid", "--", "tool"] }),
    /--class must be/u,
  );
  await assert.rejects(runCli({ arguments_: ["run"] }), /run requires/u);
  await assert.rejects(runCli({ arguments_: ["unknown"] }), /Expected status/u);
});
