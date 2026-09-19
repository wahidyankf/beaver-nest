import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";

// family_chat.feature's "Rule: Reconnect on visibility resume" -- split out
// of family-chat.steps.ts purely to stay under this project's max-lines lint
// budget (that file's own header explains the feature's overall proof
// split).

const { Then, When } = createBdd();

let socketReopenedOnResume = false;

When(
  "the tab is backgrounded with its connection silently dropped",
  async ({ page }) => {
    socketReopenedOnResume = false;
    // Attached only from this point on, so any event this listener sees is
    // unambiguously a *new* connection -- not the room's initial one, which
    // already opened before this step ran.
    page.once("websocket", () => {
      socketReopenedOnResume = true;
    });
    // A mobile PWA's OS-suspended background tab routinely severs its
    // connection without a clean close event; `setOffline` plus a real
    // `visibilitychange` to "hidden" is this layer's closest reachable proxy
    // for that (see the feature file's Exemption comment for what real OS
    // suspension this cannot reach).
    await page.context().setOffline(true);
    await page.evaluate(() => {
      Object.defineProperty(document, "visibilityState", {
        configurable: true,
        get: () => "hidden",
      });
      document.dispatchEvent(new Event("visibilitychange"));
    });
  },
);

When("the tab becomes visible again", async ({ page }) => {
  await page.context().setOffline(false);
  await page.evaluate(() => {
    Object.defineProperty(document, "visibilityState", {
      configurable: true,
      get: () => "visible",
    });
    document.dispatchEvent(new Event("visibilitychange"));
  });
});

Then("a fresh socket connection replaces the prior one", async () => {
  await expect
    .poll(() => socketReopenedOnResume, { timeout: 10_000 })
    .toBe(true);
});

// Reuses family-chat.steps.ts's own generic opener ("a visitor opens
// {string} with the socket connected to the current slot") and "the page
// does not reload" -- both already registered globally by playwright-bdd,
// so no duplicate binding is declared here.
