import { expect, type BrowserContext, type Page } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import { currentInstance } from "../support/active-instance.mts";
import { login, loginRefused } from "../support/authentication";
import {
  currentIdentities,
  rolesFor,
  userIdFor,
} from "../support/instance-identities";
import { instanceRecord } from "../support/instance-records";
import { csrfToken, putTheme } from "../support/theme-preference";
import { testUsername } from "../support/test-instance-lifecycle.mts";

const { Given, Then, When } = createBdd();

let secondUserContext: BrowserContext | undefined;
let crossUserResponses: { writeStatus: number } | undefined;

// The seeded admin whose stored roles are exactly the two the scenario names.
Given(
  "an approved user has the roles {string} and {string}",
  async ({ page }, firstRole: string, secondRole: string) => {
    const identity = currentIdentities();
    expect(rolesFor(identity.admin.username)).toEqual(
      [firstRole, secondRole].toSorted(),
    );
    await login(page, identity.admin);
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

// Creating accounts after setup is an administration operation no role is approved for. The user's own session
// submits it to the account-creation endpoint with a valid CSRF token; Bnest refuses it, and the account it tried
// to create cannot log in afterwards.
Then("an out-of-scope administration operation is denied", async ({ page }) => {
  const forged = {
    username: testUsername("forged", currentInstance().instanceId),
    password: "Synthetic forged password 1!",
  };
  await page.goto("/");
  const response = await page.request.post("/setup", {
    form: {
      "accounts[0][username]": forged.username,
      "accounts[0][password]": forged.password,
      "accounts[0][roles][]": "admin",
    },
    headers: { "x-csrf-token": await csrfToken(page) },
  });
  expect(response.status()).toBe(404);
  const browser = page.context().browser();
  if (!browser) throw new Error("Browser fixture is unavailable");
  await loginRefused(browser, new URL(page.url()).origin, forged);
});

// The child stores a dark theme through their own session; the administrator stores a dark one too, so the write below
// (light) changes each record it could reach. No page shows the
// theme any more (ADR 005), so each write is answered 204 by PUT /preferences/theme and read back from the test
// instance's record.
Given("two approved users own separate Bnest data", async ({ page }) => {
  const identity = currentIdentities();
  const browser = page.context().browser();
  if (!browser) throw new Error("Browser fixture is unavailable");
  await login(page, identity.admin);
  secondUserContext = await browser.newContext({
    baseURL: new URL(page.url()).origin,
  });
  const secondUserPage = await secondUserContext.newPage();
  await login(secondUserPage, identity.child);
  await saveTheme(secondUserPage, "dark", childId());
  await saveTheme(page, "dark", adminId());
});

function adminId(): string {
  return userIdFor(currentIdentities().admin.username);
}

function childId(): string {
  return userIdFor(currentIdentities().child.username);
}

async function saveTheme(
  page: Page,
  theme: string,
  owner: string,
): Promise<void> {
  await page.goto("/");
  expect(await putTheme(page, theme)).toBe(204);
  expect(instanceRecord("theme", owner)["theme"]).toBe(theme);
}

// The administrator names the child as the owner of a write. The write is a theme PUT that carries the child's id as an
// owner field.
When(
  "the first user attempts the second user's data operation",
  async ({ page }) => {
    const owner = childId();
    await page.goto("/");
    const writeStatus = await putTheme(page, "light", {
      owner,
      user_id: owner,
    });
    crossUserResponses = { writeStatus };
  },
);

// The server takes the owner from the session, never from the request. The write answers 204 and changes only the
// administrator's own record: it becomes light, and the child's stored theme stays dark.
Then("Bnest keeps the second user's data unchanged", async () => {
  if (!secondUserContext || !crossUserResponses)
    throw new Error("The second user's session was not opened");
  expect(crossUserResponses.writeStatus).toBe(204);
  expect(instanceRecord("theme", childId())["theme"]).toBe("dark");
  expect(instanceRecord("theme", adminId())["theme"]).toBe("light");
  await secondUserContext.close();
  secondUserContext = undefined;
  crossUserResponses = undefined;
});
