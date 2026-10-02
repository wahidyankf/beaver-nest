import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import {
  expectRowStatus,
  interfereWithSends,
  pendingRowId,
  sendThroughComposer,
} from "../support/family-chat-delivery";
import { waitForRoomReady } from "../support/family-chat-resume";
import {
  expectMenuOpenFor,
  liveRegionText,
  MENU,
  messageById,
  openMenuItems,
  openMenuWithKeyboard,
  postMessage,
  scenario,
  uniqueBody,
  waitForMessage,
} from "../support/family-chat-reply";
import { ensureRoomOpen } from "../support/family-chat-reply-room";
import { postSystemMessage } from "../support/family-chat-session";

// What the action menu offers for messages in each state, copying, and the
// press that becomes a scroll -- the rest of family_chat.feature's
// "Rule: Message actions" in a real browser (opening and closing the menu
// are in `family-chat-reply.steps.ts`).

const { After, Given, Then, When } = createBdd();

const HOLD_THRESHOLD_MS = 500;

// A scenario that takes the browser offline must not leave the next one
// offline.
After(async ({ page }) => {
  await page.context().setOffline(false);
});

function menuItem(page: Parameters<typeof openMenuItems>[0], label: string) {
  return openMenuItems(page).filter({ hasText: label }).first();
}

// --- Messages that are not yet committed ----------------------------------

Given(
  "the visitor's own message is in the {string} state",
  async ({ page, $testInfo }, state: string) => {
    await ensureRoomOpen(page, $testInfo);
    // Each state is the network a member could be on when they look.
    if (state === "Waiting for connection") {
      await page.context().setOffline(true);
    } else if (state === "Sending") {
      await interfereWithSends(page, "hold");
    } else if (state === "Retrying") {
      await interfereWithSends(page, "abort");
    } else {
      await interfereWithSends(page, "reject");
    }
    const body = uniqueBody(`Not yet committed (${state})`);
    await sendThroughComposer(page, body);
    const shown = state === "Retrying" ? "Retrying in …" : state;
    await expectRowStatus(page, body, shown);
    scenario.targetId = await pendingRowId(page, body);
  },
);

When("the visitor opens the action menu on it", async ({ page }) => {
  await openMenuWithKeyboard(page, scenario.targetId);
  await expectMenuOpenFor(page, scenario.targetId);
});

Then("{string} is present and unavailable", async ({ page }, label: string) => {
  await expect(menuItem(page, label)).toHaveAttribute("aria-disabled", "true");
});

Then(
  "the menu states that the message must send before it can be replied to",
  async ({ page }) => {
    await expect(menuItem(page, "Reply")).toHaveAccessibleDescription(
      "Send this message before replying to it",
    );
  },
);

Then("{string} remains available", async ({ page }, label: string) => {
  await expect(menuItem(page, label)).toBeVisible();
  await expect(menuItem(page, label)).not.toHaveAttribute(
    "aria-disabled",
    "true",
  );
});

// --- A system message -------------------------------------------------------

Given(
  "the room holds a committed system message",
  async ({ page, $testInfo }) => {
    await ensureRoomOpen(page, $testInfo);
    scenario.targetBody = uniqueBody("System notice");
    scenario.targetId = postSystemMessage(scenario.targetBody);
    await page.reload();
    await waitForRoomReady(page);
    await waitForMessage(page, scenario.targetId);
    await expect(messageById(page, scenario.targetId)).toContainText(
      scenario.targetBody,
    );
  },
);

Then("{string} is available", async ({ page }, label: string) => {
  await expect(menuItem(page, label)).toBeVisible();
  await expect(menuItem(page, label)).not.toHaveAttribute(
    "aria-disabled",
    "true",
  );
});

// --- Copying ----------------------------------------------------------------

Given(
  "the visitor opens the action menu on a message whose body is {string}",
  async ({ page, $testInfo }, body: string) => {
    await ensureRoomOpen(page, $testInfo);
    // A member who copies has granted the page the clipboard; reading it
    // back is how this scenario sees what was written.
    await page
      .context()
      .grantPermissions(["clipboard-read", "clipboard-write"]);
    scenario.targetBody = body;
    scenario.targetId = await postMessage(page, body);
    await waitForMessage(page, scenario.targetId);
    await openMenuWithKeyboard(page, scenario.targetId);
    await expectMenuOpenFor(page, scenario.targetId);
  },
);

Then("the clipboard holds exactly {string}", async ({ page }, text: string) => {
  await expect
    .poll(() => page.evaluate(() => navigator.clipboard.readText()))
    .toBe(text);
});

Then("the room announces that the message was copied", async ({ page }) => {
  await expect.poll(() => liveRegionText(page)).toBe("Message copied.");
});

// --- A press that becomes a scroll ----------------------------------------

When(
  "the visitor presses a message and moves more than 10 pixels before releasing",
  async ({ page }) => {
    await waitForRoomReady(page);
    scenario.targetId = await postMessage(page, uniqueBody("Pressed"));
    await waitForMessage(page, scenario.targetId);
    const message = messageById(page, scenario.targetId);
    await message.scrollIntoViewIfNeeded();
    const box = await message.boundingBox();
    if (!box) throw new Error("the pressed message has no box");
    const x = box.x + box.width / 2;
    const y = box.y + box.height / 2;
    await page.mouse.move(x, y);
    await page.mouse.down();
    await page.mouse.move(x, y - 30, { steps: 6 });
    // Held past the threshold: only the movement may stop the menu.
    await page.waitForTimeout(HOLD_THRESHOLD_MS + 300);
    await page.mouse.up();
  },
);

Then("no action menu opens", async ({ page }) => {
  await expect(page.locator(MENU)).toHaveAttribute("hidden", /.*/u);
  await expect(openMenuItems(page)).toHaveCount(0);
});
