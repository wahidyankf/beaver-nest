import { defineConfig } from "vitest/config";

// Frontend unit-test project for the family chat browser modules
// (`js/family_chat.js` and `js/family_chat/*.js`). No browser and no
// network: the `test/behaviour/*` Gherkin bindings and the plain
// `test/unit/**/*.test.ts` specs both call the production modules directly
// (see tech-doc 006's Proof Matrix and tech-doc 007's File Impact list
// under "Application unit and integration adapters").
//
// `environment: "node"` is the default because most of what these modules
// decide is not markup. Files that do need a DOM opt in per file with
// `// @vitest-environment happy-dom`, and the Gherkin scenarios' browser
// (`test/behaviour/support/browser_room.ts`) installs and removes one page
// at a time itself, so no page outlives the scenario that opened it.
//
// This config enforces no coverage threshold; `coverage` only reports.
export default defineConfig({
  test: {
    environment: "node",
    include: ["test/behaviour/verify.ts", "test/**/*.test.ts"],
    coverage: {
      provider: "v8",
      include: ["js/family_chat.js", "js/family_chat/**/*.js"],
      reporter: ["text", "json-summary"],
    },
  },
});
