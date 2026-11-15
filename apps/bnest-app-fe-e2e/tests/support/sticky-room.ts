import { mkdirSync, writeFileSync } from "node:fs";
import path from "node:path";
import type { Page, TestInfo } from "@playwright/test";

// The measuring helpers shared by the Codex and Family sticky-room steps (chat.feature and family_chat.feature, the
// Rules "... header and composer stay in place while the messages scroll"). Every box is read from the rendered page.

// A box may sit this far from the screen edge: the desktop panel keeps a 1rem margin, and a phone keeps none.
export const EDGE_TOLERANCE_PX = 24;

export interface Box {
  x: number;
  y: number;
  width: number;
  height: number;
}

export async function boxOf(page: Page, selector: string): Promise<Box> {
  const element = page.locator(selector).last();
  await element.waitFor({ state: "attached", timeout: 5000 });
  const box = await element.boundingBox();
  if (!box) throw new Error(`no box for ${selector}`);
  return box;
}

export function screenOf(page: Page): { width: number; height: number } {
  const size = page.viewportSize();
  if (!size) throw new Error("the page has no viewport");
  return size;
}

export interface RoomSelectors {
  scroller: string;
  header: string;
  composer: string;
}

// When BNEST_SCREENSHOT_DIR is set, the scrolled room is saved there for review: a PNG and a JSON file with the
// measured boxes (CSS pixels) that the ADR table is written from. Nothing is written otherwise.
export async function saveScrolledRoom(
  page: Page,
  testInfo: TestInfo,
  room: string,
  selectors: RoomSelectors,
): Promise<void> {
  const directory = process.env["BNEST_SCREENSHOT_DIR"];
  if (!directory) return;
  mkdirSync(directory, { recursive: true });
  const size = screenOf(page);
  const stem =
    testInfo.project.name + "-" + room + "-" + size.width + "x" + size.height;
  await page.screenshot({ path: path.join(directory, stem + ".png") });
  const geometry = {
    screen: size,
    scroller: await boxOf(page, selectors.scroller),
    header: await boxOf(page, selectors.header),
    composer: await boxOf(page, selectors.composer),
  };
  writeFileSync(
    path.join(directory, stem + ".json"),
    JSON.stringify(geometry, null, 2),
  );
}
