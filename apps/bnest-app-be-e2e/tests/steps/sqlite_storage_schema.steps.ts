import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import {
  isolatedStorageScenario,
  readPointer,
  runStorageCommand,
  type StorageScenario,
} from "../support/sqlite-storage";
import {
  declaredMigrationSet,
  inspectSchema,
} from "../support/sqlite-migration-evidence";

// Versioned SQLite schema scenario: the committed migration set is applied twice to an empty isolated database, and the
// schema, its indexes and its migration records are compared with the committed migration files.
//
// @scenario specs/apps/bnest/app-be/behaviours/sqlite_storage.feature: Versioned SQLite migration creates the expected schema once

const { Given, When, Then } = createBdd();

let scenario: StorageScenario;

Given("an empty isolated database", ({ $testInfo }) => {
  scenario = isolatedStorageScenario($testInfo, "schema-checksum");
  expect(readPointer(scenario)).toBeUndefined();
});

When("the committed migration set is applied twice", () => {
  const result = runStorageCommand(scenario, "run", [
    "-e",
    `
      alias BnestApp.Storage
      :ok = BnestApp.Storage.Adapters.SqliteCoordinator.ensure_started!()
      Storage.adapter(:database_lifecycle).migrate_schema!()
      Storage.adapter(:database_lifecycle).migrate_schema!()
      IO.puts("applied-twice")
    `,
  ]);
  expect(result.status, result.stderr).toBe(0);
  expect(result.stdout).toContain("applied-twice");
});

Then("the schema version and indexes match the declared checksum", () => {
  const schema = inspectSchema(scenario);
  const declared = declaredMigrationSet();

  expect([...schema.versions]).toEqual(declared.versions);
  const indexes = schema.objects
    .filter(([type, name]) => type === "index" && !name.startsWith("sqlite_"))
    .map(([, name]) => name)
    .toSorted();
  expect(indexes).toEqual(declared.indexes);
});

Then(
  "the second run makes no duplicate table, index, or migration record",
  () => {
    const schema = inspectSchema(scenario);
    const names = schema.objects.map(([type, name]) => `${type}:${name}`);
    expect(new Set(names).size).toBe(names.length);
    expect(new Set(schema.versions).size).toBe(schema.versions.length);
    expect(schema.versions).toEqual(declaredMigrationSet().versions);
  },
);
