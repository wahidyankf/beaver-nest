import type { Page } from "@playwright/test";

// What runs inside the Schedules page to watch its `Backup files` label change: the label is
// found by the markup the selected design fixes (the `dt` "Backup files" in the
// `prod-sqlite-backup-daily` schedule row, its parent as the item, its `dd` as the summary),
// and a MutationObserver keeps a trace of its text, of the focused element, and of the polite
// live region it lives in. Both functions run in the page, so each uses nothing outside its
// own body; they share what they install through `window`.

export type LabelTrace = {
  focus: string[];
  regionTexts: Record<string, string[]>;
  texts: string[];
};

export type PageHelpers = {
  describe(element: Element | null): string;
  item(): Element | null;
  region(item: Element): Element | null;
  summary(item: Element): string;
  text(value: string | null): string;
};

function installHelpers(): void {
  const rowSelector = '[data-schedule-key="prod-sqlite-backup-daily"]';
  const helpers: PageHelpers = {
    describe(element) {
      if (element === null || element === document.body) return "body";
      return [
        element.tagName.toLowerCase(),
        element.id,
        element.getAttribute("name") ?? "",
        helpers.text(element.textContent).slice(0, 40),
      ].join("|");
    },
    item() {
      for (const term of document.querySelectorAll(`${rowSelector} dt`))
        if (helpers.text(term.textContent) === "Backup files")
          return term.parentElement;
      return null;
    },
    region(item) {
      const description = item.querySelector("dd");
      for (const region of document.querySelectorAll(
        `${rowSelector} [aria-live="polite"]`,
      ))
        if (
          description !== null &&
          (region.contains(description) || description.contains(region))
        )
          return region;
      return null;
    },
    summary(item) {
      const description = item.querySelector("dd");
      if (description === null) return "";
      const copy = description.cloneNode(true) as Element;
      for (const extra of copy.querySelectorAll("ul, ol, [aria-hidden='true']"))
        extra.remove();
      return helpers.text(copy.textContent);
    },
    text(value) {
      return (value ?? "").replaceAll(/\s+/gu, " ").trim();
    },
  };
  (window as unknown as Record<string, unknown>)["__backupLabel"] = helpers;
}

function installObserver(): void {
  const helpers = (window as unknown as Record<string, PageHelpers>)[
    "__backupLabel"
  ] as PageHelpers;
  const trace: LabelTrace = { focus: [], regionTexts: {}, texts: [] };
  const regionIds = new WeakMap<Element, string>();
  const interesting =
    /checking|retained backup|could not be checked|no verified backup/u;
  const observer = new MutationObserver((records) => {
    for (const record of records)
      for (const node of [...record.removedNodes, ...record.addedNodes]) {
        const text = helpers.text(node.textContent);
        if (interesting.test(text)) trace.texts.push(text);
      }
    const item = helpers.item();
    if (item === null) return;
    const summary = helpers.summary(item);
    trace.texts.push(summary);
    trace.focus.push(helpers.describe(document.activeElement));
    const region = helpers.region(item);
    if (region === null) return;
    const id =
      regionIds.get(region) ??
      `region-${Object.keys(trace.regionTexts).length + 1}`;
    regionIds.set(region, id);
    (trace.regionTexts[id] ??= []).push(summary);
  });
  observer.observe(document, {
    characterData: true,
    childList: true,
    subtree: true,
  });
  (window as unknown as Record<string, unknown>)["__labelTrace"] = trace;
}

// Traces the label of every page the tab opens from now on, from its first parsed byte.
export async function traceBeforeNavigation(page: Page): Promise<void> {
  await page.addInitScript(installHelpers);
  await page.addInitScript(installObserver);
}

// Traces the label of the page that is open now.
export async function traceFromNow(page: Page): Promise<void> {
  await page.evaluate(installHelpers);
  await page.evaluate(installObserver);
}

export function readTrace(page: Page): Promise<LabelTrace> {
  return page.evaluate(
    () =>
      (window as unknown as Record<string, LabelTrace>)[
        "__labelTrace"
      ] as LabelTrace,
  );
}

export function focusDescriptor(page: Page): Promise<string> {
  return page.evaluate(
    () =>
      (window as unknown as Record<string, PageHelpers>)[
        "__backupLabel"
      ]?.describe(document.activeElement) ?? "unknown",
  );
}
