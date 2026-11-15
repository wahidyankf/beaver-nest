// Plain Vitest unit coverage for `js/viewport_height.js` (ADR 005, decision 5). The module writes the visual viewport's
// height to `--vvh` on the room pages only, leaves the height alone while the visitor is pinch-zoomed, and puts the page
// back at the top only when a room page has scrolled. The browser objects are fakes: the behaviour under a real soft
// keyboard is checked only by a real phone (see ADR 005, Accepted limits).

import { describe, expect, it, vi } from "vitest";
import { installVisualViewportHeight } from "../../js/viewport_height.js";

interface FakeViewport extends EventTarget {
  height: number;
  scale: number;
}

interface FakeWindow {
  visualViewport: FakeViewport | null;
  scrollY: number;
  scrollTo: ReturnType<typeof vi.fn>;
  addEventListener: EventTarget["addEventListener"];
  dispatchEvent: EventTarget["dispatchEvent"];
  document: {
    documentElement: { style: { setProperty: ReturnType<typeof vi.fn> } };
    querySelector: (selector: string) => object | null;
  };
}

function fakeViewport(height: number): FakeViewport {
  return Object.assign(new EventTarget(), { height, scale: 1 });
}

// A window whose page has a room shell when `room` is true. The room is a flag, so a test can add it later.
function fakeWindow(viewport: FakeViewport | null, room: { present: boolean }) {
  const setProperty = vi.fn();
  const scrollTo = vi.fn();
  const win: FakeWindow = Object.assign(new EventTarget(), {
    visualViewport: viewport,
    scrollY: 0,
    scrollTo,
    document: {
      documentElement: { style: { setProperty } },
      querySelector: (selector: string) => {
        expect(selector).toBe(".chat-shell, .family-chat-shell");
        return room.present ? {} : null;
      },
    },
  }) as unknown as FakeWindow;
  return { win, setProperty, scrollTo };
}

describe("installVisualViewportHeight on a room page", () => {
  it("writes the visual viewport height to --vvh", () => {
    const { win, setProperty } = fakeWindow(fakeViewport(240), {
      present: true,
    });
    installVisualViewportHeight(win as unknown as Window);
    expect(setProperty).toHaveBeenCalledWith("--vvh", "240px");
  });

  it("does not scroll when the page is already at the top", () => {
    const { win, scrollTo } = fakeWindow(fakeViewport(240), { present: true });
    installVisualViewportHeight(win as unknown as Window);
    expect(scrollTo).not.toHaveBeenCalled();
  });

  it("puts the page back at the top when it has scrolled", () => {
    const { win, scrollTo } = fakeWindow(fakeViewport(240), { present: true });
    win.scrollY = 120;
    installVisualViewportHeight(win as unknown as Window);
    expect(scrollTo).toHaveBeenCalledWith(0, 0);
  });

  it("follows the visual viewport on resize", () => {
    const viewport = fakeViewport(844);
    const { win, setProperty } = fakeWindow(viewport, { present: true });
    installVisualViewportHeight(win as unknown as Window);
    viewport.height = 430;
    viewport.dispatchEvent(new Event("resize"));
    expect(setProperty).toHaveBeenLastCalledWith("--vvh", "430px");
  });

  it("does not shrink --vvh while the visitor is pinch-zoomed, and follows again at scale 1", () => {
    const viewport = fakeViewport(844);
    const { win, setProperty } = fakeWindow(viewport, { present: true });
    installVisualViewportHeight(win as unknown as Window);
    setProperty.mockClear();
    viewport.scale = 2;
    viewport.height = 400;
    viewport.dispatchEvent(new Event("resize"));
    expect(setProperty).not.toHaveBeenCalled();
    viewport.scale = 1;
    viewport.dispatchEvent(new Event("resize"));
    expect(setProperty).toHaveBeenLastCalledWith("--vvh", "400px");
  });

  it("picks up a room that LiveView renders after the module was installed", () => {
    const room = { present: false };
    const viewport = fakeViewport(390);
    const { win, setProperty } = fakeWindow(viewport, room);
    installVisualViewportHeight(win as unknown as Window);
    expect(setProperty).not.toHaveBeenCalled();
    room.present = true;
    win.dispatchEvent(new Event("phx:page-loading-stop"));
    expect(setProperty).toHaveBeenCalledWith("--vvh", "390px");
  });
});

describe("installVisualViewportHeight on any other page", () => {
  it("writes nothing and does not scroll on a resize", () => {
    const viewport = fakeViewport(844);
    const { win, setProperty, scrollTo } = fakeWindow(viewport, {
      present: false,
    });
    installVisualViewportHeight(win as unknown as Window);
    win.scrollY = 300;
    viewport.height = 430;
    viewport.dispatchEvent(new Event("resize"));
    viewport.dispatchEvent(new Event("scroll"));
    expect(setProperty).not.toHaveBeenCalled();
    expect(scrollTo).not.toHaveBeenCalled();
  });
});

describe("installVisualViewportHeight in other situations", () => {
  it("does nothing without a visual viewport, so the stylesheet's 100dvh fallback applies", () => {
    const { win, setProperty, scrollTo } = fakeWindow(null, { present: true });
    let stop: (() => void) | undefined;
    expect(() => {
      stop = installVisualViewportHeight(win as unknown as Window);
    }).not.toThrow();
    expect(setProperty).not.toHaveBeenCalled();
    expect(scrollTo).not.toHaveBeenCalled();
    expect(() => stop?.()).not.toThrow();
  });

  it("is harmless when installed a second time: one set of listeners, the same stop", () => {
    const viewport = fakeViewport(844);
    const { win, setProperty } = fakeWindow(viewport, { present: true });
    const first = installVisualViewportHeight(win as unknown as Window);
    const second = installVisualViewportHeight(win as unknown as Window);
    expect(second).toBe(first);
    setProperty.mockClear();
    viewport.height = 430;
    viewport.dispatchEvent(new Event("resize"));
    expect(setProperty).toHaveBeenCalledTimes(1);
  });

  it("stops following once the returned function runs, and can be installed again", () => {
    const viewport = fakeViewport(844);
    const { win, setProperty } = fakeWindow(viewport, { present: true });
    const stop = installVisualViewportHeight(win as unknown as Window);
    stop();
    setProperty.mockClear();
    viewport.height = 430;
    viewport.dispatchEvent(new Event("resize"));
    expect(setProperty).not.toHaveBeenCalled();
    installVisualViewportHeight(win as unknown as Window);
    viewport.dispatchEvent(new Event("resize"));
    expect(setProperty).toHaveBeenCalledWith("--vvh", "430px");
  });
});
