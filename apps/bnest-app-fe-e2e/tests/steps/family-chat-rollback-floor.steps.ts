import { expect, type Page } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import { waitForRoomReady } from "../support/family-chat-resume";
import { promoteCandidateWithReplyFlag } from "../support/routed-rollout";
import { messageById } from "../support/family-chat-gestures";
import {
  postMessage,
  QUOTE,
  scenario,
  uniqueBody,
  waitForMessage,
} from "../support/family-chat-reply";
import { ensureRoomOpen } from "../support/family-chat-reply-room";

// AC-FCR-13's rollback floor, split from `family-chat-reply-keyboard.steps.ts`
// to stay under this project's 300-line budget.
//
// The sibling scenario in that file throws its bundle away: its `When`
// navigates, so the browser is served fresh by whichever slot is routed and
// never actually holds the previous revision's bundle. This one never
// navigates after the rollback. `reloadRoute` only rewrites Caddy's upstream
// and polls readiness over `page.request`, so the document, its bundle, and
// its socket are the ones loaded before the route moved.
//
// Everything is driven from the visitor's own page. An earlier version seeded
// through a second browser context, which had to log in against a slot that
// had just booted; that returned `Internal Server Error` often enough to make
// the scenario worthless. The proof does not need a second member.

/** The reply committed after the rollback -- the one the floor itself answered. */
let floorReplyId = "";

const { Given, Then, When } = createBdd();

/**
 * A promotion swaps the process behind the routed port, and `/health/ready`
 * answering with the new revision does not mean that process can reach SQLite
 * yet: the repo's pool can still be tearing down, and a request that lands in
 * that window comes back `Internal Server Error` with
 * `DBConnection.Holder.checkout ... (EXIT) shutdown` in the slot's log. It is
 * the harness's slot churn, not the room -- a plain send fails there just as a
 * reply does. So wait until the routed slot will actually answer a
 * database-backed read before asking it to commit anything.
 */
async function waitForRoutedReads(page: Page): Promise<void> {
  await expect
    .poll(
      () =>
        page.evaluate(async () => {
          const response = await fetch("/api/graphql", {
            method: "POST",
            credentials: "same-origin",
            headers: {
              "content-type": "application/json",
              "x-csrf-token":
                document.querySelector<HTMLMetaElement>(
                  "meta[name='csrf-token']",
                )?.content ?? "",
            },
            body: JSON.stringify({
              query:
                "query Probe($roomSlug: String!) { familyChatMessages(roomSlug: $roomSlug, limit: 1) { nodes { id } } }",
              variables: { roomSlug: "ruang-keluarga" },
            }),
          });
          if (!response.ok) return false;
          const payload = (await response.json()) as { errors?: unknown };
          return payload.errors === undefined;
        }),
      { timeout: 20_000 },
    )
    .toBe(true);
}

Given(
  "a visitor holds the reply-aware bundle with a reply on screen",
  async ({ page, $testInfo }) => {
    await ensureRoomOpen(page, $testInfo);

    // Seeded before any promotion, against the slot already serving. The
    // server stores `replyToMessageId` whatever the flag says; only the
    // browser's willingness to ask for it back is gated.
    scenario.targetBody = uniqueBody("Rollback original");
    scenario.targetId = await postMessage(page, scenario.targetBody);
    await waitForMessage(page, scenario.targetId);

    await promoteCandidateWithReplyFlag(page, true);
    await page.reload();
    await waitForRoomReady(page);
    await waitForRoutedReads(page);

    scenario.replyId = await postMessage(
      page,
      uniqueBody("Rollback reply"),
      scenario.targetId,
    );
    // Reloading here rather than waiting for the live push: this step only
    // stages the state the scenario acts on, and waiting on a subscription
    // that has just survived a promotion made the setup fail about a third of
    // the time on mobile. The constraint that matters -- never navigating --
    // binds from the rollback onwards, not here.
    await page.reload();
    await waitForRoomReady(page);
    await waitForMessage(page, scenario.replyId);
    await expect(
      messageById(page, scenario.replyId).locator(QUOTE),
    ).toBeVisible();
  },
);

When(
  "the routed slot is rolled back to the compatibility revision",
  async ({ page }) => {
    await promoteCandidateWithReplyFlag(page, false);
    // The route moved under a live socket: the prior slot's connection dies
    // and the browser has to re-subscribe against the floor before it can be
    // asked anything. Without this the next step races the reconnect.
    await waitForRoomReady(page);
    await waitForRoutedReads(page);
  },
);

When(
  "the visitor replies again with the bundle it still holds",
  async ({ page }) => {
    // Asserting the quote already on screen would assert stale DOM -- it was
    // rendered before the rollback and would survive the floor answering with
    // nothing at all. This reply is committed *after* it, so rendering its
    // quote requires the floor to accept `replyToMessageId` and to serve
    // `replyTo` back with the reply flag off, which is the asymmetry the
    // compatibility release depends on (tech-doc 002).
    floorReplyId = await postMessage(
      page,
      uniqueBody("Floor reply"),
      scenario.targetId,
    );
    await waitForMessage(page, floorReplyId);
  },
);

Then("existing replies still render their quotes", async ({ page }) => {
  // Both: the one rendered before the rollback and the one the floor itself
  // answered with. The second is what makes this more than a stale-DOM check.
  await Promise.all(
    [scenario.replyId, floorReplyId].map(async (id) => {
      const quote = messageById(page, id).locator(QUOTE);
      await expect(quote).toBeVisible();
      await expect(quote).toContainText(scenario.targetBody);
    }),
  );
});
