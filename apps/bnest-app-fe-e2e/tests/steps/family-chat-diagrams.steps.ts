import { expect, type Page } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import { messageById } from "../support/family-chat-gestures";
import {
  asAnotherMember,
  postMessage,
  scenario,
} from "../support/family-chat-reply";
import { sendThroughComposer } from "../support/family-chat-delivery";
import { waitForRoomSubscribed } from "../support/family-chat-socket";
import { instanceIdentities } from "../support/instance-identities";
import {
  setTargetMessage,
  targetBody,
  targetMessage,
} from "../support/family-chat-markdown";
import {
  canaryFired,
  diagramBody,
  fenceSourcesOf,
  recordRequests,
  requestsLeavingOrigin,
  setTypedBody,
  typedBodyOf,
} from "../support/family-chat-diagrams";

// family_chat.feature's "Diagrams in messages" rule, in Chromium at the served origin. The unit adapter
// (`family_chat_diagrams.steps.ts`) reads the same steps against a stand-in engine; here the engine is the one the
// root layout names, and the layout, the picture, the requests and the injection canary are measured in the page.
//
// Another member's messages are sent through their own session (`asAnotherMember`), so the author is a real second
// member. A Then waits for the message's committed copy before it reads the body.

import {
  DRAWN,
  committedTarget,
  settledTarget,
} from "../support/family-chat-diagram-settle";

const { Given, When, Then } = createBdd();

/** Names the message a later step is about, for both the page-keyed lookup and the reply and menu steps. */
function pointTo(page: Page, messageId: string): void {
  setTargetMessage(page, messageId);
  scenario.targetId = messageId;
}

Given(
  "{word} has sent this family chat message:",
  async ({ page, browser }, _sender: string, body: string) => {
    recordRequests(page);
    // The copy step reads the clipboard back; a member who copies has granted the page the clipboard.
    await page
      .context()
      .grantPermissions(["clipboard-read", "clipboard-write"]);
    setTypedBody(page, body);
    const id = await asAnotherMember(browser, instanceIdentities(), (other) =>
      postMessage(other, body),
    );
    pointTo(page, id);
  },
);

Given(
  "{word} has sent the diagram message {string}",
  async ({ page, browser }, _sender: string, kind: string) => {
    recordRequests(page);
    const body = diagramBody(kind);
    setTypedBody(page, body);
    const id = await asAnotherMember(browser, instanceIdentities(), (other) =>
      postMessage(other, body),
    );
    pointTo(page, id);
  },
);

When(
  "{word} sends this family chat message while the visitor watches:",
  async ({ page, browser }, _sender: string, body: string) => {
    recordRequests(page);
    setTypedBody(page, body);
    await waitForRoomSubscribed(page);
    const id = await asAnotherMember(browser, instanceIdentities(), (other) =>
      postMessage(other, body),
    );
    pointTo(page, id);
    await expect(messageById(page, id)).toHaveCount(1, { timeout: 15_000 });
  },
);

When(
  "the visitor sends this family chat message:",
  async ({ page }, body: string) => {
    recordRequests(page);
    setTypedBody(page, body);
    await sendThroughComposer(page, body);
  },
);

Then(
  "the message shows a diagram labelled {string}",
  async ({ page }, label: string) => {
    await settledTarget(page);
    await expect(
      targetBody(page).locator(
        `${DRAWN} .bnest-diagram-canvas[aria-label^="${label}."]`,
      ),
    ).toHaveCount(1, { timeout: 20_000 });
  },
);

Then("the message shows the note {string}", async ({ page }, note: string) => {
  await settledTarget(page);
  await expect(targetBody(page)).toContainText(note, { timeout: 20_000 });
});

Then("the message keeps its diagram source as text", async ({ page }) => {
  await committedTarget(page);
  const expected = fenceSourcesOf(typedBodyOf(page));
  await expect
    .poll(async () =>
      (await targetBody(page).locator("pre").allTextContents()).map((text) =>
        text.replace(/\s+$/u, ""),
      ),
    )
    .toEqual(expect.arrayContaining(expected));
});

