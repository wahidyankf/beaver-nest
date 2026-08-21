import type { LiveSocketInstanceInterface } from "phoenix_live_view";

interface LiveReloader {
  enableServerLogs(): void;
  openEditorAtCaller(target: EventTarget | null): void;
  openEditorAtDef(target: EventTarget | null): void;
}

declare global {
  interface Window {
    liveReloader: LiveReloader;
    liveSocket: LiveSocketInstanceInterface;
  }

  interface WindowEventMap {
    "phx:live_reload:attached": CustomEvent<LiveReloader>;
  }
}

export {};
