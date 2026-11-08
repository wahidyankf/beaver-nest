import { expect, type Page } from "@playwright/test";

export const chatPayload = JSON.stringify({
  version: 2,
  thread_id: null,
  model: "fixture-model",
  reasoning_effort: "medium",
  messages: [],
});

export const learningPayload = JSON.stringify({
  version: 2,
  learned_ids: [],
  review_ids: [],
  mastered_key_ids: [],
  review_key_ids: [],
  correct_answers: 0,
  incorrect_answers: 0,
  session: { mode: "dashboard" },
});

export async function setSources(
  page: Page,
  sources: {
    chat?: string | null;
    learning?: string | null;
    theme?: string | null;
  },
) {
  await page.goto("/");
  await page.evaluate((values) => {
    if (values.chat === null) sessionStorage.removeItem("bnest.chat.v1");
    else if (values.chat !== undefined)
      sessionStorage.setItem("bnest.chat.v1", values.chat);

    if (values.learning === null)
      localStorage.removeItem("bnest.sifat-allah.v1");
    else if (values.learning !== undefined) {
      localStorage.setItem("bnest.sifat-allah.v1", values.learning);
    }

    if (values.theme === null) localStorage.removeItem("phx:theme");
    else if (values.theme !== undefined)
      localStorage.setItem("phx:theme", values.theme);
  }, sources);
  await page.goto("/data-migration");
  await expect(
    page.getByRole("heading", { name: "Save this browser's Bnest data" }),
  ).toBeVisible();
}

export async function confirmImports(page: Page) {
  await page
    .getByRole("button", { name: "Preserve and verify recognized data" })
    .click();
  await expect(
    page
      .getByText(
        /accepted and verified|rejected safely|newer server data exists/u,
      )
      .first(),
  ).toBeVisible();
}
