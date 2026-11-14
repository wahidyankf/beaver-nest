import { expect, type Page } from "@playwright/test";
import { createBdd } from "playwright-bdd";

import {
  HINT,
  settle,
  TEXTAREA,
  visitorMessageCount,
  emulateFinePointer,
} from "../support/chat-ui-steps";
import { emulateTouchPointer } from "../support/touch-pointer";
import { latestReply, openChatAsAdmin } from "../support/codex-diagrams";
import { instanceIdentities } from "../support/instance-identities";
import { login } from "../support/authentication";

const { Given, Then, When } = createBdd();

// --- Pointer and send shortcut hint (shared with Family Chat) ---------------------------------

Given("the visitor's pointer is a fine pointer", async ({ page }) => {
  await emulateFinePointer(page);
});

// Touch emulation can be switched on while the page is open. The reverse (touch to fine) cannot be emulated: once
// touch emulation is on, the media override does not make the page report a fine pointer.
When("the visitor connects a touch pointer", async ({ page }) => {
  await emulateTouchPointer(page);
});

Then(
  "the send shortcut hint reads {string}",
  async ({ page }, text: string) => {
    // Each room has one hint. The wording the visitor sees is the span the stylesheet shows for this pointer.
    const hint = page.locator(HINT).first();
    await expect(hint).toBeAttached();
    const shown = await hint
      .locator(".hint-keyboard, .hint-touch")
      .evaluateAll((spans) =>
        spans
          .filter((span) => getComputedStyle(span).display !== "none")
          .map((span) => span.textContent?.trim() ?? ""),
      );
    expect(shown, "the hint wording a visitor sees").toEqual([text]);
  },
);

Then("the send shortcut hint takes no row", async ({ page }) => {
  // A touch pointer takes no visible row: the hint is a one-pixel box. The box still describes the textarea with the
  // Send-button wording, because an accessible description skips hidden children.
  const hint = page.locator(HINT).first();
  const box = await hint.boundingBox();
  expect(
    box === null || (box.width <= 1 && box.height <= 1),
    `the hint is ${JSON.stringify(box)}`,
  ).toBe(true);
  await expect(
    page.locator("textarea[aria-describedby]").first(),
  ).toHaveAccessibleDescription("Shift+Enter to send");
});

Given("the visitor's system prefers a dark color scheme", async ({ page }) => {
  await page.emulateMedia({ colorScheme: "dark" });
});

When("an approved admin opens {string}", async ({ page }, path: string) => {
  await login(page, instanceIdentities().admin);
  await page.goto(path);
  // Each page type has its own ready state: the Codex chat is a LiveView that connects, the Family room renders its
  // composer from its template, and the home page shows its logo.
  if (path === "/chat") {
    await expect(page.locator("[data-phx-main]")).toHaveClass(/phx-connected/u);
  } else if (path.startsWith("/family-chat/")) {
    await expect(page.locator("#family-chat-message-input")).toBeVisible();
  } else {
    await expect(page.getByAltText("Beaver Nest logo")).toBeVisible();
  }
});

Then("the page has no color theme control", async ({ page }) => {
  await expect(page.getByRole("button", { name: /theme/iu })).toHaveCount(0);
  await expect(
    page.locator(
      "[data-theme-toggle], .theme-dock, .chat-theme-control, .family-chat-theme, .home-theme-control",
    ),
  ).toHaveCount(0);
});

Then("the page background is light", async ({ page }) => {
  // The first element with a painted background decides the page colour; a transparent one defers to its parent.
  // No default: a page where nothing paints a background fails here, and white is never assumed.
  const rgba = await page.evaluate(() => {
    for (const element of [document.body, document.documentElement]) {
      const value = getComputedStyle(element).backgroundColor;
      if (value !== "rgba(0, 0, 0, 0)" && value !== "transparent") return value;
    }
    return null;
  });
  expect(rgba, "no element paints a page background").not.toBeNull();
  // `expect` above fails the step on null; this string only narrows the type for the reads below.
  const painted = rgba ?? "";
  const [red, green, blue] = (painted.match(/\d+(?:\.\d+)?/gu) ?? []).map(
    Number,
  );
  expect(
    Math.min(red ?? 0, green ?? 0, blue ?? 0),
    `the page background is ${painted}`,
  ).toBeGreaterThanOrEqual(200);
});

// --- Codex message box keys (chat.feature, Rule "Codex message box keys follow the visitor's pointer") ---

