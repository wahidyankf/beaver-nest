import { spawn, type ChildProcess } from "node:child_process";
import path from "node:path";
import {
  stopChildProcesses,
  terminateChildProcesses,
} from "./process-lifecycle";
import {
  appDirectory,
  candidatePort,
  requiredRevision,
  routedEnvironment,
} from "./routed-rollout-env";

// The `mix phx.server` candidate process pool behind `routed-rollout.ts`'s
// promotions -- split out purely to stay under this project's max-lines
// lint budget. Nothing here is meant to be imported outside that file.

const candidates = new Map<number, ChildProcess>();
const candidateLogs = new Map<number, string>();
const candidateFamilyChatFlags = new Map<number, boolean | undefined>();
const candidateReplyFlags = new Map<number, boolean | undefined>();
process.once("exit", () => terminateChildProcesses(candidates.values()));

export async function ensureCandidate(
  port: number,
  familyChatEnabled?: boolean,
  replyEnabled?: boolean,
): Promise<void> {
  const existing = candidates.get(port);
  if (existing !== undefined && existing.exitCode === null) {
    if (
      candidateFamilyChatFlags.get(port) === familyChatEnabled &&
      candidateReplyFlags.get(port) === replyEnabled
    )
      return;
    // A prior scenario left a candidate running on this port with a
    // different flag state than this call needs -- the flag is only set at
    // boot (`runtime.exs`), so reusing the process would silently keep the
    // stale value.
    await stopChildProcesses([existing]);
    candidates.delete(port);
  }

  const candidate = launchCandidate(port, familyChatEnabled, replyEnabled);
  candidates.set(port, candidate);
  candidateFamilyChatFlags.set(port, familyChatEnabled);
  candidateReplyFlags.set(port, replyEnabled);
  candidate.stdout?.on("data", (chunk: Buffer) =>
    appendCandidateLog(port, chunk),
  );
  candidate.stderr?.on("data", (chunk: Buffer) =>
    appendCandidateLog(port, chunk),
  );
  await waitForCandidate(candidate, port, 100, "no response");
}

export async function stopAllCandidates(): Promise<void> {
  await stopChildProcesses(candidates.values());
  candidates.clear();
  candidateFamilyChatFlags.clear();
  candidateReplyFlags.clear();
}

function launchCandidate(
  port: number,
  familyChatEnabled?: boolean,
  replyEnabled?: boolean,
): ChildProcess {
  const codexRunner = path.join(
    appDirectory,
    "test/support/codex_fixture_runner.mjs",
  );
  const codexModelsRunner = path.join(
    appDirectory,
    "test/support/codex_fixture_models.mjs",
  );
  candidateLogs.set(port, "");
  return spawn("mix", ["phx.server"], {
    cwd: appDirectory,
    env: {
      ...routedEnvironment(),
      ...(familyChatEnabled === undefined
        ? {}
        : {
            BNEST_FAMILY_CHAT_ENABLED: familyChatEnabled ? "true" : "false",
          }),
      // Left unset means "inherit the suite's own true" (see
      // `tools/run-e2e.mts`); pinned false is what makes a candidate a
      // genuine compatibility revision rather than the experience one.
      ...(replyEnabled === undefined
        ? {}
        : {
            BNEST_FAMILY_CHAT_REPLY_ENABLED: replyEnabled ? "true" : "false",
          }),
      BNEST_CODEX_MODELS_RUNNER: codexModelsRunner,
      BNEST_CODEX_RUNNER: codexRunner,
      BNEST_DEPLOY_SLOT: port === candidatePort ? "green" : "yellow",
      BNEST_RELEASE_REVISION: requiredRevision(port),
      PHX_SERVER: "true",
      PORT: String(port),
    },
    stdio: ["ignore", "pipe", "pipe"],
  });
}

async function waitForCandidate(
  candidate: ChildProcess,
  port: number,
  attempts: number,
  lastHealth: string,
): Promise<void> {
  if (candidate.exitCode !== null) {
    throw new Error(
      `candidate exited before readiness:\n${candidateLogs.get(port) ?? ""}`,
    );
  }
  if (attempts === 0) {
    throw new Error(
      `candidate did not become ready (${lastHealth}):\n${candidateLogs.get(port) ?? ""}`,
    );
  }

  let observedHealth = lastHealth;
  try {
    const response = await fetch(`http://127.0.0.1:${port}/health/ready`, {
      signal: AbortSignal.timeout(1_000),
    });
    observedHealth = `${response.status} ${await response.text()}`;
    if (
      response.status === 200 &&
      response.headers.get("x-bnest-revision") === requiredRevision(port)
    ) {
      return;
    }
  } catch (error) {
    observedHealth = String(error);
  }

  await new Promise<void>((resolve) => {
    setTimeout(resolve, 200);
  });
  await waitForCandidate(candidate, port, attempts - 1, observedHealth);
}

function appendCandidateLog(port: number, chunk: Buffer): void {
  candidateLogs.set(
    port,
    ((candidateLogs.get(port) ?? "") + chunk.toString("utf8")).slice(-8_000),
  );
}
