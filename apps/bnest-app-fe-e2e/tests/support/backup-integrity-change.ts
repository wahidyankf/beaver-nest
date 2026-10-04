import { expect, type Page } from "@playwright/test";
import {
  liveJson,
  problemLines,
  required,
  requireLabel,
  resultTimeout,
  expectedSummary,
  expectSummary,
  summaryOf,
  type IntegrityWorld,
} from "./backup-integrity-label";
import { focusDescriptor, readTrace } from "./backup-integrity-page";

// The label as it changes after a save, and what it discloses.

export async function expectCheckingThenResult(
  page: Page,
  world: IntegrityWorld,
): Promise<void> {
  await requireLabel(page);
  const result = expectedSummary(required(world.facts));
  await expect
    .poll(async () => resultIndex(await readTrace(page), result), {
      timeout: resultTimeout,
    })
    .toBeGreaterThan(-1);
  const trace = await readTrace(page);
  const checking = trace.texts.findIndex((text) => /\bchecking\b/u.test(text));
  expect(checking, "the label read checking before the result").toBeGreaterThan(
    -1,
  );
  expect(checking).toBeLessThan(resultIndex(trace, result));
}

function resultIndex(trace: { texts: string[] }, result: string): number {
  return trace.texts.findIndex((text) => text.includes(result));
}

export async function expectOneNeedsAttention(
  page: Page,
  world: IntegrityWorld,
): Promise<void> {
  const facts = required(world.facts);
  expect(facts.problems).toHaveLength(1);
  await expectSummary(page, facts);
}

export async function expectFocusStays(
  page: Page,
  world: IntegrityWorld,
): Promise<void> {
  const stays = required(world.focusOnSave);
  expect(stays).not.toBe("body");
  // LiveView blurs the submitting control while a form is in flight and focuses it again from
  // the reply, for every form of the app: the control must be back in focus once the save has
  // settled, and while the label changed focus was on it or nowhere, never on anything else.
  await expect
    .poll(() => focusDescriptor(page), { timeout: resultTimeout })
    .toBe(stays);
  const trace = await readTrace(page);
  expect(
    trace.focus.filter((held) => held !== stays && held !== "body"),
  ).toEqual([]);
}

// ---------------------------------------------------------------------------------------
// What the page discloses
// ---------------------------------------------------------------------------------------

export function expectPrivateFree(world: IntegrityWorld): void {
  const html = required(world.labelHtml);
  const facts = required(world.facts);
  expect(html, "the Backup files label was rendered").toContain("Backup files");
  for (const value of facts.privateValues) expect(html).not.toContain(value);
  expect(html).not.toMatch(/[0-9a-f]{64}/iu);
  expect(html).not.toMatch(/(?:^|[\s"'=(])\/(?:[\w.~-]+\/)+[\w.~-]+/u);
}

export function readReport(world: IntegrityWorld): void {
  world.report = liveJson<{ lines: string[] }>(
    "BnestApp.Test.BackupIntegrity.browser_report!()",
  ).lines;
}

export async function expectMatchesReport(
  page: Page,
  world: IntegrityWorld,
): Promise<void> {
  const label = await requireLabel(page);
  const report = required(world.report);
  const summary = await summaryOf(label);
  expect(report.length).toBeGreaterThan(1);
  expect(report[0]).toBe(`Backup files: ${summary}`);
  expect(report.slice(1)).toEqual(await problemLines(label));
}
