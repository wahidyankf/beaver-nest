import { expect, type Page } from "@playwright/test";
import { waitForRoomReady } from "./family-chat-resume";

// The held page after a route change: the reads it waits for and the reload it may need, split from
// family-chat-previous-revision.ts (the wire) to keep each file under the line budget.

export function navigationCount(page: Page): Promise<number> {
  return page.evaluate(() => performance.getEntriesByType("navigation").length);
}

/**
 * Also the gate before any reload after a promotion. A room reloaded into the churn window sits at "booting" for
 * good, as it loads its history once and never retries. `/health/ready` on the new revision does not mean the process
 * can reach SQLite yet: a request there fails with `DBConnection.Holder.checkout ... (EXIT) shutdown`. That is slot
 * churn, not the room, so wait until a database-backed read succeeds before asking it to commit. The held page, still
 * open, can ask first.
 */
export async function waitForRoutedReads(
  page: Page,
  revision: string,
): Promise<void> {
  await expect
    .poll(
      () =>
        page.evaluate(async (expected) => {
          const probe = async (): Promise<boolean> => {
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
            // Answered by the revision just routed, not one still draining.
            if (response.headers.get("x-bnest-revision") !== expected)
              return false;
            const payload = (await response.json()) as { errors?: unknown };
            return payload.errors === undefined;
          };
          // Side by side, so the browser's other pooled connections are asked too: the next request may not reuse one.
          const answers = await Promise.all(
            Array.from({ length: 6 }, () => probe().catch(() => false)),
          );
          return answers.every(Boolean);
        }, revision),
      { timeout: 20_000 },
    )
    .toBe(true);
}

/**
 * Reloads into the routed room. A slot still settling can answer that one request with an error page with no room in
 * it; reloading again is what a person would do.
 */
export async function reloadRoutedRoom(page: Page): Promise<void> {
  const room = page.locator('[data-role="family-chat-room"]');
  for (let attempt = 1; attempt <= 3; attempt += 1) {
    // eslint-disable-next-line no-await-in-loop -- each reload is judged on its own result.
    await page.reload();
    // eslint-disable-next-line no-await-in-loop -- see above.
    const loaded = await room
      .waitFor({ state: "attached", timeout: 5_000 })
      .then(() => true)
      .catch(() => false);
    if (loaded) break;
  }
  await waitForRoomReady(page);
}
