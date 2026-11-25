// Plain Vitest unit coverage for `js/family_chat/operations.js`: the one
// place any Family Chat GraphQL document is written. The point of this file
// is the agreement between the three documents — a subscription that omits
// `replyTo` while the query includes it produces a room where a reply's
// quote appears on reload and not on arrival, which is the hardest kind of
// bug to see (tech-doc 002). There is exactly one document shape: replies
// always ship, so every builder takes no options and always carries the
// quote.

import { describe, expect, it } from "vitest";
import {
  MESSAGE_FIELDS_BASE,
  REPLY_FIELDS,
  familyChatMessageCommittedSubscription,
  familyChatMessagesQuery,
  messageFields,
  sendFamilyChatMessageMutation,
} from "../../../js/family_chat/operations.js";

const documents = () => [
  familyChatMessagesQuery(),
  sendFamilyChatMessageMutation(),
  familyChatMessageCommittedSubscription(),
];

describe("messageFields", () => {
  it("always appends the quote", () => {
    const fields = messageFields();

    expect(fields).toContain(MESSAGE_FIELDS_BASE.trim());
    expect(fields).toContain(REPLY_FIELDS.trim());
  });

  it("asks for a flat quote, never a nested one", () => {
    // One `replyTo` in the field list. A second would mean the quote had
    // been given a quote of its own, which the schema cannot serve.
    const occurrences = messageFields().match(/replyTo/g);

    expect(occurrences).toHaveLength(1);
  });
});

describe("operation documents", () => {
  it("all three carry the quote", () => {
    for (const document of documents()) {
      expect(document).toContain("replyTo");
    }
  });

  it("all three request exactly the same message fields", () => {
    const fields = messageFields();
    for (const document of documents()) {
      expect(document).toContain(fields);
    }
  });

  it("only the mutation declares the reply argument", () => {
    expect(sendFamilyChatMessageMutation()).toContain("$replyToMessageId: ID");
    expect(familyChatMessagesQuery()).not.toContain("$replyToMessageId");
  });
});

describe("the rendered body", () => {
  // ADR 003, browser rule 1: one edit to the base field list covers query, mutation, and subscription.
  it("sits in the base field list, so no flag can drop it", () => {
    expect(MESSAGE_FIELDS_BASE).toMatch(/\bbodyHtml\b/u);
  });

  it("is requested by all three documents", () => {
    for (const document of documents()) {
      expect(document).toMatch(/\bbodyHtml\b/u);
    }
  });
});
