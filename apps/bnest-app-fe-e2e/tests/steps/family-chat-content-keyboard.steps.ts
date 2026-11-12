import { expect, type Page } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import { setTargetMessage, targetIdOf } from "../support/family-chat-markdown";
import { asAnotherMember, postMessage } from "../support/family-chat-reply";
import { ensureRoomOpen } from "../support/family-chat-reply-room";
import { instanceIdentities } from "../support/instance-identities";
import {
  DRAWN,
  describeFocus,
  diagramMessage,
  expectNewTabOpened,
  focusIsOn,
  focusIsOnMessage,
  focusIsOutsideHistory,
  focusRing,
  KIND_SELECTOR,
  linkStopCount,
  LIST,
  measuredRegion,
  MESSAGE,
  pressKeyboard,
  settleDiagrams,
  stopBodies,
  waitForCommitted,
  WIDE_BODIES,
} from "../support/family-chat-keyboard";

// family_chat.feature's "Keyboard reach of message content" rule, in Chromium at the served origin. Keys are real
// presses, and focus, overflow, scroll, the focus ring and the link's popup are measured in the page. The unit adapter
// (`family_chat_keyboard.steps.ts`) reads the same steps against a stand-in browser.

const { Given, Then, When } = createBdd();

function requireTarget(page: Page): string {
  const id = targetIdOf(page);
  if (!id) throw new Error("no message was named for this step");
  return id;
}

function requireKind(name: string): string {
  if (KIND_SELECTOR[name] === undefined)
    throw new Error(`no content kind named ${name}`);
  return name;
}

// --- Givens ---------------------------------------------------------------

Given(
  "the history holds {int} messages, each with a link",
  async ({ browser }, count: number) => {
    // Numbered from 0, so the newest message is "Note {count - 1}", the one the room's single stop lands on.
    await asAnotherMember(browser, instanceIdentities(), async (other) => {
      for (let index = 0; index < count; index += 1) {
        // eslint-disable-next-line no-await-in-loop -- each message is posted after the one before it, so the order is the history's order.
        await postMessage(
          other,
          `Note ${index} [link ${index}](https://example.test/${index})`,
        );
      }
    });
  },
);

Given(
  "{word} has sent a wide {string} message",
  async ({ page, browser }, _sender: string, kind: string) => {
    const body = WIDE_BODIES[kind];
    if (body === undefined) throw new Error(`no wide body for ${kind}`);
    const id = await asAnotherMember(browser, instanceIdentities(), (other) =>
      postMessage(other, body),
    );
    setTargetMessage(page, id);
  },
);

/** Opens the room and checks the named region of the target message against its box, once the message is drawn. */
async function checkTargetRegion(
  page: Page,
  name: string,
  wider: boolean,
): Promise<void> {
  requireKind(name);
  await ensureRoomOpen(page);
  const id = requireTarget(page);
  await waitForCommitted(page, id);
  if (name === "diagram") await settleDiagrams(page);
  await expect
    .poll(() => measuredRegion(page, name, id), { timeout: 15_000 })
    .toEqual(expect.objectContaining({ found: true, overflows: wider }));
}

Given(
  "the {string} in the message is wider than its box",
  async ({ page }, name: string) => {
    await checkTargetRegion(page, name, true);
  },
);

Given(
  "the {string} in the message fits its box",
  async ({ page }, name: string) => {
    await checkTargetRegion(page, name, false);
  },
);

// --- Whens ----------------------------------------------------------------

When("the visitor presses {string}", async ({ page }, key: string) => {
  await pressKeyboard(page, key);
});

When(
  "the visitor presses {string} until keyboard focus is on {string}",
  async ({ page }, key: string, name: string) => {
    for (let press = 0; press < 8; press += 1) {
      // eslint-disable-next-line no-await-in-loop -- each press is judged before the next.
      if (await focusIsOn(page, name)) return;
      // eslint-disable-next-line no-await-in-loop -- same.
      await pressKeyboard(page, key);
    }
    expect(
      await focusIsOn(page, name),
      `${key} never moved keyboard focus to ${JSON.stringify(name)}; focus is on ${await describeFocus(page)}`,
    ).toBe(true);
  },
);

