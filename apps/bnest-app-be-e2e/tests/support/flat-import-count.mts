import { readdirSync } from "node:fs";
import path from "node:path";

// The browser-import envelopes one user holds on a flat-primary instance (ADR 001, section 2). The flat record store
// keeps each envelope as `users/<user>/imports/<import>.json` under the instance root, so a count of the SQLite
// table reads zero there and would pass any "no duplicate" check vacuously. The user id is checked before it becomes
// a path segment, so no input can name another directory.

const userIdPattern = /^[A-Za-z0-9_-]{1,128}$/u;

export function countFlatImports(runtimeRoot: string, userId: string): number {
  if (!userIdPattern.test(userId)) {
    throw new Error("the user id is not a safe record key");
  }
  let entries;
  try {
    entries = readdirSync(path.join(runtimeRoot, "users", userId, "imports"), {
      withFileTypes: true,
    });
  } catch (error) {
    if (error instanceof Error && "code" in error && error.code === "ENOENT") {
      return 0;
    }
    throw error;
  }
  return entries.filter(
    (entry) => entry.isFile() && entry.name.endsWith(".json"),
  ).length;
}
