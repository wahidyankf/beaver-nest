// family_chat_graphql.feature's "Message body as safe HTML" Rule. Each Then reads the `bodyHtml` the send or the
// live subscription push answered at the exact origin; nothing here renders or re-parses the message itself.

import { randomUUID } from "node:crypto";
import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import {
  htmlContains,
  htmlLacks,
  isMessageBodyElement,
  keepsDiagramNote,
  marksDiagram,
  showsImage,
} from "../support/family-chat-body-html";
import { sendFromPage, sentMessage } from "../support/family-chat-messages";
import { scenario } from "../support/family-chat-state";
import {
  newestFamilyChatMessageId,
  postGraphQl,
  type FamilyChatMessage,
} from "../support/graphql";
import { familyChatSubscriptionEvents } from "../support/subscriptions.mts";

const { Then, When } = createBdd();

interface SubscriptionEvent {
  result: { data: { familyChatMessageCommitted: FamilyChatMessage } };
}

function sentBodyHtml(): string | undefined {
  return sentMessage()?.bodyHtml;
}

Then("the response's bodyHtml is the family chat message body element", () => {
  expect(isMessageBodyElement(sentBodyHtml()), sentBodyHtml()).toBe(true);
});

Then(
  "the response's bodyHtml contains {string}",
  ({ page }, fragment: string) => {
    void page;
    expect(htmlContains(sentBodyHtml(), fragment), sentBodyHtml()).toBe(true);
  },
);

Then("the response's bodyHtml lacks {string}", ({ page }, fragment: string) => {
  void page;
  expect(htmlLacks(sentBodyHtml(), fragment), sentBodyHtml()).toBe(true);
});

Then(
  "the response's bodyHtml shows the image as {string} at {string}",
  ({ page }, decision: string, address: string) => {
    void page;
    expect(showsImage(sentBodyHtml(), decision, address), sentBodyHtml()).toBe(
      true,
    );
  },
);

// The docstring is the message as typed. It is sent the way the send scenarios send a body, so its Markdown fence
// reaches the server unchanged.
When(
  "the user sends this family chat message with a fresh client message ID:",
  async ({ page }, body: string) => {
    scenario.baselineId = await newestFamilyChatMessageId(page);
    scenario.clientMessageId = randomUUID();
    scenario.knownBody = body;
    await sendFromPage(page, body, scenario.clientMessageId);
  },
);

Then("the response's bodyHtml marks a diagram for drawing", () => {
  expect(marksDiagram(sentBodyHtml()), sentBodyHtml()).toBe(true);
});

Then(
  "the response's bodyHtml keeps the diagram as a code block with the note {string}",
  ({ page }, note: string) => {
    void page;
    expect(keepsDiagramNote(sentBodyHtml(), note), sentBodyHtml()).toBe(true);
  },
);

// One event, for the message the other member committed, with the fragment in its HTML.
Then(
  "the subscriber receives exactly one committed-message event matching that message whose bodyHtml contains {string}",
  async ({ page }, fragment: string) => {
    await expect
      .poll(async () => (await familyChatSubscriptionEvents(page)).length, {
        timeout: 10_000,
      })
      .toBe(1);
    const [event] = (await familyChatSubscriptionEvents(
      page,
    )) as SubscriptionEvent[];
    const pushed = event?.result.data.familyChatMessageCommitted;
    expect(pushed?.id, "the event names the committed message").toBe(
      scenario.serverMessageId,
    );
    expect(htmlContains(pushed?.bodyHtml, fragment), pushed?.bodyHtml).toBe(
      true,
    );
  },
);

// The positive control reads `bodyPreview` from the same type, so an empty introspection answer fails.
// The introspection field is aliased so that no property access in this file uses the reserved `__type` name.
const QUOTE_TYPE_INTROSPECTION = `{ quoteType: __type(name: "FamilyChatMessageQuote") { fields { name } } }`;

Then(
  "the family chat quote type declares no bodyHtml field",
  async ({ page }) => {
    const response = await postGraphQl<{
      quoteType: { fields: { name: string }[] } | null;
    }>(page, page.context().request, QUOTE_TYPE_INTROSPECTION);
    expect(response.errors, JSON.stringify(response.errors)).toBeUndefined();
    const names = (response.data?.quoteType?.fields ?? []).map(
      (field) => field.name,
    );
    expect(names, "the quote type is introspected").toContain("bodyPreview");
    expect(names).not.toContain("bodyHtml");
  },
);
