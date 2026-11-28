import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";

// The install-as-an-app scenario of chat.feature. Split out of
// browser.steps.ts to stay under the repository's 300-line step-file budget.
// The navigation, conversation, and reconnect scenarios stay in
// browser.steps.ts.

// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: A visitor can install Beaver Nest as an app

const { Then } = createBdd();

Then("Beaver Nest is ready to install as an app", async ({ page }) => {
  await expect(page.locator('link[rel="manifest"]')).toHaveAttribute(
    "href",
    "/manifest.webmanifest",
  );

  const manifest = await page.evaluate(async () => {
    const response = await fetch("/manifest.webmanifest");
    return response.json() as Promise<{
      name: string;
      display: string;
      icons: Array<{ src: string; sizes: string }>;
    }>;
  });

  expect(manifest.name).toBe("Beaver Nest");
  expect(manifest.display).toBe("standalone");
  expect(manifest.icons).toEqual(
    expect.arrayContaining([
      expect.objectContaining({
        src: "/images/beaver-nest-192.png",
        sizes: "192x192",
      }),
      expect.objectContaining({
        src: "/images/beaver-nest-512.png",
        sizes: "512x512",
      }),
    ]),
  );

  await expect
    .poll(() =>
      page.evaluate(async () => {
        const registration = await navigator.serviceWorker.ready;
        return registration.active?.scriptURL ?? "";
      }),
    )
    .toMatch(/\/service-worker\.js$/u);
});
