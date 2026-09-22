import { expect, type Page, type TestInfo } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import {
  composerInput,
  openFamilyChatRoom,
  ROOM_ROUTE,
} from "../support/family-chat";
import {
  composerBlurCount,
  recordComposerBlurs,
} from "../support/family-chat-composer";
import {
  expectPlacedOnUnreadMarker,
  forgetReadPosition,
  inspectResumePlacement,
  inspectResumeWindow,
  newestRenderedMessageId,
  readDownToNewest,
  rememberReadPosition,
  RESUME_CONTEXT_PAGE_SIZE,
  RESUME_MESSAGE_PAGE_SIZE,
  waitForRoomReady,
} from "../support/family-chat-resume";
import {
  ensureAtLeast,
  leaveRoom,
  postAsAnotherMember,
} from "../support/family-chat-seeding";
import type { TestIdentity } from "../support/test-identity";

// The browser half of family_chat.feature's "Resuming at the last read
// position" and "Composer focus and keyboard" rules -- the frontend
// Vitest+Gherkin harness proves the same scenarios logically against the
// production modules, but cannot place a message on a real scroll position
// or hold real DOM focus across a send.

const { Given, Then, When } = createBdd();

let identity: TestIdentity | null = null;
let knownReadId = "";
// "ruang-keluarga" is one shared fixture room across every project this suite
// runs sequentially, so the body has to be unique per send or a later
// project's assertion would match an earlier project's message.
let sentBody = "";
const SHIFT_ENTER_CONTINUATION = "and more";

function requireIdentity(): TestIdentity {
  if (!identity) throw new Error("no family chat visitor has opened the room");
  return identity;
}

async function ensureRoomOpen(page: Page, testInfo: TestInfo): Promise<void> {
  if (page.url().includes(ROOM_ROUTE)) {
    await waitForRoomReady(page);
    return;
  }
  identity = await openFamilyChatRoom(page, testInfo);
}

async function readUpToNewest(page: Page, testInfo: TestInfo): Promise<void> {
  await ensureRoomOpen(page, testInfo);
  await ensureAtLeast(page, 3);
  knownReadId = await newestRenderedMessageId(page);
  await rememberReadPosition(page, knownReadId);
  await leaveRoom(page);
}

Given(
  "the family chat holds more earlier messages than one context page",
  async ({ page, $testInfo }) => {
    await ensureRoomOpen(page, $testInfo);
    await ensureAtLeast(page, RESUME_CONTEXT_PAGE_SIZE + 5);
  },
);

Given(
  "the visitor has read the family chat up to a known message",
  async ({ page, $testInfo }) => {
    await readUpToNewest(page, $testInfo);
  },
);

Given(
  "{int} newer messages arrived while the visitor was away",
  async ({ browser }, count: number) => {
    await postAsAnotherMember(browser, requireIdentity(), count, "Away");
  },
);

Given(
  "the visitor has read every message in the family chat",
  async ({ page, $testInfo }) => {
    await ensureRoomOpen(page, $testInfo);
    await ensureAtLeast(page, 3);
    await readDownToNewest(page);
    await leaveRoom(page);
  },
);

Given(
  "the visitor has never opened the family chat on this device",
  async ({ page, $testInfo }) => {
    await ensureRoomOpen(page, $testInfo);
    await ensureAtLeast(page, 3);
    await forgetReadPosition(page);
    await leaveRoom(page);
  },
);

Given(
  "the visitor left more unread messages behind than one page holds",
  async ({ page, browser, $testInfo }) => {
    await readUpToNewest(page, $testInfo);
    await postAsAnotherMember(
      browser,
      requireIdentity(),
      RESUME_MESSAGE_PAGE_SIZE + 5,
      "Away",
    );
  },
);

When("the visitor reopens {string}", async ({ page }, route: string) => {
  await page.goto(route);
  await waitForRoomReady(page);
});

When("the visitor scrolls down to the newest message", async ({ page }) => {
  await readDownToNewest(page);
});

When("the visitor jumps to the newest message", async ({ page }) => {
  await page.getByRole("button", { name: "New messages below" }).click();
});

Then(
  "the first unread message is the first message in view",
  async ({ page }) => {
    await waitForRoomReady(page);
    await expectPlacedOnUnreadMarker(page);
  },
);

