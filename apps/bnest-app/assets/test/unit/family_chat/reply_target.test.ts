// Plain Vitest unit coverage for `js/family_chat/reply_target.js`: the
// reply-target lifecycle the composer, the action menu, and the outbox all
// share, with no DOM in sight. Tech-doc 004's "The Composer Reply Strip"
// owns these rules; this file is where they are pinned.

import { describe, expect, it } from "vitest";
import {
  REPLY_UNAVAILABLE_REASON,
  createReplyTarget,
} from "../../../js/family_chat/reply_target.js";

const AYAH = {
  messageId: "1042",
  senderDisplayName: "Ayah",
  bodyPreview: "Nanti aku jemput jam 5",
};

const BUNDA = {
  messageId: "1043",
  senderDisplayName: "Bunda",
  bodyPreview: "Oke, aku siapin",
};

describe("createReplyTarget", () => {
  it("starts with nothing selected", () => {
    const target = createReplyTarget();

    expect(target.current()).toBeNull();
    expect(target.isSet()).toBe(false);
  });

  it("holds the selected message's id, sender, and preview", () => {
    const target = createReplyTarget();

    target.select(AYAH);

    expect(target.isSet()).toBe(true);
    expect(target.current()).toEqual(AYAH);
  });

  it("replaces rather than stacks when another message is selected", () => {
    const target = createReplyTarget();

    target.select(AYAH);
    target.select(BUNDA);

    expect(target.current()).toEqual(BUNDA);
  });

  it("clears on request", () => {
    const target = createReplyTarget();

    target.select(AYAH);
    target.clear();

    expect(target.current()).toBeNull();
  });

  it("announces a selection once, and a cancellation once", () => {
    const announced: string[] = [];
    const target = createReplyTarget({
      announce: (message: string) => announced.push(message),
    });

    target.select(AYAH);
    target.clear();

    expect(announced).toEqual(["Replying to Ayah.", "Reply cancelled"]);
  });

  it("stays silent when clearing something already clear", () => {
    const announced: string[] = [];
    const target = createReplyTarget({
      announce: (message: string) => announced.push(message),
    });

    target.clear();

    expect(announced).toEqual([]);
  });

  it("refuses a message with no server id, and says why", () => {
    const target = createReplyTarget();

    const result = target.select({
      messageId: null,
      senderDisplayName: "You",
      bodyPreview: "Still sending",
    });

    expect(result.selected).toBe(false);
    expect(result.reason).toBe(REPLY_UNAVAILABLE_REASON);
    expect(target.current()).toBeNull();
  });

  it("notifies a subscriber on every change, and stops once unsubscribed", () => {
    const seen: (typeof AYAH | null)[] = [];
    const target = createReplyTarget();
    const unsubscribe = target.onChange((next) => seen.push(next));

    target.select(AYAH);
    target.clear();
    unsubscribe();
    target.select(BUNDA);

    expect(seen).toEqual([AYAH, null]);
  });
});
