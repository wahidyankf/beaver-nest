#!/usr/bin/env node

import { readHostSample, defaultEvidenceRoot } from "./metrics.mjs";
import { developmentMemoryState } from "./policy.mjs";
import { runGuardedCommand } from "./guard.mjs";

const [subcommand, ...arguments_] = process.argv.slice(2);
const evidenceRoot = defaultEvidenceRoot();

const delay = (milliseconds) =>
  new Promise((resolvePromise) => setTimeout(resolvePromise, milliseconds));

async function sampledStatus() {
  const first = readHostSample();
  await delay(1000);
  return readHostSample(first.cpuTimes).sample;
}

async function main() {
  if (subcommand === "status") {
    const sample = await sampledStatus();
    if (arguments_.includes("--json")) console.log(JSON.stringify(sample));
    else
      console.log(
        `state=${developmentMemoryState(sample)} pressure=${sample.memoryPressureLevel} ` +
          `availableEstimateGiB=${(sample.availableNonCompressedEstimateBytes / 1024 ** 3).toFixed(2)} ` +
          `cpu=${sample.cpuUtilizationPercent.toFixed(1)}% compressorAvailable=${sample.compressorAvailable}`,
      );
    return;
  }
  if (subcommand === "monitor") {
    let previous = null;
    let priorState = null;
    const observe = () => {
      const reading = readHostSample(previous);
      previous = reading.cpuTimes;
      const state = developmentMemoryState(reading.sample);
      if (state !== priorState) {
        console.log(`${reading.sample.measuredAt} state=${state}`);
        priorState = state;
      }
    };
    observe();
    const interval = setInterval(observe, 1000);
    await new Promise((resolvePromise) => {
      for (const signal of ["SIGINT", "SIGTERM"])
        process.once(signal, resolvePromise);
    });
    clearInterval(interval);
    return;
  }
  if (subcommand === "run") {
    const separator = arguments_.indexOf("--");
    const classIndex = arguments_.indexOf("--class");
    const taskClass =
      classIndex >= 0 ? arguments_[classIndex + 1] : "ephemeral";
    if (!new Set(["ephemeral", "service", "transactional"]).has(taskClass))
      throw new Error("--class must be ephemeral, service, or transactional");
    if (separator < 0 || !arguments_[separator + 1])
      throw new Error("run requires -- followed by a command");
    process.exitCode = await runGuardedCommand({
      command: arguments_[separator + 1],
      arguments_: arguments_.slice(separator + 2),
      environment: process.env,
      evidenceRoot,
      taskClass,
    });
    return;
  }
  throw new Error("Expected status, monitor, or run");
}

main().catch((error) => {
  process.stderr.write(`Resource guard failed: ${error.message}\n`);
  process.exitCode = 1;
});
