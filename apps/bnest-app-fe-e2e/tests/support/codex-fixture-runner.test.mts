import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { readFileSync } from "node:fs";
import path from "node:path";
import { test } from "node:test";
import {
  CONTINUATION_PROMPT,
  RESUMED_REPLY_HOLD_MS,
  holdMsFor,
} from "../../../bnest-app/test/support/codex_fixture_hold.mjs";

// The fixture runner the e2e primary server starts. A resumed turn is held on the primary and answered at once on a
// candidate, so a "still streaming" step has a real window (chat.feature, the live socket drop scenarios).
const RUNNER = path.resolve(
  import.meta.dirname,
  "../../../bnest-app/test/support/codex_fixture_runner.mjs",
);
const REPLIES = JSON.parse(
  readFileSync(
    path.resolve(
      import.meta.dirname,
      "../../../bnest-app/test/support/codex_fixture_replies.json",
    ),
    "utf8",
  ),
) as Record<string, { prefix: string; text: string; holdMs: number }>;

const continuation = REPLIES[CONTINUATION_PROMPT];
if (continuation === undefined) throw new Error("no continuation reply");

test("the primary holds a resumed turn for the full window, a candidate does not", () => {
  assert.equal(
    holdMsFor(CONTINUATION_PROMPT, continuation),
    RESUMED_REPLY_HOLD_MS,
  );
  assert.equal(
    holdMsFor(CONTINUATION_PROMPT, continuation, "blue"),
    RESUMED_REPLY_HOLD_MS,
  );
  assert.equal(
    holdMsFor(CONTINUATION_PROMPT, continuation, "green"),
    continuation.holdMs,
  );
  assert.equal(
    holdMsFor(CONTINUATION_PROMPT, continuation, "yellow"),
    continuation.holdMs,
  );
});

test("other prompts keep their own hold on every slot", () => {
  const reply = REPLIES["Resume after reconnect"];
  if (reply === undefined) throw new Error("no reconnect reply");
  assert.equal(
    holdMsFor("Resume after reconnect", reply, "blue"),
    reply.holdMs,
  );
});

/**
 * Runs the real runner on one resumed turn and times it: from the prefix to the end of the turn. The runner reads one
 * prompt line from stdin and writes JSON event lines to stdout.
 */
function timeResumedTurn(slot: string): Promise<number> {
  return new Promise((resolve, reject) => {
    const child = spawn(
      process.execPath,
      [RUNNER, "fixture", "gpt-5.6-terra", "medium", "", "read-only"],
      {
        env: { ...process.env, BNEST_DEPLOY_SLOT: slot },
        stdio: ["pipe", "pipe", "inherit"],
      },
    );
    let prefixAt: number | undefined;
    let buffered = "";
    child.stdout.on("data", (chunk: Buffer) => {
      buffered += chunk.toString("utf8");
      const lines = buffered.split("\n");
      buffered = lines.pop() ?? "";
      for (const line of lines) {
        if (line.trim() === "") continue;
        const event = JSON.parse(line) as { type: string };
        if (event.type === "assistant_update" && prefixAt === undefined)
          prefixAt = Date.now();
        if (event.type === "turn_completed") {
          child.stdin.end();
          if (prefixAt === undefined)
            reject(new Error("the turn completed without a prefix"));
          else resolve(Date.now() - prefixAt);
        }
      }
    });
    child.on("error", reject);
    child.stdin.write(
      `${JSON.stringify({ type: "prompt", prompt: CONTINUATION_PROMPT })}\n`,
    );
  });
}

test("the runner holds a resumed turn on the blue primary for the full window", async () => {
  const held = await timeResumedTurn("blue");
  assert.ok(
    held >= RESUMED_REPLY_HOLD_MS - 500,
    `the resumed reply was held ${held} ms, not ${RESUMED_REPLY_HOLD_MS} ms`,
  );
});

test("the runner answers a resumed turn on a green candidate at its own pace", async () => {
  const held = await timeResumedTurn("green");
  assert.ok(held < 2000, `a candidate held the resumed reply for ${held} ms`);
});
