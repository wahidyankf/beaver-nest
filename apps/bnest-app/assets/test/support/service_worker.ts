// Runs the shipped `priv/static/service-worker.js` -- the real file, read
// from disk and evaluated as the classic worker script it is -- against an
// in-memory worker global: a Cache Storage that keeps every response it is
// given, and a network double that records each request it is asked for.
//
// There is no browser here, so nothing about registration or scope is
// proven; what is proven is what the worker's own handlers decide to write
// to, and read back from, Cache Storage. A test drives it the way a browser
// would: `install`, then `activate`, then `fetch` events.

import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const WORKER_PATH = path.resolve(
  here,
  "../../../priv/static/service-worker.js",
);

export const ORIGIN = "https://bnest.test";

/** Markup only a signed-in page carries; a cached copy of it is the leak. */
export const AUTHENTICATED_MARKER = "data-current-user-id";

type Listener = (event: unknown) => void;

export interface NetworkRequest {
  pathname: string;
  credentials: RequestCredentials;
}

export interface WorkerHarness {
  /** Cache name -> pathname -> stored response. */
  caches: Map<string, Map<string, Response>>;
  network: NetworkRequest[];
  online: boolean;
  /** Set a flag to make the matching Cache Storage call reject, as a full disk would. */
  faults: { cacheDelete: boolean };
  install: () => Promise<void>;
  activate: () => Promise<void>;
  /** The worker's answer, or `null` when it left the request to the browser. */
  fetch: (
    pathname: string,
    init?: { method?: string; mode?: RequestMode },
  ) => Promise<Response | null>;
  cachedPathnames: () => string[];
  /** How many `waitUntil` promises the last fetch event extended the worker's lifetime with. */
  fetchLifetimeCount: () => number;
}

/** What a fetch event carries: the parts of a `Request` the worker reads. */
interface EventRequest {
  url: string;
  method: string;
  mode: RequestMode;
  credentials: RequestCredentials;
}

type Input = RequestInfo | URL | EventRequest;

function isRequestLike(input: Input): input is Request | EventRequest {
  return typeof input === "object" && "url" in input && "method" in input;
}

function pathnameOf(input: Input): string {
  const url = isRequestLike(input) ? input.url : String(input);
  return new URL(url, ORIGIN).pathname;
}

/**
 * What the server answers: a signed-in page for any navigation (the session
 * cookie rides along unless the request omits credentials), and a plain
 * static body for everything else.
 */
function serverResponse(pathname: string, credentials: RequestCredentials) {
  if (pathname.startsWith("/assets/") || pathname.startsWith("/images/")) {
    return new Response(`static ${pathname}`, { status: 200 });
  }
  if (pathname === "/manifest.webmanifest") {
    return new Response("{}", { status: 200 });
  }
  const signedIn = credentials !== "omit";
  return new Response(
    signedIn
      ? `<main ${AUTHENTICATED_MARKER}="test-user-sw">Signed in</main>`
      : "<main>Beaver Nest</main>",
    { status: 200, headers: { "content-type": "text/html" } },
  );
}

/**
 * Cache Storage lists entries in the order they were written, and a write to
 * an existing key replaces the entry and makes it the newest. A `Map` keeps
 * the first position on `set`, so the old entry is removed first.
 */
function store(cache: Map<string, Response>, key: string, response: Response) {
  cache.delete(key);
  cache.set(key, response);
}

function createCacheStorage(
  stored: Map<string, Map<string, Response>>,
  network: (input: Input) => Promise<Response>,
  faults: { cacheDelete: boolean },
) {
  function open(name: string) {
    let entries = stored.get(name);
    if (!entries) {
      entries = new Map();
      stored.set(name, entries);
    }
    const cache = entries;
    return {
      async put(request: Input, response: Response) {
        store(cache, pathnameOf(request), response);
      },
      async addAll(requests: Input[]) {
        for (const request of requests) {
          const response = await network(request);
          store(cache, pathnameOf(request), response);
        }
      },
      async match(request: Input) {
        return cache.get(pathnameOf(request))?.clone();
      },
      async keys() {
        return [...cache.keys()].map((key) => new Request(`${ORIGIN}${key}`));
      },
      async delete(request: Input) {
        if (faults.cacheDelete) throw new Error("injected delete failure");
        return cache.delete(pathnameOf(request));
      },
    };
  }

  return {
    open: async (name: string) => open(name),
    keys: async () => [...stored.keys()],
    delete: async (name: string) => stored.delete(name),
    match: async (request: Input) => {
      for (const entries of stored.values()) {
        const hit = entries.get(pathnameOf(request));
        if (hit) return hit.clone();
      }
      return undefined;
    },
  };
}

