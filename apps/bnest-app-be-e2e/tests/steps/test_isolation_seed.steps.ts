import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import { login } from "../support/authentication";
import {
  currentInstance,
  runId as activeRunId,
  testingControl,
} from "../support/active-instance.mts";
import { instanceRowCounts } from "../support/instance-records";
import {
  newInstanceId,
  plannedAccount,
} from "../support/test-instance-lifecycle.mts";
import { testUsername } from "../support/test-instance-accounts.mts";
import {
  TestingControlError,
  type SeedResult,
  type TestingSeed,
} from "../support/testing-control.mts";

// Bindings for test_isolation.feature, the seed-once and 409-conflict scenarios.
// Split from test_isolation.steps.ts (max-lines): scenarios never span the two
// files, so each file keeps its own scenario state and Before hook.
//
// @scenario specs/apps/bnest/app-be/behaviours/test_isolation.feature: POST /instances/:id/seed applies a seed once per key
// @scenario specs/apps/bnest/app-be/behaviours/test_isolation.feature: Conflicts answer 409: run mismatch, active, busy, seed key

const { Before, Given, Then, When } = createBdd();

// Facts one step leaves for a later step of the same scenario. It starts empty for every scenario.
type Carried = {
  seedAnswer?: SeedResult;
  seedRecordsBeforeRepeat?: number;
  conflict?: ConflictAnswer;
};

// The answer a refused request gave, as the client's typed error reads it. `sent` lists the values the request carried.
type ConflictAnswer = {
  code: string;
  status: number | null;
  detail: string;
  path: string | null;
  sent: string[];
};

let carried: Carried = {};

Before(() => {
  carried = {};
});

function required<T>(value: T | undefined, what: string): T {
  if (value === undefined) throw new Error(`the scenario has no ${what}`);
  return value;
}

// --- Scenario: a seed is applied once per key, and a conflicting request answers 409 -----------

// One key for the scenario's seeds. Each scenario has its own instance, so one key is enough.
const seedKey = "e2e-seed-once";
const conflictLabel = "e2e-conflict-probe";
const otherRunId = "e2e-other-run";

// The one account a seed adds: the instance's own username form under the role `seed`, which no planned account uses.
function seededAccount(instanceId: string, roles: string[]) {
  return {
    username: testUsername("seed", instanceId),
    password: plannedAccount(instanceId, "parent").password,
    roles,
  };
}

function seedBody(instanceId: string, roles: string[]): TestingSeed {
  return { accounts: [seededAccount(instanceId, roles)] };
}

// The typed error a refused request raises, or a failure when the request was answered instead.
async function conflictOf(
  request: Promise<unknown>,
  sent: string[],
): Promise<ConflictAnswer> {
  try {
    await request;
  } catch (error) {
    if (error instanceof TestingControlError) {
      return {
        code: error.code,
        status: error.status,
        detail: error.detail,
        path: error.path,
        sent,
      };
    }
    throw error;
  }
  throw new Error("the request was answered instead of refused");
}

Given("a test seeded a current instance under a seed key", async () => {
  const instance = currentInstance();
  expect(
    await testingControl().seedInstance(instance.instanceId, {
      seedKey,
      seed: seedBody(instance.instanceId, ["parent"]),
    }),
  ).toEqual({ seedKey, applied: true });
});

When("a test seeds the current instance under a new seed key", async () => {
  const instance = currentInstance();
  carried.seedAnswer = await testingControl().seedInstance(
    instance.instanceId,
    {
      seedKey,
      seed: seedBody(instance.instanceId, ["parent"]),
    },
  );
});

Then(
  "the seed answers applied true and the seeded account can log in",
  async ({ page }) => {
    expect(carried.seedAnswer).toEqual({ seedKey, applied: true });
    await login(page, seededAccount(currentInstance().instanceId, ["parent"]));
  },
);

When("the test repeats that seed key with the same body", async () => {
  const instance = currentInstance();
  carried.seedRecordsBeforeRepeat = instanceRowCounts().bnest_records;
  carried.seedAnswer = await testingControl().seedInstance(
    instance.instanceId,
    {
      seedKey,
      seed: seedBody(instance.instanceId, ["parent"]),
    },
  );
});

// The seeded account is one record in SQLite, so an equal count after the repeat means no account was written.
Then("the repeat answers applied false and writes no new account", () => {
  expect(carried.seedAnswer).toEqual({ seedKey, applied: false });
  const before = required(carried.seedRecordsBeforeRepeat, "record count");
  expect(before).toBeGreaterThan(0);
  expect(instanceRowCounts().bnest_records).toBe(before);
});

When(
  "a test asks the server to spawn an instance under another run id",
  async () => {
    carried.conflict = await conflictOf(
      testingControl().spawnInstance({
        runId: otherRunId,
        label: conflictLabel,
      }),
      [otherRunId, conflictLabel],
    );
  },
);

When("a test asks the server to spawn an instance", async () => {
  const ownRunId = activeRunId();
  carried.conflict = await conflictOf(
    testingControl().spawnInstance({ runId: ownRunId, label: conflictLabel }),
    [ownRunId, conflictLabel],
  );
});

When("a test seeds an instance that is not current", async () => {
  const absent = newInstanceId();
  carried.conflict = await conflictOf(
    testingControl().seedInstance(absent, {
      seedKey,
      seed: seedBody(absent, ["parent"]),
    }),
    [absent, seedKey],
  );
});

When(
  "a test seeds the current instance with another body under it",
  async () => {
    const instance = currentInstance();
    carried.conflict = await conflictOf(
      testingControl().seedInstance(instance.instanceId, {
        seedKey,
        seed: seedBody(instance.instanceId, ["admin"]),
      }),
      [instance.instanceId, seedKey],
    );
  },
);

Then(
  "the response is a 409 answer with the code {string}",
  // eslint-disable-next-line no-empty-pattern
  ({}, code: string) => {
    const answer = required(carried.conflict, "conflicting request");
    expect({ status: answer.status, code: answer.code }).toEqual({
      status: 409,
      code,
    });
  },
);

Then("the answer echoes none of the request's input", () => {
  const answer = required(carried.conflict, "conflicting request");
  const text = `${answer.detail} ${answer.path ?? ""}`;
  for (const value of answer.sent) {
    expect(text).not.toContain(value);
  }
});
