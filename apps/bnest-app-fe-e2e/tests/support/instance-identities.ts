import { currentInstance, instanceLifecycle } from "./active-instance";
import {
  accountPlan,
  testUsername,
  type AccountPlan,
} from "./test-instance-lifecycle.mts";

// The synthetic accounts of the current scenario's test instance. Each username carries the instance's
// first eight characters, so it exists only in that instance's database (ADR 001, section 2).

export type InstanceIdentity = { username: string; password: string };

export type InstanceIdentities = {
  admin: InstanceIdentity;
  child: InstanceIdentity;
  childAdmin: InstanceIdentity;
  parent: InstanceIdentity;
};

export function instanceIdentities(): InstanceIdentities {
  const plan = accountPlan(currentInstance().instanceId);
  return {
    admin: identityFor(plan, "admin"),
    child: identityFor(plan, "child"),
    childAdmin: identityFor(plan, "child-admin"),
    parent: identityFor(plan, "parent"),
  };
}

// Accounts beyond the four a scenario starts with, seeded into the current instance through the seed route.
// Each call uses a new seed key, so the seeds never conflict.
let loadSeeds = 0;

export async function seedLoadIdentities(
  count: number,
): Promise<InstanceIdentity[]> {
  const instanceId = currentInstance().instanceId;
  const { password } = identityFor(accountPlan(instanceId), "admin");
  const accounts = Array.from({ length: count }, (_, index) => ({
    username: testUsername(`load-${index + 1}`, instanceId),
    password,
    roles: ["admin", "parents"],
  }));
  loadSeeds += 1;
  await instanceLifecycle().seed(`load-accounts-${loadSeeds}`, { accounts });
  return accounts.map(({ username }) => ({ username, password }));
}

function identityFor(
  plan: readonly AccountPlan[],
  role: string,
): InstanceIdentity {
  const account = plan.find((candidate) => candidate.role === role);
  if (account === undefined)
    throw new Error(`the account plan has no ${role} account`);
  return { username: account.username, password: account.password };
}

// The server's user id for one of the current instance's accounts, from the spawn response. A name that is
// not an account of this instance is refused, so a helper cannot write to another user or instance.
export function userIdFor(username: string): string {
  const account = currentInstance().accounts.find(
    (candidate) => candidate.username === username,
  );
  if (account === undefined) {
    throw new Error("the account is not part of the current test instance");
  }
  return account.userId;
}
