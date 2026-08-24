import { Codex } from "@openai/codex-sdk";
import readline from "node:readline";

process.stdout.on("error", (error) => {
  if (error.code === "EPIPE") process.exit(0);
  throw error;
});

const workingDirectory = process.argv[2];
const model = process.argv[3];
const modelReasoningEffort = process.argv[4];

if (!workingDirectory || !model || !modelReasoningEffort) {
  throw new Error(
    "The Codex runner requires a working directory, model, and reasoning effort.",
  );
}

const codex = new Codex();
const thread = codex.startThread({
  model,
  modelReasoningEffort,
  sandboxMode: "read-only",
  approvalPolicy: "never",
  networkAccessEnabled: false,
  webSearchMode: "disabled",
  workingDirectory,
});

const output = (event) => process.stdout.write(`${JSON.stringify(event)}\n`);

const runTurn = async (prompt) => {
  try {
    const { events } = await thread.runStreamed(prompt);

    for await (const event of events) {
      if (
        (event.type === "item.started" ||
          event.type === "item.updated" ||
          event.type === "item.completed") &&
        event.item.type === "agent_message"
      ) {
        output({ type: "assistant_update", text: event.item.text });
      } else if (event.type === "turn.completed") {
        output({ type: "turn_completed" });
      } else if (event.type === "turn.failed") {
        output({ type: "error", message: event.error.message });
      } else if (event.type === "error") {
        output({ type: "error", message: event.message });
      }
    }
  } catch (error) {
    output({
      type: "error",
      message:
        error instanceof Error ? error.message : "Codex failed unexpectedly.",
    });
  }
};

const lines = readline.createInterface({ input: process.stdin });

for await (const line of lines) {
  try {
    const message = JSON.parse(line);

    if (message.type === "prompt" && typeof message.prompt === "string") {
      await runTurn(message.prompt);
    } else {
      output({
        type: "error",
        message: "The Codex runner received an invalid prompt.",
      });
    }
  } catch {
    output({
      type: "error",
      message: "The Codex runner received invalid JSON.",
    });
  }
}
