import { expect, type Page } from "@playwright/test";
import { messageById } from "./family-chat-gestures";

// Support for family_chat.feature's "Keyboard reach of message content" rule (ADR 003, Decision 6), in Chromium at the
// served origin. Focus, stops, overflow, scroll, the focus ring and the link's popup are all read in the page. The unit
// adapter (`family_chat_keyboard.steps.ts`) reads the same step names against a stand-in browser, so a change to a
// name here is a change there.

export const HISTORY = '[data-role="family-chat-history"]';
export const LIST = '[data-role="family-chat-message-list"]';
export const MESSAGE = '[data-role="family-chat-message"]';
export const BODY = '[data-role="family-chat-message-body"]';
export const DRAWN = 'figure[data-bnest-diagram-state="drawn"]';
export const MARKED = 'pre[data-bnest-diagram="mermaid"]';

// The bodies the rule's wide Givens send. The unit adapter (`family_chat_keyboard.steps.ts`) sends wide bodies of the
// same kinds, table and code block, but its own strings, so the two sets are not byte-equal.
export const WIDE_TABLE =
  "| Menu | Drink | Dessert | Notes | Seats |\n" +
  "| ---- | ----- | ------- | ----- | ----- |\n" +
  "| Nasigorengkampungspesialbuatkeluargakitasemua | Tehmanisdengansusuhangatbersamakeluarga | Kuehmangkokdaripasarpagihariinisegarsekali | Pedasnyasedanglebihenakdimakanbersama | Tigaorangdewasadanduaanakkecil |";
export const WIDE_CODE =
  "```text\nNasigorengkampungspesialbuatkeluargakitasemua Tehmanisdengansusuhangatbersamakeluarga Kuehmangkokdaripasarpagihariinisegarsekali\n```";
export const WIDE_BODIES: Readonly<Record<string, string>> = {
  table: WIDE_TABLE,
  "code block": WIDE_CODE,
};

/** The selector of each kind of content a step names, as the page renders it. */
export const KIND_SELECTOR: Readonly<Record<string, string>> = {
  table: "table",
  "code block": "pre",
  diagram: ".bnest-diagram-canvas",
  "quote card": ".family-chat-message-quote",
};

/** A link's popup, armed by the Enter that opened it, and read by the Then step that checks it. */
const pendingPopups = new WeakMap<Page, Promise<Page | Error>>();

/** Presses one key. Enter on a link that opens a new tab arms the popup it will open. */
export async function pressKeyboard(page: Page, key: string): Promise<void> {
  if (key === "Enter") {
    const onNewTabLink = await page.evaluate(
      () =>
        document.activeElement instanceof HTMLAnchorElement &&
        document.activeElement.getAttribute("target") === "_blank",
    );
    if (onNewTabLink) {
      pendingPopups.set(
        page,
        page
          .waitForEvent("popup", { timeout: 15_000 })
          .catch((error: unknown) =>
            error instanceof Error ? error : new Error(String(error)),
          ),
      );
    }
  }
  await page.keyboard.press(key);
}

/** Whether keyboard focus is on the named content: a kind, or a link or summary whose text is the name. */
export function focusIsOn(page: Page, name: string): Promise<boolean> {
  return page.evaluate(
    ({ wanted, kinds }) => {
      const active = document.activeElement;
      if (!(active instanceof HTMLElement) || active === document.body)
        return false;
      const selector = kinds[wanted];
      if (selector !== undefined) return active.matches(selector);
      return (
        active.matches("a[href], summary") &&
        (active.textContent ?? "").trim() === wanted
      );
    },
    { wanted: name, kinds: KIND_SELECTOR },
  );
}

/** What holds focus now, for a failure message. */
export function describeFocus(page: Page): Promise<string> {
  return page.evaluate(() => {
    const active = document.activeElement;
    if (!(active instanceof HTMLElement) || active === document.body)
      return "nothing";
    const text = (active.textContent ?? "").trim().slice(0, 40);
    return `${active.tagName.toLowerCase()} "${text}"`;
  });
}

/** Whether keyboard focus is on the message whose body starts with `text`. */
export function focusIsOnMessage(page: Page, text: string): Promise<boolean> {
  return page.evaluate(
    ({ wanted, message, body }) => {
      const active = document.activeElement;
      if (!(active instanceof HTMLElement) || !active.matches(message))
        return false;
      return (active.querySelector(body)?.textContent ?? "")
        .trim()
        .startsWith(wanted);
    },
    { wanted: text, message: MESSAGE, body: BODY },
  );
}

