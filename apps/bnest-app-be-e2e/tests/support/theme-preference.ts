import type { Page } from "@playwright/test";

// The account's theme preference is stored per user and written only through PUT /preferences/theme (ADR 005 keeps it
// as inert storage: no page shows a theme control any more). Backend scenarios set it through that HTTP surface with
// the session's CSRF token, and read the stored value back from the test instance's record, never from a page.

export async function csrfToken(page: Page): Promise<string> {
  const token = await page
    .locator("meta[name='csrf-token']")
    .getAttribute("content");
  if (!token) throw new Error("The page carries no CSRF token");
  return token;
}

// The status the server answers. The page must already be loaded, so the CSRF token belongs to this session.
export async function putTheme(
  page: Page,
  theme: string,
  extraForm: Record<string, string> = {},
): Promise<number> {
  const response = await page.request.put("/preferences/theme", {
    form: { theme, ...extraForm },
    headers: { "x-csrf-token": await csrfToken(page) },
  });
  return response.status();
}
