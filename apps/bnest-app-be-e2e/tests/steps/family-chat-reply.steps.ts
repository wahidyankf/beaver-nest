// The reply plan's two subscription scenarios: a quote surviving the live
// push, and a quote surviving the `afterId` catch-up.
//
// Split from `family-chat.steps.ts` because that file reached its 300-line
// budget. playwright-bdd gathers step definitions from every file under
// this directory, so the split is invisible to the runner; the values the
// two files hand each other live on the shared `scenario` object.

import { randomUUID } from "node:crypto";
import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import { login } from "../support/authentication";
import {
  requireCatchUp,
  requireIdentity,
  requireResponse,
  scenario,
} from "../support/family-chat-state";
import { isolatedTestIdentity } from "../support/test-identity";
import { sendFromPage, sentMessage } from "../support/family-chat-messages";
import {
  newestFamilyChatMessageId,
  pageNodes,
  postGraphQl,
  sendFamilyChatMessage,
} from "../support/graphql";
import { familyChatSubscriptionEvents } from "../support/subscriptions";

const { Given, Then, When } = createBdd();

interface SubscriptionEvent {
  result: {
    data: {
      familyChatMessageCommitted: {
        id: string;
        replyTo: { id: string } | null;
      };
    };
  };
}

async function eventsMatching(
  page: Parameters<typeof familyChatSubscriptionEvents>[0],
  messageId: string,
): Promise<SubscriptionEvent[]> {
  const events = (await familyChatSubscriptionEvents(
    page,
  )) as SubscriptionEvent[];
  return events.filter(
    (event) => event.result.data.familyChatMessageCommitted.id === messageId,
  );
}

When(
  "another member sends a family chat reply to one of the user's messages",
  async ({ page, browser }) => {
    // The user's own message is committed first, so there is something of
    // theirs to answer. It publishes its own event to this same subscriber,
    // which is why the assertions below count events matching the REPLY's
    // server ID rather than counting the mailbox.
    const target = await sendFamilyChatMessage(
      page,
      page.context().request,
      "Nanti aku jemput jam 5",
      randomUUID(),
    );
    expect(target.errors, JSON.stringify(target.errors)).toBeUndefined();
    scenario.replyTargetId = target.data?.sendFamilyChatMessage?.id as string;

    const otherContext = await browser.newContext();
    try {
      const otherPage = await otherContext.newPage();
      await login(otherPage, requireIdentity().child);
      const reply = await sendFamilyChatMessage(
        otherPage,
        otherContext.request,
        "Oke, aku siapin",
        randomUUID(),
        scenario.replyTargetId,
      );
      expect(reply.errors, JSON.stringify(reply.errors)).toBeUndefined();
      scenario.replyId = reply.data?.sendFamilyChatMessage?.id as string;
    } finally {
      await otherContext.close();
    }
  },
);

Then(
  "the subscriber receives exactly one committed-message event matching that reply",
  async ({ page }) => {
    await expect
      .poll(async () => (await eventsMatching(page, scenario.replyId)).length, {
        timeout: 10_000,
      })
      .toBe(1);
  },
);

Then(
  "that event's message carries a quote naming the message it answers",
  async ({ page }) => {
    const [event] = await eventsMatching(page, scenario.replyId);
    expect(event, "expected a subscription event for the reply").toBeDefined();
    expect(event?.result.data.familyChatMessageCommitted.replyTo?.id).toBe(
      scenario.replyTargetId,
    );
  },
);

Given(
  "a family chat reply committed before the user's subscription started",
  async ({ page, $testInfo }) => {
    scenario.identity = isolatedTestIdentity($testInfo);
    await page.context().clearCookies();
    await login(page, requireIdentity().admin);

    // Same baseline-before-sending reasoning as the plain catch-up Given
    // above: afterId is exclusive-after, so the cursor must sit strictly
    // before the target as well as the reply.
    const before = await postGraphQl<{
      familyChatMessages: { nodes: { id: string }[] };
    }>(
      page,
      page.context().request,
      `query($roomSlug: String!) { familyChatMessages(roomSlug: $roomSlug) { nodes { id } } }`,
      { roomSlug: "ruang-keluarga" },
    );
    expect(before.errors, JSON.stringify(before.errors)).toBeUndefined();
    const knownIds = (before.data?.familyChatMessages.nodes ?? []).map((node) =>
      Number(node.id),
    );
    scenario.afterId = String(knownIds.length > 0 ? Math.max(...knownIds) : 0);

    const target = await sendFamilyChatMessage(
      page,
      page.context().request,
      "Nanti aku jemput jam 5",
      randomUUID(),
    );
    expect(target.errors, JSON.stringify(target.errors)).toBeUndefined();
    scenario.replyTargetId = target.data?.sendFamilyChatMessage?.id as string;

    const reply = await sendFamilyChatMessage(
      page,
      page.context().request,
      "Oke, aku siapin",
      randomUUID(),
      scenario.replyTargetId,
    );
    expect(reply.errors, JSON.stringify(reply.errors)).toBeUndefined();
    scenario.replyId = reply.data?.sendFamilyChatMessage?.id as string;
  },
);

Then("the response includes that reply", () => {
  const nodes = pageNodes(requireCatchUp());
  expect(nodes.some((node) => node.id === scenario.replyId)).toBe(true);
});

Then("that reply carries a quote naming the message it answers", () => {
  const nodes = pageNodes(requireCatchUp());
  const reply = nodes.find((node) => node.id === scenario.replyId);
  expect(reply, "expected the reply in the catch-up page").toBeDefined();
  expect(reply?.replyTo?.id).toBe(scenario.replyTargetId);
});

// --- A reply target the server cannot honour ----------------------------
//
// Shared by the rejected-target outline and the subscription scenario: the
// refusal comes back on the HTTP response, the room commits nothing after the
// baseline taken just before the send, and a real socket that subscribed
// before the send receives nothing (the unit layer drains its own mailbox).

When(
  "the user sends a family chat reply whose reply target names a server ID no message has",
  async ({ page }) => {
    scenario.baselineId = await newestFamilyChatMessageId(page);
    scenario.clientMessageId = randomUUID();
    scenario.knownBody = `Balasan ke pesan yang tidak ada ${scenario.clientMessageId}`;
    await sendFromPage(
      page,
      scenario.knownBody,
      scenario.clientMessageId,
      // Far beyond any seeded row, and a valid positive integer, so the
      // refusal can only come from the target not existing.
      "999000999",
    );
  },
);

Then("the response reports a validation failure", () => {
  const response = requireResponse();
  expect(
    response.errors?.map((error) => error.extensions?.["code"]),
    "expected the send to be refused, not committed",
  ).toEqual(["VALIDATION_FAILED"]);
  expect(sentMessage()).toBeNull();
});

Then("no committed-message event is published", async ({ page }) => {
  // Give a push that should not happen time to arrive before concluding it
  // did not: asserting immediately would pass even on an implementation
  // that publishes a moment later. The socket subscribed just before the
  // refused send, and nothing else commits in between, so it holds nothing.
  await page.waitForTimeout(1000);
  expect(
    await familyChatSubscriptionEvents(page),
    "a refused reply must publish nothing",
  ).toEqual([]);
});
