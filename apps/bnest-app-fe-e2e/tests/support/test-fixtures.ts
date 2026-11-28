import { test as base } from "playwright-bdd";
import { reapLeftoverInstance } from "./active-instance";

// The `test` object the generated specs import (`importTestFrom` in playwright.config.mts). It extends playwright-bdd's
// own `test`, which carries the step and scenario-hook fixtures; a plain `@playwright/test` base lacks them. Its auto
// worker fixture deletes an instance that a scenario's After hook did not delete, so a failed hook cannot leave a
// database behind for the next worker run to trip over. Worker teardown runs after the last scenario.
// `heldPage` is test-scoped state the rollback-floor steps pass between a scenario's steps, fresh for every scenario.
export type HeldPage = {
  /** The rollback scenario holds the page (true); the one running the previous bundle holds it (false). */
  rolledBack: boolean;
  /** The documents the rolled-back schema had judged by the rollback, by operation: those that opened the room. */
  judgedBeforeRollback: ReadonlyMap<string, number>;
};

export const test = base.extend<
  { heldPage: HeldPage },
  { reapTestInstance: void }
>({
  // eslint-disable-next-line no-empty-pattern -- Playwright requires the object pattern for a fixture, and this one needs no other fixture.
  heldPage: async ({}, use) => {
    await use({ rolledBack: false, judgedBeforeRollback: new Map() });
  },
  reapTestInstance: [
    // eslint-disable-next-line no-empty-pattern -- Playwright requires the object pattern for a fixture, and this worker fixture needs no other fixture.
    async ({}, use) => {
      await use();
      await reapLeftoverInstance();
    },
    { scope: "worker", auto: true },
  ],
});
