// family_chat_graphql.feature's Web Push scenarios, posted at the exact
// origin by the member the Background logged in. A subscription binds to one
// browser session, so a second browser context -- a second session -- is how
// "this session only" is observed. Endpoints name the synthetic
// `push.allowed.example.com` provider the test configuration allows; the
// server's recording push sender never dials it.

import { randomBytes, randomUUID } from "node:crypto";
import { expect, type Browser, type Page } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import { login } from "../support/authentication";
import {
  requireResponse,
  scenario,
  scenarioIdentity,
} from "../support/family-chat-state";
import { postGraphQl, type GraphQlResponse } from "../support/graphql";

const { Given, Then, When } = createBdd();

interface SubscriptionState {
  enabled: boolean;
  expirationTime: string | null;
}

const STATE_FIELDS = "enabled expirationTime";

async function upsert(page: Page): Promise<void> {
  scenario.pushEndpoint = `https://push.allowed.example.com/test-user-${randomUUID()}`;
  scenario.response = await postGraphQl(
    page,
    page.context().request,
    `mutation($endpoint: String!, $p256dh: String!, $auth: String!) {
      upsertWebPushSubscription(endpoint: $endpoint, p256dh: $p256dh, auth: $auth) { ${STATE_FIELDS} }
    }`,
    {
      endpoint: scenario.pushEndpoint,
      p256dh: randomBytes(65).toString("base64url"),
      auth: randomBytes(16).toString("base64url"),
    },
  );
}

async function disable(page: Page): Promise<void> {
  scenario.response = await postGraphQl(
    page,
    page.context().request,
    `mutation { disableCurrentWebPushSubscription { ${STATE_FIELDS} } }`,
  );
}

/** The session's own subscription state, as a fresh query reports it. */
async function currentState(page: Page): Promise<SubscriptionState> {
  const response = await postGraphQl<{
    currentWebPushSubscription: SubscriptionState | null;
  }>(
    page,
    page.context().request,
    `query { currentWebPushSubscription { ${STATE_FIELDS} } }`,
  );
  expect(response.errors, JSON.stringify(response.errors)).toBeUndefined();
  if (!response.data?.currentWebPushSubscription) {
    throw new Error("no current Web Push subscription state");
  }
  return response.data.currentWebPushSubscription;
}

/** Whether a new browser session, logged in as `identity`, holds a subscription. */
async function otherSessionEnabled(
  browser: Browser,
  identity: { username: string; password: string },
): Promise<boolean> {
  const context = await browser.newContext();
  try {
    const page = await context.newPage();
    await login(page, identity);
    return (await currentState(page)).enabled;
  } finally {
    await context.close();
  }
}

function mutationState(field: string): SubscriptionState | null {
  const response = requireResponse() as GraphQlResponse<
    Record<string, SubscriptionState | null>
  >;
  expect(response.errors, JSON.stringify(response.errors)).toBeUndefined();
  return response.data?.[field] ?? null;
}

When("the user queries the Web Push configuration", async ({ page }) => {
  scenario.response = await postGraphQl(
    page,
    page.context().request,
    "query { webPushConfiguration { available publicKey } }",
  );
});

function configuration(): { available: unknown; publicKey: unknown } {
  const response = requireResponse() as GraphQlResponse<{
    webPushConfiguration: { available: unknown; publicKey: unknown } | null;
  }>;
  expect(response.errors, JSON.stringify(response.errors)).toBeUndefined();
  if (!response.data?.webPushConfiguration) {
    throw new Error("no Web Push configuration in the response");
  }
  return response.data.webPushConfiguration;
}

Then("the response reports whether Web Push is available", () => {
  expect(typeof configuration().available).toBe("boolean");
});

// Available exactly when a key is returned, and the key is a public one: an
// uncompressed P-256 point (65 bytes, leading 0x04), never the 32-byte
// private scalar. The test server is configured with a VAPID key pair.
Then(
  "the response includes the public application server key only when configured and safe",
  () => {
    const { available, publicKey } = configuration();
    expect(available).toBe(true);
    expect(typeof publicKey).toBe("string");
    const key = Buffer.from(String(publicKey), "base64url");
    expect(key.length).toBe(65);
    expect(key[0]).toBe(4);
  },
);

When(
  "the user queries their current Web Push subscription",
  async ({ page }) => {
    scenario.response = await postGraphQl(
      page,
      page.context().request,
      `query { currentWebPushSubscription { ${STATE_FIELDS} } }`,
    );
  },
);

// The answer, and the type the schema declares for it, carry these two fields.
Then(
  "the response reports enabled state and expiration only",
  async ({ page }) => {
    const state = mutationState("currentWebPushSubscription");
    expect(typeof state?.enabled).toBe("boolean");
    expect(Object.keys(state ?? {}).toSorted()).toEqual([
      "enabled",
      "expirationTime",
    ]);
    const declared = await postGraphQl<{
      subscriptionType: { fields: { name: string }[] } | null;
    }>(
      page,
      page.context().request,
      '{ subscriptionType: __type(name: "WebPushSubscription") { fields { name } } }',
    );
    expect(
      (declared.data?.subscriptionType?.fields ?? [])
        .map((field) => field.name)
        .toSorted(),
    ).toEqual(["enabled", "expirationTime"]);
  },
);

When(
  "the user upserts a valid Web Push subscription for this session",
  ({ page }) => upsert(page),
);

Then("the response reports the subscription enabled", async ({ page }) => {
  expect(mutationState("upsertWebPushSubscription")?.enabled).toBe(true);
  expect((await currentState(page)).enabled).toBe(true);
});

// This session holds it; a second session of the same member does not, nor
// does another member's session.
Then(
  "the stored subscription is bound to the current user and session only",
  async ({ page, browser, $testInfo }) => {
    const identity = scenarioIdentity($testInfo);
    expect((await currentState(page)).enabled).toBe(true);
    expect(await otherSessionEnabled(browser, identity.admin)).toBe(false);
    expect(await otherSessionEnabled(browser, identity.child)).toBe(false);
  },
);

Given(
  "the user has an enabled Web Push subscription for this session",
  async ({ page }) => {
    await upsert(page);
    expect(mutationState("upsertWebPushSubscription")?.enabled).toBe(true);
  },
);

When("the user disables their current Web Push subscription", ({ page }) =>
  disable(page),
);

When(
  "the user disables their current Web Push subscription again",
  ({ page }) => disable(page),
);

async function reportsDisabled(page: Page): Promise<void> {
  expect(mutationState("disableCurrentWebPushSubscription")?.enabled).toBe(
    false,
  );
  expect((await currentState(page)).enabled).toBe(false);
}

Then("the response reports the subscription disabled", ({ page }) =>
  reportsDisabled(page),
);

Then("the response still reports the subscription disabled", ({ page }) =>
  reportsDisabled(page),
);
