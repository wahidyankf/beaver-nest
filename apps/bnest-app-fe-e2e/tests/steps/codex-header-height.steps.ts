import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import { boxOf } from "../support/chat-ui-steps";

const { Then } = createBdd();

// The Codex header is at most 110 CSS pixels tall at every phone and short-window size (ADR 005, decision 5). The
// unit proof is the Vitest binding in apps/bnest-app/assets/test/behaviour/codex_layout.steps.ts, which reads the
// shipped rules that let the header's rows wrap instead of growing.
const HEADER_MAX_PX = 110;

Then("the Codex header is at most 110 pixels tall", async ({ page }) => {
  const header = await boxOf(page.locator(".chat-header"), "the Codex header");
  expect(header.height, "the Codex header height").toBeLessThanOrEqual(
    HEADER_MAX_PX,
  );
});
