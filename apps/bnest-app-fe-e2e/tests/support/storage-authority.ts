import { spawnSync } from "node:child_process";
import {
  cpSync,
  existsSync,
  lstatSync,
  mkdtempSync,
  readFileSync,
  rmSync,
} from "node:fs";
import os from "node:os";
import path from "node:path";

const runtimeRoot = process.env["BNEST_E2E_RUNTIME_ROOT"] ?? "";
const runId = process.env["BNEST_E2E_RUN_ID"] ?? "";
let captured = false;
let snapshotRoot: string | undefined;

export function captureStorageAuthority(): void {
  if (captured) return;
  assertRuntimeRoot();
  snapshotRoot = mkdtempSync(path.join(os.tmpdir(), "bnest-e2e-authority-"));
  cpSync(runtimeRoot, path.join(snapshotRoot, "runtime"), { recursive: true });
  captured = true;
}

export function restoreStorageAuthority(): void {
  if (!captured) return;
  const configPath = routedStorageConfigPath();
  const databasePath = activeDatabasePath(configPath);
  const snapshot = snapshotRoot;
  if (snapshot === undefined) {
    throw new Error("routed storage snapshot is missing");
  }
  try {
    assertRuntimeRoot();
    rmSync(runtimeRoot, { recursive: true, force: false });
    cpSync(path.join(snapshot, "runtime"), runtimeRoot, { recursive: true });
    resetSqlite(databasePath, configPath);
  } finally {
    rmSync(snapshot, { recursive: true, force: true });
    captured = false;
    snapshotRoot = undefined;
  }
}

function activeDatabasePath(configPath: string): string | undefined {
  if (!existsSync(configPath)) return undefined;
  const config = JSON.parse(readFileSync(configPath, "utf8")) as Record<
    string,
    unknown
  >;
  const directory = config["databaseDirectory"];
  const filename = config["databaseFilename"];
  if (typeof directory !== "string" || typeof filename !== "string") {
    throw new TypeError("active routed storage config is incomplete");
  }
  const databasePath = path.join(path.resolve(directory), filename);
  if (!existsSync(databasePath)) return undefined;
  const expectedDirectory = path.resolve(
    os.homedir(),
    "bnest/data/test/runs",
    runId,
  );
  if (runId === "" || path.resolve(directory) !== expectedDirectory) {
    throw new Error("refusing to reset SQLite outside the marked test run");
  }
  return databasePath;
}

function assertRuntimeRoot(): void {
  const resolved = path.resolve(runtimeRoot);
  const expectedParent = path.resolve(process.cwd(), "data/test/runs");
  if (
    runId === "" ||
    path.dirname(resolved) !== expectedParent ||
    path.basename(resolved) !== runId ||
    lstatSync(resolved).isSymbolicLink()
  ) {
    throw new Error("routed storage runtime is not a marked test-run child");
  }
  const marker = JSON.parse(
    readFileSync(path.join(resolved, ".bnest-test-run.json"), "utf8"),
  ) as Record<string, unknown>;
  if (marker["recordType"] !== "bnest-test-run" || marker["runId"] !== runId) {
    throw new Error("routed storage runtime marker is invalid");
  }
}

function resetSqlite(
  databasePath: string | undefined,
  configPath: string,
): void {
  if (databasePath === undefined || !existsSync(databasePath)) return;
  const tables = [
    "bnest_schedule_runs",
    "bnest_schedules",
    "bnest_migration_items",
    "bnest_migration_runs",
    "bnest_recovery_sources",
    "bnest_records",
  ];
  const expression = `BnestApp.DataRepository.StorageCoordinator.ensure_started!(); Enum.each(${JSON.stringify(tables)}, fn table -> Ecto.Adapters.SQL.query!(BnestApp.SqliteRepo, "DELETE FROM " <> table) end); BnestApp.DataRepository.StorageCoordinator.stop()`;
  const result = spawnSync("mix", ["run", "-e", expression], {
    cwd: path.join(process.cwd(), "apps/bnest-app"),
    env: {
      ...process.env,
      BNEST_RUNTIME_ROOT: runtimeRoot,
      BNEST_STORAGE_CONFIG: configPath,
      BNEST_TEST_RUN_ID: runId,
      MIX_ENV: "test",
    },
    encoding: "utf8",
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(`failed to reset routed SQLite state: ${result.stderr}`);
  }
}

export function routedStorageConfigPath(): string {
  const configPath =
    process.env["BNEST_STORAGE_CONFIG"] ??
    path.join(runtimeRoot, "storage-config", "storage.json");
  const resolvedRoot = path.resolve(runtimeRoot);
  const resolvedConfig = path.resolve(configPath);
  if (
    resolvedRoot === path.parse(resolvedRoot).root ||
    !resolvedConfig.startsWith(`${resolvedRoot}${path.sep}`)
  ) {
    throw new Error(
      "routed storage config must stay inside the marked runtime",
    );
  }
  return resolvedConfig;
}
