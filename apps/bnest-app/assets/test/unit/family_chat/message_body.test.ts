// @vitest-environment happy-dom
//
// Plain Vitest unit coverage for `js/family_chat/message_body.js`, the one module that writes server HTML into
// the Family Chat page (ADR 003, Decision 2, browser rules 2-4). Each test states one rule of that contract and
// asserts on the element a member would see. The HTML below is the shape the server's shared component emits
// (`BnestAppWeb.ChatComponents`), copied as literals so these tests do not depend on the renderer.

import { readdirSync, readFileSync } from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";
import {
  committedBodyNode,
  rawBodyOf,
  textBodyNode,
} from "../../../js/family_chat/message_body.js";
import { messageNode } from "../../../js/family_chat/message_render.js";
import { messageFrom } from "../../../js/family_chat/mount_browser_actions.js";
import { rovingInvariantHolds } from "../../../js/family_chat/roving_focus.js";

const WRAPPER_OPEN =
  '<div phx-r class="message-content markdown-body family-chat-message-body" data-role="family-chat-message-body">';

const BOLD_LINK_HTML = `${WRAPPER_OPEN}<p><strong>Dinner</strong> is at <a href="https://example.test/home" rel="noopener noreferrer nofollow" target="_blank">home</a></p></div>`;

describe("a committed message with server HTML", () => {
  it("is the server's markdown-body element, marked as formatted", () => {
    const node = committedBodyNode({
      body: "**Dinner**",
      bodyHtml: BOLD_LINK_HTML,
    });

    expect(node.tagName).toBe("DIV");
    expect(node.classList.contains("markdown-body")).toBe(true);
    expect(node.dataset["bodyFormat"]).toBe("markdown");
    expect(node.querySelector("strong")?.textContent).toBe("Dinner");
  });

  // In dev, the server's HEEx debug annotations wrap the component in comments. A comment is not content, so the
  // same root is adopted, and the message is not shown as text.
  it("is the markdown-body element when HTML comments wrap it, as the dev annotations do", () => {
    const bodyHtml = `<!-- <BnestAppWeb.ChatComponents.markdown_body> lib/bnest_app_web/components/chat_components.ex:36 -->${BOLD_LINK_HTML}<!-- </BnestAppWeb.ChatComponents.markdown_body> -->`;
    const node = committedBodyNode({ body: "**Dinner**", bodyHtml });

    expect(node.dataset["bodyFormat"]).toBe("markdown");
    expect(node.querySelector("strong")?.textContent).toBe("Dinner");
  });

  it("still refuses a second element next to the root, even with comments around it", () => {
    const bodyHtml = `<!-- note -->${BOLD_LINK_HTML}<p>tail</p>`;
    const node = committedBodyNode({ body: "raw source", bodyHtml });

    expect(node.dataset["bodyFormat"]).toBe("text");
  });

  it("accepts the phx-r attribute the layout puts on the wrapper", () => {
    const node = committedBodyNode({ body: "x", bodyHtml: BOLD_LINK_HTML });

    expect(node.dataset["bodyFormat"]).toBe("markdown");
  });

  it("is the text paragraph when bodyHtml is absent", () => {
    for (const bodyHtml of [undefined, null]) {
      const node = committedBodyNode({ body: "**Dinner**", bodyHtml });

      expect(node.tagName).toBe("P");
      expect(node.dataset["bodyFormat"]).toBe("text");
      expect(node.textContent).toBe("**Dinner**");
    }
  });

  it("is the text paragraph when the HTML is not exactly one markdown-body root", () => {
    const shapes = [
      "<p>not a wrapper</p>",
      `${WRAPPER_OPEN}<p>a</p></div>${WRAPPER_OPEN}<p>b</p></div>`,
      '<div class="message-content"><p>a</p></div>',
      `${WRAPPER_OPEN}<p>a</p></div>tail text outside the root`,
      "",
    ];
    for (const bodyHtml of shapes) {
      const node = committedBodyNode({ body: "raw source", bodyHtml });

      expect(node.tagName, bodyHtml).toBe("P");
      expect(node.dataset["bodyFormat"], bodyHtml).toBe("text");
      expect(node.textContent, bodyHtml).toBe("raw source");
    }
  });

  it("is the text paragraph when the HTML contains a script, and no script is kept", () => {
    const bodyHtml = `${WRAPPER_OPEN}<p>hi</p><script>window.__familyChatRan = true</script></div>`;
    const node = committedBodyNode({ body: "hi", bodyHtml });

    expect(node.dataset["bodyFormat"]).toBe("text");
    expect(document.querySelector("script[data-family-chat]")).toBeNull();
    expect(node.querySelector("script")).toBeNull();
  });

  it("is the text paragraph when an element carries an event-handler attribute", () => {
    const bodyHtml = `${WRAPPER_OPEN}<p><img src="https://images.example.test/x.png" onerror="window.__familyChatRan = true"></p></div>`;
    const node = committedBodyNode({ body: "image", bodyHtml });

    expect(node.dataset["bodyFormat"]).toBe("text");
    expect(node.querySelector("img")).toBeNull();
  });

  it("never adopts a rejected payload's image, so no image request starts", () => {
    const bodyHtml = `${WRAPPER_OPEN}<p><img src="https://images.example.test/tracker.png"></p><p><script>1</script></p></div>`;
    committedBodyNode({ body: "tracked", bodyHtml });

    expect(document.querySelectorAll("img")).toHaveLength(0);
  });

  it("makes every link and checkbox inside it untabbable", () => {
    const bodyHtml = `${WRAPPER_OPEN}<ul><li><input type="checkbox" disabled> task</li></ul><p><a href="https://example.test/a">a</a></p></div>`;
    const node = committedBodyNode({ body: "x", bodyHtml });
    const controls = [...node.querySelectorAll<HTMLElement>("a[href], input")];

    expect(controls).toHaveLength(2);
    for (const control of controls) expect(control.tabIndex).toBe(-1);
  });

  it("makes every table and code block inside it untabbable until the history raises the stop", () => {
    const bodyHtml = `${WRAPPER_OPEN}<table><tr><td>Rice</td></tr></table><pre><code>rice for four</code></pre></div>`;
    const node = committedBodyNode({ body: "x", bodyHtml });
    const regions = [...node.querySelectorAll<HTMLElement>("table, pre")];

    expect(regions).toHaveLength(2);
    for (const region of regions)
      expect(region.getAttribute("tabindex")).toBe("-1");
  });

  it("keeps the wrapper's classes and the body role the styles and actions read", () => {
    const node = committedBodyNode({ body: "x", bodyHtml: BOLD_LINK_HTML });

    expect(node.classList.contains("family-chat-message-body")).toBe(true);
    expect(node.dataset["role"]).toBe("family-chat-message-body");
  });
});

