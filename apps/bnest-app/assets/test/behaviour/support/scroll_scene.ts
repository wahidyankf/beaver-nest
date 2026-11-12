// A scrolling region in happy-dom for the conversation-follow scenarios: the Codex conversation and the Family Chat
// history share one follower (`js/scroll_follow.js`), so both are bound against the same modelled region.
//
// happy-dom has no layout. The region's metrics are modelled the way a browser reports and clamps them: a scroll
// position never passes `scrollHeight - clientHeight`. A scenario changes the content, the way a reply, a drawn
// diagram or a loaded picture does, and then waits for the observers, which run after the change.

import { Window } from "happy-dom";
import { createBottomFollower } from "../../../js/scroll_follow.js";

export interface Metrics {
  content: number;
  box: number;
  top: number;
}

export interface ScrollScene {
  window: Window;
  region: HTMLElement;
  metrics: Metrics;
  follower: ReturnType<typeof createBottomFollower> | null;
}

/** A ResizeObserver that reports only when a scene shrinks its region (`shrinkRegion`), as a browser does on a resize. */
class SceneResizeObserver {
  static readonly observers = new Set<SceneResizeObserver>();
  private readonly callback: ResizeObserverCallback;
  private readonly targets = new Set<Element>();

  constructor(callback: ResizeObserverCallback) {
    this.callback = callback;
    SceneResizeObserver.observers.add(this);
  }

  observe(target: Element): void {
    this.targets.add(target);
  }

  unobserve(target: Element): void {
    this.targets.delete(target);
  }

  disconnect(): void {
    this.targets.clear();
    SceneResizeObserver.observers.delete(this);
  }

  /** Reports the resize of `target` to the callback, as the browser does once layout has run. */
  report(target: Element): void {
    if (!this.targets.has(target)) return;
    this.callback(
      [{ target } as unknown as ResizeObserverEntry],
      this as unknown as ResizeObserver,
    );
  }
}

const GLOBAL_NAMES = [
  "window",
  "document",
  "Element",
  "HTMLElement",
  "Node",
  "MutationObserver",
  "Event",
  "ResizeObserver",
] as const;

let scene: ScrollScene | null = null;
let saved: Map<string, unknown> | null = null;

function installGlobals(win: Window): void {
  saved = new Map();
  const values: Record<(typeof GLOBAL_NAMES)[number], unknown> = {
    window: win,
    document: win.document,
    Element: win.Element,
    HTMLElement: win.HTMLElement,
    Node: win.Node,
    MutationObserver: win.MutationObserver,
    Event: win.Event,
    ResizeObserver: SceneResizeObserver,
  };
  for (const name of GLOBAL_NAMES) {
    saved.set(name, Reflect.get(globalThis, name));
    Reflect.set(globalThis, name, values[name]);
  }
}

function restoreGlobals(): void {
  if (saved === null) return;
  for (const [name, value] of saved) Reflect.set(globalThis, name, value);
  saved = null;
}

/** A region holding `content` pixels of messages in a `box` pixel window, with no follower yet. */
export function openRegion(content: number, box: number): ScrollScene {
  closeRegion();
  const win = new Window({ url: "https://bnest.test/chat" });
  installGlobals(win);
  const region = document.createElement("div");
  document.body.append(region);
  const metrics: Metrics = { content, box, top: 0 };
  Object.defineProperty(region, "scrollHeight", {
    configurable: true,
    get: () => metrics.content,
  });
  Object.defineProperty(region, "clientHeight", {
    configurable: true,
    get: () => metrics.box,
  });
  Object.defineProperty(region, "scrollTop", {
    configurable: true,
    get: () => metrics.top,
    set: (value: number) => {
      metrics.top = Math.max(
        0,
        Math.min(Number(value), metrics.content - metrics.box),
      );
    },
  });
  scene = { window: win, region, metrics, follower: null };
  return scene;
}

/** Whether a region is open in this scenario. */
export function hasRegion(): boolean {
  return scene !== null;
}

/** The open region; a step that needs one before it is opened fails here, not later. */
export function currentRegion(): ScrollScene {
  if (scene === null)
    throw new Error("no scrolling region is open in this scenario");
  return scene;
}

/** Starts following the open region, as the room does when it mounts. */
export function followRegion(
  options: { startAtBottom?: boolean } = {},
): ScrollScene {
  const current = currentRegion();
  current.follower?.dispose();
  current.follower = createBottomFollower(current.region, options);
  return current;
}

/** The reader scrolls to `top` and the browser reports the scroll. */
export function readerScrollsTo(top: number): void {
  const current = currentRegion();
  current.region.scrollTop = top;
  current.region.dispatchEvent(new Event("scroll"));
}

/** Lets the observers' queued callbacks run. */
export function settle(): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, 0));
}

/**
 * The region gets `pixels` shorter, as when the Family Chat composer grows and the history beside it gives up the
 * room. The reader's place is kept (a browser keeps the scroll offset and only clamps it to the new maximum), and the
 * region's resize is reported to its observers.
 */
export function shrinkRegion(pixels: number): void {
  const current = currentRegion();
  current.metrics.box -= pixels;
  current.metrics.top = Math.min(
    current.metrics.top,
    current.metrics.content - current.metrics.box,
  );
  for (const observer of SceneResizeObserver.observers)
    observer.report(current.region);
}

export function closeRegion(): void {
  if (scene !== null) {
    scene.follower?.dispose();
    scene.window.close();
  }
  scene = null;
  restoreGlobals();
}
