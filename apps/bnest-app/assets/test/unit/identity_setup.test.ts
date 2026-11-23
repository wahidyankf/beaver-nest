// @vitest-environment happy-dom
//
// Plain Vitest unit coverage for `js/identity_setup.js`: the setup page adds
// account cards from the template and removes them again, and stays inert
// when its shell is absent.

import { afterEach, describe, expect, it } from "vitest";
import { initializeIdentitySetup } from "../../js/identity_setup.js";

function renderShell(): {
  add: HTMLButtonElement;
  cards: HTMLElement;
} {
  document.body.innerHTML = `
    <button type="button" data-add-account>Add account</button>
    <template id="account-card-template">
      <fieldset data-account-card>
        <legend data-account-number>Account 1</legend>
        <input name="accounts[__INDEX__][username]" />
        <button type="button" data-remove-account>Remove</button>
      </fieldset>
    </template>
    <div id="account-cards"></div>`;
  const add = document.querySelector("[data-add-account]");
  const cards = document.querySelector("#account-cards");
  if (!(add instanceof HTMLButtonElement)) throw new Error("no add button");
  if (!(cards instanceof HTMLElement)) throw new Error("no cards");
  return { add, cards };
}

afterEach(() => {
  document.body.innerHTML = "";
});

describe("initializeIdentitySetup", () => {
  it("adds a numbered card from the template on each click", () => {
    const { add, cards } = renderShell();
    initializeIdentitySetup();

    add.click();
    add.click();

    const rendered = cards.querySelectorAll("[data-account-card]");
    expect(rendered).toHaveLength(2);
    expect(
      rendered[0]?.querySelector("[data-account-number]")?.textContent,
    ).toBe("1");
    expect(
      rendered[1]?.querySelector("[data-account-number]")?.textContent,
    ).toBe("2");
    const input = rendered[1]?.querySelector("input");
    expect(input?.getAttribute("name")).toBe("accounts[1][username]");
  });

  it("removes a card and returns focus to the add button", () => {
    const { add, cards } = renderShell();
    initializeIdentitySetup();

    add.click();
    const remove = cards.querySelector("[data-remove-account]");
    if (!(remove instanceof HTMLButtonElement))
      throw new Error("no remove button");
    remove.click();

    expect(cards.querySelectorAll("[data-account-card]")).toHaveLength(0);
    expect(document.activeElement).toBe(add);
  });

  it("stays inert when the setup shell is absent", () => {
    document.body.innerHTML = `<main><p>No setup here</p></main>`;
    expect(() => initializeIdentitySetup()).not.toThrow();
  });

  // @scenario specs/apps/bnest/app-fe/behaviours/authentication.feature: The setup page adds and removes family member cards
  it("adds and removes a family member card around the initial administrator card", () => {
    document.body.innerHTML = `
    <button type="button" data-add-account>Add another initial account</button>
    <template id="account-card-template">
      <fieldset data-account-card>
        <legend>Family member <span data-account-number></span></legend>
        <input name="accounts[__INDEX__][username]" />
        <button type="button" data-remove-account>Remove this account</button>
      </fieldset>
    </template>
    <div id="account-cards">
      <fieldset data-account-card>
        <legend>Initial administrator</legend>
        <input name="accounts[0][username]" />
      </fieldset>
    </div>`;
    const add = document.querySelector("[data-add-account]");
    const cards = document.querySelector("#account-cards");
    if (!(add instanceof HTMLButtonElement)) throw new Error("no add button");
    if (!(cards instanceof HTMLElement)) throw new Error("no cards");
    initializeIdentitySetup();

    const initial = cards.querySelectorAll("[data-account-card]");
    expect(initial).toHaveLength(1);
    expect(initial[0]?.textContent).toContain("Initial administrator");
    expect(initial[0]?.querySelector("[data-remove-account]")).toBeNull();

    add.click();

    const grown = cards.querySelectorAll("[data-account-card]");
    expect(grown).toHaveLength(2);
    expect(grown[1]?.querySelector("[data-account-number]")?.textContent).toBe(
      "2",
    );
    const username = grown[1]?.querySelector("input");
    expect(username?.getAttribute("name")).toBe("accounts[1][username]");
    expect(document.activeElement).toBe(username);

    const remove = grown[1]?.querySelector("[data-remove-account]");
    if (!(remove instanceof HTMLButtonElement))
      throw new Error("no remove button");
    remove.click();

    expect(cards.querySelectorAll("[data-account-card]")).toHaveLength(1);
    expect(document.activeElement).toBe(add);
  });
});
