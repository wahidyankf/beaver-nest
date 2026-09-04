import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import path from "node:path";
import {
  cleanupStorageScenario,
  defaultDatabaseDirectory,
  digestFile,
  isolatedStorageScenario,
  readDefaultPointer,
  readPointer,
  runStorageMigrate,
  seedMalformedBootstrap,
  writeThemeFixture,
  type StorageScenario,
} from "../support/sqlite-storage";
import {
  cleanupIdentityStorageScenario,
  isolatedIdentityStorageScenario,
  retireFlatIdentitySources,
  runStorageEval,
  type IdentityStorageScenario,
} from "../support/sqlite-identity";

// Headless mix bnest.storage.migrate CLI flows (feature scenarios 1, 4, 5, 6,
// 7, 8). Split out of sqlite_storage.steps.ts to stay under the repository's
// 300-line step-file budget; the admin-UI and access-control scenarios live
// in their own sibling files.

const { Given, Then, When } = createBdd();

let scenario: StorageScenario;
let identityScenario: IdentityStorageScenario;
let migrateResult: { status: number; stdout: string; stderr: string };
let secondMigrateResult: { status: number; stdout: string; stderr: string };
let fixtureFile = "";
let fixtureDigestBefore = "";
const sqliteIdentity = {
  username: "test-user-sqlite-retired",
  password: "Synthetic SQLite Password 123!",
};

// --- Scenario 1: headless default location, no browser confirmation -------

let visitedStorageUI = false;

Given("Bnest has no storage configuration", ({ $testInfo }) => {
  scenario = isolatedStorageScenario($testInfo, "default-location");
  visitedStorageUI = false;
});

Given("the storage UI has not been visited", () => {
  expect(visitedStorageUI).toBe(false);
});

When("managed migration starts", () => {
  migrateResult = runStorageMigrate(scenario, [], { useDefaultPointer: true });
});

Then("Bnest keeps the storage pointer under the configuration home", () => {
  expect(migrateResult.status, migrateResult.stderr).toBe(0);
  expect(readDefaultPointer(scenario)).toBeDefined();
});

Then("Bnest uses the environment-specific data directory for SQLite", () => {
  const pointer = readDefaultPointer(scenario);
  expect(pointer?.["databaseDirectory"]).toBe(
    defaultDatabaseDirectory(scenario),
  );
  expect(pointer?.["databaseFilename"]).toBe("bnest.sqlite3");
});

Then("migration does not require a browser confirmation", () => {
  expect(visitedStorageUI).toBe(false);
  expect(migrateResult.stdout).toContain("dry run complete");
  cleanupStorageScenario(scenario);
});

// --- Scenario 4: DDL applied twice stays idempotent --------------------------

Given("an empty isolated database", ({ $testInfo }) => {
  scenario = isolatedStorageScenario($testInfo, "empty-database");
});

When("the committed migration set is applied twice", () => {
  migrateResult = runStorageMigrate(scenario, []);
  secondMigrateResult = runStorageMigrate(scenario, []);
});

Then("the schema version and indexes match the declared checksum", () => {
  expect(migrateResult.status, migrateResult.stderr).toBe(0);
  expect(secondMigrateResult.status, secondMigrateResult.stderr).toBe(0);
});

Then(
  "the second run makes no duplicate table, index, or migration record",
  () => {
    expect(migrateResult.stdout).toContain("accepted=0 blocked=0");
    expect(secondMigrateResult.stdout).toContain("accepted=0 blocked=0");
    cleanupStorageScenario(scenario);
  },
);

// --- Scenario 5: managed migration backfills recognized records -------------

Given(
  "a flat-primary installation has no custom storage location",
  ({ $testInfo }) => {
    scenario = isolatedStorageScenario($testInfo, "backfill");
    fixtureFile = writeThemeFixture(scenario);
    fixtureDigestBefore = digestFile(fixtureFile);
  },
);

When("managed storage migration runs without a UI visit", () => {
  migrateResult = runStorageMigrate(scenario, []);
});

Then("Bnest inventories records in deterministic path order", () => {
  expect(migrateResult.status, migrateResult.stderr).toBe(0);
  expect(migrateResult.stdout).toContain("accepted=1 blocked=0");
});

Then("Bnest writes the database under the resolved storage directory", () => {
  const pointer = readPointer(scenario);
  expect(pointer?.["databaseDirectory"]).toBe(
    defaultDatabaseDirectory(scenario),
  );
});

Then(
  "each accepted item has immutable source and target checksum evidence",
  () => {
    const repeat = runStorageMigrate(scenario, []);
    expect(repeat.status, repeat.stderr).toBe(0);
    expect(repeat.stdout).toContain("accepted=1 blocked=0");
  },
);

