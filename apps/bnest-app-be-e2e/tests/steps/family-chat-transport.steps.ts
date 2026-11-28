// family_chat_graphql.feature's refused-request outline: a request the transport refuses is answered with its
// status and its safe code, and carries no GraphQL data. Each request is sent by the browser context, so its session
// cookies travel with it, and a POST carries the CSRF token a browser sends.
//
// @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: The GraphQL endpoint refuses a malformed request before executing it

import { expect, type APIResponse, type Page } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import { readCsrfToken, type GraphQlResponse } from "../support/graphql";

const { Then, When } = createBdd();

const endpoint = "/api/graphql";

// The status and decoded envelope of the last refused request. A When sets it afresh.
let refused: { status: number; body: GraphQlResponse<object> } | undefined;

function refusedAnswer(): { status: number; body: GraphQlResponse<object> } {
  if (!refused) throw new Error("no refused request was sent");
  return refused;
}

async function answerOf(response: APIResponse) {
  return {
    status: response.status(),
    body: (await response.json()) as GraphQlResponse<object>,
  };
}

// A POST of a raw body under one content type, with the CSRF token a browser fetch sends.
// Playwright JSON-encodes a string body when the content type is application/json, so raw bodies are sent as Buffers.
async function postRaw(page: Page, contentType: string, data: string) {
  const token = await readCsrfToken(page);
  return answerOf(
    await page.context().request.post(endpoint, {
      headers: { "x-csrf-token": token, "content-type": contentType },
      data: Buffer.from(data, "utf8"),
    }),
  );
}

When("the user sends a GraphQL request that is a GET", async ({ page }) => {
  refused = await answerOf(await page.context().request.get(endpoint));
});

When(
  "the user sends a GraphQL request that is a body typed as plain text",
  async ({ page }) => {
    refused = await postRaw(
      page,
      "text/plain",
      '{"query": "{ webPushConfiguration { available } }"}',
    );
  },
);

When(
  "the user sends a GraphQL request that is a body over {int} KiB",
  async ({ page }, kib: number) => {
    const padding = "x".repeat(kib * 1024);
    refused = await postRaw(
      page,
      "application/json",
      JSON.stringify({
        query: "{ webPushConfiguration { available } }",
        padding,
      }),
    );
  },
);

When(
  "the user sends a GraphQL request that is malformed JSON",
  async ({ page }) => {
    refused = await postRaw(page, "application/json", '{"query": ');
  },
);

Then(
  "the response has HTTP status {int} and a safe {string} error",
  // eslint-disable-next-line no-empty-pattern
  ({}, status: number, code: string) => {
    const answer = refusedAnswer();
    expect(answer.status).toBe(status);
    expect(
      answer.body.errors?.map((error) => error.extensions?.["code"]),
    ).toEqual([code]);
    expect(Object.keys(answer.body.errors?.[0]?.extensions ?? {})).toEqual([
      "code",
    ]);
  },
);

Then("the response carries no GraphQL data", () => {
  expect(refusedAnswer().body.data ?? null).toBeNull();
});
