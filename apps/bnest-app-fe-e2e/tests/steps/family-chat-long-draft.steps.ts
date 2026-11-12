import { expect, type Locator } from "@playwright/test";
import { createBdd } from "playwright-bdd";

// The long unbroken draft rows of family_chat.feature (the Rule "Responsive and accessible presentation"). A draft of
// one unbroken address is typed into the Family composer, and each Then measures the rendered boxes in real Chromium.
// These rows are regression guards for the Family layout. They measure the outcome; they do not show which CSS keeps
// it on screen, because no mutation of the declared guards turns them red. The Vitest binding
// (apps/bnest-app/assets/test/behaviour/family_chat_layout.steps.ts) checks the declared guard strings.
// "no horizontal page scroll is present" is the step the Family rule already binds.

const { Then, When } = createBdd();

const ADDRESS_PREFIX = "https://example.com/";

async function boxOf(locator: Locator, label: string) {
  const box = await locator.boundingBox();
  if (box === null) throw new Error(`${label} has no box`);
  return box;
}

When(
  "the visitor types an unbroken {int} character address into the composer",
  async ({ page }, length: number) => {
    const address =
      ADDRESS_PREFIX + "a".repeat(Math.max(0, length - ADDRESS_PREFIX.length));
    await page.locator('[data-role="family-chat-message-input"]').fill(address);
  },
);

Then("the Family room is inside the screen", async ({ page }) => {
  const viewport = page.viewportSize();
  if (viewport === null) throw new Error("the viewport is not set");
  const box = await boxOf(
    page.locator(".family-chat-shell"),
    "the Family room",
  );
  expect(
    box.x >= 0 && box.x + box.width <= viewport.width + 0.5,
    `the Family room spans ${box.x} to ${box.x + box.width} on a ${viewport.width} px screen`,
  ).toBe(true);
});

Then(
  "the Send button is on screen and is not covered by the composer",
  async ({ page }) => {
    const viewport = page.viewportSize();
    if (viewport === null) throw new Error("the viewport is not set");
    const send = page.locator('[data-role="family-chat-send"]');
    const box = await boxOf(send, "the Family Send button");
    expect(
      box.x >= 0 && box.x + box.width <= viewport.width + 0.5,
      `the Send button spans ${box.x} to ${box.x + box.width} on a ${viewport.width} px screen`,
    ).toBe(true);
    // Measured before the trial click below, which scrolls Send into view if it is off screen.
    expect(
      box.y >= 0 && box.y + box.height <= viewport.height + 0.5,
      `the Send button spans ${box.y} to ${box.y + box.height} on a ${viewport.height} px screen height`,
    ).toBe(true);
    // A trial click fails when another element is over Send at its centre, and does not press the button.
    await send.click({ trial: true, timeout: 5_000 });
  },
);
