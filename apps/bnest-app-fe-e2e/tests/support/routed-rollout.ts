import { spawnSync } from "node:child_process";
import { expect, type Page } from "@playwright/test";
import { ensureCandidate, stopAllCandidates } from "./candidate-pool";
import {
  adminPort,
  appDirectory,
  caddyBinary,
  candidatePort,
  primaryPort,
  publicPort,
  requiredRevision,
  routedEnvironment,
  runId,
  runtimeRoot,
} from "./routed-rollout-env";
import {
  captureStorageAuthority,
  restoreStorageAuthority,
} from "./storage-authority";

let routedPort = primaryPort;
let storageActivated = false;

/**
 * Same rollout mechanics as `promoteCompatibleCandidate`, but pins the
 * target candidate's `BNEST_FAMILY_CHAT_ENABLED` explicitly instead of
 * leaving it unset (which resolves to `config/test.exs`'s unconditional
 * `true`) -- tech-doc 009's Experience Release Procedure needs a genuine
 * flag-on candidate promotion distinct from the shared compatibility
 * candidates, which an unset flag cannot express. Never reused for the
 * shared compatibility scenarios; those keep calling
 * `promoteCompatibleCandidate` unmodified.
 */
export async function promoteCandidateWithFlag(
  page: Page,
  familyChatEnabled: boolean,
): Promise<{
  previousRevision: string;
  revision: string;
}> {
  ensureLiveSqlite();
  const targetPort =
    routedPort === candidatePort ? candidatePort + 1 : candidatePort;
  await ensureCandidate(targetPort, familyChatEnabled);
  const previousRevision = requiredRevision(routedPort);
  const revision = requiredRevision(targetPort);
  await reloadRoute(page, targetPort, false);

  return { previousRevision, revision };
}

/**
 * Promotes a candidate whose `BNEST_FAMILY_CHAT_REPLY_ENABLED` is pinned,
 * which is what a compatibility revision is: the reviewed build, routed with
 * the feature off. `promoteCandidateWithFlag` above pins the room's own flag
 * instead; the two are independent, and the compatibility release turns
 * exactly one of them off.
 */
export async function promoteCandidateWithReplyFlag(
  page: Page,
  replyEnabled: boolean,
): Promise<{ previousRevision: string; revision: string }> {
  ensureLiveSqlite();
  const targetPort =
    routedPort === candidatePort ? candidatePort + 1 : candidatePort;
  await ensureCandidate(targetPort, undefined, replyEnabled);
  const previousRevision = requiredRevision(routedPort);
  const revision = requiredRevision(targetPort);
  await reloadRoute(page, targetPort, false);

  return { previousRevision, revision };
}

export async function promoteCompatibleCandidate(
  page: Page,
  // `verifyLiveView` defaults to true (unchanged behavior for every existing
  // LiveView-routed caller). The family chat room is a plain Phoenix
  // controller, never a LiveView (tech-doc 005), so its own caller passes
  // `false` and proves reconnect through its own real readiness signal
  // instead (see `family-chat.steps.ts`'s "the prior-slot socket closes").
  options: { verifyLiveView?: boolean } = {},
): Promise<{
  previousRevision: string;
  revision: string;
}> {
  ensureLiveSqlite();
  const targetPort =
    routedPort === candidatePort ? candidatePort + 1 : candidatePort;
  await ensureCandidate(targetPort);
  const previousRevision = requiredRevision(routedPort);
  const revision = requiredRevision(targetPort);
  await reloadRoute(page, targetPort, options.verifyLiveView ?? true);

  return { previousRevision, revision };
}

export async function restorePrimaryRoute(page: Page): Promise<void> {
  if (routedPort !== primaryPort) {
    await reloadRoute(page, primaryPort, false);
  }
  if (storageActivated) {
    // A candidate can still flush SQLite after SIGTERM. Do not restore the
    // captured authority until every task-owned process has actually exited.
    await stopAllCandidates();
    storageActivated = false;
  }
  restoreStorageAuthority();
}

async function reloadRoute(
  page: Page,
  targetPort: number,
  verifyLiveView: boolean,
): Promise<void> {
  const revision = requiredRevision(targetPort);
  const result = spawnSync(
    caddyBinary,
    [
      "reload",
      "--config",
      "-",
      "--adapter",
      "caddyfile",
      "--address",
      `127.0.0.1:${adminPort}`,
    ],
    {
      input: caddyfile(publicPort, targetPort, adminPort),
      encoding: "utf8",
    },
  );

  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(`Caddy route reload failed: ${result.stderr}`);
  }

  routedPort = targetPort;
  await expect
    .poll(async () => {
      const response = await page.request.get("/health/ready");
      return response.status() === 200
        ? response.headers()["x-bnest-revision"]
        : undefined;
    })
    .toBe(revision);
  if (verifyLiveView) {
    await expect(page.locator("[data-phx-main]")).toHaveClass(/phx-connected/u);
  }
}

export function ensureLiveSqlite(): void {
  if (storageActivated) return;
  if (runtimeRoot === "" || runId === "") {
    throw new Error("routed rollout requires the marked E2E runtime");
  }
  captureStorageAuthority();

  const result = spawnSync(
    "mix",
    ["bnest.storage.migrate", "--root", runtimeRoot, "--activate"],
    { cwd: appDirectory, env: routedEnvironment(), encoding: "utf8" },
  );
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(`routed SQLite activation failed: ${result.stderr}`);
  }

  const schedules = spawnSync(
    "mix",
    [
      "run",
      "-e",
      "BnestApp.Release.Migrations.PersistentSchedules.apply_and_verify!(DateTime.utc_now())",
    ],
    { cwd: appDirectory, env: routedEnvironment(), encoding: "utf8" },
  );
  if (schedules.error) throw schedules.error;
  if (schedules.status !== 0) {
    throw new Error(`routed schedule migration failed: ${schedules.stderr}`);
  }
  storageActivated = true;
}

export function runLiveMix(expression: string): {
  status: number;
  stderr: string;
  stdout: string;
} {
  const result = spawnSync("mix", ["run", "-e", expression], {
    cwd: appDirectory,
    env: routedEnvironment(),
    encoding: "utf8",
  });
  if (result.error) throw result.error;
  return {
    status: result.status ?? 1,
    stderr: result.stderr ?? "",
    stdout: result.stdout ?? "",
  };
}

function caddyfile(
  listenerPort: number,
  upstreamPort: number,
  controlPort: number,
): string {
  return `{
  admin 127.0.0.1:${controlPort}
  auto_https off
}

http://127.0.0.1:${listenerPort}, http://localhost:${listenerPort} {
  reverse_proxy 127.0.0.1:${upstreamPort}
}
`;
}
