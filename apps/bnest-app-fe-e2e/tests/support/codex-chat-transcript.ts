import { saveForTestUser } from "./test-user-records";

// The visitor's saved chat resumes `closed-thread`, the fixture Codex thread
// whose runner exits before reading a prompt (`codex_fixture_runner.mjs`), so
// the next page opens a Codex session whose runner has gone away. It is saved
// through the production CodexChat facade.
export function saveChatOnExitedCodexThread(username: string): void {
  saveForTestUser(
    username,
    "a Codex chat",
    (userId) => `
    alias BnestApp.CodexChat
    alias BnestApp.CodexChat.Domain.Transcript
    user_id = ${userId}
    previous = case CodexChat.load_transcript(user_id) do
      {:ok, _transcript, record} -> record
      {:error, :missing} -> nil
    end
    transcript = Transcript.put_thread_id(Transcript.new(), "closed-thread")
    {:ok, _saved} = CodexChat.save_transcript(user_id, transcript, previous)
  `,
  );
}
