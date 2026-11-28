import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import { ensureCandidate } from "../support/candidate-pool";
import { login } from "../support/authentication";
import {
  chatPayload,
  confirmImports,
  learningPayload,
  setSources,
} from "../support/centralized-data";
import {
  instanceIdentities,
  type InstanceIdentities,
  userIdFor,
} from "../support/instance-identities";
import { instanceRecord } from "../support/instance-records";
import { candidatePort } from "../support/routed-rollout-env";

// Trimmed from bnest-app-e2e's centralized_data.steps.ts to this project's
// owned scenarios (the browser-key-clearing half of accepted import, and the
// fresh-conversation-report half of Codex-thread resume); the server-side
// persistence scenarios moved to bnest-app-be-e2e.

const { Given, Then, When } = createBdd();

let activeIdentity: InstanceIdentities;

Given(
  "a recognized browser source and an unrelated browser key exist",
  async ({ page }) => {
    activeIdentity = instanceIdentities();
    await setSources(page, { chat: chatPayload, learning: null, theme: null });
    await page.evaluate(() =>
      localStorage.setItem("unrelated.test-key", "keep-me"),
    );
  },
);

When("Bnest accepts and reads back the normalized record", async ({ page }) => {
  await confirmImports(page);
});

Then("Bnest clears only the accepted source key", async ({ page }) => {
  expect(
    await page.evaluate(() => sessionStorage.getItem("bnest.chat.v1")),
  ).toBeNull();
  expect(
    await page.evaluate(() => localStorage.getItem("unrelated.test-key")),
  ).toBe("keep-me");
});

Given(
  "centralized chat contains a transcript and an unavailable Codex thread",
  async ({ page }) => {
    activeIdentity = instanceIdentities();
    await page.context().clearCookies();
    await login(page, activeIdentity.child);

    const unavailable = JSON.stringify({
      ...JSON.parse(chatPayload),
      thread_id: "unavailable-thread",
      messages: [
        {
          id: 1,
          role: "visitor",
          content: "Original question",
          update_count: 0,
        },
        {
          id: 2,
          role: "assistant",
          content: "Original answer",
          update_count: 1,
        },
      ],
    });
    await setSources(page, { chat: unavailable, learning: null, theme: null });
    await confirmImports(page);
  },
);

When("the authenticated user continues the chat", async ({ page }) => {
  await page.goto("/chat");
  await expect(page.locator("[data-phx-main]")).toHaveClass(/phx-connected/u);
  await page.getByLabel("Message").fill("Continue after resume");
  await page.getByRole("button", { name: "Send" }).click();
});

// The chat record is read from the test instance's database, as the server stores it. A failed resume would keep the
// unavailable thread, so the record must name a different thread.
Then("Bnest reports a fresh Codex conversation", async ({ page }) => {
  await expect(page.getByRole("alert")).toContainText(
    "transcript is preserved in a fresh conversation",
  );
  const chat = instanceRecord("chat", userIdFor(activeIdentity.child.username))[
    "state"
  ] as { thread_id: string | null };
  expect(chat.thread_id).not.toBe("unavailable-thread");
});

// @scenario specs/apps/bnest/app-fe/behaviours/centralized_data.feature: The migration page lists each recognized browser source
// @scenario specs/apps/bnest/app-fe/behaviours/centralized_data.feature: Each import outcome shows its label and its status
// @scenario specs/apps/bnest/app-fe/behaviours/centralized_data.feature: A browser acting as the local user is told to log in before importing
// @scenario specs/apps/bnest/app-fe/behaviours/centralized_data.feature: Accepted browser import clears only the accepted browser key
// @scenario specs/apps/bnest/app-fe/behaviours/centralized_data.feature: Failed Codex-thread resume reports a fresh conversation

// The recognized-source list, the per-outcome lines, and the local-user gate
// (BN-DATA-01, BN-DATA-09, BN-DATA-10). The retryable and stale-revision outline
// rows are e2e-exempt: neither a storage write failure nor a concurrent newer
// record can be caused from a browser on a healthy server (direct browser proof
// is environment-blocked here; the two-import stale flow is proven at
// integration and unit). The accepted and rejected rows stay bound here.

Given(
  "this browser holds chat, learning, and absent theme sources plus an unknown key",
  async ({ page }) => {
    await setSources(page, {
      chat: chatPayload,
      learning: learningPayload,
      theme: null,
    });
    await page.evaluate(() => localStorage.setItem("unknown.key", "keep"));
  },
);

Then(
  "the migration page lists {string} as {string}",
  async ({ page }, label: string, status: string) => {
    const card = page.locator(".identity-account-card", { hasText: label });
    await expect(card).toContainText(status);
  },
);

Then("the migration page lists no unknown source", async ({ page }) => {
  await expect(page.locator("#browser-import")).not.toContainText(
    "unknown.key",
  );
});

// A failing write and a concurrent newer record are server states the browser
// cannot produce (hence the retryable/stale e2e exemption); the accepted and
// rejected rows file genuine sources and read the genuine outcome line. The
// stale branch below still replays the two sequential imports, as integration
// and unit do, so the row stays runnable where it is bound.
Given("a browser source filed as {string}", async ({ page }, filed: string) => {
  if (filed === "accepted" || filed === "retryable") {
    await setSources(page, { chat: chatPayload, learning: null, theme: null });
  } else if (filed === "rejected") {
    await setSources(page, { chat: "{malformed", learning: null, theme: null });
  } else if (filed === "stale") {
    await setSources(page, { chat: chatPayload, learning: null, theme: null });
    await confirmImports(page);
    const stale = JSON.stringify({
      ...JSON.parse(chatPayload),
      model: "stale",
    });
    await setSources(page, { chat: stale, learning: null, theme: null });
  } else {
    throw new Error(`unknown filed source: ${filed}`);
  }
});

When("the user confirms the recognized imports", async ({ page }) => {
  await confirmImports(page);
});

Then("the migration page shows {string}", async ({ page }, line: string) => {
  await expect(page.locator("#browser-import")).toContainText(line);
});

// The cutover-off candidate serves the legacy local browser instead of the
// login gate (the same candidate the authentication cutover scenario uses).
When(
  "the visitor opens the migration page on the cutover-off candidate",
  async ({ page }) => {
    await ensureCandidate(candidatePort, false);
    // The Background logs an approved user in, and cookies are shared across
    // ports on localhost, so the candidate would authenticate that identity
    // cookie. Drop it so the browser acts as the local user (no identity).
    await page.context().clearCookies({ name: "_bnest_identity" });
    await page.goto(`http://localhost:${candidatePort}/data-migration`);
    // No wait for a connected LiveView here: the local user is redirected to
    // the home page, which has none. Wait for the home page itself instead --
    // its URL and its own heading -- so a Then that expects a control to be
    // absent never runs against the page being left.
    await expect(page).toHaveURL(`http://localhost:${candidatePort}/`);
    await expect(page.locator("#home-title")).toBeVisible();
  },
);

Then(
  "the visitor lands on the home page with the login warning",
  async ({ page }) => {
    await expect(page).toHaveURL(/\/$/u);
    await expect(
      page.getByText("Log in before importing browser data."),
    ).toBeVisible();
  },
);

Then("the visitor sees no import control", async ({ page }) => {
  await expect(
    page.getByRole("button", { name: "Preserve and verify recognized data" }),
  ).toHaveCount(0);
});
