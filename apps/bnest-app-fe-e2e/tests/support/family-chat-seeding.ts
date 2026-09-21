import { type Browser, type Page } from "@playwright/test";
import { login } from "./authentication";
import { ROOM_ROUTE } from "./family-chat";
import { waitForRoomReady } from "./family-chat-resume";
import type { TestIdentity } from "./test-identity";

// Seeding for family_chat.feature's resume scenarios: the shared fixture
// room has to hold enough history, and enough of it has to arrive while the
// visitor is away, for "where does a returning member land" to mean
// anything. Split out of `family-chat-resume.ts` purely to stay under this
// project's max-lines lint budget.

/**
 * Posts `count` real messages straight through the GraphQL mutation under
 * this page's own session, without waiting on the DOM -- the caller is
 * usually another member's page (or a room the visitor has already left),
 * where nothing is rendered to wait for.
 */
function postMessages(
  page: Page,
  count: number,
  bodyPrefix: string,
): Promise<void> {
  return page.evaluate(
    async (batch) => {
      const csrfToken =
        document.querySelector<HTMLMetaElement>("meta[name='csrf-token']")
          ?.content ?? "";
      const mutation = `
      mutation SendFamilyChatMessage($roomSlug: String!, $clientMessageId: ID!, $body: String!) {
        sendFamilyChatMessage(roomSlug: $roomSlug, clientMessageId: $clientMessageId, body: $body) { id }
      }
    `;
      for (let index = 0; index < batch.count; index += 1) {
        // eslint-disable-next-line no-await-in-loop -- sequential posting is what makes the resulting message order deterministic.
        await fetch("/api/graphql", {
          method: "POST",
          credentials: "same-origin",
          headers: {
            "content-type": "application/json",
            "x-csrf-token": csrfToken,
          },
          body: JSON.stringify({
            query: mutation,
            variables: {
              roomSlug: "ruang-keluarga",
              clientMessageId: crypto.randomUUID(),
              body: `${batch.bodyPrefix} ${index}`,
            },
          }),
        });
      }
    },
    { count, bodyPrefix },
  );
}

/**
 * "ruang-keluarga" is one shared fixture room across every project this
 * suite runs sequentially, so how much history it already holds depends on
 * run order; this tops it up to `minimum` rendered messages and reloads so
 * the server's own `hasOlder` reaches the page.
 */
export async function ensureAtLeast(
  page: Page,
  minimum: number,
): Promise<void> {
  const rendered = await page
    .locator("[data-role=family-chat-message]")
    .count();
  if (rendered >= minimum) return;
  await postMessages(page, minimum - rendered, "Earlier message");
  await page.reload();
  await waitForRoomReady(page);
}

/** Genuinely away: nothing arriving can move a closed room's read position. */
export async function leaveRoom(page: Page): Promise<void> {
  await page.goto("/");
}

export async function postAsAnotherMember(
  browser: Browser,
  identity: TestIdentity,
  count: number,
  bodyPrefix: string,
): Promise<void> {
  const context = await browser.newContext();
  try {
    const otherPage = await context.newPage();
    await login(otherPage, identity.child);
    await otherPage.goto(ROOM_ROUTE);
    await waitForRoomReady(otherPage);
    await postMessages(otherPage, count, bodyPrefix);
  } finally {
    await context.close();
  }
}
