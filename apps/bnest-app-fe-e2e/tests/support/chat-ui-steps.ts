import { expect, type Locator, type Page } from "@playwright/test";

// Shared by the Codex chat step files for the message box, Clear chat, own messages and the phone layout (ADR 005).

export const TEXTAREA = "#chat-composer-form textarea";
export const CONVERSATION = "#chat-conversation";
export const COMPOSER_FORM = "#chat-composer-form";
export const HEADER = ".chat-header";
export const USER_MESSAGE = "[data-role=user-message]";
export const RAW_TEXT = "[data-role=user-message-raw]";
export const CLEAR = "[data-role=clear-chat]";
export const CONFIRM = "[data-role=clear-chat-confirm]";
export const CANCEL = "[data-role=clear-chat-cancel]";
export const YES = "[data-role=clear-chat-yes]";
export const OPTIONS_TOGGLE = "[data-role=chat-options-toggle]";
export const HINT = ".composer-hint, .family-chat-composer-hint";
export const MARKDOWN_MESSAGE = "Keep **these** stars and `code`";
// The link starts a new paragraph, so it is parsed as a link. The mailto link is the positive control.
export const HOSTILE_MESSAGE =
  'Hi <script>alert("x")</script>\n\n[click](javascript:alert("x")) and [ok](mailto:test-user-visitor@example.invalid)';
export const LINES_MESSAGE = "First line\n    indented line\nLast line";
export const TOUCH_TARGET_PX = 44;
// How long a "nothing is sent" Then waits, so a send that would happen has time to reach the page.
export const SETTLE_MS = 500;

/** The box of a locator, failing when the element is not rendered. */
export async function boxOf(locator: Locator, label: string) {
  const box = await locator.boundingBox();
  if (box === null) throw new Error(`${label} has no box`);
  return box;
}

export function viewportOf(page: Page) {
  const viewport = page.viewportSize();
  if (viewport === null) throw new Error("the viewport is not set");
  return viewport;
}

export async function settle(page: Page): Promise<void> {
  await page.evaluate(
    (ms) =>
      new Promise<void>((resolve) => {
        setTimeout(resolve, ms);
      }),
    SETTLE_MS,
  );
}

export function visitorMessageCount(page: Page): Promise<number> {
  return page.locator(USER_MESSAGE).count();
}

/**
 * On a phone the model, effort and Clear chat sit in the options panel, so the panel is opened first. A panel that is
 * already open is left open: the toggle is pressed only while it reports collapsed.
 */
export async function openOptionsIfCollapsed(page: Page): Promise<void> {
  const toggle = page.locator(OPTIONS_TOGGLE);
  if (
    (await toggle.count()) > 0 &&
    (await toggle.isVisible()) &&
    (await toggle.getAttribute("aria-expanded")) === "false"
  ) {
    await toggle.click();
  }
}

/**
 * Clears the Codex chat the way a visitor does: the Options panel is opened on a phone, Clear chat asks for
 * confirmation, and "Yes, delete" clears the chat. Every step that clears the chat uses this one path.
 */
export async function clearCodexChat(page: Page): Promise<void> {
  await openOptionsIfCollapsed(page);
  await page.locator(CLEAR).click();
  await expect(page.locator(CONFIRM)).toBeVisible();
  await page.locator(YES).click();
}

/**
 * A fine pointer (a mouse), so the hover hint is shown. Only the media override is sent. Switching touch emulation off
 * would leave the page with no primary pointer at all (probed in Chromium: `(pointer: fine)` and `(pointer: coarse)`
 * both false), so the touch emulation is never turned off here.
 */
export async function emulateFinePointer(page: Page): Promise<void> {
  const session = await page.context().newCDPSession(page);
  await session.send("Emulation.setEmulatedMedia", {
    features: [
      { name: "pointer", value: "fine" },
      { name: "any-pointer", value: "fine" },
      { name: "hover", value: "hover" },
      { name: "any-hover", value: "hover" },
    ],
  });
  // The override must be in effect in the page, or a fine-pointer scenario would test the wrong pointer.
  const fine = await page.evaluate(() => matchMedia("(pointer: fine)").matches);
  if (!fine) throw new Error("the browser did not report a fine pointer");
}

