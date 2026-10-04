import {
  expect,
  type Locator,
  type Page,
  type TestInfo,
} from "@playwright/test";
import { login } from "./authentication";
import { focusDescriptor, traceFromNow } from "./backup-integrity-page";
import { ensureLiveSqlite, runLiveMix } from "./routed-rollout";
import { connected } from "./scheduled-backups";
import { isolatedTestIdentity, type TestIdentity } from "./test-identity";

// Journeys for the `Backup files` label of the Schedules & backups page. The ledger and the
// destination are seeded in the routed run's own isolated database and backup directory by
// `BnestApp.Test.BackupIntegrity` (the same fixtures the unit and integration drivers use),
// through the live mix; the facts a journey asserts on come back from that seed.

const schedulesRoute = "/admin/settings/schedules";
export const rowSelector = '[data-schedule-key="prod-sqlite-backup-daily"]';
// The fixtures' dates: the artifact this journey removes after the page was first read.
const removedDate = "2030-05-12";
export const resultTimeout = 15_000;

export type IntegrityFacts = {
  privateValues: string[];
  problems: string[];
  total: number;
};

// What the server holds of the routed run, read before and after a journey: every path under
// the destination with its kind and bytes, and every ledger row.
export type ServerWitness = {
  destination: { entries: Record<string, string>; present: boolean };
  ledger: Record<string, unknown>[];
};

export type IntegrityWorld = {
  facts?: IntegrityFacts;
  focusOnSave?: string;
  identity?: TestIdentity;
  labelHtml?: string;
  report?: string[];
  viewport?: { height: number; width: number };
  witness?: ServerWitness;
};

// The plan's States and Real Copy table, written out as the oracle (never the page's own
// wording function).
export function allPresentCopy(total: number): string {
  return `all ${total} retained backups are present`;
}

export function attentionCopy(problems: number, total: number): string {
  return problems === 1
    ? `1 of ${total} retained backups needs attention`
    : `${problems} of ${total} retained backups need attention`;
}

export const nothingToCheckCopy = "no verified backup to check yet";

export function expectedSummary(facts: IntegrityFacts): string {
  if (facts.total === 0) return nothingToCheckCopy;
  return facts.problems.length === 0
    ? allPresentCopy(facts.total)
    : attentionCopy(facts.problems.length, facts.total);
}

export async function prepareIntegrity(
  page: Page,
  world: IntegrityWorld,
  kind: string,
  testInfo: TestInfo,
): Promise<void> {
  for (const key of Object.keys(world))
    delete world[key as keyof IntegrityWorld];
  world.identity = isolatedTestIdentity(testInfo);
  await page.context().clearCookies();
  await login(page, world.identity.admin);
  ensureLiveSqlite();
  world.facts = liveJson<IntegrityFacts>(
    `BnestApp.Test.BackupIntegrity.seed_for_browser!("${kind}")`,
  );
}

export async function openedWhileAllPresent(
  page: Page,
  world: IntegrityWorld,
  testInfo: TestInfo,
): Promise<void> {
  await prepareIntegrity(page, world, "all_present", testInfo);
  await openSchedules(page, world);
  await expectSummary(page, required(world.facts));
}

export function removeExpectedArtifact(world: IntegrityWorld): void {
  world.facts = liveJson<IntegrityFacts>(
    `BnestApp.Test.BackupIntegrity.remove_for_browser!("${removedDate}")`,
  );
}

export async function openSchedules(
  page: Page,
  world: IntegrityWorld,
  size?: { height: number; width: number },
): Promise<void> {
  if (size !== undefined) {
    world.viewport = size;
    await page.setViewportSize(size);
  }
  await page.goto(schedulesRoute);
  await connected(page);
}

export async function saveForm(
  page: Page,
  world: IntegrityWorld,
  form: "backup folder" | "daily schedule",
): Promise<void> {
  await traceFromNow(page);
  const save = page.getByRole("button", {
    name:
      form === "daily schedule"
        ? "Save schedule"
        : "Save and create first backup",
  });
  // The administrator acts from the save control, so focus is on it when the form is submitted.
  // It is read here and not after the click: LiveView blurs the submitting control while the
  // save is in flight, so a read right after the click would race the reply.
  await save.focus();
  world.focusOnSave = await focusDescriptor(page);
  await save.click();
}

