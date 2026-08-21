import { defineConfig, devices } from "@playwright/test";
import path from "node:path";

const appDirectory = path.resolve(import.meta.dirname, "../bnest-app");

export default defineConfig({
  testDir: "./tests",
  fullyParallel: true,
  use: {
    baseURL: "http://127.0.0.1:4000",
    trace: "on-first-retry",
  },
  webServer: {
    command: "mix phx.server",
    cwd: appDirectory,
    url: "http://127.0.0.1:4000",
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
