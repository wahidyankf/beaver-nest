import { expect, type APIResponse, type Page } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import { makePng } from "../support/family-chat-markdown";

// Codex replies are rendered as Markdown inside `data-role=assistant-message`; the newest one is the
// reply a scenario is about. The canned replies come from `codex_fixture_replies.json`, which the
// fixture runner sends, so the expectations below name the text the runner really sends.
const { Before, Then, When } = createBdd();

const IMAGE_ROUTE = "/chat/images/";

// A scenario tagged @remote-image loads a third-party image. The browser is never allowed to reach the internet for
// it: the context answers the request with this 1200x60 PNG. It is wider than a phone, so a layout scenario has a
// picture that could overflow; the scenarios that only need a loaded picture still see one (naturalWidth > 0).
const REMOTE_IMAGE_PATTERN = "https://images.example.test/**";
const WIDE_PNG = makePng(1200, 60);

// The route belongs to the browser context, so it covers every page the scenario opens. It is registered before the
// first page loads, so no request for the host leaves the browser.
Before("@remote-image", async ({ context }) => {
  await context.route(REMOTE_IMAGE_PATTERN, (route) =>
    route.fulfill({ status: 200, contentType: "image/png", body: WIDE_PNG }),
  );
});

// The last image response a scenario requested. A scenario runs one step after another in its worker.
let imageResponse: APIResponse | undefined;

function latestReply(page: Page) {
  return page.locator("[data-role=assistant-message]").last();
}

function requestedImageResponse(): APIResponse {
  if (imageResponse === undefined) {
    throw new Error("The scenario has not requested a repository image.");
  }

  return imageResponse;
}

When("Codex streams the first part of the reply", async ({ page }) => {
  // The fixture runner holds this partial reply for `holdMs` after the prefix (10 s for the streaming replies,
  // see codex_fixture_replies.json). The Then steps that read the streaming state must finish inside that hold, so
  // the hold is long enough for a loaded host; a shorter one made them race it. The first update counts the prefix.
  await expect(latestReply(page)).toHaveAttribute("data-streaming", "true");
  await expect(latestReply(page)).toHaveAttribute(
    "data-update-count",
    /^[1-9][0-9]*$/u,
  );
});

When("Codex streams the rest of the reply", async ({ page }) => {
  // The reply completes when its hold ends, which is a known point after the streaming Then steps.
  // The wait is bounded by that hold plus a margin, not by a race with the page.
  await expect(latestReply(page)).toHaveAttribute("data-streaming", "false", {
    timeout: 20_000,
  });
});

Then("the latest Codex reply is still streaming", async ({ page }) => {
  await expect(latestReply(page)).toHaveAttribute("data-streaming", "true");
});

Then("the latest Codex reply is complete", async ({ page }) => {
  await expect(latestReply(page)).toHaveAttribute("data-streaming", "false");
});

Then(
  "the latest Codex reply contains a {string} element with the text {string}",
  async ({ page }, element: string, text: string) => {
    await expect(
      latestReply(page).locator(element, { hasText: text }).first(),
    ).toBeAttached();
  },
);

Then(
  "the latest Codex reply contains no {string} element",
  async ({ page }, element: string) => {
    await expect(latestReply(page).locator(element)).toHaveCount(0);
  },
);

Then(
  "the latest Codex reply shows the text {string}",
  async ({ page }, text: string) => {
    await expect(latestReply(page)).toContainText(text);
  },
);

Then(
  "the latest Codex reply shows the text {string} without a link",
  async ({ page }, text: string) => {
    await expect(latestReply(page)).toContainText(text);
    await expect(latestReply(page).locator("a", { hasText: text })).toHaveCount(
      0,
    );
  },
);

Then(
  "the latest Codex reply does not contain the text {string}",
  async ({ page }, text: string) => {
    await expect(latestReply(page)).not.toContainText(text);
  },
);

Then(
  "the latest Codex reply has no link whose address starts with {string}",
  async ({ page }, prefix: string) => {
    await expect(
      latestReply(page).locator(`a[href^=${JSON.stringify(prefix)}]`),
    ).toHaveCount(0);
  },
);

