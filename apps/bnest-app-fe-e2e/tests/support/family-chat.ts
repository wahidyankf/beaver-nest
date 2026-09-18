import {
  expect,
  type Browser,
  type Page,
  type TestInfo,
} from "@playwright/test";
import { login } from "./authentication";
import { isolatedTestIdentity, type TestIdentity } from "./test-identity";

// Support for family_chat.feature's browser-only scenarios (everything the
// frontend Vitest+Gherkin harness cannot prove without a real browser layout
// engine, accessibility tree, Cache Storage implementation, or a live Caddy
// promotion -- see each scenario's `@integration-exempt` comment in the
// feature file for its specific reason and this file's alternative-proof
// role).

export const ROOM_ROUTE = "/family-chat/ruang-keluarga";

export async function openFamilyChatRoom(
  page: Page,
  testInfo: TestInfo,
): Promise<TestIdentity> {
  const identity = isolatedTestIdentity(testInfo);
  await page.context().clearCookies();
  await login(page, identity.admin);
  await page.goto(ROOM_ROUTE);
  // The room is a plain Phoenix controller, never a LiveView (tech-doc 005),
  // so it carries no `[data-phx-main]`/`phx-connected` marker -- that pair
  // is only ever written by the LiveView JS client on a genuine `live/3`
  // route. `family_chat.js`'s own real readiness signal, set once the
  // initial message page has loaded and the composer is enabled, is this
  // route's equivalent.
  await expect(page.locator('[data-role="family-chat-room"]')).toHaveAttribute(
    "data-connection-state",
    "ready",
  );
  return identity;
}

export async function sendAsAnotherMember(
  browser: Browser,
  identity: TestIdentity,
  body: string,
): Promise<void> {
  const context = await browser.newContext();
  try {
    const otherPage = await context.newPage();
    await login(otherPage, identity.child);
    await otherPage.goto(ROOM_ROUTE);
    await expect(
      otherPage.locator('[data-role="family-chat-room"]'),
    ).toHaveAttribute("data-connection-state", "ready");
    await otherPage.getByLabel("Message").fill(body);
    await otherPage.getByRole("button", { name: "Send" }).click();
  } finally {
    await context.close();
  }
}

/**
 * Posts `count` real messages directly through the GraphQL mutation
 * (bypassing the composer UI, which would be much slower per message),
 * under the same authenticated session as `page`. Waits for the rendered
 * message count to reach at least `count` before returning.
 */
export async function seedFamilyChatMessages(
  page: Page,
  count: number,
): Promise<void> {
  const before = await page.locator("[data-role=family-chat-message]").count();
  await page.evaluate(async (messageCount) => {
    const csrfToken =
      document.querySelector<HTMLMetaElement>("meta[name='csrf-token']")
        ?.content ?? "";
    const mutation = `
      mutation SendFamilyChatMessage($roomSlug: String!, $clientMessageId: ID!, $body: String!) {
        sendFamilyChatMessage(roomSlug: $roomSlug, clientMessageId: $clientMessageId, body: $body) { id }
      }
    `;
    for (let index = 0; index < messageCount; index += 1) {
      // eslint-disable-next-line no-await-in-loop -- sequential seeding keeps message order deterministic and stays under the same session as the viewer.
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
            body: `Padding message ${index}`,
          },
        }),
      });
    }
  }, count);
  await expect
    .poll(() => page.locator("[data-role=family-chat-message]").count())
    .toBeGreaterThanOrEqual(before + count);
}

/**
 * Produces genuine scrollable overflow in the message history so "arrives
 * away from the bottom of the scroll position" is a real, physical state
 * rather than a no-op on an empty room (where `scrollHeight === clientHeight`
 * makes every arrival trivially "near the bottom", regardless of `scrollTop`).
 * Shrinks the history viewport first so a handful of real messages reliably
 * overflow it on every browser project/viewport this feature's scenarios run
 * under, then scrolls away from the bottom.
 */
export async function seedFamilyChatScrollOverflow(
  page: Page,
  count = 6,
): Promise<void> {
  await page.addStyleTag({
    content:
      '[data-role="family-chat-history"] { max-height: 120px !important; }',
  });
  await seedFamilyChatMessages(page, count);
  await page
    .locator('[data-role="family-chat-history"]')
    .evaluate((element) => {
      element.scrollTop = 0;
    });
}

/**
 * The initial page load fetches at most 50 messages
 * (`FAMILY_CHAT_MESSAGES_QUERY`'s `limit`); "Load older messages" only stays
 * actionable while the server still reports `hasOlder: true`. The room is
 * one shared fixture across this whole sequential suite run, so how many
 * messages already exist here depends on which scenarios happened to run
 * first -- seeding enough to guarantee a 51st message deterministically,
 * regardless of run order, is what keeps this scenario from flaking.
 *
 * A live arrival while the room is already open renders through the
 * subscription push path (`receiveRemoteMessage`), which never touches
 * `hasOlder` -- only a fresh page load (`renderInitial`) does. So seeding
 * alone is not enough: the page must be reloaded afterward for the new,
 * now-correct `hasOlder: true` to actually take effect on the button.
 */
export async function ensureFamilyChatHasOlderPage(page: Page): Promise<void> {
  // The rendered count is capped at 50 by the query's own `limit` regardless
  // of the real server-side total, so this always tops up to a comfortable
  // margin past 50 rather than trying to detect "already enough" from the DOM.
  const rendered = await page
    .locator("[data-role=family-chat-message]")
    .count();
  await seedFamilyChatMessages(page, Math.max(0, 55 - rendered));
  await page.reload();
  await expect(page.locator('[data-role="family-chat-room"]')).toHaveAttribute(
    "data-connection-state",
    "ready",
  );
}

export function inspectCacheStorageEntries(page: Page): Promise<string[]> {
  return page.evaluate(async () => {
    const names = await caches.keys();
    const perCache = await Promise.all(
      names.map(async (name) => {
        const cache = await caches.open(name);
        const requests = await cache.keys();
        return requests.map((request) => new URL(request.url).pathname);
      }),
    );
    return perCache.flat();
  });
}
