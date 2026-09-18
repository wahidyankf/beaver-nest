import { createBdd } from "playwright-bdd";
import { restoreStorageAuthority } from "../support/storage-authority";

// Universal post-scenario cleanup. This project has no Caddy candidate to
// restore (see live-sqlite.ts), so unlike bnest-app-fe-e2e's equivalent
// browser.steps.ts hook, only the captured storage-authority snapshot (a
// no-op when no scenario captured one) needs an unconditional restore.
const { After } = createBdd();

After(() => {
  restoreStorageAuthority();
});
