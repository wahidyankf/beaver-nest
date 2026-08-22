import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";

const { Then, When } = createBdd();

When("a visitor opens {string}", async ({ page }, route: string) => {
  await page.goto(route);
});

Then(
  "the page displays the heading {string}",
  async ({ page }, heading: string) => {
    await expect(
      page.getByRole("heading", { exact: true, name: heading }),
    ).toBeVisible();
  },
);

Then("the page displays the text {string}", async ({ page }, text: string) => {
  await expect(page.getByText(text, { exact: true })).toBeVisible();
});
