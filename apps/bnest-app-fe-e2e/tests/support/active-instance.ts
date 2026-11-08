import type { Browser } from "@playwright/test";

// The one test instance the current scenario uses (ADR 001, sections 1 and 6). Scenarios run one at a time
// on one worker, so one lifecycle per process is enough. Every secondary process (rollout candidates and
// `mix run -e` reads) takes its environment from the instance that is current here.

import type { SpawnedInstance } from "./testing-control-records.mts";
import {
  createInstanceLifecycle,
  instanceEnvironment,
  type InstanceLifecycle,
} from "./test-instance-lifecycle.mts";
import { waitForPagesIdle } from "./pages-idle.mts";
import {
  backendOrigin,
  createTestingControlClient,
} from "./testing-control.mts";

let lifecycle: InstanceLifecycle | undefined;

// Created on first use, so a worker that never runs a scenario reads no environment.
export function instanceLifecycle(): InstanceLifecycle {
  if (lifecycle === undefined) {
    const runId = process.env["BNEST_E2E_RUN_ID"] ?? "";
    const port = process.env["BNEST_E2E_BACKEND_PORT"];
    if (runId === "") throw new Error("BNEST_E2E_RUN_ID is not set");
    if (port === undefined)
      throw new Error("BNEST_E2E_BACKEND_PORT is not set");
    lifecycle = createInstanceLifecycle({
      client: createTestingControlClient({ origin: backendOrigin(port) }),
      runId,
    });
  }
  return lifecycle;
}

export function currentInstance(): SpawnedInstance {
  const instance = lifecycle?.current();
  if (instance === undefined) {
    throw new Error("no test instance is current for this scenario");
  }
  return instance;
}

// Secondary processes must never run without an instance: a missing one fails closed here.
export function currentInstanceEnvironment(): Record<string, string> {
  return instanceEnvironment(currentInstance());
}

// Deletes a leftover instance when a scenario's After hook never deleted it. Creates nothing when no
// scenario has run.
export async function reapLeftoverInstance(): Promise<void> {
  if (lifecycle === undefined) return;
  await lifecycle.reap();
}

// How long a page may take to answer the requests it already sent before its scenario ends.
const pageIdleTimeoutMs = 5000;

// Every browser context of this worker closes before an instance is deleted, so no socket of a browser
// keeps writing to the database that is being removed (ADR 001, section 1, quiescence). A request a page
// already sent is answered first (`pages-idle.mts`), because the server keeps working on it after the page
// is gone. Every close settles before a failure is rethrown, so no context is still closing when the caller
// moves on.
export async function closeBrowserContexts(browser: Browser): Promise<void> {
  const contexts = browser.contexts();
  const [idle] = await Promise.allSettled([
    waitForPagesIdle(
      contexts.flatMap((context) => context.pages()),
      pageIdleTimeoutMs,
    ),
  ]);
  const results = await Promise.allSettled(
    contexts.map((context) => context.close()),
  );
  const failed = [idle, ...results].find(
    (result): result is PromiseRejectedResult => result.status === "rejected",
  );
  if (failed !== undefined) throw failed.reason;
}
