import { expect, type Page } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import { composerInput } from "../support/family-chat";
import {
  attemptsFor,
  delivery,
  expectCommitted,
  sendThroughComposer,
} from "../support/family-chat-delivery";
import { waitForRoomReady } from "../support/family-chat-resume";
import { postAsAnotherMember } from "../support/family-chat-seeding";
import {
  messageById,
  openMenuItems,
  openMenuWithKeyboard,
  postMessage,
  QUOTE,
  REPLY_STRIP,
  scenario,
  uniqueBody,
  waitForMessage,
} from "../support/family-chat-reply";
import {
  ensureRoomOpen,
  requireIdentity,
} from "../support/family-chat-reply-room";

// The rest of family_chat.feature's "Composing a reply" and "Reading a
// reply" rules in a real browser: the strip's shortening, abandoning a
// reply, what a sent reply leaves behind, a reply to a reply, and the jump
// bound.

const { Given, Then, When } = createBdd();

const STRIP_PREVIEW = '[data-role="family-chat-reply-strip-preview"]';
const MESSAGES_PER_PAGE = 50;
const JUMP_PAGE_BOUND = 5;

let firstBody = "";
let olderPageRequests = 0;

function graphemes(text: string): string[] {
  return [...new Intl.Segmenter("en", { granularity: "grapheme" }).segment(text)].map(
    (part) => part.segment,
  );
}

async function chooseReplyOn(page: Page, messageId: string): Promise<void> {
  await openMenuWithKeyboard(page, messageId);
  await openMenuItems(page).filter({ hasText: "Reply" }).first().click();
  await expect(page.locator(REPLY_STRIP)).not.toHaveAttribute("hidden", /.*/u);
}

// --- The strip shortens a long message ------------------------------------

Given(
  "the selected message body is {int} graphemes long",
  async ({ page, $testInfo }, length: number) => {
    await ensureRoomOpen(page, $testInfo);
    // Multi-code-point graphemes throughout, so a cut by code unit or code
    // point would not land where a cut by grapheme does.
    const head = graphemes(uniqueBody("Long"));
    const filler = Array.from(
      { length: length - head.length },
      (_unused, index) => (index % 2 === 0 ? "👩‍👩‍👧" : "é"),
    );
    scenario.targetBody = [...head, ...filler].join("");
    expect(graphemes(scenario.targetBody)).toHaveLength(length);
    scenario.targetId = await postMessage(page, scenario.targetBody);
    await waitForMessage(page, scenario.targetId);
  },
);

When("the reply strip renders it", async ({ page }) => {
  await chooseReplyOn(page, scenario.targetId);
});

Then(
  "at most 160 graphemes are shown before the ellipsis",
  async ({ page }) => {
    const shown = (await page.locator(STRIP_PREVIEW).textContent()) ?? "";
    const kept = graphemes(shown.replace(/…$/u, ""));
    expect(kept.length).toBeGreaterThan(0);
    expect(kept.length).toBeLessThanOrEqual(160);
    expect(scenario.targetBody.startsWith(kept.join("").trimEnd())).toBe(true);
  },
);

Then("the shown text ends with an ellipsis", async ({ page }) => {
  await expect(page.locator(STRIP_PREVIEW)).toHaveText(/…$/u);
});

// --- Abandoning a reply -----------------------------------------------------

Given(
  "the visitor has typed {string} without sending",
  async ({ page }, text: string) => {
    // Choosing Reply put focus in the input; the member just types.
    await expect(composerInput(page)).toBeFocused();
    await page.keyboard.type(text);
  },
);

When(
  "the visitor activates the cancel control on the strip",
  async ({ page }) => {
    await page
      .locator('[data-role="family-chat-reply-strip-cancel"]')
      .click();
  },
);

When("the visitor presses Escape in the message input", async ({ page }) => {
  await expect(composerInput(page)).toBeFocused();
  await page.keyboard.press("Escape");
});

Then("the reply strip is gone", async ({ page }) => {
  await expect(page.locator(REPLY_STRIP)).toHaveAttribute("hidden", /.*/u);
});

Then(
  "the message input still holds {string}",
  async ({ page }, text: string) => {
    await expect(composerInput(page)).toHaveValue(text);
  },
);

// --- Sending clears the target ---------------------------------------------