/** The body text of each message that holds the single history tab stop (normally one). */
export function stopBodies(page: Page): Promise<string[]> {
  return page.evaluate(
    ({ message, body }) =>
      [...document.querySelectorAll<HTMLElement>(message)]
        .filter((item) => item.tabIndex === 0)
        .map((item) => (item.querySelector(body)?.textContent ?? "").trim()),
    { message: MESSAGE, body: BODY },
  );
}

/** How many links in the history can take keyboard focus. */
export function linkStopCount(page: Page): Promise<number> {
  return page.evaluate(
    (list) =>
      [
        ...document.querySelectorAll<HTMLAnchorElement>(`${list} a[href]`),
      ].filter((link) => link.tabIndex >= 0).length,
    LIST,
  );
}

/** Whether keyboard focus is outside the history (on the page, or nowhere the history holds). */
export function focusIsOutsideHistory(page: Page): Promise<boolean> {
  return page.evaluate(
    (history) =>
      !document.querySelector(history)?.contains(document.activeElement),
    HISTORY,
  );
}

/** Waits for the popup a link opened on the last Enter, checks the link's new-tab attributes, and closes the popup. */
export async function expectNewTabOpened(
  page: Page,
  text: string,
): Promise<void> {
  const popup = await pendingPopups.get(page);
  expect(popup, "no Enter armed a popup").toBeDefined();
  if (popup instanceof Error) throw popup;
  await popup?.close();
  const link = page.locator(`${LIST} a[href]`, { hasText: text }).first();
  await expect(link).toHaveAttribute("target", "_blank");
  await expect(link).toHaveAttribute("rel", /noopener/u);
}

/** The first named region in the target message: whether it was found, and whether it overflows its box. */
export function measuredRegion(
  page: Page,
  name: string,
  messageId: string,
): Promise<{ found: boolean; overflows: boolean; scrollLeft: number }> {
  return page.evaluate(
    ({ selector, id, message, body }) => {
      if (selector === undefined)
        return { found: false, overflows: false, scrollLeft: 0 };
      const region = document.querySelector<HTMLElement>(
        `${message}[data-message-id="${id}"] ${body} ${selector}`,
      );
      if (!region) return { found: false, overflows: false, scrollLeft: 0 };
      return {
        found: true,
        overflows:
          region.scrollWidth > region.clientWidth ||
          region.scrollHeight > region.clientHeight,
        scrollLeft: region.scrollLeft,
      };
    },
    {
      selector: KIND_SELECTOR[name],
      id: messageId,
      message: MESSAGE,
      body: BODY,
    },
  );
}

/** The focused element's focus indicator: whether it matches :focus-visible and how its outline is drawn. */
export function focusRing(page: Page): Promise<{
  focusVisible: boolean;
  outlineStyle: string;
  outlineWidth: number;
}> {
  return page.evaluate(() => {
    const active = document.activeElement;
    if (!(active instanceof HTMLElement)) {
      return { focusVisible: false, outlineStyle: "none", outlineWidth: 0 };
    }
    const style = getComputedStyle(active);
    return {
      focusVisible: active.matches(":focus-visible"),
      outlineStyle: style.outlineStyle,
      outlineWidth: Number(style.outlineWidth.replace(/px$/u, "")),
    };
  });
}

/**
 * Waits until every marked diagram in the room is drawn. The engine draws a diagram only once it is near the viewport
 * (ADR 004, Decision 3), so a marked diagram below the fold is scrolled to, the way a reader reaching it would.
 */
export async function settleDiagrams(page: Page): Promise<void> {
  await expect
    .poll(
      async () => {
        const marked = page.locator(`${LIST} ${MARKED}`);
        if ((await marked.count()) > 0) {
          // A failed scroll is not an error: the marker can be replaced by its drawn figure meanwhile.
          await marked
            .first()
            .scrollIntoViewIfNeeded({ timeout: 2_000 })
            .catch(() => null);
        }
        return marked.count();
      },
      { timeout: 20_000 },
    )
    .toBe(0);
}

/** The message that holds a drawn diagram, located by its drawing rather than by a named target. */
export function diagramMessage(page: Page) {
  return page.locator(MESSAGE).filter({ has: page.locator(DRAWN) });
}

/** Waits until the message's server copy has replaced its pending one. */
export async function waitForCommitted(
  page: Page,
  messageId: string,
): Promise<void> {
  await expect(messageById(page, messageId)).toHaveAttribute(
    "data-delivery-state",
    "committed",
    { timeout: 20_000 },
  );
}
