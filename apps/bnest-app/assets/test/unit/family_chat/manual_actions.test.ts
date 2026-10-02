// Plain Vitest unit coverage for a message that stopped at "Couldn't send":
// the room offers Retry and Discard on the row and in its menu, and each
// does what it says. Booted in the same production room the Gherkin
// scenarios use (`test/behaviour/support/browser_room.ts`).

import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { STATUS } from "../../../js/family_chat/outbox.js";
import {
  activePage,
  announcement,
  clickOn,
  closeWorld,
  committedFor,
  device,
  isRendered,
  namespaceOf,
  openRoomPage,
  pressKey,
  requireRow,
  rowFor,
  sendThroughComposer,
  server,
  settle,
  shownStatus,
  startWorld,
  tabOrder,
  visitor,
  waitFor,
} from "../../behaviour/support/browser_room";

async function failedMessage(): Promise<string> {
  await openRoomPage();
  server().setSendOutcome(visitor().id, { code: "VALIDATION_FAILED" });
  const id = await sendThroughComposer("Ditolak server");
  if (!id) throw new Error("the room refused to queue the message");
  await waitFor(
    () => shownStatus(requireRow(id)) === STATUS.FAILED,
    "the message to stop at Couldn't send",
  );
  server().setSendOutcome(visitor().id, "commit");
  return id;
}

function control(id: string, role: string): HTMLButtonElement | null {
  return requireRow(id).querySelector<HTMLButtonElement>(
    `[data-role="${role}"]`,
  );
}

function stored(id: string): boolean {
  return device()
    .persistence.rowsFor(namespaceOf(visitor()))
    .some((row) => row.clientMessageId === id);
}

async function chooseFromMenu(id: string, label: string): Promise<void> {
  requireRow(id).focus();
  await pressKey("Enter");
  const item = [
    ...activePage().elements.messageActions.querySelectorAll<HTMLElement>(
      '[data-role="family-chat-message-action"]',
    ),
  ].find((candidate) => candidate.textContent === label);
  if (!item) throw new Error(`the menu offers no ${label}`);
  item.focus();
  await pressKey("Enter");
  await settle();
}

beforeEach(() => {
  startWorld();
});

afterEach(async () => {
  await closeWorld();
});

describe("a message that couldn't send", () => {
  it("shows Retry and Discard on its row, described by its status", async () => {
    const id = await failedMessage();
    const status = requireRow(id).querySelector(
      '[data-role="family-chat-message-status"]',
    );

    for (const role of [
      "family-chat-message-retry",
      "family-chat-message-discard",
    ]) {
      const button = control(id, role);
      expect(button && isRendered(button)).toBe(true);
      expect(button?.getAttribute("aria-describedby")).toBe(status?.id);
      expect(status?.id).not.toBe("");
    }
    expect(control(id, "family-chat-message-retry")?.textContent).toBe("Retry");
    expect(control(id, "family-chat-message-discard")?.textContent).toBe(
      "Discard",
    );
  });

  it("keeps the history's single tab stop", async () => {
    const id = await failedMessage();

    const reachable = tabOrder(activePage().document);
    expect(reachable).not.toContain(control(id, "family-chat-message-retry"));
    expect(reachable).not.toContain(control(id, "family-chat-message-discard"));
  });

  it("sends it again from the row's Retry, and drops the controls on the way", async () => {
    const id = await failedMessage();

    await clickOn(control(id, "family-chat-message-retry") as Element);
    await waitFor(() => committedFor(id) !== undefined, "the retry to commit");
    await settle();

    const committed = committedFor(id);
    expect(rowFor(id)).toBeNull();
    expect(rowFor(committed?.id ?? "")).not.toBeNull();
  });

  it("asks before Discard, and keeps the message when the member says no", async () => {
    const id = await failedMessage();
    const page = activePage();
    page.confirmAnswer = false;

    await clickOn(control(id, "family-chat-message-discard") as Element);
    await settle();

    expect(page.dialogs).toHaveLength(1);
    expect(rowFor(id)).not.toBeNull();
    expect(stored(id)).toBe(true);
  });

  it("removes it from the room and the device on a confirmed Discard", async () => {
    const id = await failedMessage();
    const attempts = server().sendAttempts.length;

    await clickOn(control(id, "family-chat-message-discard") as Element);
    await settle();

    expect(rowFor(id)).toBeNull();
    expect(stored(id)).toBe(false);
    expect(server().sendAttempts).toHaveLength(attempts);
    expect(announcement()).toBe("Message discarded.");
    expect(activePage().document.activeElement).toBe(
      activePage().elements.input,
    );
  });

  it("offers Retry from the message's menu to a keyboard user", async () => {
    const id = await failedMessage();

    await chooseFromMenu(id, "Retry");
    await waitFor(() => committedFor(id) !== undefined, "the retry to commit");
  });

  it("offers Discard from the message's menu to a keyboard user", async () => {
    const id = await failedMessage();

    await chooseFromMenu(id, "Discard");

    expect(rowFor(id)).toBeNull();
    expect(stored(id)).toBe(false);
    expect(activePage().document.activeElement).toBe(
      activePage().elements.input,
    );
  });

  it("does not open the menu when Enter lands on its own Retry", async () => {
    const id = await failedMessage();
    control(id, "family-chat-message-retry")?.focus();

    await pressKey("Enter");
    await waitFor(() => committedFor(id) !== undefined, "the retry to commit");

    expect(activePage().elements.messageActions.hidden).toBe(true);
  });
});
