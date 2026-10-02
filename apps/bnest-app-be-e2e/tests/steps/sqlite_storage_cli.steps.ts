import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import { existsSync, readFileSync } from "node:fs";
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
  type StorageScenario,
  type StorageMigrationEvidence,
} from "../support/sqlite-storage";
import {
  declaredMigrationSet,
  inspectSchema,
  interruptRecordWrite,
  resumeRecordWrites,
  themeMigrationRows,
  type MigrationRows,
  type SchemaEvidence,
} from "../support/sqlite-migration-evidence";

// Headless mix bnest.storage.migrate CLI flows (feature scenarios 1, 4, 5, 6,
// 8). Split out of sqlite_storage.steps.ts to stay under the repository's
// 300-line step-file budget; the authority switch (scenario 7), admin-UI, and
// access-control scenarios live in their own sibling files.

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

When("managed migration starts", () => {
  migrateResult = runStorageMigrate(scenario, [], { useDefaultPointer: true });
});

// The pointer is in the configuration home the scenario's HOME gives, outside the database
// directory it names.
Then("Bnest keeps the storage pointer under the configuration home", () => {
  const pointer = readDefaultPointer(scenario);
  expect(pointer).toBeDefined();
  expect(path.dirname(defaultPointerPath(scenario))).toBe(
    path.join(scenario.homeDirectory, ".config/bnest"),
  );
  expect(
    defaultPointerPath(scenario).startsWith(
      `${String(pointer?.["databaseDirectory"])}/`,
    ),
  ).toBe(false);
});

Then("Bnest uses the environment-specific data directory for SQLite", () => {
  const pointer = readDefaultPointer(scenario);
  expect(pointer?.["databaseDirectory"]).toBe(
    defaultDatabaseDirectory(scenario),
  );
  expect(pointer?.["databaseFilename"]).toBe("bnest.sqlite3");
  expect(
    existsSync(path.join(defaultDatabaseDirectory(scenario), "bnest.sqlite3")),
  ).toBe(true);
});

// The command finished on its own, and the browser sent nothing to the storage UI while it
// ran.
Then("migration does not require a browser confirmation", () => {
  expect(migrateResult.status, migrateResult.stderr).toBe(0);
  expect(migrateResult.stdout).toContain("dry run complete");
  expect(storageUIRequests).toEqual([]);
  cleanupStorageScenario(scenario);
});

// --- Scenario 4: DDL applied twice stays idempotent --------------------------

Given("an empty isolated database", ({ $testInfo }) => {
  scenario = isolatedStorageScenario($testInfo, "empty-database");
});

let schemaAfterFirstRun: SchemaEvidence;
let schemaAfterSecondRun: SchemaEvidence;

// The schema is read from the database after each run.
When("the committed migration set is applied twice", () => {
  migrateResult = runStorageMigrate(scenario, []);
  schemaAfterFirstRun = inspectSchema(scenario);
  secondMigrateResult = runStorageMigrate(scenario, []);
  schemaAfterSecondRun = inspectSchema(scenario);
});

// The run's DDL checksum is the committed migration files' digest, computed here, the
// applied versions are their versions, and the indexes are exactly the ones they create.
Then("the schema version and indexes match the declared checksum", () => {
  expect(migrateResult.status, migrateResult.stderr).toBe(0);
  const declared = declaredMigrationSet();
  expect(schemaAfterFirstRun.runs).toEqual([
    ["flat-files-v1-to-sqlite-v1", declared.checksum],
  ]);
  expect(schemaAfterFirstRun.versions).toEqual(declared.versions);
  expect(
    schemaAfterFirstRun.objects
      .filter(([type, , sql]) => type === "index" && sql !== null)
      .map(([, name]) => name)
      .toSorted(),
  ).toEqual(declared.indexes);
});

Then(
  "the second run makes no duplicate table, index, or migration record",
  () => {
    expect(secondMigrateResult.status, secondMigrateResult.stderr).toBe(0);
    expect(schemaAfterSecondRun).toEqual(schemaAfterFirstRun);
    expect(schemaAfterSecondRun.runs).toHaveLength(1);
    expect(new Set(schemaAfterSecondRun.versions).size).toBe(
      schemaAfterSecondRun.versions.length,
    );
    cleanupStorageScenario(scenario);
  },
);

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

Then("Bnest inventories records in deterministic path order", () => {
  expect(migrateResult.status, migrateResult.stderr).toBe(0);
  migrationEvidence = inspectStorageMigration(scenario);
  const inventory = migrationEvidence.items.map(
    ([relativePath]) => relativePath,
  );
  expect(inventory).toEqual(inventory.toSorted());
});

Then("Bnest writes the database under the resolved storage directory", () => {
  const pointer = readPointer(scenario);
  expect(pointer?.["databaseDirectory"]).toBe(
    defaultDatabaseDirectory(scenario),
  );
});

Then("every recognized valid item is accepted without a block", () => {
  expect(migrateResult.status, migrateResult.stderr).toBe(0);
  expect(migrateResult.stdout).toContain("accepted=2 blocked=0");
  expect(migrationEvidence.items).toHaveLength(2);
  expect(migrationEvidence.items.every((item) => item[3] === "accepted")).toBe(
    true,
  );
});

Then(
  "each accepted item has immutable source and target checksum evidence",
  () => {
    const checksum = /^[0-9a-f]{64}$/u;
    expect(
      migrationEvidence.items.every(
        ([, sourceChecksum, targetChecksum]) =>
          checksum.test(sourceChecksum) && checksum.test(targetChecksum),
      ),
    ).toBe(true);
  },
);

Then("normal repository reads return the same validated record", () => {
  const sourceRecord = JSON.parse(readFileSync(fixtureFile, "utf8")) as Record<
    string,
    unknown
  >;
  expect(migrationEvidence.record).toEqual(sourceRecord);
  cleanupStorageScenario(scenario);
});

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

When("the administrator retries the same migration identifier", () => {
  secondMigrateResult = runStorageMigrate(scenario, []);
});

// The accepted item's ledger row and migrated record keep every column, timestamps included.
Then("accepted matching items are not rewritten or duplicated", () => {
  expect(secondMigrateResult.status, secondMigrateResult.stderr).toBe(0);
  expect(themeMigrationRows(scenario, "user-aaa-fixture")).toEqual(
    firstRowsBeforeRetry,
  );
  expect(inspectSchema(scenario).runs).toHaveLength(1);
});

Then("remaining items continue from their recorded outcomes", () => {
  const remaining = themeMigrationRows(scenario, "user-zzz-fixture");
  expect(remaining.item).toHaveLength(1);
  expect(remaining.item[0]).toContain("accepted");
  expect(remaining.record).toHaveLength(1);
  expect(secondMigrateResult.stdout).toContain("accepted=2 blocked=0");
  cleanupStorageScenario(scenario);
});

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
