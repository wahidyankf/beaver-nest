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
// `// @vitest-environment happy-dom`, and the reply scenarios' room
// (`test/behaviour/support/reply_room.ts`) installs and removes one itself,
// because its sibling scenarios must keep running without a `document` --
// `initRoom` branches on exactly that.
//
// Coverage thresholds are intentionally not enforced yet: the
// production modules and their dedicated unit tests
// (`test/unit/family_chat/{outbox,reconnect,state}.test.ts`) are Phase 3+
// "code" deliverables, so enforcing "at least 99% line coverage" during
// Phase 2 RED would fail for a coverage-tooling reason instead of the
// genuine "feature absent" reason the plan requires (see learnings.md).
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
