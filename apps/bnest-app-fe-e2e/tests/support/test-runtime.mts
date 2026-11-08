import { randomBytes } from "node:crypto";
import {
  existsSync,
  lstatSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  rmSync,
  writeFileSync,
  type Stats,
} from "node:fs";
import path from "node:path";
import os from "node:os";
import {
  backendOrigin,
  createTestingControlClient,
  type TestingControlClient,
} from "./testing-control.mts";

export type TestRuntime = { path: string; sqlitePath: string; runId: string };

const repositoryRoot = path.resolve(process.cwd());
const runsRoot = path.join(repositoryRoot, "data/test/runs");
const sqliteRunsRoot = path.join(
  process.env["HOME"] ?? "",
  "bnest/data/test/runs",
);

export function createTestRuntime(suite: string): TestRuntime {
  const safeSuite = suite.toLowerCase().replaceAll(/[^a-z0-9-]+/gu, "-");
  const runId = `${safeSuite}-${randomBytes(8).toString("base64url").toLowerCase()}`;
  const runtimePath = path.join(runsRoot, runId);
  const sqlitePath = path.join(sqliteRunsRoot, runId);
  assertCandidate(runtimePath);
  assertSqliteCandidate(sqlitePath);

  for (const relative of ["general", "apps/beaver-nest", "system", "users"]) {
    mkdirSync(path.join(runtimePath, relative), { recursive: true });
  }

  mkdirSync(sqlitePath, { recursive: true });

  const marker = JSON.stringify({
    schemaVersion: 1,
    recordType: "bnest-test-run",
    runId,
    createdAt: new Date().toISOString(),
    owner: "bnest-test-harness",
    pid: process.pid,
    hostname: os.hostname(),
  });

  for (const root of [runtimePath, sqlitePath]) {
    writeFileSync(path.join(root, ".bnest-test-run.json"), marker, {
      encoding: "utf8",
      flag: "wx",
    });
  }

  return { path: runtimePath, sqlitePath, runId };
}

// A fresh 32-byte secret per run, as 64 hex characters. The runner passes it only through the
// environment of the webServer, Playwright and the secondary BEAMs. It is never logged or written.
export function generateTestControlSecret(): string {
  return randomBytes(32).toString("hex");
}

export function cleanupTestRuntime(runtime: TestRuntime): void {
  assertCandidate(runtime.path);
  assertSqliteCandidate(runtime.sqlitePath);

  for (const root of [runtime.path, runtime.sqlitePath]) {
    const marker = JSON.parse(
      readFileSync(path.join(root, ".bnest-test-run.json"), "utf8"),
    ) as Record<string, unknown>;

    if (
      marker["schemaVersion"] !== 1 ||
      marker["recordType"] !== "bnest-test-run" ||
      marker["runId"] !== runtime.runId ||
      marker["owner"] !== "bnest-test-harness"
    ) {
      throw new Error("Refusing cleanup for an invalid Bnest test marker");
    }
  }

  rmSync(runtime.path, { recursive: true, force: false });
  rmSync(runtime.sqlitePath, { recursive: true, force: false });
}

// Every test instance directory under either root. The runner calls this after Playwright and its
// servers have exited, so any entry is a leak. Entries are listed, never followed.
export function listTestInstanceLeaks(runtime: TestRuntime): string[] {
  return [runtime.path, runtime.sqlitePath].flatMap((root) => {
    const instances = path.join(root, "instances");
    const info = lstatOrUndefined(instances);
    if (info === undefined) return [];
    if (!info.isDirectory()) return [instances];
    return readdirSync(instances).map((name) => path.join(instances, name));
  });
}

// The run base must stay data-free: no account files and no SQLite database or sidecar at any depth,
// except inside an instance directory. This mirrors the Elixir base audit.
export function runBaseLeaks(runtime: TestRuntime): string[] {
  const leaks: string[] = [];

  for (const directory of [
    path.join(runtime.path, "users"),
    path.join(runtime.path, "system", "accounts"),
  ]) {
    if (hasEntries(directory)) leaks.push(directory);
  }

  for (const root of [runtime.path, runtime.sqlitePath]) {
    leaks.push(...databaseFiles(root));
  }

  return leaks;
}

