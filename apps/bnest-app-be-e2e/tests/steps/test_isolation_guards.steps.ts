import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import {
  beginOptionsFor,
  instanceLifecycle,
  testingControl,
} from "../support/active-instance.mts";
import { plannedAccount } from "../support/test-instance-lifecycle.mts";
import {
  probeWithForwardedHeader,
  probeWithoutTestingHeader,
  probeWithWrongTestingHeader,
  runtimeRoots,
  stockNotFoundReply,
  type ProbeReply,
} from "../support/test-isolation-probes";
import { TestingControlError } from "../support/testing-control.mts";
import { listTestInstanceLeaks } from "../support/test-runtime.mts";

// Bindings for the guard scenarios of test_isolation.feature: a request to the testing routes that fails a guard gets
// the stock 404 and creates nothing, and a seeded username outside the test-user prefix is refused. Probes use Node
// fetch, never Playwright's request context. The guard scenarios start with "no test instance is current" (its
// binding in test_isolation.steps.ts ends the Before hook's instance), so a probe runs against an empty server.

const { Before, Then, When } = createBdd();

type Carried = {
  probes?: { reply: ProbeReply; missing: ProbeReply };
  refusal?: unknown;
};

let carried: Carried = {};

Before(() => {
  carried = {};
});

function required<T>(value: T | undefined, what: string): T {
  if (value === undefined) throw new Error(`the scenario has no ${what}`);
  return value;
}

// --- Testing-endpoint guards ------------------------------------------------

When(
  "a client creates a test instance without the testing header",
  async () => {
    carried.probes = {
      reply: await probeWithoutTestingHeader(),
      missing: await stockNotFoundReply(),
    };
  },
);

When(
  "a client creates a test instance with a testing header that is not the run secret",
  async () => {
    carried.probes = {
      reply: await probeWithWrongTestingHeader(),
      missing: await stockNotFoundReply(),
    };
  },
);

When(
  "a client creates a test instance with the run secret and an x-forwarded-for header",
  async () => {
    carried.probes = {
      reply: await probeWithForwardedHeader(),
      missing: await stockNotFoundReply(),
    };
  },
);

Then(
  'the response is the stock "Not Found" response that a missing route gets',
  () => {
    const { reply, missing } = required(carried.probes, "probe replies");
    expect(reply.status).toBe(404);
    expect(reply).toEqual(missing);
  },
);

// The guard scenarios start with "no test instance is current", so a refused request leaves none current. A
// request that created an instance would make one current here, and that fails the step.
Then("no test instance is created", async () => {
  expect((await testingControl().state()).instance).toBeNull();
});

// --- Seeded usernames -------------------------------------------------------

When(
  "a test spawns an instance with a seeded account named {string}",
  async ({ $testInfo }, username: string) => {
    try {
      await instanceLifecycle().begin({
        ...beginOptionsFor($testInfo),
        accounts: (instanceId) => [
          { ...plannedAccount(instanceId, "admin"), username },
        ],
      });
    } catch (error) {
      carried.refusal = error;
    }
  },
);

Then(
  "the spawn is refused with an invalid username error that names the username field",
  () => {
    const refusal = carried.refusal;
    if (!(refusal instanceof TestingControlError)) {
      throw new Error("the spawn was not refused with a testing error");
    }
    expect(refusal.code).toBe("seed_invalid");
    // The detail names the reason from the server's closed vocabulary, and the path names the field it is about.
    expect(refusal.detail).toBe("invalid_username");
    expect(refusal.path ?? "").toMatch(/username/u);
  },
);

Then("no instance directory remains for that spawn", () => {
  expect(listTestInstanceLeaks(runtimeRoots())).toEqual([]);
});