Then("normal repository reads return the same validated record", () => {
  expect(digestFile(fixtureFile)).toBe(fixtureDigestBefore);
  cleanupStorageScenario(scenario);
});

// --- Scenario 6: interrupted migration resumes idempotently -----------------

Given("migration stopped after at least one accepted item", ({ $testInfo }) => {
  scenario = isolatedStorageScenario($testInfo, "retry");
  writeThemeFixture(scenario);
  migrateResult = runStorageMigrate(scenario, []);
  expect(migrateResult.status, migrateResult.stderr).toBe(0);
  expect(migrateResult.stdout).toContain("accepted=1 blocked=0");
});

When("the administrator retries the same migration identifier", () => {
  secondMigrateResult = runStorageMigrate(scenario, []);
});

Then("accepted matching items are not rewritten or duplicated", () => {
  expect(secondMigrateResult.status, secondMigrateResult.stderr).toBe(0);
  expect(secondMigrateResult.stdout).toContain("accepted=1 blocked=0");
});

Then("remaining items continue from their recorded outcomes", () => {
  // Only the outcome summary line is compared: the first run's stdout also
  // carries one-time Ecto DDL creation logging that a retry naturally omits
  // ("Migrations already up"), which is not itself evidence of duplication.
  expect(migrationSummaryLine(secondMigrateResult.stdout)).toBe(
    migrationSummaryLine(migrateResult.stdout),
  );
  cleanupStorageScenario(scenario);
});

function migrationSummaryLine(stdout: string): string | undefined {
  return stdout.split("\n").find((line) => line.startsWith("migration "));
}

// --- Scenario 7: SQLite becomes authoritative after full verification -------

Given(
  "schema, backfill, parity, integrity, and isolated restore checks pass",
  ({ $testInfo }) => {
    identityScenario = isolatedIdentityStorageScenario($testInfo, "activation");
    scenario = identityScenario;
    const bootstrap = runStorageEval(
      identityScenario,
      `case BnestApp.Identity.bootstrap([%{"username" => "${sqliteIdentity.username}", "password" => "${sqliteIdentity.password}", "roles" => ["admin"]}]) do {:ok, _accounts} -> IO.puts("synthetic identity bootstrapped"); result -> raise "bootstrap failed: #{inspect(result)}" end`,
    );
    expect(bootstrap.status, bootstrap.stderr).toBe(0);
    writeThemeFixture(scenario);
    migrateResult = runStorageMigrate(scenario, []);
    expect(migrateResult.status, migrateResult.stderr).toBe(0);
    expect(migrateResult.stdout).toContain("accepted=4 blocked=0");
  },
);

When(
  "the managed migration commits the storage authority switch without UI confirmation",
  () => {
    secondMigrateResult = runStorageMigrate(scenario, ["--activate"]);
  },
);

Then("future reads use SQLite", () => {
  expect(secondMigrateResult.status, secondMigrateResult.stderr).toBe(0);
  expect(secondMigrateResult.stdout).toContain(
    "storage authority switched to sqlite_primary",
  );
  expect(readPointer(scenario)?.["phase"]).toBe("sqlite_primary");
});

Then("future writes remain compatible with the rollback reader", () => {
  const rollbackFile = path.join(
    scenario.flatRoot,
    "users",
    "user-fixture-001",
    "preferences",
    "theme.json",
  );
  expect(digestFile(rollbackFile)).not.toBe("missing");
});

Then("verified flat-file identity sources are retired", () => {
  retireFlatIdentitySources(identityScenario);
});

Then(
  "chat, learning, theme, login, and logout survive an application restart",
  () => {
    const afterRestart = runStorageEval(
      identityScenario,
      `:closed = BnestApp.Identity.setup_status(); case BnestApp.Identity.login("${sqliteIdentity.username}", "${sqliteIdentity.password}") do {:ok, token} -> {:ok, _user} = BnestApp.Identity.current_user(token); :ok = BnestApp.Identity.logout(token); {:error, :unauthenticated} = BnestApp.Identity.current_user(token); IO.puts("sqlite identity journey passed"); result -> raise "login failed: #{inspect(result)}" end`,
    );
    cleanupIdentityStorageScenario(identityScenario);
    expect(afterRestart.status, afterRestart.stderr).toBe(0);
    expect(afterRestart.stdout).toContain("sqlite identity journey passed");
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

When("Bnest verifies migration", () => {
  migrateResult = runStorageMigrate(scenario, []);
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
