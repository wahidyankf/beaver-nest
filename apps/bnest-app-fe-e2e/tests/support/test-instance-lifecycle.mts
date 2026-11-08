// Pure helpers and the per-scenario lifecycle of one test instance (ADR 001, sections 1 and 6 step 6).
//
// The lifecycle holds at most one current instance, because the server serves one at a time. It
// talks to the server only through an injected client, so the state machine is unit-tested without a
// server. The hook in `tests/steps/lifecycle.steps.ts` and the helpers here never write SQL or files.

import { randomInt } from "node:crypto";
import path from "node:path";
import type {
  SeedAccount,
  SeedResult,
  SpawnedInstance,
  SpawnRequest,
  TestingPhase,
  TestingSeed,
} from "./testing-control-records.mts";
import {
  defaultBusyWait,
  deleteWhenIdle,
  type BusyWait,
} from "./delete-when-idle.mts";
import type { TestingControlClient } from "./testing-control.mts";

export type TestRole = "admin" | "child" | "child-admin" | "parent";

export type AccountPlan = {
  role: string;
  username: string;
  password: string;
  roles: string[];
};

// The accounts depend on the instance id, which only `begin` chooses, so the plan is built from it.
export type BeginOptions = {
  label: string;
  phase: TestingPhase;
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

const instanceIdAlphabet = "abcdefghijklmnopqrstuvwxyz0123456789";
const instanceIdPattern = /^[a-z0-9]{16}$/u;
const roleSegmentPattern = /^[a-z0-9]+(?:-[a-z0-9]+)*$/u;
const maxUsernameLength = 32;
const maxLabelLength = 60;
const flatPrimaryTag = "@flat-primary";

// Synthetic passwords for the seeded test accounts. They identify no person and no production user.
const roleSettings: Record<TestRole, { roles: string[]; password: string }> = {
  admin: { roles: ["admin", "parents"], password: "Synthetic E2E Admin!" },
  child: { roles: ["children"], password: "Synthetic E2E Child!" },
  "child-admin": {
    roles: ["children", "admin"],
    password: "Synthetic E2E Child Admin!",
  },
  parent: { roles: ["parents"], password: "Synthetic E2E Parent!" },
};

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

// Only a scenario tagged `@flat-primary` runs against a flat-primary instance. Every other scenario
// runs against the production phase.
export function phaseForTags(tags: readonly string[]): TestingPhase {
  return tags.includes(flatPrimaryTag) ? "flat_primary" : "sqlite_primary";
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

export function shortIdOf(instanceId: string): string {
  if (!instanceIdPattern.test(instanceId)) {
    throw new Error("the instance id must be 16 lowercase letters or digits");
  }
  return instanceId.slice(0, 8);
}

// `test-user-<role>-<first eight characters of the instance id>`, within the 32-character username rule.
export function testUsername(role: string, instanceId: string): string {
  if (!roleSegmentPattern.test(role)) {
    throw new Error(`the role ${role} is not a lowercase username segment`);
  }
  const username = `test-user-${role}-${shortIdOf(instanceId)}`;
  if (username.length > maxUsernameLength) {
    throw new Error(
      `the username is longer than ${maxUsernameLength} characters`,
    );
  }
  return username;
}

// The four accounts every scenario starts with, in the same order as the role table.
export function accountPlan(instanceId: string): AccountPlan[] {
  return (Object.keys(roleSettings) as TestRole[]).map((role) => ({
    role,
    username: testUsername(role, instanceId),
    password: roleSettings[role].password,
    roles: [...roleSettings[role].roles],
  }));
}

// The environment a secondary process needs to read this instance, taken from the spawn response.
export function instanceEnvironment(
  instance: SpawnedInstance,
): Record<string, string> {
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

// Holds at most one current instance. A spawn that fails leaves none, and a delete that fails keeps the
// instance current, so the reaper can retry it.
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

// The run's storage pointer and backup config. The server writes them under the SQLite run root (see
// `BnestApp.TestInstance.Paths`), so the primary server and every secondary process must read these paths,
// never the flat run root.
export function runConfigPaths(input: { runId: string; home: string }): {
  sqliteRunRoot: string;
  storageConfig: string;
  backupConfig: string;
} {
  const sqliteRunRoot = path.join(
    input.home,
    "bnest/data/test/runs",
    input.runId,
  );
  const storageConfigDirectory = path.join(sqliteRunRoot, "storage-config");
  return {
    sqliteRunRoot,
    storageConfig: path.join(storageConfigDirectory, "storage.json"),
    backupConfig: path.join(storageConfigDirectory, "backup.json"),
  };
}

// Runs every cleanup step, even after one fails, so a failed page close cannot keep the instance from being
// deleted. The steps run one after another, each once the previous one has settled. The failures are
// rethrown afterwards.
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
