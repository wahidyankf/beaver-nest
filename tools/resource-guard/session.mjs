import { mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { randomUUID } from "node:crypto";
import { join } from "node:path";

const sleep = (milliseconds) =>
  new Promise((resolvePromise) => setTimeout(resolvePromise, milliseconds));

function ownerPath(root) {
  return join(root, "heavy.lock", "owner.json");
}

function livePid(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

function readOwner(root) {
  try {
    return JSON.parse(readFileSync(ownerPath(root), "utf8"));
  } catch {
    return null;
  }
}

export function inheritedSession(root, token) {
  if (!token) return false;
  const owner = readOwner(root);
  return (
    owner?.schemaVersion === 1 &&
    owner.token === token &&
    Number.isInteger(owner.pid) &&
    livePid(owner.pid)
  );
}

export async function acquireSession(root, options = {}) {
  if (inheritedSession(root, options.token))
    return { inherited: true, token: options.token };
  mkdirSync(root, { recursive: true, mode: 0o700 });
  const lockPath = join(root, "heavy.lock");
  const deadline = Date.now() + (options.waitMs ?? 300_000);
  while (Date.now() <= deadline) {
    try {
      mkdirSync(lockPath, { mode: 0o700 });
      const owner = {
        schemaVersion: 1,
        pid: process.pid,
        token: randomUUID(),
      };
      writeFileSync(ownerPath(root), `${JSON.stringify(owner)}\n`, {
        encoding: "utf8",
        mode: 0o600,
      });
      return { inherited: false, path: lockPath, token: owner.token };
    } catch (error) {
      if (error?.code !== "EEXIST") throw error;
      const owner = readOwner(root);
      if (owner?.pid && !livePid(owner.pid)) {
        rmSync(lockPath, { recursive: true });
        continue;
      }
      await (options.sleep ?? sleep)(1000);
    }
  }
  return null;
}

export function releaseSession(root, session) {
  if (!session || session.inherited) return;
  const owner = readOwner(root);
  if (owner?.pid !== process.pid || owner.token !== session.token)
    throw new Error(
      "Refusing to release a resource session owned by another process",
    );
  rmSync(session.path, { recursive: true });
}
