import { readFileSync } from "node:fs";
import path from "node:path";
import { expect, type Page } from "@playwright/test";
import { waitForRoomReady } from "./family-chat-resume";
import { repositoryRoot } from "./routed-rollout-env";

// Support for the earlier-revision scenarios in family-chat-rollback-floor.steps.ts. It holds the
// held browser's GraphQL traffic, rewritten to the frozen previous-bundle documents, the judgement
// of what the rolled-back slot refuses, and the routed-read waits and reloads those scenarios share.
// The step file keeps the step definitions only.

interface FrozenDocument {
  document: string;
  variables: string[];
}

const PREVIOUS_REVISION = JSON.parse(
  readFileSync(
    path.join(
      repositoryRoot,
      "apps/bnest-app/assets/test/support/family_chat_previous_revision.json",
    ),
    "utf8",
  ),
) as {
  previousClient: { documents: Record<string, FrozenDocument> };
  rolledBackSlot: { documents: Record<string, FrozenDocument> };
};

/**
 * What the held page sent and what the rolled-back slot refused. The step definitions read and reset it.
 */
export const previousRevisionTraffic = {
  /** Requests the older page sent as the previous bundle's documents. */
  documentsSent: 0,
  /** Requests the held page sent that the frozen rolled-back slot does not accept, by operation. */
  floorRefusals: [] as string[],
};

const GRAPHQL_ROUTE = "**/api/graphql";

function operationOf(query: string): string {
  return /^\s*(?:query|mutation|subscription)\s+(\w+)/u.exec(query)?.[1] ?? "";
}

function declaredOnly(
  variables: Record<string, unknown>,
  declared: string[],
): Record<string, unknown> {
  return Object.fromEntries(
    Object.entries(variables).filter(([name]) => declared.includes(name)),
  );
}

/**
 * The page's GraphQL requests go out as the frozen previous bundle sends them, so the routed revision answers
 * the documents an older browser really holds. A release that stops accepting one fails the scenario here.
 */
export async function sendPreviousBundleDocuments(page: Page): Promise<void> {
  await page.route(GRAPHQL_ROUTE, (route) => {
    const sent = JSON.parse(route.request().postData() ?? "{}") as {
      query?: string;
      variables?: Record<string, unknown>;
    };
    const frozen =
      PREVIOUS_REVISION.previousClient.documents[operationOf(sent.query ?? "")];
    if (!frozen) return route.continue();
    previousRevisionTraffic.documentsSent += 1;
    return route.continue({
      postData: JSON.stringify({
        query: frozen.document,
        variables: declaredOnly(sent.variables ?? {}, frozen.variables),
      }),
    });
  });
}

/** Records each request the page sends that the frozen rolled-back slot would not accept. */
export async function judgeAgainstRolledBackSlot(page: Page): Promise<void> {
  await page.route(GRAPHQL_ROUTE, (route) => {
    const sent = JSON.parse(route.request().postData() ?? "{}") as {
      query?: string;
    };
    const operation = operationOf(sent.query ?? "");
    const accepted = PREVIOUS_REVISION.rolledBackSlot.documents[operation];
    if (accepted && accepted.document !== sent.query)
      previousRevisionTraffic.floorRefusals.push(operation);
    return route.continue();
  });
}

export function navigationCount(page: Page): Promise<number> {
  return page.evaluate(() => performance.getEntriesByType("navigation").length);
}

/**
 * Also the gate before any reload that follows a promotion: the room loads its
 * history once and never retries, so a reload into the churn window sits at
 * "booting" for good -- the held page, still open, can ask first.
 *
 * A promotion swaps the process behind the routed port, and `/health/ready`
 * answering with the new revision does not mean that process can reach SQLite
 * yet: the repo's pool can still be tearing down, and a request that lands in
 * that window comes back `Internal Server Error` with
 * `DBConnection.Holder.checkout ... (EXIT) shutdown` in the slot's log. It is
 * the harness's slot churn, not the room -- a plain send fails there just as a
 * reply does. So wait until the routed slot will actually answer a
 * database-backed read before asking it to commit anything.
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
          // Side by side, so the browser's other pooled connections to the
          // origin are asked too: the next real request may not reuse this one.
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
 * Reloads into the routed room. The page itself comes from the slot just
 * routed, and a slot still settling can answer that one request with an error
 * page that has no room in it; reloading again is what a person would do.
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
