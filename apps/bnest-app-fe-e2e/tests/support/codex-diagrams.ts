import { expect, type BrowserContext, type Page } from "@playwright/test";
import { instanceIdentities } from "./instance-identities";
import { login } from "./authentication";

// Helpers for the Codex reply diagram scenarios (ADR 004). Every check reads what the browser shows or what the
// network did; nothing is inferred from the server's markup alone.

export const DIAGRAM_ENGINE_PATH = "/assets/js/diagrams/";
export const DRAWN_FIGURE =
  'figure.bnest-diagram[data-bnest-diagram-state="drawn"]';
export const MARKED_DIAGRAM = 'pre[data-bnest-diagram="mermaid"]';
export const ENGINE_CORE_CHUNK =
  "**/assets/js/diagrams/chunks/engine_core-*.js";

/**
 * Holds the diagram engine's core chunk for `ms` before it is served, so a marked diagram stays undrawn for that long
 * and a scenario can measure the page before the draw. The route belongs to the browser context, so it covers every
 * page the scenario opens.
 */
export async function holdDiagramEngine(
  context: BrowserContext,
  ms: number,
): Promise<void> {
  await context.route(ENGINE_CORE_CHUNK, async (route) => {
    await new Promise((resolve) => {
      setTimeout(resolve, ms);
    });
    await route.continue();
  });
}

// The request URLs each browser context made, from the moment the scenario starts (see the Before hook in
// codex_diagrams.steps.ts). A context is one scenario's browser, so its list is one scenario's traffic.
const requests = new WeakMap<BrowserContext, string[]>();

/** Starts recording every request the context makes. Called before the first page opens. */
export function recordRequests(context: BrowserContext): void {
  const urls: string[] = [];
  requests.set(context, urls);
  context.on("request", (request) => urls.push(request.url()));
}

function recordedUrls(page: Page): string[] {
  const urls = requests.get(page.context());
  if (urls === undefined)
    throw new Error("the request recorder was not started for this scenario");
  return urls;
}

/** Every recorded request that leaves the test origin. `data:` and `blob:` addresses stay in the page. */
export function offOriginRequests(page: Page): string[] {
  const origin = new URL(page.url()).origin;

  return recordedUrls(page).filter((url) => {
    if (url.startsWith("data:") || url.startsWith("blob:")) return false;
    return new URL(url).origin !== origin;
  });
}

export function diagramEngineRequests(page: Page): string[] {
  return recordedUrls(page).filter((url) => url.includes(DIAGRAM_ENGINE_PATH));
}

export function latestReply(page: Page) {
  return page.locator("[data-role=assistant-message]").last();
}

export async function openChatAsAdmin(page: Page): Promise<void> {
  await login(page, instanceIdentities().admin);
  await page.goto("/chat");
  await expect(page.locator("[data-phx-main]")).toHaveClass(/phx-connected/u);
}

/** Sends a message and waits until the reply to it is complete (the same wait the Codex steps use). */
export async function sendAndWaitForReply(
  page: Page,
  message: string,
): Promise<void> {
  await expect(page.locator("[data-phx-main]")).toHaveClass(/phx-connected/u);
  const replies = page.locator("[data-role=assistant-message]");
  const before = await replies.count();
  await page.getByLabel("Message").fill(message);
  await page.getByRole("button", { name: "Send" }).click();
  // The send adds this turn's reply at once. Until it is there, the latest reply is the previous one, which is
  // already finished, so waiting on its state alone returns before this turn starts.
  await expect(replies).toHaveCount(before + 1, { timeout: 20_000 });
  await expect(latestReply(page)).toHaveAttribute("data-streaming", "false", {
    timeout: 20_000,
  });
}

export function drawnFigures(page: Page) {
  return page.locator(`[data-role=assistant-message] ${DRAWN_FIGURE}`);
}

/**
 * Scrolls each marked diagram into view, the way a reader reaching it would, until none is left. The engine draws a
 * marked diagram only once it is near the viewport (ADR 004, Decision 3), so on a short phone screen a diagram below
 * the fold stays marked until it is scrolled to. A diagram that cannot be drawn ends as its own figure with a note,
 * so the wait ends for those as well.
 */
export async function scrollMarkedIntoView(page: Page): Promise<void> {
  const marked = page.locator(MARKED_DIAGRAM);
  await expect
    .poll(
      async () => {
        if ((await marked.count()) > 0) {
          // A scroll can find its node replaced by the drawn figure; the next count sees the result.
          await marked
            .first()
            .scrollIntoViewIfNeeded({ timeout: 2_000 })
            .catch(() => null);
        }
        return marked.count();
      },
      { timeout: 20_000 },
    )
    .toBe(0);
}

/** Waits until the browser has drawn `count` pictures in the conversation (the draw is asynchronous). */
export async function expectDrawnPictures(
  page: Page,
  count: number,
): Promise<void> {
  await scrollMarkedIntoView(page);
  await expect(drawnFigures(page)).toHaveCount(count, { timeout: 15_000 });
}

/** The picture's SVG is decoded by the browser: a real drawing has a natural width. */
export async function expectDecodedPicture(page: Page): Promise<void> {
  const image = drawnFigures(page).last().locator(".bnest-diagram-canvas img");

  await expect(image).toHaveAttribute("src", /^data:image\/svg\+xml/u);
  await expect
    .poll(() =>
      image.evaluate((element) => (element as HTMLImageElement).naturalWidth),
    )
    .toBeGreaterThan(0);
}

