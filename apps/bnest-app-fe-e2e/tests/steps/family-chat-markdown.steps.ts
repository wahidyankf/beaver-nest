import { expect, type Page } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import {
  messageById,
  openMenuWithKeyboard,
} from "../support/family-chat-gestures";
import {
  openMenuItems,
  postMessage,
  asAnotherMember,
} from "../support/family-chat-reply";
import {
  expectCommitted,
  interfereWithSends,
  sendThroughComposer,
} from "../support/family-chat-delivery";
import { waitForRoomSubscribed } from "../support/family-chat-socket";
import { instanceIdentities } from "../support/instance-identities";
import {
  serveRemoteImages,
  setTargetMessage,
  TWO_LINES,
  targetBody,
  targetIdOf,
  targetMessage,
  WIDE_MESSAGE,
} from "../support/family-chat-markdown";

// family_chat.feature's "Formatted messages" rule, in a real browser against the served origin.
// Another member's messages are sent through their own session (`asAnotherMember`), so a message's
// author is a real second member; the visitor's own sends go through the composer.
//
// A Then waits for the message's server copy to replace its pending one before it reads the body,
// so each check reads what the room rendered for the committed message.

const { Given, When, Then } = createBdd();

/** Waits until the target message's committed copy is rendered, then the body is what a member sees. */
async function committedTarget(page: Page): Promise<void> {
  await expect(targetMessage(page)).toHaveAttribute(
    "data-delivery-state",
    "committed",
    { timeout: 20_000 },
  );
}

Given(
  "{word} has sent the family chat message {string}",
  async ({ page, browser }, _sender: string, body: string) => {
    await serveRemoteImages(page.context());
    const id = await asAnotherMember(browser, instanceIdentities(), (other) =>
      postMessage(other, body),
    );
    setTargetMessage(page, id);
  },
);

Given(
  "{word} has sent a message typed on two lines",
  async ({ page, browser }, _sender: string) => {
    await serveRemoteImages(page.context());
    const id = await asAnotherMember(browser, instanceIdentities(), (other) =>
      postMessage(other, TWO_LINES),
    );
    setTargetMessage(page, id);
  },
);

Given(
  "{word} has sent a wide image and a wide table",
  async ({ page, browser }, _sender: string) => {
    await serveRemoteImages(page.context());
    const id = await asAnotherMember(browser, instanceIdentities(), (other) =>
      postMessage(other, WIDE_MESSAGE),
    );
    setTargetMessage(page, id);
  },
);

// A send that never gets an answer, so the row stays pending (shown "Sending") while the scenario reads it.
// Registered after the composer's own two-second delay, whose fallback reaches this hold.
Given(
  "the server holds the visitor's next message unanswered",
  async ({ page }) => {
    await interfereWithSends(page, "hold");
  },
);

When(
  "{word} sends the family chat message {string} while the visitor watches",
  async ({ page, browser }, _sender: string, body: string) => {
    await waitForRoomSubscribed(page);
    const id = await asAnotherMember(browser, instanceIdentities(), (other) =>
      postMessage(other, body),
    );
    setTargetMessage(page, id);
    await expect(messageById(page, id)).toHaveCount(1, { timeout: 15_000 });
  },
);

When(
  "the visitor replies to the message with {string}",
  async ({ page }, body: string) => {
    const target = targetIdOf(page);
    if (!target) throw new Error("no message was named to reply to");
    await openMenuWithKeyboard(page, target);
    await openMenuItems(page).filter({ hasText: "Reply" }).first().click();
    await sendThroughComposer(page, body);
    setTargetMessage(page, await expectCommitted(page, body));
  },
);

Then("the message shows {string} in bold", async ({ page }, text: string) => {
  await committedTarget(page);
  const strong = await targetBody(page).locator("strong").allTextContents();
  expect(strong, "the bold text of the message").toContain(text);
});

