// @vitest-environment happy-dom
//
// Plain Vitest unit coverage for `js/codex_composer_hook.js` (ADR 005, decision 1). The Codex message box is a LiveView
// hook: when the visitor sends, the server clears the box in a patch. Text typed between the send and that patch must
// survive the clear. Each test drives the hook through the lifecycle LiveView calls, on a real textarea in happy-dom.

import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { ChatComposer, typedAfterSend } from "../../js/codex_composer_hook.js";

interface Mounted {
  el: HTMLTextAreaElement;
  sent: string | null;
  before: string | null;
  kept: string | null;
  form: HTMLFormElement | null;
  onSubmit: (() => void) | null;
  mounted(): void;
  beforeUpdate(): void;
  updated(): void;
  destroyed(): void;
}

let form: HTMLFormElement;
let box: HTMLTextAreaElement;
let hook: Mounted;

// One LiveView patch of the form: the hook is told before and after the server writes the box. `serverValue` is what the
// server renders into the box; `null` means the patch leaves the box alone.
function patch(serverValue: string | null): void {
  hook.beforeUpdate();
  if (serverValue !== null) box.value = serverValue;
  hook.updated();
}

beforeEach(() => {
  document.body.innerHTML = `<form id="chat-composer-form"><textarea data-role="chat-composer"></textarea></form>`;
  form = document.querySelector("form") as HTMLFormElement;
  box = document.querySelector("textarea") as HTMLTextAreaElement;
  hook = Object.assign(Object.create(ChatComposer), { el: box }) as Mounted;
  hook.mounted();
});

afterEach(() => {
  hook.destroyed();
  document.body.innerHTML = "";
});

describe("typedAfterSend", () => {
  it("keeps only the text beyond the sent text", () => {
    expect(typedAfterSend("Keyboard send and more", "Keyboard send")).toBe(
      " and more",
    );
  });

  it("is empty when nothing was typed after the send", () => {
    expect(typedAfterSend("Keyboard send", "Keyboard send")).toBe("");
  });

  it("keeps the whole box when it no longer starts with the sent text", () => {
    expect(typedAfterSend("Edited", "Keyboard send")).toBe("Edited");
  });
});

describe("ChatComposer across a send", () => {
  it("keeps the text typed after the send when the server clears the box", () => {
    box.value = "Keyboard send";
    form.dispatchEvent(new Event("submit", { cancelable: true }));
    box.value = "Keyboard send and more";

    patch("");

    expect(box.value).toBe(" and more");
  });

  it("leaves the box empty when nothing was typed after the send", () => {
    box.value = "Keyboard send";
    form.dispatchEvent(new Event("submit", { cancelable: true }));

    patch("");

    expect(box.value).toBe("");
  });

  it("does not touch the box on a patch that leaves its text in place", () => {
    box.value = "Keyboard send";
    form.dispatchEvent(new Event("submit", { cancelable: true }));
    box.value = "Keyboard send and more";

    patch(null);

    expect(box.value).toBe("Keyboard send and more");
  });

  it("restores nothing on a patch that clears a box the visitor never sent from", () => {
    box.value = "A draft";

    patch("");

    expect(box.value).toBe("");
  });

  it("forgets the send once the clear has come, so text typed later is not overwritten", () => {
    box.value = "Keyboard send";
    form.dispatchEvent(new Event("submit", { cancelable: true }));
    box.value = "Keyboard send and more";
    patch("");

    box.value = "Next question";
    patch(null);

    expect(box.value).toBe("Next question");
  });

  it("stops listening to the form when it is destroyed", () => {
    hook.destroyed();
    box.value = "Keyboard send";
    form.dispatchEvent(new Event("submit", { cancelable: true }));
    box.value = "Keyboard send and more";

    patch("");

    expect(box.value).toBe("");
    hook.mounted();
  });
});