// Walks real directories only. A symbolic link is listed by name when it looks like a database, and it is
// never followed, so a link cannot send the audit outside the run.
function databaseFiles(root: string): string[] {
  const found: string[] = [];

  const walk = (directory: string): void => {
    for (const name of readdirSync(directory).toSorted()) {
      const entry = path.join(directory, name);
      if (name.includes(".sqlite3")) found.push(entry);
      const info = lstatOrUndefined(entry);
      if (info?.isDirectory() && name !== "instances") walk(entry);
    }
  };

  const info = lstatOrUndefined(root);
  if (info?.isDirectory()) walk(root);
  return found;
}

type TeardownInput = {
  runtime: TestRuntime;
  client: Pick<TestingControlClient, "state" | "deleteInstance">;
};

// Runs while the server is still up: deletes the current instance, then checks the base. It does not
// remove the roots. The runner removes them after the servers have exited.
export async function tearDownTestInstances({
  runtime,
  client,
}: TeardownInput): Promise<void> {
  const state = await client.state();
  if (state.runId !== runtime.runId) {
    throw new Error(
      `testing control serves run ${state.runId}, not ${runtime.runId}`,
    );
  }

  if (state.instance !== null) {
    await client.deleteInstance(state.instance.instanceId);
  }

  const leaks = runBaseLeaks(runtime);
  if (leaks.length > 0) {
    throw new Error(`run base is not data-free: ${leaks.join(", ")}`);
  }
}

export default async function globalTeardown(): Promise<void> {
  const runtimePath = process.env["BNEST_E2E_RUNTIME_ROOT"];
  const runId = process.env["BNEST_E2E_RUN_ID"];

  if (!runtimePath || !runId || !existsSync(runtimePath)) return;

  assertCandidate(runtimePath);
  const runtime: TestRuntime = {
    path: runtimePath,
    sqlitePath: path.join(sqliteRunsRoot, runId),
    runId,
  };
  assertSqliteCandidate(runtime.sqlitePath);

  // The FE config sets this to the backend port (frontend port + 100) before teardown runs. Missing
  // means the config did not load, so the teardown fails rather than guessing a port.
  const backendPort = process.env["BNEST_E2E_BACKEND_PORT"];
  if (backendPort === undefined) {
    throw new Error("BNEST_E2E_BACKEND_PORT is not set for global teardown");
  }

  await tearDownTestInstances({
    runtime,
    client: createTestingControlClient({ origin: backendOrigin(backendPort) }),
  });
}

function lstatOrUndefined(candidate: string): Stats | undefined {
  try {
    return lstatSync(candidate);
  } catch (error) {
    if (
      error instanceof Error &&
      "code" in error &&
      (error.code === "ENOENT" || error.code === "ENOTDIR")
    ) {
      return undefined;
    }
    throw error;
  }
}

function hasEntries(directory: string): boolean {
  const info = lstatOrUndefined(directory);
  if (info === undefined) return false;
  // A file where a directory belongs is itself a leak.
  if (!info.isDirectory()) return true;
  return readdirSync(directory).length > 0;
}

function assertSqliteCandidate(runtimePath: string): void {
  const resolved = path.resolve(runtimePath);

  if (
    path.dirname(resolved) !== sqliteRunsRoot ||
    resolved === sqliteRunsRoot
  ) {
    throw new Error(
      "Bnest E2E SQLite runtime must be one child of ~/bnest/data/test/runs",
    );
  }

  if (existsSync(resolved) && lstatSync(resolved).isSymbolicLink()) {
    throw new Error("Bnest E2E SQLite runtime cannot be a symlink");
  }
}

function assertCandidate(runtimePath: string): void {
  const resolved = path.resolve(runtimePath);

  if (path.dirname(resolved) !== runsRoot || resolved === runsRoot) {
    throw new Error("Bnest E2E runtime must be one child of data/test/runs");
  }

  if (existsSync(resolved) && lstatSync(resolved).isSymbolicLink()) {
    throw new Error("Bnest E2E runtime cannot be a symlink");
  }
}
