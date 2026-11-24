import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import {
  cleanupStorageScenario,
  defaultDatabaseDirectory,
  digestFile,
  inspectStorageMigration,
  isolatedStorageScenario,
  readDefaultPointer,
  readPointer,
  runStorageMigrate,
  seedMalformedBootstrap,
  writeThemeFixture,
  type StorageScenario,
} from "../support/sqlite-storage";
import {
  inspectSchema,
  interruptRecordWrite,
  resumeRecordWrites,
  themeMigrationRows,
  type MigrationRows,
} from "../support/sqlite-migration-evidence";

// Headless mix bnest.storage.migrate CLI flows (feature scenarios 1, 5, 6,
// and 8). Split out of sqlite_storage.steps.ts to stay under the repository's
// 300-line step-file budget; the authority switch (scenario 7), admin-UI, and
// access-control scenarios live in their own sibling files.
//
// @scenario specs/apps/bnest/app-be/behaviours/sqlite_storage.feature: The storage migration task uses the default private data folder with no browser visit
// @scenario specs/apps/bnest/app-be/behaviours/sqlite_storage.feature: The storage migration task moves every recognized record and reports none blocked
// @scenario specs/apps/bnest/app-be/behaviours/sqlite_storage.feature: Running the storage migration task again after an interruption finishes it without duplicates
// @scenario specs/apps/bnest/app-be/behaviours/sqlite_storage.feature: Invalid or changed source blocks cutover without data loss

const { Given, Then, When } = createBdd();

let scenario: StorageScenario;
let migrateResult: { status: number; stdout: string; stderr: string };
let secondMigrateResult: { status: number; stdout: string; stderr: string };
let fixtureFile = "";
let fixtureDigestBefore = "";

// --- Scenario 1: headless default location, no browser confirmation -------

// Every request the scenario's browser sends to the storage UI, from the Given on.
const storageUIRequests: string[] = [];

Given("Bnest has no storage configuration", ({ $testInfo }) => {
  scenario = isolatedStorageScenario($testInfo, "default-location");
  expect(readDefaultPointer(scenario)).toBeUndefined();
  expect(readPointer(scenario)).toBeUndefined();
});

Given("the storage UI has not been visited", ({ page }) => {
  storageUIRequests.length = 0;
  page.context().on("request", (request) => {
    if (new URL(request.url()).pathname.startsWith("/storage"))
      storageUIRequests.push(request.url());
  });
  expect(storageUIRequests).toEqual([]);
});

When("the operator runs `mix bnest.storage.migrate`", () => {
  migrateResult = runStorageMigrate(scenario, [], { useDefaultPointer: true });
});

// The command finished on its own, the database sits in the environment-specific data directory,
// and the browser sent nothing to the storage UI while it ran.
Then("it exits 0 and the database file is in the default data folder", () => {
  expect(migrateResult.status, migrateResult.stderr).toBe(0);
  expect(migrateResult.stdout).toContain("dry run complete");
  const pointer = readDefaultPointer(scenario);
  expect(pointer?.["databaseDirectory"]).toBe(
    defaultDatabaseDirectory(scenario),
  );
  expect(pointer?.["databaseFilename"]).toBe("bnest.sqlite3");
  expect(
    existsSync(path.join(defaultDatabaseDirectory(scenario), "bnest.sqlite3")),
  ).toBe(true);
  expect(storageUIRequests).toEqual([]);
  cleanupStorageScenario(scenario);
});

// --- Scenario 5: managed migration backfills recognized records -------------

Given(
  "a flat-primary installation has no custom storage location",
  ({ $testInfo }) => {
    scenario = isolatedStorageScenario($testInfo, "backfill");
    fixtureFile = writeThemeFixture(scenario);
    writeThemeFixture(scenario, "user-aaa-fixture");
    fixtureDigestBefore = digestFile(fixtureFile);
  },
);

When("managed storage migration runs without a UI visit", () => {
  migrateResult = runStorageMigrate(scenario, []);
});