describe("the text fallback", () => {
  it("is a paragraph holding the body as text, marked as text", () => {
    const node = textBodyNode("first line\n<b>not bold</b>");

    expect(node.tagName).toBe("P");
    expect(node.dataset["bodyFormat"]).toBe("text");
    expect(node.dataset["role"]).toBe("family-chat-message-body");
    expect(node.textContent).toBe("first line\n<b>not bold</b>");
    expect(node.querySelector("b")).toBeNull();
  });
});

describe("the raw body", () => {
  it("is the typed source for a formatted message", () => {
    const node = committedBodyNode({
      body: "**Dinner** is at [home](https://example.test/home)",
      bodyHtml: BOLD_LINK_HTML,
    });

    expect(rawBodyOf(node)).toBe(
      "**Dinner** is at [home](https://example.test/home)",
    );
  });

  it("is the body for the text fallback", () => {
    expect(rawBodyOf(textBodyNode("plain"))).toBe("plain");
  });

  it("is undefined for an element this module did not build", () => {
    expect(rawBodyOf(document.createElement("p"))).toBeUndefined();
  });
});

describe("copy and Reply read the source, not the rendered text", () => {
  it("reads the typed Markdown from a formatted committed message", () => {
    const row = messageNode(
      {
        id: "1001",
        body: "**Dinner** is at [home](https://example.test/home)",
        bodyHtml: BOLD_LINK_HTML,
        senderDisplayName: "Ayah",
        senderId: "u-ayah",
      },
      { pending: false, currentUserId: "u-me" },
    );

    expect(messageFrom(row).body).toBe(
      "**Dinner** is at [home](https://example.test/home)",
    );
  });

  it("reads the body of a message with no server HTML the way it did before", () => {
    const row = messageNode(
      {
        id: "1002",
        body: "Dinner is ready",
        senderDisplayName: "Ayah",
        senderId: "u-ayah",
      },
      { pending: false, currentUserId: "u-me" },
    );

    expect(messageFrom(row).body).toBe("Dinner is ready");
  });
});

