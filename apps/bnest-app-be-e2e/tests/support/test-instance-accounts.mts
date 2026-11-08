// The synthetic accounts a test instance is seeded with, and their usernames (ADR 001, section 2). Every username
// carries the instance short id as one segment, so identities stay unique per instance and traceable. No account
// stands for a real person, and every password is marked synthetic.

export type TestRole = "admin" | "child" | "child-admin" | "parent";

export type AccountPlan = {
  role: TestRole;
  username: string;
  password: string;
  roles: string[];
};

export type PlannedIdentity = { username: string; password: string };

export type InstanceIdentities = {
  admin: PlannedIdentity;
  child: PlannedIdentity;
  childAdmin: PlannedIdentity;
  parent: PlannedIdentity;
};

export const instanceIdPattern = /^[a-z0-9]{16}$/u;
const roleSegmentPattern = /^[a-z]+(?:-[a-z]+)*$/u;
// ADR 001, section 2: `^test-user-[a-z0-9-]{1,22}$`, which is the production username rule and the login field's
// `maxlength` of 32 characters in all.
const maxUsernameLength = 32;

const roleSettings: Record<TestRole, { roles: string[]; password: string }> = {
  admin: { roles: ["admin", "parents"], password: "Synthetic E2E Admin!" },
  child: { roles: ["children"], password: "Synthetic E2E Child!" },
  "child-admin": {
    roles: ["children", "admin"],
    password: "Synthetic E2E Child Admin!",
  },
  parent: { roles: ["parents"], password: "Synthetic E2E Parent!" },
};

export function shortIdOf(instanceId: string): string {
  if (!instanceIdPattern.test(instanceId)) {
    throw new Error("the instance id must be 16 lowercase letters or digits");
  }
  return instanceId.slice(0, 8);
}

// `test-user-<role>-<first eight characters of the instance id>`, within the server's username rule.
export function testUsername(role: string, instanceId: string): string {
  if (!roleSegmentPattern.test(role)) {
    throw new Error(`the role ${role} is not a lowercase username segment`);
  }
  const suffix = `${role}-${shortIdOf(instanceId)}`;
  const username = `test-user-${suffix}`;
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

// The planned account of one role. The same instance id always yields the same username and password.
export function plannedAccount(instanceId: string, role: TestRole): AccountPlan {
  const account = accountPlan(instanceId).find(
    (candidate) => candidate.role === role,
  );
  if (account === undefined) {
    throw new Error(`the account plan has no ${role} account`);
  }
  return account;
}

// The planned identities by role, so a step names the account it means rather than an index.
export function identitiesOf(plan: readonly AccountPlan[]): InstanceIdentities {
  return {
    admin: identityFor(plan, "admin"),
    child: identityFor(plan, "child"),
    childAdmin: identityFor(plan, "child-admin"),
    parent: identityFor(plan, "parent"),
  };
}

function identityFor(
  plan: readonly AccountPlan[],
  role: TestRole,
): PlannedIdentity {
  const account = plan.find((candidate) => candidate.role === role);
  if (account === undefined) {
    throw new Error(`the account plan has no ${role} account`);
  }
  return { username: account.username, password: account.password };
}
