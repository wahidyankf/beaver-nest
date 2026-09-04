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
const backendPort = String(Number(port) + 100);
const caddyAdminPort = String(Number(port) + 200);
const baseURL = `http://localhost:${port}`;
process.env["BNEST_E2E_BACKEND_PORT"] = backendPort;
process.env["BNEST_E2E_CADDY_ADMIN_PORT"] = caddyAdminPort;
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
  tags: "not @e2e-exempt",
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
  /private default without storage UI|valid custom database folder|Private custom storage|Unsafe database folder is rejected|expected schema once|every recognized flat-file record|resumes idempotently|authoritative only after complete verification|blocks cutover without data loss|Non-admin cannot configure storage|reconnects across compatible SQLite rollout|Authoritative SQLite relocates|Verified legacy flat-file storage/u;

export default defineConfig({
  testDir,
  fullyParallel: false,
  timeout: 120_000,
  workers: 1,
  globalTeardown: path.resolve(
    import.meta.dirname,
    "tests/support/test-runtime.mts",
  ),
  use: {
    baseURL,
    trace: "on-first-retry",
  },
  webServer: [
    {
      command: "mix phx.server",
      cwd: appDirectory,
      env: {
        ...process.env,
        BNEST_CODEX_MODELS_RUNNER: codexModelsRunner,
        BNEST_CODEX_RUNNER: codexRunner,
        BNEST_DEPLOY_SLOT: "blue",
        BNEST_BACKUP_CONFIG: path.join(
          runtime.path,
          "storage-config",
          "backup.json",
        ),
        BNEST_RELEASE_REVISION: "e2e-blue",
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
        PORT: backendPort,
      },
      url: `http://127.0.0.1:${backendPort}`,
      reuseExistingServer: false,
      timeout: 120_000,
    },
    {
      command: "node apps/bnest-app-e2e/tools/run-caddy.mts",
      cwd: path.resolve(import.meta.dirname, "../.."),
      env: {
        ...process.env,
        BNEST_E2E_BACKEND_PORT: backendPort,
        BNEST_E2E_CADDY_ADMIN_PORT: caddyAdminPort,
        BNEST_E2E_PORT: port,
      },
      url: baseURL,
      reuseExistingServer: false,
      timeout: 30_000,
    },
  ],
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
