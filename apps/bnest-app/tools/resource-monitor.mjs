import { spawnSync } from "node:child_process";
import { appendFileSync, mkdirSync, statfsSync, writeFileSync } from "node:fs";
import { loadavg } from "node:os";
import { dirname } from "node:path";

import { readHostSample } from "../../../tools/resource-guard/metrics.mjs";
import { percentile } from "../../../tools/resource-guard/policy.mjs";

const outputPath = requiredArgument("--output");
const summaryPath = requiredArgument("--summary");
const deploymentRoot = requiredArgument("--deployment-root");
const durationMs = optionalPositiveInteger("--duration-ms");
const samples = [];
let previousCpuTimes = null;

mkdirSync(dirname(outputPath), { recursive: true });
writeFileSync(outputPath, "", { encoding: "utf8", flag: "wx", mode: 0o600 });

function sample() {
  const disk = statfsSync(deploymentRoot);
  const health = caddyHealth();
  const reading = readHostSample(previousCpuTimes, {
    diskPath: deploymentRoot,
  });
  previousCpuTimes = reading.cpuTimes;
  const value = {
    ...reading.sample,
    oneMinuteLoad: loadavg()[0],
    serviceRssBytes: serviceRssBytes(),
    diskFreeBytes: disk.bavail * disk.bsize,
    caddyHealthStatus: health.status,
    caddyHealthLatencyMs: health.latencyMs,
  };
  samples.push(value);
  appendFileSync(outputPath, `${JSON.stringify(value)}\n`, "utf8");
}

function finalize() {
  if (samples.length === 0) sample();
  const summary = {
    schemaVersion: 2,
    sampleCount: samples.length,
    availableParallelism: samples[0].availableParallelism,
    availableNonCompressedEstimateMinBytes: Math.min(
      ...samples.map(
        ({ availableNonCompressedEstimateBytes }) =>
          availableNonCompressedEstimateBytes,
      ),
    ),
    memoryPressureLevelMax: Math.max(
      ...samples.map(({ memoryPressureLevel }) => memoryPressureLevel),
    ),
    compressorAvailableAll: samples.every(
      ({ compressorAvailable }) => compressorAvailable === true,
    ),
    compressorPayloadPeakBytes: Math.max(
      ...samples.map(({ compressorPayloadBytes }) => compressorPayloadBytes),
    ),
    physicalMemoryBytes: samples[0].physicalMemoryBytes,
    cpuUtilizationP95Percent:
      percentile(
        samples
          .map(({ cpuUtilizationPercent }) => cpuUtilizationPercent)
          .filter(Number.isFinite),
        0.95,
      ) ?? 0,
    serviceRssPeakBytes: Math.max(
      ...samples.map(({ serviceRssBytes }) => serviceRssBytes),
    ),
    diskFreeMinBytes: Math.min(
      ...samples.map(({ diskFreeBytes }) => diskFreeBytes),
    ),
    swapInsDelta: Math.max(0, samples.at(-1).swapIns - samples[0].swapIns),
    swapOutsDelta: Math.max(0, samples.at(-1).swapOuts - samples[0].swapOuts),
    swapFreeMinBytes: Math.min(
      ...samples.map(({ swapFreeBytes }) => swapFreeBytes),
    ),
    caddyHealthLatencyP95Ms: percentile(
      samples.map(({ caddyHealthLatencyMs }) => caddyHealthLatencyMs),
      0.95,
    ),
    healthFailures: samples.filter(
      ({ caddyHealthStatus }) => caddyHealthStatus !== 200,
    ).length,
  };
  writeFileSync(summaryPath, `${JSON.stringify(summary, null, 2)}\n`, {
    encoding: "utf8",
    flag: "wx",
    mode: 0o600,
  });
  process.exit(0);
}

function requiredArgument(name) {
  const index = process.argv.indexOf(name);
  const value = index >= 0 ? process.argv[index + 1] : undefined;
  if (!value) throw new Error(`${name} is required`);
  return value;
}

function optionalPositiveInteger(name) {
  const index = process.argv.indexOf(name);
  if (index < 0) return null;
  const value = Number(process.argv[index + 1]);
  if (!Number.isInteger(value) || value <= 0)
    throw new Error(`${name} must be a positive integer`);
  return value;
}

function serviceRssBytes() {
  const pids = new Set();
  for (const port of [4000, 4001, 4100]) {
    const result = spawnSync(
      "lsof",
      ["-nP", `-iTCP:${port}`, "-sTCP:LISTEN", "-t"],
      {
        encoding: "utf8",
      },
    );
    for (const pid of result.stdout?.trim().split(/\s+/u).filter(Boolean) ?? [])
      pids.add(pid);
  }
  if (pids.size === 0) return 0;
  const result = spawnSync("ps", ["-o", "rss=", "-p", [...pids].join(",")], {
    encoding: "utf8",
  });
  return (
    (result.stdout
      ?.trim()
      .split(/\s+/u)
      .reduce((total, value) => total + (Number(value) || 0), 0) ?? 0) * 1024
  );
}

function caddyHealth() {
  const result = spawnSync(
    "curl",
    [
      "-sS",
      "--max-time",
      "3",
      "-o",
      "/dev/null",
      "-w",
      "%{http_code} %{time_total}",
      "http://127.0.0.1:4100/health/ready",
    ],
    { encoding: "utf8" },
  );
  const [status, seconds] = result.stdout?.trim().split(/\s+/u) ?? [];
  return {
    status: result.status === 0 ? Number(status) : 0,
    latencyMs: result.status === 0 ? Number(seconds) * 1000 : 3000,
  };
}

sample();
const interval = setInterval(sample, 1000);
if (durationMs !== null)
  setTimeout(() => {
    clearInterval(interval);
    finalize();
  }, durationMs);
process.on("SIGTERM", () => {
  clearInterval(interval);
  finalize();
});
process.on("SIGINT", () => {
  clearInterval(interval);
  finalize();
});
