import { expect, type Page } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import { restorePrimaryRoute } from "../support/routed-rollout";
import {
  isolatedTestIdentity,
  type TestIdentity,
} from "../support/test-identity";
import {
  composerInput,
  ensureFamilyChatHasOlderPage,
  openFamilyChatRoom,
  promoteWithConcurrentTraffic,
  seedFamilyChatScrollOverflow,
  sendAsAnotherMember,
} from "../support/family-chat";
import {
  sendAttempts,
  type SendAttempt,
} from "../support/family-chat-delivery";
import {
  recordCatchUps,
  watchSockets,
  type CatchUp,
  type SocketLog,
} from "../support/family-chat-socket";

// family_chat.feature's browser-only scenarios about the live room: a Caddy
// promotion under a connected client, the scroll anchor, and the live-region
// announcement. Everything else in that feature is proven by its own step
// files, by Elixir ExBdd (the two "Canonical route" scenarios, which reuse
// the generic `a visitor opens {string}` binding), or -- where the feature
// says so -- by the frontend Vitest+Gherkin harness alone.

const { Given, Then, When } = createBdd();

let identity: TestIdentity;
let catchUpProbeBody = "";
let draftBody = "";
let sockets: SocketLog = { opened: [], closed: [] };
let catchUps: CatchUp[] = [];
let sends: SendAttempt[] = [];
let anchor = { id: "", offset: 0 };

const ANCHOR_TOLERANCE_PX = 4;

Given(
  "a visitor opens {string} with the socket connected to the current slot",
  async ({ page, $testInfo, browser }, route: string) => {
    // The room's catch-up asks for "everything after the newest message it
    // knows"; an empty room has none, so it would refetch the latest page
    // instead, and a run alone on a fresh server would not be proving the
    // gap-fill at all. One earlier message makes the room open with a baseline.
    await sendAsAnotherMember(
      browser,
      isolatedTestIdentity($testInfo),
      `Catch-up baseline ${crypto.randomUUID().slice(0, 8)}`,
    );
    // Watching from before the room opens its socket, so the first socket
    // seen is the one connected to the current slot.
    sockets = watchSockets(page);
    catchUps = recordCatchUps(page);
    sends = sendAttempts(page);
    identity = await openFamilyChatRoom(page, $testInfo);
    expect(page.url()).toContain(route);
    // The room reports itself ready once its history is shown, and only
    // then opens the socket it subscribes on.
    await expect.poll(() => sockets.opened.length, { timeout: 15_000 }).toBe(1);
    // Lives only as long as this window does: a reload would drop it.
    await page.evaluate(() => {
      Object.assign(window, { bnestNoReloadProbe: "held" });
    });
  },
);

When("Caddy promotes a replacement slot", async ({ page, browser }) => {
  // The room is a plain controller, not a LiveView. A real
  // exact-once-catch-up proof needs a message this client never sent itself
  // and a message it tried to send but couldn't, both genuinely in flight
  // around the cutover -- see `promoteWithConcurrentTraffic`'s own header
  // comment.
  ({ catchUpProbeBody, draftBody } = await promoteWithConcurrentTraffic(
    page,
    browser,
    identity,
    () =>
      expect
        .poll(
          () => {
            const reopenedAt = sockets.opened[1];
            return (
              reopenedAt !== undefined &&
              catchUps.some((entry) => entry.answeredAt >= reopenedAt)
            );
          },
          { timeout: 15_000 },
        )
        .toBe(true),
  ));
});

Then("the prior-slot socket closes", async ({ page }) => {
  // The socket connected to the prior slot emitted `close`, and a new one
  // was opened after it -- the room's own reconnect, not a page load.
  await expect.poll(() => sockets.closed.length).toBeGreaterThanOrEqual(1);
  await expect.poll(() => sockets.opened.length).toBeGreaterThanOrEqual(2);
  expect(sockets.opened[1] ?? 0).toBeGreaterThanOrEqual(sockets.closed[0] ?? 0);
  await expect(page.locator('[data-role="family-chat-room"]')).toHaveAttribute(
    "data-connection-state",
    "ready",
    { timeout: 10_000 },
  );
});

Then(
  "the browser subscribes on the promoted slot and completes catch-up within ten seconds",
  async ({ page }) => {
    // A message this client never sent itself, posted by another member
    // concurrently with the promotion, must arrive exactly once -- not zero
    // (lost across the cutover) and not more than once (duplicated by the
    // reconnect module's merge-by-server-ID step).
    await expect(
      page.locator('[data-role="family-chat-message"]', {
        hasText: catchUpProbeBody,
      }),
    ).toHaveCount(1, { timeout: 10_000 });
  },
);

