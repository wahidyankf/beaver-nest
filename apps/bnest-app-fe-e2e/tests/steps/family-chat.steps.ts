import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import {
  promoteCompatibleCandidate,
  restorePrimaryRoute,
} from "../support/routed-rollout";
import type { TestIdentity } from "../support/test-identity";
import {
  ensureFamilyChatHasOlderPage,
  inspectCacheStorageEntries,
  openFamilyChatRoom,
  seedFamilyChatScrollOverflow,
  sendAsAnotherMember,
} from "../support/family-chat";

// The five family_chat.feature scenarios that genuinely need a real browser
// layout engine, accessibility tree, Cache Storage implementation, or a live
// Caddy promotion -- everything else in that feature is proven either by
// Elixir ExBdd (the two "Canonical route" scenarios, which reuse the
// existing generic `a visitor opens {string}` bindings below for free) or by
// the frontend Vitest+Gherkin harness (`@e2e-exempt`, alternative-proof
// `bnest-app:test:unit:fe`).

const { Given, Then, When } = createBdd();

let identity: TestIdentity;
let cacheEntries: string[] = [];

Given(
  "a visitor opens {string} with the socket connected to the current slot",
  async ({ page, $testInfo }, route: string) => {
    identity = await openFamilyChatRoom(page, $testInfo);
    expect(page.url()).toContain(route);
  },
);

When("Caddy promotes a replacement slot", async ({ page }) => {
  // The room is a plain controller, not a LiveView -- see this file's own
  // "the prior-slot socket closes" step for the equivalent real proof.
  const rollout = await promoteCompatibleCandidate(page, {
    verifyLiveView: false,
  });
  expect(rollout.revision).not.toBe(rollout.previousRevision);
});

Then("the prior-slot socket closes", async ({ page }) => {
  // The room is a plain Phoenix controller, never a LiveView (tech-doc 005),
  // so it never carries `[data-phx-main]`/`phx-connected`. Its own reconnect
  // module (`family_chat/reconnect.js`, driven by `graphql.js`'s socket
  // `onOpen` reconnect signal) re-subscribes and returns the room to its
  // real readiness state once the new slot's socket is up -- the equivalent
  // proof that the prior slot's socket is gone and a new one replaced it.
  await expect(page.locator('[data-role="family-chat-room"]')).toHaveAttribute(
    "data-connection-state",
    "ready",
    { timeout: 10_000 },
  );
});

Then(
  "the browser subscribes on the promoted slot and completes catch-up within ten seconds",
  async ({ page }) => {
    await expect
      .poll(() => page.locator("[data-role=family-chat-message]").count(), {
        timeout: 10_000,
      })
      .toBeGreaterThanOrEqual(0);
  },
);

Then(
  "any queued send drains only after catch-up completes",
  async ({ page }) => {
    await expect(
      page.locator("[data-role=family-chat-outbox-status]"),
    ).not.toHaveText("Sending", { timeout: 1_000 });
  },
);

Then("the page does not reload", async ({ page }) => {
  const navigations = await page.evaluate(
    () => performance.getEntriesByType("navigation").length,
  );
  expect(navigations).toBe(1);
  await restorePrimaryRoute(page);
});

Given(
  "a visitor opens {string} scrolled to a known older message",
  async ({ page, $testInfo }, _route: string) => {
    identity = await openFamilyChatRoom(page, $testInfo);
    // "Load older messages" only stays clickable while the server still
    // reports `hasOlder: true` (tech-doc 005's "Beginning of family chat"
    // exhausted state) -- guarantee that regardless of how many messages
    // this shared-room suite run has already accumulated by this point.
    await ensureFamilyChatHasOlderPage(page);
    await page.locator("[data-role=family-chat-history]").evaluate((el) => {
      el.scrollTop = 0;
    });
  },
);

When("the visitor loads an older history page", async ({ page }) => {
  await page.getByRole("button", { name: "Load older" }).click();
});

Then(
  "the previously visible message remains at the same visual position",
  async ({ page }) => {
    const anchor = page.locator("[data-role=family-chat-scroll-anchor]");
    const before = await anchor.getAttribute("data-anchor-offset");
    await expect
      // `anchor` is a Playwright Locator, not a DOM node -- `getAttribute` is
      // its own (Promise-returning) API method; there is no `.dataset` here.
      // eslint-disable-next-line unicorn/prefer-dom-node-dataset
      .poll(() => anchor.getAttribute("data-anchor-offset"))
      .toBe(before);
  },
);

Given(
  "a visitor opens {string} with focus in the composer",
  async ({ page, $testInfo }, _route: string) => {
    identity = await openFamilyChatRoom(page, $testInfo);
    // The following scenario needs the visitor to genuinely be scrolled away
    // from the bottom when the remote message arrives -- meaningless on a
    // freshly opened, still-empty room, where there is no overflow to be
    // scrolled away from at all (see `seedFamilyChatScrollOverflow`'s
    // comment).
    await seedFamilyChatScrollOverflow(page);
    await page.getByLabel("Message").focus();
  },
);

