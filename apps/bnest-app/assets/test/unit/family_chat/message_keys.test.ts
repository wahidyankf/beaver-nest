// @vitest-environment happy-dom
//
// Plain Vitest unit coverage for the key handlers of `js/family_chat/mount_browser_actions.js` (ADR 003, Decision 6,
// rule 4). The handlers act only when the key's target is the message element itself. A key pressed on content inside
// the message keeps its own meaning, so Enter follows a link, arrows scroll a table, and Escape returns to the message.
//
// The handlers are wired through `wireMessageActions`, the one entry point the room calls, on a real DOM.

import { beforeEach, describe, expect, it, vi } from "vitest";
import { wireMessageActions } from "../../../js/family_chat/mount_browser_actions.js";
import { messageNode } from "../../../js/family_chat/message_render.js";
import { STATUS } from "../../../js/family_chat/outbox_namespace.js";

const BODY_OPEN =
  '<div phx-r class="message-content markdown-body family-chat-message-body" data-role="family-chat-message-body">';

const clock = {
  now: () => 0,
  random: () => 0.5,
  setTimer: () => 0,
  clearTimer: () => undefined,
};

interface Harness {
  readonly list: HTMLElement;
  readonly host: HTMLElement;
  readonly store: {
    rovingMove: ReturnType<typeof vi.fn>;
    rovingMoveTo: ReturnType<typeof vi.fn>;
  };
  messageOf(id: string): HTMLElement;
}

function keyDown(
  target: Element,
  key: string,
  shiftKey = false,
): KeyboardEvent {
  const event = new KeyboardEvent("keydown", {
    key,
    shiftKey,
    bubbles: true,
    cancelable: true,
  });
  target.dispatchEvent(event);
  return event;
}

function build(): Harness {
  const list = document.createElement("ol");
  list.append(
    messageNode(
      {
        id: "1",
        body: "Dinner plan",
        bodyHtml: `${BODY_OPEN}<p>Dinner plan <a href="https://example.test/home">home</a></p></div>`,
        senderDisplayName: "Ayah",
        senderId: "u-ayah",
      },
      { pending: false, currentUserId: "u-me" },
    ),
    messageNode(
      {
        id: "2",
        body: "Menu",
        bodyHtml: `${BODY_OPEN}<table><tr><td>Rice</td></tr></table></div>`,
        senderDisplayName: "Ayah",
        senderId: "u-ayah",
      },
      { pending: false, currentUserId: "u-me" },
    ),
    messageNode(
      {
        id: "3",
        body: "Failed draft",
        senderDisplayName: "Ayah",
        senderId: "u-me",
        status: STATUS.FAILED,
      },
      { pending: true, currentUserId: "u-me" },
    ),
  );
  const host = document.createElement("div");
  host.hidden = true;
  const liveRegion = document.createElement("p");
  const input = document.createElement("textarea");
  document.body.replaceChildren(list, host, liveRegion, input);

  const store = { rovingMove: vi.fn(), rovingMoveTo: vi.fn() };
  const room = { store, replyTarget: null };
  const elements = {
    list,
    messageActions: host,
    liveRegion,
    input,
  } as unknown as Parameters<typeof wireMessageActions>[1];
  wireMessageActions(
    room as unknown as Parameters<typeof wireMessageActions>[0],
    elements,
    clock,
  );

  return {
    list,
    host,
    store,
    messageOf: (id) => {
      const message = list.querySelector<HTMLElement>(
        `[data-message-id="${id}"]`,
      );
      if (!message) throw new Error(`no message ${id}`);
      return message;
    },
  };
}

function menuIsOpen(host: HTMLElement): boolean {
  return !host.hidden && host.querySelectorAll('[role="menuitem"]').length > 0;
}

describe("the key handlers act only on the message element itself", () => {
  let harness: Harness;

  beforeEach(() => {
    harness = build();
  });

  it("does not open the action menu for Enter pressed on a link inside the message", () => {
    const link = harness.messageOf("1").querySelector<HTMLElement>("a[href]")!;

    const event = keyDown(link, "Enter");

    expect(menuIsOpen(harness.host)).toBe(false);
    expect(event.defaultPrevented).toBe(false);
  });

  it("opens the action menu for Enter pressed on the message itself", () => {
    const event = keyDown(harness.messageOf("1"), "Enter");

    expect(menuIsOpen(harness.host)).toBe(true);
    expect(event.defaultPrevented).toBe(true);
  });

  it("opens the action menu for Space pressed on the message itself", () => {
    keyDown(harness.messageOf("1"), " ");

    expect(menuIsOpen(harness.host)).toBe(true);
  });

  it("does not open the action menu for Enter on a table, and leaves the key to the browser", () => {
    const table = harness.messageOf("2").querySelector<HTMLElement>("table")!;

    const event = keyDown(table, "Enter");

    expect(menuIsOpen(harness.host)).toBe(false);
    expect(event.defaultPrevented).toBe(false);
  });

  it("leaves Enter on a failed message's Retry control to that control", () => {
    const retry = harness
      .messageOf("3")
      .querySelector<HTMLElement>('[data-role="family-chat-message-retry"]');
    if (!retry) throw new Error("the failed message has no Retry control");

    const event = keyDown(retry, "Enter");

    expect(menuIsOpen(harness.host)).toBe(false);
    expect(event.defaultPrevented).toBe(false);
  });

  it("moves the stop on ArrowUp pressed on the message itself", () => {
    const event = keyDown(harness.messageOf("2"), "ArrowUp");

    expect(harness.store.rovingMove).toHaveBeenCalledWith("ArrowUp");
    expect(event.defaultPrevented).toBe(true);
  });

  it("does not move the stop for an arrow key on a table, so the table can scroll", () => {
    const table = harness.messageOf("2").querySelector<HTMLElement>("table")!;

    const event = keyDown(table, "ArrowRight");

    expect(harness.store.rovingMove).not.toHaveBeenCalled();
    expect(event.defaultPrevented).toBe(false);
  });

  it("does not move the stop for an arrow key on a link", () => {
    const link = harness.messageOf("1").querySelector<HTMLElement>("a[href]")!;

    const event = keyDown(link, "ArrowDown");

    expect(harness.store.rovingMove).not.toHaveBeenCalled();
    expect(event.defaultPrevented).toBe(false);
  });

  it("returns focus from a link to its message on Escape, and does nothing else", () => {
    const message = harness.messageOf("1");
    const link = message.querySelector<HTMLElement>("a[href]")!;
    link.focus();

    keyDown(link, "Escape");

    expect(document.activeElement).toBe(message);
    expect(menuIsOpen(harness.host)).toBe(false);
  });

  it("leaves focus where it is on Escape pressed on the message itself", () => {
    const message = harness.messageOf("2");
    message.focus();

    keyDown(message, "Escape");

    expect(document.activeElement).toBe(message);
  });
});
