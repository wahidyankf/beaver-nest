import { expect, type Page } from "@playwright/test";

// Support for family_chat.feature's "Resuming at the last read position" and
// "Composer focus and keyboard" rules -- where a returning member is placed
// in the conversation, and whether the composer keeps DOM focus across a
// send, are real scroll position and real accessibility-tree state that no
// server-rendered assertion can reach (see each scenario's own
// `@integration-exempt` comment for its boundary reason).

// Mirrors `page_source.js`'s own CONTEXT_PAGE_SIZE / MESSAGE_PAGE_SIZE: how
// much already-read conversation a resumed room loads above the unread
// marker, and how many messages one page holds.
export const RESUME_CONTEXT_PAGE_SIZE = 20;
export const RESUME_MESSAGE_PAGE_SIZE = 50;

// `message_render.js` places the unread marker RESUME_CONTEXT_PX (72) below
// the top edge of the history viewport. The slack absorbs sub-pixel layout
// and late font reflow without admitting a room that opened at the top of
// its window (offset 0 with nothing scrolled past) or at the bottom.
const RESUME_ANCHOR_TOLERANCE_PX = 96;

const READ_MARKER_PREFIX = "bnest.family-chat.last-read";
const ROOM_SLUG = "ruang-keluarga";
const BOTTOM_THRESHOLD_PX = 80;

export interface ResumeWindow {
  contextIds: string[];
  unreadIds: string[];
  dividerCount: number;
}

export interface ResumePlacement {
  dividerOffset: number | null;
  firstUnreadOffset: number | null;
  viewportHeight: number;
  scrollTop: number;
  atBottom: boolean;
  newestVisible: boolean;
}

export async function waitForRoomReady(page: Page): Promise<void> {
  await expect(page.locator('[data-role="family-chat-room"]')).toHaveAttribute(
    "data-connection-state",
    "ready",
    { timeout: 15_000 },
  );
}

function currentUserId(page: Page): Promise<string> {
  return page.evaluate(
    () =>
      document.querySelector<HTMLElement>('[data-role="family-chat-room"]')
        ?.dataset["currentUserId"] ?? "",
  );
}

// The read position is browser-local state keyed by member and room
// (`read_marker.js`), so every helper here derives the key the same way the
// page itself does rather than assuming one.
async function readMarkerKey(page: Page): Promise<string> {
  const userId = await currentUserId(page);
  if (!userId) throw new Error("the family chat room is not open on this page");
  return `${READ_MARKER_PREFIX}.${userId}.${ROOM_SLUG}`;
}

export async function rememberReadPosition(
  page: Page,
  messageId: string,
): Promise<void> {
  const key = await readMarkerKey(page);
  await page.evaluate(
    (entry) => {
      localStorage.setItem(entry.key, entry.value);
    },
    { key, value: messageId },
  );
}

export async function forgetReadPosition(page: Page): Promise<void> {
  const key = await readMarkerKey(page);
  await page.evaluate((storageKey) => {
    localStorage.removeItem(storageKey);
  }, key);
}

export async function storedReadPosition(page: Page): Promise<string | null> {
  const key = await readMarkerKey(page);
  return page.evaluate((storageKey) => localStorage.getItem(storageKey), key);
}

export function renderedMessageIds(page: Page): Promise<string[]> {
  return page.evaluate(() =>
    [
      ...document.querySelectorAll<HTMLElement>(
        '[data-role="family-chat-message"]',
      ),
    ].map((node) => node.dataset["messageId"] ?? ""),
  );
}

export async function newestRenderedMessageId(page: Page): Promise<string> {
  const ids = await renderedMessageIds(page);
  const newest = ids.at(-1);
  if (!newest) throw new Error("the family chat room rendered no messages");
  return newest;
}

/** Splits the rendered window at the unread marker, in document order. */
export function inspectResumeWindow(page: Page): Promise<ResumeWindow> {
  return page.evaluate(() => {
    const list = document.querySelector(
      '[data-role="family-chat-message-list"]',
    );
    const contextIds: string[] = [];
    const unreadIds: string[] = [];
    let seenDivider = false;
    let dividerCount = 0;
    for (const child of list?.children ?? []) {
      const node = child as HTMLElement;
      const role = node.dataset["role"];
      if (role === "family-chat-unread-divider") {
        seenDivider = true;
        dividerCount += 1;
      } else if (role === "family-chat-message") {
        const bucket = seenDivider ? unreadIds : contextIds;
        bucket.push(node.dataset["messageId"] ?? "");
      }
    }
    return { contextIds, unreadIds, dividerCount };
  });
}

