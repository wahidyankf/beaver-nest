import type { Browser } from "@playwright/test";
import {
  accountPlan,
  createInstanceLifecycle,
  instanceEnvironment,
  phaseForTags,
  scenarioLabel,
  seedsAccountsForTags,
  storageForTags,
  type BeginOptions,
  type InstanceEnvironment,
  type InstanceLifecycle,
} from "./test-instance-lifecycle.mts";
import type { SpawnedInstance } from "./testing-control-records.mts";
import {
  backendOrigin,
  createTestingControlClient,
  type TestingControlClient,
} from "./testing-control.mts";

// The one test instance the current scenario uses (ADR 001, sections 1 and 6 step 6). Scenarios run one at a time
// on one worker, so one lifecycle per process is enough. Every secondary process (`mix run -e` reads) takes its
// environment from the instance that is current here.

let lifecycle: InstanceLifecycle | undefined;
let client: TestingControlClient | undefined;

export function runId(): string {
  const value = process.env["BNEST_E2E_RUN_ID"] ?? "";
  if (value === "") throw new Error("BNEST_E2E_RUN_ID is not set");
  return value;
}

export function backendOriginFromEnv(): string {
  return backendOrigin(process.env["BNEST_BE_E2E_PORT"] ?? "4030");
}

// One control client per process. It reads the secret per call, so it never holds the secret itself.
export function testingControl(): TestingControlClient {
  client ??= createTestingControlClient({ origin: backendOriginFromEnv() });
  return client;
}

// Created on first use, so a worker that never runs a scenario reads no environment.
export function instanceLifecycle(): InstanceLifecycle {
  lifecycle ??= createInstanceLifecycle({
    client: testingControl(),
    runId: runId(),
  });
  return lifecycle;
}

// The spawn options of one scenario, from its title and tags. The Before hook and any step that spawns again use
// these, so every instance of a scenario has the same phase and the same seeding rule.
export function beginOptionsFor(scenario: {
  title: string;
  tags: readonly string[];
}): BeginOptions {
  return {
    label: scenarioLabel(scenario.title),
    phase: phaseForTags(scenario.tags),
    storage: storageForTags(scenario.tags),
    accounts: seedsAccountsForTags(scenario.tags) ? accountPlan : () => [],
  };
}

export function currentInstance(): SpawnedInstance {
  const instance = lifecycle?.current();
  if (instance === undefined) {
    throw new Error("no test instance is current for this scenario");
  }
  return instance;
}

// Secondary processes must never run without an instance: a missing one fails closed here.
export function currentInstanceEnvironment(): InstanceEnvironment {
  return instanceEnvironment(currentInstance());
}

// Deletes a leftover instance when a scenario's After hook never deleted it. Creates nothing when no scenario
// has run.
export async function reapLeftoverInstance(): Promise<void> {
  if (lifecycle === undefined) return;
  await lifecycle.reap();
}

// Every browser context of this worker closes before an instance is deleted, so no socket of a browser keeps
// writing to the database that is being removed (ADR 001, section 1, quiescence). Every close settles before a
// failure is rethrown, so no context is still closing when the caller moves on.
export async function closeBrowserContexts(browser: Browser): Promise<void> {
  const results = await Promise.allSettled(
    browser.contexts().map((context) => context.close()),
  );
  const failed = results.find(
    (result): result is PromiseRejectedResult => result.status === "rejected",
  );
  if (failed !== undefined) throw failed.reason;
}