When("the visitor sends the message", async ({ page }) => {
  await sendThroughComposer(page, uniqueBody("Sent reply"));
  firstBody = delivery.body;
  await expectCommitted(page, firstBody);
  expect(attemptsFor(page, firstBody)[0]?.replyToMessageId).toBe(
    scenario.targetId,
  );
});

Then(
  "the next message the visitor sends carries no reply target",
  async ({ page }) => {
    await sendThroughComposer(page, uniqueBody("Plain follow-up"));
    const committedId = await expectCommitted(page, delivery.body);
    expect(
      attemptsFor(page, delivery.body).map(
        (attempt) => attempt.replyToMessageId,
      ),
    ).toEqual([null]);
    await expect(messageById(page, committedId).locator(QUOTE)).toHaveCount(0);
  },
);

// --- A reply to a reply -----------------------------------------------------

Given("message A exists", async ({ page, $testInfo }) => {
  await ensureRoomOpen(page, $testInfo);
  scenario.targetBody = uniqueBody("Message A");
  scenario.targetId = await postMessage(page, scenario.targetBody);
});

Given("message B is a reply to A", async ({ page }) => {
  scenario.replyBody = uniqueBody("Message B");
  scenario.secondTargetId = await postMessage(
    page,
    scenario.replyBody,
    scenario.targetId,
  );
});

When("a reply to B is rendered", async ({ page }) => {
  scenario.replyId = await postMessage(
    page,
    uniqueBody("Reply to B"),
    scenario.secondTargetId,
  );
  await waitForMessage(page, scenario.replyId);
});

Then("that reply shows a quote of B", async ({ page }) => {
  await expect(
    messageById(page, scenario.replyId).locator(QUOTE).first(),
  ).toContainText(scenario.replyBody.slice(0, 40));
});

Then("that quote shows no quote of its own", async ({ page }) => {
  const reply = messageById(page, scenario.replyId);
  await expect(reply.locator(QUOTE)).toHaveCount(1);
  await expect(reply.locator(`${QUOTE} ${QUOTE}`)).toHaveCount(0);
  await expect(reply).not.toContainText(scenario.targetBody);
});

// --- The jump bound ---------------------------------------------------------

Given(
  "a reply quotes a message more than five older pages above the loaded window",
  async ({ page, browser, $testInfo }) => {
    await ensureRoomOpen(page, $testInfo);
    scenario.targetBody = uniqueBody("Beyond the bound");
    scenario.targetId = await postMessage(page, scenario.targetBody);
    // Six pages and more lie between the newest page and the original.
    await postAsAnotherMember(
      browser,
      requireIdentity(),
      (JUMP_PAGE_BOUND + 1) * MESSAGES_PER_PAGE + 20,
      "Far filler",
    );
    scenario.replyBody = uniqueBody("Far reply");
    scenario.replyId = await postMessage(
      page,
      scenario.replyBody,
      scenario.targetId,
    );
    await page.reload();
    await waitForRoomReady(page);
    await waitForMessage(page, scenario.replyId);
    await expect(messageById(page, scenario.targetId)).toHaveCount(0);
    olderPageRequests = 0;
    page.on("request", (request) => {
      const postData = request.postData() ?? "";
      if (!postData.includes("FamilyChatMessages")) return;
      const { variables } = JSON.parse(postData) as {
        variables?: { beforeId?: string | null };
      };
      if (typeof variables?.beforeId === "string") olderPageRequests += 1;
    });
  },
);

Then("no more than five older pages are requested", async ({ page }) => {
  // The jump has given up once the room explains why; what it says is the
  // next step's concern.
  const remediation = page.locator('[data-role="family-chat-remediation"]');
  await expect(remediation).toBeVisible({ timeout: 30_000 });
  await expect(remediation).not.toHaveText("");
  expect(olderPageRequests).toBeGreaterThan(0);
  expect(olderPageRequests).toBeLessThanOrEqual(JUMP_PAGE_BOUND);
  await expect(messageById(page, scenario.targetId)).toHaveCount(0);
});

Then(
  "the room states that the message is too far back to jump to",
  async ({ page }) => {
    const refusal = "That message is too far back to jump to.";
    await expect(page.getByRole("status")).toHaveText(refusal);
    await expect(
      page.locator('[data-role="family-chat-remediation"]'),
    ).toHaveText(refusal);
    await expect(
      page.locator('[data-role="family-chat-remediation"]'),
    ).toBeVisible();
  },
);
