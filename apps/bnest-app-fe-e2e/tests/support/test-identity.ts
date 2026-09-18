import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";
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
    childAdmin: {
      username: "test-user-e2e-desk-child-admin",
      password: "Synthetic E2E Desktop Admin!",
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
    childAdmin: {
      username: "test-user-e2e-tablet-child-admin",
      password: "Synthetic E2E Tablet Admin!",
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
    childAdmin: {
      username: "test-user-e2e-mobile-child-admin",
      password: "Synthetic E2E Mobile Admin!",
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
    childAdmin: {
      username: `test-user-${digest}-child-admin`,
      password: base.childAdmin.password,
    },
    parent: {
      username: `test-user-${digest}-parent`,
      password: base.parent.password,
    },
  } as TestIdentity;

  seedAccount(base.admin.username, identity.admin.username, digest, "admin");
  seedAccount(base.child.username, identity.child.username, digest, "child");
  seedAccount(
    base.admin.username,
    identity.childAdmin.username,
    digest,
    "childAdmin",
  );
  seedAccount(base.parent.username, identity.parent.username, digest, "parent");
  syncAuthoritativeSqlite();
  return identity;
}

export function isolatedLoadIdentities(
  testInfo: TestInfo,
  count: number,
): Array<{ password: string; username: string }> {
  const source = testIdentityForProject(testInfo.project.name).admin;
  const loadIdentities = Array.from({ length: count }, (_, index) => {
    const digest = createHash("sha256")
      .update(
        `${testInfo.project.name}:${testInfo.file}:${testInfo.title}:load:${index}`,
      )
      .digest("hex")
      .slice(0, 10);
    const username = `test-user-${digest}-load-${index + 1}`;
    seedAccount(source.username, username, digest, "admin");
    return { password: source.password, username };
  });
  syncAuthoritativeSqlite();
  return loadIdentities;
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
  role: "admin" | "child" | "childAdmin" | "parent",
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

function syncAuthoritativeSqlite(): void {
  const root = process.env["BNEST_E2E_RUNTIME_ROOT"];
  if (!root) return;
  const pointerPath =
    process.env["BNEST_STORAGE_CONFIG"] ??
    path.join(root, "storage-config", "storage.json");
  if (!existsSync(pointerPath)) return;
  if (readJson(pointerPath)["phase"] !== "sqlite_primary") return;

  const result = spawnSync("mix", ["bnest.storage.migrate", "--root", root], {
    cwd: path.join(process.cwd(), "apps/bnest-app"),
    env: {
      ...process.env,
      BNEST_RUNTIME_ROOT: root,
      BNEST_STORAGE_CONFIG: pointerPath,
      BNEST_TEST_LAYER: "integration",
      MIX_ENV: "test",
    },
    encoding: "utf8",
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(
      `failed to sync E2E identity into SQLite: ${result.stderr}`,
    );
  }
}

function rolesFor(role: "admin" | "child" | "childAdmin" | "parent"): string[] {
  if (role === "admin") return ["admin", "parents"];
  if (role === "childAdmin") return ["children", "admin"];
  if (role === "parent") return ["parents"];
  return ["children"];
}
