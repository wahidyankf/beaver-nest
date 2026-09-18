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
// No Caddy in front of this project: it proves backend-boundary behaviour
// directly against a single mix phx.server, never the blue/green rollout
// route. Its own 4030-4039 pool stays disjoint from the FE E2E 4010-4019
// pool so both projects can run concurrently without a port collision.
const port = process.env["BNEST_BE_E2E_PORT"] ?? "4030";
// `localhost`, not `127.0.0.1`: the app's base config pins
// `Endpoint.url.host` to "localhost" (config.exs), which Phoenix's default
// `check_origin: true` validates every LiveView/Channel socket handshake's
// Origin header against. The original bnest-app-e2e project's baseURL uses
// `localhost` for the same reason; matching it here is required, not
// cosmetic — `127.0.0.1` fails socket origin checks with "Could not check
// origin for Phoenix.Socket transport." even though plain HTTP requests
// (no socket layer) are unaffected and appear to work fine.
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
  "../../specs/apps/bnest/app-be/behaviours",
);
const testDir = defineBddConfig({
  arityCheck: true,
  featuresRoot,
  missingSteps: "fail-on-gen",
  outputDir: ".features-gen",
  steps: "tests/steps/**/*.ts",
  tags: "not @e2e-exempt",
});
const setupScenario =
  /Initial setup creates policy-valid accounts exactly once/u;

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
  webServer: {
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
      BNEST_RELEASE_REVISION: "be-e2e",
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
  ],
});
