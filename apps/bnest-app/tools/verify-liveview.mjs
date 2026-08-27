import { chromium } from "@playwright/test";

const origin = process.env.BNEST_PRODUCTION_ORIGIN;
if (!origin) throw new Error("BNEST_PRODUCTION_ORIGIN is required");

const browser = await chromium.launch({ headless: true });
let outcome = "failed";
const clients = [];

try {
  for (let index = 0; index < 10; index += 1) {
    const context = await browser.newContext();
    const page = await context.newPage();
    clients.push({ context, group: (index % 3) + 1, page, pathBefore: null });
  }

  await Promise.all(
    clients.map(async (client) => {
      await client.page.goto(new URL("/login", origin).toString(), {
        waitUntil: "domcontentloaded",
      });
      await client.page
        .locator("[data-phx-main]")
        .waitFor({ state: "attached" });
      await client.page.waitForFunction(() =>
        document
          .querySelector("[data-phx-main]")
          ?.classList.contains("phx-connected"),
      );
      client.pathBefore = new URL(client.page.url()).pathname;
    }),
  );

  await Promise.all(
    clients.map(({ page }) =>
      page.evaluate(() => window.liveSocket.disconnect()),
    ),
  );
  await Promise.all(
    clients.map(({ page }) =>
      page.waitForFunction(() =>
        document
          .querySelector("[data-phx-main]")
          ?.classList.contains("phx-client-error"),
      ),
    ),
  );
  await Promise.all(
    clients.map(({ page }) => page.evaluate(() => window.liveSocket.connect())),
  );
  await Promise.all(
    clients.map(async ({ page, pathBefore }) => {
      await page.waitForFunction(() =>
        document
          .querySelector("[data-phx-main]")
          ?.classList.contains("phx-connected"),
      );
      if (new URL(page.url()).pathname !== pathBefore)
        throw new Error("LiveView route changed during reconnect");
    }),
  );
  outcome = "passed";
} finally {
  await Promise.all(clients.map(({ context }) => context.close()));
  await browser.close();
}

process.stdout.write(
  `${JSON.stringify({
    schemaVersion: 1,
    outcome,
    liveView: true,
    reconnected: true,
    clientCount: clients.length,
    groupCount: new Set(clients.map(({ group }) => group)).size,
  })}\n`,
);
