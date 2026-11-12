import { expect, type Locator } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import { latestReply } from "../support/codex-diagrams";

// The Codex chat layout steps of chat.feature: the panel, the composer and its Send button, the conversation's share of
// the screen, and the wide table, code block and logo. Split from codex_follow.steps.ts to stay under its line limit.

const { Then } = createBdd();

const CONVERSATION = "#chat-conversation";
const TEXTAREA = "#chat-composer-form textarea";
const SEND = "#chat-composer-form button[type=submit]";
const PANEL = ".chat-panel";

async function boxOf(locator: Locator, label: string) {
  const box = await locator.boundingBox();
  if (box === null) throw new Error(`${label} has no box`);
  return box;
}

// --- Layout -------------------------------------------------------------------------

Then(
  "the conversation is at least 40 percent of the screen height",
  async ({ page }) => {
    const viewport = page.viewportSize();
    const conversation = await boxOf(
      page.locator(CONVERSATION),
      "The conversation",
    );
    expect(viewport).not.toBeNull();
    expect(conversation.height).toBeGreaterThanOrEqual(
      0.4 * (viewport?.height ?? 0),
    );
  },
);

Then("the Send button is beside the message box", async ({ page }) => {
  const [field, send] = await Promise.all([
    boxOf(page.locator(TEXTAREA), "The message box"),
    boxOf(page.locator(SEND), "The Send button"),
  ]);
  expect(
    Math.abs(send.y + send.height / 2 - (field.y + field.height / 2)),
  ).toBeLessThanOrEqual(field.height / 2);
  expect(send.x).toBeGreaterThanOrEqual(field.x + field.width - 1);
});

Then("the Codex panel is no taller than the window", async ({ page }) => {
  const viewport = page.viewportSize();
  const panel = await boxOf(page.locator(PANEL), "The Codex panel");
  expect(panel.height).toBeLessThanOrEqual((viewport?.height ?? 0) + 1);
});

Then("the conversation scrolls inside the panel", async ({ page }) => {
  await expect(page.locator(CONVERSATION)).toHaveCSS("overflow-y", "auto");
  const overflow = await page
    .locator(CONVERSATION)
    .evaluate((element) => element.scrollHeight - element.clientHeight);
  expect(overflow, "the conversation has nothing to scroll").toBeGreaterThan(0);
  const [panel, conversation] = await Promise.all([
    boxOf(page.locator(PANEL), "The Codex panel"),
    boxOf(page.locator(CONVERSATION), "The conversation"),
  ]);
  expect(conversation.height).toBeLessThan(panel.height);
});

Then(
  "the reply bubble takes at least 80 percent of the conversation width",
  async ({ page }) => {
    const [bubble, conversation] = await Promise.all([
      boxOf(
        latestReply(page).locator("xpath=ancestor::article[1]"),
        "The reply bubble",
      ),
      boxOf(page.locator(CONVERSATION), "The conversation"),
    ]);
    expect(bubble.width).toBeGreaterThanOrEqual(0.8 * conversation.width);
  },
);

Then("the wide table is named {string}", async ({ page }, name: string) => {
  await expect(latestReply(page).locator("table").first()).toHaveAttribute(
    "aria-label",
    name,
  );
});

Then(
  "the wide code block is named {string}",
  async ({ page }, name: string) => {
    const code = latestReply(page).locator("pre").first();
    await expect(code).toHaveAttribute("aria-label", name);
    await expect(code).toHaveAttribute("role", "group");
  },
);

/** The relative luminance of an rgb(r, g, b) colour, as WCAG defines it. */
function luminanceOf(value: string): number {
  const channels = (value.match(/\d+/gu) ?? []).slice(0, 3).map((part) => {
    const channel = Number(part) / 255;
    return channel <= 0.03928
      ? channel / 12.92
      : ((channel + 0.055) / 1.055) ** 2.4;
  });
  const [red = 0, green = 0, blue = 0] = channels;
  return 0.2126 * red + 0.7152 * green + 0.0722 * blue;
}

/** The WCAG contrast ratio of two rgb(r, g, b) colours. */
function contrastOf(first: string, second: string): number {
  const [a, b] = [luminanceOf(first), luminanceOf(second)];
  const light = Math.max(a, b);
  const dark = Math.min(a, b);
  return (light + 0.05) / (dark + 0.05);
}

Then(
  "the repository write toggle text has a contrast ratio of at least 4.5 to 1",
  async ({ page }) => {
    const toggle = page.locator(".repository-write-toggle");
    await expect(toggle).toBeVisible();
    const colors = await toggle.evaluate((element) => {
      const style = getComputedStyle(element);
      return { text: style.color, background: style.backgroundColor };
    });
    expect(contrastOf(colors.text, colors.background)).toBeGreaterThanOrEqual(
      4.5,
    );
  },
);
