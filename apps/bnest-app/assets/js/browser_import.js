/** @type {SourceDefinition[]} */
const sourceDefinitions = [
  { storageArea: "sessionStorage", storageKey: "bnest.chat.v1" },
  { storageArea: "localStorage", storageKey: "bnest.sifat-allah.v1" },
  { storageArea: "localStorage", storageKey: "phx:theme" },
];

/** @typedef {{ storageArea: StorageArea, storageKey: string }} SourceDefinition */
/** @typedef {"sessionStorage" | "localStorage"} StorageArea */

/** @param {StorageArea} area */
const storage = (area) =>
  area === "sessionStorage" ? window.sessionStorage : window.localStorage;

/** @param {SourceDefinition} source */
const readSource = ({ storageArea, storageKey }) => {
  try {
    const payload = storage(storageArea).getItem(storageKey);
    return { storageArea, storageKey, present: payload !== null, payload };
  } catch {
    return { storageArea, storageKey, present: false, payload: null };
  }
};

/** @param {string} key */
const removeAccepted = (key) => {
  const definition = sourceDefinitions.find(
    (source) => source.storageKey === key,
  );
  if (!definition) return;

  try {
    storage(definition.storageArea).removeItem(key);
  } catch {
    // The accepted server copy remains durable; the page will offer cleanup again.
  }
};

/** @type {import("phoenix_live_view").Hook} */
export const BrowserImport = {
  mounted() {
    this.pushEvent("browser-sources", {
      sources: sourceDefinitions.map((source) => readSource(source)),
    });

    this.handleEvent("imports-accepted", ({ storageKeys }) => {
      if (!Array.isArray(storageKeys)) return;
      storageKeys.forEach((key) => {
        if (typeof key === "string") removeAccepted(key);
      });
    });
  },
};
