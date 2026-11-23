import { readFileSync } from "node:fs";
import readline from "node:readline";
import { holdMsFor } from "./codex_fixture_hold.mjs";

// The canned replies, shared with `BnestApp.Test.CodexFixtureConversation`: a prefix the page shows
// first, then the full text after `holdMs`.
const replies = JSON.parse(
  readFileSync(
    new URL("./codex_fixture_replies.json", import.meta.url),
    "utf8",
  ),
);

process.stdout.on("error", (error) => {
  if (error.code === "EPIPE") process.exit(0);
  throw error;
});

const output = (event) => process.stdout.write(`${JSON.stringify(event)}\n`);
const lines = readline.createInterface({ input: process.stdin });
// Held only on the primary slot of the deployment scenario. A reconnect resend of any other prompt is answered there.
const deploymentHeldPrompts = new Set(["Resume after deployment"]);
// After a live socket drop the server resends the turn as this continuation. Its reply is held on the primary, so a
// test can observe the resumed reply while it still streams (`holdMsFor`, codex_fixture_hold.mjs).
const prompts = [];
const model = process.argv[3];
const reasoningEffort = process.argv[4];
const resumedThreadId = process.argv[5];
const sandboxMode = process.argv[6];
// A thread id the strict generated-image name rule accepts (hex and hyphens
// only, with a hyphen): the process id in hex keeps one runner's thread
// distinct from another's. A `fixture-<pid>` thread renders no image because
// `GeneratedImage.reference/2` refuses it and the reply keeps the reference
// as text instead of an inline image.
const newThreadId = `9f1e4a2b-${process.pid.toString(16)}`;
const expectedSettings = new Map([
  ["After model switch", ["gpt-6-luna", "high"]],
  ["After effort switch", ["gpt-6.1-terra", "high"]],
  ["After reload", ["gpt-6-luna", "high"]],
  ["Fresh start", ["gpt-6-luna", "high"]],
]);

if (!["read-only", "workspace-write"].includes(sandboxMode)) {
  throw new Error("Fixture runner received an invalid sandbox mode.");
}

// A Codex runner that has gone away: resuming this thread exits before reading any prompt,
// so the session holding it must refuse the next prompt itself.
if (resumedThreadId === "closed-thread") process.exit(0);

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

    // A resume failure whose message carries transport noise: the session must strip the
    // `rmcp::` line before the owner sees it, leaving only the genuine failure.
    if (resumedThreadId === "noisy-thread") {
      output({
        type: "resume_failed",
        message:
          "ERROR rmcp::transport::worker: worker quit with fatal: AuthRequired(MCP server `foo` requires login)\nFixture Codex thread is unavailable.",
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

    // The primary slot never finishes these turns, so only the turn a deployed candidate
    // resends can answer them.
    if (
      deploymentHeldPrompts.has(message.prompt) &&
      process.env.BNEST_DEPLOY_SLOT === "blue"
    ) {
      continue;
    }

    await new Promise((resolve) => setTimeout(resolve, 750));

    if (message.prompt === "Please fail this turn") {
      output({ type: "error", message: "Turn failed." });
      continue;
    }

    // A runner that is gone before it answers: the session reports the exit
    // status to its owner, which shows one fixed line and frees the composer.
    if (message.prompt === "Exit the runner") {
      process.exit(3);
    }

    // A runner that prints a line which is not JSON, or JSON of an unknown
    // event: the session reports invalid data to its owner, which shows one
    // fixed line and frees the composer.
    if (message.prompt === "Return invalid runner data") {
      process.stdout.write("this line is not runner JSON\n");
      output({ type: "turn_completed" });
      continue;
    }

    // A host plugin MCP server that is not logged in prints transport noise to the runner's
    // stderr, and the SDK embeds it in the turn error. The session must strip those lines
    // before the owner sees them; only the genuine error lines survive.
    if (message.prompt === "Please fail with transport noise") {
      output({
        type: "error",
        message:
          "ERROR rmcp::transport::worker: worker quit with fatal: AuthRequired(MCP server `foo` requires login)\nAuthRequired: sign-in required for the model provider\nTurn failed.",
      });
      continue;
    }

    // A turn that saves a generated image the reply never references (ADR 007, Decision 4):
    // the runner's directory diff emits the fallback event the transcript appends.
    if (message.prompt === "Generate an image without a reference") {
      output({
        type: "assistant_update",
        item_id: "fixture-image",
        text: "Here is your image.",
      });
      output({
        type: "image_generated",
        item_id: "generated-exec-fixture-image.png",
        file: "exec-fixture-image.png",
      });
      output({ type: "turn_completed" });
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

    // The prefix stays on screen for `holdMs`, so a test can observe a reply that is still streaming.
    if (Object.hasOwn(replies, message.prompt)) {
      const reply = replies[message.prompt];
      const holdMs = holdMsFor(
        message.prompt,
        reply,
        process.env.BNEST_DEPLOY_SLOT,
      );
      output({
        type: "assistant_update",
        item_id: "fixture-reply",
        text: reply.prefix,
      });
      await new Promise((resolve) => setTimeout(resolve, holdMs));
      output({
        type: "assistant_update",
        item_id: "fixture-reply",
        text: reply.text,
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
