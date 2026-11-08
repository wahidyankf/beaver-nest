import { randomUUID } from "node:crypto";
import { instanceLifecycle } from "./active-instance";

// The visitor's saved chat resumes `closed-thread`, the fixture Codex thread
// whose runner exits before reading a prompt (`codex_fixture_runner.mjs`), so
// the next page opens a Codex session whose runner has gone away. It is seeded as a
// `codexChatTranscript` record. The value is a version 3 snapshot with no messages: the production
// restore upgrades it to the current version and fills in the default model and effort, exactly as
// `Transcript.new/0` did before.
export async function saveChatOnExitedCodexThread(
  username: string,
): Promise<void> {
  await instanceLifecycle().seed(`codex-chat-${randomUUID()}`, {
    records: [
      {
        owner: username,
        kind: "codexChatTranscript",
        value: { version: 3, thread_id: "closed-thread", messages: [] },
      },
    ],
  });
}
