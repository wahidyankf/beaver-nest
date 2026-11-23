import { mkdirSync, rmSync, writeFileSync } from "node:fs";
import path from "node:path";
import { expect, type Page } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import { currentInstance, instanceLifecycle } from "../support/active-instance";
import { login } from "../support/authentication";
import { instanceIdentities } from "../support/instance-identities";
import { runId } from "../support/routed-rollout-env";
import {
  accountPlan,
  runConfigPaths,
  scenarioLabel,
} from "../support/test-instance-lifecycle.mts";
import { deriveTestInstancePaths } from "../support/test-instance-paths.mts";

// Storage status, migration and folder-lock flows (feature scenarios 11-13).
// State that only the host can arrange — a malformed flat source, a repaired
// source — is written straight into the current flat-primary instance's flat
// root, the same files the CLI scenario seeds. The browser itself only logs
// in, opens `/storage` and presses the migration control.

const { Given, When, Then } = createBdd();

function flatInstanceRoot(): string {
  const runtimeRoot = process.env["BNEST_E2E_RUNTIME_ROOT"] ?? "";
  if (runtimeRoot === "") throw new Error("Missing marked E2E runtime root");
  const derived = deriveTestInstancePaths({
    flatRunRoot: runtimeRoot,
    sqliteRunRoot: runConfigPaths({
      runId,
      home: process.env["HOME"] ?? "",
    }).sqliteRunRoot,
    runId,
    instanceId: currentInstance().instanceId,
  });
  if (!derived.ok) {
    throw new Error(`the instance paths are invalid: ${derived.error}`);
  }
  return derived.paths.flatInstanceRoot;
}

function malformedSourcePath(): string {
  return path.join(
    flatInstanceRoot(),
    "system",
    "manifests",
    "broken-manifest.json",
  );
}

function plantMalformedSource(): void {
  mkdirSync(path.dirname(malformedSourcePath()), { recursive: true });
  writeFileSync(malformedSourcePath(), "{malformed");
}

function removeMalformedSource(): void {
  rmSync(malformedSourcePath(), { force: true });
}

async function openStorageAsAdmin(page: Page): Promise<void> {
  const admin = instanceIdentities().admin;
  await page.context().clearCookies();
  await login(page, admin);
  await page.goto("/storage");
  await expect(page.locator("[data-phx-main]")).toHaveClass(/phx-connected/u);
}

function statusSection(page: Page) {
  return page.locator("section[aria-label='Migration status']");
}

// --- Scenario 11: the storage status reads Not started, Blocked, or SQLite active ---

Given(
  "a storage installation in {string} state",
  async ({ $testInfo }, setup: string) => {
    if (setup === "blocked migration") {
      plantMalformedSource();
    } else if (setup === "active SQLite") {
      // The active state is read on the default instance, which is already
      // SQLite-primary: swap the scenario's flat-primary instance for one. The
      // When opens the page on the replacement.
      await instanceLifecycle().replace({
        label: `${scenarioLabel($testInfo.title)}-active`,
        phase: "sqlite_primary",
        accounts: accountPlan,
      });
    } else if (setup !== "fresh flat-primary") {
      throw new Error(`unknown storage setup: ${setup}`);
    }
  },
);

When("the administrator opens \\/storage", async ({ page }) => {
  await openStorageAsAdmin(page);
});

Then("the page reads {string}", async ({ page }, text: string) => {
  await expect(statusSection(page)).toContainText(text);
});

// --- Scenario 12: Move data and Retry migration start or retry the migration ---

Given(
  "a flat-primary installation with seeded family data and one malformed source",
  async ({ page }) => {
    plantMalformedSource();
    await openStorageAsAdmin(page);
  },
);

Then("the storage control reads {string}", async ({ page }, label: string) => {
  await expect(statusSection(page).getByRole("button")).toHaveText(label);
});

When("the administrator presses {string}", async ({ page }, label: string) => {
  await statusSection(page).getByRole("button", { name: label }).click();
});

Then(
  "the page reads {string} and the control reads {string}",
  async ({ page }, status: string, label: string) => {
    await expect(statusSection(page)).toContainText(status);
    await expect(statusSection(page).getByRole("button")).toHaveText(label);
  },
);

When(
  "the operator repairs the malformed source and the administrator presses {string}",
  async ({ page }, label: string) => {
    removeMalformedSource();
    await statusSection(page).getByRole("button", { name: label }).click();
  },
);

// --- Scenario 13: the folder is locked once migration has started ---

Given(
  "a flat-primary installation with a migration in progress",
  async ({ page }) => {
    plantMalformedSource();
    await openStorageAsAdmin(page);
    await statusSection(page)
      .getByRole("button", { name: "Move data" })
      .click();
    await expect(statusSection(page)).toContainText(
      "Status: Blocked — retry available",
    );
  },
);

Then(
  "the folder input and the Check folder button are disabled and Create database is not offered",
  async ({ page }) => {
    await expect(page.locator("#directory")).toBeDisabled();
    await expect(
      page.getByRole("button", { name: "Check folder" }),
    ).toBeDisabled();
    await expect(
      page.getByRole("button", { name: "Create database" }),
    ).toHaveCount(0);
  },
);
