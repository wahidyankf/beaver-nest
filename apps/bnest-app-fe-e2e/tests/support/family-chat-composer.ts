import { type Page } from "@playwright/test";

// Support for family_chat.feature's "Composer focus and keyboard" rule.
// Whether the message input keeps DOM focus across a send is real
// accessibility-tree state, only observable in a real browser -- split out of
// `family-chat-resume.ts` purely to stay under this project's max-lines lint
// budget.

const INPUT_SELECTOR = '[data-role="family-chat-message-input"]';

/**
 * Counts every blur the message input takes from here on, so "the send
 * control never takes focus away" is proven across the whole send rather
 * than only sampled once it has finished.
 */
export async function recordComposerBlurs(page: Page): Promise<void> {
  await page.evaluate((selector) => {
    const input = document.querySelector<HTMLTextAreaElement>(selector);
    if (!input) throw new Error("the composer input is not rendered");
    input.dataset["blurCount"] = "0";
    input.addEventListener("blur", () => {
      input.dataset["blurCount"] = String(
        Number(input.dataset["blurCount"] ?? "0") + 1,
      );
    });
  }, INPUT_SELECTOR);
}

export function composerBlurCount(page: Page): Promise<number> {
  return page.evaluate(
    (selector) =>
      Number(
        document.querySelector<HTMLTextAreaElement>(selector)?.dataset[
          "blurCount"
        ] ?? "-1",
      ),
    INPUT_SELECTOR,
  );
}
