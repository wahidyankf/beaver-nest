import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import { login } from "../support/authentication";
import {
  chatPayload,
  confirmImports,
  learningPayload,
  readChatState,
  recordSnapshot,
  setSources,
} from "../support/centralized-data";
import { currentIdentities, userIdFor } from "../support/instance-identities";
import { importCount, instanceRecord } from "../support/instance-records";
import { putTheme } from "../support/theme-preference";

// Trimmed from bnest-app-e2e's centralized_data.steps.ts to this project's owned scenarios (import/theme/rejection/
// idempotency/staleness, and the server-persistence halves of the accepted-import and Codex-resume scenarios); the
// browser-key-clearing and fresh-conversation-report halves moved to bnest-app-fe-e2e. Every record is read from the
// current test instance's database through production's record read, never from a file. The interrupted-import
// scenario's bindings live in centralized_data_import.steps.ts.

const { Given, Then, When } = createBdd();

let beforeRecordSnapshot = "";
let beforeThemeSnapshot = "";

function adminId(): string {
  return userIdFor(currentIdentities().admin.username);
}

function childId(): string {
  return userIdFor(currentIdentities().child.username);
}

Given(
  "the browser has recognized Bnest chat, Sifat Allah, and explicit theme sources",
  async ({ page }) => {
    await setSources(page, {
      chat: chatPayload,
      learning: learningPayload,
      theme: "dark",
    });
  },
);

When("the user confirms the recognized imports", async ({ page }) => {
  await confirmImports(page);
});

Then("Bnest preserves an immutable envelope for each source", () => {
  expect(importCount(adminId())).toBeGreaterThanOrEqual(3);
});

Then("Bnest reads each normalized user-owned record successfully", () => {
  const id = adminId();
  for (const kind of ["chat", "sifat_allah", "theme"] as const) {
    expect(instanceRecord(kind, id)).toEqual(expect.any(Object));
  }
});

Given("the browser has no explicit theme source", async ({ page }) => {
  await setSources(page, { chat: null, learning: null, theme: null });
  beforeThemeSnapshot = recordSnapshot("theme", adminId());
});

Then("Bnest records the absent system theme outcome", async ({ page }) => {
  await expect(
    page.getByText("Theme preference: accepted and verified"),
  ).toBeVisible();
});

Then("Bnest creates no explicit theme preference", () => {
  expect(recordSnapshot("theme", adminId())).toBe(beforeThemeSnapshot);
});

Given("the browser has an invalid Bnest source", async ({ page }) => {
  await setSources(page, { chat: chatPayload, learning: null, theme: null });
  await confirmImports(page);
  await setSources(page, { chat: "{malformed", learning: null, theme: null });
  beforeRecordSnapshot = recordSnapshot("chat", adminId());
});

Then("Bnest reports a safe rejected import", async ({ page }) => {
  await expect(
    page.getByText(/Chat conversation: rejected safely/u),
  ).toBeVisible();
});

Then(
  "the browser source and accepted server record remain unchanged",
  async ({ page }) => {
    expect(
      await page.evaluate(() => sessionStorage.getItem("bnest.chat.v1")),
    ).toBe("{malformed");
    expect(recordSnapshot("chat", adminId())).toBe(beforeRecordSnapshot);
  },
);

Given("browser B has an older revision than browser A", async ({ page }) => {
  await setSources(page, { chat: chatPayload, learning: null, theme: null });
  await confirmImports(page);
  beforeRecordSnapshot = recordSnapshot("chat", adminId());
  const stale = JSON.stringify({
    ...JSON.parse(chatPayload),
    reasoning_effort: "high",
  });
  await setSources(page, { chat: stale, learning: null, theme: null });
});

When("browser B writes the stale record", async ({ page }) => {
  await confirmImports(page);
});

Then("Bnest keeps the newer centralized record", () => {
  expect(recordSnapshot("chat", adminId())).toBe(beforeRecordSnapshot);
});

Then("browser B is asked to refresh", async ({ page }) => {
  await expect(page.getByText(/newer server data exists/u)).toBeVisible();
});

Given(
  "a recognized browser source and an unrelated browser key exist",
  async ({ page }) => {
    await setSources(page, { chat: chatPayload, learning: null, theme: null });
    await page.evaluate(() =>
      localStorage.setItem("unrelated.test-key", "keep-me"),
    );
  },
);

When("Bnest accepts and reads back the normalized record", async ({ page }) => {
  await confirmImports(page);
});

// Each write must reach the server's record, and the browser must keep none of it. A poll waits for the server's
// write; each read is a fresh production record read, so the timeout covers a secondary process per attempt.
Then("Bnest persists future changes only on the server", async ({ page }) => {
  const id = adminId();
  const beforeChat = recordSnapshot("chat", id);
  const beforeLearning = recordSnapshot("sifat_allah", id);

  await page.goto("/chat");
  await expect(page.locator("[data-phx-main]")).toHaveClass(/phx-connected/u);
  await page.getByLabel("Message").fill("Server-only follow-up");
  await page.getByRole("button", { name: "Send" }).click();
  await expect
    .poll(() => recordSnapshot("chat", id), { timeout: 30_000 })
    .not.toBe(beforeChat);

  expect(
    await page.evaluate(() => sessionStorage.getItem("bnest.chat.v1")),
  ).toBeNull();

  await page.goto("/apps/sifat-allah");
  await expect(page.locator("[data-phx-main]")).toHaveClass(/phx-connected/u);
  await page.getByRole("button", { name: "Belajar 3 Pasangan" }).click();
  await page.getByRole("button", { name: "Aku sudah ingat" }).click();

  expect(
    await page.evaluate(() => localStorage.getItem("bnest.sifat-allah.v1")),
  ).toBeNull();
  await expect
    .poll(() => recordSnapshot("sifat_allah", id), { timeout: 30_000 })
    .not.toBe(beforeLearning);

  // The preference is written through PUT /preferences/theme, the same surface the removed control used (ADR 005).
  expect(await putTheme(page, "dark")).toBe(204);
  // The theme is not kept in the browser: no localStorage theme key is written, only the server record changes.
  expect(
    await page.evaluate(() => localStorage.getItem("phx:theme")),
  ).toBeNull();

  expect(instanceRecord("theme", id)["theme"]).toBe("dark");
});

Given(
  "centralized chat contains a transcript and an unavailable Codex thread",
  async ({ page }) => {
    await page.context().clearCookies();
    await login(page, currentIdentities().child);

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

// The alert proves the failed resume was handled before the saved chat is read.
Then("Bnest preserves the transcript", async ({ page }) => {
  await expect(page.getByRole("alert")).toContainText(
    "transcript is preserved in a fresh conversation",
  );
  const original = ["Original question", "Original answer"];
  // Each text is matched inside its rendered bubble. A visitor message also keeps a hidden raw copy of its text, so a
  // page-wide text match would find the same message twice.
  await expect(
    page.locator("[data-role=user-message]", { hasText: "Original question" }),
  ).toBeVisible();
  await expect(
    page.locator("[data-role=assistant-message]", {
      hasText: "Original answer",
    }),
  ).toBeVisible();
  await expect(
    page.locator("[data-role=user-message]", {
      hasText: "Continue after resume",
    }),
  ).toBeVisible();
  const chat = readChatState(childId());
  expect(chat.thread_id).not.toBe("unavailable-thread");
  expect(chat.messages.slice(0, 2).map((m) => m.content)).toEqual(original);
});
