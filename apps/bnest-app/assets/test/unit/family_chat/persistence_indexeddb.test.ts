// @vitest-environment happy-dom
//
// Plain Vitest unit coverage for the row `js/family_chat/persistence_indexeddb.js` writes to this device's IndexedDB
// (ADR 003, browser rule 5). The server HTML of a committed message is never stored: nothing caches it, so a sanitizer
// change cannot leave old markup on a device. The row holds the outbox fields and the raw body only.

import { describe, expect, it } from "vitest";
import { toRow } from "../../../js/family_chat/persistence_indexeddb.js";

const NAMESPACE = "u-me:ruang-keluarga";
const CREATED_AT = Date.UTC(2026, 10, 10);

describe("the row the outbox stores", () => {
  it("never carries bodyHtml, even when the message it is built from has one", () => {
    // Not annotated as a QueuedMessage: the server HTML is an extra field the queue must never persist.
    const queued = {
      clientMessageId: "c-1",
      body: "**not yet**",
      bodyHtml:
        '<div class="markdown-body"><p><strong>not yet</strong></p></div>',
      status: "Sending",
      attempt: 1,
      retryCount: 0,
      createdAt: CREATED_AT,
      nextRetryAt: 0,
      timerHandle: null,
    };
    const row = toRow(NAMESPACE, queued);

    expect(row).not.toHaveProperty("bodyHtml");
    expect(row.body).toBe("**not yet**");
  });

  it("holds exactly the outbox fields for an ordinary queued message", () => {
    const row = toRow(NAMESPACE, {
      clientMessageId: "c-2",
      body: "Dinner is ready",
      status: "Sending",
      attempt: 1,
      retryCount: 0,
      createdAt: CREATED_AT,
      nextRetryAt: 0,
      timerHandle: null,
    });

    expect(Object.keys(row).sort()).toEqual(
      [
        "attempt",
        "body",
        "clientMessageId",
        "createdAt",
        "key",
        "namespace",
        "nextRetryAt",
        "retryCount",
        "status",
      ].sort(),
    );
  });
});
