// Pure helpers and the per-scenario lifecycle of one test instance (ADR 001, sections 1 and 6 step 6).
//
// The lifecycle holds at most one current instance, because the server serves one at a time. It talks to the
// server only through an injected client, so the state machine is unit-tested without a server. The Before and
// After hooks in `tests/steps/lifecycle.steps.ts` use this module and never write SQL or files.

import { randomInt } from "node:crypto";
import path from "node:path";
import {
  instanceIdPattern,
  type AccountPlan,
} from "./test-instance-accounts.mts";
import type {
  SeedAccount,
  SeedResult,
  SpawnedInstance,
  SpawnRequest,
  TestingPhase,
  TestingSeed,
  TestingStorage,
} from "./testing-control-records.mts";
import {
  defaultBusyWait,
  deleteWhenIdle,
  type BusyWait,
} from "./delete-when-idle.mts";
import type { TestingControlClient } from "./testing-control.mts";

export {
  accountPlan,
  identitiesOf,
  plannedAccount,
  shortIdOf,
  testUsername,
  type AccountPlan,
  type InstanceIdentities,
  type PlannedIdentity,
  type TestRole,
} from "./test-instance-accounts.mts";

// The accounts depend on the instance id, which only `begin` chooses, so the plan is built from it.
export type BeginOptions = {
  label: string;
  phase: TestingPhase;
  storage?: TestingStorage;
  accounts: (instanceId: string) => readonly AccountPlan[];
};

export type LifecycleClient = Pick<
  TestingControlClient,
  "spawnInstance" | "seedInstance" | "deleteInstance"
>;

export type InstanceLifecycle = {
  current(): SpawnedInstance | undefined;
  begin(options: BeginOptions): Promise<SpawnedInstance>;
  seed(seedKey: string, seed: TestingSeed): Promise<SeedResult>;
  end(): Promise<void>;
  replace(options: BeginOptions): Promise<SpawnedInstance>;
  reap(): Promise<void>;
};

export type InstanceEnvironment = {
  BNEST_TEST_INSTANCE_ID: string;
  BNEST_RUNTIME_ROOT: string;
  BNEST_STORAGE_CONFIG: string;
};

const instanceIdAlphabet = "abcdefghijklmnopqrstuvwxyz0123456789";
const maxLabelLength = 60;
const flatPrimaryTag = "@flat-primary";
const openSetupTag = "@open-setup";
const storageUnconfiguredTag = "@storage-unconfigured";

// A lowercase slug of at most 60 characters, the server's `label` rule. A title with no letters or digits
// becomes `scenario`.
export function scenarioLabel(title: string): string {
  const slug = title
    .toLowerCase()
    .replaceAll(/[^a-z0-9]+/gu, "-")
    .replaceAll(/^-+|-+$/gu, "")
    .slice(0, maxLabelLength)
    .replace(/-+$/u, "");
  return slug === "" ? "scenario" : slug;
}

// Only a scenario tagged `@flat-primary` runs against a flat-primary instance. Every other scenario runs
// against the production phase, `sqlite_primary`.
export function phaseForTags(tags: readonly string[]): TestingPhase {
  return tags.includes(flatPrimaryTag) ? "flat_primary" : "sqlite_primary";
}

// `@storage-unconfigured` starts the scenario before any database location is chosen, as a fresh installation is: no
// storage pointer and no database. Only a flat-primary instance can be in that state, so the tag belongs with
// `@flat-primary` (ADR 001, section 1, "Phase").
export function storageForTags(tags: readonly string[]): TestingStorage {
  return tags.includes(storageUnconfiguredTag) ? "unconfigured" : "configured";
}

// `@open-setup` keeps `/setup` open, so its instance is seeded with no account. Only a flat-primary instance
// keeps setup open (ADR 001, section 2), so the tag belongs with `@flat-primary`.
export function seedsAccountsForTags(tags: readonly string[]): boolean {
  return !tags.includes(openSetupTag);
}

// Steps of one scenario share a single Before-hook instance. Its Given is the scenario's first step, so only the
// first step may end that instance; a later step that finds an instance current must report it, not end it.
export function isScenarioPrecondition(stepsStarted: number): boolean {
  return stepsStarted === 1;
}

// A client-chosen instance id of 16 characters from [a-z0-9]. `randomIndex` is injectable for tests.
export function newInstanceId(
  randomIndex: (exclusiveMax: number) => number = (max) => randomInt(max),
): string {
  let id = "";
  for (let index = 0; index < 16; index += 1) {
    id += instanceIdAlphabet.charAt(randomIndex(instanceIdAlphabet.length));
  }
  if (!instanceIdPattern.test(id)) {
    throw new Error(
      "the generated instance id is not 16 lowercase letters or digits",
    );
  }
  return id;
}

