import type { Page, TestInfo } from "@playwright/test";
import { openFamilyChatRoom, ROOM_ROUTE } from "./family-chat";
import { waitForRoomReady } from "./family-chat-resume";
import {
  asAnotherMember,
  postMessage,
  waitForMessage,
} from "./family-chat-reply";
import type { TestIdentity } from "./test-identity";

// The room-lifecycle half of the reply scenarios' support: who the visitor
// is, and how a scenario gets a committed message to act on. Split from
// `family-chat-reply.ts` purely to stay under this project's max-lines lint
// budget.

let identity: TestIdentity | null = null;

export function requireIdentity(): TestIdentity {
  if (!identity) throw new Error("no family chat visitor has opened the room");
  return identity;
}

/**
 * Scenarios run sequentially against one shared fixture room, so a scenario
 * that inherits an already-open room must not log in again -- doing so would
 * discard the read position and socket state the previous one established.
 */
export async function ensureRoomOpen(
  page: Page,
  testInfo: TestInfo,
): Promise<void> {
  if (page.url().includes(ROOM_ROUTE)) {
    await waitForRoomReady(page);
    return;
  }
  identity = await openFamilyChatRoom(page, testInfo);
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