Then(
  "the message links {string} to {string}",
  async ({ page }, text: string, address: string) => {
    await committedTarget(page);
    const links = await targetBody(page)
      .locator("a[href]")
      .evaluateAll((elements) =>
        elements.map((element) => ({
          text: element.textContent,
          href: element.getAttribute("href"),
        })),
      );
    expect(links).toContainEqual({ text, href: address });
  },
);

Then("the message shows the text {string}", async ({ page }, text: string) => {
  await committedTarget(page);
  await expect(targetBody(page)).toContainText(text);
});

Then("the message contains no script or image element", async ({ page }) => {
  await committedTarget(page);
  await expect(targetBody(page).locator("script, img")).toHaveCount(0);
});

Then(
  "the message shows {string} as typed text with no formatting",
  async ({ page }, text: string) => {
    const body = targetBody(page);
    await expect(body).toHaveAttribute("data-body-format", "text", {
      timeout: 20_000,
    });
    await expect(body).toHaveText(text);
    await expect(body.locator("*")).toHaveCount(0);
  },
);

Then("the message keeps its two lines on separate lines", async ({ page }) => {
  await committedTarget(page);
  const body = targetBody(page);
  await expect(body.locator("br")).toHaveCount(1);
  await expect(body).toContainText("First line");
  await expect(body).toContainText("Second line");
});

Then(
  "the message shows the image {string} from {string}",
  async ({ page }, alt: string, address: string) => {
    await committedTarget(page);
    const shown = targetBody(page).locator(`img[alt="${alt}"]`);
    await expect(shown).toHaveCount(1);
    await expect(shown).toHaveAttribute("src", address);
    await expect
      .poll(() =>
        shown.evaluate((element: HTMLImageElement) => element.naturalWidth),
      )
      .toBeGreaterThan(0);
  },
);

Then("the message shows no image", async ({ page }) => {
  await committedTarget(page);
  await expect(targetBody(page).locator("img")).toHaveCount(0);
});

Then("the links in the message open in a new tab", async ({ page }) => {
  await committedTarget(page);
  const links = targetBody(page).locator("a[href]");
  await expect(links).not.toHaveCount(0);
  const attributes = await links.evaluateAll((elements) =>
    elements.map((element) => ({
      target: element.getAttribute("target"),
      rel: element.getAttribute("rel") ?? "",
    })),
  );
  for (const attribute of attributes) {
    expect(attribute.target).toBe("_blank");
    expect(attribute.rel).toContain("noopener");
  }
});

Then("the message fits the phone width", async ({ page }) => {
  await committedTarget(page);
  const viewport = await page.evaluate(() => window.innerWidth);
  expect(viewport, "the viewport width").toBe(390);
  const bubble = targetMessage(page).locator(".family-chat-message-bubble");
  const [bubbleScroll, bubbleClient] = await bubble.evaluate((element) => [
    element.scrollWidth,
    element.clientWidth,
  ]);
  expect(bubbleScroll, "bubble scroll width").toBeLessThanOrEqual(bubbleClient);
  const [pageScroll, pageClient] = await page.evaluate(() => [
    document.documentElement.scrollWidth,
    document.documentElement.clientWidth,
  ]);
  expect(pageScroll, "page scroll width").toBeLessThanOrEqual(pageClient);
});

Then("the image in the message loads", async ({ page }) => {
  await committedTarget(page);
  const image = targetBody(page).locator("img").first();
  await expect(image).toHaveCount(1);
  await expect
    .poll(() =>
      image.evaluate((element: HTMLImageElement) => element.naturalWidth),
    )
    .toBeGreaterThan(0);
});

Then(
  "the reply quotes {string} as plain text",
  async ({ page }, text: string) => {
    await committedTarget(page);
    const preview = targetMessage(page).locator(
      '[data-role="family-chat-message-quote-preview"]',
    );
    await expect(preview).toHaveText(text);
    await expect(preview.locator("*")).toHaveCount(0);
  },
);

Then("the quote contains no link", async ({ page }) => {
  const quote = targetMessage(page).locator(
    '[data-role="family-chat-message-quote"]',
  );
  await expect(quote).toHaveCount(1);
  await expect(quote.locator("a")).toHaveCount(0);
});
