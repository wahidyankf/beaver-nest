// @vitest-environment happy-dom
//
// Plain Vitest unit coverage for `js/logout.js`: logging out removes this
// member's queued family-chat messages from the device before the session
// ends, and never blocks the log-out itself.

import { afterEach, describe, expect, it } from "vitest";
import { wireLogoutQueueClearing } from "../../js/logout.js";

const USER = "test-user-logout-1";

function renderLogoutForm(userId: string | null = USER): HTMLFormElement {
  document.body.innerHTML = `
    <form action="/logout" method="post" data-role="logout"
      ${userId === null ? "" : `data-current-user-id="${userId}"`}>
      <button type="submit">Log out</button>
    </form>`;
  const form = document.querySelector("form");
  if (!form) throw new Error("no form rendered");
  return form;
}

/** Records the order the browser saw things happen in. */
function trackSubmit(form: HTMLFormElement, events: string[]): void {
  form.submit = () => {
    events.push("submitted");
  };
}

async function submit(form: HTMLFormElement): Promise<boolean> {
  const event = new Event("submit", { bubbles: true, cancelable: true });
  form.dispatchEvent(event);
  return event.defaultPrevented;
}

async function until(predicate: () => boolean): Promise<void> {
  for (let attempt = 0; attempt < 200; attempt += 1) {
    if (predicate()) return;
    await new Promise((resolve) => setTimeout(resolve, 1));
  }
  throw new Error("timed out");
}

afterEach(() => {
  document.body.innerHTML = "";
});

describe("wireLogoutQueueClearing", () => {
  it("clears the member's queue before the log-out request is sent", async () => {
    const events: string[] = [];
    const form = renderLogoutForm();
    trackSubmit(form, events);
    wireLogoutQueueClearing({
      persistence: {
        clearUser: async (userId: string) => {
          await Promise.resolve();
          events.push(`cleared ${userId}`);
        },
      },
    });

    expect(await submit(form)).toBe(true);
    await until(() => events.includes("submitted"));

    expect(events).toEqual([`cleared ${USER}`, "submitted"]);
  });

  it("still logs out when the device refuses to clear", async () => {
    const events: string[] = [];
    const form = renderLogoutForm();
    trackSubmit(form, events);
    wireLogoutQueueClearing({
      persistence: {
        clearUser: async () => {
          throw new Error("storage unavailable");
        },
      },
    });

    await submit(form);
    await until(() => events.includes("submitted"));

    expect(events).toEqual(["submitted"]);
  });

  it("does not hold the log-out hostage to a clear that never finishes", async () => {
    const events: string[] = [];
    const form = renderLogoutForm();
    trackSubmit(form, events);
    wireLogoutQueueClearing({
      persistence: { clearUser: () => new Promise<void>(() => {}) },
      timeoutMs: 5,
    });

    await submit(form);
    await until(() => events.includes("submitted"));

    expect(events).toEqual(["submitted"]);
  });

  it("submits only once however many times it is pressed", async () => {
    const events: string[] = [];
    const form = renderLogoutForm();
    trackSubmit(form, events);
    wireLogoutQueueClearing({
      persistence: {
        clearUser: async () => {
          await new Promise((resolve) => setTimeout(resolve, 5));
        },
      },
    });

    await submit(form);
    expect(await submit(form)).toBe(true);
    await until(() => events.includes("submitted"));
    await new Promise((resolve) => setTimeout(resolve, 20));

    expect(events).toEqual(["submitted"]);
  });

  it("leaves a log-out form that names no member to submit on its own", async () => {
    const form = renderLogoutForm(null);
    let cleared = false;
    wireLogoutQueueClearing({
      persistence: {
        clearUser: async () => {
          cleared = true;
        },
      },
    });

    expect(await submit(form)).toBe(false);
    expect(cleared).toBe(false);
  });

  it("does nothing on a page without a log-out form", () => {
    document.body.innerHTML = "<main></main>";

    expect(() =>
      wireLogoutQueueClearing({ persistence: { clearUser: async () => {} } }),
    ).not.toThrow();
  });
});
