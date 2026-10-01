import { spawnSync } from "node:child_process";
import path from "node:path";
import { appDirectory, routedEnvironment } from "./routed-rollout-env";
import { assertRuntimeRoot } from "./storage-authority";
import { userDataRelativePath } from "./test-identity";

// An authenticated learner's Sifat Allah progress lives only on the server,
// so a learner who has remembered every pair is set up by saving that
// progress through the production SifatAllah facade: a `mix run` over this
// run's marked runtime root and storage pointer, the ones the server uses.
// The root must be the marked test-run child and the owner a synthetic test
// user before anything is written.
export function saveEveryPairRemembered(username: string): void {
  assertRuntimeRoot();
  const userId = path.basename(userDataRelativePath(username));
  if (
    !username.startsWith("test-user-") ||
    !/^user-test-[a-z0-9-]+$/u.test(userId)
  ) {
    throw new Error("Sifat Allah progress may be seeded only for a test user");
  }

  const expression = `
    alias BnestApp.SifatAllah
    alias BnestApp.SifatAllah.Domain.Quiz
    user_id = ${JSON.stringify(userId)}
    progress = Enum.reduce(Quiz.curriculum(), Quiz.progress(), &Quiz.remember(&2, &1.id))
    previous = case SifatAllah.load_progress(user_id) do
      {:ok, record} -> record
      {:error, :missing} -> nil
    end
    {:ok, _saved} = SifatAllah.save_progress(user_id, Map.put(progress, "session", %{"mode" => "dashboard"}), previous)
  `;
  const result = spawnSync("mix", ["run", "-e", expression], {
    cwd: appDirectory,
    env: routedEnvironment(),
    encoding: "utf8",
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(`failed to save Sifat Allah progress: ${result.stderr}`);
  }
}
