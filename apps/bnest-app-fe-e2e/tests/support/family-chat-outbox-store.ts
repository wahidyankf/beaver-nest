import { expect, type Page } from "@playwright/test";

// The browser's own outbox database, read from outside the room the way
// the room itself reads it, and the namespace a member's rows live under.
// Split from `family-chat-delivery.ts`, which drives and observes sends.

const OUTBOX_DATABASE = "bnest-family-chat-outbox";
const OUTBOX_STORE = "queuedMessages";
const ROOM_SLUG = "ruang-keluarga";

export interface StoredRow {
  namespace: string;
  clientMessageId: string;
  body: string;
  replyToMessageId?: string;
  status: string;
  createdAt: number;
}

export function currentUserId(page: Page): Promise<string> {
  return page.evaluate(
    () =>
      document.querySelector<HTMLElement>('[data-role="family-chat-room"]')
        ?.dataset["currentUserId"] ?? "",
  );
}

export function roomNamespace(userId: string): string {
  return `${userId}:${ROOM_SLUG}`;
}

/**
 * Every row in the browser's own outbox database, read the way the room
 * reads it. An absent database is reported as empty rather than created:
 * opening one that does not exist would make an empty version-1 database
 * without the room's store, which the room would then never upgrade.
 */
export function storedOutboxRows(page: Page): Promise<StoredRow[]> {
  return page.evaluate(
    async ({ name, store }) => {
      const known = await indexedDB.databases();
      if (!known.some((database) => database.name === name)) return [];
      const database = await new Promise<IDBDatabase>((resolve, reject) => {
        const request = indexedDB.open(name);
        request.addEventListener("success", () => resolve(request.result));
        request.addEventListener("error", () => reject(request.error));
      });
      try {
        if (!database.objectStoreNames.contains(store)) return [];
        return await new Promise<StoredRow[]>((resolve, reject) => {
          const request = database
            .transaction(store, "readonly")
            .objectStore(store)
            .getAll();
          request.addEventListener("success", () =>
            resolve(request.result as StoredRow[]),
          );
          request.addEventListener("error", () => reject(request.error));
        });
      } finally {
        database.close();
      }
    },
    { name: OUTBOX_DATABASE, store: OUTBOX_STORE },
  );
}

export async function storedRowFor(
  page: Page,
  body: string,
): Promise<StoredRow | undefined> {
  const rows = await storedOutboxRows(page);
  return rows.find((row) => row.body === body);
}

/** Waits until the room has written `body` through to IndexedDB. */
export async function expectStored(page: Page, body: string): Promise<StoredRow> {
  await expect
    .poll(async () => (await storedRowFor(page, body)) !== undefined, {
      timeout: 10_000,
    })
    .toBe(true);
  const row = await storedRowFor(page, body);
  if (!row) throw new Error(`no stored row for ${body}`);
  return row;
}

/** Waits until the page is controlled by the service worker. */
export async function expectServiceWorkerControl(page: Page): Promise<void> {
  await page.evaluate(() => navigator.serviceWorker.ready);
  await expect
    .poll(() => page.evaluate(() => navigator.serviceWorker.controller !== null))
    .toBe(true);
}
