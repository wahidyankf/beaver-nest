import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import { existsSync, readdirSync, readFileSync } from "node:fs";
import path from "node:path";
import {
  cleanupStorageScenario,
  defaultDatabaseDirectory,
  defaultPointerPath,
  digestFile,
  inspectStorageMigration,
  isolatedStorageScenario,
  readDefaultPointer,
  readPointer,
  runStorageMigrate,
  seedMalformedBootstrap,
  writeThemeFixture,
  type StorageMigrationEvidence,
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
let migrationEvidence: StorageMigrationEvidence;

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
});

// Every storage.json file the run left under the scenario's HOME, found by walking the tree rather
// than by naming a path, so a pointer written anywhere else under HOME is seen as well.
function storagePointerFilesUnder(directory: string): string[] {
  return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const entryPath = path.join(directory, entry.name);
    if (entry.isDirectory()) return storagePointerFilesUnder(entryPath);
    return entry.name === "storage.json" ? [entryPath] : [];
  });
}

// The pointer file sits in the configuration home the scenario's HOME gives, outside the database
// directory it names. The Given showed no pointer before the run, so the only storage.json the walk
// finds under HOME is the one the product wrote, and it must be the one in the configuration home.
// The scenario's scratch directory is removed after this last step.
Then("Bnest keeps the storage pointer under the configuration home", () => {
  const pointer = readDefaultPointer(scenario);
  expect(pointer).toBeDefined();
  const configHome = path.join(scenario.homeDirectory, ".config/bnest");
  expect(storagePointerFilesUnder(scenario.homeDirectory)).toEqual([
    path.join(configHome, "storage.json"),
  ]);
  expect(
    String(pointer?.["databaseDirectory"]).startsWith(`${configHome}/`),
  ).toBe(false);
  expect(
    defaultPointerPath(scenario).startsWith(
      `${String(pointer?.["databaseDirectory"])}/`,
    ),
  ).toBe(false);
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
// through the app. The evidence is kept for the steps that follow.
Then(
  "the task reports accepted records with blocked=0 and exits 0, and every record reads back unchanged through the app",
  () => {
    expect(migrateResult.status, migrateResult.stderr).toBe(0);
    expect(migrateResult.stdout).toContain("accepted=2 blocked=0");
    migrationEvidence = inspectStorageMigration(scenario);
    expect(migrationEvidence.items).toHaveLength(2);
    expect(
      migrationEvidence.items.every((item) => item[3] === "accepted"),
    ).toBe(true);
    const sourceRecord = JSON.parse(
      readFileSync(fixtureFile, "utf8"),
    ) as Record<string, unknown>;
    expect(migrationEvidence.record).toEqual(sourceRecord);
  },
);

// The ledger lists the two theme sources in ascending path order.
Then("Bnest inventories records in deterministic path order", () => {
  expect(migrateResult.status, migrateResult.stderr).toBe(0);
  expect(migrationEvidence.items.map(([relativePath]) => relativePath)).toEqual(
    [
      "users/user-aaa-fixture/preferences/theme.json",
      "users/user-fixture-001/preferences/theme.json",
    ],
  );
});

// Each accepted item's source checksum is the digest of its source file as it stands, and its target
// checksum is a SHA-256 digest.
Then(
  "each accepted item has immutable source and target checksum evidence",
  () => {
    const checksum = /^[0-9a-f]{64}$/u;
    expect(migrationEvidence.items).toHaveLength(2);
    for (const [
      relativePath,
      sourceChecksum,
      targetChecksum,
    ] of migrationEvidence.items) {
      expect(sourceChecksum).toBe(
        digestFile(path.join(scenario.flatRoot, relativePath)),
      );
      expect(targetChecksum).toMatch(checksum);
    }
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

// The second run reports the remaining item accepted, and no record is written twice: each theme
// source holds one ledger row and one migrated record.
Then(
  "it exits 0, the counts show the remaining items accepted, and no record appears twice",
  () => {
    expect(secondMigrateResult.status, secondMigrateResult.stderr).toBe(0);
    expect(secondMigrateResult.stdout).toContain("accepted=2 blocked=0");
    expect(
      themeMigrationRows(scenario, "user-aaa-fixture").record,
    ).toHaveLength(1);
    expect(themeMigrationRows(scenario, "user-zzz-fixture").item).toHaveLength(
      1,
    );
    expect(
      themeMigrationRows(scenario, "user-zzz-fixture").record,
    ).toHaveLength(1);
    expect(inspectSchema(scenario).runs).toHaveLength(1);
  },
);

// The accepted item's ledger row and migrated record keep every column, timestamps included. The
// remaining item's recorded outcome is accepted.
Then(
  "accepted items are not rewritten, and remaining items continue from their recorded outcomes",
  () => {
    expect(themeMigrationRows(scenario, "user-aaa-fixture")).toEqual(
      firstRowsBeforeRetry,
    );
    const remaining = themeMigrationRows(scenario, "user-zzz-fixture");
    expect(remaining.item[0]).toContain("accepted");
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
