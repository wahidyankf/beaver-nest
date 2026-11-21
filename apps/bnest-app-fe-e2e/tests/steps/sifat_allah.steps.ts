import { expect, type Page } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import { saveEveryPairRemembered } from "../support/sifat-allah-progress";
import { instanceIdentities } from "../support/instance-identities";

const { Given, Then, When } = createBdd();

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

// The logged-in child's progress is saved on the server, then the page is
// opened again over it; the Given fails unless the page shows that progress.
Given("the visitor has remembered every Sifat Allah pair", async ({ page }) => {
  saveEveryPairRemembered(instanceIdentities().child.username);
  await page.reload();
  await waitForLiveView(page);
  await expect(
    page.getByText("120 dari 120 soal sudah hafal", { exact: true }),
  ).toBeVisible();
});

// A pair is remembered by the study card's mark, or by a correct answer to the first quiz
// question. The visitor is back on the mission afterwards, as the feature expects.
Given(
  "the visitor has remembered the first pair by {string}",
  async ({ page }, how: string) => {
    await waitForLiveView(page);
    if (how === "study mark") {
      await page.getByRole("button", { name: "Belajar 3 Pasangan" }).click();
      await page.getByRole("button", { name: "Aku sudah ingat" }).click();
    } else if (how === "a correct answer") {
      await page.getByRole("button", { name: "Latihan Ujian" }).click();
      await page.getByRole("button", { name: "Ada", exact: true }).click();
    } else {
      throw new Error(`unknown way to remember a pair: ${how}`);
    }
    await page.getByRole("button", { name: "← Kembali ke misi" }).click();
  },
);

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

// Green has green as its strongest channel; orange has red strongest, then
// green, then blue.
function hueOf(color: string): "green" | "orange" | "other" {
  const [red = 0, green = 0, blue = 0] = (color.match(/\d+/gu) ?? []).map(
    Number,
  );
  if (green > red && green > blue) return "green";
  if (red > green && green > blue) return "orange";
  return "other";
}

Then(
  "the study card uses green for wajib and orange for mustahil",
  async ({ page }) => {
    const card = page.locator("[data-role=study-card]");
    const backgroundOf = (label: string) =>
      card
        .locator(".sifat-side", { hasText: label })
        .evaluate((side) => getComputedStyle(side).backgroundColor);

    await expect(card).toBeVisible();
    expect(hueOf(await backgroundOf("SIFAT WAJIB"))).toBe("green");
    expect(hueOf(await backgroundOf("SIFAT MUSTAHIL"))).toBe("orange");
  },
);

When("the visitor marks the current pair as remembered", async ({ page }) => {
  await waitForLiveView(page);
  await page.getByRole("button", { name: "Aku sudah ingat" }).click();
});

Then("the progress shows {string}", async ({ page }, progress: string) => {
  await expect(page.getByText(progress, { exact: true })).toBeVisible();
});

When("the visitor asks to reset Sifat Allah progress", async ({ page }) => {
  await waitForLiveView(page);
  await page
    .getByRole("button", { name: "Reset progress", exact: true })
    .click();
});

When(
  "the visitor confirms resetting Sifat Allah progress",
  async ({ page }) => {
    await waitForLiveView(page);
    await page
      .getByRole("button", { name: "Ya, reset progress", exact: true })
      .click();
  },
);

When("the visitor starts a quiz", async ({ page }) => {
  await waitForLiveView(page);
  await page.getByRole("button", { name: "Latihan Ujian" }).click();
});

Then("the quiz puts correct answers in varied positions", async ({ page }) => {
  const answerButtons = page.locator(".sifat-answer-grid button");
  await expect(page.locator("[data-role=quiz-question] h2")).toHaveText(
    "Apa arti Wujud?",
  );
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

  expect(firstPosition).toBeGreaterThanOrEqual(0);
  expect(secondPosition).toBeGreaterThanOrEqual(0);
  expect(firstPosition).not.toBe(secondPosition);
});

Then("the quiz answer choices are locked", async ({ page }) => {
  const answerButtons = page.locator(".sifat-answer-grid button");
  await expect
    .poll(() =>
      answerButtons.evaluateAll(
        (buttons) =>
          buttons.length > 0 &&
          buttons.every(
            (button) =>
              button instanceof HTMLButtonElement &&
              button.disabled &&
              getComputedStyle(button).pointerEvents === "none",
          ),
      ),
    )
    .toBe(true);
});

When("five seconds pass after a quiz answer", async ({ page }) => {
  await page.waitForTimeout(5_000);
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

// Moves to the next quiz question and waits until the question text has changed.
async function continueQuizQuestion(page: Page) {
  const question = page.locator("[data-role=quiz-question] h2");
  const previousQuestion = await question.innerText();
  await page.getByRole("button", { name: "Soal berikutnya →" }).click();
  await expect.poll(() => question.innerText()).not.toBe(previousQuestion);
}

When("the visitor continues to the next quiz question", async ({ page }) => {
  await waitForLiveView(page);
  await continueQuizQuestion(page);
});

// Question 1 is the one the quiz opens on, so question N is N - 1 continues.
When(
  "the visitor reaches quiz question number {int}",
  async ({ page }, number: number) => {
    await waitForLiveView(page);
    for (let reached = 1; reached < number; reached += 1) {
      // eslint-disable-next-line no-await-in-loop -- each continue reads the question the one before it showed.
      await continueQuizQuestion(page);
    }
  },
);

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
