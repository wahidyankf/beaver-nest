// @vitest-environment happy-dom
//
// Plain Vitest unit coverage for `js/family_chat/roving_focus.js`: the
// history's single tab stop and the arrow-key movement that carries it.
// Tech-doc 004's "Keyboard Navigation of the History" owns these rules.
//
// This file asks for a real DOM because the contract *is* a DOM contract:
// "exactly one `tabindex="0"` among the message items" is not a statement
// about data, and checking it against a hand-built stand-in would prove
// only that the stand-in agrees with itself. Where focus actually lands
// when the browser applies these attributes is FE_E2E's.

import { beforeEach, describe, expect, it } from "vitest";
import {
  createRovingFocus,
  rovingInvariantHolds,
} from "../../../js/family_chat/roving_focus.js";
import { messageNode } from "../../../js/family_chat/message_render.js";

function renderList(count: number): HTMLElement {
  const list = document.createElement("ol");
  for (let index = 0; index < count; index += 1) {
    list.append(
      messageNode(
        {
          id: String(1000 + index),
          body: `Message ${index}`,
          senderDisplayName: "Ayah",
          senderId: "u-ayah",
        },
        { pending: false, currentUserId: "u-me" },
      ),
    );
  }
  return list;
}

function tabIndexes(list: HTMLElement): number[] {
  return [...list.querySelectorAll('[data-role="family-chat-message"]')].map(
    (item) => (item as HTMLElement).tabIndex,
  );
}

function stopId(list: HTMLElement): string | undefined {
  const stop = list.querySelector<HTMLElement>(
    '[data-role="family-chat-message"][tabindex="0"]',
  );
  return stop?.dataset["messageId"];
}

describe("rovingInvariantHolds", () => {
  it("holds when exactly one item is the tab stop and the rest are skipped", () => {
    const list = renderList(3);
    createRovingFocus(list).refresh();

    expect(rovingInvariantHolds(list)).toBe(true);
  });

  it("fails when no item is reachable -- the history would be unreachable by Tab", () => {
    const list = renderList(3);
    createRovingFocus(list).refresh();
    list.querySelector<HTMLElement>('[tabindex="0"]')!.tabIndex = -1;

    expect(rovingInvariantHolds(list)).toBe(false);
  });

  it("fails when two items are reachable -- Tab would stop in the history twice", () => {
    const list = renderList(3);
    createRovingFocus(list).refresh();
    const items = list.querySelectorAll<HTMLElement>(
      '[data-role="family-chat-message"]',
    );
    items[0]!.tabIndex = 0;
    items[1]!.tabIndex = 0;

    expect(rovingInvariantHolds(list)).toBe(false);
  });

  it("holds vacuously for an empty history: there is nothing to reach", () => {
    expect(rovingInvariantHolds(renderList(0))).toBe(true);
  });
});

describe("createRovingFocus", () => {
  let list: HTMLElement;

  beforeEach(() => {
    list = renderList(50);
    document.body.replaceChildren(list);
  });

  it("puts the single stop on the newest message on first render", () => {
    createRovingFocus(list).refresh();

    expect(tabIndexes(list).filter((value) => value === 0)).toHaveLength(1);
    expect(stopId(list)).toBe("1049");
  });

  it("moves the stop up and down with the arrow keys", () => {
    const roving = createRovingFocus(list);
    roving.refresh();

    roving.move("ArrowUp");
    expect(stopId(list)).toBe("1048");

    roving.move("ArrowUp");
    expect(stopId(list)).toBe("1047");

    roving.move("ArrowDown");
    expect(stopId(list)).toBe("1048");
  });

  it("never leaves the list at either end", () => {
    const roving = createRovingFocus(list);
    roving.refresh();

    for (let step = 0; step < 100; step += 1) roving.move("ArrowUp");
    expect(stopId(list)).toBe("1000");
    expect(rovingInvariantHolds(list)).toBe(true);

    for (let step = 0; step < 100; step += 1) roving.move("ArrowDown");
    expect(stopId(list)).toBe("1049");
    expect(rovingInvariantHolds(list)).toBe(true);
  });

  it("jumps to the oldest loaded and the newest with Home and End", () => {
    const roving = createRovingFocus(list);
    roving.refresh();

    roving.move("Home");
    expect(stopId(list)).toBe("1000");

    roving.move("End");
    expect(stopId(list)).toBe("1049");
  });

  it("keeps exactly one stop through every movement", () => {
    const roving = createRovingFocus(list);
    roving.refresh();

    for (const key of ["ArrowUp", "ArrowUp", "Home", "ArrowDown", "End"]) {
      roving.move(key);
      expect(rovingInvariantHolds(list)).toBe(true);
    }
  });

  it("keeps the stop where the reader left it when newer messages arrive", () => {
    const roving = createRovingFocus(list);
    roving.refresh();
    roving.move("ArrowUp");
    roving.move("ArrowUp");

    list.append(
      messageNode(
        { id: "2000", body: "Later", senderDisplayName: "Bunda" },
        { pending: false },
      ),
    );
    roving.refresh();

    // Moving the stop to an arrival the reader has not reached would drag a
    // screen reader away from what they were reading.
    expect(stopId(list)).toBe("1047");
    expect(rovingInvariantHolds(list)).toBe(true);
  });

  it("falls back to the newest message when the stop's message is gone", () => {
    const roving = createRovingFocus(list);
    roving.refresh();
    roving.move("Home");

    list.querySelector('[data-message-id="1000"]')!.remove();
    roving.refresh();

    expect(stopId(list)).toBe("1049");
    expect(rovingInvariantHolds(list)).toBe(true);
  });

  it("moves the stop to a jump target, so a reader lands on it rather than past it", () => {
    const roving = createRovingFocus(list);
    roving.refresh();

    roving.moveTo("1020");

    expect(stopId(list)).toBe("1020");
    expect(rovingInvariantHolds(list)).toBe(true);
  });

  it("reads the stop back, so the menu knows which message Enter acts on", () => {
    const roving = createRovingFocus(list);
    roving.refresh();
    roving.move("ArrowUp");

    expect(roving.current()?.dataset["messageId"]).toBe("1048");
  });
});