// The task's line names the accepted count with nothing blocked, and the record reads back unchanged
// through the app. Each accepted item's source and target checksums are read from the same evidence.
Then(
  "the task reports accepted records with blocked=0 and exits 0, and every record reads back unchanged through the app",
  () => {
    expect(migrateResult.status, migrateResult.stderr).toBe(0);
    expect(migrateResult.stdout).toContain("accepted=2 blocked=0");
    const evidence = inspectStorageMigration(scenario);
    expect(evidence.items).toHaveLength(2);
    expect(evidence.items.every((item) => item[3] === "accepted")).toBe(true);
    const sourceRecord = JSON.parse(
      readFileSync(fixtureFile, "utf8"),
    ) as Record<string, unknown>;
    expect(evidence.record).toEqual(sourceRecord);
    cleanupStorageScenario(scenario);
  },
);

// --- Scenario 6: interrupted migration resumes idempotently -----------------

let firstRowsBeforeRetry: MigrationRows;

// Two theme sources; the run fails at the second one's record write, as a killed migration
// would, after the path-first source was accepted. The failure is then cleared.
Given("migration stopped after at least one accepted item", ({ $testInfo }) => {
  scenario = isolatedStorageScenario($testInfo, "retry");
  writeThemeFixture(scenario, "user-aaa-fixture");
  writeThemeFixture(scenario, "user-zzz-fixture");
  interruptRecordWrite(scenario, "user-zzz-fixture");
  migrateResult = runStorageMigrate(scenario, []);
  expect(migrateResult.status).not.toBe(0);
  expect(migrateResult.stderr).toContain("interrupted migration");
  resumeRecordWrites(scenario);
  firstRowsBeforeRetry = themeMigrationRows(scenario, "user-aaa-fixture");
  expect(firstRowsBeforeRetry.item).toHaveLength(1);
  expect(themeMigrationRows(scenario, "user-zzz-fixture").item).toEqual([]);
});

When("the operator runs the same task again", () => {
  secondMigrateResult = runStorageMigrate(scenario, []);
});

// The accepted item's ledger row and migrated record keep every column, timestamps included. The
// remaining item is accepted once, and no record appears twice.
Then(
  "it exits 0, the counts show the remaining items accepted, and no record appears twice",
  () => {
    expect(secondMigrateResult.status, secondMigrateResult.stderr).toBe(0);
    expect(themeMigrationRows(scenario, "user-aaa-fixture")).toEqual(
      firstRowsBeforeRetry,
    );
    expect(inspectSchema(scenario).runs).toHaveLength(1);
    const remaining = themeMigrationRows(scenario, "user-zzz-fixture");
    expect(remaining.item).toHaveLength(1);
    expect(remaining.item[0]).toContain("accepted");
    expect(remaining.record).toHaveLength(1);
    expect(secondMigrateResult.stdout).toContain("accepted=2 blocked=0");
    cleanupStorageScenario(scenario);
  },
);

// --- Scenario 8: malformed/changed source blocks cutover --------------------

Given(
  "a source is malformed, unsupported, or changes after inventory",
  ({ $testInfo }) => {
    scenario = isolatedStorageScenario($testInfo, "blocked");
    fixtureFile = seedMalformedBootstrap(scenario);
    fixtureDigestBefore = digestFile(fixtureFile);
  },
);

// Verification asks for the authority switch, so only the refusal keeps the flat phase.
When("Bnest verifies migration", () => {
  migrateResult = runStorageMigrate(scenario, ["--activate"]);
});

Then("SQLite does not become authoritative", () => {
  expect(migrateResult.status).not.toBe(0);
  expect(readPointer(scenario)?.["phase"]).toBe("flat_primary");
});

Then("the source and current flat-primary service remain unchanged", () => {
  expect(digestFile(fixtureFile)).toBe(fixtureDigestBefore);
});

Then("the administrator sees a value-free retry category", () => {
  expect(migrateResult.stderr).toContain(
    "migration blocked: resolve the malformed or changed source, then retry with the same identifier",
  );
  expect(migrateResult.stderr).not.toContain(scenario.flatRoot);
  cleanupStorageScenario(scenario);
});
