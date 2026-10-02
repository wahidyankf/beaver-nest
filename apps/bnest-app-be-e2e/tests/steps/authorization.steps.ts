import { readFileSync } from "node:fs";
import { expect, type BrowserContext, type Page } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import {
  isolatedTestIdentity,
  type TestIdentity,
} from "../support/test-identity";
import {
  login,
  runtimeDigest,
  storedAccountFile,
} from "../support/authentication";

const { Given, Then, When } = createBdd();

let activeIdentity: TestIdentity;
let accountsDigestBefore = "";
let secondUserContext: BrowserContext | undefined;
let secondUserPage: Page | undefined;
let crossUserResponses: { read: string; writeStatus: number } | undefined;

function storedRoles(username: string): string[] {
  const account = JSON.parse(
    readFileSync(storedAccountFile(username), "utf8"),
  ) as { roles: string[] };
  return account.roles.toSorted();
}

async function csrfToken(page: Page): Promise<string> {
  const token = await page
    .locator("meta[name='csrf-token']")
    .getAttribute("content");
  if (!token) throw new Error("The page carries no CSRF token");
  return token;
}

// The isolated identity whose stored roles are exactly the two the scenario names.
Given(
  "an approved user has the roles {string} and {string}",
  async ({ page, $testInfo }, firstRole: string, secondRole: string) => {
    activeIdentity = isolatedTestIdentity($testInfo);
    expect(storedRoles(activeIdentity.admin.username)).toEqual(
      [firstRole, secondRole].toSorted(),
    );
    await login(page, activeIdentity.admin);
  },
);

When("Bnest authorizes that user's own data operation", async ({ page }) => {
  await page.goto("/chat");
});

Then("the operation is allowed", async ({ page }) => {
  await expect(
    page.getByRole("heading", { name: "Beaver Nest" }),
  ).toBeVisible();
  await expect(page.getByLabel("Message")).toBeEnabled();
});

// Creating accounts after setup is an administration operation no role is approved for.
// The user's own session submits it to the account-creation endpoint with a valid CSRF
// token; Bnest refuses it and the stored accounts stay as they were.
Then("an out-of-scope administration operation is denied", async ({ page }) => {
  accountsDigestBefore = runtimeDigest("system/accounts");
  await page.goto("/");
  const response = await page.request.post("/setup", {
    form: {
      "accounts[0][username]": "test-user-e2e-forged-account",
      "accounts[0][password]": "Synthetic forged password 1!",
      "accounts[0][roles][]": "admin",
    },
    headers: { "x-csrf-token": await csrfToken(page) },
  });
  expect(response.status()).toBe(404);
  expect(runtimeDigest("system/accounts")).toBe(accountsDigestBefore);
});

// The child owns a dark theme saved through their own session; the administrator owns the
// light theme.
Given(
  "two approved users own separate Bnest data",
  async ({ page, $testInfo }) => {
    activeIdentity = isolatedTestIdentity($testInfo);
    const browser = page.context().browser();
    if (!browser) throw new Error("Browser fixture is unavailable");
    await login(page, activeIdentity.admin);
    secondUserContext = await browser.newContext({
      baseURL: new URL(page.url()).origin,
    });
    secondUserPage = await secondUserContext.newPage();
    await login(secondUserPage, activeIdentity.child);
    await saveTheme(secondUserPage, "dark");
    await saveTheme(page, "light");
  },
);

async function saveTheme(page: Page, theme: string): Promise<void> {
  await page.goto("/");
  const response = await page.request.put("/preferences/theme", {
    form: { theme },
    headers: { "x-csrf-token": await csrfToken(page) },
  });
  expect(response.status()).toBe(204);
  await page.goto("/");
  await expect(page.locator("html")).toHaveAttribute("data-theme", theme);
}

// The administrator names the child as the owner of a read and of a write.
When(
  "the first user attempts the second user's data operation",
  async ({ page }) => {
    const owner = storedAccountFile(activeIdentity.child.username)
      .split("/")
      .at(-1)
      ?.replace(/\.json$/u, "");
    if (!owner) throw new Error("The child has no account");
    await page.goto(`/?owner=${encodeURIComponent(owner)}`);
    const read = (await page.locator("html").getAttribute("data-theme")) ?? "";
    await page.goto("/");
    const write = await page.request.put("/preferences/theme", {
      form: { owner, theme: "light", user_id: owner },
      headers: { "x-csrf-token": await csrfToken(page) },
    });
    crossUserResponses = { read, writeStatus: write.status() };
  },
);

// The read showed the administrator's own theme, and the write landed on the
// administrator's record only: the child's session still renders the child's dark theme.
Then(
  "Bnest denies the operation before repository access",
  async ({ page }) => {
    void page;
    if (!secondUserPage || !secondUserContext || !crossUserResponses)
      throw new Error("The second user's session was not opened");
    expect(crossUserResponses.read).toBe("light");
    expect(crossUserResponses.writeStatus).toBe(204);
    await secondUserPage.goto("/");
    await expect(secondUserPage.locator("html")).toHaveAttribute(
      "data-theme",
      "dark",
    );
    await secondUserContext.close();
    secondUserContext = undefined;
    secondUserPage = undefined;
  },
);