let codexSendsBefore = 0;
let codexRepliesBefore = 0;

Given("the Codex message box has keyboard focus", async ({ page }) => {
  await openChatAsAdmin(page);
  await page.locator(TEXTAREA).focus();
  await expect(page.locator(TEXTAREA)).toBeFocused();
});

// The draft each page was given, so "a new line after its draft" compares with what this scenario typed.
const codexDraftOf = new WeakMap<Page, string>();

Given(
  "the Codex message box holds {string}",
  async ({ page }, draft: string) => {
    codexDraftOf.set(page, draft);
    await page.locator(TEXTAREA).fill(draft);
  },
);

Given("Codex is {string}", async ({ page }, state: string) => {
  if (state === "idle") return;
  if (state !== "replying") throw new Error(`unknown Codex state ${state}`);
  // The reply holds while it streams, and the box is read-only until it ends. The draft is put back after the send,
  // so the key press happens while the reply is still streaming.
  const draft = await page.locator(TEXTAREA).inputValue();
  await page.locator(TEXTAREA).fill("Stream unfinished Markdown");
  await page.getByRole("button", { name: "Send" }).click();
  await expect(latestReply(page)).toHaveAttribute("data-streaming", "true", {
    timeout: 20_000,
  });
  await page.locator(TEXTAREA).evaluate((element, value) => {
    (element as HTMLTextAreaElement).value = value;
  }, draft);
});

// The box is read-only while the reply streams. It keeps keyboard focus, and it takes text again when the reply lands.
// A reply must appear first: without that wait, a send that never reached Codex would pass at once, because nothing
// would be streaming.
Given("Codex finishes the reply", async ({ page }) => {
  await expect
    .poll(() => page.locator("[data-role=assistant-message]").count(), {
      timeout: 30_000,
    })
    .toBeGreaterThan(codexRepliesBefore);
  await expect(latestReply(page)).not.toHaveAttribute(
    "data-streaming",
    "true",
    {
      timeout: 30_000,
    },
  );
  await expect(page.locator(TEXTAREA)).not.toHaveAttribute("readonly");
});

Then("keyboard focus is in the Codex message box", async ({ page }) => {
  await expect(page.locator(TEXTAREA)).toBeFocused();
});

// A pointer press on the Send button, as the visitor makes it. The press must not move keyboard focus off the box.
When("the visitor presses Send with a pointer", async ({ page }) => {
  codexSendsBefore = await visitorMessageCount(page);
  codexRepliesBefore = await page
    .locator("[data-role=assistant-message]")
    .count();
  await page.locator("#chat-composer-form .send-button").click();
});

When(
  "the visitor presses {string} in the Codex message box",
  async ({ page }, name: string) => {
    codexSendsBefore = await visitorMessageCount(page);
    codexRepliesBefore = await page
      .locator("[data-role=assistant-message]")
      .count();
    // Playwright names a chord as "Shift+Enter"; the browser applies the key's own default action.
    await page.locator(TEXTAREA).press(name);
  },
);

When(
  "the visitor confirms a composition with {string} in the Codex message box",
  async ({ page }, name: string) => {
    codexSendsBefore = await visitorMessageCount(page);
    // A key press that confirms an IME composition carries isComposing, and the page must not send on it.
    await page.locator(TEXTAREA).dispatchEvent("keydown", {
      key: name.replace(/^Shift\+/u, ""),
      shiftKey: name.startsWith("Shift+"),
      isComposing: true,
    });
  },
);

Then("the message box shows {string}", async ({ page }, shown: string) => {
  const box = page.locator(TEXTAREA);
  if (shown === "an empty box") {
    await expect(box).toHaveValue("");
    return;
  }
  if (shown === "a new line after its draft") {
    const draft = codexDraftOf.get(page);
    expect(draft, "the scenario gave the box no draft").toBeDefined();
    await expect(box).toHaveValue(`${draft}\n`);
    return;
  }
  throw new Error(`unknown box state ${shown}`);
});

Then("nothing is sent to Codex", async ({ page }) => {
  await settle(page);
  expect(await visitorMessageCount(page)).toBe(codexSendsBefore);
});

Then("Codex receives {int} message sends", async ({ page }, sends: number) => {
  if (sends === 0) {
    await settle(page);
    expect(await visitorMessageCount(page)).toBe(codexSendsBefore);
    return;
  }
  await expect
    .poll(() => visitorMessageCount(page), { timeout: 10_000 })
    .toBe(codexSendsBefore + sends);
});
