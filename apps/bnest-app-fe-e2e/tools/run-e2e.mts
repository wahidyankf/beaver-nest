import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import path from "node:path";
import {
  cleanupTestRuntime,
  createTestRuntime,
  generateTestControlSecret,
  listTestInstanceLeaks,
} from "../tests/support/test-runtime.mts";
import { runConfigPaths } from "../tests/support/test-instance-lifecycle.mts";
import { cleanupStaleTestData } from "../../bnest-app/tools/test-data-cleanup.mjs";

const repositoryRoot = path.resolve(import.meta.dirname, "../../..");
cleanupStaleTestData();
const runtime = createTestRuntime("fe-e2e");
// The storage pointer and backup config of this run, under its SQLite run root. The Playwright config reads
// them from the environment below, so the primary server and the step files share one derivation.
const runPaths = runConfigPaths({
  runId: runtime.runId,
  home: process.env["HOME"] ?? "",
});
// Per run. It reaches the primary webServer, every rollout candidate and Playwright only through the
// environment below, because each server spreads this process's environment. It is never logged or
// written.
const testControlSecret = generateTestControlSecret();
const port = Number(process.env["BNEST_E2E_PORT"] ?? "4010");

try {
  const result = spawnSync(
    "npm",
    [
      "exec",
      "--",
      "playwright",
      "test",
      "--config",
      "apps/bnest-app-fe-e2e/playwright.config.mts",
      ...process.argv.slice(2),
    ],
    {
      cwd: repositoryRoot,
      env: {
        ...process.env,
        BNEST_E2E_RUNTIME_ROOT: runtime.path,
        BNEST_E2E_RUN_ID: runtime.runId,
        BNEST_E2E_STORAGE_CONFIG: runPaths.storageConfig,
        BNEST_E2E_BACKUP_CONFIG: runPaths.backupConfig,
        BNEST_E2E_PORT: String(port),
        BNEST_TEST_CONTROL_SECRET: testControlSecret,
        // Set once, here, rather than in each server definition: both the
        // primary `webServer` and every rollout candidate spread this
        // process's environment, so one assignment reaches all of them. The
        // browser scenarios exercise the feature as the experience release
        // ships it; the compatibility scenario overrides it per candidate.
        BNEST_FAMILY_CHAT_REPLY_ENABLED: "true",
      },
      stdio: "inherit",
    },
  );

  if (result.error) throw result.error;
  process.exitCode = result.status ?? 1;
} finally {
  // Playwright, the primary server and the rollout candidates have exited here, so nothing can still
  // write. Any instance left under either root is a teardown bug: report it, fail the run, then remove
  // the validated pair.
  const leaks = listTestInstanceLeaks(runtime);
  if (leaks.length > 0) {
    process.stderr.write(
      `Bnest test instances leaked past teardown:\n${leaks.map((leak) => `  ${leak}`).join("\n")}\n`,
    );
    process.exitCode = 1;
  }
  if (existsSync(runtime.path)) cleanupTestRuntime(runtime);
}
