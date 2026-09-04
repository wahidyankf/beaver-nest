import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
  existsSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import os from "node:os";
import path from "node:path";
import type { TestInfo } from "@playwright/test";

// Every scenario that drives `mix bnest.storage.migrate` headlessly gets its
// own scratch flat root, pointer file, and HOME directory so it never shares
// mutable storage state with other scenarios or with the live E2E webServer
// (which has its own fixed, shared pointer for the admin-UI scenarios). This
// mirrors the isolation the Elixir integration tests already use.
export type StorageScenario = {
  flatRoot: string;
  pointerPath: string;
  homeDirectory: string;
  runId: string;
};

const repositoryRoot = process.cwd();
const appDirectory = path.join(repositoryRoot, "apps/bnest-app");
let discoveredMixHome = "";

export function isolatedStorageScenario(
  testInfo: TestInfo,
  label: string,
): StorageScenario {
  const digest = createHash("sha256")
    .update(
      `${testInfo.project.name}:${testInfo.file}:${testInfo.title}:${label}`,
    )
    .digest("hex")
    .slice(0, 12);
  const base = path.join(os.tmpdir(), `bnest-e2e-storage-${digest}`);
  rmSync(base, { recursive: true, force: true });
  mkdirSync(path.join(base, "flat"), { recursive: true });
  mkdirSync(path.join(base, "pointer"), { recursive: true });
  mkdirSync(path.join(base, "home"), { recursive: true });
  return {
    flatRoot: path.join(base, "flat"),
    pointerPath: path.join(base, "pointer", "storage.json"),
    homeDirectory: path.join(base, "home"),
    runId: digest,
  };
}

export function cleanupStorageScenario(scenario: StorageScenario): void {
  rmSync(path.dirname(path.dirname(scenario.pointerPath)), {
    recursive: true,
    force: true,
  });
}

export function defaultPointerPath(scenario: StorageScenario): string {
  return path.join(scenario.homeDirectory, ".config/bnest/storage.json");
}

export function defaultDatabaseDirectory(scenario: StorageScenario): string {
  return path.join(
    scenario.homeDirectory,
    "bnest/data/test/runs",
    scenario.runId,
  );
}

type MigrateResult = { status: number; stdout: string; stderr: string };

// By default the isolated pointer path is used (BNEST_STORAGE_CONFIG set).
// Pass useDefaultPointer to exercise Location.default_directory() instead,
// scoped safely under scenario.homeDirectory via a HOME override so the
// real ~/.config/bnest on the developer/CI machine is never touched.
export function runStorageMigrate(
  scenario: StorageScenario,
  args: string[],
  { useDefaultPointer = false }: { useDefaultPointer?: boolean } = {},
): MigrateResult {
  const result = runStorageCommand(
    scenario,
    "bnest.storage.migrate",
    ["--root", scenario.flatRoot, ...args],
    { useDefaultPointer },
  );
  return result;
}

export function runStorageCommand(
  scenario: StorageScenario,
  command: string,
  args: string[],
  { useDefaultPointer = false }: { useDefaultPointer?: boolean } = {},
): MigrateResult {
  const realHome = os.homedir();
  const env: NodeJS.ProcessEnv = {
    ...process.env,
    MIX_ENV: "test",
    HOME: scenario.homeDirectory,
    MIX_HOME: process.env["MIX_HOME"] ?? resolveMixHome(),
    BNEST_TEST_RUN_ID: scenario.runId,
    ASDF_DIR: process.env["ASDF_DIR"] ?? path.join(realHome, ".asdf"),
    ASDF_DATA_DIR: process.env["ASDF_DATA_DIR"] ?? path.join(realHome, ".asdf"),
  };
  delete env["BNEST_STORAGE_CONFIG"];
  if (!useDefaultPointer) env["BNEST_STORAGE_CONFIG"] = scenario.pointerPath;

  const result = spawnSync("mix", [command, ...args], {
    cwd: appDirectory,
    env,
    encoding: "utf8",
  });
  return {
    status: result.status ?? 1,
    stdout: result.stdout ?? "",
    stderr: result.stderr ?? "",
  };
}

