// The shipped service worker (`priv/static/service-worker.js`) never puts an
// authenticated response into Cache Storage, and never serves one from it.
// The worker runs from disk against an in-memory worker global
// (`test/support/service_worker.ts`).

import { describe, expect, it } from "vitest";
import {
  AUTHENTICATED_MARKER,
  ORIGIN,
  loadServiceWorker,
  type WorkerHarness,
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

const DIAGRAMS = "/assets/js/diagrams/";
const DIAGRAM_LIMIT = 120;

/** A content-hashed chunk name, as a release writes them. */
function chunk(index: number): string {
  return `${DIAGRAMS}chunks/chunk-${index}.js`;
}

function chunkPaths(from: number, to: number): string[] {
  return Array.from({ length: to - from }, (_, offset) => chunk(from + offset));
}

/** Each fetch finishes before the next starts, so Cache Storage sees them in order. */
async function fetchInOrder(worker: WorkerHarness, paths: string[]) {
  for (const path of paths) {
    // eslint-disable-next-line no-await-in-loop -- the cache's write order is the age order under test.
    await worker.fetch(path);
  }
}

async function fetchChunks(worker: WorkerHarness, from: number, to: number) {
  await fetchInOrder(worker, chunkPaths(from, to));
}

function diagramChunks(worker: WorkerHarness): string[] {
  return worker.cachedPathnames().filter((p) => p.startsWith(DIAGRAMS));
}

/** Lets the worker's background `put` and trim settle before asserting. */
function settle(): Promise<void> {
  return new Promise((resolve) => {
    setTimeout(resolve, 0);
  });
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

describe("service worker fetch lifetime", () => {
  // A write the worker starts after answering is not kept alive by the browser unless the worker hands it to
  // waitUntil; an unawaited write in a suspended worker never completes (ADR 004, Decision 4).
  it("keeps the worker alive until a static file it fetched is written", async () => {
    const worker = await installed();

    await worker.fetch("/assets/js/diagrams/chunks/chunk-9.js");

    expect(worker.fetchLifetimeCount()).toBe(1);
  });

  it("extends no lifetime for a request it does not cache", async () => {
    const worker = await installed();

    await worker.fetch("/api/graphql");

    expect(worker.fetchLifetimeCount()).toBe(0);
  });
});

describe("service worker cross-origin fetch", () => {
  it("leaves a cross-origin request to the network even when its path looks static", async () => {
    const worker = await installed();
    const before = worker.cachedPathnames();

    // Third-party image hosts may use /images/ or /assets/ paths; the worker
    // must not answer them, nor write them to Cache Storage.
    expect(
      await worker.fetch("https://cdn.example.test/images/x.png"),
    ).toBeNull();
    expect(
      await worker.fetch("https://cdn.example.test/assets/x.png"),
    ).toBeNull();
    expect(worker.cachedPathnames()).toEqual(before);
  });

  it("leaves a cross-origin page navigation to the browser, with no offline fallback", async () => {
    const worker = await installed();
    worker.online = false;

    expect(
      await worker.fetch("https://cdn.example.test/family-chat/x", {
        mode: "navigate",
      }),
    ).toBeNull();
  });

  it("still answers and caches a same-origin static request given as an absolute URL", async () => {
    const worker = await installed();

    await worker.fetch(`${ORIGIN}/images/x.png`);
    worker.online = false;

    const response = await worker.fetch(`${ORIGIN}/images/x.png`);

    expect(await response?.text()).toBe("static /images/x.png");
  });
});

describe("service worker diagram chunk trim", () => {
  it("keeps the 120 newest chunks and evicts the oldest when the 121st is cached", async () => {
    const worker = await installed();

    await fetchChunks(worker, 0, DIAGRAM_LIMIT + 1);
    await settle();

    expect(diagramChunks(worker)).toEqual(chunkPaths(1, DIAGRAM_LIMIT + 1));
    expect([...worker.caches.keys()]).toEqual(["beaver-nest-shell-v2"]);
  });

  it("holds the cache at 120 chunks across several releases of new chunks", async () => {
    const worker = await installed();

    await fetchChunks(worker, 0, 250);
    await settle();

    expect(diagramChunks(worker)).toEqual(chunkPaths(130, 250));
  });

  it("renews a chunk that is fetched again, so an older chunk is evicted first", async () => {
    const worker = await installed();
    await fetchChunks(worker, 0, DIAGRAM_LIMIT);

    await worker.fetch(chunk(0));
    await fetchChunks(worker, DIAGRAM_LIMIT, DIAGRAM_LIMIT + 1);
    await settle();

    expect(diagramChunks(worker)).toContain(chunk(0));
    expect(diagramChunks(worker)).not.toContain(chunk(1));
    expect(diagramChunks(worker)).toHaveLength(DIAGRAM_LIMIT);
  });
});

describe("service worker diagram chunk trim scope", () => {
  it("never evicts a static file outside the diagrams prefix, even one with a look-alike path", async () => {
    const worker = await installed();
    const others = Array.from(
      { length: 130 },
      (_, index) => `/assets/js/diagrams-legacy-${index}.js`,
    );
    await fetchInOrder(worker, others);

    await fetchChunks(worker, 0, DIAGRAM_LIMIT + 1);
    await settle();

    expect(worker.cachedPathnames()).toEqual(
      expect.arrayContaining([...others, "/assets/js/app.js"]),
    );
    expect(diagramChunks(worker)).toHaveLength(DIAGRAM_LIMIT);
  });

  it("does not count a cross-origin request under the prefix, so it evicts nothing", async () => {
    const worker = await installed();
    await fetchChunks(worker, 0, DIAGRAM_LIMIT);

    expect(
      await worker.fetch("https://cdn.example.test/assets/js/diagrams/x.js"),
    ).toBeNull();
    await settle();

    expect(diagramChunks(worker)).toEqual(chunkPaths(0, DIAGRAM_LIMIT));
  });
});

describe("service worker diagram chunk trim offline and failures", () => {
  it("still draws a chunk kept offline, and answers nothing for one the trim evicted", async () => {
    const worker = await installed();
    await fetchChunks(worker, 0, DIAGRAM_LIMIT + 1);
    await settle();
    worker.online = false;

    const kept = await worker.fetch(chunk(1));

    expect(await kept?.text()).toBe(`static ${chunk(1)}`);
    expect(await worker.fetch(chunk(0))).toBeUndefined();
  });

  it("keeps serving the response when the trim cannot delete an entry", async () => {
    const worker = await installed();
    await fetchChunks(worker, 0, DIAGRAM_LIMIT);
    worker.faults.cacheDelete = true;

    const response = await worker.fetch(chunk(DIAGRAM_LIMIT));
    await settle();

    expect(await response?.text()).toBe(`static ${chunk(DIAGRAM_LIMIT)}`);
    expect(diagramChunks(worker)).toHaveLength(DIAGRAM_LIMIT + 1);
  });
});
