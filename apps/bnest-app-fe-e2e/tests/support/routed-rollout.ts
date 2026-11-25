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
} from "./routed-rollout-env";

// The storage of a scenario is its test instance (`active-instance.ts`), spawned before the scenario and
// deleted after it. Nothing here captures, restores or migrates storage.
let routedPort = primaryPort;

export async function promoteCompatibleCandidate(
  page: Page,
  // `verifyLiveView` defaults to true (unchanged behavior for every existing
  // LiveView-routed caller). The family chat room is a plain Phoenix
  // controller, never a LiveView (tech-doc 005), so its own caller passes
  // `false` and proves reconnect through its own real readiness signal
  // instead (see `family-chat.steps.ts`'s "the room reconnects").
  options: { verifyLiveView?: boolean } = {},
): Promise<{
  previousPort: number;
  previousRevision: string;
  revision: string;
}> {
  const targetPort =
    routedPort === candidatePort ? candidatePort + 1 : candidatePort;
  await ensureCandidate(targetPort);
  const previousPort = routedPort;
  const previousRevision = requiredRevision(routedPort);
  const revision = requiredRevision(targetPort);
  await reloadRoute(page, targetPort, options.verifyLiveView ?? true);

  return { previousPort, previousRevision, revision };
}

// Routes the browser back to the primary server. It uses the page, so it runs before the browser contexts
// close. The candidates are stopped separately, after the contexts are gone.
export async function restorePrimaryRoute(page: Page): Promise<void> {
  if (routedPort !== primaryPort) {
    await reloadRoute(page, primaryPort, false);
  }
}

// A candidate can still flush SQLite after SIGTERM, so the scenario's After hook waits for every candidate
// to exit before it deletes the instance that candidate was using.
export async function stopRoutedCandidates(): Promise<void> {
  await stopAllCandidates();
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
