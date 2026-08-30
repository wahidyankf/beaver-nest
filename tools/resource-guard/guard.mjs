import { spawn } from "node:child_process";

import {
  cleanupEvidence,
  EvidenceWriter,
  evidenceIdentifier,
} from "./evidence.mjs";
import { readHostSample } from "./metrics.mjs";
import {
  admissionReady,
  developmentPolicy,
  developmentResourceAssessment,
} from "./policy.mjs";

export const storageBlockedExitCode = 73;
import { acquireSession, releaseSession } from "./session.mjs";

const sleep = (milliseconds) =>
  new Promise((resolvePromise) => setTimeout(resolvePromise, milliseconds));

function signalProcessGroup(child, signal) {
  if (!child.pid) return;
  try {
    process.kill(-child.pid, signal);
  } catch {
    child.kill(signal);
  }
}

function signalExitCode(signal) {
  return { SIGINT: 130, SIGTERM: 143 }[signal] ?? 128;
}

async function collectAdmission(writer, options) {
  const deadline = options.now() + options.policy.admissionWindowMs;
  let previousCpuTimes = null;
  const samples = [];
  while (options.now() <= deadline) {
    const reading = options.collect(previousCpuTimes);
    previousCpuTimes = reading.cpuTimes;
    writer.append(reading.sample);
    samples.push(reading.sample);
    const resource = developmentResourceAssessment(samples, options.policy);
    if (resource.storageBlocked)
      return { admitted: false, previousCpuTimes, resource, samples };
    if (admissionReady(samples, options.policy))
      return { admitted: true, previousCpuTimes, resource, samples };
    await options.sleep(1000);
  }
  return { admitted: false, previousCpuTimes, samples };
}

export async function runGuardedCommand({
  arguments_,
  command,
  environment = process.env,
  evidenceRoot,
  taskClass = "ephemeral",
  dependencies = {},
}) {
  const sampleHost = dependencies.readHostSample ?? readHostSample;
  const collect =
    dependencies.collect ??
    ((previous) =>
      sampleHost(previous, {
        diskPath: dependencies.diskPath ?? process.cwd(),
      }));
  const pause = dependencies.sleep ?? sleep;
  const now = dependencies.now ?? Date.now;
  const policy = { ...developmentPolicy, ...dependencies.policy };
  const spawnChild = dependencies.spawn ?? spawn;
  const setInterval_ = dependencies.setInterval ?? setInterval;
  const clearInterval_ = dependencies.clearInterval ?? clearInterval;
  const setTimeout_ = dependencies.setTimeout ?? setTimeout;
  const clearTimeout_ = dependencies.clearTimeout ?? clearTimeout;
  const signalSource = dependencies.signalSource ?? process;
  cleanupEvidence(evidenceRoot);
  const session = await acquireSession(evidenceRoot, {
    token: environment.BNEST_RESOURCE_SESSION,
    waitMs: policy.leaseWaitMs,
    sleep: pause,
  });
  if (!session) return 75;
  if (session.inherited) {
    const child = spawnChild(command, arguments_, {
      env: environment,
      stdio: "inherit",
    });
    return await new Promise((resolvePromise, rejectPromise) => {
      child.once("error", rejectPromise);
      child.once("exit", (code, signal) =>
        resolvePromise(signal ? 128 : (code ?? 1)),
      );
    });
  }

  const writer = new EvidenceWriter(
    evidenceRoot,
    evidenceIdentifier(`development-${taskClass}`),
  );
  let outcome = "capacity-deferred";
  try {
    const admission = await collectAdmission(writer, {
      collect,
      now,
      policy,
      sleep: pause,
    });
    if (!admission.admitted) {
      if (admission.resource?.storageBlocked) {
        outcome = "storage-blocked";
        process.stderr.write(
          `Resource guard blocked task: ${admission.resource.reason}; storage inspection or cleanup is required.\n`,
        );
        writer.finalize({ taskClass, outcome });
        return storageBlockedExitCode;
      }
      process.stderr.write(
        "Resource guard deferred task: safe admission was not reached.\n",
      );
      writer.finalize({ taskClass, outcome });
      return 75;
    }

    const child = spawnChild(command, arguments_, {
      detached: process.platform !== "win32",
      env: { ...environment, BNEST_RESOURCE_SESSION: session.token },
      stdio: "inherit",
    });
    let previousCpuTimes = admission.previousCpuTimes;
    let samples = admission.samples;
    let warningSince = null;
    let shed = false;
    let shedExitCode = 75;
    let forceTimer = null;
    let forwardedSignal = null;
    const observe = () => {
      const reading = collect(previousCpuTimes);
      previousCpuTimes = reading.cpuTimes;
      writer.append(reading.sample);
      samples.push(reading.sample);
      const sampleLimit =
        Math.ceil(policy.trendWindowMs / (policy.sampleIntervalMs ?? 1000)) + 2;
      samples = samples.slice(-sampleLimit);
      const resource = developmentResourceAssessment(samples, policy);
      const { state } = resource;
      if (state === "normal") warningSince = null;
      else if (state === "warning") warningSince ??= now();
      if (taskClass === "transactional" || shed) return;
      const warningGrace =
        taskClass === "service"
          ? policy.serviceWarningGraceMs
          : policy.ephemeralWarningGraceMs;
      if (
        state === "critical" ||
        (warningSince !== null && now() - warningSince >= warningGrace)
      ) {
        shed = true;
        shedExitCode = resource.storageBlocked ? storageBlockedExitCode : 75;
        outcome = resource.storageBlocked ? "storage-shed" : "pressure-shed";
        process.stderr.write(
          `Resource guard shedding ${taskClass} child after ${resource.reason}.\n`,
        );
        signalProcessGroup(child, "SIGTERM");
        forceTimer = setTimeout_(
          () => signalProcessGroup(child, "SIGKILL"),
          policy.terminationGraceMs,
        );
      }
    };
    const interval = setInterval_(observe, policy.sampleIntervalMs ?? 1000);
    const forwardSignal = (signal) => {
      forwardedSignal ??= signal;
      signalProcessGroup(child, signal);
    };
    const signalHandlers = new Map(
      ["SIGINT", "SIGTERM"].map((signal) => [
        signal,
        () => forwardSignal(signal),
      ]),
    );
    for (const [signal, handler] of signalHandlers)
      signalSource.once(signal, handler);
    let exit;
    try {
      exit = await new Promise((resolvePromise, rejectPromise) => {
        child.once("error", rejectPromise);
        child.once("exit", (code, signal) => resolvePromise({ code, signal }));
      });
    } finally {
      clearInterval_(interval);
      if (forceTimer) clearTimeout_(forceTimer);
      for (const [signal, handler] of signalHandlers)
        signalSource.off(signal, handler);
    }
    if (!shed) outcome = exit.code === 0 ? "passed" : "task-failed";
    writer.finalize({ taskClass, outcome });
    cleanupEvidence(evidenceRoot);
    return shed
      ? shedExitCode
      : (exit.code ?? signalExitCode(exit.signal ?? forwardedSignal));
  } finally {
    releaseSession(evidenceRoot, session);
  }
}