/** Boxes of the Codex room, read in the browser, and the space that is not conversation. One line per run is logged. */
export async function measureCodexRoom(page: Page): Promise<CodexRoomMeasure> {
  const viewport = viewportOf(page);
  const header = await boxOf(page.locator(HEADER), "the Codex header");
  const conversation = await boxOf(
    page.locator(CONVERSATION),
    "the conversation",
  );
  const composer = await boxOf(page.locator(COMPOSER_FORM), "the composer");
  const measure: CodexRoomMeasure = {
    room: "codex",
    width: viewport.width,
    height: viewport.height,
    header: header.height,
    gapHeaderToConversation: conversation.y - (header.y + header.height),
    conversation: conversation.height,
    gapConversationToComposer:
      composer.y - (conversation.y + conversation.height),
    composer: composer.height,
    space: viewport.height - conversation.height,
    conversationShare: conversation.height / viewport.height,
  };
  // The measurement log is read from the e2e run output; it is not an assertion.
  console.log(`PHONE-MEASURE ${JSON.stringify(measure)}`);
  return measure;
}

export interface CodexRoomMeasure {
  room: "codex";
  width: number;
  height: number;
  header: number;
  gapHeaderToConversation: number;
  conversation: number;
  gapConversationToComposer: number;
  composer: number;
  space: number;
  conversationShare: number;
}

/** Boxes of the Family Chat room, read in the browser, and the space that is not history. One line per run is logged. */
export async function measureFamilyRoom(
  page: Page,
): Promise<FamilyRoomMeasure> {
  const viewport = viewportOf(page);
  const header = await boxOf(
    page.locator(".family-chat-header"),
    "the Family header",
  );
  const history = await boxOf(
    page.locator('[data-role="family-chat-history"]'),
    "the Family history",
  );
  const composer = await boxOf(
    page.locator(".family-chat-composer"),
    "the Family composer",
  );
  const measure: FamilyRoomMeasure = {
    room: "family",
    width: viewport.width,
    height: viewport.height,
    header: header.height,
    gapHeaderToConversation: history.y - (header.y + header.height),
    conversation: history.height,
    gapConversationToComposer: composer.y - (history.y + history.height),
    composer: composer.height,
    space: viewport.height - history.height,
    conversationShare: history.height / viewport.height,
  };
  console.log(`PHONE-MEASURE ${JSON.stringify(measure)}`);
  return measure;
}

export interface FamilyRoomMeasure extends Omit<CodexRoomMeasure, "room"> {
  room: "family";
}

/**
 * The header's names in screen order: boxes within 8 pixels of one row read left to right, and rows read top to bottom.
 * The tab order must match, or Tab would jump across the header.
 */
export function inScreenOrder(
  parts: { name: string; top: number; left: number }[],
): string[] {
  const rowTolerancePx = 8;
  return parts
    .toSorted((a, b) =>
      Math.abs(a.top - b.top) > rowTolerancePx
        ? a.top - b.top
        : a.left - b.left,
    )
    .map((part) => part.name);
}

/**
 * A busy Codex turn leaves the message box read-only, so focus stays in it. A model that is not available disables it.
 * The box is locked when either attribute is set.
 */
/** The width and height of a viewport spec such as "narrow 320x568". */
export function parseViewport(spec: string): { width: number; height: number } {
  const match = /^\w+ (\d+)x(\d+)$/u.exec(spec);
  if (!match) throw new Error(`unreadable viewport ${JSON.stringify(spec)}`);
  return { width: Number(match[1]), height: Number(match[2]) };
}

export async function expectComposerLocked(composer: Locator): Promise<void> {
  await expect
    .poll(() =>
      composer.evaluate((element) => {
        const box = element as HTMLTextAreaElement;
        return box.disabled || box.readOnly;
      }),
    )
    .toBe(true);
}
