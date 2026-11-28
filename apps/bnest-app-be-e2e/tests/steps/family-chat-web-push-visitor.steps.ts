// family_chat_graphql.feature's Web Push visitor scenarios: a caller with no
// session runs each subscription operation. Split from family-chat-web-push.steps.ts
// (max-lines); the visitor answers live only in this file.
//
// @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: A visitor with no session is refused every Web Push subscription operation

import { randomBytes, randomUUID } from "node:crypto";
import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import { postGraphQl, type GraphQlResponse } from "../support/graphql";
import { instanceRowCounts } from "../support/instance-records";

const { When, Then } = createBdd();

const STATE_FIELDS = "enabled expirationTime";

// --- A visitor with no session (family_chat_graphql.feature) -------------------

// The visitor's three subscription answers and configuration answer. The When that asks them sets both afresh.
let visitorAnswers: GraphQlResponse<object>[] = [];
let visitorConfiguration: GraphQlResponse<object> | undefined;

When(
  "the caller runs each Web Push subscription operation",
  async ({ page }) => {
    const request = page.context().request;
    visitorAnswers = [
      await postGraphQl(
        page,
        request,
        `mutation($endpoint: String!, $p256dh: String!, $auth: String!) {
        upsertWebPushSubscription(endpoint: $endpoint, p256dh: $p256dh, auth: $auth) { ${STATE_FIELDS} }
      }`,
        {
          endpoint: `https://push.allowed.example.com/test-user-${randomUUID()}`,
          p256dh: randomBytes(65).toString("base64url"),
          auth: randomBytes(16).toString("base64url"),
        },
      ),
      await postGraphQl(
        page,
        request,
        `mutation { disableCurrentWebPushSubscription { ${STATE_FIELDS} } }`,
      ),
      await postGraphQl(
        page,
        request,
        `query { currentWebPushSubscription { ${STATE_FIELDS} } }`,
      ),
    ];
    visitorConfiguration = await postGraphQl(
      page,
      request,
      "query { webPushConfiguration { available publicKey } }",
    );
  },
);

Then(
  "each Web Push subscription operation answers a safe {string} error reading {string}",
  // eslint-disable-next-line no-empty-pattern
  ({}, code: string, message: string) => {
    expect(visitorAnswers).toHaveLength(3);
    for (const answer of visitorAnswers) {
      expect(answer.errors?.map((error) => error.extensions?.["code"])).toEqual(
        [code],
      );
      expect(answer.errors?.map((error) => error.message)).toEqual([message]);
      for (const value of Object.values(answer.data ?? {})) {
        expect(value).toBeNull();
      }
    }
  },
);

Then("the Web Push configuration query still answers the caller", () => {
  const response = visitorConfiguration as
    | GraphQlResponse<{ webPushConfiguration: { available: unknown } | null }>
    | undefined;
  expect(response?.errors, JSON.stringify(response?.errors)).toBeUndefined();
  expect(typeof response?.data?.webPushConfiguration?.available).toBe(
    "boolean",
  );
});

// The instance's own rows, read through SQLite: the refused upserts stored nothing.
Then("no Web Push subscription is stored", () => {
  expect(instanceRowCounts().web_push_subscriptions).toBe(0);
});
