import { gibibyte } from "./metrics.mjs";

const mebibyte = 1024 ** 2;

export const developmentPolicy = Object.freeze({
  admissionMemoryBytes: 9 * gibibyte,
  criticalMemoryBytes: 4 * gibibyte,
  diskWarningBytes: 30 * gibibyte,
  diskCriticalBytes: 20 * gibibyte,
  trendWindowMs: 15_000,
  swapOutWarningBytes: 128 * mebibyte,
  swapOutCriticalBytes: 512 * mebibyte,
  compressorWarningPayloadBytes: 12 * gibibyte,
  compressorWarningGrowthBytes: 1 * gibibyte,
  compressorCriticalPayloadBytes: 16 * gibibyte,
  compressorCriticalGrowthBytes: 2 * gibibyte,
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
    Number.isFinite(sample.compressorPayloadBytes) &&
    Number.isFinite(Date.parse(sample.measuredAt)) &&
    Number.isInteger(sample.pageSizeBytes) &&
    sample.pageSizeBytes > 0 &&
    Number.isFinite(sample.swapOuts) &&
    Number.isInteger(sample.availableParallelism) &&
    sample.availableParallelism > 0
  );
}

export function developmentMemoryState(sample, policy = developmentPolicy) {
  if (!essentialReadingsValid(sample)) return "critical";
  if (
    sample.memoryPressureLevel === 4 ||
    !sample.compressorAvailable ||
    sample.availableNonCompressedEstimateBytes < policy.criticalMemoryBytes
  )
    return "critical";
  if (
    sample.memoryPressureLevel === 2 ||
    sample.availableNonCompressedEstimateBytes < policy.admissionMemoryBytes
  )
    return "warning";
  return "normal";
}

export function cpuAdmissionReady(sample, policy = developmentPolicy) {
  const ceiling =
    100 *
    (1 -
      Math.min(policy.reservedCpuUnits, sample.availableParallelism) /
        sample.availableParallelism);
  return (
    Number.isFinite(sample.cpuUtilizationPercent) &&
    sample.cpuUtilizationPercent <= ceiling
  );
}

function scaledWindowDelta(samples, field, multiplier, policy) {
  const current = samples.at(-1);
  const currentTime = Date.parse(current?.measuredAt);
  if (!current || !Number.isFinite(currentTime)) return 0;
  const start = samples
    .slice(0, -1)
    .map((sample) => ({ sample, time: Date.parse(sample.measuredAt) }))
    .filter(
      ({ time }) =>
        Number.isFinite(time) &&
        currentTime > time &&
        currentTime - time <= policy.trendWindowMs,
    )
    .at(0);
  if (!start) return 0;
  const delta = current[field] - start.sample[field];
  if (!Number.isFinite(delta) || delta <= 0) return 0;
  return (
    (delta * multiplier * policy.trendWindowMs) / (currentTime - start.time)
  );
}

function assessment(state, reason, storageBlocked, signals) {
  return { ...signals, reason, state, storageBlocked };
}

export function developmentResourceAssessment(
  samples,
  policy = developmentPolicy,
) {
  const current = samples.at(-1);
  const pageSizeBytes = Number.isFinite(current?.pageSizeBytes)
    ? current.pageSizeBytes
    : 0;
  const signals = {
    compressorGrowthWindowBytes: scaledWindowDelta(
      samples,
      "compressorPayloadBytes",
      1,
      policy,
    ),
    swapOutWindowBytes: scaledWindowDelta(
      samples,
      "swapOuts",
      pageSizeBytes,
      policy,
    ),
  };
  if (!Number.isFinite(current?.diskFreeBytes))
    return assessment("critical", "disk-unavailable", true, signals);

  const storageBlocked = current.diskFreeBytes < policy.diskWarningBytes;
  const candidates = [];
  if (current.diskFreeBytes < policy.diskCriticalBytes)
    candidates.push({ reason: "disk-critical", state: "critical" });
  else if (storageBlocked)
    candidates.push({ reason: "disk-warning", state: "warning" });

  const memoryState = developmentMemoryState(current, policy);
  if (memoryState !== "normal")
    candidates.push({
      reason: `memory-${memoryState}`,
      state: memoryState,
    });
  if (signals.swapOutWindowBytes >= policy.swapOutCriticalBytes)
    candidates.push({ reason: "swap-critical", state: "critical" });
  else if (signals.swapOutWindowBytes >= policy.swapOutWarningBytes)
    candidates.push({ reason: "swap-warning", state: "warning" });

  const compressorPayloadBytes = current.compressorPayloadBytes;
  if (
    compressorPayloadBytes >= policy.compressorCriticalPayloadBytes &&
    signals.compressorGrowthWindowBytes >= policy.compressorCriticalGrowthBytes
  )
    candidates.push({ reason: "compressor-critical", state: "critical" });
  else if (
    compressorPayloadBytes >= policy.compressorWarningPayloadBytes &&
    signals.compressorGrowthWindowBytes >= policy.compressorWarningGrowthBytes
  )
    candidates.push({ reason: "compressor-warning", state: "warning" });

  const winner = candidates.toSorted(
    (left, right) =>
      ({ normal: 0, warning: 1, critical: 2 })[right.state] -
      { normal: 0, warning: 1, critical: 2 }[left.state],
  )[0] ?? { reason: "normal", state: "normal" };
  return assessment(winner.state, winner.reason, storageBlocked, signals);
}

export function admissionReady(samples, policy = developmentPolicy) {
  const tail = samples.slice(-policy.consecutiveCpuSamples);
  return (
    developmentResourceAssessment(samples, policy).state === "normal" &&
    tail.length === policy.consecutiveCpuSamples &&
    tail.every((sample) => cpuAdmissionReady(sample, policy))
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
