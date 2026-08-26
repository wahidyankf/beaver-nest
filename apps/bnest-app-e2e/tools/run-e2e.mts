import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import path from "node:path";
import {
  cleanupTestRuntime,
  createTestRuntime,
} from "../tests/support/test-runtime.mts";

const repositoryRoot = path.resolve(import.meta.dirname, "../../..");
const runtime = createTestRuntime("e2e");

try {
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
      },
      stdio: "inherit",
    },
  );

  if (result.error) throw result.error;
  process.exitCode = result.status ?? 1;
} finally {
  if (existsSync(runtime.path)) cleanupTestRuntime(runtime);
}
