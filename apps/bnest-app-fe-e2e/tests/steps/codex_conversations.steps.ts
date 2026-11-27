import { mkdirSync } from "node:fs";
import path from "node:path";
import { expect, type Page } from "@playwright/test";
import { createBdd } from "playwright-bdd";

// Step bindings for the Multiple chat conversations rule of
// specs/apps/bnest/app-fe/behaviours/chat.feature: the rail the server renders,
// with one entry per conversation. On a phone the rail is a drawer behind the
// Chats toggle, so every rail step opens the drawer first when the toggle is
// visible; on desktop the toggle is hidden and the steps use the sidebar.
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: A visitor starts a second chat from the conversation rail
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: A visitor switches between two chats and each keeps its messages
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: A visitor deletes a chat from the conversation rail
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: A visitor renames a chat from the conversation rail
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: A visitor keeps every chat after a reload
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: A visitor opens and closes the conversation drawer
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: Opening a conversation from the drawer closes the drawer
// @scenario specs/apps/bnest/app-fe/behaviours/chat.feature: A phone visitor reaches the newest message and the composer from the drawer
const { Then, When } = createBdd();

const DRAWER_TOGGLE = "[data-role=conversations-toggle]";
const DRAWER = "[data-role=conversation-rail]";
const DRAWER_CLOSE = "[data-role=conversation-close]";

/**
 * Opens the conversation drawer on a phone, where the rail hides behind the Chats toggle. A drawer that is already
 * open stays open, and a desktop page without a visible toggle is left alone.
 */
async function openDrawerIfCollapsed(page: Page): Promise<void> {
  const toggle = page.locator(DRAWER_TOGGLE);
  if (
    (await toggle.count()) > 0 &&
    (await toggle.isVisible()) &&
    (await toggle.getAttribute("aria-expanded")) === "false"
  ) {
    await toggle.click();
    await expect(page.locator(DRAWER)).toHaveClass(/is-open/u);
  }
}

// The stylesheet shows the Chats toggle, and hides the desktop chrome, only where this query matches (app.css). The
// drawer steps read the viewport through the same query and assert the outcome that viewport requires, so a phone
// that hid its toggle fails here instead of passing.
const PHONE_QUERY = "(max-width: 42rem)";

function isPhoneViewport(page: Page): Promise<boolean> {
  return page.evaluate(
    (query) => window.matchMedia(query).matches,
    PHONE_QUERY,
  );
}

// On a wide screen the Chats toggle is absent and the rail is the desktop sidebar, always shown.
async function expectDesktopSidebar(page: Page): Promise<void> {
  await expect(page.locator(DRAWER_TOGGLE)).toBeHidden();
  await expect(page.locator(DRAWER)).toBeVisible();
}

// A drawer render for the delivery record, saved only when the run asks for screenshots.
async function saveDrawerShot(page: Page, name: string): Promise<void> {
  const shots = process.env["BNEST_SCREENSHOT_DIR"];
  if (!shots) return;
  mkdirSync(shots, { recursive: true });
  const viewport = page.viewportSize();
  await page.screenshot({
    path: path.join(
      shots,
      `${name}-${viewport?.width ?? 0}x${viewport?.height ?? 0}.png`,
    ),
  });
}

When("the visitor starts a new chat", async ({ page }) => {
  await openDrawerIfCollapsed(page);
  await page.getByRole("button", { name: "New chat" }).click();
  // On a phone the New-chat tap closes the drawer (conversation_drawer.js), so the step reopens it and asserts that
  // the new entry is visible in the rail. It then closes the drawer again, as the tap left it, so the composer stays
  // reachable. On the desktop sidebar the helper leaves the rail alone and the close is skipped.
  await openDrawerIfCollapsed(page);
  await expect(
    page
      .locator("[data-role=select-conversation]")
      .filter({ hasText: "New chat" }),
  ).toBeVisible();
  if (await isPhoneViewport(page)) {
    await page.locator(DRAWER_CLOSE).click();
    await expect(page.locator(DRAWER)).not.toHaveClass(/is-open/u);
  }
});

Then(
  "the conversation list shows {string}",
  async ({ page }, title: string) => {
    await openDrawerIfCollapsed(page);
    await expect(
      page.locator("[data-role=conversation-item]").filter({ hasText: title }),
    ).toBeVisible();
  },
);

Then(
  "the conversation list does not show {string}",
  async ({ page }, title: string) => {
    await openDrawerIfCollapsed(page);
    await expect(
      page.locator("[data-role=conversation-item]").filter({ hasText: title }),
    ).toHaveCount(0);
  },
);

When(
  "the visitor opens the conversation {string}",
  async ({ page }, title: string) => {
    await openDrawerIfCollapsed(page);
    await page
      .locator("[data-role=select-conversation]")
      .filter({ hasText: title })
      .click();
    await expect(page).toHaveURL(/conversation=/u);
  },
);

