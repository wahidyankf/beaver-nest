import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import {
  beginOptionsFor,
  instanceLifecycle,
} from "../support/active-instance.mts";
import {
  plannedAccount,
  shortIdOf,
} from "../support/test-instance-lifecycle.mts";
import type { SpawnedInstance } from "../support/testing-control-records.mts";

// Bindings for the "Seeded accounts are test identities only" rule of test_isolation.feature. A spawn with two planned
// accounts must list exactly those accounts, each with the test-user prefix and the instance's short id. Control calls
// use Node fetch through the shared client, never Playwright's request context.

const { Before, Then, When } = createBdd();

// The spawn this scenario made. It starts empty for every scenario.
let spawnedInstance: SpawnedInstance | undefined;

Before(() => {
  spawnedInstance = undefined;
});

function required<T>(value: T | undefined, what: string): T {
  if (value === undefined) throw new Error(`the scenario has no ${what}`);
  return value;
}

When(
  "a test spawns an instance with two seeded accounts",
  async ({ $testInfo }) => {
    spawnedInstance = await instanceLifecycle().begin({
      ...beginOptionsFor($testInfo),
      accounts: (instanceId) => [
        plannedAccount(instanceId, "admin"),
        plannedAccount(instanceId, "child"),
      ],
    });
  },
);

Then("the spawn response lists exactly those two accounts", () => {
  const spawned = required(spawnedInstance, "spawned instance");
  const expected = [
    plannedAccount(spawned.instanceId, "admin").username,
    plannedAccount(spawned.instanceId, "child").username,
  ];
  expect(
    spawned.accounts.map((account) => account.username).toSorted(),
  ).toEqual(expected.toSorted());
});

Then('each listed username starts with "test-user-"', () => {
  const spawned = required(spawnedInstance, "spawned instance");
  for (const account of spawned.accounts) {
    expect(account.username.startsWith("test-user-")).toBe(true);
  }
});

Then(
  "each listed username carries the first eight characters of the instance ID",
  () => {
    const spawned = required(spawnedInstance, "spawned instance");
    const short = shortIdOf(spawned.instanceId);
    for (const account of spawned.accounts) {
      expect(account.username.split("-")).toContain(short);
    }
  },
);
