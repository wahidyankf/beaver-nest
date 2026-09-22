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

// --- Opening the menu -----------------------------------------------------

Given(
  "a visitor opens {string} with at least one committed message",
  async ({ page, $testInfo }, _route: string) => {
    await ensureRoomOpen(page, $testInfo);
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

When(
  "the visitor activates the actions control revealed on hover on that message",
  async ({ page }) => {
    const message = messageById(page, scenario.targetId);
    const more = message.locator('[data-role="family-chat-message-more"]');
    await message.hover();
    const finePointer = await page.evaluate(
      () => globalThis.matchMedia("(pointer: fine)").matches,
    );
    if (!finePointer) {
      // Tech-doc 005 removes this control entirely on a coarse pointer: a
      // permanently visible control on every bubble is noise where holding
      // the message is already the gesture, and there is no hover to reveal
      // it with. Assert that removal -- the decision this entry point
      // actually makes on this device -- and then open the menu the way this
      // pointer does, so the scenario's Then still judges the menu.
      await expect(more).toBeHidden();
      await pressAndHold(page, scenario.targetId, 500);
      return;
    }
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
  async ({ page, $testInfo }) => {
    await ensureRoomOpen(page, $testInfo);
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
  async ({ page, $testInfo }) => {
    await ensureRoomOpen(page, $testInfo);
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
  async ({ page, browser, $testInfo }, _sender: string, body: string) => {
    await ensureRoomOpen(page, $testInfo);
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

Given("the composer shows a reply strip", async ({ page, $testInfo }) => {
  await ensureRoomOpen(page, $testInfo);
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
