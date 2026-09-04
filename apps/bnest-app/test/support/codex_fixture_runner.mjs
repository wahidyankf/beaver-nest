import readline from "node:readline";

process.stdout.on("error", (error) => {
  if (error.code === "EPIPE") process.exit(0);
  throw error;
});

const output = (event) => process.stdout.write(`${JSON.stringify(event)}\n`);
const lines = readline.createInterface({ input: process.stdin });
const prompts = [];
const model = process.argv[3];
const reasoningEffort = process.argv[4];
const resumedThreadId = process.argv[5];
const sandboxMode = process.argv[6];
const newThreadId = `fixture-${process.pid}`;
const expectedSettings = new Map([
  ["After model switch", ["gpt-5.6-luna", "high"]],
  ["After effort switch", ["gpt-5.6-terra", "high"]],
  ["After reload", ["gpt-5.6-luna", "high"]],
  ["Fresh start", ["gpt-5.6-luna", "high"]],
]);

if (!["read-only", "workspace-write"].includes(sandboxMode)) {
  throw new Error("Fixture runner received an invalid sandbox mode.");
}

for await (const line of lines) {
  const message = JSON.parse(line);

  if (message.type === "prompt" && typeof message.prompt === "string") {
    if (resumedThreadId === "unavailable-thread") {
      output({
        type: "resume_failed",
        message: "Fixture Codex thread is unavailable.",
      });
      continue;
    }

    if (
      message.prompt === "Remember me" &&
      !prompts.includes("Hello, Beaver Nest")
    ) {
      output({
        type: "error",
        message: "Fixture conversation was not preserved.",
      });
      continue;
    }

    if (message.prompt === "After reload" && !resumedThreadId) {
      output({
        type: "error",
        message: "Fixture Codex thread was not resumed.",
      });
      continue;
    }

    const expected = expectedSettings.get(message.prompt);

    if (
      expected &&
      (model !== expected[0] || reasoningEffort !== expected[1])
    ) {
      output({
        type: "error",
        message: "Fixture selected model or effort was not applied.",
      });
      continue;
    }

    if (
      ["After model switch", "After effort switch"].includes(message.prompt) &&
      !resumedThreadId
    ) {
      output({
        type: "error",
        message: "Fixture runtime setting switch started a new Codex thread.",
      });
      continue;
    }

    if (message.prompt === "Fresh start" && resumedThreadId) {
      output({
        type: "error",
        message: "Fixture Codex thread was not cleared.",
      });
      continue;
    }

    prompts.push(message.prompt);
    output({
      type: "thread_started",
      thread_id: resumedThreadId || newThreadId,
    });

    const responseDelay =
      message.prompt === "Resume after deployment" ? 2_000 : 750;
    await new Promise((resolve) => setTimeout(resolve, responseDelay));

    if (message.prompt === "Are you there?") {
      output({ type: "error", message: "Codex is not available." });
      continue;
    }

    if (message.prompt === "Please fail this turn") {
      output({ type: "error", message: "Turn failed." });
      continue;
    }

    if (message.prompt === "Show progress") {
      output({
        type: "reasoning_update",
        item_id: "fixture-reasoning",
        text: "Fixture reasoning summary",
      });
      // Preserve the real event boundary so the public progress state is observable
      // before the final answer closes the streaming disclosure.
      await new Promise((resolve) => setTimeout(resolve, 500));
      output({
        type: "assistant_update",
        item_id: "fixture-progress",
        text: "Fixture progress",
      });
      output({
        type: "assistant_update",
        item_id: "fixture-final",
        text: "Fixture final answer",
      });
      await new Promise((resolve) => setTimeout(resolve, 500));
      output({ type: "turn_completed" });
      continue;
    }

    if (message.prompt === "Report sandbox mode") {
      output({
        type: "assistant_update",
        item_id: "fixture-sandbox-mode",
        text: `Fixture sandbox: ${sandboxMode}`,
      });
      output({ type: "turn_completed" });
      continue;
    }

    output({
      type: "assistant_update",
      item_id: "fixture-answer",
      text: "Fixture response",
    });
    await new Promise((resolve) => setTimeout(resolve, 50));
    output({
      type: "assistant_update",
      item_id: "fixture-answer",
      text: "Fixture response complete.",
    });
    output({ type: "turn_completed" });
  }
}
