import { expect, type Locator, type Page } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import {
  DRAWN_FIGURE,
  holdDiagramEngine,
  latestReply,
  MARKED_DIAGRAM,
  openChatAsAdmin,
  sendAndWaitForReply,
} from "../support/codex-diagrams";

// The Codex conversation rule of chat.feature that follows the newest message, and the layout scenarios that keep
// the conversation on screen at each size. Each Then reads a rendered box or a computed style in real Chromium; the
// Vitest binding (apps/bnest-app/assets/test/behaviour/codex_follow.steps.ts) proves the follow contract on a model.

const { Given, Then, When } = createBdd();

const CONVERSATION = "#chat-conversation";
const TEXTAREA = "#chat-composer-form textarea";
const SEND = "#chat-composer-form button[type=submit]";
const WIDE_REPLY = "Show a wide table, a long code block and the logo";
// The engine is held this long, so the marked diagram is still undrawn when the page is measured.
const NOT_YET_DRAWN_MS = 8000;
// The conversation's size just before the diagram draws: the draw must make it taller.
let beforeDraw: { scrollHeight: number; gap: number } | undefined;

/** The reader's place: the distance from the newest content, and how far the conversation is scrolled. */
function positionOf(page: Page) {
  return page.locator(CONVERSATION).evaluate((element) => ({
    top: element.scrollTop,
    gap: element.scrollHeight - element.scrollTop - element.clientHeight,
  }));
}

async function boxOf(locator: Locator, label: string) {
  const box = await locator.boundingBox();
  if (box === null) throw new Error(`${label} has no box`);
  return box;
}

/** Three long replies, so the conversation is taller than a phone or a short window. */
async function fillConversation(page: Page): Promise<void> {
  // Each reply is awaited before the next is sent, so the prompts run in order.
  await [WIDE_REPLY, "Format a sample reply", WIDE_REPLY].reduce(
    async (previous, prompt) => {
      await previous;
      await sendAndWaitForReply(page, prompt);
    },
    Promise.resolve(),
  );
}

/** The conversation's full height, and the distance the reader is above its newest content. */
function sizeOf(page: Page) {
  return page.locator(CONVERSATION).evaluate((element) => ({
    scrollHeight: element.scrollHeight,
    gap: element.scrollHeight - element.scrollTop - element.clientHeight,
  }));
}

/** The newest reply's bottom edge is in view, and the reader is at the bottom of a conversation taller than its box. */
async function expectNewestInView(page: Page): Promise<void> {
  // A picture changes the height once it has decoded, so the measure waits for every picture in the conversation.
  await expect
    .poll(() =>
      page
        .locator(`${CONVERSATION} img`)
        .evaluateAll((images) =>
          images.every(
            (image) =>
              (image as HTMLImageElement).complete &&
              (image as HTMLImageElement).naturalWidth > 0,
          ),
        ),
    )
    .toBe(true);
  const overflow = await page
    .locator(CONVERSATION)
    .evaluate((element) => element.scrollHeight - element.clientHeight);
  expect(
    overflow,
    "the conversation does not overflow, so the reader cannot be at its bottom",
  ).toBeGreaterThan(0);
  await expect
    .poll(async () => (await positionOf(page)).gap)
    .toBeLessThanOrEqual(2);
  const [conversation, reply] = await Promise.all([
    boxOf(page.locator(CONVERSATION), "The conversation"),
    boxOf(latestReply(page), "The newest reply"),
  ]);
  expect(reply.y + reply.height).toBeLessThanOrEqual(
    conversation.y + conversation.height + 1,
  );
  expect(reply.y + reply.height).toBeGreaterThan(conversation.y);
}

Given(
  "the visitor has a Codex conversation with older replies",
  async ({ page }) => {
    await openChatAsAdmin(page);
    await fillConversation(page);
  },
);

Given(
  "the visitor is at the bottom of the Codex conversation",
  async ({ page }) => {
    await openChatAsAdmin(page);
    await fillConversation(page);
    await expectNewestInView(page);
  },
);