function resolveMixHome(): string {
  if (discoveredMixHome !== "") return discoveredMixHome;

  const result = spawnSync(
    "elixir",
    ["-e", "Mix.start(); IO.write(Mix.Utils.mix_home())"],
    { cwd: os.tmpdir(), env: process.env, encoding: "utf8" },
  );
  const resolved = result.stdout?.trim() ?? "";
  if (result.error) throw result.error;
  if (result.status !== 0 || resolved === "") {
    throw new Error(`failed to resolve Mix home: ${result.stderr}`);
  }
  discoveredMixHome = resolved;
  return discoveredMixHome;
}

export function readPointer(
  scenario: StorageScenario,
): Record<string, unknown> | undefined {
  return readJsonIfPresent(scenario.pointerPath);
}

export function writePointer(
  scenario: StorageScenario,
  databaseDirectory: string,
): void {
  writeFileSync(
    scenario.pointerPath,
    JSON.stringify({
      schemaVersion: 1,
      databaseDirectory,
      databaseFilename: "bnest.sqlite3",
      phase: "flat_primary",
      migrationId: "flat-files-v1-to-sqlite-v1",
    }),
    { encoding: "utf8", flag: "wx" },
  );
}

export function readDefaultPointer(
  scenario: StorageScenario,
): Record<string, unknown> | undefined {
  return readJsonIfPresent(defaultPointerPath(scenario));
}

function readJsonIfPresent(file: string): Record<string, unknown> | undefined {
  return existsSync(file)
    ? (JSON.parse(readFileSync(file, "utf8")) as Record<string, unknown>)
    : undefined;
}

export function writeThemeFixture(
  scenario: StorageScenario,
  ownerId = "user-fixture-001",
): string {
  const file = path.join(
    scenario.flatRoot,
    "users",
    ownerId,
    "preferences",
    "theme.json",
  );
  mkdirSync(path.dirname(file), { recursive: true });
  writeFileSync(
    file,
    JSON.stringify({
      schemaVersion: 1,
      recordType: "theme-preference",
      ownerId,
      sourceImportId: null,
      revision: 1,
      theme: "light",
      updatedAt: new Date().toISOString(),
    }),
    { encoding: "utf8", flag: "wx" },
  );
  return file;
}

export function seedMalformedBootstrap(scenario: StorageScenario): string {
  const file = path.join(scenario.flatRoot, "system", "bootstrap.json");
  mkdirSync(path.dirname(file), { recursive: true });
  writeFileSync(file, "{not valid json", { encoding: "utf8" });
  return file;
}

export function digestFile(file: string): string {
  return existsSync(file)
    ? createHash("sha256").update(readFileSync(file)).digest("hex")
    : "missing";
}

function jsonFilesRecursive(directory: string): string[] {
  if (!existsSync(directory)) return [];
  return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const candidate = path.join(directory, entry.name);
    if (entry.isDirectory()) return jsonFilesRecursive(candidate);
    return entry.isFile() && entry.name.endsWith(".json") ? [candidate] : [];
  });
}

export function flatRootDigest(root: string): string {
  const hash = createHash("sha256");
  for (const file of jsonFilesRecursive(root).toSorted()) {
    hash.update(readFileSync(file));
  }
  return hash.digest("hex");
}

// --- Live, shared webServer pointer (admin-UI and health scenarios only) ---
// playwright.config.mts pins BNEST_STORAGE_CONFIG for the whole E2E run to
// this path, scoped inside the marked E2E runtime root. Only scenarios that
// interact with the running server through the browser or /health/ready use
// this shared, single-lifetime pointer; every headless CLI scenario above
// uses its own private scratch pointer instead.
export function liveRuntimeRoot(): string {
  const root = process.env["BNEST_E2E_RUNTIME_ROOT"];
  if (!root) throw new Error("Missing marked E2E runtime root");
  return root;
}

export function liveStoragePointerPath(): string {
  return path.join(liveRuntimeRoot(), "storage-config", "storage.json");
}

export function readLivePointer(): Record<string, unknown> | undefined {
  return readJsonIfPresent(liveStoragePointerPath());
}
