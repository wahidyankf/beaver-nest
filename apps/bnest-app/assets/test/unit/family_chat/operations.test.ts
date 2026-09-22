// Plain Vitest unit coverage for `js/family_chat/operations.js`: the one
// place any Family Chat GraphQL document is written. The point of this file
// is the agreement between the three documents — a subscription that omits
// `replyTo` while the query includes it produces a room where a reply's
// quote appears on reload and not on arrival, which is the hardest kind of
// bug to see (tech-doc 002).

import { describe, expect, it } from "vitest";
import {
  MESSAGE_FIELDS_BASE,
  REPLY_FIELDS,
  familyChatMessageCommittedSubscription,
  familyChatMessagesQuery,
  messageFields,
  sendFamilyChatMessageMutation,
} from "../../../js/family_chat/operations.js";

const documentsFor = (replies: boolean) => [
  familyChatMessagesQuery({ replies }),
  sendFamilyChatMessageMutation({ replies }),
  familyChatMessageCommittedSubscription({ replies }),
];

describe("messageFields", () => {
  it("omits the quote when replies are off", () => {
    expect(messageFields({ replies: false })).toBe(MESSAGE_FIELDS_BASE);
    expect(messageFields({ replies: false })).not.toContain("replyTo");
  });

  it("appends the quote when replies are on", () => {
    const fields = messageFields({ replies: true });

    expect(fields).toContain(MESSAGE_FIELDS_BASE.trim());
    expect(fields).toContain(REPLY_FIELDS.trim());
  });

  it("asks for a flat quote, never a nested one", () => {
    // One `replyTo` in the field list. A second would mean the quote had
    // been given a quote of its own, which the schema cannot serve.
    const occurrences = messageFields({ replies: true }).match(/replyTo/g);

    expect(occurrences).toHaveLength(1);
  });
});

describe("operation documents", () => {
  it("all three carry the quote when replies are on", () => {
    for (const document of documentsFor(true)) {
      expect(document).toContain("replyTo");
    }
  });

  it("all three omit the quote when replies are off", () => {
    for (const document of documentsFor(false)) {
      expect(document).not.toContain("replyTo");
    }
  });

  it("all three request exactly the same message fields", () => {
    for (const replies of [true, false]) {
      const fields = messageFields({ replies });
      for (const document of documentsFor(replies)) {
        expect(document).toContain(fields);
      }
    }
  });

  it("only the mutation declares the reply argument, and only when it is on", () => {
    expect(sendFamilyChatMessageMutation({ replies: true })).toContain(
      "$replyToMessageId: ID",
    );
    expect(sendFamilyChatMessageMutation({ replies: false })).not.toContain(
      "replyToMessageId",
    );
    expect(familyChatMessagesQuery({ replies: true })).not.toContain(
      "$replyToMessageId",
    );
  });
});
