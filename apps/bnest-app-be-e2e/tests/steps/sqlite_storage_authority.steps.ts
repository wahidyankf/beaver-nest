import { readFileSync } from "node:fs";
import path from "node:path";
import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import { readPointer, runStorageMigrate } from "../support/sqlite-storage";
import {
  cleanupIdentityStorageScenario,
  isolatedIdentityStorageScenario,
  restartJourney,
  retireFlatIdentitySources,
  seedFlatIdentityJourney,
  writeAfterSwitch,
  type FutureWriteEvidence,
  type IdentityStorageScenario,
  type JourneyEvidence,
} from "../support/sqlite-identity";

// The headless storage authority switch and the restart after it, split out of
// sqlite_storage_cli.steps.ts to stay under the 300-line step-file budget.
//
// @scenario specs/apps/bnest/app-be/behaviours/sqlite_storage.feature: The task switches storage to SQLite only when every check passes and the app then reads from it
// @scenario specs/apps/bnest/app-be/behaviours/sqlite_storage.feature: Chat, learning, theme, login and logout survive a restart after the switch

const { After, Given, Then, When } = createBdd();

type CommandResult = { status: number; stdout: string; stderr: string };

const sqliteIdentity = {
  username: "test-user-sqlite-retired",
  password: "Synthetic SQLite Password 123!",
};

let scenario: IdentityStorageScenario;
let ownedScenario: IdentityStorageScenario | undefined;
let journey: JourneyEvidence;
let activation: CommandResult;
let futureWrite: FutureWriteEvidence;

const changedTheme = "dark";

// The scenario's marked runtime pair is removed whether or not it reached its
// last step.
After(() => {
  const owned = ownedScenario;
  ownedScenario = undefined;
  if (owned) cleanupIdentityStorageScenario(owned);
});

Given(
  "schema, backfill, parity, integrity, and isolated restore checks pass",
  ({ $testInfo }) => {
    scenario = isolatedIdentityStorageScenario($testInfo, "activation");
    ownedScenario = scenario;
    journey = seedFlatIdentityJourney(scenario, sqliteIdentity);
    const backfill = runStorageMigrate(scenario, []);
    expect(backfill.status, backfill.stderr).toBe(0);
    expect(backfill.stdout).toContain("accepted=6 blocked=0");
  },
);

When(
  "the managed migration commits the storage authority switch without UI confirmation",
  () => {
    activation = runStorageMigrate(scenario, ["--activate"]);
  },
);

Then("future reads use SQLite", () => {
  expect(activation.status, activation.stderr).toBe(0);
  expect(activation.stdout).toContain(
    "storage authority switched to sqlite_primary",
  );
  expect(readPointer(scenario)?.["phase"]).toBe("sqlite_primary");
});

// After the switch, a login writes a session and the Preferences facade writes a theme, both into
// SQLite. The flat source keeps its bytes, and a rollback reader accepts the same records.
Then("future writes remain compatible with the rollback reader", () => {
  expect(journey.theme["theme"]).not.toBe(changedTheme);
  futureWrite = writeAfterSwitch(
    scenario,
    sqliteIdentity,
    journey.userId,
    changedTheme,
  );
  const flatSourceTheme = path.join(
    scenario.flatRoot,
    "users",
    journey.userId,
    "preferences",
    "theme.json",
  );
  expect(futureWrite.routed.theme["theme"]).toBe(changedTheme);
  expect(futureWrite.routed.session["userId"]).toBe(journey.userId);
  expect(futureWrite.sqlite).toEqual(futureWrite.routed);
  expect(futureWrite.flatBeforeRollback).toEqual({
    session: "missing",
    theme: "missing",
  });
  expect(JSON.parse(readFileSync(flatSourceTheme, "utf8"))).toEqual(
    journey.theme,
  );
  expect(futureWrite.rollback).toEqual(futureWrite.routed);
});

// Runs after the switch and before the restart, so the restart reads only SQLite.
When("verified flat-file identity sources are retired", () => {
  const retirement = retireFlatIdentitySources(scenario);
  const pointer = readPointer(scenario);
  expect(retirement.presentBefore).toHaveLength(3);
  expect(retirement.retired["flatFilesRetiredAt"]).toEqual(expect.any(String));
  expect(pointer?.["flatFilesRetiredAt"]).toBe(
    retirement.retired["flatFilesRetiredAt"],
  );
  expect(pointer?.["phase"]).toBe("sqlite_primary");
  expect(retirement.presentAfter).toEqual([]);
});

Then(
  "chat, learning, theme, login, and logout survive an application restart",
  () => {
    const restarted = restartJourney(scenario, sqliteIdentity);
    expect(restarted.setupStatus).toBe(":closed");
    expect(restarted.userId).toBe(journey.userId);
    expect(restarted.chat).toEqual(journey.chat);
    expect(restarted.learning).toEqual(journey.learning);
    expect(restarted.theme).toBe(journey.theme["theme"]);
    expect(restarted.afterLogout).toBe("{:error, :unauthenticated}");
  },
);
