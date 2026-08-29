import { spawnSync } from "node:child_process";
import { statfsSync } from "node:fs";
import { availableParallelism, cpus, homedir, totalmem } from "node:os";
import { join } from "node:path";

export const gibibyte = 1024 ** 3;

export function parseAvailableNonCompressedEstimate(output, physicalBytes) {
  const match = output.match(/free percentage:\s*(\d+)%/u);
  if (!match) return null;
  const percentage = Number(match[1]);
  if (!Number.isFinite(percentage) || percentage < 0 || percentage > 100)
    return null;
  return (physicalBytes * percentage) / 100;
}

export function parseVmStat(output) {
  const pageSize = Number(output.match(/page size of (\d+) bytes/u)?.[1]);
  const value = (label) =>
    Number(output.match(new RegExp(`${label}:\\s+(\\d+)\\.`, "u"))?.[1]);
  const result = {
    pageSizeBytes: pageSize,
    compressorStoredPages: value("Pages stored in compressor"),
    compressorOccupiedPages: value("Pages occupied by compressor"),
    swapIns: value("Swapins"),
    swapOuts: value("Swapouts"),
  };
  return Object.values(result).every(Number.isFinite) ? result : null;
}

export function parseSwapUsage(output) {
  const match = output.match(
    /total = ([\d.]+)M\s+used = ([\d.]+)M\s+free = ([\d.]+)M/u,
  );
  if (!match) return null;
  const [totalMiB, usedMiB, freeMiB] = match.slice(1).map(Number);
  if (![totalMiB, usedMiB, freeMiB].every(Number.isFinite)) return null;
  return {
    swapTotalBytes: totalMiB * 1024 ** 2,
    swapUsedBytes: usedMiB * 1024 ** 2,
    swapFreeBytes: freeMiB * 1024 ** 2,
  };
}

export function cpuUtilizationPercent(previous, current) {
  if (!Array.isArray(previous) || previous.length !== current.length)
    return null;
  let idleDelta = 0;
  let totalDelta = 0;
  for (let index = 0; index < current.length; index += 1) {
    const before = previous[index];
    const after = current[index];
    for (const key of ["user", "nice", "sys", "idle", "irq"]) {
      const delta = after[key] - before[key];
      if (!Number.isFinite(delta) || delta < 0) return null;
      totalDelta += delta;
      if (key === "idle") idleDelta += delta;
    }
  }
  if (totalDelta <= 0) return null;
  return ((totalDelta - idleDelta) / totalDelta) * 100;
}

function command(command, arguments_, dependencies) {
  return dependencies.spawnSync(command, arguments_, { encoding: "utf8" });
}

function sysctlNumber(name, dependencies) {
  const result = command("sysctl", ["-n", name], dependencies);
  const value = Number(result.stdout?.trim());
  return result.status === 0 && Number.isFinite(value) ? value : null;
}

export function defaultEvidenceRoot(environment = process.env) {
  return (
    environment.BNEST_RESOURCE_ROOT ??
    join(homedir(), "bnest", "runtime", "resource-guard")
  );
}

export function readHostSample(previousCpuTimes = null, options = {}) {
  const dependencies = {
    availableParallelism,
    cpus,
    now: () => new Date(),
    spawnSync,
    totalmem,
    ...options.dependencies,
  };
  const physicalMemoryBytes = dependencies.totalmem();
  const currentCpuTimes = dependencies
    .cpus()
    .map(({ times }) => ({ ...times }));
  const pressure = command("memory_pressure", ["-Q"], dependencies);
  const vmStat = command("vm_stat", [], dependencies);
  const swapUsage = command("sysctl", ["-n", "vm.swapusage"], dependencies);
  const pressureLevel = sysctlNumber(
    "kern.memorystatus_vm_pressure_level",
    dependencies,
  );
  const compressorAvailable = sysctlNumber(
    "vm.compressor_available",
    dependencies,
  );
  const compressorPayloadBytes = sysctlNumber(
    "vm.compressor_bytes_used",
    dependencies,
  );
  const parsedVm =
    vmStat.status === 0 ? parseVmStat(vmStat.stdout ?? "") : null;
  const parsedSwap =
    swapUsage.status === 0 ? parseSwapUsage(swapUsage.stdout ?? "") : null;
  let diskFreeBytes = null;
  if (options.diskPath) {
    try {
      const disk = statfsSync(options.diskPath);
      diskFreeBytes = disk.bavail * disk.bsize;
    } catch {
      diskFreeBytes = null;
    }
  }
  const availableNonCompressedEstimateBytes =
    pressure.status === 0
      ? parseAvailableNonCompressedEstimate(
          pressure.stdout ?? "",
          physicalMemoryBytes,
        )
      : null;
  return {
    cpuTimes: currentCpuTimes,
    sample: {
      schemaVersion: 2,
      measuredAt: dependencies.now().toISOString(),
      availableNonCompressedEstimateBytes,
      memoryPressureLevel: pressureLevel,
      compressorAvailable:
        compressorAvailable === 1
          ? true
          : compressorAvailable === 0
            ? false
            : null,
      compressorPayloadBytes,
      physicalMemoryBytes,
      availableParallelism: dependencies.availableParallelism(),
      cpuUtilizationPercent: cpuUtilizationPercent(
        previousCpuTimes,
        currentCpuTimes,
      ),
      diskFreeBytes,
      ...(parsedVm ?? {
        pageSizeBytes: null,
        compressorStoredPages: null,
        compressorOccupiedPages: null,
        swapIns: null,
        swapOuts: null,
      }),
      ...(parsedSwap ?? {
        swapTotalBytes: null,
        swapUsedBytes: null,
        swapFreeBytes: null,
      }),
    },
  };
}
