import { readHostSample, defaultEvidenceRoot } from "./metrics.mjs";
import { developmentMemoryState } from "./policy.mjs";
import { runGuardedCommand } from "./guard.mjs";

const delay = (milliseconds) =>
  new Promise((resolvePromise) => setTimeout(resolvePromise, milliseconds));

export async function runCli({
  arguments_ = process.argv.slice(2),
  environment = process.env,
  dependencies = {},
} = {}) {
  const [subcommand, ...subcommandArguments] = arguments_;
  const collect = dependencies.collect ?? readHostSample;
  const log = dependencies.log ?? console.log;
  const pause = dependencies.sleep ?? delay;
  const run = dependencies.run ?? runGuardedCommand;
  const setInterval_ = dependencies.setInterval ?? setInterval;
  const clearInterval_ = dependencies.clearInterval ?? clearInterval;
  const signalSource = dependencies.signalSource ?? process;
  const evidenceRoot = defaultEvidenceRoot(environment);

  if (subcommand === "status") {
    const first = collect();
    await pause(1000);
    const sample = collect(first.cpuTimes).sample;
    if (subcommandArguments.includes("--json")) log(JSON.stringify(sample));
    else
      log(
        `state=${developmentMemoryState(sample)} pressure=${sample.memoryPressureLevel} ` +
          `availableEstimateGiB=${(sample.availableNonCompressedEstimateBytes / 1024 ** 3).toFixed(2)} ` +
          `cpu=${sample.cpuUtilizationPercent.toFixed(1)}% compressorAvailable=${sample.compressorAvailable}`,
      );
    return 0;
  }
  if (subcommand === "monitor") {
    let previous = null;
    let priorState = null;
    const observe = () => {
      const reading = collect(previous);
      previous = reading.cpuTimes;
      const state = developmentMemoryState(reading.sample);
      if (state !== priorState) {
        log(`${reading.sample.measuredAt} state=${state}`);
        priorState = state;
      }
    };
    observe();
    const interval = setInterval_(observe, 1000);
    await new Promise((resolvePromise) => {
      for (const signal of ["SIGINT", "SIGTERM"])
        signalSource.once(signal, resolvePromise);
    });
    clearInterval_(interval);
    return 0;
  }
  if (subcommand === "run") {
    const separator = subcommandArguments.indexOf("--");
    const classIndex = subcommandArguments.indexOf("--class");
    const taskClass =
      classIndex >= 0 ? subcommandArguments[classIndex + 1] : "ephemeral";
    if (!new Set(["ephemeral", "service", "transactional"]).has(taskClass))
      throw new Error("--class must be ephemeral, service, or transactional");
    if (separator < 0 || !subcommandArguments[separator + 1])
      throw new Error("run requires -- followed by a command");
    return run({
      command: subcommandArguments[separator + 1],
      arguments_: subcommandArguments.slice(separator + 2),
      environment,
      evidenceRoot,
      taskClass,
    });
  }
  throw new Error("Expected status, monitor, or run");
}
