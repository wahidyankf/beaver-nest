// family_chat_graphql.feature's cookie/CSRF and socket-session scenarios at
// the exact origin: a mutation posted with the member's session cookies but
// without the CSRF token, and the GraphQL socket opened by a browser holding
// no identity.

import { randomUUID } from "node:crypto";
import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import { requireResponse, scenario } from "../support/family-chat-state";
import { postGraphQlWithStatus } from "../support/graphql";
import { openFamilyChatSocket } from "../support/subscriptions";

const { Then, When } = createBdd();

When(
  "the user sends a family chat message mutation with a missing CSRF token",
  async ({ page }) => {
    const { status, body } = await postGraphQlWithStatus(
      page.context().request,
      {},
      `mutation($roomSlug: String!, $clientMessageId: ID!, $body: String!) {
        sendFamilyChatMessage(roomSlug: $roomSlug, clientMessageId: $clientMessageId, body: $body) { id }
      }`,
      {
        roomSlug: "ruang-keluarga",
        clientMessageId: randomUUID(),
        body: "no csrf",
      },
    );
    scenario.httpStatus = status;
    scenario.response = body;
  },
);

Then(
  "the response is a 403 envelope with a safe {string} error",
  ({ page }, code: string) => {
    void page;
    expect(scenario.httpStatus).toBe(403);
    const response = requireResponse();
    expect(response.data ?? null).toBeNull();
    expect(response.errors?.map((error) => error.extensions?.["code"])).toEqual(
      [code],
    );
  },
);

When(
  "the visitor's browser opens the family chat GraphQL socket",
  async ({ page }) => {
    scenario.socketOutcome = await openFamilyChatSocket(page);
  },
);

Then("the socket handshake is rejected", () => {
  expect(scenario.socketOutcome).toBe("rejected");
});
