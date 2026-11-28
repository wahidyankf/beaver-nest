import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import {
  composerInput,
  openFamilyChatRoom,
  seedFamilyChatScrollOverflow,
  sendAsAnotherMember,
} from "../support/family-chat";
import { type InstanceIdentities } from "../support/instance-identities";

// family_chat.feature's live-region announcement scenarios: a message that
// arrives while scrolled up is announced without moving focus, and a "New
// messages below" button is shown instead of auto-scrolling. Split out of
// family-chat.steps.ts to stay under the repository's 300-line step-file
// budget. The reconnect and scroll-anchor scenarios stay in
// family-chat.steps.ts.

// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: A new message away from the bottom shows "New messages below" instead of scrolling
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: A new message is announced to assistive technology without moving focus from the composer

const { Given, Then, When } = createBdd();

let identity: InstanceIdentities;

Given(
  "a visitor opens {string} with focus in the composer",
  async ({ page }, _route: string) => {
    identity = await openFamilyChatRoom(page);
    // The following scenario needs the visitor to genuinely be scrolled away
    // from the bottom when the remote message arrives (see
    // `seedFamilyChatScrollOverflow`'s comment).
    await seedFamilyChatScrollOverflow(page);
    await composerInput(page).focus();
  },
);

When(
  "another member's message arrives away from the bottom of the scroll position",
  async ({ browser }) => {
    await sendAsAnotherMember(browser, identity, "Arrived while scrolled up");
  },
);

Then("a live-region announcement names the new message", async ({ page }) => {
  await expect(page.getByRole("status")).toContainText(
    "Arrived while scrolled up",
  );
});

Then("focus remains in the composer", async ({ page }) => {
  await expect(composerInput(page)).toBeFocused();
});

Then(
  "{string} is shown instead of auto-scrolling",
  async ({ page }, label: string) => {
    await expect(page.getByRole("button", { name: label })).toBeVisible();
  },
);
