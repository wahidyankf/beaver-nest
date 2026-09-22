// @vitest-environment happy-dom
//
// Plain Vitest unit coverage for the quote card: what a reply renders inside
// its bubble, and the fact that every window path renders the same thing.
// Tech-doc 004's "The Quote Card" owns the markup and the accessible name;
// tech-doc 003's Copy Inventory owns the exact wording.
//
// A real DOM, because a quote card is markup and an accessible name, not
// data. Whether a browser's accessibility tree actually computes that name
// the way the attribute says is FE_E2E's.

import { beforeEach, describe, expect, it } from "vitest";
import { messageNode } from "../../../js/family_chat/message_render.js";
import { createRealStore } from "../../../js/family_chat/real_store.js";

const QUOTE = '[data-role="family-chat-message-quote"]';

const AYAH_QUOTE = {
  id: "1042",
  senderKind: "user",
  senderDisplayName: "Ayah",
  bodyPreview: "Nanti aku jemput jam 5",
};

type RenderableMessage =
  import("../../../js/family_chat/real_store.js").RenderableMessage;

function reply(overrides: Record<string, unknown> = {}): RenderableMessage {
  return {
    id: "1043",
    body: "Oke, aku siap",
    senderDisplayName: "Bunda",
    senderId: "u-bunda",
    replyTo: AYAH_QUOTE,
    ...overrides,
  } as RenderableMessage;
}

function render(message: RenderableMessage): HTMLElement {
  return messageNode(message, { pending: false, currentUserId: "u-me" });
}

describe("messageNode quote rendering", () => {
  it("renders a quote card for a message that answers another", () => {
    const quote = render(reply()).querySelector(QUOTE);

    expect(quote).not.toBeNull();
  });

  it("renders no quote for an ordinary message", () => {
    expect(
      render(reply({ replyTo: undefined })).querySelector(QUOTE),
    ).toBeNull();
    expect(render(reply({ replyTo: null })).querySelector(QUOTE)).toBeNull();
  });

  it("shows the quoted sender and the server's own preview", () => {
    const node = render(reply());

    expect(
      node.querySelector('[data-role="family-chat-message-quote-sender"]')
        ?.textContent,
    ).toBe("Ayah");
    expect(
      node.querySelector('[data-role="family-chat-message-quote-preview"]')
        ?.textContent,
    ).toBe("Nanti aku jemput jam 5");
  });

  it("composes the accessible name: relationship, content, then affordance", () => {
    const quote = render(reply()).querySelector(QUOTE);

    expect(quote?.getAttribute("aria-label")).toBe(
      "Reply to Ayah: Nanti aku jemput jam 5. Go to that message.",
    );
  });

  it("is a button, because activating it acts in place rather than navigating", () => {
    const quote = render(reply()).querySelector(QUOTE) as HTMLButtonElement;

    expect(quote.tagName).toBe("BUTTON");
    expect(quote.type).toBe("button");
  });

  it("carries the target's id, which is what the jump needs", () => {
    const quote = render(reply()).querySelector<HTMLElement>(QUOTE);

    expect(quote?.dataset["targetMessageId"]).toBe("1042");
  });

  it("names a system message's quoted sender as System", () => {
    const node = render(
      reply({ replyTo: { ...AYAH_QUOTE, senderKind: "system" } }),
    );

    expect(
      node.querySelector('[data-role="family-chat-message-quote-sender"]')
        ?.textContent,
    ).toBe("System");
  });

  it("escapes the quoted text rather than interpreting it", () => {
    const node = render(
      reply({
        replyTo: { ...AYAH_QUOTE, bodyPreview: "<img src=x onerror=1>" },
      }),
    );

    expect(node.querySelector("img")).toBeNull();
    expect(
      node.querySelector('[data-role="family-chat-message-quote-preview"]')
        ?.textContent,
    ).toBe("<img src=x onerror=1>");
  });

  it("never nests a quote inside a quote, whatever the payload carries", () => {
    // The GraphQL type makes this unrepresentable; the renderer takes no
    // nesting parameter either, so a payload that somehow carried one still
    // renders flat.
    const node = render(
      reply({
        replyTo: { ...AYAH_QUOTE, replyTo: { ...AYAH_QUOTE, id: "999" } },
      }),
    );

    expect(node.querySelectorAll(QUOTE)).toHaveLength(1);
  });
});

describe("every window path renders the same quote", () => {
  let elements: Record<string, HTMLElement>;

  beforeEach(() => {
    document.body.innerHTML = `
      <div data-role="family-chat-history">
        <button data-role="family-chat-load-older"></button>
        <p data-role="family-chat-empty"></p>
        <ol data-role="family-chat-message-list"></ol>
        <span data-role="family-chat-scroll-anchor"></span>
      </div>
      <button data-role="family-chat-new-messages"></button>
      <p data-role="family-chat-live-region"></p>
    `;
    elements = Object.fromEntries(
      [
        "history",
        "loadOlder",
        "empty",
        "list",
        "scrollAnchor",
        "newMessages",
        "liveRegion",
      ].map((name) => [
        name,
        document.querySelector(
          `[data-role="family-chat-${
            {
              history: "history",
              loadOlder: "load-older",
              empty: "empty",
              list: "message-list",
              scrollAnchor: "scroll-anchor",
              newMessages: "new-messages",
              liveRegion: "live-region",
            }[name]
          }"]`,
        ) as HTMLElement,
      ]),
    );
  });

  function store() {
    return createRealStore({
      roomSlug: "ruang-keluarga",
      // eslint-disable-next-line @typescript-eslint/no-explicit-any -- the real shape is the template's; this fixture carries the fields the store reads.
      elements: elements as any,
      currentUserId: "u-me",
    });
  }

  function quoteText(): string | null {
    return (
      document.querySelector(
        `${QUOTE} [data-role="family-chat-message-quote-preview"]`,
      )?.textContent ?? null
    );
  }

  it("renders the quote on the initial page", () => {
    store().renderInitial([reply()], false);

    expect(quoteText()).toBe("Nanti aku jemput jam 5");
  });

  it("renders the quote on an older page", () => {
    const real = store();
    real.renderInitial([reply({ id: "2000", replyTo: undefined })], true);
    real.prependOlder([reply()], false);

    expect(quoteText()).toBe("Nanti aku jemput jam 5");
  });

  it("renders the quote on a resumed window", () => {
    store().renderResumed({
      contextNodes: [],
      unreadNodes: [reply()],
      hasOlder: false,
      hasNewer: false,
    });

    expect(quoteText()).toBe("Nanti aku jemput jam 5");
  });

  it("renders the quote on an appended newer page", () => {
    const real = store();
    real.renderInitial([reply({ id: "2000", replyTo: undefined })], false);
    real.appendNewer([reply()], false);

    expect(quoteText()).toBe("Nanti aku jemput jam 5");
  });

  it("renders the quote when the visitor's own send is reconciled", () => {
    const real = store();
    real.renderPending({ clientMessageId: "c-1", body: "Oke, aku siap" });
    expect(quoteText()).toBeNull();

    real.reconcile("c-1", reply());

    expect(quoteText()).toBe("Nanti aku jemput jam 5");
  });

  it("renders the quote when a remote arrival lands live", async () => {
    const real = store();
    real.renderInitial([reply({ id: "2000", replyTo: undefined })], false);
    await real.receiveRemoteMessage(reply());

    expect(quoteText()).toBe("Nanti aku jemput jam 5");
  });
});