export async function readLabelHtml(
  page: Page,
  world: IntegrityWorld,
): Promise<void> {
  await openSchedules(page, world);
  const present = await findLabel(page).count();
  if (present === 0) {
    world.labelHtml = "";
    return;
  }
  await expectSummary(page, required(world.facts));
  world.labelHtml = await item(page).evaluate((element) => element.outerHTML);
}

// ---------------------------------------------------------------------------------------
// The label
// ---------------------------------------------------------------------------------------

export function findLabel(page: Page): Locator {
  return page
    .locator(rowSelector)
    .locator("dt")
    .filter({ hasText: /^Backup files$/u });
}

export function item(page: Page): Locator {
  return findLabel(page).locator("xpath=..");
}

// The first assertion of every Then about the label: it names the missing label itself.
export async function requireLabel(page: Page): Promise<Locator> {
  await expect(
    findLabel(page),
    "the Production database backup row carries a Backup files term",
  ).toHaveCount(1);
  return item(page);
}

export function summaryOf(label: Locator): Promise<string> {
  return label
    .locator("dd")
    .first()
    .evaluate((description) => {
      const copy = description.cloneNode(true) as Element;
      for (const extra of copy.querySelectorAll("ul, ol, [aria-hidden='true']"))
        extra.remove();
      return (copy.textContent ?? "").replaceAll(/\s+/gu, " ").trim();
    });
}

export async function problemLines(label: Locator): Promise<string[]> {
  const lines = await label.locator("dd li").allInnerTexts();
  return lines.map((line) => line.replaceAll(/\s+/gu, " ").trim());
}

export async function expectSummary(
  page: Page,
  facts: IntegrityFacts,
): Promise<void> {
  const label = await requireLabel(page);
  await expect
    .poll(() => summaryOf(label), { timeout: resultTimeout })
    .toBe(expectedSummary(facts));
}

export async function expectAllPresent(
  page: Page,
  world: IntegrityWorld,
): Promise<void> {
  const facts = required(world.facts);
  expect(facts.problems).toEqual([]);
  await expectSummary(page, facts);
}

export async function expectNoProblemDate(page: Page): Promise<void> {
  const label = await requireLabel(page);
  expect(await problemLines(label)).toEqual([]);
  expect(await label.locator("dd").first().innerText()).not.toMatch(
    /\d{4}-\d{2}-\d{2}/u,
  );
}

export async function expectAttentionCount(
  page: Page,
  world: IntegrityWorld,
): Promise<void> {
  const facts = required(world.facts);
  expect(facts.problems.length).toBeGreaterThan(0);
  await expectSummary(page, facts);
}

export async function expectProblemLines(
  page: Page,
  world: IntegrityWorld,
): Promise<void> {
  const label = await requireLabel(page);
  const facts = required(world.facts);
  await expect
    .poll(() => problemLines(label), { timeout: resultTimeout })
    .toEqual(facts.problems);
}

// The intact dates are counted as present: the total includes them and none is listed.
export async function expectIntactCounted(
  page: Page,
  world: IntegrityWorld,
): Promise<void> {
  const label = await requireLabel(page);
  const facts = required(world.facts);
  const intact = facts.total - facts.problems.length;
  expect(intact).toBeGreaterThan(0);
  await expect
    .poll(() => summaryOf(label), { timeout: resultTimeout })
    .toBe(attentionCopy(facts.problems.length, facts.total));
  expect(await problemLines(label)).toHaveLength(facts.problems.length);
}

export function liveJson<T>(expression: string): T {
  const marker = "integrity-json";
  const result = runLiveMix(
    `value = ${expression}; IO.puts("${marker}=" <> Jason.encode!(value))`,
  );
  expect(result.status, result.stderr).toBe(0);
  const line = result.stdout
    .split("\n")
    .find((entry) => entry.startsWith(`${marker}=`));
  if (line === undefined) throw new Error(`${expression} printed no result`);
  return JSON.parse(line.slice(marker.length + 1)) as T;
}

export function required<T>(value: T | undefined): T {
  if (value === undefined)
    throw new Error("a step ran before its Given prepared its state");
  return value;
}
