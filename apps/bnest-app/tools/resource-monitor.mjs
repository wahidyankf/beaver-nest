import { spawnSync } from "node:child_process";
import { appendFileSync, mkdirSync, statfsSync, writeFileSync } from "node:fs";
import { availableParallelism, freemem, loadavg, totalmem } from "node:os";
import { dirname } from "node:path";

const outputPath = requiredArgument("--output");
const summaryPath = requiredArgument("--summary");
const deploymentRoot = requiredArgument("--deployment-root");
const samples = [];

mkdirSync(dirname(outputPath), { recursive: true });
writeFileSync(outputPath, "", { encoding: "utf8", flag: "wx", mode: 0o600 });

function sample() {
  const disk = statfsSync(deploymentRoot);
  const health = caddyHealth();
  const value = {
    schemaVersion: 1,
    measuredAt: new Date().toISOString(),
    availableMemoryBytes: availableMemoryBytes(),
    memoryPressureLevel: memoryPressureLevel(),
    compressorBytes: compressorBytes(),
    physicalMemoryBytes: totalmem(),
    logicalCores: availableParallelism(),
    systemCpuPercent: systemCpuPercent(),
    oneMinuteLoad: loadavg()[0],
    serviceRssBytes: serviceRssBytes(),
    diskFreeBytes: disk.bavail * disk.bsize,
    swapIns: swapIns(),
    caddyHealthStatus: health.status,
    caddyHealthLatencyMs: health.latencyMs,
  };
  samples.push(value);
  appendFileSync(outputPath, `${JSON.stringify(value)}\n`, "utf8");
}

function finalize() {
  if (samples.length === 0) sample();
  const summary = {
    schemaVersion: 1,
    sampleCount: samples.length,
    logicalCores: samples[0].logicalCores,
    availableMemoryMinBytes: Math.min(
      ...samples.map(({ availableMemoryBytes }) => availableMemoryBytes),
    ),
    memoryPressureLevelMax: Math.max(
      ...samples.map(({ memoryPressureLevel }) => memoryPressureLevel),
    ),
    compressorBytesPeak: Math.max(
      ...samples.map(({ compressorBytes }) => compressorBytes),
    ),
    physicalMemoryBytes: samples[0].physicalMemoryBytes,
    systemCpuP95Percent: percentile(
      samples.map(({ systemCpuPercent }) => systemCpuPercent),
      0.95,
    ),
    serviceRssPeakBytes: Math.max(
      ...samples.map(({ serviceRssBytes }) => serviceRssBytes),
    ),
    diskFreeMinBytes: Math.min(
      ...samples.map(({ diskFreeBytes }) => diskFreeBytes),
    ),
    swapInsDelta: Math.max(0, samples.at(-1).swapIns - samples[0].swapIns),
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

function availableMemoryBytes() {
  if (process.platform !== "darwin") return freemem();
  const result = spawnSync("memory_pressure", ["-Q"], { encoding: "utf8" });
  const matched = result.stdout?.match(/free percentage:\s*(\d+)%/u);
  return matched ? (totalmem() * Number(matched[1])) / 100 : freemem();
}

function memoryPressureLevel() {
  if (process.platform !== "darwin") return 1;
  return darwinSysctlNumber("kern.memorystatus_vm_pressure_level", 4);
}

function compressorBytes() {
  if (process.platform !== "darwin") return 0;
  return darwinSysctlNumber("vm.compressor_bytes_used", totalmem());
}

function darwinSysctlNumber(name, fallback) {
  const result = spawnSync("sysctl", ["-n", name], { encoding: "utf8" });
  const value = Number(result.stdout?.trim());
  return result.status === 0 && Number.isFinite(value) ? value : fallback;
}

function systemCpuPercent() {
  const result = spawnSync("ps", ["-A", "-o", "%cpu="], { encoding: "utf8" });
  if (result.status !== 0) return 0;
  return result.stdout
    .trim()
    .split(/\s+/u)
    .reduce((total, value) => total + (Number(value) || 0), 0);
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

function swapIns() {
  if (process.platform !== "darwin") return 0;
  const result = spawnSync("vm_stat", [], { encoding: "utf8" });
  return Number(result.stdout?.match(/Swapins:\s+(\d+)\./u)?.[1] ?? 0);
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

function percentile(values, proportion) {
  const sorted = values.toSorted((left, right) => left - right);
  return sorted[Math.max(0, Math.ceil(sorted.length * proportion) - 1)] ?? 0;
}

sample();
const interval = setInterval(sample, 1000);
process.on("SIGTERM", () => {
  clearInterval(interval);
  finalize();
});
process.on("SIGINT", () => {
  clearInterval(interval);
  finalize();
});
