import { expect, type Browser, type Page } from "@playwright/test";
import { login } from "./authentication";
import { ROOM_ROUTE } from "./family-chat";
import { waitForRoomReady } from "./family-chat-resume";
import type { TestIdentity } from "./test-identity";

// Support for family_chat.feature's reply rules -- the action menu, the
// composer reply strip, the quote card, the bounded jump, and the history's
// single tab stop. Each of these scenarios carries its own
// `@integration-exempt` comment naming what only a real browser resolves:
// a hold gesture's own event stream, where DOM focus lands, an element's
// computed accessible name, and real scroll position.
//
// "ruang-keluarga" is one shared fixture room across every project this
// suite runs sequentially, so every body posted here is made unique per run
// -- a later project's assertion must never match an earlier project's
// message.

export const MESSAGE = "[data-role=family-chat-message]";
export const MENU = "[data-role=family-chat-message-actions]";
export const MENU_ITEM = "[data-role=family-chat-message-action]";
export const QUOTE = "[data-role=family-chat-message-quote]";
export const REPLY_STRIP = "[data-role=family-chat-reply-strip]";

export interface ReplyScenarioState {
  targetId: string;
  secondTargetId: string;
  targetBody: string;
  /**
   * The display name the room actually rendered for the quoted message.
   * The feature writes `"Ayah"`, which is a stand-in for "the original
   * sender": a browser scenario signs in as an isolated synthetic identity,
   * so the name on screen is that identity's, and asserting the literal
   * would be asserting the fixture rather than the room.
   */
  targetSender: string;
  replyId: string;
  replyBody: string;
}

/**
 * One scenario's "that message" / "that reply", shared by the two step files
 * this suite splits across. A module-level object rather than exported
 * bindings: `import`ed bindings are read-only views, so a second file could
 * read this state but never advance it.
 */
export const scenario: ReplyScenarioState = {
  targetId: "",
  secondTargetId: "",
  targetBody: "",
  targetSender: "",
  replyId: "",
  replyBody: "",
};

export function uniqueBody(prefix: string): string {
  return `${prefix} ${Date.now()}-${Math.floor(Math.random() * 1e6)}`;
}

/**
 * Posts one message straight through the GraphQL mutation under this page's
 * own session and returns the committed server ID, which is what every
 * reply-target and quote assertion is keyed on.
 */
export function postMessage(
  page: Page,
  body: string,
  replyToMessageId: string | null = null,
): Promise<string> {
  return page.evaluate(
    async (input) => {
      const csrfToken =
        document.querySelector<HTMLMetaElement>("meta[name='csrf-token']")
          ?.content ?? "";
      const mutation = `
      mutation SendFamilyChatMessage($roomSlug: String!, $clientMessageId: ID!, $body: String!, $replyToMessageId: ID) {
        sendFamilyChatMessage(roomSlug: $roomSlug, clientMessageId: $clientMessageId, body: $body, replyToMessageId: $replyToMessageId) { id }
      }
    `;
      const response = await fetch("/api/graphql", {
        method: "POST",
        credentials: "same-origin",
        headers: {
          "content-type": "application/json",
          "x-csrf-token": csrfToken,
        },
        body: JSON.stringify({
          query: mutation,
          variables: {
            roomSlug: "ruang-keluarga",
            clientMessageId: crypto.randomUUID(),
            body: input.body,
            replyToMessageId: input.replyToMessageId,
          },
        }),
      });
      const payload = (await response.json()) as {
        data?: { sendFamilyChatMessage?: { id?: string } };
        errors?: unknown;
      };
      const id = payload.data?.sendFamilyChatMessage?.id;
      if (!id) throw new Error(`send failed: ${JSON.stringify(payload)}`);
      return id;
    },
    { body, replyToMessageId },
  );
}

/**
 * Runs `work` as a second, genuinely separate member -- own context, own
 * session -- and always closes the context it created.
 */
export async function asAnotherMember<T>(
  browser: Browser,
  identity: TestIdentity,
  work: (page: Page) => Promise<T>,
): Promise<T> {
  const context = await browser.newContext();
  try {
    const page = await context.newPage();
    await login(page, identity.child);
    await page.goto(ROOM_ROUTE);
    await waitForRoomReady(page);
    return await work(page);
  } finally {
    await context.close();
  }
}

export function messageById(page: Page, messageId: string) {
  return page.locator(`${MESSAGE}[data-message-id="${messageId}"]`);
}

/** Waits for the message to reach the rendered window, however it arrives. */
export async function waitForMessage(
  page: Page,
  messageId: string,
): Promise<void> {
  await expect(messageById(page, messageId)).toBeVisible({ timeout: 15_000 });
}

/**
 * The press-and-hold gesture, as a real pointer event stream rather than a
 * synthesised one: `mouse.down`, a wait longer than the 500 ms threshold
 * with the pointer genuinely held, then `mouse.up`.
 */
export async function pressAndHold(
  page: Page,
  messageId: string,
  holdMs: number,
): Promise<void> {
  const box = await messageById(page, messageId).boundingBox();
  if (!box) throw new Error(`message ${messageId} has no layout box`);
  const x = box.x + box.width / 2;
  const y = box.y + box.height / 2;
  await page.mouse.move(x, y);
  await page.mouse.down();
  await page.waitForTimeout(holdMs + 50);
  await page.mouse.up();
}

