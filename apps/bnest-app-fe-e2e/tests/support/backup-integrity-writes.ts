import { expect, type Page } from "@playwright/test";
import {
  expectProblemLines,
  liveJson,
  openSchedules,
  required,
  type IntegrityWorld,
  type ServerWitness,
} from "./backup-integrity-label";
import { connected } from "./scheduled-backups";

// Rendering the label never writes: the routed run's destination and ledger are read from the
// server's own filesystem and database, by the live mix, before the page is opened and again
// by each Then once it has been opened and reloaded.

const unknownFile = "unknown-note.txt";

function readWitness(): ServerWitness {
  return liveJson<ServerWitness>(
    "BnestApp.Test.BackupIntegrity.witness_for_browser!()",
  );
}

export async function openAndReload(
  page: Page,
  world: IntegrityWorld,
): Promise<void> {
  world.witness = readWitness();
  await openSchedules(page, world);
  await page.reload();
  await connected(page);
  // The check has finished once the label names the missing artifact, so a write it made
  // would already be on the server.
  await expectProblemLines(page, world);
}

export async function expectDestinationUnchanged(
  page: Page,
  world: IntegrityWorld,
): Promise<void> {
  const facts = required(world.facts);
  const before = required(world.witness).destination;
  // The check ran over a destination with a problem and an unknown file, so an unchanged
  // destination is a measured result and not the absence of a check.
  expect(facts.problems.length).toBeGreaterThan(0);
  await expectProblemLines(page, world);
  expect(
    Object.keys(before.entries).some((entry) => entry.endsWith(unknownFile)),
    "the destination holds the unknown file",
  ).toBe(true);
  expect(readWitness().destination).toEqual(before);
}

export function expectLedgerUnchanged(world: IntegrityWorld): void {
  const before = required(world.witness).ledger;
  expect(before.length, "the ledger holds the seeded runs").toBeGreaterThan(0);
  expect(readWitness().ledger).toEqual(before);
}
