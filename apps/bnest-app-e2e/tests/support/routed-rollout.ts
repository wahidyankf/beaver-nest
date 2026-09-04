import { spawn, spawnSync, type ChildProcess } from "node:child_process";
import path from "node:path";
import { expect, type Page } from "@playwright/test";
import {
  stopChildProcesses,
  terminateChildProcesses,
} from "./process-lifecycle";
import {
  captureStorageAuthority,
  restoreStorageAuthority,
  routedStorageConfigPath,
} from "./storage-authority";

const repositoryRoot = process.cwd();
const appDirectory = path.join(repositoryRoot, "apps/bnest-app");
const runtimeRoot = process.env["BNEST_E2E_RUNTIME_ROOT"] ?? "";
const runId = process.env["BNEST_E2E_RUN_ID"] ?? "";
const publicPort = optionalPort("BNEST_E2E_PORT", 4010);
const primaryPort = optionalPort("BNEST_E2E_BACKEND_PORT", publicPort + 100);
const candidatePort = primaryPort + 1;
const adminPort = optionalPort("BNEST_E2E_CADDY_ADMIN_PORT", publicPort + 200);
const caddyBinary = process.env["BNEST_E2E_CADDY_BIN"] ?? "caddy";
const revisions = new Map<number, string>([
  [primaryPort, "e2e-blue"],
  [candidatePort, "e2e-green"],
  [candidatePort + 1, "e2e-yellow"],
]);

const candidates = new Map<number, ChildProcess>();
const candidateLogs = new Map<number, string>();
let routedPort = primaryPort;
let storageActivated = false;
process.once("exit", () => terminateChildProcesses(candidates.values()));

export async function promoteCompatibleCandidate(page: Page): Promise<{
  previousRevision: string;
  revision: string;
}> {
  ensureLiveSqlite();
  const targetPort =
    routedPort === candidatePort ? candidatePort + 1 : candidatePort;
  await ensureCandidate(targetPort);
  const previousRevision = requiredRevision(routedPort);
  const revision = requiredRevision(targetPort);
  await reloadRoute(page, targetPort, true);

  return { previousRevision, revision };
}

export async function restorePrimaryRoute(page: Page): Promise<void> {
  if (routedPort !== primaryPort) {
    await reloadRoute(page, primaryPort, false);
  }
  if (storageActivated) {
    // A candidate can still flush SQLite after SIGTERM. Do not restore the
    // captured authority until every task-owned process has actually exited.
    await stopChildProcesses(candidates.values());
    candidates.clear();
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

async function ensureCandidate(port: number): Promise<void> {
  const existing = candidates.get(port);
  if (existing !== undefined && existing.exitCode === null) return;

  const candidate = launchCandidate(port);
  candidates.set(port, candidate);
  candidate.stdout?.on("data", (chunk: Buffer) =>
    appendCandidateLog(port, chunk),
  );
  candidate.stderr?.on("data", (chunk: Buffer) =>
    appendCandidateLog(port, chunk),
  );
  await waitForCandidate(candidate, port, 100, "no response");
}

function launchCandidate(port: number): ChildProcess {
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

function routedEnvironment(): NodeJS.ProcessEnv {
  return {
    ...process.env,
    BNEST_BACKUP_CONFIG: path.join(
      runtimeRoot,
      "storage-config",
      "backup.json",
    ),
    BNEST_RUNTIME_ROOT: runtimeRoot,
    BNEST_STORAGE_CONFIG: routedStorageConfigPath(),
    BNEST_TEST_LAYER: "integration",
    BNEST_TEST_RUN_ID: runId,
    MIX_ENV: "test",
  };
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

function appendCandidateLog(port: number, chunk: Buffer): void {
  candidateLogs.set(
    port,
    ((candidateLogs.get(port) ?? "") + chunk.toString("utf8")).slice(-8_000),
  );
}

function optionalPort(name: string, fallback: number): number {
  const value = Number(process.env[name] ?? fallback);
  if (!Number.isInteger(value) || value < 1 || value > 65_535) {
    throw new Error(`${name} must be a valid TCP port`);
  }
  return value;
}

function requiredRevision(port: number): string {
  const revision = revisions.get(port);
  if (revision === undefined) throw new Error(`unknown rollout port ${port}`);
  return revision;
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
  reverse_proxy 127.0.0.1:${upstreamPort} {
    stream_close_delay 1s
  }
}
`;
}
