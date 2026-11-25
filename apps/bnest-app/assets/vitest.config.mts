import { fileURLToPath } from "node:url";
import { dirname, resolve as resolvePath } from "node:path";
import { defineConfig } from "vitest/config";

const here = dirname(fileURLToPath(import.meta.url));

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
// The unit gate enforces the 99% line floor (plan T10/BN-1, AC-19): the
// `test:unit:fe` target always passes `--coverage`, and a run below the
// threshold exits non-zero.
export default defineConfig({
  resolve: {
    // Mirrors the esbuild bundle's `NODE_PATH` (`../deps`): the Phoenix
    // JavaScript clients ship inside the Hex packages, not npm, so the unit
    // run resolves the same files the bundle does. Behaviour doubles replace
    // them through `vi.mock` wherever a test needs control.
    alias: [
      {
        find: "phoenix_html",
        replacement: resolvePath(
          here,
          "../deps/phoenix_html/priv/static/phoenix_html.js",
        ),
      },
      {
        find: "phoenix_live_view",
        replacement: resolvePath(
          here,
          "../deps/phoenix_live_view/priv/static/phoenix_live_view.esm.js",
        ),
      },
      {
        find: "phoenix-colocated/bnest_app",
        replacement: resolvePath(
          here,
          "../_build/test/phoenix-colocated/bnest_app/index.js",
        ),
      },
    ],
  },
  test: {
    environment: "node",
    // The Node binary that runs this suite. Unit tests read it with inject(),
    // because the oxlint unit override bans the process global.
    provide: { nodeBinary: process.execPath },
    // 30s budget: suite growth plus coverage load contends the slowest pickle past the 5s default; isolated runs pass, so this is load, not a hang.
    testTimeout: 30_000,
    include: ["test/behaviour/verify.ts", "test/**/*.test.ts"],
    coverage: {
      provider: "v8",
      include: [
        "js/family_chat.js",
        "js/family_chat/**/*.js",
        "js/diagrams/**/*.js",
        "js/chat_keys.js",
        "js/chat_controls.js",
        // Top-level page modules measured from T10: every authored production
        // file under `js/` sits in the unit denominator (the worker in
        // `priv/static/` keeps its dedicated handler tests; it is not an
        // importable page module, so v8 cannot instrument it).
        "js/app.js",
        "js/browser_import.js",
        "js/codex_composer_hook.js",
        "js/identity_setup.js",
        "js/logout.js",
        "js/scroll_follow.js",
        "js/scroll_region_names.js",
        "js/sifat_celebration.js",
        "js/sifat_history.js",
        "js/sifat_swipe.js",
        "js/viewport_height.js",
      ],
      reporter: ["text", "json-summary"],
      thresholds: {
        lines: 99,
      },
    },
  },
});
