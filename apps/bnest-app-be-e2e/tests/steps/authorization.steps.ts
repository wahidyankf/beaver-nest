import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import {
  isolatedTestIdentity,
  type TestIdentity,
} from "../support/test-identity";
import { login } from "../support/authentication";

const { Given, Then, When } = createBdd();

let activeIdentity: TestIdentity;

Given(
  "an approved user has the roles {string} and {string}",
  async ({ page, $testInfo }, _firstRole: string, _secondRole: string) => {
    activeIdentity = isolatedTestIdentity($testInfo);
    await login(page, activeIdentity.admin);
  },
);

When("Bnest authorizes that user's own data operation", async ({ page }) => {
  await page.goto("/chat");
});

Then("the operation is allowed", async ({ page }) => {
  await expect(
    page.getByRole("heading", { name: "Beaver Nest" }),
  ).toBeVisible();
  await expect(page.getByLabel("Message")).toBeEnabled();
});

Then("an out-of-scope administration operation is denied", async ({ page }) => {
  expect((await page.request.get("/admin")).status()).toBe(404);
});

Given(
  "two approved users own separate Bnest data",
  async ({ page, $testInfo }) => {
    activeIdentity = isolatedTestIdentity($testInfo);
    await login(page, activeIdentity.admin);
  },
);

When(
  "the first user attempts the second user's data operation",
  async ({ page }) => {
    await page.goto(
      `/chat?owner=${encodeURIComponent(activeIdentity.child.username)}`,
    );
  },
);

Then(
  "Bnest denies the operation before repository access",
  async ({ page }) => {
    await expect(page).toHaveURL(/\/chat\?owner=/u);
    expect((await page.request.get("/users/other/chat")).status()).toBe(404);
  },
);
