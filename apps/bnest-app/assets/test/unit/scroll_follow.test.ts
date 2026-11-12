// @vitest-environment happy-dom
//
// Plain Vitest unit coverage for `js/scroll_follow.js`: a scrolling region that stays on its newest content while the
// reader is at its bottom, and leaves a reader who scrolled up where they are (the Codex conversation and the Family
// Chat history share it). happy-dom has no layout, so the region's metrics are modelled here the way a browser clamps
// them: a scroll position can never pass `scrollHeight - clientHeight`.

import { afterEach, describe, expect, it, vi } from "vitest";
import { createBottomFollower } from "../../js/scroll_follow.js";

interface Metrics {
  content: number;
  box: number;
  top: number;
}

/** A region of `box` pixels showing `content` pixels of messages, with its scroll position clamped as a browser does. */
function regionOf(
  content: number,
  box: number,
): { el: HTMLElement; metrics: Metrics } {
  const el = document.createElement("div");
  document.body.replaceChildren(el);
  const metrics: Metrics = { content, box, top: 0 };
  Object.defineProperty(el, "scrollHeight", {
    configurable: true,
    get: () => metrics.content,
  });
  Object.defineProperty(el, "clientHeight", {
    configurable: true,
    get: () => metrics.box,
  });
  Object.defineProperty(el, "scrollTop", {
    configurable: true,
    get: () => metrics.top,
    set: (value: number) => {
      metrics.top = Math.max(
        0,
        Math.min(Number(value), metrics.content - metrics.box),
      );
    },
  });
  return { el, metrics };
}

/** A reply arrives: a message is added below and the content grows by `pixels`. */
function reply(el: HTMLElement, metrics: Metrics, pixels: number): void {
  metrics.content += pixels;
  el.append(document.createElement("p"));
}

/** Lets the observers' queued callbacks run. */
const settle = () => new Promise((resolve) => setTimeout(resolve, 0));

/** The reader scrolls to `top` and the browser reports it. */
function scrollTo(el: HTMLElement, top: number): void {
  el.scrollTop = top;
  el.dispatchEvent(new Event("scroll"));
}

describe("createBottomFollower: a reader at the bottom", () => {
  it("opens at the newest content", () => {
    const { el, metrics } = regionOf(1000, 300);
    createBottomFollower(el);
    expect(metrics.top).toBe(700);
  });

  it("follows a reply that arrives while the reader is at the bottom", async () => {
    const { el, metrics } = regionOf(1000, 300);
    createBottomFollower(el);
    reply(el, metrics, 200);
    await settle();
    expect(metrics.top).toBe(900);
  });

  it("follows again once a picture that grew the content has loaded", async () => {
    const { el, metrics } = regionOf(1000, 300);
    createBottomFollower(el);
    const image = document.createElement("img");
    el.append(image);
    metrics.content += 400;
    image.dispatchEvent(new Event("load"));
    await settle();
    expect(metrics.top).toBe(1100);
  });
});

describe("createBottomFollower: a reader who scrolled up", () => {
  it("is not pulled to the bottom by a new reply", async () => {
    const { el, metrics } = regionOf(1000, 300);
    const follower = createBottomFollower(el);
    scrollTo(el, 100);
    expect(follower.pinned()).toBe(false);
    reply(el, metrics, 200);
    await settle();
    expect(metrics.top).toBe(100);
  });

  it("follows again once the reader scrolls back to the bottom", async () => {
    const { el, metrics } = regionOf(1000, 300);
    const follower = createBottomFollower(el);
    scrollTo(el, 100);
    scrollTo(el, metrics.content - metrics.box);
    expect(follower.pinned()).toBe(true);
    reply(el, metrics, 200);
    await settle();
    expect(metrics.top).toBe(900);
  });

  it("jumps to the newest content when the room asks it to pin, such as after the reader sends a message", async () => {
    const { el, metrics } = regionOf(1000, 300);
    const follower = createBottomFollower(el);
    scrollTo(el, 100);
    follower.pin();
    expect(follower.pinned()).toBe(true);
    expect(metrics.top).toBe(700);
  });
});

