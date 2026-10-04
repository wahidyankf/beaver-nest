import { expect, type Page } from "@playwright/test";
import {
  expectedSummary,
  openSchedules,
  problemLines,
  required,
  requireLabel,
  resultTimeout,
  rowSelector,
  type IntegrityWorld,
} from "./backup-integrity-label";
import { readTrace, traceBeforeNavigation } from "./backup-integrity-page";
import {
  pageOverflow,
  problemLayouts,
  readingOrder,
  walkTabStops,
} from "./backup-integrity-trace";

// The label at each supported width, and for a keyboard and screen reader user.

export async function openWithTrace(
  page: Page,
  world: IntegrityWorld,
): Promise<void> {
  await traceBeforeNavigation(page);
  await openSchedules(page, world);
}

async function problemsRendered(
  page: Page,
  world: IntegrityWorld,
): Promise<void> {
  const label = await requireLabel(page);
  const facts = required(world.facts);
  await expect
    .poll(() => problemLines(label), { timeout: resultTimeout })
    .toEqual(facts.problems);
}

export async function expectNoHorizontalScroll(
  page: Page,
  world: IntegrityWorld,
): Promise<void> {
  await problemsRendered(page, world);
  expect(await pageOverflow(page)).toBeLessThanOrEqual(
    required(world.viewport).width,
  );
}

export async function expectProblemLinesWhole(
  page: Page,
  world: IntegrityWorld,
): Promise<void> {
  await problemsRendered(page, world);
  const { width } = required(world.viewport);
  const layouts = await problemLayouts(page);
  expect(layouts.map((layout) => layout.text)).toEqual(
    required(world.facts).problems,
  );
  for (const layout of layouts) {
    expect(layout.visible, `${layout.text} is visible`).toBe(true);
    expect(layout.clipped, `${layout.text} is not clipped`).toBe(false);
    expect(layout.wraps, `${layout.text} may wrap`).toBe(true);
    expect(layout.left).toBeGreaterThanOrEqual(0);
    expect(layout.right).toBeLessThanOrEqual(width);
  }
}

export async function expectProblemsInText(
  page: Page,
  world: IntegrityWorld,
): Promise<void> {
  await problemsRendered(page, world);
  for (const layout of await problemLayouts(page))
    expect(layout.text).toMatch(
      /^\d{4}-\d{2}-\d{2}: file (?:missing|changed)$/u,
    );
}

// ---------------------------------------------------------------------------------------
// Keyboard and screen reader
// ---------------------------------------------------------------------------------------

export async function expectAnnouncedInPlace(
  page: Page,
  world: IntegrityWorld,
): Promise<void> {
  const label = await requireLabel(page);
  const facts = required(world.facts);
  await expect(label.getByRole("term")).toHaveText("Backup files");
  await expect(label.getByRole("definition").first()).toContainText(
    expectedSummary(facts),
    {
      timeout: resultTimeout,
    },
  );
  const order = await readingOrder(page);
  expect(order.afterLastResult, "the label follows the Last result term").toBe(
    true,
  );
  expect(order.beforeForms, "the label precedes the forms").toBe(true);
}

// Opens the page with the label traced from its first byte; the Thens judge what it read.
export function walkPage(page: Page, world: IntegrityWorld): Promise<void> {
  return openWithTrace(page, world);
}

export async function expectFocusOrderUnchanged(page: Page): Promise<void> {
  await requireLabel(page);
  const walk = await walkTabStops(page);
  expect(walk.domOrder.length).toBeGreaterThanOrEqual(4);
  expect(walk.insideLabel, "no control of the label takes focus").toEqual([]);
  expect(walk.stops).toEqual(walk.domOrder);
}

export async function expectPoliteAnnouncement(page: Page): Promise<void> {
  await requireLabel(page);
  await expect(
    page.locator(
      `${rowSelector} [aria-live="assertive"], ${rowSelector} [role="alert"]`,
    ),
  ).toHaveCount(0);
  const trace = await readTrace(page);
  const announced = Object.values(trace.regionTexts).some(
    (texts) =>
      texts.some((text) => /\bchecking\b/u.test(text)) &&
      texts.some(
        (text) => /retained backup/u.test(text) && !/\bchecking\b/u.test(text),
      ),
  );
  expect(
    announced,
    "checking changed to the result inside one polite region",
  ).toBe(true);
  // Nothing took focus while the label changed: the page was never focused on a control.
  expect([...new Set(trace.focus)]).toEqual(["body"]);
}
