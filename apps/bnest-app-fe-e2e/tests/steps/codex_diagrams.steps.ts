import { expect, type Route } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import {
  DRAWN_FIGURE,
  MARKED_DIAGRAM,
  diagramEngineRequests,
  drawMilliseconds,
  drawnFigures,
  engineAddress,
  expectDecodedPicture,
  expectDrawnPictures,
  installDrawTiming,
  latestReply,
  openChatAsAdmin,
  recordRequests,
  scrollMarkedIntoView,
  sendAndWaitForReply,
  ENGINE_CORE_CHUNK,
} from "../support/codex-diagrams";
import { clearCodexChat } from "../support/chat-ui-steps";

// The browser-only Codex diagram scenarios of chat.feature (tag @codex-diagram). Each one runs in real Chromium:
// the picture is decoded, the network is recorded, and the offline cache is used. Their unit proof is the
// Vitest binding in apps/bnest-app/assets/test/behaviour/codex_diagram.steps.ts.
const { Before, Given, Then, When } = createBdd();

// Every scenario in the group starts recording its requests before the first page opens.
Before("@codex-diagram", ({ context }) => {
  recordRequests(context);
});

// The engine's core chunk, as the build names it (apps/bnest-app/config/config.exs, `--chunk-names=chunks/[name]-[hash]`).
// LIMITS.engineRetryMs (diagram_limits.js) is 30 seconds; the page waits a little longer than that.
const ENGINE_RETRY_WINDOW_MS = 31_000;
// A cold draw may wait for the engine start (LIMITS.engineStartTimeoutMs, 20 s) and then for the render
// (LIMITS.renderTimeoutMs, 8 s). The 1,500 ms budget is reported, not asserted (see the step below).
const DRAW_TIME_LIMIT_MS = 28_000;

// --- Given ---------------------------------------------------------------------------------------------------

Given("the diagram engine cannot be loaded", async ({ page }) => {
  // Routed before the chat page opens, so the engine's import fails the first time a diagram needs it.
  await page
    .context()
    .route("**/assets/js/diagrams/**", (route) => route.abort());
});

Given(
  "a completed Codex reply marks a flowchart for drawing",
  async ({ page }) => {
    await openChatAsAdmin(page);
    await sendAndWaitForReply(page, "Show a flowchart");
  },
);

Given(
  "a completed Codex reply marks a flowchart with a syntax error for drawing",
  async ({ page }) => {
    await openChatAsAdmin(page);
    await sendAndWaitForReply(page, "Show a broken diagram");
  },
);

Given(
  "a completed Codex reply shows a drawn flowchart with its source open",
  async ({ page }) => {
    await openChatAsAdmin(page);
    await sendAndWaitForReply(page, "Show a flowchart");
    await expectDrawnPictures(page, 1);
    // The reader opens the source, and the test marks the picture so a later patch that replaces it is seen.
    await drawnFigures(page).locator("summary").click();
    await drawnFigures(page)
      .first()
      .evaluate((figure) => {
        figure.dataset["bnestProbe"] = "same";
      });
  },
);

Given("a completed Codex reply shows a drawn flowchart", async ({ page }) => {
  await openChatAsAdmin(page);
  await sendAndWaitForReply(page, "Show a flowchart");
  await expectDrawnPictures(page, 1);
});

Given(
  "a completed Codex reply marks a wide flowchart for drawing",
  async ({ page }) => {
    await openChatAsAdmin(page);
    await sendAndWaitForReply(page, "Show a wide flowchart");
  },
);

Given(
  "a completed Codex reply marks the largest allowed flowchart for drawing",
  async ({ page }) => {
    await openChatAsAdmin(page);
    // Installed before the reply completes, so the marker's arrival is measured in the page.
    await installDrawTiming(page);
    await sendAndWaitForReply(page, "Show the largest allowed flowchart");
  },
);

Given("the first start of the diagram engine fails", async ({ page }) => {
  // The hidden frame fetches the core chunk to start the engine. The first fetch is aborted and later ones pass,
  // so the first start fails and a later one can succeed. A flag, because unrouting inside the handler is too late.
  let failed = false;
  await page.context().route(ENGINE_CORE_CHUNK, async (route: Route) => {
    if (failed) {
      await route.continue();
      return;
    }
    failed = true;
    await route.abort();
  });
});

Given("a completed Codex reply has no diagram", async ({ page }) => {
  await openChatAsAdmin(page);
  await sendAndWaitForReply(page, "Show a plain follow-up");
});

// --- When ----------------------------------------------------------------------------------------------------

When("the browser draws the marked diagrams", async ({ page }) => {
  // The draw is started by the page. A diagram that cannot be drawn ends as its own figure with a note
  // (ADR 004, Decision 3), so the step waits for a figure in the latest reply, then for no marker to be left.
  // The marker reaches the page when the reply completes; it is scrolled to only once it is there.
  await expect(
    latestReply(page)
      .locator('pre[data-bnest-diagram="mermaid"], figure.bnest-diagram')
      .first(),
  ).toBeAttached({ timeout: 15_000 });
  await scrollMarkedIntoView(page);
  await expect(
    latestReply(page).locator("figure.bnest-diagram").first(),
  ).toBeAttached({
    timeout: 15_000,
  });
  await expect(page.locator(MARKED_DIAGRAM)).toHaveCount(0, {
    timeout: 15_000,
  });
});

