import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import {
  delivery,
  expectCommitted,
  sendAttempts,
  sendThroughComposer,
} from "../support/family-chat-delivery";
import { waitForRoomReady } from "../support/family-chat-resume";
import { promoteCompatibleCandidate } from "../support/routed-rollout";
import { messageById } from "../support/family-chat-gestures";
import {
  expectMenuOpenFor,
  openMenuItems,
  openMenuWithKeyboard,
  postMessage,
  QUOTE,
  REPLY_STRIP,
  scenario,
  uniqueBody,
  waitForMessage,
} from "../support/family-chat-reply";
import { ensureRoomOpen } from "../support/family-chat-reply-room";
import { test } from "../support/test-fixtures";
import {
  expectLiveServerAnswered,
  forgetAnsweredBeforeRollback,
  judgeAgainstRolledBackSlot,
  previousRevisionTraffic,
  refusals,
  routeGraphqlWire,
  sendPreviousBundleDocuments,
} from "../support/family-chat-previous-revision";
import {
  navigationCount,
  reloadRoutedRoom,
  waitForRoutedReads,
} from "../support/family-chat-routed-room";
// AC-FCR-13's two release scenarios: a browser holding an older bundle while
// the routed slot changes beneath it. Neither ever navigates after the route
// moves. `reloadRoute` only rewrites Caddy's upstream and polls readiness
// over `page.request`, so the document, its bundle, and its socket are the
// ones loaded before the route moved, and everything the Thens judge is that
// held bundle talking to the newly routed revision.
//
// The held bundle's wire is judged against the frozen contract in
// apps/bnest-app/assets/test/support/family_chat_previous_revision.json. The older page's documents are replayed as
// the previous bundle sends them, and every document the held page sends is judged against the frozen rolled-back
// schema. Both promoted candidates are one build, so the fixture is the only earlier contract these scenarios can see.
//
// Everything is driven from the visitor's own page. An earlier version seeded
// through a second browser context, which had to log in against a slot that
// had just booted; that returned `Internal Server Error` often enough to make
// the scenario worthless. The proof does not need a second member.

/** The message seeded while the newer version is live: the reloaded held page must render it. */
let seededId = "";
/** The reply committed after the rollback -- the one the earlier revision itself answered. */
let floorReplyId = "";
/** The revision whose bundle the page holds, and the one routed after it. */
let heldRevision = "";
let routedRevision = "";

// `heldPage.rolledBack` (a test-scoped fixture) tells the shared Then which scenario's page is held.
const { Given, Then, When } = createBdd(test);

// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: A browser still running the older app version can open the room and send after an update
// @scenario specs/apps/bnest/app-fe/behaviours/family_chat.feature: After the app is rolled back, a visitor on the newer version can still open the room, reply, and see earlier quotes

// --- The earlier revision ------------------------------------------
//
// The page loads the room from an earlier routed revision -- a bundle built
// before the currently routed one -- and keeps it while a newer revision
// (a different build serving the same always-on room) is routed.

Given("the newer app version is live", async ({ page }) => {
  await ensureRoomOpen(page);
  ({ revision: heldRevision } = await promoteCompatibleCandidate(page, {
    verifyLiveView: false,
  }));
  await waitForRoutedReads(page, heldRevision);
  // Seeded before the held page reloads, so the render after that reload is the previous bundle's history at work.
  seededId = await postMessage(page, uniqueBody("Previous bundle seed"));
  await waitForMessage(page, seededId);
  // The held page reloads below through the previous bundle's wire, so its history and subscription are the
  // previous bundle's documents, each judged against the frozen rolled-back schema.
  await sendPreviousBundleDocuments(page);
  judgeAgainstRolledBackSlot(page);
  await reloadRoutedRoom(page);
  await waitForMessage(page, seededId);
  ({ revision: routedRevision } = await promoteCompatibleCandidate(page, {
    verifyLiveView: false,
  }));
  expect(routedRevision).not.toBe(heldRevision);
});

