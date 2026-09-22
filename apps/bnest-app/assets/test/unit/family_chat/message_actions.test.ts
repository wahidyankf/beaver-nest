// Plain Vitest unit coverage for `js/family_chat/message_actions.js`: the
// action menu's three separable concerns -- gesture recognition, menu state,
// and action execution -- without a browser. Tech-doc 004's "The Action
// Menu" owns these rules.
//
// What is deliberately *not* here: where DOM focus actually lands, and
// whether a real long-press on a real touchscreen produces these events at
// all. Both need a focus and input engine, and both are proven at FE_E2E.

import { describe, expect, it, vi } from "vitest";
import {
  COPIED_ANNOUNCEMENT,
  COPY_REFUSED_ANNOUNCEMENT,
  HOLD_DURATION_MS,
  HOLD_MOVE_TOLERANCE_PX,
  createHoldGesture,
  createMenuState,
  menuItemsFor,
  runCopyAction,
} from "../../../js/family_chat/message_actions.js";
import { REPLY_UNAVAILABLE_REASON } from "../../../js/family_chat/reply_target.js";
import { createFakeClock } from "./support/fake_clock";

const COMMITTED = {
  clientMessageId: "c-1",
  messageId: "1042",
  body: "Nanti aku jemput jam 5",
  senderDisplayName: "Ayah",
};

const QUEUED = {
  clientMessageId: "c-2",
  messageId: null,
  body: "Oke",
  senderDisplayName: "You",
};

describe("createHoldGesture", () => {
  it("opens once the hold reaches the full duration", () => {
    const clock = createFakeClock();
    const onHold = vi.fn();
    const gesture = createHoldGesture({ clock, onHold });

    gesture.start({ x: 10, y: 10 });
    clock.advance(HOLD_DURATION_MS);

    expect(onHold).toHaveBeenCalledTimes(1);
  });

  it("does not open when the pointer is released early", () => {
    const clock = createFakeClock();
    const onHold = vi.fn();
    const gesture = createHoldGesture({ clock, onHold });

    gesture.start({ x: 10, y: 10 });
    clock.advance(HOLD_DURATION_MS - 1);
    gesture.end();
    clock.advance(HOLD_DURATION_MS);

    expect(onHold).not.toHaveBeenCalled();
  });

  it("does not open when the pointer moves past the tolerance", () => {
    const clock = createFakeClock();
    const onHold = vi.fn();
    const gesture = createHoldGesture({ clock, onHold });

    gesture.start({ x: 10, y: 10 });
    gesture.move({ x: 10, y: 10 + HOLD_MOVE_TOLERANCE_PX + 1 });
    clock.advance(HOLD_DURATION_MS);

    expect(onHold).not.toHaveBeenCalled();
  });

  it("tolerates movement within the threshold -- a hold is never perfectly still", () => {
    const clock = createFakeClock();
    const onHold = vi.fn();
    const gesture = createHoldGesture({ clock, onHold });

    gesture.start({ x: 10, y: 10 });
    gesture.move({ x: 13, y: 14 });
    clock.advance(HOLD_DURATION_MS);

    expect(onHold).toHaveBeenCalledTimes(1);
  });

  it("measures movement from where the press began, not from the last move", () => {
    const clock = createFakeClock();
    const onHold = vi.fn();
    const gesture = createHoldGesture({ clock, onHold });

    gesture.start({ x: 0, y: 0 });
    for (let step = 1; step <= 6; step += 1) {
      gesture.move({ x: 0, y: step * 3 });
    }
    clock.advance(HOLD_DURATION_MS);

    expect(onHold).not.toHaveBeenCalled();
  });

  it("cancels on pointercancel, the way an interrupting scroll arrives", () => {
    const clock = createFakeClock();
    const onHold = vi.fn();
    const gesture = createHoldGesture({ clock, onHold });

    gesture.start({ x: 10, y: 10 });
    gesture.cancel();
    clock.advance(HOLD_DURATION_MS);

    expect(onHold).not.toHaveBeenCalled();
  });
});

