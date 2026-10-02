// The shipped service worker (`priv/static/service-worker.js`) never puts an
// authenticated response into Cache Storage, and never serves one from it.
// The worker runs from disk against an in-memory worker global
// (`test/support/service_worker.ts`).

import { describe, expect, it } from "vitest";
import {
  AUTHENTICATED_MARKER,
  loadServiceWorker,
} from "../support/service_worker";

function isStaticPath(pathname: string): boolean {
  return (
    pathname.startsWith("/assets/") ||
    pathname.startsWith("/images/") ||
    pathname === "/manifest.webmanifest"
  );
}

async function installed() {
  const worker = loadServiceWorker();
  await worker.install();
  await worker.activate();
  return worker;
}

describe("service worker install", () => {
  it("precaches only static files, never a page", async () => {
    const worker = await installed();

    expect(worker.cachedPathnames().length).toBeGreaterThan(0);
    expect(worker.cachedPathnames().filter((p) => !isStaticPath(p))).toEqual(
      [],
    );
  });

  it("removes a cache an earlier version left holding the signed-in home page", async () => {
    const worker = loadServiceWorker({
      "beaver-nest-shell-v1": {
        "/": `<main ${AUTHENTICATED_MARKER}="test-user-sw">Signed in</main>`,
      },
    });
    await worker.install();
    await worker.activate();

    expect(worker.caches.has("beaver-nest-shell-v1")).toBe(false);
    expect(worker.cachedPathnames()).not.toContain("/");
  });
});

describe("service worker fetch", () => {
  it("answers an online navigation from the network and caches nothing", async () => {
    const worker = await installed();
    const before = worker.cachedPathnames();

    const response = await worker.fetch("/family-chat/ruang-keluarga", {
      mode: "navigate",
    });

    expect(await response?.text()).toContain(AUTHENTICATED_MARKER);
    expect(worker.cachedPathnames()).toEqual(before);
  });

  it("answers an offline navigation with a page that holds no signed-in content", async () => {
    const worker = await installed();
    worker.online = false;

    const response = await worker.fetch("/family-chat/ruang-keluarga", {
      mode: "navigate",
    });

    expect(response).not.toBeNull();
    const body = (await response?.text()) ?? "";
    expect(body).toContain("offline");
    expect(body).not.toContain(AUTHENTICATED_MARKER);
    expect(worker.cachedPathnames().filter((p) => !isStaticPath(p))).toEqual(
      [],
    );
  });

  it("caches a static asset it fetched and serves it back offline", async () => {
    const worker = await installed();
    await worker.fetch("/assets/js/chunk-1.js");
    worker.online = false;

    const response = await worker.fetch("/assets/js/chunk-1.js");

    expect(await response?.text()).toBe("static /assets/js/chunk-1.js");
  });

  it("leaves GraphQL and every non-GET request to the network", async () => {
    const worker = await installed();

    expect(await worker.fetch("/api/graphql", { method: "POST" })).toBeNull();
    expect(await worker.fetch("/api/graphql")).toBeNull();
    expect(worker.cachedPathnames().filter((p) => !isStaticPath(p))).toEqual(
      [],
    );
  });
});
