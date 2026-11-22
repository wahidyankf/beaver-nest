import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import { login } from "../support/authentication";
import {
  beginOptionsFor,
  closeBrowserContexts,
  currentInstance,
  instanceLifecycle,
  runId as activeRunId,
  testingControl,
} from "../support/active-instance.mts";
import {
  instanceRecordState,
  instanceRowCounts,
} from "../support/instance-records";
import { readyStorageGeneration } from "../support/test-isolation-probes";
import {
  instanceEnvironment,
  isScenarioPrecondition,
  newInstanceId,
  plannedAccount,
} from "../support/test-instance-lifecycle.mts";
import { testUsername } from "../support/test-instance-accounts.mts";
import {
  TestingControlError,
  type SeedResult,
  type TestingSeed,
} from "../support/testing-control.mts";
import {
  instanceHostFiles,
  presentHostFiles,
  type InstanceHostFiles,
} from "../support/instance-host-files.mts";
import { flatAccountFiles, runBaseLeaks } from "../support/test-runtime.mts";
import type { SpawnedInstance } from "../support/testing-control-records.mts";

// Bindings for test_isolation.feature, the lifecycle scenarios (the testing-guard and invalid-username scenarios live in
// test_isolation_guards.steps.ts). The Before hook in lifecycle.steps.ts spawns an instance for every scenario, so a
// scenario's first step, its Given, ends that instance. playwright-bdd matches a step by its text alone, so one binding
// serves the Given and the Then of "no test instance is current". It ends an instance only as the first step (see
// isScenarioPrecondition). Control calls use Node fetch through the shared client, never Playwright's request context.

const { Before, BeforeStep, Given, Then, When } = createBdd();