/** Where the room placed the visitor, measured against the history viewport. */
export function inspectResumePlacement(page: Page): Promise<ResumePlacement> {
  return page.evaluate((bottomThreshold) => {
    const historyEl = document.querySelector(
      '[data-role="family-chat-history"]',
    );
    if (!historyEl) throw new Error("the family chat history is not rendered");
    const historyTop = historyEl.getBoundingClientRect().top;
    const offsetOf = (node: Element | null): number | null =>
      node === null ? null : node.getBoundingClientRect().top - historyTop;
    const divider = document.querySelector(
      '[data-role="family-chat-unread-divider"]',
    );
    const messages = [
      ...document.querySelectorAll('[data-role="family-chat-message"]'),
    ];
    const newest = messages.at(-1) ?? null;
    const newestTop = offsetOf(newest);
    const newestBottom =
      newest === null
        ? null
        : newest.getBoundingClientRect().bottom - historyTop;
    return {
      dividerOffset: offsetOf(divider),
      firstUnreadOffset: offsetOf(divider?.nextElementSibling ?? null),
      viewportHeight: historyEl.clientHeight,
      scrollTop: historyEl.scrollTop,
      atBottom:
        historyEl.scrollHeight - historyEl.scrollTop - historyEl.clientHeight <=
        bottomThreshold,
      newestVisible:
        newestTop !== null &&
        newestBottom !== null &&
        newestTop < historyEl.clientHeight &&
        newestBottom > 0,
    };
  }, BOTTOM_THRESHOLD_PX);
}

/**
 * Waits for the settled placement rather than the first one: the room
 * re-anchors once the frame and the web fonts land, so only where the marker
 * comes to rest is what the visitor actually sees.
 *
 * The marker belongs at the top of the view, but a browser cannot scroll
 * past the end of the content: when the unread block is shorter than the
 * viewport the room lands at the bottom with the marker further down, which
 * is the same place and the correct one. So the tight anchor bound is
 * required only while there is still room left to scroll.
 */
export async function expectPlacedOnUnreadMarker(page: Page): Promise<void> {
  await expect
    .poll(async () => {
      const { scrollTop, dividerOffset, atBottom } =
        await inspectResumePlacement(page);
      const placed =
        scrollTop > 0 &&
        dividerOffset !== null &&
        dividerOffset >= 0 &&
        (dividerOffset <= RESUME_ANCHOR_TOLERANCE_PX || atBottom);
      return `placed=${placed} scrollTop=${Math.round(scrollTop)} dividerOffset=${Math.round(dividerOffset ?? Number.NaN)} atBottom=${atBottom}`;
    })
    .toMatch(/^placed=true /u);
  const placement = await inspectResumePlacement(page);
  expect(placement.firstUnreadOffset).not.toBeNull();
  const dividerOffset = placement.dividerOffset ?? Number.NaN;
  const firstUnreadOffset = placement.firstUnreadOffset ?? Number.NaN;
  expect(firstUnreadOffset).toBeGreaterThan(dividerOffset);
  expect(firstUnreadOffset).toBeLessThan(placement.viewportHeight);
}

/**
 * Reads forward to the end of the conversation the way a member does: each
 * time the window's end is reached the room either advances the stored read
 * position or, while it still stops short of the newest committed message,
 * loads the next page -- so this repeats until the stored position is the
 * newest rendered message.
 */
export async function readDownToNewest(page: Page): Promise<void> {
  const historyEl = page.locator('[data-role="family-chat-history"]');
  await expect
    .poll(
      async () => {
        await historyEl.evaluate((node) => {
          node.scrollTop = node.scrollHeight;
        });
        const ids = await renderedMessageIds(page);
        return (await storedReadPosition(page)) === (ids.at(-1) ?? null);
      },
      { timeout: 30_000 },
    )
    .toBe(true);
}
