import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import path from "node:path";
import {
  cleanupTestRuntime,
  createTestRuntime,
} from "../tests/support/test-runtime.mts";
import {
  acquirePortLease,
  releasePortLease,
} from "../../bnest-app/tools/port-lease.mjs";

const repositoryRoot = path.resolve(import.meta.dirname, "../../..");
const runtime = createTestRuntime("e2e");
const port = Number(process.env["BNEST_E2E_PORT"] ?? "4010");
let lease: ReturnType<typeof acquirePortLease> | undefined;

try {
  lease = acquirePortLease(port, "e2e", 4010, 4019);
  const result = spawnSync(
    "npm",
    [
      "exec",
      "--",
      "playwright",
      "test",
      "--config",
      "apps/bnest-app-e2e/playwright.config.mts",
      ...process.argv.slice(2),
    ],
    {
      cwd: repositoryRoot,
      env: {
        ...process.env,
        BNEST_E2E_RUNTIME_ROOT: runtime.path,
        BNEST_E2E_RUN_ID: runtime.runId,
        BNEST_E2E_PORT: String(port),
      },
      stdio: "inherit",
    },
  );

  if (result.error) throw result.error;
  process.exitCode = result.status ?? 1;
} finally {
  try {
    if (existsSync(runtime.path)) cleanupTestRuntime(runtime);
  } finally {
    if (lease) releasePortLease(lease);
  }
}
