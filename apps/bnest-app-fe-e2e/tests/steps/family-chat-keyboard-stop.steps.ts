import { expect, type Page } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import { asAnotherMember, postMessage } from "../support/family-chat-reply";
import { instanceIdentities } from "../support/instance-identities";

// family_chat.feature, the keyboard focus scenarios of the "Diagrams in messages" rule, in Chromium at the served origin:
// keyboard focus stays in a message while its diagram picture replaces the source, and the keyboard stop can be moved
// to an older message. The shared diagram steps stay in family-chat-diagrams.steps.ts.

const { Given, When, Then } = createBdd();

// The engine's own module is held back until the visitor releases it, so a scenario can press keys while a marked
// diagram is still its source. The route matches only the engine module (`diagrams/engine...`), not its chunks.
const engineReleases = new WeakMap<Page, () => void>();

Given(
  "the diagram engine is held until the visitor releases it",
  async ({ page }) => {
    let release: (() => void) | null = null;
    const released = new Promise<void>((resolve) => {
      release = resolve;
    });
    engineReleases.set(page, () => release?.());
    await page.route(/\/assets\/js\/diagrams\/engine/u, async (route) => {
      await released;
      await route.continue();
    });
  },
);

When("the visitor releases the diagram engine", ({ page }) => {
  const release = engineReleases.get(page);
  if (!release) throw new Error("the diagram engine was not held");
  release();
});

Given(
  "{word} has sent {int} family chat messages after that",
  async ({ browser }, _sender: string, count: number) => {
    await asAnotherMember(browser, instanceIdentities(), async (other) => {
      for (let index = 0; index < count; index += 1) {
        // eslint-disable-next-line no-await-in-loop -- each message is posted after the one before it, so the order is the history's order.
        await postMessage(other, `Later note ${index}`);
      }
    });
  },
);

Then("keyboard focus is inside the keyboard stop message", async ({ page }) => {
  // The stop message is the one whose tab index is 0; focus inside it reads that attribute from the focused element.
  await expect
    .poll(() =>
      page.evaluate(
        () =>
          document.activeElement
            ?.closest('[data-role="family-chat-message"]')
            ?.getAttribute("tabindex") ?? null,
      ),
    )
    .toBe("0");
});

// Presses the key until the named message is the one keyboard stop. The room holds however many messages it holds
// (a shared room keeps earlier ones), so the press count is not part of the claim.
When(
  "the visitor presses {string} until the message {string} is the keyboard stop",
  async ({ page }, key: string, text: string) => {
    for (let press = 0; press < 40; press += 1) {
      // Each check reads the focus after the key before it, so the presses run one after another.
      // eslint-disable-next-line no-await-in-loop -- the stop is read after each press, so the checks cannot overlap.
      const stopped = await page.evaluate((body) => {
        const stops = [
          ...document.querySelectorAll<HTMLElement>(
            '[data-role="family-chat-message"][tabindex="0"]',
          ),
        ];
        return (
          stops.length === 1 && (stops[0]?.textContent ?? "").includes(body)
        );
      }, text);
      if (stopped) return;
      // eslint-disable-next-line no-await-in-loop -- one key press at a time, each after the stop has been read.
      await page.keyboard.press(key);
    }
    throw new Error(`the keyboard stop never reached ${JSON.stringify(text)}`);
  },
);
