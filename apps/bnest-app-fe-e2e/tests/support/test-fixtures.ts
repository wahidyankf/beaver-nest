import { test as base } from "playwright-bdd";
import { reapLeftoverInstance } from "./active-instance";

// The `test` object the generated specs import (`importTestFrom` in playwright.config.mts). It extends playwright-bdd's
// own `test`, which carries the step and scenario-hook fixtures; a plain `@playwright/test` base lacks them. Its auto
// worker fixture deletes an instance that a scenario's After hook did not delete, so a failed hook cannot leave a
// database behind for the next worker run to trip over. Worker teardown runs after the last scenario.
export const test = base.extend<object, { reapTestInstance: void }>({
  reapTestInstance: [
    // eslint-disable-next-line no-empty-pattern -- Playwright requires the object pattern for a fixture, and this worker fixture needs no other fixture.
    async ({}, use) => {
      await use();
      await reapLeftoverInstance();
    },
    { scope: "worker", auto: true },
  ],
});
