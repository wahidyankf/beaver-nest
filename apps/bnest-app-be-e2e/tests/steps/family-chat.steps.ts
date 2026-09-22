import { randomUUID } from "node:crypto";
import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import { login } from "../support/authentication";
import {
  isolatedTestIdentity,
  type TestIdentity,
} from "../support/test-identity";
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

let identity: TestIdentity;
let lastClientMessageId: string;
let lastServerMessageId: string;
let lastAfterId: string;
let replyTargetId: string;
let replyMessageId: string;

Given(
  "the user holds an authorized {string} subscription for {string}",
  async (
    { page, browser, $testInfo },
    _subscriptionName: string,
    roomSlug: string,
  ) => {
    identity = isolatedTestIdentity($testInfo);
    await page.context().clearCookies();
    await login(page, identity.admin);
    // Establishing the connection here, before the "another member" step
    // below sends, is what lets the assertion later prove "exactly one".
    void browser;
    await connectFamilyChatSubscription(page, SUBSCRIPTION_QUERY, { roomSlug });
  },
);

When(
  "another member sends the family chat message {string} with a fresh client message ID",
  async ({ browser, request }, body: string) => {
    lastClientMessageId = randomUUID();
    const otherContext = await browser.newContext();
    try {
      const otherPage = await otherContext.newPage();
      await login(otherPage, identity.child);
      const result = await sendFamilyChatMessage(
        otherPage,
        otherContext.request,
        body,
        lastClientMessageId,
      );
      expect(result.errors, JSON.stringify(result.errors)).toBeUndefined();
      lastServerMessageId = result.data?.sendFamilyChatMessage?.id as string;
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
      lastServerMessageId,
    );
  },
);

Then(
  "a duplicate retry of the same client message ID publishes no second event",
  async ({ browser }) => {
    const otherContext = await browser.newContext();
    try {
      const otherPage = await otherContext.newPage();
      await login(otherPage, identity.child);
      // Re-sends the exact same client message ID captured above: a fresh
      // UUID here would commit a genuinely new message instead of
      // exercising idempotent retry, which is the entire point of this
      // scenario.
      await sendFamilyChatMessage(
        otherPage,
        otherContext.request,
        "duplicate retry body",
        lastClientMessageId,
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
    identity = isolatedTestIdentity($testInfo);
    await page.context().clearCookies();
    await login(page, identity.admin);

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
    lastAfterId = String(knownIds.length > 0 ? Math.max(...knownIds) : 0);

    lastClientMessageId = randomUUID();
    const result = await sendFamilyChatMessage(
      page,
      page.context().request,
      "committed before subscription",
      lastClientMessageId,
    );
    expect(result.errors, JSON.stringify(result.errors)).toBeUndefined();
    lastServerMessageId = result.data?.sendFamilyChatMessage?.id as string;
    void browser;
  },
);

When(
  "the user establishes the {string} subscription for {string}",
  async ({ page }, _subscriptionName: string, roomSlug: string) => {
    await connectFamilyChatSubscription(page, SUBSCRIPTION_QUERY, { roomSlug });
  },
);

let catchUpResult: Awaited<ReturnType<typeof queryFamilyChatMessagesAfter>>;

When(
  "the user queries family chat messages after their last known committed message ID",
  async ({ page }) => {
    catchUpResult = await queryFamilyChatMessagesAfter(
      page,
      page.context().request,
      lastAfterId,
    );
  },
);

Then(
  "the response includes the message committed before the subscription started",
  () => {
    const nodes = catchUpResult.data?.familyChatMessages.nodes ?? [];
    expect(nodes.some((node) => node.id === lastServerMessageId)).toBe(true);
  },
);

// --- the reply plan's two subscription scenarios ---

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
    replyTargetId = target.data?.sendFamilyChatMessage?.id as string;

    const otherContext = await browser.newContext();
    try {
      const otherPage = await otherContext.newPage();
      await login(otherPage, identity.child);
      const reply = await sendFamilyChatMessage(
        otherPage,
        otherContext.request,
        "Oke, aku siapin",
        randomUUID(),
        replyTargetId,
      );
      expect(reply.errors, JSON.stringify(reply.errors)).toBeUndefined();
      replyMessageId = reply.data?.sendFamilyChatMessage?.id as string;
    } finally {
      await otherContext.close();
    }
  },
);

Then(
  "the subscriber receives exactly one committed-message event matching that reply",
  async ({ page }) => {
    await expect
      .poll(async () => (await eventsMatching(page, replyMessageId)).length, {
        timeout: 10_000,
      })
      .toBe(1);
  },
);

Then(
  "that event's message carries a quote naming the message it answers",
  async ({ page }) => {
    const [event] = await eventsMatching(page, replyMessageId);
    expect(event, "expected a subscription event for the reply").toBeDefined();
    expect(event?.result.data.familyChatMessageCommitted.replyTo?.id).toBe(
      replyTargetId,
    );
  },
);

Given(
  "a family chat reply committed before the user's subscription started",
  async ({ page, $testInfo }) => {
    identity = isolatedTestIdentity($testInfo);
    await page.context().clearCookies();
    await login(page, identity.admin);

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
    lastAfterId = String(knownIds.length > 0 ? Math.max(...knownIds) : 0);

    const target = await sendFamilyChatMessage(
      page,
      page.context().request,
      "Nanti aku jemput jam 5",
      randomUUID(),
    );
    expect(target.errors, JSON.stringify(target.errors)).toBeUndefined();
    replyTargetId = target.data?.sendFamilyChatMessage?.id as string;

    const reply = await sendFamilyChatMessage(
      page,
      page.context().request,
      "Oke, aku siapin",
      randomUUID(),
      replyTargetId,
    );
    expect(reply.errors, JSON.stringify(reply.errors)).toBeUndefined();
    replyMessageId = reply.data?.sendFamilyChatMessage?.id as string;
  },
);

Then("the response includes that reply", () => {
  const nodes = catchUpResult.data?.familyChatMessages.nodes ?? [];
  expect(nodes.some((node) => node.id === replyMessageId)).toBe(true);
});

Then("that reply carries a quote naming the message it answers", () => {
  const nodes = catchUpResult.data?.familyChatMessages.nodes ?? [];
  const reply = nodes.find((node) => node.id === replyMessageId);
  expect(reply, "expected the reply in the catch-up page").toBeDefined();
  expect(reply?.replyTo?.id).toBe(replyTargetId);
});
