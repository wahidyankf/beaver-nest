// Plain Vitest unit coverage for `js/family_chat/composer.js`: draft
// validation, the key chords, and the focus rule that keeps a mobile
// on-screen keyboard up across a send. The Gherkin scenarios cover the happy
// journeys; this file covers the refusals and the draft-restoring branch
// they do not reach.

import { describe, expect, it } from "vitest";
import {
  EMPTY_DRAFT_REMEDIATION,
  QUEUE_REFUSED_REMEDIATION,
  TOO_LONG_REMEDIATION,
  createComposer,
} from "../../../js/family_chat/composer.js";
import { createReplyTarget } from "../../../js/family_chat/reply_target.js";

function composerWith(sendResult: string | null) {
  const sent: { body: string; replyToMessageId?: string }[] = [];
  const state = {
    remediationMessage: /** @type {string | null} */ null as string | null,
  };
  const replyTarget = createReplyTarget();
  const composer = createComposer({
    outbox: {
      send: async (body: string, opts: { replyToMessageId?: string } = {}) => {
        sent.push({ body, ...opts });
        return sendResult;
      },
    },
    state,
    replyTarget,
    focused: true,
  });
  return { composer, sent, state, replyTarget, bodies: sent };
}

function bodiesOf(sent: { body: string }[]) {
  return sent.map((message) => message.body);
}

describe("createComposer", () => {
  it("queues a trimmed draft and clears the input", async () => {
    const { composer, sent } = composerWith("client-id");

    composer.type("  On my way  ");
    const result = await composer.submit();

    expect(result).toEqual({
      queued: true,
      clientMessageId: "client-id",
      remediation: null,
    });
    expect(bodiesOf(sent)).toEqual(["On my way"]);
    expect(composer.draft()).toBe("");
    expect(composer.remediation()).toBeNull();
  });

  it("keeps keyboard focus through a send", async () => {
    const { composer } = composerWith("client-id");

    composer.type("Still typing");
    await composer.submit();

    expect(composer.focused()).toBe(true);
    // The browser binding reads this to decide whether to let the Send
    // button's press take focus at all.
    expect(composer.focusFollowsSendControl()).toBe(false);
  });

  it("refuses an empty draft without reaching the outbox", async () => {
    const { composer, sent } = composerWith("client-id");

    composer.type("   ");
    const result = await composer.submit();

    expect(result.queued).toBe(false);
    expect(result.remediation).toBe(EMPTY_DRAFT_REMEDIATION);
    expect(bodiesOf(sent)).toEqual([]);
    expect(composer.draft()).toBe("   ");
  });

  it("refuses an over-long draft and keeps what was written", async () => {
    const { composer, sent } = composerWith("client-id");
    const tooLong = "x".repeat(4001);

    composer.type(tooLong);
    const result = await composer.submit();

    expect(result.remediation).toBe(TOO_LONG_REMEDIATION);
    expect(bodiesOf(sent)).toEqual([]);
    expect(composer.draft()).toBe(tooLong);
  });

  it("restores the draft when the outbox refuses to queue it", async () => {
    const { composer } = composerWith(null);

    composer.type("Queue is full");
    const result = await composer.submit();

    expect(result.queued).toBe(false);
    expect(result.remediation).toBe(QUEUE_REFUSED_REMEDIATION);
    expect(composer.draft()).toBe("Queue is full");
  });

  it("prefers a remediation the outbox already explained", async () => {
    const { composer, state } = composerWith(null);
    composer.type("Queue is full");

    // `onQueueFull` writes the specific remediation into the shared state
    // while the send is in flight.
    const submitted = composer.submit();
    state.remediationMessage = "Keep waiting messages under 100.";
    const result = await submitted;

    expect(result.remediation).toBe("Keep waiting messages under 100.");
  });

  it("reads Enter as send and Shift+Enter as a continued message", () => {
    const { composer } = composerWith("client-id");

    expect(composer.keyIntent({ key: "Enter" })).toBe("send");
    expect(composer.keyIntent({ key: "Enter", shiftKey: true })).toBe(
      "newline",
    );
    expect(composer.keyIntent({ key: "a" })).toBe("ignore");
  });

  it("continues a draft on a new line", () => {
    const { composer } = composerWith("client-id");

    composer.type("First line");
    composer.appendLine("Second line");

    expect(composer.draft()).toBe("First line\nSecond line");
  });

  it("tracks focus leaving and returning to the input", () => {
    const { composer } = composerWith("client-id");

    composer.blur();
    expect(composer.focused()).toBe(false);
    composer.focus();
    expect(composer.focused()).toBe(true);
  });
});

describe("composing a reply", () => {
  const AYAH = {
    messageId: "1042",
    senderDisplayName: "Ayah",
    bodyPreview: "Nanti aku jemput jam 5",
  };

  it("carries the reply target into the send", async () => {
    const { composer, sent, replyTarget } = composerWith("client-id");

    replyTarget.select(AYAH);
    composer.type("Oke, aku siapin");
    await composer.submit();

    expect(sent).toEqual([
      { body: "Oke, aku siapin", replyToMessageId: "1042" },
    ]);
  });

  it("sends no target key at all when none is set", async () => {
    const { composer, sent } = composerWith("client-id");

    composer.type("Dinner is ready");
    await composer.submit();

    expect(sent).toEqual([{ body: "Dinner is ready" }]);
  });

  it("clears the target once the message is queued", async () => {
    const { composer, replyTarget } = composerWith("client-id");

    replyTarget.select(AYAH);
    composer.type("Oke, aku siapin");
    await composer.submit();

    expect(replyTarget.current()).toBeNull();
  });

  it("keeps the target and the text when the queue refuses", async () => {
    const { composer, replyTarget } = composerWith(null);

    replyTarget.select(AYAH);
    composer.type("Oke, aku siapin");
    const result = await composer.submit();

    expect(result.queued).toBe(false);
    expect(replyTarget.current()).toEqual(AYAH);
    expect(composer.draft()).toBe("Oke, aku siapin");
  });

  it("keeps the target when the draft itself is refused", async () => {
    const { composer, sent, replyTarget } = composerWith("client-id");

    replyTarget.select(AYAH);
    composer.type("   ");
    await composer.submit();

    expect(bodiesOf(sent)).toEqual([]);
    expect(replyTarget.current()).toEqual(AYAH);
  });

  it("tells the queued message which target it answered", async () => {
    const queued: { replyToMessageId?: string }[] = [];
    const state = { remediationMessage: null as string | null };
    const replyTarget = createReplyTarget();
    const composer = createComposer({
      outbox: { send: async () => "client-id" },
      state,
      replyTarget,
      onQueued: (message: { replyToMessageId?: string }) =>
        queued.push(message),
    });

    replyTarget.select(AYAH);
    composer.type("Oke, aku siapin");
    await composer.submit();

    expect(queued[0]?.replyToMessageId).toBe("1042");
  });

  it("works with no reply target wired at all", async () => {
    const state = { remediationMessage: null as string | null };
    const sent: { body: string; replyToMessageId?: string }[] = [];
    const composer = createComposer({
      outbox: {
        send: async (
          body: string,
          opts: { replyToMessageId?: string } = {},
        ) => {
          sent.push({ body, ...opts });
          return "client-id";
        },
      },
      state,
    });

    composer.type("Dinner is ready");
    const result = await composer.submit();

    expect(result.queued).toBe(true);
    expect(sent).toEqual([{ body: "Dinner is ready" }]);
  });
});
