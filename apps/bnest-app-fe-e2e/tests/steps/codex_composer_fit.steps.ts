import { expect, type Locator, type Page } from "@playwright/test";
import { createBdd } from "playwright-bdd";

// The long unbroken draft rows of chat.feature (the Rule "Codex chat follows the newest message and fits every
// screen"). A draft of one unbroken address is typed into the Codex message box, and each Then measures the rendered
// boxes in real Chromium. The Vitest binding (apps/bnest-app/assets/test/behaviour/codex_layout.steps.ts) proves the
// declared CSS guards that keep these boxes inside the window.

const { Then, When } = createBdd();

const ADDRESS_PREFIX = "https://example.com/";

async function boxOf(locator: Locator, label: string) {
  const box = await locator.boundingBox();
  if (box === null) throw new Error(`${label} has no box`);
  return box;
}

When(
  "the visitor types an unbroken {int} character address into the Codex message box",
  async ({ page }, length: number) => {
    const address =
      ADDRESS_PREFIX + "a".repeat(Math.max(0, length - ADDRESS_PREFIX.length));
    await page.locator('[data-role="chat-composer"]').fill(address);
  },
);

Then("the Codex chat panel is inside the screen", async ({ page }) => {
  const viewport = page.viewportSize();
  if (viewport === null) throw new Error("the viewport is not set");
  const box = await boxOf(page.locator(".chat-panel"), "the Codex chat panel");
  expect(
    box.x >= 0 && box.x + box.width <= viewport.width + 0.5,
    `the Codex chat panel spans ${box.x} to ${box.x + box.width} on a ${viewport.width} px screen`,
  ).toBe(true);
  expect(
    box.width <= viewport.width,
    `the Codex chat panel is ${box.width} px wide`,
  ).toBe(true);
});

Then(
  "the Send button is on screen and is not covered by the message box",
  async ({ page }) => {
    const viewport = page.viewportSize();
    if (viewport === null) throw new Error("the viewport is not set");
    const send = page.locator(".send-button");
    const box = await boxOf(send, "the Send button");
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

Then(
  "the Codex page does not scroll sideways",
  async ({ page }: { page: Page }) => {
    const [scrollWidth, clientWidth] = await page.evaluate(() => [
      document.documentElement.scrollWidth,
      document.documentElement.clientWidth,
    ]);
    expect(
      scrollWidth,
      `the Codex page is ${scrollWidth} px wide on a ${clientWidth} px screen`,
    ).toBeLessThanOrEqual(clientWidth);
  },
);
