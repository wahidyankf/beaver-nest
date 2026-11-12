export declare const CONTINUATION_PROMPT: string;
export declare const RESUMED_REPLY_HOLD_MS: number;
export declare function holdMsFor(
  prompt: string,
  reply: { holdMs: number },
  slot?: string,
): number;
