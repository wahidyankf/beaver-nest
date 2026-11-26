import { mkdirSync } from "node:fs";
import path from "node:path";
import { expect, type Page } from "@playwright/test";
import { createBdd } from "playwright-bdd";

// Step bindings for the Multiple chat conversations rule of
// specs/apps/bnest/app-fe/behaviours/chat.feature: the rail the server renders,
// with one entry per conversation. On a phone the rail is a drawer behind the
// Chats toggle, so every rail step opens the drawer first when the toggle is
// visible; on desktop the toggle is hidden and the steps use the sidebar.
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

async function drawerToggleVisible(page: Page): Promise<boolean> {
  const toggle = page.locator(DRAWER_TOGGLE);
  return (await toggle.count()) > 0 && (await toggle.isVisible());
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
  // The New-chat tap closes the drawer (conversation_drawer.js), so this step leaves it closed: the entry stays in
  // the rail for later rail steps, which reopen the drawer themselves, and the composer stays reachable. Counting
  // instead of checking visibility keeps the assertion true in the closed drawer and in the desktop sidebar alike.
  await expect(
    page
      .locator("[data-role=select-conversation]")
      .filter({ hasText: "New chat" }),
  ).toHaveCount(1);
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
  if (await drawerToggleVisible(page)) {
    await expect(page.locator(DRAWER)).toHaveClass(/is-open/u);
    await expect(page.locator(DRAWER_TOGGLE)).toHaveAttribute(
      "aria-expanded",
      "true",
    );
    await saveDrawerShot(page, "drawer-open");
  } else {
    await expect(page.locator(DRAWER)).toBeVisible();
    await saveDrawerShot(page, "drawer-desktop-sidebar");
  }
});

When("the visitor closes the conversation drawer", async ({ page }) => {
  if (await drawerToggleVisible(page)) {
    await page.locator(DRAWER_CLOSE).click();
    await expect(page.locator(DRAWER)).not.toHaveClass(/is-open/u);
  }
});

Then("the conversation drawer is open", async ({ page }) => {
  if (await drawerToggleVisible(page)) {
    await expect(page.locator(DRAWER)).toHaveClass(/is-open/u);
    await expect(page.locator(DRAWER_TOGGLE)).toHaveAttribute(
      "aria-expanded",
      "true",
    );
  } else {
    await expect(page.locator(DRAWER)).toBeVisible();
  }
});

Then("the conversation drawer is closed", async ({ page }) => {
  if (await drawerToggleVisible(page)) {
    await expect(page.locator(DRAWER)).not.toHaveClass(/is-open/u);
    await expect(page.locator(DRAWER_TOGGLE)).toHaveAttribute(
      "aria-expanded",
      "false",
    );
  }
});

Then(
  "the Chats toggle is at least 44 pixels across and tall",
  async ({ page }) => {
    if (await drawerToggleVisible(page)) {
      const box = await page.locator(DRAWER_TOGGLE).boundingBox();
      if (box === null) throw new Error("the Chats toggle has no box");
      expect(box.width).toBeGreaterThanOrEqual(44);
      expect(box.height).toBeGreaterThanOrEqual(44);
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
