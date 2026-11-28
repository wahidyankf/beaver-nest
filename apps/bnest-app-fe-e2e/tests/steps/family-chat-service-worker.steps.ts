import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import { ROOM_ROUTE } from "../support/family-chat";
import {
  expectCommitted,
  sendThroughComposer,
} from "../support/family-chat-delivery";
import { waitForRoomReady } from "../support/family-chat-resume";
import { uniqueBody } from "../support/family-chat-reply";
import { sendAsAnotherMember } from "../support/family-chat";
import { instanceIdentities } from "../support/instance-identities";

// family_chat.feature, Rule "Release candidate proof" neighbours: the service worker's Cache Storage in a real browser,
// after a visitor opens the room and the room exchanges messages.

const { Given, Then, When } = createBdd();

// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: The service worker cache stores no authenticated content

// The cache entries the shipped worker wrote, as pathnames, read from the page's own Cache Storage.
let cacheEntries: string[] = [];

function isStaticBuildPath(pathname: string): boolean {
  return (
    pathname.startsWith("/assets/") ||
    pathname.startsWith("/images/") ||
    pathname === "/manifest.webmanifest"
  );
}

Given(
  "a visitor opens {string} and exchanges messages",
  async ({ page, browser }, pathname: string) => {
    expect(pathname).toBe(ROOM_ROUTE);
    await page.goto(pathname);
    await waitForRoomReady(page);
    const body = uniqueBody("Exchanged with the service worker");
    await sendThroughComposer(page, body);
    // The server's push can render the committed row before this send's own response drops the pending one, so the
    // body briefly matches two rows. Judge the settled state: one committed row, and no pending copy left.
    await expectCommitted(page, body);
    await sendAsAnotherMember(
      browser,
      instanceIdentities(),
      uniqueBody("Reply from another member"),
    );
  },
);

When("the service worker's Cache Storage is inspected", async ({ page }) => {
  // The worker installs and activates after registration; wait for it before reading the cache.
  await page.evaluate(() => navigator.serviceWorker.ready);
  await expect
    .poll(() => page.evaluate(async () => (await caches.keys()).length), {
      timeout: 15_000,
    })
    .toBeGreaterThan(0);
  cacheEntries = await page.evaluate(async () => {
    const openCaches = await Promise.all(
      (await caches.keys()).map((name) => caches.open(name)),
    );
    const requests = await Promise.all(openCaches.map((cache) => cache.keys()));
    return requests.flat().map((request) => new URL(request.url).pathname);
  });
});

Then("it contains only static build assets", () => {
  expect(
    cacheEntries.length,
    "Cache Storage holds entries to judge",
  ).toBeGreaterThan(0);
  expect(
    cacheEntries.filter((pathname) => !isStaticBuildPath(pathname)),
    "Cache Storage holds a non-static entry",
  ).toEqual([]);
});

Then("it contains no navigation response, message, or GraphQL response", () => {
  expect(
    cacheEntries.filter(
      (pathname) =>
        pathname.startsWith("/family-chat") ||
        pathname.startsWith("/api/") ||
        pathname === "/",
    ),
    "Cache Storage holds a navigation, message or GraphQL response",
  ).toEqual([]);
});
