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

type TestRuntime = { path: string; runId: string };

const repositoryRoot = path.resolve(process.cwd());
const runsRoot = path.join(repositoryRoot, "data/test/runs");

export function createTestRuntime(suite: string): TestRuntime {
  const safeSuite = suite.toLowerCase().replaceAll(/[^a-z0-9-]+/gu, "-");
  const runId = `${safeSuite}-${randomBytes(8).toString("base64url").toLowerCase()}`;
  const runtimePath = path.join(runsRoot, runId);
  assertCandidate(runtimePath);

  for (const relative of ["general", "apps/beaver-nest", "system", "users"]) {
    mkdirSync(path.join(runtimePath, relative), { recursive: true });
  }

  writeFileSync(
    path.join(runtimePath, ".bnest-test-run.json"),
    JSON.stringify({
      schemaVersion: 1,
      recordType: "bnest-test-run",
      runId,
      createdAt: new Date().toISOString(),
      owner: "bnest-test-harness",
    }),
    { encoding: "utf8", flag: "wx" },
  );

  return { path: runtimePath, runId };
}

export function cleanupTestRuntime(runtime: TestRuntime): void {
  assertCandidate(runtime.path);

  const marker = JSON.parse(
    readFileSync(path.join(runtime.path, ".bnest-test-run.json"), "utf8"),
  ) as Record<string, unknown>;

  if (
    marker["schemaVersion"] !== 1 ||
    marker["recordType"] !== "bnest-test-run" ||
    marker["runId"] !== runtime.runId ||
    marker["owner"] !== "bnest-test-harness"
  ) {
    throw new Error("Refusing cleanup for an invalid Bnest test marker");
  }

  rmSync(runtime.path, { recursive: true, force: false });
}

export default function globalTeardown(): void {
  const runtimePath = process.env["BNEST_E2E_RUNTIME_ROOT"];
  const runId = process.env["BNEST_E2E_RUN_ID"];

  if (runtimePath && runId && existsSync(runtimePath)) {
    cleanupTestRuntime({ path: runtimePath, runId });
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