export async function openMenuWithKeyboard(
  page: Page,
  messageId: string,
): Promise<void> {
  await messageById(page, messageId).focus();
  await page.keyboard.press("Enter");
}

export function openMenuItems(page: Page) {
  return page.locator(`${MENU}:not([hidden]) ${MENU_ITEM}`);
}

export async function expectMenuOpenFor(
  page: Page,
  messageId: string,
): Promise<void> {
  const menu = page.locator(MENU);
  await expect(menu).not.toHaveAttribute("hidden", /.*/u);
  await expect(menu).toHaveAttribute("data-message-id", messageId);
}

/** Which element the browser's own accessibility tree says has focus. */
export function focusedRole(page: Page): Promise<string> {
  return page.evaluate(() => {
    const active = document.activeElement;
    if (!active) return "none";
    const role = active.getAttribute("role");
    const dataRole = (active as HTMLElement).dataset["role"];
    return role ?? dataRole ?? active.tagName.toLowerCase();
  });
}

export function focusedMessageId(page: Page): Promise<string | null> {
  return page.evaluate((selector) => {
    const active = document.activeElement;
    const message = active?.closest<HTMLElement>(selector);
    return message?.dataset["messageId"] ?? null;
  }, MESSAGE);
}

/** How many rendered messages the browser would stop on while tabbing. */
export function tabbableMessageCount(page: Page): Promise<number> {
  return page.evaluate(
    (selector) =>
      [...document.querySelectorAll<HTMLElement>(selector)].filter(
        (item) => item.tabIndex === 0,
      ).length,
    MESSAGE,
  );
}

export async function liveRegionText(page: Page): Promise<string> {
  return (
    (await page
      .locator('[data-role="family-chat-live-region"]')
      .textContent()) ?? ""
  );
}

/**
 * Posts `count` messages one after another. Sequential on purpose: the
 * resulting order is what "two pages above the loaded window" means, and
 * `Promise.all` would commit them in whatever order the server happened to
 * interleave.
 */
export async function postFiller(
  page: Page,
  count: number,
  prefix: string,
): Promise<void> {
  for (let index = 0; index < count; index += 1) {
    // eslint-disable-next-line no-await-in-loop -- see this function's own comment.
    await postMessage(page, uniqueBody(`${prefix} ${index}`));
  }
}

/**
 * Walks back through older pages the way a reader would, until `messageId`
 * is rendered. Bounded so a genuinely absent message fails the scenario
 * rather than hanging it.
 */
export async function loadOlderUntilRendered(
  page: Page,
  messageId: string,
  maxPages = 8,
): Promise<void> {
  const loadOlder = page.locator('[data-role="family-chat-load-older"]');
  for (let page_index = 0; page_index < maxPages; page_index += 1) {
    // eslint-disable-next-line no-await-in-loop -- each page must be rendered before the next request is decided.
    if ((await messageById(page, messageId).count()) > 0) return;
    // The room disables this control twice over: while a page is in flight,
    // and permanently once nothing older remains. Settling first is what
    // tells them apart -- a page still loading becomes enabled again, an
    // exhausted history does not -- and without it the loop clicks straight
    // into the previous page's own disabled window and reports that as a
    // paging failure.
    let exhausted = false;
    // eslint-disable-next-line no-await-in-loop -- the control's settled state after the previous page is what decides this.
    await expect(loadOlder)
      .toBeEnabled({ timeout: 10_000 })
      .catch(() => {
        exhausted = true;
      });
    if (exhausted) break;
    // eslint-disable-next-line no-await-in-loop -- the newly prepended page moves this control; a stale position is what the bubbles intercept.
    await loadOlder.scrollIntoViewIfNeeded();
    // eslint-disable-next-line no-await-in-loop -- one page per iteration is the behaviour under test.
    const before = await page.locator(MESSAGE).count();
    // eslint-disable-next-line no-await-in-loop -- same.
    await loadOlder.click({ timeout: 10_000 });
    // eslint-disable-next-line no-await-in-loop -- awaiting the page that was just requested, not a batch.
    await expect
      .poll(() => page.locator(MESSAGE).count(), { timeout: 10_000 })
      .toBeGreaterThan(before);
  }
  await expect(messageById(page, messageId)).toHaveCount(1);
}

/** Whether any open menu item is marked unavailable. */
export function anyMenuItemDisabled(page: Page): Promise<boolean> {
  return page.evaluate(
    (selector) =>
      [...document.querySelectorAll(selector)].some(
        (item) => item.getAttribute("aria-disabled") === "true",
      ),
    `${MENU}:not([hidden]) ${MENU_ITEM}`,
  );
}

/** Every rendered message's server key, in document order. */
export function renderedMessageIds(page: Page): Promise<string[]> {
  return page.evaluate(
    (selector) =>
      [...document.querySelectorAll<HTMLElement>(selector)].map(
        (item) => item.dataset["messageId"] ?? "",
      ),
    MESSAGE,
  );
}