Then(
  "any queued send drains only after catch-up completes",
  async ({ page }) => {
    // The message this client tried to send during the cutover reaches the
    // server and renders once.
    await expect(
      page.locator("[data-role=family-chat-outbox-status]"),
    ).not.toContainText("Retrying", { timeout: 20_000 });
    await expect(
      page.locator('[data-role="family-chat-message"]', {
        hasText: draftBody,
      }),
    ).toHaveCount(1);
    // And in order: once the new socket opened, the room asked for the gap
    // first, and the first send it attempted on that socket followed the
    // gap's answer.
    const reopenedAt = sockets.opened[1] ?? Number.POSITIVE_INFINITY;
    const catchUp = catchUps.find((entry) => entry.answeredAt >= reopenedAt);
    const firstSend = sends.find(
      (attempt) => attempt.body === draftBody && attempt.at >= reopenedAt,
    );
    expect(catchUp, "no catch-up after the new socket").toBeDefined();
    expect(firstSend, "no send after the new socket").toBeDefined();
    expect(firstSend?.at ?? 0).toBeGreaterThanOrEqual(catchUp?.answeredAt ?? 0);
  },
);

Then("the page does not reload", async ({ page }) => {
  // A reloaded page is a new window with a navigation entry of its own, so
  // counting entries alone cannot see it; the Given's probe can.
  const probe = await page.evaluate(
    () =>
      (window as unknown as { bnestNoReloadProbe?: string }).bnestNoReloadProbe,
  );
  expect(probe, "the page was reloaded").toBe("held");
  const navigations = await page.evaluate(
    () => performance.getEntriesByType("navigation").length,
  );
  expect(navigations).toBe(1);
  await restorePrimaryRoute(page);
});

// --- Scroll anchor ----------------------------------------------------------

/** The first message showing at the top of the history, and where it sits. */
function topVisibleMessage(
  page: Page,
): Promise<{ id: string; offset: number }> {
  return page.evaluate(() => {
    const history = document.querySelector('[data-role="family-chat-history"]');
    if (!history) throw new Error("the history is not rendered");
    const top = history.getBoundingClientRect().top;
    const visible = [
      ...document.querySelectorAll<HTMLElement>(
        '[data-role="family-chat-message"]',
      ),
    ].find((message) => message.getBoundingClientRect().bottom > top);
    if (!visible) throw new Error("no message is visible");
    return {
      id: visible.dataset["messageId"] ?? "",
      offset: visible.getBoundingClientRect().top - top,
    };
  });
}

function offsetOf(page: Page, id: string): Promise<number | null> {
  return page.evaluate((messageId) => {
    const history = document.querySelector('[data-role="family-chat-history"]');
    const message = document.querySelector(
      `[data-role="family-chat-message"][data-message-id="${messageId}"]`,
    );
    if (!history || !message) return null;
    return (
      message.getBoundingClientRect().top - history.getBoundingClientRect().top
    );
  }, id);
}

Given(
  "a visitor opens {string} scrolled to a known older message",
  async ({ page, $testInfo }, _route: string) => {
    identity = await openFamilyChatRoom(page, $testInfo);
    // "Load older messages" only stays clickable while the server still
    // reports `hasOlder: true` -- guarantee that regardless of how many
    // messages this shared-room suite run has already accumulated.
    await ensureFamilyChatHasOlderPage(page);
    await page.locator("[data-role=family-chat-history]").evaluate((el) => {
      el.scrollTop = 0;
    });
  },
);

When("the visitor loads an older history page", async ({ page }) => {
  // Measured by the test, from the layout, before anything moves.
  anchor = await topVisibleMessage(page);
  const before = await page.locator("[data-role=family-chat-message]").count();
  await page.getByRole("button", { name: "Load older" }).click();
  await expect
    .poll(() => page.locator("[data-role=family-chat-message]").count())
    .toBeGreaterThan(before);
});

Then(
  "the previously visible message remains at the same visual position",
  async ({ page }) => {
    await expect
      .poll(async () => {
        const offset = await offsetOf(page, anchor.id);
        return offset === null
          ? Number.POSITIVE_INFINITY
          : Math.abs(offset - anchor.offset);
      })
      .toBeLessThanOrEqual(ANCHOR_TOLERANCE_PX);
  },
);

// --- Announcements ----------------------------------------------------------

Given(
  "a visitor opens {string} with focus in the composer",
  async ({ page, $testInfo }, _route: string) => {
    identity = await openFamilyChatRoom(page, $testInfo);
    // The following scenario needs the visitor to genuinely be scrolled away
    // from the bottom when the remote message arrives (see
    // `seedFamilyChatScrollOverflow`'s comment).
    await seedFamilyChatScrollOverflow(page);
    await composerInput(page).focus();
  },
);

When(
  "another member's message arrives away from the bottom of the scroll position",
  async ({ browser }) => {
    await sendAsAnotherMember(browser, identity, "Arrived while scrolled up");
  },
);

Then("a live-region announcement names the new message", async ({ page }) => {
  await expect(page.getByRole("status")).toContainText(
    "Arrived while scrolled up",
  );
});

Then("focus remains in the composer", async ({ page }) => {
  await expect(composerInput(page)).toBeFocused();
});

Then(
  "{string} is shown instead of auto-scrolling",
  async ({ page }, label: string) => {
    await expect(page.getByRole("button", { name: label })).toBeVisible();
  },
);
