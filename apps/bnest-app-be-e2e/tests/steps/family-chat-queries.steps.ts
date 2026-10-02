// family_chat_graphql.feature's room, pagination and safe-error scenarios,
// posted at the exact origin by the member the Background logged in (or, for
// the visitor, by a page holding no identity at all).
//
// The run's room is shared by every scenario before this one, so each Then
// reads the room as the server reports it now -- a second query, never a
// count kept here.

import { randomUUID } from "node:crypto";
import { expect, type Page } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import {
  requireResponse,
  resetFamilyChatScenario,
  scenario,
} from "../support/family-chat-state";
import {
  pageNodes,
  postGraphQl,
  queryFamilyChatMessages,
  sendFamilyChatMessage,
  type FamilyChatMessagesResult,
  type FamilyChatPageVariables,
  type GraphQlResponse,
} from "../support/graphql";

const { Before, Given, Then, When } = createBdd();

Before(() => {
  resetFamilyChatScenario();
});

interface Room {
  id: string;
  slug: string;
  name: string;
  roomKind: string;
  memberPostingEnabled: boolean;
}

const ROOM_FIELDS = "id slug name roomKind memberPostingEnabled";

async function queryPage(
  page: Page,
  variables: FamilyChatPageVariables,
): Promise<void> {
  scenario.response = await queryFamilyChatMessages(
    page,
    page.context().request,
    variables,
  );
}

function responsePage(): GraphQlResponse<FamilyChatMessagesResult> {
  return requireResponse() as GraphQlResponse<FamilyChatMessagesResult>;
}

function ascendingIds(): number[] {
  const ids = pageNodes(responsePage()).map((node) => Number(node.id));
  expect(ids, "page IDs ascend").toEqual(ids.toSorted((a, b) => a - b));
  return ids;
}

function knownIds(): string[] {
  expect(scenario.historyIds, "the history Given committed five").toHaveLength(
    5,
  );
  return scenario.historyIds.slice(1, 4);
}

When("the user queries the family chat room list", async ({ page }) => {
  scenario.response = await postGraphQl(
    page,
    page.context().request,
    `query { familyChatRooms { ${ROOM_FIELDS} } }`,
  );
});

Then(
  "the response lists exactly the active {string} room",
  ({ page }, name: string) => {
    void page;
    const response = requireResponse() as GraphQlResponse<{
      familyChatRooms: Room[];
    }>;
    expect(response.errors, JSON.stringify(response.errors)).toBeUndefined();
    const rooms = response.data?.familyChatRooms ?? [];
    expect(rooms.map((room) => [room.name, room.slug])).toEqual([
      [name, "ruang-keluarga"],
    ]);
  },
);

When(
  "the user queries the family chat room {string}",
  async ({ page }, slug: string) => {
    scenario.response = await postGraphQl(
      page,
      page.context().request,
      `query($slug: String!) { familyChatRoom(slug: $slug) { ${ROOM_FIELDS} } }`,
      { slug },
    );
  },
);

Then("the response returns the {string} room", ({ page }, name: string) => {
  void page;
  const response = requireResponse() as GraphQlResponse<{
    familyChatRoom: Room | null;
  }>;
  expect(response.errors, JSON.stringify(response.errors)).toBeUndefined();
  expect(response.data?.familyChatRoom?.name).toBe(name);
  expect(response.data?.familyChatRoom?.slug).toBe("ruang-keluarga");
});

// Safe: the code, no data for any operation, and no detail beside the code.
Then("the response is a safe {string} error", ({ page }, code: string) => {
  void page;
  const response = requireResponse();
  expect(response.errors?.map((error) => error.extensions?.["code"])).toEqual([
    code,
  ]);
  expect(Object.keys(response.errors?.[0]?.extensions ?? {})).toEqual(["code"]);
  for (const value of Object.values(response.data ?? {})) {
    expect(value).toBeNull();
  }
});

// One after another, so the history's order is the order of its IDs.
async function commitHistory(page: Page, tag: string, index: number) {
  if (index > 5) return;
  const sent = await sendFamilyChatMessage(
    page,
    page.context().request,
    `history ${index} ${tag}`,
    randomUUID(),
  );
  expect(sent.errors, JSON.stringify(sent.errors)).toBeUndefined();
  scenario.historyIds.push(sent.data?.sendFamilyChatMessage?.id ?? "");
  await commitHistory(page, tag, index + 1);
}

Given(
  "the family chat room holds a known ordered history of messages",
  ({ page }) => commitHistory(page, randomUUID(), 1),
);

When("the user queries family chat messages with no cursor", ({ page }) =>
  queryPage(page, {}),
);

// The latest page: ascending, at most 50, ending at the newest message, which
// is the last one the history Given committed, and holding that whole history.
Then("the response returns at most 50 messages ascending by server ID", () => {
  const ids = ascendingIds();
  expect(ids.length).toBeLessThanOrEqual(50);
  expect(ids.slice(-5)).toEqual(scenario.historyIds.map(Number));
});

Then(
  '"hasOlder" reflects whether an older message exists',
  async ({ page }) => {
    const oldest = pageNodes(responsePage())[0]?.id;
    expect(oldest, "the page holds a message").toBeDefined();
    const older = pageNodes(
      await queryFamilyChatMessages(page, page.context().request, {
        beforeId: oldest ?? "",
        limit: 1,
      }),
    );
    expect(responsePage().data?.familyChatMessages?.hasOlder).toBe(
      older.length > 0,
    );
  },
);

When(
  "the user queries family chat messages before a known message ID",
  ({ page }) => queryPage(page, { beforeId: knownIds()[0] ?? "" }),
);

Then("the response returns older messages ascending by server ID", () => {
  const ids = ascendingIds();
  const first = Number(knownIds()[0]);
  expect(ids.every((id) => id < first)).toBe(true);
  expect(ids.at(-1)).toBe(Number(scenario.historyIds[0]));
});

When(
  "the user queries family chat messages after a known committed message ID",
  ({ page }) => queryPage(page, { afterId: knownIds()[2] ?? "" }),
);

Then("the response returns newer messages ascending by server ID", () => {
  const ids = ascendingIds();
  const last = Number(knownIds()[2]);
  expect(ids.every((id) => id > last)).toBe(true);
  expect(ids[0]).toBe(Number(scenario.historyIds[4]));
});

Then('"hasNewer" reflects whether another page remains', async ({ page }) => {
  const newest = pageNodes(responsePage()).at(-1)?.id;
  expect(newest, "the page holds a message").toBeDefined();
  const newer = pageNodes(
    await queryFamilyChatMessages(page, page.context().request, {
      afterId: newest ?? "",
      limit: 1,
    }),
  );
  expect(responsePage().data?.familyChatMessages?.hasNewer).toBe(
    newer.length > 0,
  );
});

When(
  "the user queries family chat messages with both a beforeId and an afterId",
  ({ page }) =>
    queryPage(page, {
      beforeId: knownIds()[2] ?? "",
      afterId: knownIds()[0] ?? "",
    }),
);

When(
  "the user queries family chat messages with limit {int}",
  ({ page }, limit: number) => queryPage(page, { limit }),
);

// The Background logged a member in; the visitor is a browser with no
// identity cookie, which the server sends back to the login page.
Given("a visitor has no authenticated Bnest session", async ({ page }) => {
  await page.context().clearCookies();
  await page.goto("/");
  await expect(page).toHaveURL(/\/login/u);
});

When("the visitor queries the family chat room list", async ({ page }) => {
  scenario.response = await postGraphQl(
    page,
    page.context().request,
    `query { familyChatRooms { ${ROOM_FIELDS} } }`,
  );
});
