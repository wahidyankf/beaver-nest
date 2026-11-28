import { mkdirSync, rmSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import path from "node:path";
import { expect, type APIResponse } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import { openFamilyChatRoom } from "../support/family-chat";
import { sendThroughComposer } from "../support/family-chat-delivery";
import {
  requestedImageResponse,
  setRequestedImageResponse,
} from "./codex_markdown.steps";

// Step bindings for the phase-8 FE ADD rows about installability and
// Codex-generated images: the web manifest, the service worker, and the
// generated-image route, proved through the real browser against the real
// server.

const { Given, Then, When } = createBdd();

// E2E bindings for the phase-8 FE ADD rows about installability and
// Codex-generated images:
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: Codex-generated images show inline in the reply
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: The web manifest names Beaver Nest as a standalone app with two icons
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: The service worker precaches the shell and drops the old cache
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: Every image answer is private-cached and sandboxed
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: A signed-in visitor can fetch a generated image
function escapeRegExp(text: string): string {
  return text.replaceAll(/[.*+?^${}()|[\]\\]/gu, "\\$&");
}

// --- Web manifest (BN-PWA-02) -------------------------------------------------

Then(
  "the web manifest names Beaver Nest as a standalone app",
  async ({ page }) => {
    const response = await page.request.get("/manifest.webmanifest");
    expect(response.status()).toBe(200);
    const manifest = (await response.json()) as {
      display: string;
      name: string;
      short_name: string;
      start_url: string;
    };
    expect(manifest.name).toBe("Beaver Nest");
    expect(manifest.short_name).toBe("Beaver Nest");
    expect(manifest.display).toBe("standalone");
    expect(manifest.start_url).toBe("/");
  },
);

Then("each manifest icon loads", async ({ page }) => {
  const response = await page.request.get("/manifest.webmanifest");
  const manifest = (await response.json()) as { icons: { src: string }[] };
  expect(manifest.icons).toHaveLength(2);
  for (const icon of manifest.icons) {
    // eslint-disable-next-line no-await-in-loop -- two small icon fetches run in order so a failure names its icon.
    const iconResponse = await page.request.get(icon.src);
    expect(iconResponse.status()).toBe(200);
  }
});

// --- Service worker (BN-PWA-03) -------------------------------------------------

let workerResponse: APIResponse | undefined;

function workerBody(): Promise<string> {
  if (workerResponse === undefined) {
    throw new Error(
      "The scenario has not requested the service worker script.",
    );
  }
  return workerResponse.text();
}

When("a visitor requests the service worker script", async ({ page }) => {
  workerResponse = await page.request.get("/service-worker.js");
  expect(workerResponse.status()).toBe(200);
});

Then(
  "the worker precaches the manifest, app CSS, app JS and both icons under {string}",
  async ({ page: _page }, cache: string) => {
    const body = await workerBody();
    expect(body).toContain(`CACHE_NAME = "${cache}"`);
    for (const entry of [
      "/manifest.webmanifest",
      "/assets/css/app.css",
      "/assets/js/app.js",
      "/images/beaver-nest-192.png",
      "/images/beaver-nest-512.png",
    ]) {
      expect(body).toContain(`"${entry}"`);
    }
    expect(body).toContain("cache.addAll(APP_SHELL)");
  },
);

Then(
  "the worker never precaches {string}",
  async ({ page: _page }, routePath: string) => {
    const body = await workerBody();
    const shell = /const APP_SHELL = \[(.*?)\];/su.exec(body)?.[1] ?? "";
    expect(shell).not.toContain(`"${routePath}"`);
  },
);

Then(
  "activating the worker deletes every other cache name",
  async ({ page }) => {
    // The scenario only used page.request so far, leaving the page on
    // about:blank, which has no Cache Storage or service worker. Open a
    // same-origin document first. It is the manifest, not an app page: an app
    // page registers this same worker on load, and that earlier activation
    // would finish before the old cache below exists, so nothing would delete it.
    await page.goto("/manifest.webmanifest");
    await page.evaluate(async () => {
      await caches.delete("beaver-nest-shell-v1");
      const oldCache = await caches.open("beaver-nest-shell-v1");
      await oldCache.put("/old-shell-entry", new Response("old"));
      await navigator.serviceWorker.register("/service-worker.js");
    });
    await expect
      .poll(() => page.evaluate(() => caches.keys()), { timeout: 15_000 })
      .toEqual(["beaver-nest-shell-v2"]);
    const entries = await page.evaluate(async () => {
      const cache = await caches.open("beaver-nest-shell-v2");
      return (await cache.keys()).map(
        (request) => new URL(request.url).pathname,
      );
    });
    expect([...entries].toSorted()).toEqual(
      [
        "/assets/css/app.css",
        "/assets/js/app.js",
        "/images/beaver-nest-192.png",
        "/images/beaver-nest-512.png",
        "/manifest.webmanifest",
      ].toSorted(),
    );
    expect(entries).not.toContain("/");
    await page.evaluate(async () => {
      const registrations = await navigator.serviceWorker.getRegistrations();
      await Promise.all(
        registrations.map((registration) => registration.unregister()),
      );
      await caches.delete("beaver-nest-shell-v2");
    });
  },
);

// --- Codex-generated images (BN-CHAT-30, BN-HTTP-13/14) --------------------------

const GENERATED_THREAD = "abcdef12-3456";
const GENERATED_ROUTE = "/chat/generated-images/";
const PNG_BYTES = Buffer.from([
  0x89,
  0x50,
  0x4e,
  0x47,
  0x0d,
  0x0a,
  0x1a,
  0x0a,
  ...Buffer.from("e2e generated image"),
]);
const JPEG_BYTES = Buffer.from([
  0xff,
  0xd8,
  0xff,
  0xe0,
  ...Buffer.from("e2e generated photo"),
]);

function generatedImageDir(): string {
  return path.join(homedir(), ".codex", "generated_images", GENERATED_THREAD);
}

When("the Codex image reply completes", async ({ page }) => {
  const reply = page.locator("[data-role=assistant-message]").last();
  await expect(reply).toHaveAttribute("data-streaming", "false", {
    timeout: 20_000,
  });
  await expect(reply.locator("img")).toHaveCount(1);
});

Then(
  "the latest Codex reply shows the generated image {string} inline",
  async ({ page }, file: string) => {
    const image = page
      .locator("[data-role=assistant-message]")
      .last()
      .locator("img");
    await expect(image).toHaveCount(1);
    await expect(image).toHaveAttribute(
      "src",
      new RegExp(`/chat/generated-images/.+/${escapeRegExp(file)}$`, "u"),
    );
  },
);

Then("the family room shows the same reference as text", async ({ page }) => {
  await openFamilyChatRoom(page);
  await sendThroughComposer(
    page,
    `![Generated image](codex-image:${GENERATED_THREAD}/exec-fixture-image.png)`,
  );
  const row = page.locator('[data-role="family-chat-message"]', {
    hasText: "[image not shown: Generated image]",
  });
  await expect(row).toHaveCount(1);
  await expect(row.locator("img")).toHaveCount(0);
});

Given(
  "a generated image {string} is saved",
  ({ page: _page }, file: string) => {
    mkdirSync(generatedImageDir(), { recursive: true });
    writeFileSync(path.join(generatedImageDir(), file), PNG_BYTES);
  },
);

Given(
  "a generated image {string} holding JPEG bytes is saved",
  ({ page: _page }, file: string) => {
    mkdirSync(generatedImageDir(), { recursive: true });
    writeFileSync(path.join(generatedImageDir(), file), JPEG_BYTES);
  },
);

Given("no generated image is saved", () => {
  rmSync(path.join(generatedImageDir(), "exec-absent.png"), { force: true });
});

Given("the repository holds its logo", async ({ page }) => {
  const response = await page.request.get(
    `/chat/images/${encodeURIComponent("apps/bnest-app/priv/static/images/beaver-nest-logo.png")}`,
    { maxRedirects: 0 },
  );
  expect(response.status()).toBe(200);
});

When(
  "the visitor requests the generated image {string}",
  async ({ page }, file: string) => {
    setRequestedImageResponse(
      await page.request.get(`${GENERATED_ROUTE}${GENERATED_THREAD}/${file}`, {
        maxRedirects: 0,
      }),
    );
  },
);

When(
  "the visitor requests the generated image {string} as one encoded segment",
  async ({ page }, file: string) => {
    setRequestedImageResponse(
      await page.request.get(
        `${GENERATED_ROUTE}${encodeURIComponent(`${GENERATED_THREAD}/${file}`)}`,
        { maxRedirects: 0 },
      ),
    );
  },
);

Then("the image answer is private-cached and sandboxed", ({ page: _page }) => {
  const headers = requestedImageResponse().headers();
  expect(headers["cache-control"]).toBe("private, max-age=60");
  expect(headers["content-security-policy"]).toBe(
    "default-src 'none'; sandbox",
  );
});

Then("the image answer echoes no request header", () => {
  const response = requestedImageResponse();
  const values = Object.values(response.headers());
  expect(
    values.some((value) => value.includes(response.url())),
    `a response header echoes the request URL ${response.url()}`,
  ).toBe(false);
});

Then(
  "the image response is an empty not found response",
  async ({ page: _page }) => {
    const response = requestedImageResponse();
    expect(response.status()).toBe(404);
    expect(await response.text()).toBe("");
  },
);
