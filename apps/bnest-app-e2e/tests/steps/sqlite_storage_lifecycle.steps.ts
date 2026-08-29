import { existsSync, writeFileSync } from "node:fs";
import path from "node:path";
import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import {
  cleanupStorageScenario,
  defaultDatabaseDirectory,
  isolatedStorageScenario,
  readPointer,
  runStorageCommand,
  runStorageMigrate,
  writePointer,
  writeThemeFixture,
  type StorageScenario,
} from "../support/sqlite-storage";

const { Given, Then, When } = createBdd();

let scenario: StorageScenario;
let result: { status: number; stdout: string; stderr: string };
let legacyDatabase = "";
let generation = "";

Given(
  "authoritative SQLite still uses the legacy configuration directory",
  ({ $testInfo }) => {
    scenario = isolatedStorageScenario($testInfo, "relocation");
    writeThemeFixture(scenario);
    const legacyDirectory = path.join(scenario.homeDirectory, ".config/bnest");
    writePointer(scenario, legacyDirectory);
    result = runStorageMigrate(scenario, ["--activate"]);
    expect(result.status).toBe(0);
    legacyDatabase = path.join(
      scenario.homeDirectory,
      ".config/bnest/bnest.sqlite3",
    );
    expect(existsSync(legacyDatabase)).toBe(true);
  },
);

When("managed storage relocation runs", () => {
  result = runStorageCommand(scenario, "bnest.storage.relocate", []);
});

Then(
  "the storage pointer resolves the production data directory atomically",
  () => {
    expect(result.status).toBe(0);
    const pointer = readPointer(scenario);
    expect(pointer?.["databaseDirectory"]).toBe(
      defaultDatabaseDirectory(scenario),
    );
    generation = String(pointer?.["databaseGeneration"] ?? "");
    expect(generation).not.toBe("");
  },
);

Then(
  "legacy SQLite files remain until the new database passes routed proof",
  () => {
    expect(existsSync(legacyDatabase)).toBe(true);
    expect(
      existsSync(
        path.join(defaultDatabaseDirectory(scenario), "bnest.sqlite3"),
      ),
    ).toBe(true);
    expect(result.stdout).toContain("relocation verified");
    cleanupStorageScenario(scenario);
  },
);

Given(
  "routed SQLite proof matches the authoritative database generation",
  ({ $testInfo }) => {
    scenario = isolatedStorageScenario($testInfo, "retirement");
    writeThemeFixture(scenario);
    writeFileSync(path.join(scenario.flatRoot, ".gitkeep"), "");
    writePointer(scenario, path.join(scenario.homeDirectory, ".config/bnest"));
    expect(runStorageMigrate(scenario, ["--activate"]).status).toBe(0);
    expect(
      runStorageCommand(scenario, "bnest.storage.relocate", []).status,
    ).toBe(0);
    const pointer = readPointer(scenario);
    generation = String(pointer?.["databaseGeneration"] ?? "");
    legacyDatabase = path.join(
      scenario.homeDirectory,
      ".config/bnest/bnest.sqlite3",
    );
    expect(generation).not.toBe("");
  },
);

When("managed legacy storage cleanup runs", () => {
  result = runStorageCommand(scenario, "bnest.storage.retire", [
    "--root",
    scenario.flatRoot,
    "--generation",
    generation,
  ]);
});

Then(
  "Bnest removes every verified flat-file source and legacy SQLite sidecar",
  () => {
    expect(result.status, result.stderr).toBe(0);
    expect(existsSync(legacyDatabase)).toBe(false);
    expect(existsSync(path.join(scenario.flatRoot, "users"))).toBe(false);
  },
);

Then("Bnest preserves storage configuration and tracked placeholders", () => {
  expect(readPointer(scenario)?.["flatFilesRetiredAt"]).toBeTruthy();
  expect(existsSync(path.join(scenario.flatRoot, ".gitkeep"))).toBe(true);
  cleanupStorageScenario(scenario);
});
