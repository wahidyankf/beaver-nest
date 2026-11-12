import { expect, type Page } from "@playwright/test";
import { targetBody, targetMessage } from "./family-chat-markdown";

// Waiting helpers for the target Family chat message, shared by the Family diagram step files.
export const DRAWN = 'figure[data-bnest-diagram-state="drawn"]';
export const MARKED = 'pre[data-bnest-diagram="mermaid"]';

/** Waits until the target message's committed copy is rendered. */
export async function committedTarget(page: Page): Promise<void> {
  await expect(targetMessage(page)).toHaveAttribute(
    "data-delivery-state",
    "committed",
    {
      timeout: 20_000,
    },
  );
}

/**
 * Waits until every marked diagram in the target message has been drawn or refused. The engine draws a diagram
 * only once it is near the viewport (ADR 004, Decision 3), so a marked diagram below the fold is scrolled to here,
 * the way a reader reaching it would.
 */
export async function settledTarget(page: Page): Promise<void> {
  await committedTarget(page);
  const marked = targetBody(page).locator(MARKED);
  await expect
    .poll(
      async () => {
        // A scroll can find its node replaced by the drawn figure; the next count then sees the result.
        if ((await marked.count()) > 0) {
          // A failed scroll is not an error here: the node can be replaced by its drawn figure while the scroll
          // waits. The count below then sees the figure, and the poll repeats until no marker is left.
          await marked
            .first()
            .scrollIntoViewIfNeeded({ timeout: 2_000 })
            .catch(() => null);
        }
        return marked.count();
      },
      { timeout: 20_000 },
    )
    .toBe(0);
}