describe("createBottomFollower: disposing", () => {
  it("stops following once it is disposed", async () => {
    const { el, metrics } = regionOf(1000, 300);
    const follower = createBottomFollower(el);
    follower.dispose();
    reply(el, metrics, 200);
    await settle();
    expect(metrics.top).toBe(700);
  });

  it("reports each stick through its onStick callback", () => {
    const { el } = regionOf(1000, 300);
    let sticks = 0;
    createBottomFollower(el, { onStick: () => (sticks += 1) });
    expect(sticks).toBe(1);
  });
});

describe("createBottomFollower: a region that gets shorter", () => {
  // The region's size changes when a sibling grows (the Family Chat composer), so the follower's resize observer is the
  // only thing that sees it. The stub keeps each observer's callback and runs it when the test resizes the region.
  const resizes: Array<() => void> = [];

  // Every size observer the code under test made: what it observes, and whether it was disconnected.
  const sizeObservers: StubResizeObserver[] = [];

  class StubResizeObserver {
    readonly targets = new Set<Element>();
    disconnected = false;
    private readonly callback: () => void;
    constructor(callback: () => void) {
      this.callback = callback;
      sizeObservers.push(this);
      resizes.push(() => this.callback());
    }
    observe(target: Element): void {
      this.targets.add(target);
    }
    unobserve(target: Element): void {
      this.targets.delete(target);
    }
    disconnect(): void {
      this.disconnected = true;
      this.targets.clear();
    }
  }

  afterEach(() => {
    resizes.length = 0;
    sizeObservers.length = 0;
    vi.unstubAllGlobals();
  });

  it("keeps a reader at the bottom when the region loses height", async () => {
    vi.stubGlobal("ResizeObserver", StubResizeObserver);
    const { el, metrics } = regionOf(1000, 300);
    createBottomFollower(el, { startAtBottom: true });
    metrics.box = 240;
    resizes.forEach((resize) => resize());
    await settle();
    expect(metrics.top).toBe(760);
  });

  // A browser fires the scroll event for a frame in which the region also shrank, before the resize observer runs. The
  // reader did not move, but the geometry already reads 120 pixels from the bottom, so a reader who is judged by it
  // would be unpinned and left under the composer.
  it("keeps a reader at the bottom when a scroll event arrives in the same frame as the shrink", async () => {
    vi.stubGlobal("ResizeObserver", StubResizeObserver);
    const { el, metrics } = regionOf(1000, 300);
    createBottomFollower(el, { startAtBottom: true });
    expect(metrics.top).toBe(700);
    metrics.box = 180;
    el.dispatchEvent(new Event("scroll"));
    resizes.forEach((resize) => resize());
    await settle();
    expect(metrics.top).toBe(820);
  });

  it("leaves a reader who scrolled up where they are when the region loses height", async () => {
    vi.stubGlobal("ResizeObserver", StubResizeObserver);
    const { el, metrics } = regionOf(1000, 300);
    createBottomFollower(el, { startAtBottom: false });
    scrollTo(el, 400);
    metrics.box = 240;
    resizes.forEach((resize) => resize());
    await settle();
    expect(metrics.top).toBe(400);
  });

  it("stops observing the region's size once disposed", () => {
    vi.stubGlobal("ResizeObserver", StubResizeObserver);
    const { el } = regionOf(1000, 300);
    const follower = createBottomFollower(el, { startAtBottom: true });
    expect(sizeObservers).toHaveLength(1);
    expect(
      sizeObservers[0]?.targets.has(el),
      "the region is not observed",
    ).toBe(true);
    follower.dispose();
    expect(
      sizeObservers[0]?.disconnected,
      "the size observer is still connected after dispose",
    ).toBe(true);
    expect(
      sizeObservers[0]?.targets.size,
      "the size observer still watches the region",
    ).toBe(0);
  });
});
