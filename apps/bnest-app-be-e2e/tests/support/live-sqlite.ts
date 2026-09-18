import { spawnSync } from "node:child_process";
import path from "node:path";
import {
  captureStorageAuthority,
  routedStorageConfigPath,
} from "./storage-authority";

// This project has no Caddy candidate/rollout apparatus (see project.json /
// playwright.config.mts): it drives the shared webServer's live SQLite
// authority directly. Trimmed from bnest-app-e2e's routed-rollout.ts, which
// also owns Caddy blue/green candidate promotion that only bnest-app-fe-e2e
// still exercises.
const repositoryRoot = process.cwd();
const appDirectory = path.join(repositoryRoot, "apps/bnest-app");
const runtimeRoot = process.env["BNEST_E2E_RUNTIME_ROOT"] ?? "";
const runId = process.env["BNEST_E2E_RUN_ID"] ?? "";
let storageActivated = false;

function liveEnvironment(): NodeJS.ProcessEnv {
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

export function ensureLiveSqlite(): void {
  if (storageActivated) return;
  if (runtimeRoot === "" || runId === "") {
    throw new Error("live SQLite activation requires the marked E2E runtime");
  }
  captureStorageAuthority();

  const result = spawnSync(
    "mix",
    ["bnest.storage.migrate", "--root", runtimeRoot, "--activate"],
    { cwd: appDirectory, env: liveEnvironment(), encoding: "utf8" },
  );
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(`live SQLite activation failed: ${result.stderr}`);
  }

  const schedules = spawnSync(
    "mix",
    [
      "run",
      "-e",
      "BnestApp.Release.Migrations.PersistentSchedules.apply_and_verify!(DateTime.utc_now())",
    ],
    { cwd: appDirectory, env: liveEnvironment(), encoding: "utf8" },
  );
  if (schedules.error) throw schedules.error;
  if (schedules.status !== 0) {
    throw new Error(`live schedule migration failed: ${schedules.stderr}`);
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
    env: liveEnvironment(),
    encoding: "utf8",
  });
  if (result.error) throw result.error;
  return {
    status: result.status ?? 1,
    stderr: result.stderr ?? "",
    stdout: result.stdout ?? "",
  };
}
