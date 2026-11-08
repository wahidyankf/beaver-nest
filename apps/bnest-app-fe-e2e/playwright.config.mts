import { defineConfig, devices } from "@playwright/test";
import path from "node:path";
import { defineBddConfig } from "playwright-bdd";
import { browserEnvironment } from "./tests/support/browser-environment.mts";

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
// The server writes the storage pointer and the backup config under the SQLite run root, and every
// instance spawn reports that pointer. The primary server must read the same files. tools/run-e2e.mts derives
// both paths with runConfigPaths and passes them here, because this file cannot import that helper: Playwright
// loads the config as a module, and the step files then load the same .mts helper through CommonJS, which
// fails for a helper loaded that way.
const runStorage = {
  backupConfig: process.env["BNEST_E2E_BACKUP_CONFIG"] ?? "",
  storageConfig: process.env["BNEST_E2E_STORAGE_CONFIG"] ?? "",
};
// A run always comes from tools/run-e2e.mts, which sets the run id with the paths. Without the paths, that
// run bypassed the script, and the primary server would start without its storage pointer.
if (
  process.env["BNEST_E2E_RUN_ID"] !== undefined &&
  (runStorage.storageConfig === "" || runStorage.backupConfig === "")
) {
  throw new Error(
    "BNEST_E2E_STORAGE_CONFIG and BNEST_E2E_BACKUP_CONFIG are not set; start the suite through tools/run-e2e.mts",
  );
}
const featuresRoot = path.resolve(
  import.meta.dirname,
  "../../specs/apps/bnest/app-fe/behaviours",
);
const testDir = defineBddConfig({
  arityCheck: true,
  featuresRoot,
  // The generated specs take `test` from here, so its worker-scoped auto fixture reaps a leftover instance.
  // Moving this file into `steps` makes bddgen import playwright-bdd's own `test` and drops that fixture.
  importTestFrom: path.resolve(
    import.meta.dirname,
    "tests/support/test-fixtures.ts",
  ),
  missingSteps: "fail-on-gen",
  outputDir: ".features-gen",
  steps: "tests/steps/**/*.ts",
  tags: "not @e2e-exempt",
});
const setupScenario = /Initial setup warns about unavailable recovery/u;
const desktopOnlyLoadScenario =
  /Ten synthetic visitors preserve recoverable state/u;
// These scenarios persist real state into the shared candidate's SQLite
// database (a schedule pointer, or a real chat message) rather than a
// synthetic, per-run-unique value, and the routed-rollout candidate process
// is not reset between projects within one `test:e2e` invocation. Running
// them on `tablet-chromium`/`mobile-chromium` too would replay the exact
// same write against a database that already has it from the `chromium`
// project's run, so — like the one-time setup scenario — they run on
// chromium only. (Confirmed live: without this exclusion, the experience
// release candidate proof's `toHaveCount(1)` assertion saw 2 and then 3
// matching messages on the second and third project runs.)
const sqliteStorageScenario =
  /Non-admin cannot configure storage|reconnects across compatible SQLite rollout|Two members prove draft, offline queue, and exact-once catch-up on the flag-enabled experience candidate/u;

export default defineConfig({
  testDir,
  fullyParallel: false,
  timeout: 120_000,
  workers: 1,
  globalTeardown: path.resolve(
    import.meta.dirname,
    "tests/support/global-teardown.ts",
  ),
  use: {
    baseURL,
    // Browsers get no test-control secret; the servers and the test steps keep it.
    launchOptions: { env: browserEnvironment(process.env) },
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
        BNEST_BACKUP_CONFIG: runStorage.backupConfig,
        BNEST_RELEASE_REVISION: "e2e-blue",
        BNEST_RUNTIME_ROOT: runtime.path,
        BNEST_STORAGE_CONFIG: runStorage.storageConfig,
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
      command: "node apps/bnest-app-fe-e2e/tools/run-caddy.mts",
      cwd: path.resolve(import.meta.dirname, "../.."),
      // Caddy only routes requests and never calls the control routes, so it starts from the browser's copy, which
      // has no control secret.
      env: {
        ...browserEnvironment(process.env),
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
