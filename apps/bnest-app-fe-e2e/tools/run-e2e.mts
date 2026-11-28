import { spawn } from "node:child_process";
import { createWriteStream, existsSync, mkdirSync } from "node:fs";
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

// RHINO discards the output of a failing child gate, so the CI log of a failed scheduled run would show no
// scenario. This file keeps the whole Playwright output. The workflow uploads it as an artifact. Playwright's own
// output directory is the repository-root test-results, which it clears at the start of a run, so the log lives
// beside the JSON summary instead.
const outputLogPath = path.resolve(
  import.meta.dirname,
  "../test-results/e2e-output.log",
);

// Streams the child's output to this process and to the log while it runs, so a run that is killed on a timeout
// still leaves what it printed. Resolves with the child's exit status, and 1 when a signal ended it.
const runPlaywright = (env: NodeJS.ProcessEnv): Promise<number> =>
  new Promise((resolve, reject) => {
    mkdirSync(path.dirname(outputLogPath), { recursive: true });
    const outputLog = createWriteStream(outputLogPath);
    const child = spawn(
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
      { cwd: repositoryRoot, env, stdio: ["inherit", "pipe", "pipe"] },
    );
    child.stdout.on("data", (chunk: Buffer) => {
      process.stdout.write(chunk);
      outputLog.write(chunk);
    });
    child.stderr.on("data", (chunk: Buffer) => {
      process.stderr.write(chunk);
      outputLog.write(chunk);
    });
    child.on("error", (error) => {
      outputLog.end();
      reject(error);
    });
    child.on("close", (status) => {
      outputLog.end(() => {
        resolve(status ?? 1);
      });
    });
  });

try {
  process.exitCode = await runPlaywright({
    ...process.env,
    BNEST_E2E_RUNTIME_ROOT: runtime.path,
    BNEST_E2E_RUN_ID: runtime.runId,
    BNEST_E2E_STORAGE_CONFIG: runPaths.storageConfig,
    BNEST_E2E_BACKUP_CONFIG: runPaths.backupConfig,
    BNEST_E2E_PORT: String(port),
    BNEST_TEST_CONTROL_SECRET: testControlSecret,
  });
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
