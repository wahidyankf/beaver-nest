import { expect, type Page } from "@playwright/test";

// A touch pointer for the layout scenarios: Chromium reports `(pointer: coarse)` only when touch emulation is on, and the
// media override alone does not change the primary pointer. Shared by the Codex and the Family Chat layout bindings.

/** The primary and any pointer are coarse, and hovering is not available. */
export async function emulateTouchPointer(page: Page): Promise<void> {
  const session = await page.context().newCDPSession(page);
  // Touch emulation makes a desktop browser report a coarse primary pointer; the media override alone does not.
  await session.send("Emulation.setTouchEmulationEnabled", {
    enabled: true,
    maxTouchPoints: 5,
  });
  await session.send("Emulation.setEmulatedMedia", {
    features: [
      { name: "pointer", value: "coarse" },
      { name: "any-pointer", value: "coarse" },
      { name: "hover", value: "none" },
      { name: "any-hover", value: "none" },
    ],
  });
  const coarse = await page.evaluate(
    () => matchMedia("(pointer: coarse)").matches,
  );
  expect(coarse, "the touch pointer is not in effect").toBe(true);
}