// The environment a secondary process needs to read this instance, taken from the spawn response.
export function instanceEnvironment(
  instance: SpawnedInstance,
): InstanceEnvironment {
  const { environment } = instance;
  if (environment.BNEST_TEST_INSTANCE_ID !== instance.instanceId) {
    throw new Error(
      "the spawn response names a different instance than it reports",
    );
  }
  for (const name of ["BNEST_RUNTIME_ROOT", "BNEST_STORAGE_CONFIG"] as const) {
    if (!path.isAbsolute(environment[name])) {
      throw new Error(`${name} must be an absolute path`);
    }
  }
  return {
    BNEST_TEST_INSTANCE_ID: environment.BNEST_TEST_INSTANCE_ID,
    BNEST_RUNTIME_ROOT: environment.BNEST_RUNTIME_ROOT,
    BNEST_STORAGE_CONFIG: environment.BNEST_STORAGE_CONFIG,
  };
}

type LifecycleState = { current: SpawnedInstance | undefined; busy: boolean };

type LifecycleContext = {
  client: LifecycleClient;
  runId: string;
  nextInstanceId: () => string;
  state: LifecycleState;
  busyWait: BusyWait;
};

// Runs one operation at a time. A second one is refused at once rather than interleaving with the first.
async function guarded<T>(
  state: LifecycleState,
  work: () => Promise<T>,
): Promise<T> {
  if (state.busy) throw new Error("another test instance operation is running");
  state.busy = true;
  try {
    return await work();
  } finally {
    state.busy = false;
  }
}

async function spawnCurrent(
  context: LifecycleContext,
  beginOptions: BeginOptions,
): Promise<SpawnedInstance> {
  const { client, runId, nextInstanceId, state } = context;
  if (state.current !== undefined) {
    throw new Error(
      "a test instance is already current; end it before beginning another",
    );
  }
  const instanceId = nextInstanceId();
  const request: SpawnRequest = {
    runId,
    label: beginOptions.label,
    instanceId,
    phase: beginOptions.phase,
    ...(beginOptions.storage === undefined
      ? {}
      : { storage: beginOptions.storage }),
    ...seedOf(beginOptions.accounts(instanceId)),
  };
  const spawned = await client.spawnInstance(request);
  if (spawned.instanceId !== instanceId) {
    // Remove what the server built, because this lifecycle cannot track it.
    await client.deleteInstance(spawned.instanceId);
    throw new Error(
      "the spawn answered a different instance than it was asked for",
    );
  }
  state.current = spawned;
  return spawned;
}

// The current instance stays current when its delete fails, so the reaper can retry it.
async function deleteCurrent(context: LifecycleContext): Promise<void> {
  const instance = context.state.current;
  if (instance === undefined) return;
  await deleteWhenIdle(context.client, instance.instanceId, context.busyWait);
  context.state.current = undefined;
}

// A seed with no current instance throws synchronously; `guarded` turns that into a rejection.
function seedCurrent(
  context: LifecycleContext,
  seedKey: string,
  seed: TestingSeed,
): Promise<SeedResult> {
  const instance = context.state.current;
  if (instance === undefined) {
    throw new Error("no test instance is current to seed");
  }
  return context.client.seedInstance(instance.instanceId, { seedKey, seed });
}

// Holds at most one current instance. A spawn that fails leaves none, and a delete that fails keeps the instance
// current, so the reaper can retry it.
export function createInstanceLifecycle(options: {
  client: LifecycleClient;
  runId: string;
  newInstanceId?: () => string;
  busyWait?: BusyWait;
}): InstanceLifecycle {
  const context: LifecycleContext = {
    client: options.client,
    runId: options.runId,
    nextInstanceId: options.newInstanceId ?? (() => newInstanceId()),
    state: { current: undefined, busy: false },
    busyWait: options.busyWait ?? defaultBusyWait,
  };
  const { state } = context;
  const begin = (beginOptions: BeginOptions) =>
    guarded(state, () => spawnCurrent(context, beginOptions));
  const end = () => guarded(state, () => deleteCurrent(context));
  return {
    current: () => state.current,
    begin,
    seed: (seedKey, seed) =>
      guarded(state, () => seedCurrent(context, seedKey, seed)),
    end,
    replace: async (beginOptions) => {
      await end();
      return begin(beginOptions);
    },
    reap: end,
  };
}

// Runs every cleanup step, even after one fails, so a failed page close cannot keep the instance from being
// deleted. The steps run one after another, each once the previous one has settled. The failures are rethrown
// afterwards.
export async function settleAll(
  steps: ReadonlyArray<() => Promise<void>>,
): Promise<void> {
  const failures: unknown[] = [];
  await steps.reduce<Promise<void>>(
    (previous, step) =>
      previous.then(step).catch((error: unknown) => {
        failures.push(error);
      }),
    Promise.resolve(),
  );
  if (failures.length === 1) throw failures[0];
  if (failures.length > 1) {
    throw new AggregateError(failures, "several cleanup steps failed");
  }
}

// An empty account list sends no seed at all, so the server keeps its no-account defaults.
function seedOf(accounts: readonly AccountPlan[]): { seed?: TestingSeed } {
  if (accounts.length === 0) return {};
  return {
    seed: {
      accounts: accounts.map(({ username, password, roles }): SeedAccount => ({
        username,
        password,
        roles,
      })),
    },
  };
}
