import { defineConfig, devices } from "@playwright/test";
import path from "node:path";
import { defineBddConfig } from "playwright-bdd";

const appDirectory = path.resolve(import.meta.dirname, "../bnest-app");
const codexRunner = path.resolve(
  appDirectory,
  "test/support/codex_fixture_runner.mjs",
);
const codexModelsRunner = path.resolve(
  appDirectory,
  "test/support/codex_fixture_models.mjs",
);
const port = process.env["BNEST_E2E_PORT"] ?? "4010";
const baseURL = `http://localhost:${port}`;
const runtime = {
  path:
    process.env["BNEST_E2E_RUNTIME_ROOT"] ??
    path.resolve(
      import.meta.dirname,
      "../../data/test/runs/configuration-only",
    ),
  runId: process.env["BNEST_E2E_RUN_ID"] ?? "configuration-only",
};
const featuresRoot = path.resolve(
  import.meta.dirname,
  "../../specs/apps/bnest/app/behaviours",
);
const testDir = defineBddConfig({
  arityCheck: true,
  featuresRoot,
  missingSteps: "fail-on-gen",
  outputDir: ".features-gen",
  steps: "tests/steps/**/*.ts",
});
const setupScenario = /Initial setup warns about unavailable account recovery/u;
const desktopOnlyLoadScenario =
  /Ten synthetic visitors preserve recoverable state/u;
// The admin-UI storage scenarios persist a single, once-per-server-lifetime
// pointer (Bnest's storage location is immutable once set). Running them
// again on the tablet/mobile projects would collide with the chromium
// project's own run of the same pointer, so — like the one-time setup
// scenario — sqlite storage runs on chromium only.
const sqliteStorageScenario =
  /private default without storage UI|valid custom database folder|Unsafe database folder is rejected|expected schema once|every recognized flat-file record|resumes idempotently|authoritative only after complete verification|blocks cutover without data loss|Non-admin cannot configure storage|reconnects across compatible SQLite rollout|Authoritative SQLite relocates|Verified legacy flat-file storage/u;

export default defineConfig({
  testDir,
  fullyParallel: false,
  globalTeardown: path.resolve(
    import.meta.dirname,
    "tests/support/test-runtime.mts",
  ),
  use: {
    baseURL,
    trace: "on-first-retry",
  },
  webServer: {
    command: "mix phx.server",
    cwd: appDirectory,
    env: {
      ...process.env,
      BNEST_CODEX_MODELS_RUNNER: codexModelsRunner,
      BNEST_CODEX_RUNNER: codexRunner,
      BNEST_RUNTIME_ROOT: runtime.path,
      BNEST_STORAGE_CONFIG: path.join(
        runtime.path,
        "storage-config",
        "storage.json",
      ),
      BNEST_TEST_LAYER: "integration",
      BNEST_TEST_RUN_ID: runtime.runId,
      MIX_ENV: "test",
      PHX_SERVER: "true",
      PORT: port,
    },
    url: baseURL,
    reuseExistingServer: false,
    timeout: 120_000,
  },
  projects: [
    {
      name: "one-time-setup",
      grep: setupScenario,
      use: { ...devices["Desktop Chrome"] },
    },
    {
      name: "chromium",
      dependencies: ["one-time-setup"],
      grepInvert: setupScenario,
      use: { ...devices["Desktop Chrome"] },
    },
    {
      name: "tablet-chromium",
      dependencies: ["one-time-setup"],
      grepInvert: new RegExp(
        `${setupScenario.source}|${desktopOnlyLoadScenario.source}|${sqliteStorageScenario.source}`,
        "u",
      ),
      use: {
        ...devices["Desktop Chrome"],
        viewport: { width: 768, height: 1024 },
      },
    },
    {
      name: "mobile-chromium",
      dependencies: ["one-time-setup"],
      grepInvert: new RegExp(
        `${setupScenario.source}|${desktopOnlyLoadScenario.source}|${sqliteStorageScenario.source}`,
        "u",
      ),
      use: { ...devices["Pixel 5"] },
    },
  ],
});
