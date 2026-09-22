import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import { waitForRoomReady } from "../support/family-chat-resume";
import {
  asAnotherMember,
  focusedMessageId,
  loadOlderUntilRendered,
  messageById,
  postFiller,
  postMessage,
  QUOTE,
  scenario,
  uniqueBody,
  waitForMessage,
} from "../support/family-chat-reply";
import {
  ensureRoomOpen,
  replyAsAnotherMember,
  requireIdentity,
} from "../support/family-chat-reply-room";

// The reading half of family_chat.feature's reply rules: how a quote reaches
// the visitor on each arrival path, and the bounded jump back to what it
// quotes. Split from `family-chat-reply.steps.ts` purely to stay under this
// project's max-lines lint budget; the keyboard journey and the tab stop are
// in `family-chat-reply-keyboard.steps.ts`.

const { Given, Then, When } = createBdd();

// --- Quotes on every arrival path ----------------------------------------

Given(
  "another member has replied to one of the visitor's messages",
  async ({ page, browser, $testInfo }) => {
    await ensureRoomOpen(page, $testInfo);
    scenario.targetBody = uniqueBody("Quoted original");
    scenario.targetId = await postMessage(page, scenario.targetBody);
    await waitForMessage(page, scenario.targetId);
    scenario.replyBody = uniqueBody("Quoting reply");
    scenario.replyId = await replyAsAnotherMember(
      browser,
      scenario.replyBody,
      scenario.targetId,
    );
  },
);

When(
  "the reply reaches the visitor through the first history page",
  async ({ page }) => {
    await page.reload();
    await waitForRoomReady(page);
    await waitForMessage(page, scenario.replyId);
  },
);

When(
  "the reply reaches the visitor through an older history page",
  async ({ page, browser }) => {
    // Push the reply out of the newest page, then walk back to it the way a
    // reader would -- through the room's own "load older" path, not by
    // re-querying for it.
    await asAnotherMember(browser, requireIdentity(), (other) =>
      postFiller(other, 55, "Filler"),
    );
    await page.reload();
    await waitForRoomReady(page);
    await loadOlderUntilRendered(page, scenario.replyId);
  },
);

When(
  "the reply reaches the visitor through the live subscription",
  async ({ page }) => {
    // The room was already open and subscribed when the reply committed, so
    // this arrival is the socket's, not a fetch's.
    await waitForMessage(page, scenario.replyId);
  },
);

When(
  "the reply reaches the visitor through reconnect catch-up after a dropped socket",
  async ({ page, browser }) => {
    await page.evaluate(() => window.dispatchEvent(new Event("offline")));
    scenario.replyBody = uniqueBody("Catch-up reply");
    scenario.replyId = await replyAsAnotherMember(
      browser,
      scenario.replyBody,
      scenario.targetId,
    );
    await page.evaluate(() => window.dispatchEvent(new Event("online")));
    await waitForMessage(page, scenario.replyId);
  },
);

Then(
  "the reply renders a quote naming the original sender",
  async ({ page }) => {
    await expect(
      messageById(page, scenario.replyId).locator(QUOTE),
    ).toBeVisible();
  },
);

Then("the quote shows the original message text", async ({ page }) => {
  await expect(
    messageById(page, scenario.replyId).locator(QUOTE),
  ).toContainText(scenario.targetBody.slice(0, 40));
});

// --- Jumping to the original ---------------------------------------------

Given(
  "a reply and the message it quotes are both loaded",
  async ({ page, browser, $testInfo }) => {
    await ensureRoomOpen(page, $testInfo);
    scenario.targetBody = uniqueBody("Jump original");
    scenario.targetId = await postMessage(page, scenario.targetBody);
    scenario.replyBody = uniqueBody("Jump reply");
    scenario.replyId = await replyAsAnotherMember(
      browser,
      scenario.replyBody,
      scenario.targetId,
    );
    await page.reload();
    await waitForRoomReady(page);
    await waitForMessage(page, scenario.replyId);
    await waitForMessage(page, scenario.targetId);
  },
);

Given(
  "a reply quotes a message two older pages above the loaded window",
  async ({ page, browser, $testInfo }) => {
    await ensureRoomOpen(page, $testInfo);
    scenario.targetBody = uniqueBody("Distant original");
    scenario.targetId = await postMessage(page, scenario.targetBody);
    await asAnotherMember(browser, requireIdentity(), (other) =>
      postFiller(other, 110, "Distance"),
    );
    scenario.replyBody = uniqueBody("Distant reply");
    scenario.replyId = await replyAsAnotherMember(
      browser,
      scenario.replyBody,
      scenario.targetId,
    );
    await page.reload();
    await waitForRoomReady(page);
    await waitForMessage(page, scenario.replyId);
    // The premise of the scenario, asserted rather than assumed: the target
    // really is outside the loaded window.
    await expect(messageById(page, scenario.targetId)).toHaveCount(0);
  },
);

When("the visitor activates the quote", async ({ page }) => {
  await messageById(page, scenario.replyId).locator(QUOTE).click();
});

Then("the history scrolls to the original message", async ({ page }) => {
  await expect(messageById(page, scenario.targetId)).toBeInViewport();
});

Then("that message is highlighted", async ({ page }) => {
  await expect(messageById(page, scenario.targetId)).toHaveAttribute(
    "data-jump-highlight",
    /.+/u,
  );
});

Then("keyboard focus moves to it", async ({ page }) => {
  await expect.poll(() => focusedMessageId(page)).toBe(scenario.targetId);
});

Then(
  "older pages are loaded until the original is present",
  async ({ page }) => {
    await expect(messageById(page, scenario.targetId)).toHaveCount(1, {
      timeout: 20_000,
    });
  },
);

Then("the history scrolls to it", async ({ page }) => {
  await expect(messageById(page, scenario.targetId)).toBeInViewport();
});

// --- Reduced motion -------------------------------------------------------

Given("the visitor's system requests reduced motion", async ({ page }) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
});

When(
  "the visitor jumps to a quoted message",
  async ({ page, browser, $testInfo }) => {
    await ensureRoomOpen(page, $testInfo);
    scenario.targetBody = uniqueBody("Reduced motion original");
    scenario.targetId = await postMessage(page, scenario.targetBody);
    scenario.replyBody = uniqueBody("Reduced motion reply");
    scenario.replyId = await replyAsAnotherMember(
      browser,
      scenario.replyBody,
      scenario.targetId,
    );
    await page.reload();
    await waitForRoomReady(page);
    await waitForMessage(page, scenario.replyId);
    await messageById(page, scenario.replyId).locator(QUOTE).click();
  },
);

Then("the message is marked without an animated pulse", async ({ page }) => {
  const target = messageById(page, scenario.targetId);
  await expect(target).toHaveAttribute("data-jump-highlight", /.+/u);
  // The computed style under a real media query, which is the only place
  // `prefers-reduced-motion` actually resolves.
  const animationName = await target.evaluate(
    (element) => globalThis.getComputedStyle(element).animationName,
  );
  expect(animationName).toBe("none");
});
