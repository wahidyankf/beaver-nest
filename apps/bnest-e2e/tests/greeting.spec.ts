import { expect, test } from "@playwright/test";

test("shows the Beaver Nest greeting", async ({ page }) => {
  await page.goto("/");

  await expect(page.getByRole("heading", { name: "Hello, WW!" })).toBeVisible();
  await expect(page.getByText("Welcome to Beaver Nest.")).toBeVisible();
});
