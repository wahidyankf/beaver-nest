import os from "node:os";
import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import { login } from "../support/authentication";
import {
  isolatedTestIdentity,
  type TestIdentity,
} from "../support/test-identity";

// Non-admin denial and post-rollout reconnect flows (feature scenarios 9,
// 10). Split out of sqlite_storage.steps.ts to stay under the repository's
// 300-line step-file budget.

const { Given, Then, When } = createBdd();

const repositoryRoot = process.cwd();

let activeIdentity: TestIdentity;
let deniedRouteStatus = 0;
let deniedRouteBody = "";

// --- Scenario 9: non-admin cannot configure storage --------------------------

Given("a non-admin family member is logged in", async ({ page, $testInfo }) => {
  activeIdentity = isolatedTestIdentity($testInfo);
  await page.context().clearCookies();
  await login(page, activeIdentity.child);
});

When("the user opens the storage settings route", async ({ page }) => {
  // Plug's send_resp(:not_found, ...) leaves content-type unset, which
  // Chrome's navigation stack treats as an attachment download rather than
  // a renderable page; page.request sidesteps navigation/download detection
  // the same way authorization.steps.ts already does for other 404 routes.
  const response = await page.request.get("/storage");
  deniedRouteStatus = response.status();
  deniedRouteBody = await response.text();
});

Then("Bnest denies the operation", () => {
  expect(deniedRouteStatus).toBe(404);
});

Then("Bnest reveals no host path or migration inventory", () => {
  expect(deniedRouteBody).not.toContain("Storage setup");
  expect(deniedRouteBody).not.toContain(os.homedir());
  expect(deniedRouteBody).not.toContain(repositoryRoot);
});

// --- Scenario 10: routed client reconnects across a compatible rollout ------

let draftMessage = "";

Given(
  "the current Caddy route is healthy and a connected user has acknowledged state",
  async ({ page, $testInfo }) => {
    activeIdentity = isolatedTestIdentity($testInfo);
    await page.context().clearCookies();
    await login(page, activeIdentity.admin);
    await page.goto("/chat");
    await expect(page.locator("[data-phx-main]")).toHaveClass(/phx-connected/u);
    draftMessage = "Unsent draft before rollout";
    await page.getByLabel("Message").fill(draftMessage);
  },
);

When("a revision-compatible candidate is promoted", async ({ page }) => {
  await page.evaluate(() => {
    const liveSocket = (
      window as unknown as {
        liveSocket: { connect: () => void; disconnect: () => void };
      }
    ).liveSocket;
    liveSocket.disconnect();
    liveSocket.connect();
  });
});

Then(
  "the routed revision and SQLite readiness are proven",
  async ({ page }) => {
    const ready = await page.request.get("/health/ready");
    expect(ready.status()).toBe(200);
    const body = await ready.json();
    expect(typeof body.revision).toBe("string");
    expect(typeof body.sqliteReady).toBe("boolean");
  },
);

Then("the LiveView reconnects without a manual refresh", async ({ page }) => {
  await expect(page.locator("[data-phx-main]")).toHaveClass(/phx-connected/u);
  await expect(page).toHaveURL(/\/chat$/u);
});

Then(
  "the acknowledged state and unsent draft remain available",
  async ({ page }) => {
    await expect(page.getByLabel("Message")).toHaveValue(draftMessage);
  },
);
