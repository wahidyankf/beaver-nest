import { expect, type Page } from "@playwright/test";
import { createBdd } from "playwright-bdd";

const { Given, Then, When } = createBdd();

const questionKinds = [
  "wajib_meaning",
  "wajib_opposite",
  "mustahil_meaning",
  "meaning_wajib",
  "mustahil_opposite",
  "meaning_mustahil",
];

const masteredQuestionIds = (pairIds: string[]) =>
  pairIds.flatMap((pairId) => questionKinds.map((kind) => `${pairId}:${kind}`));

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

Given("the visitor has remembered every Sifat Allah pair", async ({ page }) => {
  const pairIds = [
    "wujud",
    "qidam",
    "baqa",
    "mukhalafatuhu-lil-hawaditsi",
    "qiyamuhu-binafsihi",
    "wahdaniyah",
    "qudrah",
    "iradah",
    "ilmun",
    "hayah",
    "sama",
    "basar",
    "kalam",
    "qadiran",
    "muridan",
    "aliman",
    "hayyan",
    "samian",
    "basiran",
    "mutakalliman",
  ];

  const rememberedQuestionIds = masteredQuestionIds(pairIds);

  await page.evaluate((masteredKeyIds) => {
    localStorage.setItem(
      "bnest.sifat-allah.v1",
      JSON.stringify({
        version: 2,
        mastered_key_ids: masteredKeyIds,
        review_key_ids: [],
        correct_answers: 0,
        incorrect_answers: 0,
        session: { mode: "dashboard" },
      }),
    );
  }, rememberedQuestionIds);
  await page.reload();
  await waitForLiveView(page);
});

async function swipe(
  page: Page,
  selector: string,
  direction: "left" | "right",
) {
  const target = page.locator(selector);
  await target.scrollIntoViewIfNeeded();
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

When("the visitor goes back in the browser", async ({ page }) => {
  await expect
    .poll(() => page.evaluate(() => history.state?.bnestSifatMode))
    .toBe("active");
  await page.goBack();
  await waitForLiveView(page);
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

Then(
  "the study card uses green for wajib and orange for mustahil",
  async ({ page }) => {
    await expect(page.locator("[data-memory-color=wajib]")).toBeVisible();
    await expect(page.locator("[data-memory-color=mustahil]")).toBeVisible();
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

Then("the quiz puts correct answers in varied positions", async ({ page }) => {
  const answerButtons = page.locator(".sifat-answer-grid button");
  const firstPosition = await answerButtons.evaluateAll((buttons) =>
    buttons.findIndex((button) => button.textContent?.trim() === "Ada"),
  );

  await page.getByRole("button", { name: "Soal berikutnya →" }).click();

  await expect(page.locator("[data-role=quiz-question] h2")).toHaveText(
    "Apa lawan dari Qidam?",
  );

  const secondPosition = await answerButtons.evaluateAll((buttons) =>
    buttons.findIndex((button) => button.textContent?.trim() === "Hudus"),
  );

  expect(firstPosition).not.toBe(secondPosition);
});

When("the visitor starts learned review", async ({ page }) => {
  await waitForLiveView(page);
  await page
    .getByRole("button", { name: /^Ulangi yang sudah hafal \(\d+\)$/u })
    .click();
});

When("the visitor starts focused review", async ({ page }) => {
  await waitForLiveView(page);
  await page
    .getByRole("button", { name: /^Ulangi yang masih bikin bingung \(\d+\)$/u })
    .click();
});

When("the visitor continues to the next quiz question", async ({ page }) => {
  await waitForLiveView(page);
  const question = page.locator("[data-role=quiz-question] h2");
  const previousQuestion = await question.innerText();
  await page.getByRole("button", { name: "Soal berikutnya →" }).click();
  await expect.poll(() => question.innerText()).not.toBe(previousQuestion);
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