Then(
  "the latest Codex reply links {string} to {string}",
  async ({ page }, label: string, address: string) => {
    await expect(
      latestReply(page).locator("a", { hasText: label }),
    ).toHaveAttribute("href", address);
  },
);

Then(
  "the link {string} in the latest Codex reply opens in a new tab without sharing the page",
  async ({ page }, label: string) => {
    const link = latestReply(page).locator("a", { hasText: label });

    await expect(link).toHaveAttribute("target", "_blank");

    const rel = ((await link.getAttribute("rel")) ?? "").split(/\s+/u);
    expect(rel).toEqual(expect.arrayContaining(["noopener", "noreferrer"]));
  },
);

Then(
  "the latest Codex reply shows two checked and two unchecked task checkboxes",
  async ({ page }) => {
    await expect(
      latestReply(page).locator("input[type=checkbox]:checked"),
    ).toHaveCount(2);
    await expect(
      latestReply(page).locator("input[type=checkbox]:not(:checked)"),
    ).toHaveCount(2);
  },
);

Then(
  "the latest Codex reply shows the repository image {string}",
  async ({ page }, path: string) => {
    const image = latestReply(page).locator("img").first();

    await expect(image).toHaveAttribute("src", /^\/chat\/images\//u);

    const src = (await image.getAttribute("src")) ?? "";
    expect(decodeURIComponent(src.slice(IMAGE_ROUTE.length))).toBe(path);

    // The browser decoded the image, not only the markup that names it.
    await expect
      .poll(() =>
        image.evaluate((element) => (element as HTMLImageElement).naturalWidth),
      )
      .toBeGreaterThan(0);
  },
);

// An inline image is a real `img` with its alt text, outside any link, and the browser decoded it: a decoded image
// has a width. An image in a link would be a link, not an inline image.
Then(
  "the latest Codex reply shows an inline image with the alt text {string}",
  async ({ page }, alt: string) => {
    const image = latestReply(page).getByAltText(alt, { exact: true });

    await expect(image).toHaveCount(1);
    await expect(
      latestReply(page).locator("a").getByAltText(alt, { exact: true }),
    ).toHaveCount(0);
    await expect
      .poll(() =>
        image.evaluate((element) => (element as HTMLImageElement).naturalWidth),
      )
      .toBeGreaterThan(0);
  },
);

Then(
  "the latest Codex reply loads the inline image {string} from {string}",
  async ({ page }, alt: string, address: string) => {
    const image = latestReply(page).getByAltText(alt, { exact: true });

    await expect(image).toHaveAttribute("src", address);
    await expect(
      latestReply(page).locator("a").getByAltText(alt, { exact: true }),
    ).toHaveCount(0);
    await expect
      .poll(() =>
        image.evaluate((element) => (element as HTMLImageElement).naturalWidth),
      )
      .toBeGreaterThan(0);
  },
);

When(
  "the visitor requests the repository image {string}",
  async ({ page }, path: string) => {
    // The whole path is one encoded segment, so the browser keeps `..` and `/` in the request.
    // Redirects are not followed: a signed-out visitor's answer is the login redirect itself.
    imageResponse = await page.request.get(
      `${IMAGE_ROUTE}${encodeURIComponent(path)}`,
      { maxRedirects: 0 },
    );
  },
);

Then(
  "the image response has status {int}",
  ({ page: _page }, status: number) => {
    expect(requestedImageResponse().status()).toBe(status);
  },
);

Then(
  "the image response has content type {string}",
  ({ page: _page }, type: string) => {
    const contentType =
      requestedImageResponse().headers()["content-type"] ?? "";
    expect(contentType.split(";")[0]?.trim()).toBe(type);
  },
);

Then(
  "the image response redirects to {string}",
  ({ page: _page }, location: string) => {
    const response = requestedImageResponse();
    expect(response.status()).toBe(302);
    expect((response.headers()["location"] ?? "").startsWith(location)).toBe(
      true,
    );
  },
);
