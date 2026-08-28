import { resolve } from "node:path";
import readline from "node:readline";
import { pathToFileURL } from "node:url";

process.stdout.on("error", (error) => {
  if (error.code === "EPIPE") process.exit(0);
  throw error;
});

const workingDirectory = process.argv[2];
const model = process.argv[3];
const modelReasoningEffort = process.argv[4];
const resumedThreadId = process.argv[5];

if (!workingDirectory || !model || !modelReasoningEffort) {
  throw new Error(
    "The Codex runner requires a working directory, model, and reasoning effort.",
  );
}

const { Codex } = await import(
  pathToFileURL(
    resolve(workingDirectory, "node_modules/@openai/codex-sdk/dist/index.js"),
  ).href
);
const codex = new Codex();
const threadOptions = {
  model,
  modelReasoningEffort,
  sandboxMode: "read-only",
  approvalPolicy: "never",
  networkAccessEnabled: false,
  webSearchMode: "disabled",
  workingDirectory,
};
const thread = resumedThreadId
  ? codex.resumeThread(resumedThreadId, threadOptions)
  : codex.startThread(threadOptions);
let threadStarted = false;

const output = (event) => process.stdout.write(`${JSON.stringify(event)}\n`);

const outputPublicItem = (type, item, text) => {
  if (
    typeof item.id === "string" &&
    item.id.length > 0 &&
    typeof text === "string" &&
    text.trim().length > 0
  ) {
    output({ type, item_id: item.id, text });
  }
};

const runTurn = async (prompt) => {
  try {
    const { events } = await thread.runStreamed(prompt);

    for await (const event of events) {
      if (event.type === "thread.started") {
        threadStarted = true;
        output({ type: "thread_started", thread_id: event.thread_id });
      } else if (
        (event.type === "item.started" ||
          event.type === "item.updated" ||
          event.type === "item.completed") &&
        event.item.type === "agent_message"
      ) {
        outputPublicItem("assistant_update", event.item, event.item.text);
      } else if (
        (event.type === "item.started" ||
          event.type === "item.updated" ||
          event.type === "item.completed") &&
        event.item.type === "reasoning"
      ) {
        outputPublicItem("reasoning_update", event.item, event.item.text);
      } else if (
        (event.type === "item.started" || event.type === "item.completed") &&
        event.item.type === "web_search"
      ) {
        outputPublicItem(
          "activity_update",
          event.item,
          event.type === "item.started"
            ? "Searching the web…"
            : "Finished searching the web.",
        );
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
      type: resumedThreadId && !threadStarted ? "resume_failed" : "error",
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
