import { runLiveMix } from "./routed-rollout";
import { userIdFor } from "./instance-identities";

// An authenticated learner's Sifat Allah progress lives only on the server,
// so a learner who has remembered every pair is set up by saving that
// progress through the production SifatAllah facade. The value is the whole curriculum
// (every pair and question kind), which only the domain module knows, so it stays a
// `mix run -e` write over the current instance. The seed route takes no such computed value yet.
export function saveEveryPairRemembered(username: string): void {
  const userId = userIdFor(username);
  const result = runLiveMix(`
    alias BnestApp.SifatAllah
    alias BnestApp.SifatAllah.Domain.Quiz
    user_id = ${JSON.stringify(userId)}
    progress = Enum.reduce(Quiz.curriculum(), Quiz.progress(), &Quiz.remember(&2, &1.id))
    previous = case SifatAllah.load_progress(user_id) do
      {:ok, record} -> record
      {:error, :missing} -> nil
    end
    {:ok, _saved} = SifatAllah.save_progress(user_id, Map.put(progress, "session", %{"mode" => "dashboard"}), previous)
  `);
  if (result.status !== 0) {
    throw new Error(`failed to save Sifat Allah progress: ${result.stderr}`);
  }
}
