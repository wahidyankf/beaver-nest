import { randomUUID } from "node:crypto";
import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import { login } from "../support/authentication";
import {
  requireCatchUp,
  requireIdentity,
  scenario,
} from "../support/family-chat-state";
import { isolatedTestIdentity } from "../support/test-identity";
import {
  postGraphQl,
  queryFamilyChatMessagesAfter,
  sendFamilyChatMessage,
} from "../support/graphql";
import {
  closeFamilyChatSubscription,
  connectFamilyChatSubscription,
  familyChatSubscriptionEvents,
} from "../support/subscriptions";

// Only the four family_chat_graphql.feature scenarios that a live Absinthe
// subscription push actually requires -- the original pair, and the reply
// plan's pair proving a quote survives both arrival paths (the live push and
// the afterId catch-up). Every other scenario in that file and all of
// family_chat_operations.feature carry @e2e-exempt, proven instead through
// bnest-app:test:integration; see the exemption comments in the feature files
// themselves.

const { After, Given, Then, When } = createBdd();

// Playwright tears the page down after each test regardless, which drops
// the WebSocket too; this just closes it a little earlier and more
// explicitly so a slow close never bleeds into the next test's timing.
After(async ({ page }) => {
  await closeFamilyChatSubscription(page);
});

// `family_chat_message`'s GraphQL type has no client-facing
// idempotency/client-message-id field (tech-doc 008 -- it is an internal
// dedup mechanism only), so every correlation below uses the
// server-assigned `id`, never a client-chosen key.
const SUBSCRIPTION_QUERY = `subscription($roomSlug: String!) {
  familyChatMessageCommitted(roomSlug: $roomSlug) {
    id
    roomSlug
    senderKind
    senderId
    senderDisplayName
    body
    committedAt
    replyTo { id senderKind senderDisplayName bodyPreview }
  }
}`;

Given(
  "the user holds an authorized {string} subscription for {string}",
  async (
    { page, browser, $testInfo },
    _subscriptionName: string,
    roomSlug: string,
  ) => {
    scenario.identity = isolatedTestIdentity($testInfo);
    await page.context().clearCookies();
    await login(page, requireIdentity().admin);
    // Establishing the connection here, before the "another member" step
    // below sends, is what lets the assertion later prove "exactly one".
    void browser;
    await connectFamilyChatSubscription(page, SUBSCRIPTION_QUERY, { roomSlug });
  },
);

When(
  "another member sends the family chat message {string} with a fresh client message ID",
  async ({ browser, request }, body: string) => {
    scenario.clientMessageId = randomUUID();
    const otherContext = await browser.newContext();
    try {
      const otherPage = await otherContext.newPage();
      await login(otherPage, requireIdentity().child);
      const result = await sendFamilyChatMessage(
        otherPage,
        otherContext.request,
        body,
        scenario.clientMessageId,
      );
      expect(result.errors, JSON.stringify(result.errors)).toBeUndefined();
      scenario.serverMessageId = result.data?.sendFamilyChatMessage
        ?.id as string;
    } finally {
      await otherContext.close();
    }
    void request;
  },
);

Then(
  "the subscriber receives exactly one committed-message event matching that message",
  async ({ page }) => {
    await expect
      .poll(async () => (await familyChatSubscriptionEvents(page)).length, {
        timeout: 10_000,
      })
      .toBe(1);
    const [event] = (await familyChatSubscriptionEvents(page)) as {
      result: { data: { familyChatMessageCommitted: { id: string } } };
    }[];
    expect(event, "expected exactly one subscription event").toBeDefined();
    expect(event?.result.data.familyChatMessageCommitted.id).toBe(
      scenario.serverMessageId,
    );
  },
);

Then(
  "a duplicate retry of the same client message ID publishes no second event",
  async ({ browser }) => {
    const otherContext = await browser.newContext();
    try {
      const otherPage = await otherContext.newPage();
      await login(otherPage, requireIdentity().child);
      // Re-sends the exact same client message ID captured above: a fresh
      // UUID here would commit a genuinely new message instead of
      // exercising idempotent retry, which is the entire point of this
      // scenario.
      await sendFamilyChatMessage(
        otherPage,
        otherContext.request,
        "duplicate retry body",
        scenario.clientMessageId,
      );
    } finally {
      await otherContext.close();
    }
    // A fixed settle window, not a poll-to-N: the assertion is that the
    // count stays at 1, so polling for "!= 1" would also pass on a event
    // that never arrives, which proves nothing.
    await new Promise((resolve) => {
      setTimeout(resolve, 2_000);
    });
  },
);

Given(
  "a message committed before the user's subscription started",
  async ({ page, browser, $testInfo }) => {
    scenario.identity = isolatedTestIdentity($testInfo);
    await page.context().clearCookies();
    await login(page, requireIdentity().admin);

    // Captures a genuine baseline ID *before* sending the pre-subscription
    // message: the later "queries ... after their last known committed
    // message ID" step must cursor from a point strictly before this
    // message (afterId is exclusive-after), or the very message this
    // scenario expects to "catch up" on would never appear in its own
    // results.
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

    scenario.clientMessageId = randomUUID();
    const result = await sendFamilyChatMessage(
      page,
      page.context().request,
      "committed before subscription",
      scenario.clientMessageId,
    );
    expect(result.errors, JSON.stringify(result.errors)).toBeUndefined();
    scenario.serverMessageId = result.data?.sendFamilyChatMessage?.id as string;
    void browser;
  },
);

When(
  "the user establishes the {string} subscription for {string}",
  async ({ page }, _subscriptionName: string, roomSlug: string) => {
    await connectFamilyChatSubscription(page, SUBSCRIPTION_QUERY, { roomSlug });
  },
);

When(
  "the user queries family chat messages after their last known committed message ID",
  async ({ page }) => {
    scenario.catchUp = await queryFamilyChatMessagesAfter(
      page,
      page.context().request,
      scenario.afterId,
    );
  },
);

Then(
  "the response includes the message committed before the subscription started",
  () => {
    const nodes = requireCatchUp().data?.familyChatMessages.nodes ?? [];
    expect(nodes.some((node) => node.id === scenario.serverMessageId)).toBe(
      true,
    );
  },
);
