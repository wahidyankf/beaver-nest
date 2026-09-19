import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";

// family_chat.feature's "Rule: Subscription channel handshake" -- split out
// of family-chat.steps.ts purely to stay under this project's max-lines lint
// budget, matching family-chat-visibility-resume.steps.ts's own precedent.
//
// This scenario's "Given"/"When" steps are the exact same ones
// family-chat-visibility-resume.steps.ts already binds (reused verbatim by
// the feature file, not redeclared here) -- a reconnect is what re-triggers
// `graphql.js`'s `subscribe()`, the only place a per-message join could ever
// be attempted.

const { Before, Then } = createBdd();

const sentEvents: string[] = [];

Before("@subscription-handshake", ({ page }) => {
  sentEvents.length = 0;
  // Must attach before the room's own `Given` step opens the first
  // WebSocket, or the control-channel join's own frames (and the wire
  // protocol's `join_ref`/`topic` shape) would go unobserved.
  page.on("websocket", (ws) => {
    ws.on("framesent", (frame) => {
      if (typeof frame.payload !== "string") return;
      const parsed: unknown = JSON.parse(frame.payload);
      if (!Array.isArray(parsed)) return;
      const [, , topic, event] = parsed as [unknown, unknown, string, string];
      if (event === "phx_join") sentEvents.push(topic);
    });
  });
});

Then(
  "no phx_join frame is sent for any topic other than the control channel",
  () => {
    // Scoped to `__absinthe__:*` only -- the same page's unrelated LiveView
    // sockets (e.g. the login route) also send their own legitimate
    // `phx_join` frames on `lv:*` topics, which this assertion has no
    // opinion about.
    const offenders = sentEvents.filter(
      (topic) =>
        topic.startsWith("__absinthe__:") && topic !== "__absinthe__:control",
    );
    expect(
      offenders,
      `unexpected phx_join topics: ${offenders.join(", ")}`,
    ).toEqual([]);
  },
);
