import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import { login } from "../support/authentication";
import {
  instanceIdentities,
  type InstanceIdentities,
} from "../support/instance-identities";
import { promoteCompatibleCandidate } from "../support/routed-rollout";

// Post-rollout reconnect flow (feature scenario 10). Split out of
// sqlite_storage.steps.ts to stay under the repository's 300-line step-file
// budget. The non-admin denial moved to scheduled-backups.steps.ts.

const { Given, Then, When } = createBdd();

// @scenario specs/apps/bnest/app-fe/behaviours/sqlite_storage.feature: A connected user keeps their state across a compatible release

let activeIdentity: InstanceIdentities;
let rolloutRevisions: { previousRevision: string; revision: string };

// --- Scenario 10: routed client reconnects across a compatible rollout ------

let draftMessage = "";
const acknowledgedMessage = "Acknowledged before rollout";
const acknowledgedReply = "Fixture response complete.";

// The acknowledged state is a sent message whose Codex reply finished streaming on the
// current route's revision; only then is the next message typed and left unsent.
Given(
  "the current site is healthy and a connected user has acknowledged state",
  async ({ page }) => {
    activeIdentity = instanceIdentities();
    await page.context().clearCookies();
    await login(page, activeIdentity.admin);
    expect((await page.request.get("/health/ready")).status()).toBe(200);
    await page.goto("/chat");
    await expect(page.locator("[data-phx-main]")).toHaveClass(/phx-connected/u);
    await page.getByLabel("Message").fill(acknowledgedMessage);
    await page.getByRole("button", { name: "Send" }).click();
    await expect(
      page.locator("[data-role=user-message]", {
        hasText: acknowledgedMessage,
      }),
    ).toBeVisible();
    await expect(
      page.locator('[data-role=assistant-message][data-streaming="false"]', {
        hasText: acknowledgedReply,
      }),
    ).toBeVisible();
    draftMessage = "Unsent draft before rollout";
    await page.getByLabel("Message").fill(draftMessage);
  },
);

When("a compatible new release is promoted", async ({ page }) => {
  rolloutRevisions = await promoteCompatibleCandidate(page);
});

Then(
  "the deploy report names the new release and shows SQLite ready",
  async ({ page }) => {
    const ready = await page.request.get("/health/ready");
    expect(ready.status()).toBe(200);
    const body = await ready.json();
    expect(body.revision).toBe(rolloutRevisions.revision);
    expect(body.revision).not.toBe(rolloutRevisions.previousRevision);
    expect(body.sqliteReady).toBe(true);
  },
);

Then("the LiveView reconnects without a manual refresh", async ({ page }) => {
  await expect(page.locator("[data-phx-main]")).toHaveClass(/phx-connected/u);
  await expect(page).toHaveURL(/\/chat$/u);
});

// Revision B rendered the conversation it loaded, so the acknowledged exchange is there
// once, beside the draft the client recovered into the composer.
Then(
  "the acknowledged state and unsent draft remain available",
  async ({ page }) => {
    await expect(
      page.locator("[data-role=user-message]", {
        hasText: acknowledgedMessage,
      }),
    ).toHaveCount(1);
    await expect(
      page.locator('[data-role=assistant-message][data-streaming="false"]', {
        hasText: acknowledgedReply,
      }),
    ).toHaveCount(1);
    await expect(page.getByLabel("Message")).toHaveValue(draftMessage);
  },
);