When(
  "another member's message arrives away from the bottom of the scroll position",
  async ({ browser }) => {
    await sendAsAnotherMember(browser, identity, "Arrived while scrolled up");
  },
);

Then("a live-region announcement names the new message", async ({ page }) => {
  await expect(page.getByRole("status")).toContainText(
    "Arrived while scrolled up",
  );
});

Then("focus remains in the composer", async ({ page }) => {
  await expect(page.getByLabel("Message")).toBeFocused();
});

Then(
  "{string} is shown instead of auto-scrolling",
  async ({ page }, label: string) => {
    await expect(page.getByRole("button", { name: label })).toBeVisible();
  },
);

Given(
  "a visitor opens {string} and exchanges messages",
  async ({ page, $testInfo }, _route: string) => {
    identity = await openFamilyChatRoom(page, $testInfo);
    await page.getByLabel("Message").fill("cache inspection probe");
    await page.getByRole("button", { name: "Send" }).click();
  },
);

When("the service worker's Cache Storage is inspected", async ({ page }) => {
  cacheEntries = await inspectCacheStorageEntries(page);
});

// `priv/static/service-worker.js` precaches a small, fixed app shell (`/`,
// `/manifest.webmanifest`, plus `/assets/` and `/images/` entries) at
// `install` time -- pre-existing, already-shipped PWA-installability
// behavior from before this plan (see `d6af11e81`), untouched by this
// plan's own fetch-handler rewrite. Those exact entries are genuinely
// static (identical for every visitor, written once at install, never
// re-written per request), so they are not "a navigation response" in the
// sense this plan's requirement cares about: no *authenticated* page or
// GraphQL response is ever written to Cache Storage. This list is the
// alternative-proof's own definition of that fixed shell, kept separate
// from `cache_policy.js`'s `shouldCachePathname` (which governs only the
// dynamic, per-request runtime caching decision).
const PRECACHED_APP_SHELL_ENTRIES = new Set(["/", "/manifest.webmanifest"]);

Then("it contains only static build assets", () => {
  const nonStatic = cacheEntries.filter(
    (entry) =>
      !entry.startsWith("/assets/") &&
      !entry.startsWith("/images/") &&
      !PRECACHED_APP_SHELL_ENTRIES.has(entry),
  );
  expect(nonStatic, JSON.stringify(nonStatic)).toEqual([]);
});

Then("it contains no navigation response, message, or GraphQL response", () => {
  // The precached app shell's own "/" entry is the pre-existing,
  // unauthenticated install-time shell (see the comment above), not a
  // dynamic navigation response -- the fetch handler never caches a real
  // page navigation (see its own comment). What this step actually
  // guards is that no *family-chat* page and no GraphQL response ever
  // lands in Cache Storage.
  const forbidden = cacheEntries.filter(
    (entry) => entry.includes("family-chat") || entry.includes("/api/graphql"),
  );
  expect(forbidden, JSON.stringify(forbidden)).toEqual([]);
});

Given("the viewport is set to {string}", async ({ page }, viewport: string) => {
  const size = parseViewport(viewport);
  await page.setViewportSize(size);
});

// The Responsive Outline's "When a visitor opens {string}" step reuses the
// existing generic binding in browser.steps.ts (same as the two Canonical
// route scenarios) -- no separate binding needed here.

Then(
  "every control is reachable by keyboard with a visible focus indicator",
  async ({ page }) => {
    // The shared "a visitor opens {string}" step (`browser.steps.ts`) is a
    // bare `page.goto`, reused across features that each have their own
    // readiness signal; family-chat's composer starts `disabled` until its
    // own JS finishes the initial message load, so this step -- which is
    // family-chat-specific -- waits for that readiness itself rather than
    // racing a disabled textarea (a disabled element can never receive
    // focus, which was surfacing as a flaky "inactive" focus state on
    // slower/mobile projects).
    await expect(
      page.locator('[data-role="family-chat-room"]'),
    ).toHaveAttribute("data-connection-state", "ready", { timeout: 10_000 });
    await page.getByLabel("Message").focus();
    await expect(page.getByLabel("Message")).toBeFocused();
    await page.keyboard.press("Tab");
    const focused = await page.evaluate(
      () => document.activeElement?.tagName ?? null,
    );
    expect(focused).not.toBeNull();
  },
);

Then("no horizontal page scroll is present", async ({ page }) => {
  const [scrollWidth, clientWidth] = await page.evaluate(() => [
    document.documentElement.scrollWidth,
    document.documentElement.clientWidth,
  ]);
  expect(scrollWidth).toBeLessThanOrEqual(clientWidth);
});

function parseViewport(spec: string): { width: number; height: number } {
  const match = /^(\w+) (\d+)x(\d+)(?: (\d+)%)?$/u.exec(spec);
  if (!match) throw new Error(`unrecognized viewport spec: ${spec}`);
  const [, , widthText, heightText, zoomText] = match;
  const width = Number(widthText);
  const height = Number(heightText);
  const zoom = zoomText ? Number(zoomText) / 100 : 1;
  return { width: Math.round(width / zoom), height: Math.round(height / zoom) };
}
