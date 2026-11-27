import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import { sendAsAnotherMember } from "../support/family-chat";
import {
  expectRoomConnected,
  watchJoins,
  watchSubscriptions,
  type JoinLog,
  type SubscriptionLog,
} from "../support/family-chat-socket";
import { uniqueBody } from "../support/family-chat-reply";
import { instanceIdentities } from "../support/instance-identities";

// family_chat.feature's "Rule: Reconnect on visibility resume" -- split out
// of family-chat.steps.ts purely to stay under this project's max-lines lint
// budget (that file's own header explains the feature's overall proof
// split).

const { Then, When } = createBdd();

// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: A tab that lost its connection while hidden receives new messages again once it is shown, without reloading

let socketReopenedOnResume = false;
let resumedJoins: JoinLog = { topics: [] };
let resumedSubscriptions: SubscriptionLog = { acknowledged: 0 };
const CONTROL_TOPIC = "__absinthe__:control";

When(
  "the tab is backgrounded with its connection silently dropped",
  async ({ page }) => {
    socketReopenedOnResume = false;
    // Every frame the resumed socket sends and every subscription it acknowledges, counted from this point on.
    resumedJoins = watchJoins(page);
    resumedSubscriptions = watchSubscriptions(page);
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
  // The page opened a new websocket once the tab resumed; the dead connection was not reused.
  await expect
    .poll(() => socketReopenedOnResume, { timeout: 10_000 })
    .toBe(true);
});

// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: A reconnect never attempts to join the per-message subscription channel
Then(
  "no phx_join frame is sent for any topic other than the control channel",
  async ({ page }) => {
    // The resumed room has subscribed again (the server acknowledges the `doc` push with a subscription ID) and
    // finished its reconnect, so every frame of the reconnect has been sent before the check reads them.
    await expect
      .poll(() => resumedSubscriptions.acknowledged, { timeout: 15_000 })
      .toBeGreaterThan(0);
    await expectRoomConnected(page);
    expect(
      resumedJoins.topics.includes(CONTROL_TOPIC),
      "the resumed socket never joined the control channel",
    ).toBe(true);
    expect(
      resumedJoins.topics.filter((topic) => topic !== CONTROL_TOPIC),
    ).toEqual([]);
  },
);

Then(
  "a message sent by another member now appears",
  async ({ page, browser }) => {
    // The dead connection was replaced by a fresh socket...
    await expect
      .poll(() => socketReopenedOnResume, { timeout: 10_000 })
      .toBe(true);
    // ...and that socket carries live updates again: a message another member
    // sends after the tab resumes reaches this page without a reload.
    const body = uniqueBody("Sent while the tab was hidden");
    await sendAsAnotherMember(browser, instanceIdentities(), body);
    await expect(
      page.locator('[data-role="family-chat-message"]', { hasText: body }),
    ).toHaveCount(1, { timeout: 10_000 });
  },
);

// Reuses family-chat.steps.ts's own generic opener ("a visitor opens
// {string} with the socket connected to the current slot") and "the page
// does not reload" -- both already registered globally by playwright-bdd,
// so no duplicate binding is declared here.