// Facts one step leaves for a later step of the same scenario. It starts empty for every scenario.
type Carried = {
  deletedInstanceId?: string;
  deletedHostFiles?: InstanceHostFiles;
  previousInstance?: SpawnedInstance;
  previousUserId?: string;
  spawned?: SpawnedInstance;
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
// Steps of the current scenario that have started, counted before each step runs.
let stepsStarted = 0;

BeforeStep(() => {
  stepsStarted += 1;
});

Before(() => {
  carried = {};
  stepsStarted = 0;
});

function required<T>(value: T | undefined, what: string): T {
  if (value === undefined) throw new Error(`the scenario has no ${what}`);
  return value;
}

// Checks first. It ends the instance the Before hook spawned only as the scenario's first step, then checks the server
// reports none. Any later step only checks, so an instance that a When left current fails here instead of being ended.
async function noCurrentInstance(): Promise<void> {
  const testing = testingControl();
  if (
    isScenarioPrecondition(stepsStarted) &&
    (await testing.state()).instance !== null
  ) {
    await instanceLifecycle().end();
  }
  expect((await testing.state()).instance).toBeNull();
}

// --- Shared --------------------------------------------------------------------

Given("no test instance is current", noCurrentInstance);

Given("a test instance is current", async () => {
  const instance = currentInstance();
  expect((await testingControl().state()).instance?.instanceId).toBe(
    instance.instanceId,
  );
});

// --- Scenario: a spawned instance with no seeded accounts starts empty ---------

When(
  "a test spawns an instance with no seeded accounts",
  async ({ $testInfo }) => {
    carried.spawned = await instanceLifecycle().begin({
      ...beginOptionsFor($testInfo),
      accounts: () => [],
    });
  },
);

Then(
  "no account can log in, the chat has no messages, and the initial setup page is open",
  async ({ page }) => {
    expect(instanceRowCounts()).toEqual({
      bnest_records: 0,
      family_chat_messages: 0,
      web_push_subscriptions: 0,
    });
    // A flat-primary instance keeps accounts and user records in its flat root, not in SQLite, so the row counts prove
    // nothing about them. The root must exist, and it must hold no account, username, or user file.
    expect(
      flatAccountFiles(
        instanceEnvironment(currentInstance()).BNEST_RUNTIME_ROOT,
      ),
    ).toEqual([]);
    const response = await page.goto("/setup");
    expect(response?.status()).toBe(200);
    await expect(
      page.getByRole("heading", { name: "Create the first family accounts" }),
    ).toBeVisible();
  },
);

// --- Scenario: consecutive tests never share a database ---------------------

Given("a test spawned an instance and created an account in it", () => {
  const instance = currentInstance();
  const account = instance.accounts[0];
  if (account === undefined) {
    throw new Error("the previous test instance has no seeded account");
  }
  // Positive control: the account reads back here, so a later absence is about the next instance and not a failed read.
  expect(instanceRecordState("account", account.userId).present).toBe(true);
  carried.previousInstance = instance;
  carried.previousUserId = account.userId;
});

When(
  "the next test spawns its own instance",
  async ({ browser, $testInfo }) => {
    // The previous instance's browser contexts close before it is deleted, as the After hook requires.
    await closeBrowserContexts(browser);
    carried.spawned = await instanceLifecycle().replace(
      beginOptionsFor($testInfo),
    );
  },
);

Then("the next instance has a different instance ID and generation", () => {
  const previous = required(carried.previousInstance, "previous instance");
  const next = required(carried.spawned, "next instance");
  expect(next.instanceId).not.toBe(previous.instanceId);
  expect(next.generation).not.toBe(previous.generation);
});

Then(
  "the account created by the previous test cannot be found in the next instance",
  () => {
    const userId = required(carried.previousUserId, "previous account");
    // Exactly "missing". Any other read error would hide the account too, so only an absent row passes.
    expect(instanceRecordState("account", userId)).toEqual({
      present: false,
      reason: "missing",
    });
  },
);

Then(
  "the readiness check reports the generation of the next instance",
  async () => {
    expect(await readyStorageGeneration()).toBe(
      required(carried.spawned, "next instance").generation,
    );
  },
);

// --- Scenario: the spawn returns after its migrations and seed, and the instance stays current until deletion ---

When(
  "a test spawns an instance with one seeded account",
  async ({ $testInfo }) => {
    carried.spawned = await instanceLifecycle().begin({
      ...beginOptionsFor($testInfo),
      accounts: (instanceId) => [plannedAccount(instanceId, "admin")],
    });
  },
);

Then(
  "the spawn returns only after its migrations and its seed have finished",
  async () => {
    const spawned = required(carried.spawned, "spawned instance");
    expect(spawned.accounts).toHaveLength(1);
    expect(spawned.accounts[0]?.userId).toBeTruthy();
    // The readiness route serves the new database only after its migrations and seed have finished.
    expect(await readyStorageGeneration()).toBe(spawned.generation);
  },
);

Then(
  "the seeded account can log in as soon as the spawn returns",
  async ({ page }) => {
    const spawned = required(carried.spawned, "spawned instance");
    await login(page, plannedAccount(spawned.instanceId, "admin"));
  },
);

Then("the instance stays current until the test deletes it", async () => {
  const spawned = required(carried.spawned, "spawned instance");
  expect((await testingControl().state()).instance?.instanceId).toBe(
    spawned.instanceId,
  );
});

// --- Scenario: teardown removes the instance from the running server --------

When("the test deletes the instance", async ({ browser }) => {
  carried.deletedInstanceId = currentInstance().instanceId;
  const files = instanceHostFiles(runRoots(), carried.deletedInstanceId);
  carried.deletedHostFiles = files;
  // Positive control: the SQLite instance root and the storage pointer exist before the delete, so a later absence is
  // about the delete and not about a path that never existed. The default phase is SQLite-primary, which has no flat
  // instance root.
  expect(presentHostFiles(files)).toEqual(
    expect.arrayContaining([files.instanceRoots[1], files.storagePointer]),
  );
  await closeBrowserContexts(browser);
  await instanceLifecycle().end();
});

Then("the server reports no current instance", async () => {
  expect((await testingControl().state()).instance).toBeNull();
});

Then("a second delete of that instance is refused", async () => {
  const instanceId = required(carried.deletedInstanceId, "deleted instance");
  await expect(
    testingControl().deleteInstance(instanceId),
  ).rejects.toMatchObject({
    code: "not_current",
  });
});

// --- Scenario: teardown removes every host file the instance made -----------

// The run roots the runner created, the same ones the server validates.
function runRoots() {
  return {
    flatRunRoot: process.env["BNEST_E2E_RUNTIME_ROOT"] ?? "",
    sqliteRunRoot: process.env["BNEST_E2E_SQLITE_RUNTIME_ROOT"] ?? "",
    runId: process.env["BNEST_E2E_RUN_ID"] ?? "",
  };
}

Then(
  "no instance directory, storage pointer, or backup configuration file for that instance remains",
  () => {
    const files = required(carried.deletedHostFiles, "deleted instance files");
    expect(presentHostFiles(files)).toEqual([]);
  },
);

Then("the run root holds no database file", () => {
  const { flatRunRoot, sqliteRunRoot, runId } = runRoots();
  expect(
    runBaseLeaks({ path: flatRunRoot, sqlitePath: sqliteRunRoot, runId }),
  ).toEqual([]);
});

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
