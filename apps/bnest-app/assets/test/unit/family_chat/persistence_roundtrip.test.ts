// @vitest-environment happy-dom
//
// Plain Vitest unit coverage for `js/family_chat/persistence_indexeddb.js`:
// the real-browser IndexedDB binding behind an in-memory IDB double (no
// browser store exists in this environment). Every adapter operation is
// exercised: save, load, remove, namespace clear, user clear, and the
// best-effort degradation when the store refuses.

import { afterEach, describe, expect, it, vi } from "vitest";
import {
  createIndexedDbPersistence,
  resolvePersistence,
  toRow,
} from "../../../js/family_chat/persistence_indexeddb.js";

interface Row {
  key: string;
  namespace: string;
  [key: string]: unknown;
}

type Listener = () => void;

class FakeRequest {
  result: unknown = undefined;
  error: unknown = undefined;
  private readonly listeners = new Map<string, Listener[]>();

  addEventListener(type: string, callback: Listener): void {
    const list = this.listeners.get(type) ?? [];
    list.push(callback);
    this.listeners.set(type, list);
  }

  succeed(result: unknown): void {
    this.result = result;
    queueMicrotask(() => {
      for (const callback of this.listeners.get("success") ?? []) callback();
    });
  }

  fire(type: string): void {
    queueMicrotask(() => {
      for (const callback of this.listeners.get(type) ?? []) callback();
    });
  }

  fail(error: unknown): void {
    this.error = error;
    queueMicrotask(() => {
      for (const callback of this.listeners.get("error") ?? []) callback();
    });
  }
}

class FakeCursor {
  constructor(
    private readonly request: FakeRequest,
    private readonly keys: string[],
    readonly primaryKey: string,
    private readonly store: FakeStore,
  ) {}

  continue(): void {
    const next = this.keys.shift();
    queueMicrotask(() => {
      if (next === undefined) {
        this.request.succeed(null);
      } else {
        const cursor = new FakeCursor(
          this.request,
          this.keys,
          next,
          this.store,
        );
        this.request.succeed(cursor);
      }
    });
  }
}

class FakeStore {
  readonly rows = new Map<string, Row>();

  createIndex(): void {}

  put(row: Row): FakeRequest {
    const request = new FakeRequest();
    this.rows.set(row.key, row);
    request.succeed(undefined);
    return request;
  }

  delete(key: string): FakeRequest {
    const request = new FakeRequest();
    this.rows.delete(key);
    request.succeed(undefined);
    return request;
  }

  index(_name: string): {
    getAll: (namespace: string) => FakeRequest;
    openKeyCursor: (range: {
      matches: (namespace: string) => boolean;
    }) => FakeRequest;
  } {
    const store = this;
    return {
      getAll(namespace: string): FakeRequest {
        const request = new FakeRequest();
        const rows = [...store.rows.values()].filter(
          (row) => row.namespace === namespace,
        );
        request.succeed(rows);
        return request;
      },
      openKeyCursor(range: {
        matches: (namespace: string) => boolean;
      }): FakeRequest {
        const request = new FakeRequest();
        const keys = [...store.rows.values()]
          .filter((row) => range.matches(row.namespace as string))
          .map((row) => row.key);
        const first = keys.shift();
        queueMicrotask(() => {
          if (first === undefined) {
            request.succeed(null);
          } else {
            request.succeed(new FakeCursor(request, keys, first, store));
          }
        });
        return request;
      },
    };
  }
}

class FakeDatabase {
  readonly stores = new Map<string, FakeStore>();
  readonly objectStoreNames = {
    contains: (name: string) => this.stores.has(name),
  };

  createObjectStore(name: string): FakeStore {
    const store = new FakeStore();
    this.stores.set(name, store);
    return store;
  }

  transaction(storeName: string): {
    objectStore: (name: string) => FakeStore;
    addEventListener: (type: string, callback: Listener) => void;
    error: unknown;
  } {
    const store =
      this.stores.get(storeName) ?? this.createObjectStore(storeName);
    const listeners = new Map<string, Listener[]>();
    setTimeout(() => {
      for (const callback of listeners.get("complete") ?? []) callback();
    }, 0);
    return {
      objectStore: () => store,
      addEventListener: (type: string, callback: Listener) => {
        const list = listeners.get(type) ?? [];
        list.push(callback);
        listeners.set(type, list);
      },
      error: null,
    };
  }
}