Then(
  "an unread marker separates the read messages from the new ones",
  async ({ page }) => {
    const { contextIds, unreadIds, dividerCount } =
      await inspectResumeWindow(page);
    expect(dividerCount).toBe(1);
    expect(contextIds.length).toBeGreaterThan(0);
    expect(unreadIds.length).toBeGreaterThan(0);
    const boundary = Number(knownReadId);
    const aboveMarker = contextIds.map(Number).filter((id) => id > boundary);
    const belowMarker = unreadIds.map(Number).filter((id) => id <= boundary);
    expect(aboveMarker, JSON.stringify(aboveMarker)).toEqual([]);
    expect(belowMarker, JSON.stringify(belowMarker)).toEqual([]);
  },
);

Then(
  "one bounded page of earlier messages is loaded above the unread marker",
  async ({ page }) => {
    const { contextIds } = await inspectResumeWindow(page);
    expect(contextIds).toHaveLength(RESUME_CONTEXT_PAGE_SIZE);
  },
);

Then("older history can still be loaded on request", async ({ page }) => {
  const loadOlder = page.getByRole("button", { name: "Load older" });
  await expect(loadOlder).toBeEnabled();
  await loadOlder.click();
  await expect
    .poll(async () => (await inspectResumeWindow(page)).contextIds.length)
    .toBeGreaterThan(RESUME_CONTEXT_PAGE_SIZE);
});

Then("the newest message is in view", async ({ page }) => {
  await waitForRoomReady(page);
  await expect
    .poll(async () => {
      const placement = await inspectResumePlacement(page);
      return placement.atBottom && placement.newestVisible;
    })
    .toBe(true);
  await expect(
    page.getByRole("button", { name: "New messages below" }),
  ).toBeHidden();
});

Then("no unread marker is shown", async ({ page }) => {
  await expect(
    page.locator('[data-role="family-chat-unread-divider"]'),
  ).toHaveCount(0);
});

Then(
  "{string} offers a way back to the newest message",
  async ({ page }, label: string) => {
    // Visibility, not enabled state: the control ships attached and is
    // toggled through `hidden` alone, so it is "enabled" even when the room
    // never offers it.
    await expect(page.getByRole("button", { name: label })).toBeVisible();
  },
);

When(
  "the visitor sends {string} through the composer",
  async ({ page }, body: string) => {
    await recordComposerBlurs(page);
    sentBody = `${body} ${crypto.randomUUID().slice(0, 8)}`;
    await composerInput(page).fill(sentBody);
    await page.getByRole("button", { name: "Send" }).click();
    await expect
      .poll(() =>
        page
          .locator('[data-role="family-chat-message"]', { hasText: sentBody })
          .count(),
      )
      .toBeGreaterThan(0);
  },
);

Then("the visitor's own message is in view", async ({ page }) => {
  await expect(
    page.locator('[data-role="family-chat-message"]', { hasText: sentBody }),
  ).toBeInViewport();
});

When(
  "the visitor submits {string} with the Enter key",
  async ({ page }, body: string) => {
    await recordComposerBlurs(page);
    const input = composerInput(page);
    // Unique per send for the reason `sentBody` is: the three browser
    // projects share one room, so the raw Gherkin literal would already be on
    // screen from an earlier project and this poll would pass without the
    // Enter key having sent anything.
    sentBody = `${body} ${crypto.randomUUID().slice(0, 8)}`;
    await input.fill(sentBody);
    await input.press("Enter");
    await expect
      .poll(() =>
        page
          .locator('[data-role="family-chat-message"]', { hasText: sentBody })
          .count(),
      )
      .toBeGreaterThan(0);
  },
);

When(
  "the visitor presses Shift and Enter while writing {string}",
  async ({ page }, body: string) => {
    const input = composerInput(page);
    await input.fill(body);
    await input.press("Shift+Enter");
    await input.pressSequentially(SHIFT_ENTER_CONTINUATION);
  },
);

Then("the composer still holds keyboard focus", async ({ page }) => {
  await expect(composerInput(page)).toBeFocused();
});

Then(
  "activating the send control never takes focus from the message input",
  async ({ page }) => {
    expect(await composerBlurCount(page)).toBe(0);
  },
);

Then(
  "the composer is empty and ready for the next message",
  async ({ page }) => {
    const input = composerInput(page);
    await expect(input).toHaveValue("");
    await expect(input).toBeEnabled();
  },
);

Then("the composer holds an unsent multi-line draft", async ({ page }) => {
  const draft = await composerInput(page).inputValue();
  expect(draft).toContain("\n");
  expect(draft).toContain(SHIFT_ENTER_CONTINUATION);
  await expect(
    page.locator('[data-role="family-chat-message"]', {
      hasText: SHIFT_ENTER_CONTINUATION,
    }),
  ).toHaveCount(0);
});
