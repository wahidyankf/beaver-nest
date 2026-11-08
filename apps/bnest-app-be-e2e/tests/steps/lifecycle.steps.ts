import { createBdd } from "playwright-bdd";
import {
  beginOptionsFor,
  closeBrowserContexts,
  instanceLifecycle,
} from "../support/active-instance.mts";
import { settleAll } from "../support/test-instance-lifecycle.mts";

// Each scenario gets its own test instance (ADR 001, sections 1 and 6 step 6): spawned and seeded before the scenario
// runs, used by that scenario only, and deleted after it. The scenario's tags pick its phase and whether its
// instance is seeded. The `test` object from `test-fixtures.ts` deletes a leftover instance if this After never runs.

const { After, Before } = createBdd();

Before(async ({ $testInfo }) => {
  await instanceLifecycle().begin(beginOptionsFor($testInfo));
});

// Every browser context of the worker closes before the instance is deleted, so no socket still writes to the
// database being removed. Both steps run even when the first one fails, and a failed delete fails the scenario.
After(async ({ browser }) => {
  await settleAll([
    () => closeBrowserContexts(browser),
    () => instanceLifecycle().end(),
  ]);
});
