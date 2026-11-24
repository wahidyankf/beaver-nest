import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import { waitForRoomReady } from "../support/family-chat-resume";
import { ensureAtLeast } from "../support/family-chat-seeding";
import {
  anyMenuItemDisabled,
  expectMenuOpenFor,
  focusedMessageId,
  focusedRole,
  liveRegionText,
  MENU,
  messageById,
  openMenuItems,
  openMenuWithKeyboard,
  postMessage,
  pressAndHold,
  REPLY_STRIP,
  scenario,
  uniqueBody,
  waitForMessage,
} from "../support/family-chat-reply";
import {
  ensureRoomOpen,
  requireIdentity,
  seedOtherMemberMessage,
} from "../support/family-chat-reply-room";

// The action-menu and composer-strip half of family_chat.feature's reply
// rules, in a real browser. The frontend Vitest+Gherkin harness proves the
// same decisions logically against the production modules; what it cannot do
// is produce a real hold gesture or hold real DOM focus -- which is what each
// of these scenarios is tagged `@integration-exempt` for. Quote rendering,
// the jump, and the history's tab stop are in
// `family-chat-reply-reading.steps.ts`.

const { Given, Then, When } = createBdd();

// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: A committed message offers both actions
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: A fine-pointer Enter send keeps keyboard focus in the Family composer
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: Choosing Reply puts the target above the message input
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: Closing the menu returns focus to the message it came from
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: Only one menu is open at a time
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: The actions control has an accessible name
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: The reply target does not survive a reload

// --- Opening the menu -----------------------------------------------------

Given(
  "a visitor opens {string} with at least one committed message",
  async ({ page }, _route: string) => {
    await ensureRoomOpen(page);
    await ensureAtLeast(page, 1);
    scenario.targetBody = uniqueBody("Menu target");
    scenario.targetId = await postMessage(page, scenario.targetBody);
    await waitForMessage(page, scenario.targetId);
  },
);

When(
  "the visitor presses and holds for {int} milliseconds on that message",
  async ({ page }, holdMs: number) => {
    await pressAndHold(page, scenario.targetId, holdMs);
  },
);

When(
  "the visitor opens the browser context menu on that message",
  async ({ page }) => {
    await messageById(page, scenario.targetId).click({ button: "right" });
  },
);

// The actions control is visible on every pointer and needs no hover (family_chat.feature, "The actions control is
// visible and large enough to press"), so this entry point presses it on each project.
When(
  "the visitor activates the actions control on that message",
  async ({ page }) => {
    const more = messageById(page, scenario.targetId).locator(
      '[data-role="family-chat-message-more"]',
    );
    await more.click();
  },
);

When(
  "the visitor moves focus to the message and presses Enter on that message",
  async ({ page }) => {
    await openMenuWithKeyboard(page, scenario.targetId);
  },
);

Then("the message action menu opens for that message", async ({ page }) => {
  await expectMenuOpenFor(page, scenario.targetId);
});

Then("keyboard focus is inside the menu", async ({ page }) => {
  await expect
    .poll(() =>
      page.evaluate(
        (selector) =>
          document.querySelector(selector)?.contains(document.activeElement) ??
          false,
        MENU,
      ),
    )
    .toBe(true);
});

// --- Closing the menu -----------------------------------------------------

Given(
  "the message action menu is open for a committed message",
  async ({ page }) => {
    await ensureRoomOpen(page);
    scenario.targetBody = uniqueBody("Escape target");
    scenario.targetId = await postMessage(page, scenario.targetBody);
    await waitForMessage(page, scenario.targetId);
    await openMenuWithKeyboard(page, scenario.targetId);
    await expectMenuOpenFor(page, scenario.targetId);
  },
);

When("the visitor presses Escape", async ({ page }) => {
  await page.keyboard.press("Escape");
});

Then("the menu closes", async ({ page }) => {
  await expect(page.locator(MENU)).toHaveAttribute("hidden", /.*/u);
});

Then("keyboard focus is on that same message", async ({ page }) => {
  await expect.poll(() => focusedMessageId(page)).toBe(scenario.targetId);
});

// --- One menu at a time ---------------------------------------------------

