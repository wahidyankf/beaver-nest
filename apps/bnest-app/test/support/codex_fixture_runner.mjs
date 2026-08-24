import readline from "node:readline";

process.stdout.on("error", (error) => {
  if (error.code === "EPIPE") process.exit(0);
  throw error;
});

const output = (event) => process.stdout.write(`${JSON.stringify(event)}\n`);
const lines = readline.createInterface({ input: process.stdin });
const prompts = [];
const resumedThreadId = process.argv[5];
const newThreadId = `fixture-${process.pid}`;

for await (const line of lines) {
  const message = JSON.parse(line);

  if (message.type === "prompt" && typeof message.prompt === "string") {
    await new Promise((resolve) => setTimeout(resolve, 750));

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

    if (message.prompt === "Are you there?") {
      output({ type: "error", message: "Codex is not available." });
      continue;
    }

    if (message.prompt === "Please fail this turn") {
      output({ type: "error", message: "Turn failed." });
      continue;
    }

    output({ type: "assistant_update", text: "Fixture response" });
    await new Promise((resolve) => setTimeout(resolve, 50));
    output({ type: "assistant_update", text: "Fixture response complete." });
    output({ type: "turn_completed" });
  }
}
