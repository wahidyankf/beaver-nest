import { saveForTestUser } from "./test-user-records";

// An authenticated learner's Sifat Allah progress lives only on the server,
// so a learner who has remembered every pair is set up by saving that
// progress through the production SifatAllah facade.
export function saveEveryPairRemembered(username: string): void {
  saveForTestUser(
    username,
    "Sifat Allah progress",
    (userId) => `
    alias BnestApp.SifatAllah
    alias BnestApp.SifatAllah.Domain.Quiz
    user_id = ${userId}
    progress = Enum.reduce(Quiz.curriculum(), Quiz.progress(), &Quiz.remember(&2, &1.id))
    previous = case SifatAllah.load_progress(user_id) do
      {:ok, record} -> record
      {:error, :missing} -> nil
    end
    {:ok, _saved} = SifatAllah.save_progress(user_id, Map.put(progress, "session", %{"mode" => "dashboard"}), previous)
  `,
  );
}
