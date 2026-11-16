import { homedir } from "node:os";
import { readdir } from "node:fs/promises";
import { resolve } from "node:path";
import readline from "node:readline";
import { pathToFileURL } from "node:url";
import { developerInstructions } from "./chat_instructions.mjs";

process.stdout.on("error", (error) => {
  if (error.code === "EPIPE") process.exit(0);
  throw error;
});

const workingDirectory = process.argv[2];
const model = process.argv[3];
const modelReasoningEffort = process.argv[4];
const resumedThreadId = process.argv[5];
const sandboxMode = process.argv[6];
// The host Codex CLI, when the Elixir port session found one on PATH. A missing binary arrives as an
// empty string and leaves the override unset, so the SDK uses its bundled CLI as before.
const systemCodexPath = process.argv[7];

if (
  !workingDirectory ||
  !model ||
  !modelReasoningEffort ||
  !["read-only", "workspace-write"].includes(sandboxMode)
) {
  throw new Error(
    "The Codex runner requires a working directory, model, reasoning effort, and allowed sandbox mode.",
  );
}

const { Codex } = await import(
  pathToFileURL(
    resolve(workingDirectory, "node_modules/@openai/codex-sdk/dist/index.js"),
  ).href
);
// Every turn of every thread, including resumed ones, starts a `codex exec` process with this developer instruction.
const codexOptions = {
  config: { developer_instructions: developerInstructions },
};

if (typeof systemCodexPath === "string" && systemCodexPath !== "") {
  codexOptions.codexPathOverride = systemCodexPath;
}

const codex = new Codex(codexOptions);
const threadOptions = {
  model,
  modelReasoningEffort,
  sandboxMode,
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

// The directory a Codex turn saves its generated images in (ADR 007, Decision 4): the Codex
// home's `generated_images/<thread_id>`, the same home the CLI itself uses. A listing that
// fails (no thread yet, no directory) is an empty set, never an error.
const generatedDir = (threadId) => {
  const home = process.env.CODEX_HOME || homedir();
  return resolve(home, "generated_images", threadId);
};

const listGenerated = async (threadId) => {
  try {
    return new Set(await readdir(generatedDir(threadId)));
  } catch {
    return new Set();
  }
};

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

    // The generated files the turn started with, per thread directory (ADR 007, Decision 4).
    // A resumed thread lists its directory at once; a fresh thread lists nothing until its
    // `thread.started` event names it.
    let currentThreadId = resumedThreadId || null;
    let baseline = currentThreadId
      ? await listGenerated(currentThreadId)
      : new Set();

    for await (const event of events) {
      if (event.type === "thread.started") {
        threadStarted = true;
        currentThreadId = event.thread_id;
        baseline = await listGenerated(currentThreadId);
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
        // Every image the turn saved that the listings can see, in lexical order, before the
        // completion itself: the transcript appends each file the reply did not reference.
        if (currentThreadId) {
          const after = await listGenerated(currentThreadId);

          for (const file of [...after]
            .filter((name) => !baseline.has(name))
            .sort()) {
            output({
              type: "image_generated",
              item_id: `generated-${file}`,
              file,
            });
          }
        }

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
