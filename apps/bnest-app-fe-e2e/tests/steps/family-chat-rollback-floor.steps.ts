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
import {
  judgeAgainstRolledBackSlot,
  navigationCount,
  previousRevisionTraffic,
  reloadRoutedRoom,
  sendPreviousBundleDocuments,
  waitForRoutedReads,
} from "../support/family-chat-previous-revision";
// AC-FCR-13's two release scenarios: a browser holding an older bundle while
// the routed slot changes beneath it. Neither ever navigates after the route
// moves. `reloadRoute` only rewrites Caddy's upstream and polls readiness
// over `page.request`, so the document, its bundle, and its socket are the
// ones loaded before the route moved, and everything the Thens judge is that
// held bundle talking to the newly routed revision.
//
// The held bundle's wire is judged against the frozen contract in
// apps/bnest-app/assets/test/support/family_chat_previous_revision.json. The older page sends the previous bundle's
// documents, and the rolled-back slot must accept the reply-aware documents. Both promoted candidates are one build,
// so the fixture is the only earlier contract these scenarios can see.
//
// Everything is driven from the visitor's own page. An earlier version seeded
// through a second browser context, which had to log in against a slot that
// had just booted; that returned `Internal Server Error` often enough to make
// the scenario worthless. The proof does not need a second member.

/** The reply committed after the rollback -- the one the earlier revision itself answered. */
let floorReplyId = "";
/** The revision whose bundle the page holds, and the one routed after it. */
let heldRevision = "";
let routedRevision = "";

const { Given, Then, When } = createBdd();

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
  await reloadRoutedRoom(page);
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
    previousRevisionTraffic.documentsSent = 0;
    await sendPreviousBundleDocuments(page);
    await waitForRoomReady(page);
    await waitForRoutedReads(page, routedRevision);
  },
);

Then("the room loads", async ({ page }) => {
  await expect(page.locator('[data-role="family-chat-room"]')).toHaveAttribute(
    "data-connection-state",
    "ready",
  );
  // The room is otherwise exactly the shipped one: the reply strip is part
  // of the static shell, hidden until a reply target is chosen.
  await expect(page.locator(REPLY_STRIP)).toHaveAttribute("hidden", /.*/u);
});

Then("the visitor can send a message normally", async ({ page }) => {
  const sent = page.waitForResponse((response) =>
    (response.request().postData() ?? "").includes("SendFamilyChatMessage"),
  );
  await sendThroughComposer(page, uniqueBody("Compatibility send"));
  // Answered by the newly routed revision, through the held bundle.
  expect((await sent).headers()["x-bnest-revision"]).toBe(routedRevision);
  expect(
    previousRevisionTraffic.documentsSent,
    "the older page sent no previous-bundle document",
  ).toBeGreaterThan(0);
  await expectCommitted(page, delivery.body);
  expect(await navigationCount(page)).toBe(1);
});

// --- The rollback ----------------------------------------------------

Given(
  "a visitor on the newer version has a reply on screen",
  async ({ page }) => {
    await ensureRoomOpen(page);

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
    await page.reload();
    await waitForRoomReady(page);
    await waitForMessage(page, scenario.replyId);
    await expect(
      messageById(page, scenario.replyId).locator(QUOTE),
    ).toBeVisible();
  },
);

When("the app is rolled back to the previous version", async ({ page }) => {
  previousRevisionTraffic.floorRefusals = [];
  await judgeAgainstRolledBackSlot(page);
  ({ revision: routedRevision } = await promoteCompatibleCandidate(page, {
    verifyLiveView: false,
  }));
  // The route moved under a live socket: the prior slot's connection dies
  // and the browser has to re-subscribe against the floor before it can be
  // asked anything. Without this the next step races the reconnect.
  await waitForRoomReady(page);
  await waitForRoutedReads(page, routedRevision);
});

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
      previousRevisionTraffic.floorRefusals,
      "the rolled-back slot does not accept the held bundle's documents",
    ).toEqual([]);
    floorReplyId = await expectCommitted(page, delivery.body);
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
});
