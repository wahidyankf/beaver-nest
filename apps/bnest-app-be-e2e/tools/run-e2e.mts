import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import path from "node:path";
import {
  cleanupTestRuntime,
  createTestRuntime,
  generateTestControlSecret,
  listTestInstanceLeaks,
} from "../tests/support/test-runtime.mts";
import { cleanupStaleTestData } from "../../bnest-app/tools/test-data-cleanup.mjs";

const repositoryRoot = path.resolve(import.meta.dirname, "../../..");
cleanupStaleTestData();
const runtime = createTestRuntime("be-e2e");
// Per run. It reaches the webServer, Playwright and secondary BEAMs only through the environment below.
// It is never logged or written.
const testControlSecret = generateTestControlSecret();
const port = Number(process.env["BNEST_BE_E2E_PORT"] ?? "4030");

try {
  const result = spawnSync(
    "npm",
    [
      "exec",
      "--",
      "playwright",
      "test",
      "--config",
      "apps/bnest-app-be-e2e/playwright.config.mts",
      ...process.argv.slice(2),
    ],
    {
      cwd: repositoryRoot,
      env: {
        ...process.env,
        BNEST_E2E_RUNTIME_ROOT: runtime.path,
        BNEST_E2E_SQLITE_RUNTIME_ROOT: runtime.sqlitePath,
        BNEST_E2E_RUN_ID: runtime.runId,
        BNEST_BE_E2E_PORT: String(port),
        BNEST_TEST_CONTROL_SECRET: testControlSecret,
      },
      stdio: "inherit",
    },
  );

  if (result.error) throw result.error;
  process.exitCode = result.status ?? 1;
} finally {
  // Playwright and its servers have exited here, so nothing can still write. Any instance left under
  // either root is a teardown bug: report it, fail the run, then remove the validated pair.
  const leaks = listTestInstanceLeaks(runtime);
  if (leaks.length > 0) {
    process.stderr.write(
      `Bnest test instances leaked past teardown:\n${leaks.map((leak) => `  ${leak}`).join("\n")}\n`,
    );
    process.exitCode = 1;
  }
  if (existsSync(runtime.path)) cleanupTestRuntime(runtime);
}
