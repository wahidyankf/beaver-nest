import { expect, type Page } from "@playwright/test";
import { createBdd } from "playwright-bdd";

// Family Chat bindings for the message box keys and the phone layout budget of family_chat.feature (ADR 005). The
// Vitest bindings prove the key handler and the declared CSS; these press real keys in Chromium and read the rendered
// boxes. The shared hint, pointer and light-appearance steps live in chat-ui-consistency.steps.ts.

import { measureFamilyRoom, settle } from "../support/chat-ui-steps";

const { Then, When } = createBdd();

const COMPOSER_INPUT = ".family-chat-message-input";
const MESSAGE = '[data-role="family-chat-message"]';

// The message count before a key press, so a Then can tell whether that press sent anything.
let sentBefore = 0;

// The draft each page typed, so "a new line after its draft" compares with what this scenario typed.
const familyDraftOf = new WeakMap<Page, string>();

When(
  "the visitor types {string} and presses {string} in the family composer",
  async ({ page }, text: string, name: string) => {
    familyDraftOf.set(page, text);
    const input = page.locator(COMPOSER_INPUT);
    sentBefore = await page.locator(MESSAGE).count();
    await input.fill(text);
    await input.press(name);
  },
);

Then(
  "the family room sends {int} messages",
  async ({ page }, sends: number) => {
    // A send shows at once as a message row, pending or sent, so the row count is what a send changes.
    if (sends === 0) {
      await settle(page);
      expect(await page.locator(MESSAGE).count()).toBe(sentBefore);
      return;
    }
    await expect
      .poll(() => page.locator(MESSAGE).count(), { timeout: 10_000 })
      .toBe(sentBefore + sends);
  },
);

Then("the family composer shows {string}", async ({ page }, shown: string) => {
  const input = page.locator(COMPOSER_INPUT);
  if (shown === "an empty box") {
    await expect(input).toHaveValue("");
    return;
  }
  if (shown === "a new line after its draft") {
    const draft = familyDraftOf.get(page);
    expect(draft, "the scenario typed no draft").toBeDefined();
    await expect(input).toHaveValue(`${draft}\n`);
    return;
  }
  throw new Error(`unknown box state ${shown}`);
});

Then("nothing is sent yet", async ({ page }) => {
  await settle(page);
  expect(await page.locator(MESSAGE).count()).toBe(sentBefore);
});

When(
  "the visitor confirms a composition with Enter in the family composer",
  async ({ page }) => {
    sentBefore = await page.locator(MESSAGE).count();
    // A key press that confirms an IME composition carries isComposing, and the room must not send on it.
    await page.locator(COMPOSER_INPUT).dispatchEvent("keydown", {
      key: "Enter",
      isComposing: true,
    });
  },
);

When(
  "the visitor confirms a composition with keyCode 229 in the family composer",
  async ({ page }) => {
    sentBefore = await page.locator(MESSAGE).count();
    // Safari's composition Enter: keyCode 229 with isComposing false. The keyboard API cannot set keyCode, so the event is
    // dispatched with it; the room must not send on it.
    await page
      .locator(COMPOSER_INPUT)
      .dispatchEvent("keydown", { key: "Enter", keyCode: 229 });
  },
);

When("the visitor holds Enter in the family composer", async ({ page }) => {
  sentBefore = await page.locator(MESSAGE).count();
  // The second keydown of a held key is an auto-repeat in Chromium. The first sends; the repeat must send nothing more.
  await page.keyboard.down("Enter");
  await page.keyboard.down("Enter");
  await page.keyboard.up("Enter");
  await settle(page);
});

Then(
  "the composer holds the draft {string}",
  async ({ page }, draft: string) => {
    await expect(page.locator(COMPOSER_INPUT)).toHaveValue(draft);
  },
);

When(
  "the visitor presses Shift+Enter with an empty draft",
  async ({ page }) => {
    sentBefore = await page.locator(MESSAGE).count();
    await page.locator(COMPOSER_INPUT).press("Shift+Enter");
  },
);

Then(
  "the history takes at least {int} percent of the screen with an empty draft",
  async ({ page }, percent: number) => {
    const measure = await measureFamilyRoom(page);
    expect(
      measure.conversation,
      `the history is ${measure.conversation} px of ${measure.height} px`,
    ).toBeGreaterThanOrEqual((percent / 100) * measure.height);
  },
);

// The space the header and the composer take, in CSS pixels (chat.feature, the typical Family Chat phone view).
Then(
  "the header and the composer take at most {int} pixels outside the history",
  async ({ page }, limit: number) => {
    const { space } = await measureFamilyRoom(page);
    expect(
      space,
      `the space that is not history is ${space} px`,
    ).toBeLessThanOrEqual(limit);
  },
);
