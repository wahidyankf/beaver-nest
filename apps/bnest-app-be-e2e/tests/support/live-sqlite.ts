import { spawnSync } from "node:child_process";
import path from "node:path";
import { currentInstanceEnvironment } from "./active-instance.mts";
import { secondaryEnvironment } from "./secondary-environment.mts";

// Secondary `mix run -e` processes for the reads a test still makes through Elixir (ADR 001, section 2). Each one
// takes its runtime and storage environment from the current instance, so it reads only that instance's database.
// The primary server is never restarted or re-pointed from here; the spawn already re-pointed it.

const appDirectory = path.join(process.cwd(), "apps/bnest-app");

// The SQLite run root, `~/bnest/data/test/runs/<run>`, which holds every instance and the storage pointer.
export function sqliteRunRoot(): string {
  const root = process.env["BNEST_E2E_SQLITE_RUNTIME_ROOT"];
  if (!root) throw new Error("Missing marked E2E SQLite runtime root");
  return root;
}

// One backup configuration file for the run, which each spawn and each delete removes (ADR 001, section 3).
export function backupConfigPath(): string {
  return path.join(sqliteRunRoot(), "storage-config", "backup.json");
}

// The environment of a secondary process: the current instance's three variables, the fixed backup configuration,
// and the test layer. The inherited control secret is removed, because no `mix run -e` read calls the control routes.
export function liveEnvironment(): NodeJS.ProcessEnv {
  const runId = process.env["BNEST_E2E_RUN_ID"] ?? "";
  if (runId === "") throw new Error("BNEST_E2E_RUN_ID is not set");
  return secondaryEnvironment(process.env, currentInstanceEnvironment(), {
    backupConfig: backupConfigPath(),
    runId,
  });
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
