import { gibibyte } from "./metrics.mjs";

export const developmentPolicy = Object.freeze({
  admissionMemoryBytes: 9 * gibibyte,
  criticalMemoryBytes: 4 * gibibyte,
  reservedCpuUnits: 2,
  consecutiveCpuSamples: 3,
  admissionWindowMs: 15_000,
  ephemeralWarningGraceMs: 10_000,
  serviceWarningGraceMs: 30_000,
  terminationGraceMs: 10_000,
  leaseWaitMs: 300_000,
});

export function essentialReadingsValid(sample) {
  return (
    Number.isFinite(sample.availableNonCompressedEstimateBytes) &&
    [1, 2, 4].includes(sample.memoryPressureLevel) &&
    typeof sample.compressorAvailable === "boolean" &&
    Number.isInteger(sample.availableParallelism) &&
    sample.availableParallelism > 0
  );
}

export function developmentMemoryState(sample) {
  if (!essentialReadingsValid(sample)) return "critical";
  if (
    sample.memoryPressureLevel === 4 ||
    !sample.compressorAvailable ||
    sample.availableNonCompressedEstimateBytes <
      developmentPolicy.criticalMemoryBytes
  )
    return "critical";
  if (
    sample.memoryPressureLevel === 2 ||
    sample.availableNonCompressedEstimateBytes <
      developmentPolicy.admissionMemoryBytes
  )
    return "warning";
  return "normal";
}

export function cpuAdmissionReady(sample) {
  const ceiling =
    100 *
    (1 -
      Math.min(
        developmentPolicy.reservedCpuUnits,
        sample.availableParallelism,
      ) /
        sample.availableParallelism);
  return (
    Number.isFinite(sample.cpuUtilizationPercent) &&
    sample.cpuUtilizationPercent <= ceiling
  );
}

export function admissionReady(samples) {
  const tail = samples.slice(-developmentPolicy.consecutiveCpuSamples);
  return (
    tail.length === developmentPolicy.consecutiveCpuSamples &&
    tail.every(
      (sample) =>
        developmentMemoryState(sample) === "normal" &&
        cpuAdmissionReady(sample),
    )
  );
}

export function percentile(values, proportion) {
  const finite = values
    .filter(Number.isFinite)
    .toSorted((left, right) => left - right);
  return finite[Math.max(0, Math.ceil(finite.length * proportion) - 1)] ?? null;
}

export function releaseResourceHeadroomAvailable(summary) {
  const swapPressure =
    (summary.swapInsDelta > 0 || summary.swapOutsDelta > 0) &&
    summary.availableNonCompressedEstimateMinBytes < 4 * gibibyte;
  return (
    summary.availableNonCompressedEstimateMinBytes >= 2 * gibibyte &&
    summary.memoryPressureLevelMax === 1 &&
    summary.compressorAvailableAll === true &&
    !swapPressure &&
    summary.cpuUtilizationP95Percent <=
      100 * (1 - 2 / summary.availableParallelism) &&
    summary.healthFailures === 0
  );
}
