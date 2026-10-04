import { expect, type Page } from "@playwright/test";
import {
  expectSummary,
  problemLines,
  required,
  requireLabel,
  type IntegrityWorld,
} from "./backup-integrity-label";

// The label over a ledger that holds no verified run. The routed run's ledger is emptied of
// verified runs by the Given's seed (`BnestApp.Test.BackupIntegrity.seed_for_browser!`, which
// every label journey starts with), leaving one failed attempt: a failed run is not a backup.

export async function expectNothingToCheck(
  page: Page,
  world: IntegrityWorld,
): Promise<void> {
  const facts = required(world.facts);
  expect(facts.total, "the seeded ledger holds no verified run").toBe(0);
  await expectSummary(page, facts);
  expect(await problemLines(await requireLabel(page))).toEqual([]);
}

// Read once the label has settled on its result (`expectNothingToCheck`), so a claim of
// presence cannot still be on its way.
export async function expectNoPresentClaim(page: Page): Promise<void> {
  const label = await requireLabel(page);
  const description = await label.locator("dd").first().innerText();
  expect(description).not.toMatch(/present/iu);
  expect(description).not.toMatch(/\d{4}-\d{2}-\d{2}/u);
}
