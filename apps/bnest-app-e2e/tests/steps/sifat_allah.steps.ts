import { expect, type Page } from "@playwright/test";
import { createBdd } from "playwright-bdd";

const { Then, When } = createBdd();

async function waitForLiveView(page: Page) {
  await expect(page.locator("[data-phx-main]")).toHaveClass(/phx-connected/u);
}

Then("the study mode is available", async ({ page }) => {
  await expect(
    page.getByRole("button", { name: "Belajar 3 Pasangan" }),
  ).toBeEnabled();
});

Then("the quiz mode is available", async ({ page }) => {
  await expect(
    page.getByRole("button", { name: "Latihan Ujian" }),
  ).toBeEnabled();
});

When("the visitor starts learning", async ({ page }) => {
  await waitForLiveView(page);
  await page.getByRole("button", { name: "Belajar 3 Pasangan" }).click();
});

async function swipe(
  page: Page,
  selector: string,
  direction: "left" | "right",
) {
  const target = page.locator(selector);
  const box = await target.boundingBox();

  if (!box) throw new Error(`Swipe target ${selector} is not visible`);

  const startX = box.x + box.width / 2;
  const endX = startX + (direction === "left" ? -80 : 80);
  const y = box.y + box.height / 2;

  await page.mouse.move(startX, y);
  await page.mouse.down();
  await page.mouse.move(endX, y, { steps: 4 });
  await page.mouse.up();
}

When("the visitor swipes left on the study card", async ({ page }) => {
  await waitForLiveView(page);
  await swipe(page, "[data-role=study-card]", "left");
});

When("the visitor swipes right on the study card", async ({ page }) => {
  await waitForLiveView(page);
  await swipe(page, "[data-role=study-card]", "right");
});

When("the visitor returns to the mission", async ({ page }) => {
  await waitForLiveView(page);
  await page.getByRole("button", { name: "← Kembali ke misi" }).click();
});

When("the visitor swipes left on the quiz question", async ({ page }) => {
  await waitForLiveView(page);
  await swipe(page, "[data-role=quiz-question] h2", "left");
});

When("the visitor swipes right on the quiz question", async ({ page }) => {
  await waitForLiveView(page);
  await swipe(page, "[data-role=quiz-question] h2", "right");
});

Then(
  "the study card shows {string} and {string}",
  async ({ page }, name: string, meaning: string) => {
    await expect(page.locator("[data-role=study-card]")).toContainText(name);
    await expect(page.locator("[data-role=study-card]")).toContainText(meaning);
  },
);

When("the visitor marks the current pair as remembered", async ({ page }) => {
  await waitForLiveView(page);
  await page.getByRole("button", { name: "Aku sudah ingat" }).click();
});

Then("the progress shows {string}", async ({ page }, progress: string) => {
  await expect(page.getByText(progress, { exact: true })).toBeVisible();
});

When("the visitor starts a quiz", async ({ page }) => {
  await waitForLiveView(page);
  await page.getByRole("button", { name: "Latihan Ujian" }).click();
});

When("the visitor starts focused review", async ({ page }) => {
  await waitForLiveView(page);
  await page
    .getByRole("button", { name: /^Ulangi yang masih bikin bingung \(\d+\)$/u })
    .click();
});

When("the visitor continues to the next quiz question", async ({ page }) => {
  await waitForLiveView(page);
  await page.getByRole("button", { name: "Soal berikutnya →" }).click();
});

When("the visitor answers {string}", async ({ page }, answer: string) => {
  await waitForLiveView(page);
  await page.getByRole("button", { name: answer, exact: true }).click();
});

When(
  "the visitor answers {string} in focused review",
  async ({ page }, answer: string) => {
    await waitForLiveView(page);
    await page
      .locator("[data-role=review-question]")
      .getByRole("button", { name: answer, exact: true })
      .click();
  },
);

When("the visitor continues focused review", async ({ page }) => {
  await waitForLiveView(page);
  await page.locator('button[phx-click="next-review-question"]').click();
});

Then("the revision list contains {string}", async ({ page }, name: string) => {
  await expect(page.getByTestId("sifat-allah-revision-list")).toContainText(
    name,
  );
});
