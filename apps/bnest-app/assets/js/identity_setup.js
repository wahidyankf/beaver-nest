export const initializeIdentitySetup = () => {
  const addAccountButton = document.querySelector("[data-add-account]");
  const accountTemplate = document.querySelector("#account-card-template");
  const accountCards = document.querySelector("#account-cards");

  if (
    !(addAccountButton instanceof HTMLButtonElement) ||
    !(accountTemplate instanceof HTMLTemplateElement) ||
    !(accountCards instanceof HTMLElement)
  ) {
    return;
  }

  let nextIndex = accountCards.querySelectorAll("[data-account-card]").length;

  addAccountButton.addEventListener("click", () => {
    const index = nextIndex;
    nextIndex += 1;
    const wrapper = document.createElement("div");
    wrapper.innerHTML = accountTemplate.innerHTML.replaceAll(
      "__INDEX__",
      String(index),
    );
    const card = wrapper.firstElementChild;

    if (!(card instanceof HTMLFieldSetElement)) return;

    const number = card.querySelector("[data-account-number]");
    if (number) number.textContent = String(index + 1);
    accountCards.append(card);
    card.querySelector("input")?.focus();
  });

  accountCards.addEventListener("click", (event) => {
    const target = event.target;
    if (!(target instanceof Element)) return;

    const removeButton = target.closest("[data-remove-account]");
    if (!(removeButton instanceof HTMLButtonElement)) return;

    const card = removeButton.closest("[data-account-card]");
    if (!(card instanceof HTMLFieldSetElement)) return;

    card.remove();
    addAccountButton.focus();
  });
};
