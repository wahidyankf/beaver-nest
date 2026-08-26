import { existsSync, readFileSync } from "node:fs";
import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import { login } from "../support/authentication";
import {
  chatPayload,
  confirmImports,
  digestFile,
  importCount,
  learningPayload,
  seedInterruptedChatImport,
  setSources,
  userPath,
} from "../support/centralized-data";
import {
  isolatedTestIdentity,
  testIdentityForProject,
  type TestIdentity,
} from "../support/test-identity";

const { Given, Then, When } = createBdd();

let beforeRecordDigest = "";
let beforeThemeDigest = "";
let beforeImportCount = 0;
let activeIdentity: TestIdentity = testIdentityForProject("chromium");

Given(
  "the browser has recognized Bnest chat, Sifat Allah, and explicit theme sources",
  async ({ page, $testInfo }) => {
    activeIdentity = isolatedTestIdentity($testInfo);
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

Then("Bnest preserves an immutable envelope for each source", ({ page }) => {
  void page;
  expect(importCount(activeIdentity.admin.username)).toBeGreaterThanOrEqual(3);
});

Then(
  "Bnest reads each normalized user-owned record successfully",
  ({ page }) => {
    void page;
    expect(
      existsSync(userPath("chat/current.json", activeIdentity.admin.username)),
    ).toBe(true);
    expect(
      existsSync(
        userPath("sifat-allah/progress.json", activeIdentity.admin.username),
      ),
    ).toBe(true);
    expect(
      existsSync(
        userPath("preferences/theme.json", activeIdentity.admin.username),
      ),
    ).toBe(true);
  },
);

Given(
  "the browser has no explicit theme source",
  async ({ page, $testInfo }) => {
    activeIdentity = isolatedTestIdentity($testInfo);
    await setSources(page, { chat: null, learning: null, theme: null });
    beforeThemeDigest = digestFile(
      userPath("preferences/theme.json", activeIdentity.admin.username),
    );
  },
);

Then("Bnest records the absent system theme outcome", async ({ page }) => {
  await expect(
    page.getByText("Theme preference: accepted and verified"),
  ).toBeVisible();
});

Then("Bnest creates no explicit theme preference", ({ page }) => {
  void page;
  expect(
    digestFile(
      userPath("preferences/theme.json", activeIdentity.admin.username),
    ),
  ).toBe(beforeThemeDigest);
});

Given(
  "the browser has an invalid Bnest source",
  async ({ page, $testInfo }) => {
    activeIdentity = isolatedTestIdentity($testInfo);
    await setSources(page, { chat: chatPayload, learning: null, theme: null });
    await confirmImports(page);
    await setSources(page, { chat: "{malformed", learning: null, theme: null });
    beforeRecordDigest = digestFile(
      userPath("chat/current.json", activeIdentity.admin.username),
    );
  },
);

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
    expect(
      digestFile(userPath("chat/current.json", activeIdentity.admin.username)),
    ).toBe(beforeRecordDigest);
  },
);

Given(
  "a recognized import was interrupted after source preservation",
  async ({ page, $testInfo }) => {
    activeIdentity = isolatedTestIdentity($testInfo);
    await setSources(page, { chat: chatPayload, learning: null, theme: null });
    seedInterruptedChatImport(activeIdentity.admin.username);
    beforeImportCount = importCount(activeIdentity.admin.username);
  },
);

When("the user retries that import", async ({ page }) => {
  await confirmImports(page);
});

Then("Bnest reuses its idempotent import identity", ({ page }) => {
  void page;
  expect(importCount(activeIdentity.admin.username)).toBe(beforeImportCount);
});

Then(
  "Bnest does not duplicate or overwrite accepted data",
  async ({ page }) => {
    await expect(
      page.getByText("Chat conversation: accepted and verified"),
    ).toBeVisible();
  },
);

Given(
  "browser B has an older revision than browser A",
  async ({ page, $testInfo }) => {
    activeIdentity = isolatedTestIdentity($testInfo);
    await setSources(page, { chat: chatPayload, learning: null, theme: null });
    await confirmImports(page);
    beforeRecordDigest = digestFile(
      userPath("chat/current.json", activeIdentity.admin.username),
    );
    const stale = JSON.stringify({
      ...JSON.parse(chatPayload),
      reasoning_effort: "high",
    });
    await setSources(page, { chat: stale, learning: null, theme: null });
  },
);

When("browser B writes the stale record", async ({ page }) => {
  await confirmImports(page);
});

Then("Bnest keeps the newer centralized record", ({ page }) => {
  void page;
  expect(
    digestFile(userPath("chat/current.json", activeIdentity.admin.username)),
  ).toBe(beforeRecordDigest);
});

Then("browser B is asked to refresh", async ({ page }) => {
  await expect(page.getByText(/newer server data exists/u)).toBeVisible();
});

Given(
  "a recognized browser source and an unrelated browser key exist",
  async ({ page, $testInfo }) => {
    activeIdentity = isolatedTestIdentity($testInfo);
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

Then("Bnest persists future changes only on the server", async ({ page }) => {
  const username = activeIdentity.admin.username;
  const chatPath = userPath("chat/current.json", username);
  const learningPath = userPath("sifat-allah/progress.json", username);
  const beforeChat = digestFile(chatPath);
  const beforeLearning = digestFile(learningPath);

  await page.goto("/chat");
  await expect(page.locator("[data-phx-main]")).toHaveClass(/phx-connected/u);
  await page.getByLabel("Message").fill("Server-only follow-up");
  await page.getByRole("button", { name: "Send" }).click();
  await expect.poll(() => digestFile(chatPath)).not.toBe(beforeChat);

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
  expect(digestFile(learningPath)).not.toBe(beforeLearning);

  await page.getByRole("button", { name: "Use dark theme" }).click();
  await expect(page.locator("html")).toHaveAttribute("data-theme", "dark");
  expect(
    await page.evaluate(() => localStorage.getItem("phx:theme")),
  ).toBeNull();

  const theme = JSON.parse(
    readFileSync(userPath("preferences/theme.json", username), "utf8"),
  ) as { theme: string };
  expect(theme.theme).toBe("dark");
});

Given(
  "centralized chat contains a transcript and an unavailable Codex thread",
  async ({ page, $testInfo }) => {
    activeIdentity = isolatedTestIdentity($testInfo);
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

Then("Bnest preserves the transcript", async ({ page }) => {
  await expect(page.getByText("Original question")).toBeVisible();
  await expect(page.getByText("Original answer")).toBeVisible();
});

Then("Bnest reports a fresh Codex conversation", async ({ page }) => {
  await expect(page.getByRole("alert")).toContainText(
    "transcript is preserved in a fresh conversation",
  );
  expect(
    existsSync(userPath("chat/current.json", activeIdentity.child.username)),
  ).toBe(true);
});
