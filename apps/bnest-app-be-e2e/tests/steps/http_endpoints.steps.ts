import { expect } from "@playwright/test";
import { createBdd } from "playwright-bdd";
import { login } from "../support/authentication";
import { currentIdentities, userIdFor } from "../support/instance-identities";
import { instanceRecordState } from "../support/instance-records";
import { liveProbe, type LiveReply } from "../support/test-isolation-probes";
import { putThemeAnswer } from "../support/theme-preference";

// E2E bindings for http_endpoints.feature (BN-HTTP-01, BN-HTTP-10, BN-HTTP-23, BN-HTTP-24). The refused-write
// scenario carries @e2e-exempt and needs nothing here: every seeded account has a valid role and the exact-origin
// SQLite store is healthy, so no exact-origin request yields its 403 or 409.
//
// @scenario specs/apps/bnest/app-be/behaviours/http_endpoints.feature: Liveness reports its status, revision, and slot
// @scenario specs/apps/bnest/app-be/behaviours/http_endpoints.feature: A theme change is saved or refused as invalid
// @scenario specs/apps/bnest/app-be/behaviours/http_endpoints.feature: A public static file is served without signing in
// @scenario specs/apps/bnest/app-be/behaviours/http_endpoints.feature: An unknown path gets the stock not found page, as HTML or JSON

const { Before, Given, Then, When } = createBdd();

// The harness boots one fixed pair (playwright.config.mts webServer.env), so the exact-origin liveness proof is that
// pair on every outline row; the row variance is proven at the unit and integration layers.
const bootRevision = "be-e2e";
const bootSlot = "blue";

// Facts one step leaves for a later step of the same scenario. It starts empty for every scenario.
type Carried = {
  media?: string;
  release?: { revision: string; slot: string };
  live?: LiveReply;
  saved?: string;
  theme?: string;
  themeAnswer?: { status: number; body: string };
  sessionless?: boolean;
  statics?: Map<string, string>;
  staticStatus?: number;
  staticMedia?: string;
  unknownStatus?: number;
  unknownJson?: unknown;
  unknownText?: string;
};

let carried: Carried = {};

Before(() => {
  carried = {};
});

function required<T>(value: T | undefined, what: string): T {
  if (value === undefined) throw new Error(`the scenario has no ${what}`);
  return value;
}

// The outline's unset marker maps through the same defaulting the unit layer proves.
function defaulted(value: string, fallback: string): string {
  return value === "(unset)" ? fallback : value;
}

function adminId(): string {
  return userIdFor(currentIdentities().admin.username);
}

function storedTheme(): string {
  const state = instanceRecordState("theme", adminId());
  if (!state.present) return "system";
  const theme = state.record["theme"];
  if (typeof theme !== "string")
    throw new Error("the stored theme preference holds no theme");
  return theme;
}

// --- Liveness reports its status, revision, and slot ---

Given(
  "the release names revision {string} and slot {string}",
  // eslint-disable-next-line no-empty-pattern
  ({}, revision: string, slot: string) => {
    carried.release = { revision, slot };
  },
);

When("a visitor fetches the liveness probe", async () => {
  carried.live = await liveProbe();
});

Then(
  "the probe answers live with revision {string} from slot {string}",
  // eslint-disable-next-line no-empty-pattern
  ({}, reported: string, reportedSlot: string) => {
    const live = required(carried.live, "liveness answer");
    const release = required(carried.release, "release naming");
    expect(live.status).toBe(200);
    expect(live.body).toMatchObject({
      status: "live",
      revision: bootRevision,
      slot: bootSlot,
    });
    expect(defaulted(release.revision, "development")).toBe(reported);
    expect(defaulted(release.slot, "standalone")).toBe(reportedSlot);
  },
);

Then(
  "the revision header carries {string}",
  // eslint-disable-next-line no-empty-pattern
  ({}, reported: string) => {
    const live = required(carried.live, "liveness answer");
    const release = required(carried.release, "release naming");
    expect(live.revisionHeader).toBe(bootRevision);
    expect(defaulted(release.revision, "development")).toBe(reported);
  },
);

