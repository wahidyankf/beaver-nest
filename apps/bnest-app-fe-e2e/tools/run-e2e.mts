import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import path from "node:path";
import {
  cleanupTestRuntime,
  createTestRuntime,
} from "../tests/support/test-runtime.mts";
import { cleanupStaleTestData } from "../../bnest-app/tools/test-data-cleanup.mjs";

const repositoryRoot = path.resolve(import.meta.dirname, "../../..");
cleanupStaleTestData();
const runtime = createTestRuntime("fe-e2e");
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
        BNEST_E2E_PORT: String(port),
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
  if (existsSync(runtime.path)) cleanupTestRuntime(runtime);
}