/**
 * Evaluates the shipped worker once. `seed` is Cache Storage as an earlier
 * worker version left it on the device.
 */
export function loadServiceWorker(
  seed: Record<string, Record<string, string>> = {},
): WorkerHarness {
  const listeners = new Map<string, Listener[]>();
  const stored = new Map<string, Map<string, Response>>();
  for (const [name, entries] of Object.entries(seed)) {
    stored.set(
      name,
      new Map(
        Object.entries(entries).map(([key, body]) => [key, new Response(body)]),
      ),
    );
  }

  const faults = { cacheDelete: false };
  const harness = {
    caches: stored,
    network: [] as NetworkRequest[],
    online: true,
    faults,
  } as WorkerHarness;

  async function network(input: Input): Promise<Response> {
    const credentials = isRequestLike(input)
      ? input.credentials
      : "same-origin";
    const pathname = pathnameOf(input);
    harness.network.push({ pathname, credentials });
    if (!harness.online) throw new TypeError("Failed to fetch");
    return serverResponse(pathname, credentials);
  }

  const self = {
    addEventListener(type: string, listener: Listener) {
      listeners.set(type, [...(listeners.get(type) ?? []), listener]);
    },
    skipWaiting: async () => undefined,
    clients: { claim: async () => undefined },
    registration: { showNotification: async () => undefined },
    location: new URL(`${ORIGIN}/service-worker.js`),
  };

  const source = readFileSync(WORKER_PATH, "utf8");
  // A classic worker script reads these as globals; handing them in as
  // parameters is the same thing without touching this process's own.
  // oxlint-disable-next-line no-new-func
  new Function("self", "caches", "fetch", "Request", "Response", source)(
    self,
    createCacheStorage(stored, network, faults),
    network,
    Request,
    Response,
  );

  let lastFetchLifetimes: Promise<unknown>[] = [];

  async function dispatchLifecycle(type: string): Promise<void> {
    const pending: Promise<unknown>[] = [];
    for (const listener of listeners.get(type) ?? []) {
      listener({
        waitUntil: (promise: Promise<unknown>) => pending.push(promise),
      });
    }
    await Promise.all(pending);
  }

  harness.install = () => dispatchLifecycle("install");
  harness.activate = () => dispatchLifecycle("activate");
  harness.fetch = async (pathname, init = {}) => {
    // A plain object rather than a `Request`: Node refuses the "navigate"
    // mode a browser reports for a page load.
    // `pathname` may also be an absolute URL, which is how a cross-origin request is modelled.
    const eventRequest: EventRequest = {
      url: new URL(pathname, ORIGIN).href,
      method: init.method ?? "GET",
      mode: init.mode ?? "cors",
      credentials: "include",
    };
    let answer: Promise<Response> | null = null;
    lastFetchLifetimes = [];
    for (const listener of listeners.get("fetch") ?? []) {
      listener({
        request: eventRequest,
        respondWith: (response: Promise<Response>) => {
          answer = response;
        },
        waitUntil: (promise: Promise<unknown>) =>
          lastFetchLifetimes.push(promise),
      });
    }
    const response = answer === null ? null : await answer;
    // A browser keeps the worker running until these settle. The harness waits for them too, so a test reads
    // Cache Storage only after the worker's writes are done.
    await Promise.allSettled(lastFetchLifetimes);
    return response;
  };
  harness.fetchLifetimeCount = () => lastFetchLifetimes.length;
  harness.cachedPathnames = () =>
    [...stored.values()].flatMap((entries) => [...entries.keys()]);
  return harness;
}
