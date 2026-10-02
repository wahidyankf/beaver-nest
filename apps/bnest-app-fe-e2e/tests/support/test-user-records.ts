import { spawnSync } from "node:child_process";
import path from "node:path";
import { appDirectory, routedEnvironment } from "./routed-rollout-env";
import { assertRuntimeRoot } from "./storage-authority";
import { userDataRelativePath } from "./test-identity";

// A synthetic user's server-side record is set up by saving it through a
// production facade: a `mix run` over this run's marked runtime root and
// storage pointer, the ones the server uses. The root must be the marked
// test-run child and the owner a synthetic test user before anything is
// written. `expression` receives the owner's quoted user ID.
export function saveForTestUser(
  username: string,
  record: string,
  expression: (quotedUserId: string) => string,
): void {
  assertRuntimeRoot();
  const userId = path.basename(userDataRelativePath(username));
  if (
    !username.startsWith("test-user-") ||
    !/^user-test-[a-z0-9-]+$/u.test(userId)
  ) {
    throw new Error(`${record} may be seeded only for a test user`);
  }

  const result = spawnSync(
    "mix",
    ["run", "-e", expression(JSON.stringify(userId))],
    { cwd: appDirectory, env: routedEnvironment(), encoding: "utf8" },
  );
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(`failed to save ${record}: ${result.stderr}`);
  }
}
