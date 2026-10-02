// family_chat_graphql.feature's reply scenarios that need no subscription:
// the quote a reply's commit carries, its bounded preview, the targets the
// server refuses, and the flat quote of a reply to a reply. The subscription
// pair lives in family-chat-reply.steps.ts.

import { randomUUID } from "node:crypto";
import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import { login } from "../support/authentication";
import {
  commitFromPage,
  sendFromPage,
  sentMessage,
  sinceBaseline,
} from "../support/family-chat-messages";
import { scenario, scenarioIdentity } from "../support/family-chat-state";
import {
  newestFamilyChatMessageId,
  pageNodes,
  postGraphQl,
  queryFamilyChatMessages,
  sendFamilyChatMessage,
} from "../support/graphql";

const { Given, Then, When } = createBdd();

const graphemes = new Intl.Segmenter("en", { granularity: "grapheme" });

function graphemeCount(text: string): number {
  return [...graphemes.segment(text)].length;
}

Given(
  "a family chat message from another member is already committed in {string}",
  async ({ browser, $testInfo }, roomSlug: string) => {
    expect(roomSlug).toBe("ruang-keluarga");
    const other = scenarioIdentity($testInfo).child;
    const otherContext = await browser.newContext();
    try {
      const otherPage = await otherContext.newPage();
      await login(otherPage, other);
      scenario.replyTargetBody = `Nanti aku jemput jam 5 ${randomUUID()}`;
      const target = await sendFamilyChatMessage(
        otherPage,
        otherContext.request,
        scenario.replyTargetBody,
        randomUUID(),
      );
      expect(target.errors, JSON.stringify(target.errors)).toBeUndefined();
      scenario.replyTargetId = target.data?.sendFamilyChatMessage?.id ?? "";
      scenario.replyTargetSender = other.username;
    } finally {
      await otherContext.close();
    }
  },
);

When(
  "the user sends the family chat message {string} naming that message as the reply target",
  async ({ page }, body: string) => {
    await sendFromPage(page, body, randomUUID(), scenario.replyTargetId);
  },
);

Then("the response's quote names that reply target's server ID", () => {
  expect(scenario.replyTargetId).not.toBe("");
  expect(sentMessage()?.replyTo?.id).toBe(scenario.replyTargetId);
});

// The other member's account name and the body they sent, short enough that
// the preview is the whole body.
Then(
  "the response's quote reports that target's sender display name and a preview of its body",
  () => {
    const quote = sentMessage()?.replyTo;
    expect(quote?.senderDisplayName).toBe(scenario.replyTargetSender);
    expect(quote?.bodyPreview).toBe(scenario.replyTargetBody);
  },
);

// The response carries no quote, and neither does the message the room
// reports under its ID.
Then("the response's message carries no quote", async ({ page }) => {
  const message = sentMessage();
  expect(message, "the send committed").not.toBeNull();
  expect(message?.replyTo).toBeNull();
  const stored = (await sinceBaseline(page)).find(
    (node) => node.id === message?.id,
  );
  expect(stored, "the room reports the message").toBeDefined();
  expect(stored?.replyTo).toBeNull();
});

Given(
  "a committed family chat message whose body is 400 graphemes long",
  async ({ page }) => {
    scenario.replyTargetBody = "a".repeat(400);
    scenario.replyTargetId = await commitFromPage(
      page,
      scenario.replyTargetBody,
    );
  },
);

When(
  "the user sends a family chat reply naming that message as the reply target",
  async ({ page }) => {
    await sendFromPage(
      page,
      "Oke, aku siapin",
      randomUUID(),
      scenario.replyTargetId,
    );
  },
);

Then(
  "the response's quote preview keeps at most {int} graphemes before its ellipsis",
  ({ page }, budget: number) => {
    void page;
    const preview = sentMessage()?.replyTo?.bodyPreview ?? "";
    expect(preview, "the response carries a quote preview").not.toBe("");
    const kept = preview.endsWith("…") ? preview.slice(0, -1) : preview;
    expect(graphemeCount(kept)).toBeLessThanOrEqual(budget);
  },
);

Then("the response's quote preview ends with an ellipsis", () => {
  expect(sentMessage()?.replyTo?.bodyPreview.endsWith("…")).toBe(true);
});

// The quoted message as the room reports it to a reader: the whole body the
// Given wrote.
Then(
  "the quoted message's own body is returned in full, unshortened",
  async ({ page }) => {
    const [target] = pageNodes(
      await queryFamilyChatMessages(page, page.context().request, {
        afterId: String(Number(scenario.replyTargetId) - 1),
        limit: 1,
      }),
    );
    expect(target?.id).toBe(scenario.replyTargetId);
    expect(target?.body).toBe("a".repeat(400));
  },
);

When(
  "the user sends a family chat reply whose reply target is not a positive integer",
  async ({ page }) => {
    scenario.baselineId = await newestFamilyChatMessageId(page);
    scenario.clientMessageId = randomUUID();
    scenario.knownBody = `Balasan tanpa target ${scenario.clientMessageId}`;
    await sendFromPage(
      page,
      scenario.knownBody,
      scenario.clientMessageId,
      "not-a-number",
    );
  },
);

// The room committed nothing since the refused send's baseline.
Then(
  "the family chat room holds no message for that client message ID",
  async ({ page }) => {
    expect(await sinceBaseline(page)).toEqual([]);
  },
);

Given(
  "a committed family chat message {string}",
  async ({ page }, body: string) => {
    scenario.replyTargetId = await commitFromPage(page, body);
  },
);

Given(
  "a committed family chat reply to it reading {string}",
  async ({ page }, body: string) => {
    scenario.replyId = await commitFromPage(page, body, scenario.replyTargetId);
  },
);

When(
  "the user sends a family chat reply naming that reply as the reply target",
  async ({ page }) => {
    await sendFromPage(page, "Siap", randomUUID(), scenario.replyId);
  },
);

Then("the response's quote names the reply it answers", () => {
  expect(scenario.replyId).not.toBe("");
  expect(sentMessage()?.replyTo?.id).toBe(scenario.replyId);
});

// The quote is exactly its four fields, and the schema refuses a document
// that asks a quote for a quote of its own.
Then("that quote carries no quote of its own", async ({ page }) => {
  expect(Object.keys(sentMessage()?.replyTo ?? {}).toSorted()).toEqual([
    "bodyPreview",
    "id",
    "senderDisplayName",
    "senderKind",
  ]);
  const nested = await postGraphQl(
    page,
    page.context().request,
    `query($roomSlug: String!) {
      familyChatMessages(roomSlug: $roomSlug, limit: 1) { nodes { replyTo { replyTo { id } } } }
    }`,
    { roomSlug: "ruang-keluarga" },
  );
  expect(nested.data ?? null).toBeNull();
  expect(nested.errors?.[0]?.message).toContain("replyTo");
});