// --- A theme change is saved or refused as invalid ---

Given("a visitor signed in as the scenario's owner", async ({ page }) => {
  await login(page, currentIdentities().admin);
});

Given("the owner saved theme {string}", async ({ page }, saved: string) => {
  carried.saved = saved;
  if (saved !== "(none)") {
    const { status } = await putThemeAnswer(page, saved);
    expect(status).toBe(204);
  }
});

When("the visitor saves theme {string}", async ({ page }, theme: string) => {
  carried.theme = theme;
  carried.themeAnswer = await putThemeAnswer(
    page,
    theme === "(empty)" ? "" : theme,
  );
});

Then(
  "the theme answer is {int} with body {string}",
  // eslint-disable-next-line no-empty-pattern
  ({}, status: number, body: string) => {
    const answer = required(carried.themeAnswer, "theme answer");
    expect(answer.status).toBe(status);
    expect(answer.body).toBe(body === "(empty)" ? "" : body);
  },
);

Then(
  "the stored theme is {string}",
  // eslint-disable-next-line no-empty-pattern
  ({}, stored: string) => {
    expect(storedTheme()).toBe(stored);
  },
);

// --- A public static file is served without signing in ---

Given("a visitor with no session", () => {
  // The When step below fetches through the `request` fixture, which carries
  // no cookies, so this Given only records that the fetch must stay anonymous.
  carried.sessionless = true;
});

When("the visitor fetches {string}", async ({ request }, path: string) => {
  expect(carried.sessionless).toBe(true);
  const response = await request.get(path);
  const statics = carried.statics ?? new Map<string, string>();
  statics.set(path, await response.text());
  carried.statics = statics;
  carried.staticStatus = response.status();
  carried.staticMedia = response.headers()["content-type"] ?? "";
});

Then(
  "the file answers 200 with its own {string} content",
  // eslint-disable-next-line no-empty-pattern
  ({}, media: string) => {
    expect(carried.staticStatus).toBe(200);
    expect(required(carried.staticMedia, "content type")).toContain(media);
    const statics = required(carried.statics, "fetched files");
    for (const body of statics.values()) {
      expect(body.length).toBeGreaterThan(0);
    }
    if (statics.size === 2) {
      const [first, second] = [...statics.values()];
      expect(first).not.toBe(second);
    }
  },
);

// --- An unknown path gets the stock not found page, as HTML or JSON ---

Given(
  "a visitor asking for {string}",
  // eslint-disable-next-line no-empty-pattern
  ({}, media: string) => {
    carried.media = media;
  },
);

When("the visitor opens the unknown path", async ({ page, request }) => {
  if (required(carried.media, "asked media").includes("json")) {
    const response = await request.get("/no/such/page", {
      headers: { accept: "application/json" },
    });
    carried.unknownStatus = response.status();
    carried.unknownJson = (await response.json()) as unknown;
  } else {
    const response = await page.goto("/no/such/page");
    if (response) {
      carried.unknownStatus = response.status();
      carried.unknownText = await response.text();
    }
  }
});

Then(
  "the unknown path answers 404 as {string}",
  // eslint-disable-next-line no-empty-pattern
  ({}, format: string) => {
    expect(carried.unknownStatus).toBe(404);
    expect(format).toBe(
      required(carried.media, "asked media").includes("json") ? "JSON" : "HTML",
    );
  },
);

Then(
  "the not found detail is {string}",
  // eslint-disable-next-line no-empty-pattern
  ({}, detail: string) => {
    if (required(carried.media, "asked media").includes("json")) {
      const body = required(carried.unknownJson, "JSON not found body") as {
        errors?: { detail?: unknown };
      };
      expect(body.errors?.detail).toBe(detail);
    } else {
      expect(required(carried.unknownText, "HTML not found body")).toBe(detail);
    }
  },
);