function installIdb(db: FakeDatabase): void {
  const openRequest = () => {
    const request = new FakeRequest();
    request.result = db;
    request.fire("upgradeneeded");
    request.succeed(db);
    return request;
  };
  vi.stubGlobal("indexedDB", { open: () => openRequest() });
  vi.stubGlobal("IDBKeyRange", {
    only: (value: string) => ({
      matches: (namespace: string) => namespace === value,
    }),
    bound: (lower: string, upper: string) => ({
      matches: (namespace: string) => namespace >= lower && namespace <= upper,
    }),
  });
}

const NAMESPACE = "u-me:ruang-keluarga";
const MESSAGE = {
  clientMessageId: "c-1",
  body: "Dinner is ready",
  status: "Sending",
  attempt: 1,
  retryCount: 0,
  createdAt: 100,
  nextRetryAt: 0,
  timerHandle: null,
};

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("indexeddb persistence", () => {
  it("round-trips a saved message through load", async () => {
    installIdb(new FakeDatabase());
    const persistence = createIndexedDbPersistence();

    persistence.save(NAMESPACE, { ...MESSAGE });
    await new Promise((resolve) => setTimeout(resolve, 10));
    const loaded = await persistence.loadAll(NAMESPACE);

    expect(loaded).toHaveLength(1);
    expect(loaded[0]).toMatchObject({
      clientMessageId: "c-1",
      body: "Dinner is ready",
    });
  });

  it("removes a single message and clears a namespace", async () => {
    installIdb(new FakeDatabase());
    const persistence = createIndexedDbPersistence();

    persistence.save(NAMESPACE, { ...MESSAGE, clientMessageId: "c-1" });
    persistence.save(NAMESPACE, { ...MESSAGE, clientMessageId: "c-2" });
    persistence.save("u-me:other-room", { ...MESSAGE, clientMessageId: "c-3" });
    await new Promise((resolve) => setTimeout(resolve, 10));

    persistence.remove(NAMESPACE, "c-1");
    await new Promise((resolve) => setTimeout(resolve, 10));
    expect(await persistence.loadAll(NAMESPACE)).toHaveLength(1);

    persistence.clear(NAMESPACE);
    await new Promise((resolve) => setTimeout(resolve, 10));
    expect(await persistence.loadAll(NAMESPACE)).toHaveLength(0);
    expect(await persistence.loadAll("u-me:other-room")).toHaveLength(1);
  });

  it("clears every namespace of one user", async () => {
    installIdb(new FakeDatabase());
    const persistence = createIndexedDbPersistence();

    persistence.save("u-me:room-a", { ...MESSAGE, clientMessageId: "c-1" });
    persistence.save("u-me:room-b", { ...MESSAGE, clientMessageId: "c-2" });
    persistence.save("u-you:room-a", { ...MESSAGE, clientMessageId: "c-3" });
    await new Promise((resolve) => setTimeout(resolve, 10));

    await persistence.clearUser("u-me");

    expect(await persistence.loadAll("u-me:room-a")).toHaveLength(0);
    expect(await persistence.loadAll("u-me:room-b")).toHaveLength(0);
    expect(await persistence.loadAll("u-you:room-a")).toHaveLength(1);
  });

  it("degrades to empty when the store refuses", async () => {
    vi.stubGlobal("indexedDB", {
      open: () => {
        const request = new FakeRequest();
        request.fail(new Error("denied"));
        return request;
      },
    });
    vi.stubGlobal("IDBKeyRange", { only: () => ({}), bound: () => ({}) });
    const persistence = createIndexedDbPersistence();

    expect(await persistence.loadAll(NAMESPACE)).toEqual([]);
    persistence.save(NAMESPACE, { ...MESSAGE });
    await new Promise((resolve) => setTimeout(resolve, 10));
  });

  it("resolves an injected persistence without touching indexeddb", async () => {
    const loaded: string[] = [];
    const injected = {
      loadAll: async (namespace: string) => {
        loaded.push(namespace);
        return [];
      },
      save: async () => {},
      remove: async () => {},
      clear: async () => {},
    };
    const persistence = await resolvePersistence(
      "u-me",
      "ruang-keluarga",
      injected,
    );
    expect(persistence).toBe(injected);
    expect(loaded).toEqual(["u-me:ruang-keluarga"]);
  });

  it("resolves the indexeddb persistence when none is injected", async () => {
    installIdb(new FakeDatabase());
    const persistence = await resolvePersistence(
      "u-me",
      "ruang-keluarga",
      undefined,
    );
    expect(await persistence.loadAll("u-me:ruang-keluarga")).toEqual([]);
    expect(toRow(NAMESPACE, { ...MESSAGE }).key).toBe(`${NAMESPACE}::c-1`);
  });
});