When(
  "a browser running the previous app version opens {string}",
  async ({ page }, route: string) => {
    // Already open, from before the promotion: the held page is the browser.
    expect(new URL(page.url()).pathname).toBe(route);
    expect(await navigationCount(page)).toBe(1);
    await waitForRoomReady(page);
    await waitForRoutedReads(page, routedRevision);
  },
);

Then("the room loads", async ({ page, heldPage }) => {
  await expect(page.locator('[data-role="family-chat-room"]')).toHaveAttribute(
    "data-connection-state",
    "ready",
  );
  if (heldPage.rolledBack) {
    // The held page, never reloaded, still shows the history it had: the message and the reply to it.
    await waitForMessage(page, scenario.targetId);
    await waitForMessage(page, scenario.replyId);
  } else {
    // The reloaded page renders the seeded message from its history: the previous bundle's history query answered.
    await waitForMessage(page, seededId);
  }
  // The room is otherwise exactly the shipped one: the reply strip is part
  // of the static shell, hidden until a reply target is chosen.
  await expect(page.locator(REPLY_STRIP)).toHaveAttribute("hidden", /.*/u);
  // The history query and the subscription that open the room both went out, and were judged against the frozen
  // rolled-back schema (in the rollback scenario, before the route moved: the held page is never reloaded after it).
  // The previous-bundle scenario also replayed them as that bundle sends them; the rollback scenario's held page is
  // the newer bundle, so there the judging alone proves the room opens against the rolled-back schema.
  const judged = heldPage.rolledBack
    ? heldPage.judgedBeforeRollback
    : previousRevisionTraffic.judged;
  for (const operation of [
    "FamilyChatMessages",
    "FamilyChatMessageCommitted",
  ]) {
    expect(
      judged.get(operation) ?? 0,
      `the rolled-back schema judged no ${operation} the held page sent to open the room`,
    ).toBeGreaterThan(0);
    if (!heldPage.rolledBack)
      expect(
        previousRevisionTraffic.rewritten.get(operation) ?? 0,
        `the held page sent no previous-bundle ${operation}`,
      ).toBeGreaterThan(0);
  }
  expect(
    refusals(),
    "the rolled-back schema refuses a held page document",
  ).toEqual([]);
  // The subscription can answer after this step starts: wait for it, then expect no live refusal.
  await expectLiveServerAnswered(
    heldPage.rolledBack ? "re-subscribed" : "replayed",
  );
});

Then("the visitor can send a message normally", async ({ page }) => {
  const sent = page.waitForResponse((response) =>
    (response.request().postData() ?? "").includes("SendFamilyChatMessage"),
  );
  await sendThroughComposer(page, uniqueBody("Compatibility send"));
  // Answered by the newly routed revision, through the held bundle.
  expect((await sent).headers()["x-bnest-revision"]).toBe(routedRevision);
  expect(
    previousRevisionTraffic.rewritten.get("SendFamilyChatMessage") ?? 0,
    "the older page sent no previous-bundle SendFamilyChatMessage",
  ).toBeGreaterThan(0);
  await expectCommitted(page, delivery.body);
  // The subscription can answer after this step starts: wait for it, then expect no live refusal.
  await expectLiveServerAnswered("replayed");
  expect(await navigationCount(page)).toBe(1);
});

// --- The rollback ----------------------------------------------------