When(
  "the visitor deletes the conversation {string}",
  async ({ page }, title: string) => {
    await openDrawerIfCollapsed(page);
    const item = page
      .locator("[data-role=conversation-item]")
      .filter({ hasText: title });
    // The rail delete is an icon button: its accessible name carries the
    // action, so the locator keys off the stable data-role hook instead.
    await item.locator("[data-role=delete-conversation]").click();
    await expect(item).toHaveCount(0);
  },
);

When(
  "the visitor renames the conversation {string} to {string}",
  async ({ page }, title: string, next: string) => {
    await openDrawerIfCollapsed(page);
    const item = page
      .locator("[data-role=conversation-item]")
      .filter({ hasText: title });
    await item.locator("[data-role=rename-toggle]").click();
    await expect(item.locator("[data-role=rename-input]")).toBeVisible();
    await saveDrawerShot(page, "drawer-rename");
    await item.locator("[data-role=rename-input]").fill(next);
    await item.locator("[data-role=rename-submit]").click();
    await expect(
      page.locator("[data-role=conversation-item]").filter({ hasText: next }),
    ).toBeVisible();
  },
);

When("the visitor opens the conversation drawer", async ({ page }) => {
  await openDrawerIfCollapsed(page);
  if (await isPhoneViewport(page)) {
    await expect(page.locator(DRAWER_TOGGLE)).toBeVisible();
    await expect(page.locator(DRAWER)).toHaveClass(/is-open/u);
    await expect(page.locator(DRAWER_TOGGLE)).toHaveAttribute(
      "aria-expanded",
      "true",
    );
    await saveDrawerShot(page, "drawer-open");
  } else {
    await expectDesktopSidebar(page);
    await saveDrawerShot(page, "drawer-desktop-sidebar");
  }
});

When("the visitor closes the conversation drawer", async ({ page }) => {
  if (await isPhoneViewport(page)) {
    await expect(page.locator(DRAWER_TOGGLE)).toBeVisible();
    await page.locator(DRAWER_CLOSE).click();
    await expect(page.locator(DRAWER)).not.toHaveClass(/is-open/u);
  } else {
    await expectDesktopSidebar(page);
  }
});

Then("the conversation drawer is open", async ({ page }) => {
  if (await isPhoneViewport(page)) {
    await expect(page.locator(DRAWER_TOGGLE)).toBeVisible();
    await expect(page.locator(DRAWER)).toHaveClass(/is-open/u);
    await expect(page.locator(DRAWER_TOGGLE)).toHaveAttribute(
      "aria-expanded",
      "true",
    );
  } else {
    await expectDesktopSidebar(page);
  }
});

Then("the conversation drawer is closed", async ({ page }) => {
  if (await isPhoneViewport(page)) {
    await expect(page.locator(DRAWER_TOGGLE)).toBeVisible();
    await expect(page.locator(DRAWER)).not.toHaveClass(/is-open/u);
    await expect(page.locator(DRAWER_TOGGLE)).toHaveAttribute(
      "aria-expanded",
      "false",
    );
  } else {
    await expectDesktopSidebar(page);
  }
});

Then(
  "the Chats toggle is at least 44 pixels across and tall",
  async ({ page }) => {
    if (await isPhoneViewport(page)) {
      await expect(page.locator(DRAWER_TOGGLE)).toBeVisible();
      const box = await page.locator(DRAWER_TOGGLE).boundingBox();
      if (box === null) throw new Error("the Chats toggle has no box");
      expect(box.width).toBeGreaterThanOrEqual(44);
      expect(box.height).toBeGreaterThanOrEqual(44);
    } else {
      await expect(page.locator(DRAWER_TOGGLE)).toBeHidden();
    }
  },
);

When(
  "the visitor scrolls the conversation to the newest message",
  async ({ page }) => {
    const scroller = page.locator("#chat-conversation");
    await scroller.evaluate((element) => {
      element.scrollTop = element.scrollHeight;
    });
    // The scroll lands before the newest message is read.
    await expect
      .poll(() =>
        scroller.evaluate(
          (element) => element.scrollTop + element.clientHeight,
        ),
      )
      .toBeGreaterThanOrEqual(
        await scroller.evaluate((element) => element.scrollHeight - 1),
      );
    // A scrolled-to-bottom render for the delivery record, saved only when the run asks for screenshots.
    const shots = process.env["BNEST_SCREENSHOT_DIR"];
    if (shots) {
      mkdirSync(shots, { recursive: true });
      const viewport = page.viewportSize();
      await page.screenshot({
        path: path.join(
          shots,
          `drawer-scrolled-${viewport?.width ?? 0}x${viewport?.height ?? 0}.png`,
        ),
      });
    }
  },
);
