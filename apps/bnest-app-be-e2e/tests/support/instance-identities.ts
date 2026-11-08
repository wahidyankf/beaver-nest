import { currentInstance } from "./active-instance.mts";
import {
  accountPlan,
  identitiesOf,
  type InstanceIdentities,
} from "./test-instance-lifecycle.mts";

// The synthetic accounts of the current scenario's test instance. Each username carries the instance's first eight
// characters, so it exists only in that instance's database (ADR 001, section 2). Names come from the instance id
// the lifecycle chose, so a flat-primary instance with no seeded account still knows its planned identities.

export type TestIdentity = InstanceIdentities;

export function currentIdentities(): TestIdentity {
  return identitiesOf(accountPlan(currentInstance().instanceId));
}

// The server's user id for one of the current instance's seeded accounts, from the spawn response. A name the spawn
// did not seed is refused, so a helper cannot reach another user or another instance.
export function userIdFor(username: string): string {
  return seededAccount(username).userId;
}

// The roles the server stored for a seeded account, from the spawn response.
export function rolesFor(username: string): string[] {
  return [...seededAccount(username).roles].toSorted();
}

function seededAccount(username: string): {
  userId: string;
  roles: string[];
} {
  const account = currentInstance().accounts.find(
    (candidate) => candidate.username === username,
  );
  if (account === undefined) {
    throw new Error("the account was not seeded into the current test instance");
  }
  return account;
}
