import { randomBytes } from "node:crypto";
import {
  existsSync,
  lstatSync,
  mkdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import path from "node:path";
import os from "node:os";

type TestRuntime = { path: string; sqlitePath: string; runId: string };

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

export default function globalTeardown(): void {
  const runtimePath = process.env["BNEST_E2E_RUNTIME_ROOT"];
  const runId = process.env["BNEST_E2E_RUN_ID"];

  if (runtimePath && runId && existsSync(runtimePath)) {
    cleanupTestRuntime({
      path: runtimePath,
      sqlitePath: path.join(sqliteRunsRoot, runId),
      runId,
    });
  }
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
