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

// A long saved conversation for the layout scenarios: `count` messages, alternating visitor and Codex, each with a
// short synthetic body. Versions 1 to 3 are upgraded on restore, so the page opens on it with no fixture reply.
export async function saveChatWithMessages(
  username: string,
  count: number,
): Promise<void> {
  const messages = Array.from({ length: count }, (_, index) => ({
    id: index + 1,
    role: index % 2 === 0 ? "visitor" : "assistant",
    content: `Layout message ${index + 1}: a short synthetic line for the scroll check.`,
    update_count: 0,
    active_item_id: null,
    progress: [],
  }));
  await instanceLifecycle().seed(`codex-chat-${randomUUID()}`, {
    records: [
      {
        owner: username,
        kind: "codexChatTranscript",
        value: { version: 3, thread_id: "closed-thread", messages },
      },
    ],
  });
}
