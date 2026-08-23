import { defineConfig, devices } from "@playwright/test";
import path from "node:path";
import { defineBddConfig } from "playwright-bdd";

const appDirectory = path.resolve(import.meta.dirname, "../bnest-app");
const port = process.env["BNEST_E2E_PORT"] ?? "4000";
const baseURL = `http://127.0.0.1:${port}`;
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

export default defineConfig({
  testDir,
  fullyParallel: true,
  use: {
    baseURL,
    trace: "on-first-retry",
  },
  webServer: {
    command: "mix phx.server",
    cwd: appDirectory,
    env: { ...process.env, PORT: port },
    url: baseURL,
    reuseExistingServer: !process.env["CI"],
    timeout: 120_000,
  },
  projects: [
    {
      name: "chromium",
      use: { ...devices["Desktop Chrome"] },
    },
  ],
});
