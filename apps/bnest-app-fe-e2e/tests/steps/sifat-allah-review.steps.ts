import { expect, type Page } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import { ensureCandidate } from "../support/candidate-pool";
import { login } from "../support/authentication";
import { instanceIdentities } from "../support/instance-identities";
import { candidatePort } from "../support/routed-rollout-env";

// Quiz review flows, the celebration outline, and the storage note. Split
// out of sifat_allah.steps.ts to stay under the repository's 300-line
// step-file budget.

// @scenario specs/apps/bnest/app-fe/behaviours/sifat_allah.feature: A celebration plays on success and is skipped with reduced motion
// @scenario specs/apps/bnest/app-fe/behaviours/sifat_allah.feature: The page says where progress is stored for this user

// The celebration outline and the storage note (BN-SIFAT-15, BN-SIFAT-17).
// The failed-save notice (BN-SIFAT-16) is e2e-exempt: no browser action makes
// the healthy server store fail, so it runs at integration and unit only and
// has no binding here.

const { Given, Then, When } = createBdd();

async function waitForLiveView(page: Page) {
  await expect(page.locator("[data-phx-main]")).toHaveClass(/phx-connected/u);
}

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

When(
  "the visitor answers {string} with {string} motion preference",
  async ({ page }, answer: string, motion: string) => {
    await waitForLiveView(page);
    if (motion === "reduced") {
      await page.emulateMedia({ reducedMotion: "reduce" });
    }
    await page.getByRole("button", { name: answer, exact: true }).click();
  },
);

Then(
  "the celebration layer holds {int} pieces",
  async ({ page }, pieces: number) => {
    await expect(
      page.locator("#sifat-celebrations .sifat-confetti"),
    ).toHaveCount(pieces);
  },
);

// The revision page owner: the signed-in child on the primary server, or the
// local browser on the cutover-off candidate.
let revisionUrl: string | undefined;

Given("the signed-in child is ready", async ({ page }) => {
  revisionUrl = undefined;
  await login(page, instanceIdentities().child);
});

Given("the local browser is ready", async ({ page }) => {
  await ensureCandidate(candidatePort, undefined, undefined, false);
  await page.context().clearCookies();
  revisionUrl = `http://localhost:${candidatePort}`;
});

When("the revision page opens", async ({ page }) => {
  await page.goto(`${revisionUrl ?? ""}/apps/sifat-allah`);
  await waitForLiveView(page);
});

Then(
  "the page shows the storage note {string}",
  async ({ page }, message: string) => {
    await expect(page.locator(".sifat-saved-note")).toHaveText(message);
  },
);