Given(
  "a visitor on the newer version has a reply on screen",
  async ({ page, heldPage }) => {
    heldPage.rolledBack = true;
    await ensureRoomOpen(page);
    // Routed before the page loads the document it will hold: Playwright routes sockets through a patch injected
    // into each new document, so the reconnect after the rollback is seen only by a wire installed before this
    // page's last navigation (the reload below).
    await routeGraphqlWire(page);

    // Seeded before any promotion, against the slot already serving. The
    // server stores `replyToMessageId` unconditionally, and every bundle
    // asks for `replyTo` back.
    scenario.targetBody = uniqueBody("Rollback original");
    scenario.targetId = await postMessage(page, scenario.targetBody);
    await waitForMessage(page, scenario.targetId);

    const { revision } = await promoteCompatibleCandidate(page, {
      verifyLiveView: false,
    });
    await waitForRoutedReads(page, revision);
    await reloadRoutedRoom(page);
    await waitForRoutedReads(page, revision);

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
    //
    // Judging is armed before this reload, so the history query and the subscription the held page sends are judged
    // against the frozen rolled-back schema: the reload is the only place the room is opened, and the rollback must
    // not navigate again. The rollback keeps these refusals and counts.
    judgeAgainstRolledBackSlot(page);
    await page.reload();
    await waitForRoomReady(page);
    await waitForMessage(page, scenario.replyId);
    await expect(
      messageById(page, scenario.replyId).locator(QUOTE),
    ).toBeVisible();
  },
);

When(
  "the app is rolled back to the previous version",
  async ({ page, heldPage }) => {
    // What opened the room (the history query, the subscription) was judged before the route moves: the Then checks
    // this count, so a document judged only after the rollback cannot stand in for it. The subscription is pushed
    // once the socket joins, which can land after the room shows as ready, so wait for it before the route moves.
    await expect
      .poll(
        () => previousRevisionTraffic.judged.get("FamilyChatMessageCommitted"),
        {
          message:
            "the held page sent no FamilyChatMessageCommitted subscription to judge before the rollback",
          timeout: 15_000,
        },
      )
      .toBeGreaterThan(0);
    heldPage.judgedBeforeRollback = new Map(previousRevisionTraffic.judged);
    // Judging stays armed from the Given, so its refusals and counts stay. Only the answers are forgotten: the
    // subscription the held page opened before the route moved was answered by the newer slot, and the wait for the
    // re-subscribed one must not be satisfied by that.
    forgetAnsweredBeforeRollback();
    ({ revision: routedRevision } = await promoteCompatibleCandidate(page, {
      verifyLiveView: false,
    }));
    // The route moved under a live socket: the prior slot's connection dies
    // and the browser has to re-subscribe against the floor before it can be
    // asked anything. Without this the next step races the reconnect.
    await waitForRoomReady(page);
    await waitForRoutedReads(page, routedRevision);
  },
);

When(
  "the visitor replies again with the bundle it still holds",
  async ({ page }) => {
    // Asserting the quote already on screen would assert stale DOM -- it was
    // rendered before the rollback and would survive the earlier revision
    // answering with nothing at all. This reply is composed in the held
    // bundle's own UI and committed *after* the rollback, so rendering its
    // quote requires the earlier revision to accept `replyToMessageId` and
    // to serve `replyTo` back (tech-doc 002).
    await openMenuWithKeyboard(page, scenario.targetId);
    await expectMenuOpenFor(page, scenario.targetId);
    await openMenuItems(page).filter({ hasText: "Reply" }).first().click();
    await expect(page.locator(REPLY_STRIP)).not.toHaveAttribute(
      "hidden",
      /.*/u,
    );
    const sent = page.waitForResponse((response) =>
      (response.request().postData() ?? "").includes("SendFamilyChatMessage"),
    );
    await sendThroughComposer(page, uniqueBody("Floor reply"));
    expect((await sent).headers()["x-bnest-revision"]).toBe(routedRevision);
    expect(
      refusals(),
      "the rolled-back slot refuses a document the held bundle sends",
    ).toEqual([]);
    floorReplyId = await expectCommitted(page, delivery.body);
    // The subscription can answer after this step starts: wait for it, then expect no live refusal.
    await expectLiveServerAnswered("re-subscribed");
    expect(sendAttempts(page).at(-1)?.replyToMessageId).toBe(scenario.targetId);
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
  // The subscription can answer after this step starts: wait for it, then expect no live refusal.
  await expectLiveServerAnswered("re-subscribed");
});