// --- Thens ----------------------------------------------------------------

Then("keyboard focus is on {string}", async ({ page }, name: string) => {
  await expect
    .poll(async () =>
      (await focusIsOn(page, name)) ? "" : await describeFocus(page),
    )
    .toBe("");
});

Then(
  "keyboard focus is on the message {string}",
  async ({ page }, text: string) => {
    await expect
      .poll(async () =>
        (await focusIsOnMessage(page, text)) ? "" : await describeFocus(page),
      )
      .toBe("");
  },
);

Then("keyboard focus is outside the history", async ({ page }) => {
  await expect
    .poll(async () =>
      (await focusIsOutsideHistory(page)) ? "" : await describeFocus(page),
    )
    .toBe("");
});

Then(
  "the message {string} is the keyboard stop",
  async ({ page }, text: string) => {
    await expect
      .poll(() => stopBodies(page))
      .toEqual([expect.stringContaining(text)]);
  },
);

Then("exactly one link in the history is a tab stop", async ({ page }) => {
  await expect.poll(() => linkStopCount(page)).toBe(1);
});

Then(
  "the link {string} opens its address in a new tab",
  async ({ page }, text: string) => {
    await expectNewTabOpened(page, text);
  },
);

Then("the diagram source is shown", async ({ page }) => {
  await expect(
    page.locator(`${LIST} details.bnest-diagram-source`).first(),
  ).toHaveJSProperty("open", true);
});

Then(
  "the {string} is scrolled to the right",
  async ({ page }, name: string) => {
    requireKind(name);
    const id = requireTarget(page);
    await expect
      .poll(async () => (await measuredRegion(page, name, id)).scrollLeft)
      .toBeGreaterThan(0);
  },
);

Then(
  "the {string} shows a visible focus ring",
  async ({ page }, name: string) => {
    requireKind(name);
    const ring = await focusRing(page);
    expect(ring.focusVisible, `focus on ${name} is visible focus`).toBe(true);
    expect(ring.outlineStyle, `outline on ${name}`).not.toBe("none");
    expect(ring.outlineWidth, `outline width on ${name}`).toBeGreaterThan(0);
  },
);

Then(
  "the diagram message shows a diagram labelled {string}",
  async ({ page }, label: string) => {
    await settleDiagrams(page);
    await expect(
      diagramMessage(page).locator(
        `${DRAWN} .bnest-diagram-canvas[aria-label^="${label}."]`,
      ),
    ).toHaveCount(1, { timeout: 20_000 });
  },
);

Then("the diagram message adds no tab stop", async ({ page }) => {
  await settleDiagrams(page);
  const figure = diagramMessage(page).locator(DRAWN).first();
  await expect(figure).toHaveCount(1);
  const stops = await figure.evaluate((element) => {
    const canvas = element.querySelector<HTMLElement>(".bnest-diagram-canvas");
    const summary = element.querySelector<HTMLElement>(
      ".bnest-diagram-source > summary",
    );
    return { canvas: canvas?.tabIndex, summary: summary?.tabIndex };
  });
  expect(stops, "tab index of the picture and its source summary").toEqual({
    canvas: -1,
    summary: -1,
  });
  const inHistory = await page.evaluate((message) => {
    const items = [...document.querySelectorAll<HTMLElement>(message)];
    return {
      messageStops: items.filter((item) => item.tabIndex === 0).length,
      insideMessages: items.flatMap((item) =>
        [
          ...item.querySelectorAll<HTMLElement>(
            "a[href], button, input, summary, [tabindex]",
          ),
        ].filter((element) => element.tabIndex >= 0),
      ).length,
    };
  }, MESSAGE);
  expect(inHistory.messageStops, "messages holding the single tab stop").toBe(
    1,
  );
  expect(inHistory.insideMessages, "tab stops inside messages").toBe(0);
});
