import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import {
  closeBrowserContexts,
  currentInstance,
  instanceLifecycle,
} from "../support/active-instance";
import { accountPlan } from "../support/test-instance-lifecycle.mts";
import {
  instanceIdentities,
  type InstanceIdentity,
} from "../support/instance-identities";

// test_instances.feature: a replacement instance serves its own database, and an account of the instance it
// replaced is absent from it. Both are read back through production (the health route and the login form).

const { Then, When } = createBdd();

let previousAdmin: InstanceIdentity | undefined;

When(
  "the test replaces the current test instance with a fresh one",
  async ({ browser }) => {
    previousAdmin = instanceIdentities().admin;
    // Quiesce first: no browser may hold a socket into the instance that is about to be deleted.
    await closeBrowserContexts(browser);
    await instanceLifecycle().replace({
      label: "replacement-test-instance",
      phase: "sqlite_primary",
      accounts: accountPlan,
    });
  },
);

Then(
  "Bnest reports the fresh instance's storage generation",
  async ({ request }) => {
    const response = await request.get("/health/ready");
    expect(response.status()).toBe(200);
    const body = (await response.json()) as { storageGeneration?: unknown };
    expect(body.storageGeneration).toBe(currentInstance().generation);
  },
);

Then(
  "the previous instance's admin account cannot log in",
  async ({ browser }) => {
    if (previousAdmin === undefined) {
      throw new Error("the replacement step must run before this check");
    }
    const context = await browser.newContext();
    try {
      const page = await context.newPage();
      await page.goto("/login");
      await expect(page.locator("[data-phx-main]")).toHaveClass(/phx-connected/u);
      await page.getByLabel("Username").fill(previousAdmin.username);
      await page.getByLabel("Password").fill(previousAdmin.password);
      await page.getByRole("button", { name: "Log in" }).click();
      await expect(page.getByRole("alert")).toHaveText(
        "Username or password is not valid.",
      );
      await expect(page).toHaveURL(/\/login/u);
    } finally {
      await context.close();
    }
  },
);
