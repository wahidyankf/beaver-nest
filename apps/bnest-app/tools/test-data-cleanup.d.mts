export type CleanupOptions = {
  roots?: string[];
  legacyParents?: string[];
  olderThanHours?: number;
  now?: number;
};

export function cleanupStaleTestData(options?: CleanupOptions): {
  removed: number;
  retained: number;
};
