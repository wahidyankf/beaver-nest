import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import type { TestInfo } from "@playwright/test";

const identities = {
  chromium: {
    admin: {
      username: "test-user-e2e-desktop-admin",
      password: "Synthetic E2E Desktop Admin!",
    },
    child: {
      username: "test-user-e2e-desktop-child",
      password: "Synthetic E2E Desktop Child!",
    },
    parent: {
      username: "test-user-e2e-desktop-parent",
      password: "Synthetic E2E Desktop Parent!",
    },
  },
  "tablet-chromium": {
    admin: {
      username: "test-user-e2e-tablet-admin",
      password: "Synthetic E2E Tablet Admin!",
    },
    child: {
      username: "test-user-e2e-tablet-child",
      password: "Synthetic E2E Tablet Child!",
    },
    parent: {
      username: "test-user-e2e-tablet-parent",
      password: "Synthetic E2E Tablet Parent!",
    },
  },
  "mobile-chromium": {
    admin: {
      username: "test-user-e2e-mobile-admin",
      password: "Synthetic E2E Mobile Admin!",
    },
    child: {
      username: "test-user-e2e-mobile-child",
      password: "Synthetic E2E Mobile Child!",
    },
    parent: {
      username: "test-user-e2e-mobile-parent",
      password: "Synthetic E2E Mobile Parent!",
    },
  },
} as const;

export type TestIdentity = (typeof identities)[keyof typeof identities];

export const initialTestIdentities = Object.values(identities);

export function testIdentityForProject(projectName: string): TestIdentity {
  if (projectName === "tablet-chromium") return identities["tablet-chromium"];
  if (projectName === "mobile-chromium") return identities["mobile-chromium"];
  return identities.chromium;
}

export function isolatedTestIdentity(testInfo: TestInfo): TestIdentity {
  const base = testIdentityForProject(testInfo.project.name);
  const digest = createHash("sha256")
    .update(`${testInfo.project.name}:${testInfo.file}:${testInfo.title}`)
    .digest("hex")
    .slice(0, 10);
  const identity = {
    admin: {
      username: `test-user-${digest}-admin`,
      password: base.admin.password,
    },
    child: {
      username: `test-user-${digest}-child`,
      password: base.child.password,
    },
    parent: {
      username: `test-user-${digest}-parent`,
      password: base.parent.password,
    },
  } as TestIdentity;

  seedAccount(base.admin.username, identity.admin.username, digest, "admin");
  seedAccount(base.child.username, identity.child.username, digest, "child");
  seedAccount(base.parent.username, identity.parent.username, digest, "parent");
  return identity;
}

export function userDataRelativePath(username: string): string {
  const root = process.env["BNEST_E2E_RUNTIME_ROOT"];
  if (!root) throw new Error("Missing marked E2E runtime root");
  const index = readJson(
    path.join(root, "system/usernames", `${username}.json`),
  );
  return `users/${String(index["userId"])}`;
}

function seedAccount(
  sourceUsername: string,
  username: string,
  digest: string,
  role: "admin" | "child" | "parent",
): void {
  const root = process.env["BNEST_E2E_RUNTIME_ROOT"];
  if (!root) throw new Error("Missing marked E2E runtime root");

  const indexPath = path.join(root, "system/usernames", `${username}.json`);
  if (existsSync(indexPath)) return;

  const sourceIndex = readJson(
    path.join(root, "system/usernames", `${sourceUsername}.json`),
  );
  const sourceAccount = readJson(
    path.join(root, "system/accounts", `${sourceIndex["userId"]}.json`),
  );
  const userId = `user-test-e2e-${digest}-${role}`;
  const account = {
    ...sourceAccount,
    userId,
    displayUsername: username,
    normalizedUsername: username,
    roles: rolesFor(role),
  };
  const index = {
    ...sourceIndex,
    normalizedUsername: username,
    userId,
  };

  mkdirSync(path.dirname(indexPath), { recursive: true });
  mkdirSync(path.join(root, "system/accounts"), { recursive: true });
  writeFileSync(
    path.join(root, "system/accounts", `${userId}.json`),
    JSON.stringify(account),
    { encoding: "utf8", flag: "wx" },
  );
  writeFileSync(indexPath, JSON.stringify(index), {
    encoding: "utf8",
    flag: "wx",
  });
}

function readJson(file: string): Record<string, unknown> {
  return JSON.parse(readFileSync(file, "utf8")) as Record<string, unknown>;
}

function rolesFor(role: "admin" | "child" | "parent"): string[] {
  if (role === "admin") return ["admin", "parents"];
  if (role === "parent") return ["parents"];
  return ["children"];
}
