// How long the fixture runner keeps a reply's prefix on screen before the full text. The runner and its node test
// both call `holdMsFor`, so the test checks the decision the runner really makes.

/** The prompt the server resends after a live socket drop (the drop scenarios of chat.feature). */
export const CONTINUATION_PROMPT =
  "Continue the previous answer to the user's latest request. Do not repeat text already shown.";

/** Long enough for a streaming Then step to observe the reply before it completes. */
export const RESUMED_REPLY_HOLD_MS = 10000;

/**
 * The hold for one prompt. The primary server has no deployment slot when run locally, and runs as the `blue` slot in
 * the e2e and web-test runs. A deployed candidate runs as `green` or `yellow` and answers the resend at its own pace.
 */
export function holdMsFor(prompt, reply, slot) {
  const primary = slot === undefined || slot === "blue";
  return prompt === CONTINUATION_PROMPT && primary
    ? RESUMED_REPLY_HOLD_MS
    : reply.holdMs;
}