/**
 * Records, inside the page, when the first marked diagram appears and when its picture is inserted. The
 * observer is installed before the reply completes, so the marker's arrival is seen, not inferred.
 */
export async function installDrawTiming(page: Page): Promise<void> {
  await page.evaluate(() => {
    const root = document.documentElement;
    const observer = new MutationObserver(() => {
      if (
        root.dataset["bnestMarkedAt"] === undefined &&
        document.querySelector('pre[data-bnest-diagram="mermaid"]') !== null
      ) {
        root.dataset["bnestMarkedAt"] = String(performance.now());
      }
      if (
        root.dataset["bnestDrawnAt"] === undefined &&
        document.querySelector(
          'figure.bnest-diagram[data-bnest-diagram-state="drawn"]',
        ) !== null
      ) {
        root.dataset["bnestDrawnAt"] = String(performance.now());
      }
    });
    observer.observe(document, { childList: true, subtree: true });
  });
}

/** The time from the marker's arrival to the picture's insertion, measured in the page. */
export function drawMilliseconds(page: Page): Promise<number> {
  return page.evaluate(() => {
    const marked = Number(document.documentElement.dataset["bnestMarkedAt"]);
    const drawn = Number(document.documentElement.dataset["bnestDrawnAt"]);
    return drawn - marked;
  });
}

/** True when a script element, a canary or an event-handler attribute is in the conversation. */
export function scriptOrHandlerInConversation(page: Page): Promise<boolean> {
  return page.evaluate(() => {
    const conversation = document.querySelector("#chat-conversation");
    if (conversation === null) return false;
    if (conversation.querySelector("script") !== null) return true;
    if ("__bnestCanary" in window) return true;
    return [...conversation.querySelectorAll("*")].some((element) =>
      element.getAttributeNames().some((name) => name.startsWith("on")),
    );
  });
}

/** Measures a picture's box at the current viewport: its scroll box, its width and the page's width. */
export function pictureLayout(page: Page) {
  return page.evaluate(() => {
    const canvas = document.querySelector(
      '[data-role=assistant-message] figure.bnest-diagram[data-bnest-diagram-state="drawn"] .bnest-diagram-canvas',
    );
    if (!(canvas instanceof HTMLElement))
      throw new Error("no drawn picture canvas is on the page");
    const image = canvas.querySelector("img");
    return {
      overflowX: getComputedStyle(canvas).overflowX,
      canvasScrolls: canvas.scrollWidth > canvas.clientWidth,
      imageWidth: image?.getBoundingClientRect().width ?? 0,
      naturalWidth: Number(image?.getAttribute("width") ?? 0),
      canvasWidth: canvas.getBoundingClientRect().width,
      pageScrollWidth: document.documentElement.scrollWidth,
      pageClientWidth: document.documentElement.clientWidth,
    };
  });
}

/** The engine's address, from the meta tag the root layout renders (the production URL carries its digest). */
export async function engineAddress(page: Page): Promise<string> {
  const address = await page
    .locator('meta[name="bnest-diagram-engine"]')
    .getAttribute("content");
  if (address === null)
    throw new Error("the page has no diagram engine address");
  return address;
}

// The policy the engine's frame must carry (diagram_frame.js, FRAME_POLICY). The unit test pins the source; this is the
// browser's copy of the same text.
const FRAME_POLICY_CONTENT =
  "default-src 'none'; script-src 'self'; style-src 'unsafe-inline'; img-src data:";

// The frame must carry the policy, and a picture it asks for from another origin must be refused. The probe's own
// request may appear in the recorder, so the callers' request check runs before this.
export async function expectFrameRefusesOutsidePicture(
  page: Page,
): Promise<void> {
  const probe = await framePolicyProbe(page);
  expect(probe).not.toBeNull();
  expect(probe?.policy).toBe(FRAME_POLICY_CONTENT);
  expect(probe?.directive).toMatch(/^img-src/u);
}

// Asks the diagram frame (the engine's hidden same-origin iframe, which is kept after a successful start) for a
// picture from another origin. The frame's policy must refuse it, and the violation names the directive. The
// recorder may still list the probe's own request, so callers check requests before they call this. Null when no
// frame is open.
export function framePolicyProbe(
  page: Page,
): Promise<{ policy: string; directive: string } | null> {
  return page.evaluate(async () => {
    const frame = document.querySelector<HTMLIFrameElement>(
      'iframe[aria-hidden="true"][srcdoc]',
    );
    const frameDocument = frame?.contentDocument;
    if (!frameDocument) return null;

    const policy =
      frameDocument
        .querySelector('meta[http-equiv="Content-Security-Policy"]')
        ?.getAttribute("content") ?? "";
    const violation = new Promise<string>((resolve) => {
      frameDocument.addEventListener(
        "securitypolicyviolation",
        (event) => {
          resolve(event.violatedDirective);
        },
        { once: true },
      );
    });
    const image = frameDocument.createElement("img");
    image.src = "https://foreign.example.test/probe.png";
    frameDocument.body.append(image);
    const directive = await Promise.race([
      violation,
      new Promise<string>((resolve) => {
        setTimeout(() => {
          resolve("none");
        }, 5_000);
      }),
    ]);
    image.remove();
    return { policy, directive };
  });
}
