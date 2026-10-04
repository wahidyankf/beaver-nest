import type { Page } from "@playwright/test";
import { focusDescriptor, type PageHelpers } from "./backup-integrity-page";

// How the Schedules page sits around its `Backup files` label: the reading order, the tab
// stops, and the reflow at the viewport a journey set. The label is found by the helpers
// `backup-integrity-page.ts` installed in the page, so a trace is installed first.

export type ReadingOrder = {
  afterLastResult: boolean;
  beforeForms: boolean;
};

export type TabWalk = {
  domOrder: string[];
  insideLabel: string[];
  stops: string[];
};

export type ProblemLayout = {
  clipped: boolean;
  left: number;
  right: number;
  text: string;
  visible: boolean;
  wraps: boolean;
};

// Whether the label comes after the row's `Last result` term and before the page's forms.
export function readingOrder(page: Page): Promise<ReadingOrder> {
  return page.evaluate(() => {
    const row = document.querySelector(
      '[data-schedule-key="prod-sqlite-backup-daily"]',
    );
    const terms = [...(row?.querySelectorAll("dt") ?? [])];
    const label = terms.find(
      (term) => term.textContent?.trim() === "Backup files",
    );
    const last = terms.find(
      (term) => term.textContent?.trim() === "Last result",
    );
    const form = document.querySelector('form[phx-submit="save_schedule"]');
    const following = Node.DOCUMENT_POSITION_FOLLOWING;
    return {
      afterLastResult:
        label !== undefined &&
        last !== undefined &&
        (last.compareDocumentPosition(label) & following) !== 0,
      beforeForms:
        label !== undefined &&
        form !== null &&
        (label.compareDocumentPosition(form) & following) !== 0,
    };
  });
}

// The page's focusable controls in document order, those inside the label among them.
function focusableControls(
  page: Page,
): Promise<{ domOrder: string[]; labelStops: string[] }> {
  return page.evaluate(() => {
    const helpers = (window as unknown as Record<string, PageHelpers>)[
      "__backupLabel"
    ] as PageHelpers;
    const item = helpers.item();
    const focusable = [
      ...document.querySelectorAll(
        'a[href], button:not([disabled]), input:not([disabled]):not([type="hidden"]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])',
      ),
    ].filter((element) => element.getClientRects().length > 0);
    (document.activeElement as HTMLElement | null)?.blur();
    window.scrollTo(0, 0);
    return {
      domOrder: focusable.map((element) => helpers.describe(element)),
      labelStops: focusable
        .filter((element) => item?.contains(element) ?? false)
        .map((element) => helpers.describe(element)),
    };
  });
}

function focusIsInsideLabel(page: Page): Promise<boolean> {
  return page.evaluate(() => {
    const helpers = (window as unknown as Record<string, PageHelpers>)[
      "__backupLabel"
    ] as PageHelpers;
    return helpers.item()?.contains(document.activeElement) ?? false;
  });
}

// Presses Tab once per focusable control and names each stop, next to the controls the page
// holds in document order and the stops that fall inside the label.
export async function walkTabStops(page: Page): Promise<TabWalk> {
  const { domOrder, labelStops } = await focusableControls(page);
  const stops: string[] = [];
  const insideLabel = [...labelStops];
  for (let stop = 0; stop < domOrder.length; stop += 1) {
    // eslint-disable-next-line no-await-in-loop -- each press moves focus from where the last one left it.
    await page.keyboard.press("Tab");
    // eslint-disable-next-line no-await-in-loop -- the stop is read before the next press moves it.
    const current = await focusDescriptor(page);
    stops.push(current);
    // eslint-disable-next-line no-await-in-loop -- same.
    if (await focusIsInsideLabel(page)) insideLabel.push(current);
  }
  return { domOrder, insideLabel, stops };
}

export function pageOverflow(page: Page): Promise<number> {
  return page.evaluate(() =>
    Math.max(document.documentElement.scrollWidth, document.body.scrollWidth),
  );
}

// For each problem line: visible, inside the viewport, wrapped and not clipped.
export function problemLayouts(page: Page): Promise<ProblemLayout[]> {
  return page.evaluate(() => {
    const helpers = (window as unknown as Record<string, PageHelpers>)[
      "__backupLabel"
    ] as PageHelpers;
    const lines = [...(helpers.item()?.querySelectorAll("dd li") ?? [])];
    return lines.map((line) => {
      const box = line.getBoundingClientRect();
      const style = getComputedStyle(line);
      let clipped =
        style.textOverflow === "ellipsis" ||
        line.scrollWidth > line.clientWidth + 1;
      for (
        let ancestor = line.parentElement;
        ancestor !== null && ancestor !== document.documentElement;
        ancestor = ancestor.parentElement
      )
        if (
          getComputedStyle(ancestor).overflowX !== "visible" &&
          ancestor.scrollWidth > ancestor.clientWidth + 1
        )
          clipped = true;
      return {
        clipped,
        left: box.left,
        right: box.right,
        text: helpers.text(line.textContent),
        visible:
          box.width > 0 && box.height > 0 && style.visibility !== "hidden",
        wraps: !["nowrap", "pre"].includes(style.whiteSpace),
      };
    });
  });
}