Then(
  "the message shows the diagram source as typed text with no drawing",
  async ({ page }) => {
    const body = targetBody(page);
    await expect(body).toHaveAttribute("data-body-format", "text", {
      timeout: 20_000,
    });
    await expect(body.locator("figure, pre")).toHaveCount(0);
    await expect
      .poll(() => body.evaluate((element) => element.textContent))
      .toBe(typedBodyOf(page));
  },
);

Then(
  "the message shows {int} drawn diagrams",
  async ({ page }, count: number) => {
    await settledTarget(page);
    await expect(targetBody(page).locator(DRAWN)).toHaveCount(Number(count), {
      timeout: 20_000,
    });
  },
);

Then("no script from the message runs", async ({ page }) => {
  await settledTarget(page);
  await expect(targetBody(page).locator("script")).toHaveCount(0);
  expect(await canaryFired(page), "the injection canary fired").toBe(false);
  expect(requestsLeavingOrigin(page), "requests that left the origin").toEqual(
    [],
  );
});

Then("the clipboard holds the message as typed", async ({ page }) => {
  await expect
    .poll(() => page.evaluate(() => navigator.clipboard.readText()))
    .toBe(typedBodyOf(page));
});

Then("the reply quotes the typed message as plain text", async ({ page }) => {
  await committedTarget(page);
  // The server's quote preview collapses every run of whitespace, so the typed Markdown is compared in that form.
  const collapsed = typedBodyOf(page).replaceAll(/\s+/gu, " ").trim();
  const preview = targetMessage(page).locator(
    '[data-role="family-chat-message-quote-preview"]',
  );
  await expect(preview).toHaveText(collapsed);
  await expect(preview.locator("*")).toHaveCount(0);
});

Then(
  "the drawn diagram sits on its own paper surface in the own bubble",
  async ({ page }) => {
    await settledTarget(page);
    const figure = targetBody(page).locator(DRAWN).first();
    await expect(figure).toHaveCount(1);
    // The page resolves the paper token itself, so the comparison is between two computed colours.
    const colours = await figure.evaluate((element) => {
      const probe = document.createElement("i");
      probe.style.backgroundColor = "var(--bnest-paper)";
      element.append(probe);
      const expected = getComputedStyle(probe).backgroundColor;
      probe.remove();
      return { actual: getComputedStyle(element).backgroundColor, expected };
    });
    expect(colours.expected, "the paper token resolves").not.toBe("");
    expect(colours.actual).toBe(colours.expected);
  },
);

Then("the diagram fits the message bubble", async ({ page }) => {
  await settledTarget(page);
  const figure = targetBody(page).locator(DRAWN).first();
  await expect(figure).toHaveCount(1);
  const fit = await figure.evaluate((element) => {
    const bubble = element.closest<HTMLElement>(".family-chat-message-bubble");
    if (!bubble) return null;
    const picture = element.querySelector<HTMLElement>(
      ".bnest-diagram-canvas img",
    );
    return {
      bubbleScroll: bubble.scrollWidth,
      bubbleClient: bubble.clientWidth,
      figureWidth: element.getBoundingClientRect().width,
      pictureWidth: picture?.getBoundingClientRect().width ?? 0,
    };
  });
  expect(fit, "the figure sits inside a message bubble").not.toBeNull();
  expect(fit?.bubbleScroll, "bubble scroll width").toBeLessThanOrEqual(
    fit?.bubbleClient ?? 0,
  );
  expect(fit?.figureWidth, "figure width against bubble").toBeLessThanOrEqual(
    fit?.bubbleClient ?? 0,
  );
  expect(fit?.pictureWidth, "picture width against bubble").toBeLessThanOrEqual(
    fit?.bubbleClient ?? 0,
  );
});
