import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import {
  MARKED_DIAGRAM,
  drawnFigures,
  expectFrameRefusesOutsidePicture,
  latestReply,
  offOriginRequests,
  openChatAsAdmin,
  scriptOrHandlerInConversation,
  sendAndWaitForReply,
} from "../support/codex-diagrams";

// The hostile-diagram scenario of chat.feature (ADR 004, Decisions 1 and 2): a script, an event handler, an outside
// picture and shape data in a diagram must not reach the reader. The shared Before hook is in codex_diagrams.steps.ts.
const { Given, Then } = createBdd();

Given(
  "a completed Codex reply holds hostile diagram text",
  async ({ page }) => {
    await openChatAsAdmin(page);
    await sendAndWaitForReply(page, "Show hostile diagram text");
  },
);

// The frame's own policy is the second line after the server's gate: a picture from another origin, asked for
// inside the diagram frame, must be refused by the frame's Content-Security-Policy and never requested.
Then("the picture loads nothing from another origin", async ({ page }) => {
  // Every request of the scenario, from its first page, is on the test origin.
  expect(offOriginRequests(page)).toEqual([]);
  await expectFrameRefusesOutsidePicture(page);
});

Then(
  "no script or event handler from the diagram text runs",
  async ({ page }) => {
    expect(await scriptOrHandlerInConversation(page)).toBe(false);
    expect(offOriginRequests(page)).toEqual([]);
  },
);

// The server refuses a fence with shape data (`@{`) before the browser sees it: the source stays a code block, and
// the note the server writes after it is the only picture-free text. If the server's gate were removed, the fence
// would be marked and drawn, and this step would fail.
Then(
  "the diagram with shape data is not drawn and shows the note that settings are not allowed",
  async ({ page }) => {
    // The reply's `click` fence is refused with the same note, so the note is matched only after the shape fence.
    await expect(
      latestReply(page)
        .locator("pre")
        .filter({ has: page.locator("code", { hasText: "imageSquare" }) })
        .locator("xpath=following-sibling::p[1]//em"),
    ).toHaveText("Diagram not drawn: it uses settings that are not allowed.");
    await expect(
      latestReply(page).locator(MARKED_DIAGRAM, { hasText: "imageSquare" }),
    ).toHaveCount(0);
    await expect(
      latestReply(page).locator("figure.bnest-diagram", {
        hasText: "imageSquare",
      }),
    ).toHaveCount(0);
  },
);

Then("the diagram text shows as text only", async ({ page }) => {
  const code = drawnFigures(page).first().locator(".bnest-diagram-source code");

  await expect(code).toContainText("<script>");
  await expect(code.locator("*")).toHaveCount(0);
});