Given(
  "the message action menu is open for one committed message",
  async ({ page }) => {
    await ensureRoomOpen(page);
    scenario.targetId = await postMessage(page, uniqueBody("First menu"));
    scenario.secondTargetId = await postMessage(
      page,
      uniqueBody("Second menu"),
    );
    await waitForMessage(page, scenario.secondTargetId);
    await openMenuWithKeyboard(page, scenario.targetId);
    await expectMenuOpenFor(page, scenario.targetId);
  },
);

When("the visitor opens the menu on a different message", async ({ page }) => {
  await openMenuWithKeyboard(page, scenario.secondTargetId);
});

Then("only the second message has an open menu", async ({ page }) => {
  await expectMenuOpenFor(page, scenario.secondTargetId);
  // One host element exists at all, so "only one" is a property of the DOM
  // rather than of the test's patience.
  await expect(page.locator(MENU)).toHaveCount(1);
});

// --- What the menu offers -------------------------------------------------

When("the visitor opens the action menu on that message", async ({ page }) => {
  await openMenuWithKeyboard(page, scenario.targetId);
  await expectMenuOpenFor(page, scenario.targetId);
});

Then(
  "the menu offers exactly {string} and {string}",
  async ({ page }, first: string, second: string) => {
    await expect(openMenuItems(page)).toHaveText([first, second]);
  },
);

Then("both actions are available", async ({ page }) => {
  expect(await anyMenuItemDisabled(page)).toBe(false);
});

// --- Choosing Reply -------------------------------------------------------

Given(
  "the visitor opens the action menu on a message from {string} reading {string}",
  async ({ page, browser }, _sender: string, body: string) => {
    await ensureRoomOpen(page);
    scenario.targetBody = body;
    // The feature names the sender "Ayah"; the suite seeds the message from
    // a synthetic identity instead, per the test-data Iron Rule. The name
    // the strip must carry is therefore that identity's, known here rather
    // than read back off the strip the assertion is judging.
    scenario.targetSender = requireIdentity().child.username;
    scenario.targetId = await seedOtherMemberMessage(page, browser, body);
    await openMenuWithKeyboard(page, scenario.targetId);
    await expectMenuOpenFor(page, scenario.targetId);
  },
);

When("the visitor chooses {string}", async ({ page }, label: string) => {
  await openMenuItems(page).filter({ hasText: label }).first().click();
});

Then(
  "the composer shows a reply strip naming {string}",
  async ({ page }, _name: string) => {
    const strip = page.locator(REPLY_STRIP);
    await expect(strip).not.toHaveAttribute("hidden", /.*/u);
    // "Naming" is the claim: `Replying to` alone would pass on a strip that
    // named the wrong member, or no one.
    await expect(
      strip.locator('[data-role="family-chat-reply-strip-name"]'),
    ).toHaveText(`Replying to ${scenario.targetSender}`);
  },
);

Then("the strip shows the text of that message", async ({ page }) => {
  await expect(
    page.locator('[data-role="family-chat-reply-strip-preview"]'),
  ).toContainText(scenario.targetBody.slice(0, 40));
});

Then("keyboard focus is in the message input", async ({ page }) => {
  await expect.poll(() => focusedRole(page)).toBe("family-chat-message-input");
});

Then(
  "the room announces that the visitor is replying to {string}",
  async ({ page }, _name: string) => {
    await expect
      .poll(() => liveRegionText(page))
      .toContain(`Replying to ${scenario.targetSender}`);
  },
);

// --- The strip does not survive a reload ---------------------------------

Given("the composer shows a reply strip", async ({ page }) => {
  await ensureRoomOpen(page);
  scenario.targetBody = uniqueBody("Strip target");
  scenario.targetId = await postMessage(page, scenario.targetBody);
  await waitForMessage(page, scenario.targetId);
  await openMenuWithKeyboard(page, scenario.targetId);
  await openMenuItems(page).filter({ hasText: "Reply" }).first().click();
  await expect(page.locator(REPLY_STRIP)).not.toHaveAttribute("hidden", /.*/u);
});

Then("no reply strip is shown", async ({ page }) => {
  await waitForRoomReady(page);
  await expect(page.locator(REPLY_STRIP)).toHaveAttribute("hidden", /.*/u);
});
