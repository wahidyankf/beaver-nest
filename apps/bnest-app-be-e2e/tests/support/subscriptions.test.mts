import assert from "node:assert/strict";
import test from "node:test";
import type { Page } from "@playwright/test";
import { closeFamilyChatSubscription } from "./subscriptions.mts";

// A stand-in page. Playwright rejects evaluate once the context is closed, which is what the lifecycle After hook
// causes by closing every browser context before the family-chat After hook runs.
function fakePage(closed: boolean): { page: Page; evaluateCalls: number } {
  const state = { evaluateCalls: 0 };
  const page = {
    isClosed: () => closed,
    evaluate: () => {
      state.evaluateCalls += 1;
      return closed
        ? Promise.reject(new Error("page.evaluate: Target page, context or browser has been closed"))
        : Promise.resolve();
    },
  } as unknown as Page;
  return {
    page,
    get evaluateCalls() {
      return state.evaluateCalls;
    },
  };
}

test("closing the family-chat socket on an open page runs the close script once", async () => {
  const fake = fakePage(false);

  await closeFamilyChatSubscription(fake.page);

  assert.equal(fake.evaluateCalls, 1);
});

test("a page that its context already closed needs no socket close and does not throw", async () => {
  const fake = fakePage(true);

  await closeFamilyChatSubscription(fake.page);

  assert.equal(fake.evaluateCalls, 0);
});
