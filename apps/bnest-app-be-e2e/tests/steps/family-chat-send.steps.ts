// family_chat_graphql.feature's send and idempotent-retry scenarios, posted
// at the exact origin by the member the Background logged in.
//
// The client message ID is never exposed over GraphQL, so "the room holds
// exactly one message for that client message ID" is read as the room
// reports it: every message committed after the scenario's own baseline.
// Scenarios run one at a time, so nothing else commits in between.

import { randomUUID } from "node:crypto";
import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import {
  commitFromPage,
  sendFromPage,
  sentMessage,
  sinceBaseline,
} from "../support/family-chat-messages";
import {
  requireResponse,
  scenario,
  scenarioIdentity,
} from "../support/family-chat-state";
import { newestFamilyChatMessageId } from "../support/graphql";

const { Given, Then, When } = createBdd();

// The outline's `<body>` tokens name the invalid bodies the server must
// refuse; the real bodies are built here.
function expandBody(body: string): string {
  if (body === "whitespace-only-body") return "   \n\t  ";
  if (body === "over-4000-graphemes-normalized-body") return "a".repeat(4001);
  // One base letter and five combining marks is one grapheme of 11 bytes, so
  // this crosses 16 KiB while staying under 4000 graphemes.
  if (body === "over-16-kib-body") return `e${"́".repeat(5)}`.repeat(1500);
  return body;
}

When(
  "the user sends the family chat message {string} with a fresh client message ID",
  async ({ page }, body: string) => {
    scenario.baselineId = await newestFamilyChatMessageId(page);
    scenario.clientMessageId = randomUUID();
    scenario.knownBody = expandBody(body);
    await sendFromPage(page, scenario.knownBody, scenario.clientMessageId);
  },
);

Then(
  "the response returns the committed message with a server ID and commit time",
  () => {
    const message = sentMessage();
    expect(message, JSON.stringify(requireResponse().errors)).not.toBeNull();
    expect(message?.id).toMatch(/^[1-9]\d*$/u);
    expect(Number.isNaN(Date.parse(message?.committedAt ?? ""))).toBe(false);
  },
);

Then(
  "the family chat room holds exactly one message with that client message ID",
  async ({ page }) => {
    const committedNow = await sinceBaseline(page);
    expect(committedNow.map((node) => [node.id, node.body])).toEqual([
      [sentMessage()?.id, scenario.knownBody],
    ]);
  },
);

// The account's display username is the one the scenario seeded and logged
// in with; the user ID is a different, internal value.
Then(
  "the response reports the sender's real display username, not their raw user ID",
  ({ $testInfo }) => {
    const message = sentMessage();
    const username = scenarioIdentity($testInfo).admin.username;
    expect(message?.senderDisplayName).toBe(username);
    expect(message?.senderId).not.toBe(username);
  },
);

Given(
  "the user already sent the family chat message {string} with a known client message ID",
  async ({ page }, body: string) => {
    scenario.baselineId = await newestFamilyChatMessageId(page);
    scenario.clientMessageId = randomUUID();
    scenario.knownBody = body;
    const first = await sendFromPage(page, body, scenario.clientMessageId);
    scenario.originalId = first?.id ?? "";
    expect(scenario.originalId, "the first send committed").not.toBe("");
  },
);

When(
  "the user resends a different body with the same client message ID",
  async ({ page }) => {
    await sendFromPage(
      page,
      `a different body than ${scenario.knownBody}`,
      scenario.clientMessageId,
    );
  },
);

Then("the response returns the original committed message unchanged", () => {
  const message = sentMessage();
  expect(message?.id).toBe(scenario.originalId);
  expect(message?.body).toBe(scenario.knownBody);
});

// The original is the only message the room committed with the scenario's
// body since the baseline, and no message carries the retry's body.
Then(
  "the family chat room still holds exactly one message for that client message ID",
  async ({ page }) => {
    const committedNow = await sinceBaseline(page);
    expect(
      committedNow
        .filter((node) => node.body === scenario.knownBody)
        .map((node) => node.id),
    ).toEqual([scenario.originalId]);
    expect(
      committedNow.filter((node) => node.body.startsWith("a different body")),
    ).toEqual([]);
  },
);

// Two candidate targets, so the retry can name a genuinely different one.
Given(
  "the user already sent a family chat reply to a known message with a known client message ID",
  async ({ page }) => {
    scenario.replyTargetId = await commitFromPage(page, "first target");
    scenario.secondTargetId = await commitFromPage(page, "second target");
    scenario.baselineId = scenario.secondTargetId;
    scenario.clientMessageId = randomUUID();
    scenario.knownBody = `Oke, aku siapin ${scenario.clientMessageId}`;
    const reply = await sendFromPage(
      page,
      scenario.knownBody,
      scenario.clientMessageId,
      scenario.replyTargetId,
    );
    scenario.originalId = reply?.id ?? "";
    expect(scenario.originalId, "the reply committed").not.toBe("");
  },
);

When(
  "the user resends the same client message ID naming a different reply target",
  async ({ page }) => {
    await sendFromPage(
      page,
      scenario.knownBody,
      scenario.clientMessageId,
      scenario.secondTargetId,
    );
  },
);

// The response's quote, and the quote the room reports for that message.
Then(
  "that message's quote still names the reply target committed first",
  async ({ page }) => {
    expect(sentMessage()?.replyTo?.id).toBe(scenario.replyTargetId);
    const stored = (await sinceBaseline(page)).find(
      (node) => node.id === scenario.originalId,
    );
    expect(stored?.replyTo?.id).toBe(scenario.replyTargetId);
  },
);

Then("the family chat room gains no new message", async ({ page }) => {
  expect(await sinceBaseline(page)).toEqual([]);
});