Given(
  "the visitor has sent a message and Codex is still streaming its reply",
  async ({ page }) => {
    await openChatAsAdmin(page);
    await fillConversation(page);
    // The reply holds for ten seconds, so it is still streaming while the reader scrolls.
    const replies = page.locator("[data-role=assistant-message]");
    const before = await replies.count();
    await page.locator(TEXTAREA).fill("Stream unfinished Markdown");
    await page.locator(SEND).click();
    await expect(replies).toHaveCount(before + 1, { timeout: 20_000 });
    await expect(latestReply(page)).toHaveAttribute("data-streaming", "true");
  },
);

Given(
  "the visitor has scrolled up in the Codex conversation",
  async ({ page }) => {
    await page.locator(CONVERSATION).evaluate((element) => {
      element.scrollTop = 0;
    });
    await expect.poll(async () => (await positionOf(page)).top).toBe(0);
  },
);

Given(
  "a Codex reply holds a diagram that is not yet drawn",
  async ({ page }) => {
    await openChatAsAdmin(page);
    await holdDiagramEngine(page.context(), NOT_YET_DRAWN_MS);
    await fillConversation(page);
    await sendAndWaitForReply(page, "Show a wide flowchart");
    // The reply holds the diagram's source and the engine has not drawn it yet, so the page is measured as it is now.
    await expect(latestReply(page).locator(MARKED_DIAGRAM)).toHaveCount(1);
    await expect(latestReply(page).locator(DRAWN_FIGURE)).toHaveCount(0);
    await expectNewestInView(page);
    beforeDraw = await sizeOf(page);
  },
);

Given("the conversation holds three long Codex replies", async ({ page }) => {
  await fillConversation(page);
});

When("the visitor opens the Codex chat page", async ({ page }) => {
  await page.goto("/chat");
  await expect(page.locator("[data-phx-main]")).toHaveClass(/phx-connected/u);
  await expect(latestReply(page)).toBeAttached();
});

When(
  "the visitor sends a message and Codex streams the reply",
  async ({ page }) => {
    await sendAndWaitForReply(page, WIDE_REPLY);
  },
);

When("Codex streams more of the reply", async ({ page }) => {
  await expect(latestReply(page)).toHaveAttribute("data-streaming", "false", {
    timeout: 40_000,
  });
});

// The one step both rooms bind: a drawn figure is the same element in Codex replies and in Family Chat messages.
When("the diagram is drawn", async ({ page }) => {
  await expect
    .poll(
      () => page.locator('figure[data-bnest-diagram-state="drawn"]').count(),
      { timeout: 30_000 },
    )
    .toBeGreaterThan(0);
});

Then(
  "the newest reply is at the bottom of the conversation",
  async ({ page }) => {
    await expectNewestInView(page);
  },
);

Then("the newest part of the reply is in view", async ({ page }) => {
  await expectNewestInView(page);
});

Then("the newest reply is in view above the composer", async ({ page }) => {
  // The draw is what grew the conversation (the picture is taller than the source it replaced), and the reader stayed
  // at its bottom through it.
  if (beforeDraw === undefined)
    throw new Error(
      "the conversation was not measured before the diagram drew",
    );
  const after = await sizeOf(page);
  expect(
    after.scrollHeight,
    "the draw did not grow the conversation",
  ).toBeGreaterThan(beforeDraw.scrollHeight);
  beforeDraw = undefined;
  await expectNewestInView(page);
  const [reply, composer] = await Promise.all([
    boxOf(latestReply(page), "The newest reply"),
    boxOf(page.locator("#chat-composer-form"), "The composer"),
  ]);
  expect(reply.y + reply.height).toBeLessThanOrEqual(composer.y + 1);
});

Then(
  "the visitor's position in the conversation does not change",
  async ({ page }) => {
    // The reader scrolled to the top before the reply streamed; the reply's growth must not move them.
    const overflow = await page
      .locator(CONVERSATION)
      .evaluate((element) => element.scrollHeight - element.clientHeight);
    expect(
      overflow,
      "the conversation does not overflow, so a scroll position means nothing",
    ).toBeGreaterThan(0);
    await expect
      .poll(async () => (await positionOf(page)).top)
      .toBeLessThanOrEqual(1);
  },
);