describe("pending and failed rows", () => {
  it("are always the text paragraph, even when a bodyHtml arrives for the body", () => {
    const row = messageNode(
      {
        clientMessageId: "c-1",
        body: "**not yet**",
        bodyHtml: BOLD_LINK_HTML,
        status: "Sending",
        senderId: "u-me",
        senderDisplayName: "Me",
      },
      { pending: true, currentUserId: "u-me" },
    );
    const body = row.querySelector<HTMLElement>(
      '[data-role="family-chat-message-body"]',
    );

    expect(body?.tagName).toBe("P");
    expect(body?.dataset["bodyFormat"]).toBe("text");
    expect(body?.textContent).toBe("**not yet**");
    expect(body?.querySelector("strong")).toBeNull();
  });
});

describe("the tab stop with formatted content", () => {
  it("holds for a message with a link and a task list", () => {
    const list = document.createElement("ol");
    const bodyHtml = `${WRAPPER_OPEN}<ul><li><input type="checkbox" disabled> buy milk</li></ul><p><a href="https://example.test/">home</a></p></div>`;
    list.append(
      messageNode(
        {
          id: "2001",
          body: "- [ ] buy milk",
          bodyHtml,
          senderId: "u-ayah",
          senderDisplayName: "Ayah",
        },
        { pending: false, currentUserId: "u-me" },
      ),
      messageNode(
        {
          id: "2002",
          body: "next",
          senderId: "u-ayah",
          senderDisplayName: "Ayah",
        },
        { pending: false, currentUserId: "u-me" },
      ),
    );
    const first = list.querySelector<HTMLElement>('[data-message-id="2001"]');
    first?.setAttribute("tabindex", "0");

    expect(rovingInvariantHolds(list)).toBe(true);
  });
});

// The one insertion point (ADR 003, threat table: "XSS through innerHTML of bodyHtml"). A grep, not a
// behaviour: it fails the moment a second module parses or writes HTML, which the rendering tests cannot see.
describe("the only insertion of server HTML", () => {
  const familyChatDir = path.resolve(
    import.meta.dirname,
    "../../../js/family_chat",
  );
  const sources = readdirSync(familyChatDir)
    .filter((file) => file.endsWith(".js"))
    .map((file) => ({
      file,
      text: readFileSync(path.join(familyChatDir, file), "utf8"),
    }));

  // Writes that put markup into the page or parse markup into nodes.
  const markupWrite =
    /\binnerHTML\s*=(?!=)|\binsertAdjacentHTML\b|\bcreateContextualFragment\b|\bDOMParser\b|\bouterHTML\s*=(?!=)/u;

  it("finds the module sources it inspects", () => {
    expect(sources.length).toBeGreaterThan(10);
  });

  it("is written only in message_body.js and in message_render.js's escaped sender line", () => {
    const writers = sources
      .filter(({ text }) => markupWrite.test(text))
      .map(({ file }) => file)
      .sort();

    expect(writers).toEqual(["message_body.js", "message_render.js"]);
  });

  it("parses server HTML only in message_body.js", () => {
    for (const { file, text } of sources) {
      if (file === "message_body.js") continue;
      expect(text, file).not.toMatch(
        /<template\b|\.content\b.*\.append|\.content\.firstElementChild/u,
      );
      expect(text, file).not.toMatch(
        /\bbodyHtml\b.*\binnerHTML\b|\binnerHTML\b.*\bbodyHtml\b/u,
      );
    }
  });

  it("never names bodyHtml in a module that stores or renders outside the body", () => {
    for (const { file, text } of sources) {
      if (
        ["operations.js", "message_body.js", "message_render.js"].includes(file)
      )
        continue;
      expect(text, file).not.toMatch(/\bbodyHtml\b/u);
    }
  });
});
