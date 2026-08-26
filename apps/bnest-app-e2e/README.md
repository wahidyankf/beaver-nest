# bnest-app-e2e

`bnest-app-e2e` is the browser adapter for the canonical Gherkin behavior shared with [bnest-app](../bnest-app/README.md). Playwright-BDD generates native Playwright tests from that corpus. See the [repository README](../../README.md) for shared setup and test commands.

## Scope

This project owns thin browser bindings, browser configuration, and assertions across the running application boundary. Its web server injects deterministic Codex model-catalog and chat runners so acceptance tests cover discovery, model switching, streaming, and page lifecycle without a live model call. The canonical [C4 architecture model](../../specs/apps/bnest/app/architecture.md), features, and unit/integration adapters are shared concerns rooted in `specs/` and `bnest-app`; component, LiveView, controller, and domain-level tests remain with `bnest-app`.

## Quality Targets

Install the repository dependencies and Playwright's Chromium browser, then run the Nx target from the repository root:

```sh
npm install
npm exec -- playwright install chromium
npm exec -- nx run -p bnest-app-e2e -t test:quick
```

`test:quick` runs these fail-fast checks in order:

1. `typecheck` checks every `.ts` file with TypeScript strict mode, rejects implicit and explicit `any`, and emits no files.
2. `lint` runs Oxlint's correctness, suspicious, pedantic, and performance rules and rejects explicit `any`.
3. `test:coverage:behaviour` checks the unit, integration, and browser adapters against the exact recursive corpus. Its local `test:coverage:behaviour:e2e` slice runs the compliance self-tests, generates Playwright tests, and rejects undefined, ambiguous, unused, or incorrectly shaped browser bindings and scenarios.

There is no `test:unit` or aggregate `test:coverage` target because this project owns only end-to-end tests. `test:coverage:behaviour` measures complete feature-to-binding coverage without collecting numeric TypeScript line coverage or launching a browser. `test:e2e` is intentionally excluded from `test:quick` because browser tests are slow by nature.

## Authoring Behaviours

Every browser journey must originate in an English `.feature` file below [`specs/apps/bnest/app/behaviours/`](../../specs/apps/bnest/app/behaviours/). Features are discovered recursively, so adding or nesting one requires no registration. Put routes, user actions, expected content, and examples in Gherkin. Keep Playwright mechanics in thin `tests/steps/*.ts` bindings, and do not add direct `tests/**/*.spec.ts` journey files.

Every feature must contain a scenario, and every scenario must contain an explicit `When` and `Then`. `test:coverage:behaviour` fails for malformed features, missing or ambiguous bindings, incorrect binding arity, direct journey specs, and bindings unused by every feature.

During development, follow the [end-to-end testing standard](../../repo-governance/development/end-to-end-testing.md) and run only cases plausibly affected by the change. Pass a scenario-title or tag `--grep` filter through the Nx target:

```sh
npm exec -- nx run -p bnest-app-e2e -t test:e2e -- --grep "Reload preserves a completed conversation and Codex session"
```

The `test:e2e` target first enforces behavior coverage, creates an exact-cleanup marked runtime root, then uses [playwright.config.mts](playwright.config.mts) to start an isolated `bnest-app` at `http://localhost:4010`. The hostname intentionally matches Phoenix's WebSocket origin. Set `BNEST_E2E_PORT` to use another local port. Every scenario creates its own `test-user-` identity and user-owned paths within the marked run; desktop, tablet, mobile, and parallel workers never assert mutable aggregate counts. The harness never reuses a development server or production data, waits for connected LiveView state before interacting, cleans only its validated run root, and records a trace on first retry.

Chat assertions deliberately avoid exact assistant prose. The fixtures emit a stable picker-visible catalog and multiple transport updates, while the browser contract checks deterministic protocol and UI outcomes: complete admin model options, Terra/medium defaulting, locked admin selectors during turns, child Luna/medium and parent Terra/medium sessions without selectors, incremental completion, same-tab reload restoration, model changes applied to a resumed thread, and a fresh thread after **Clear chat**. The fixture rejects a switched-model prompt unless Luna/medium receives the existing thread ID, rejects reload continuation without a resumed ID, and rejects a fresh-start prompt if Clear retained that ID. The Sifat Allah browser journeys also verify a confirmed browser-progress reset that persists after reload, version-2 browser-progress compatibility across a live update, browser Back returning an active exercise to its mission dashboard, an answer locking all choices before automatic five-second advancement, every answered question immediately moving between the learned and difficult repeat queues, and the exam skipping learned questions until all 120 are learned. Semantic model quality is outside deterministic browser acceptance and belongs in representative evals with outcome-based graders.

## Structure

- `specs/apps/bnest/app/architecture.md` contains the canonical as-built C4 model.
- `specs/apps/bnest/app/behaviours/` contains the canonical executable journeys.
- `playwright.config.mts` defines BDD discovery, generated output, browser, base URL, and app server.
- `tests/steps/` contains thin Playwright-BDD bindings.
- `tests/support/authentication.ts` owns connected-LiveView setup/login helpers and scenario-scoped synthetic identities.
- `tests/support/centralized-data.ts` owns safe browser-source fixtures and user-scoped record evidence.
- `tests/support/test-runtime.mts` owns marked runtime-root creation and exact cleanup.
- `tools/run-e2e.mts` owns the guarded runtime lifecycle around the canonical Playwright target.
- `.features-gen/` contains ignored, disposable generated Playwright tests.

Keep tests focused on behavior that requires a real browser or crosses application boundaries. Prefer the narrower `bnest-app` `test:unit` or `test:integration` target when Playwright is unnecessary.