describe("createMenuState", () => {
  it("starts closed", () => {
    const menu = createMenuState();

    expect(menu.openFor()).toBeNull();
    expect(menu.isOpen()).toBe(false);
  });

  it("reaches one open function from every trigger", () => {
    const clock = createFakeClock();
    const menu = createMenuState();
    const gesture = createHoldGesture({
      clock,
      onHold: () => menu.open(COMMITTED),
    });

    // 1. press and hold
    gesture.start({ x: 1, y: 1 });
    clock.advance(HOLD_DURATION_MS);
    expect(menu.openFor()).toEqual(COMMITTED);
    menu.close();

    // 2. the browser context menu, 3. the actions control, 4. Enter on the
    // focused message -- all three are a direct call, which is the point:
    // there is one entry point, and the bindings differ only in the event.
    for (const _trigger of ["contextmenu", "actions-control", "keyboard"]) {
      menu.open(COMMITTED);
      expect(menu.isOpen()).toBe(true);
      menu.close();
    }
  });

  it("holds only one message open at a time", () => {
    const menu = createMenuState();

    menu.open(COMMITTED);
    menu.open(QUEUED);

    expect(menu.openFor()).toEqual(QUEUED);
  });

  it("remembers the message to return focus to, and forgets it on close", () => {
    const menu = createMenuState();

    menu.open(COMMITTED);
    expect(menu.returnFocusTo()).toEqual(COMMITTED);

    menu.close();
    expect(menu.openFor()).toBeNull();
    expect(menu.returnFocusTo()).toEqual(COMMITTED);
  });

  it("notifies listeners on open and on close", () => {
    const menu = createMenuState();
    const seen: (typeof COMMITTED | null)[] = [];
    menu.onChange((next) => seen.push(next));

    menu.open(COMMITTED);
    menu.close();

    expect(seen).toEqual([COMMITTED, null]);
  });
});

describe("menuItemsFor", () => {
  it("offers exactly Reply and Copy text, in that order", () => {
    expect(menuItemsFor(COMMITTED).map((item) => item.label)).toEqual([
      "Reply",
      "Copy text",
    ]);
  });

  it("makes both available for a committed message", () => {
    expect(menuItemsFor(COMMITTED).every((item) => item.available)).toBe(true);
  });

  it("makes Reply unavailable, with its reason, before the message has a server ID", () => {
    const [reply] = menuItemsFor(QUEUED);

    expect(reply.available).toBe(false);
    expect(reply.reason).toBe(REPLY_UNAVAILABLE_REASON);
  });

  it("keeps Copy text available on a message that has not sent yet", () => {
    const [, copy] = menuItemsFor(QUEUED);

    expect(copy.available).toBe(true);
    expect(copy.reason).toBeNull();
  });

  it("does not special-case a sender kind: a system message can be replied to", () => {
    const system = { ...COMMITTED, senderKind: "system" };

    expect(menuItemsFor(system)[0].available).toBe(true);
  });
});

describe("runCopyAction", () => {
  it("writes the full body, not the preview, and announces the copy", async () => {
    const written: string[] = [];
    const announce = vi.fn();
    const long = { ...COMMITTED, body: "a".repeat(400) };

    await runCopyAction(long, {
      writeText: async (text: string) => {
        written.push(text);
      },
      announce,
    });

    expect(written).toEqual([long.body]);
    expect(announce).toHaveBeenCalledWith(COPIED_ANNOUNCEMENT);
  });

  it("reports a refused clipboard instead of swallowing it", async () => {
    const announce = vi.fn();

    await runCopyAction(COMMITTED, {
      writeText: async () => {
        throw new Error("NotAllowedError");
      },
      announce,
    });

    expect(announce).toHaveBeenCalledWith(COPY_REFUSED_ANNOUNCEMENT);
  });

  it("reports the same refusal when the browser exposes no clipboard at all", async () => {
    const announce = vi.fn();

    await runCopyAction(COMMITTED, { writeText: undefined, announce });

    expect(announce).toHaveBeenCalledWith(COPY_REFUSED_ANNOUNCEMENT);
  });

  it("resolves rather than rejecting, so a caller never sees an unhandled rejection", async () => {
    await expect(
      runCopyAction(COMMITTED, {
        writeText: async () => {
          throw new Error("NotAllowedError");
        },
        announce: () => {},
      }),
    ).resolves.toBe(false);
  });
});
