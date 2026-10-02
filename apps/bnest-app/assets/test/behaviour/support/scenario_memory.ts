// What one scenario's steps hand each other: the message a Given named, the
// measurement a When took for a Then to compare against. Cleared after every
// scenario (`verify.ts`), so nothing a scenario remembers reaches the next.

const memory = new Map<string, unknown>();

export function remember(key: string, value: unknown): void {
  memory.set(key, value);
}

export function recall<T>(key: string): T {
  if (!memory.has(key)) {
    throw new Error(`no earlier step in this scenario recorded ${key}`);
  }
  return memory.get(key) as T;
}

export function recallOr<T>(key: string, fallback: T): T {
  return memory.has(key) ? (memory.get(key) as T) : fallback;
}

export function forgetScenario(): void {
  memory.clear();
}