When("the diagram engine retry window has passed", async ({ page }) => {
  // A failed start is remembered for the window and then retried by the next draw (ADR 004, Decision 4), so the
  // page waits past the window before the next reply is drawn.
  await page.waitForTimeout(ENGINE_RETRY_WINDOW_MS);
});

When("a later reply changes the conversation", async ({ page }) => {
  await sendAndWaitForReply(page, "Show a plain follow-up");
});

When("the visitor clears the chat in the browser", async ({ page }) => {
  await clearCodexChat(page);
  await expect(page.locator("[data-role=assistant-message]")).toHaveCount(0);
});

When("a later reply marks a flowchart for drawing", async ({ page }) => {
  await sendAndWaitForReply(page, "Show a second flowchart");
});

When("the network is cut", async ({ page }) => {
  await page.context().setOffline(true);
});

When("the browser draws the same flowchart again", async ({ page }) => {
  // With the network cut, a second marked fence with the same source is what the server would send; the page
  // gets it as a DOM change inside the latest reply, and the drawn picture comes from the page's own cache.
  await latestReply(page).evaluate((reply) => {
    const pre = document.createElement("pre");
    pre.dataset["bnestDiagram"] = "mermaid";
    const code = document.createElement("code");
    code.textContent = "flowchart TD\n  A --> B";
    pre.append(code);
    reply.append(pre);
  });
  await scrollMarkedIntoView(page);
  await expect(drawnFigures(page)).toHaveCount(2, { timeout: 15_000 });
});

When("the chat page loads", async ({ page }) => {
  await page.reload();
  await expect(page.locator("[data-phx-main]")).toHaveClass(/phx-connected/u);
});

// --- Then ----------------------------------------------------------------------------------------------------

Then("the picture is labelled {string}", async ({ page }, label: string) => {
  const canvas = drawnFigures(page).last().locator(".bnest-diagram-canvas");

  await expect(canvas).toHaveAttribute("role", "img");
  await expect
    .poll(async () => (await canvas.getAttribute("aria-label")) ?? "")
    .toContain(`${label}.`);
  // A drawing, not an empty box: the browser decoded the SVG and it has a natural size.
  await expectDecodedPicture(page);
});

Then(
  "the diagram source {string} is kept as text",
  async ({ page }, source: string) => {
    await expect(
      latestReply(page)
        .locator("figure.bnest-diagram pre code", { hasText: source })
        .first(),
    ).toBeAttached();
  },
);

Then("the diagram shows the note {string}", async ({ page }, note: string) => {
  await expect(
    latestReply(page).locator("figure.bnest-diagram p.bnest-diagram-note", {
      hasText: note,
    }),
  ).toHaveCount(1);
});

Then("the picture is the same node as before", async ({ page }) => {
  // The probe was set on the first picture before the later reply arrived; a replaced node has no probe.
  await expect(page.locator('[data-bnest-probe="same"]')).toHaveCount(1);
  await expect(drawnFigures(page)).toHaveCount(1);
});

Then("the diagram source is still open", async ({ page }) => {
  await expect(page.locator(`${DRAWN_FIGURE} details`).first()).toHaveAttribute(
    "open",
    "",
  );
});

Then(
  "the conversation holds {int} flowchart picture(s)",
  async ({ page }, count: number) => {
    await expectDrawnPictures(page, count);
  },
);

Then("no diagram picture remains", async ({ page }) => {
  await expect(page.locator("figure.bnest-diagram")).toHaveCount(0);
});

Then("the diagram engine stays available", async ({ page }) => {
  // The engine file is answered from the service worker's cache while the network is cut.
  const address = await engineAddress(page);
  const status = await page.evaluate(
    async (url) => (await fetch(url)).status,
    address,
  );

  expect(status).toBe(200);
  await expect(drawnFigures(page)).toHaveCount(2);
});

Then("the diagram engine was not requested", ({ page }) => {
  expect(diagramEngineRequests(page)).toEqual([]);
});

Then(
  "the largest allowed flowchart is drawn within the draw time limit",
  async ({ page, $testInfo }) => {
    const milliseconds = await drawMilliseconds(page);

    // Reported on every run as a test annotation, so a change to the caps is judged on a measured number (ADR 004,
    // Decision 4). 1,500 ms is a target, not a bound. A cold draw includes the first engine start: about 1.5 s on
    // Chromium and about 2.4 s on mobile in the measured runs. Those numbers are reported only; the asserted bound is
    // 28 s (DRAW_TIME_LIMIT_MS).
    $testInfo.annotations.push({
      type: "draw-time",
      description: `largest allowed Codex flowchart: marker to picture ${milliseconds.toFixed(0)} ms`,
    });
    // The product's limit for a cold draw: the engine start timeout plus the render timeout (diagram_limits.js).
    expect(milliseconds).toBeLessThan(DRAW_TIME_LIMIT_MS);
  },
);
