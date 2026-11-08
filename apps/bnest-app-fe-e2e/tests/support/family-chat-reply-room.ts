import type { Page } from "@playwright/test";
import { openFamilyChatRoom, ROOM_ROUTE } from "./family-chat";
import { waitForRoomReady } from "./family-chat-resume";
import {
  trackRoomSubscription,
  waitForRoomSubscribed,
} from "./family-chat-socket";
import {
  asAnotherMember,
  postMessage,
  waitForMessage,
} from "./family-chat-reply";
import type { InstanceIdentities } from "./instance-identities";

// The room-lifecycle half of the reply scenarios' support: who the visitor
// is, and how a scenario gets a committed message to act on. Split from
// `family-chat-reply.ts` purely to stay under this project's max-lines lint
// budget.

let identity: InstanceIdentities | null = null;

export function requireIdentity(): InstanceIdentities {
  if (!identity) throw new Error("no family chat visitor has opened the room");
  return identity;
}

/**
 * A scenario gets its own instance and browser page, so the room is opened once per scenario. A later step
 * of the same scenario that finds the room already open must not log in again: doing so would discard the
 * read position and socket state the earlier step established.
 */
export async function ensureRoomOpen(page: Page): Promise<void> {
  if (page.url().includes(ROOM_ROUTE)) {
    await waitForRoomReady(page);
    await waitForRoomSubscribed(page);
    return;
  }
  trackRoomSubscription(page);
  identity = await openFamilyChatRoom(page);
  await waitForRoomSubscribed(page);
}

/** A committed message from another member, present in the rendered window. */
export async function seedOtherMemberMessage(
  page: Page,
  browser: Parameters<typeof asAnotherMember>[0],
  body: string,
): Promise<string> {
  const id = await asAnotherMember(browser, requireIdentity(), (other) =>
    postMessage(other, body),
  );
  await waitForMessage(page, id);
  return id;
}

/** A reply from another member to `targetId`, committed but not awaited. */
export function replyAsAnotherMember(
  browser: Parameters<typeof asAnotherMember>[0],
  body: string,
  targetId: string,
): Promise<string> {
  return asAnotherMember(browser, requireIdentity(), (other) =>
    postMessage(other, body, targetId),
  );
}

/**
 * Focuses the last operable control that comes before the history in tab order. Which control that is depends on
 * the room: "Load older messages" is that control only while an earlier page exists, and a room that fits in one
 * page disables it, so the control before the history is then the one ahead of it. Throws when none is found.
 */
export async function focusControlBeforeHistory(page: Page): Promise<void> {
  const focused = await page.evaluate(() => {
    const history = document.querySelector('[data-role="family-chat-history"]');
    if (!history) return false;
    const operable = [
      ...document.querySelectorAll<HTMLElement>(
        'a[href], button:not([disabled]), input:not([disabled]):not([type="hidden"]), select:not([disabled]), textarea:not([disabled]), [tabindex="0"]',
      ),
    ].filter(
      (control) =>
        !history.contains(control) &&
        control.tabIndex >= 0 &&
        control.getClientRects().length > 0 &&
        Boolean(
          history.compareDocumentPosition(control) &
          Node.DOCUMENT_POSITION_PRECEDING,
        ),
    );
    const before = operable.at(-1);
    before?.focus();
    return before !== undefined && document.activeElement === before;
  });
  if (!focused) throw new Error("no operable control comes before the history");
}
