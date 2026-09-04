# bnest-app-e2e

`bnest-app-e2e` is the browser adapter for the canonical Gherkin behaviour shared with [bnest-app](../bnest-app/README.md). Playwright-BDD generates native Playwright tests from that corpus. See the [repository README](../../README.md) for shared setup and test commands.

## Scope

This project owns thin browser bindings, browser configuration, and assertions across the running application boundary. Its web server injects deterministic Codex model-catalog and chat runners so acceptance tests cover discovery, model switching, streaming, and page lifecycle without a live model call. The canonical [C4 architecture model](../../specs/apps/bnest/app/architecture.md), features, and unit/integration adapters are shared concerns rooted in `specs/` and `bnest-app`; component, LiveView, controller, and domain-level tests remain with `bnest-app`.

## Quality Targets

Install the repository dependencies and Playwright's Chromium browser, then run the Nx target from the repository root through the workspace [HIPPO](../../repo-governance/development/resource-aware-development.md):

```sh
npm install
npm exec -- playwright install chromium
./hippo run --class ephemeral -- npm exec -- nx run -p bnest-app-e2e -t test:quick
```

`test:quick` owns and runs these fail-fast checks in order, without depending on the application's complete quick gate:

1. `typecheck` checks every `.ts` file with TypeScript strict mode, rejects implicit and explicit `any`, and emits no files.
2. `lint` runs Oxlint's correctness, suspicious, pedantic, and performance rules and rejects explicit `any`.
3. `test:coverage:behaviour` checks the unit, integration, and browser adapters against the exact recursive corpus. Its local `test:coverage:behaviour:e2e` slice runs the compliance self-tests, generates Playwright tests, and rejects undefined, ambiguous, unused, or incorrectly shaped browser bindings and scenarios.

The managed Bnest release uses `test:release-quick` after the application quick gate. It runs this project's typecheck and lint without needlessly repeating the already-passed application quick and shared behaviour checks.

There is no `test:unit` or aggregate `test:coverage` target because this project owns only end-to-end tests. `test:coverage:behaviour` measures complete feature-to-binding coverage without collecting numeric TypeScript line coverage or launching a browser. `test:e2e` is intentionally excluded from `test:quick` because browser tests are slow by nature.

## Authoring Behaviours

Every browser journey must originate in an English `.feature` file below [`specs/apps/bnest/app/behaviours/`](../../specs/apps/bnest/app/behaviours/). Features are discovered recursively, so adding or nesting one requires no registration. Put routes, user actions, expected content, and examples in Gherkin. Keep Playwright mechanics in thin `tests/steps/*.ts` bindings, and do not add direct `tests/**/*.spec.ts` journey files.

Every feature must contain a scenario, and every scenario must contain an explicit `When` and `Then`. `test:coverage:behaviour` fails for malformed features, missing or ambiguous bindings, incorrect binding arity, direct journey specs, invalid exemption tags, and bindings unused by every feature. Runtime excludes only a scenario carrying a documented `@e2e-exempt`; unit has no exemption, and `@integration-exempt` affects only the integration adapter. A green static check never substitutes for the [manual one-by-one implementation review](../../repo-governance/workflows/gherkin-implementation-review.md).

During development, follow the [end-to-end testing standard](../../repo-governance/development/end-to-end-testing.md) and run only cases plausibly affected by the change. Pass a scenario-title or tag `--grep` filter through the Nx target:

```sh
./hippo run --class ephemeral -- npm exec -- nx run -p bnest-app-e2e -t test:e2e -- --grep "An automatic LiveView reconnect"
./hippo run --class ephemeral -- npm exec -- nx run -p bnest-app-e2e -t test:e2e -- --project chromium --grep "Ten synthetic visitors preserve recoverable state"
```

The `test:e2e` target first enforces behaviour coverage and rebuilds browser assets from the current source, preventing stale generated CSS or JavaScript from masking a UI regression. It then cleans stale marked roots, creates paired flat-file and SQLite roots with the same run marker, leases `4010` by default from the exclusive `4010`–`4019` E2E pool, and uses [playwright.config.mts](playwright.config.mts) to start an isolated primary `bnest-app` behind Caddy at the exact `http://localhost:<port>` public origin. The flat fixture lives below repository `data/test/runs/`; SQLite lives below `~/bnest/data/test/runs/`. Set `BNEST_E2E_PORT` to select another port in the pool; occupied or concurrently leased ports fail before server startup. Every scenario creates its own `test-user-` identity and user-owned paths within the marked run; desktop, tablet, mobile, and parallel workers never assert mutable aggregate counts. The ten-client release-load scenario creates ten distinct identities and browser contexts across three declared recovery groups and runs once on desktop Chromium to bound host cost; the ordinary reconnect scenario still runs on desktop, tablet, and mobile. Reconnect scenarios start a revision-distinct candidate against the same isolated SQLite authority, reload the Caddy upstream, prove the routed revision and readiness, and await automatic LiveView reconnection without `page.reload()`. The harness never reuses a development server or production data, cleans only its validated paired roots, and records a trace on first retry.

Scheduled-backup scenarios that expose a browser route run here. Internal destination resolution, restart reconciliation, SQLite claim fencing, VACUUM proof, retention, coordinator dispatch, and expiration policy carry documented `@e2e-exempt` tags because they have no public trigger; their named `bnest-app:test:integration` scenarios exercise the real local filesystem, process, and SQLite boundaries instead.

The scheduled-backup feature also exercises admin discovery, grouped schedule presentation, backup configuration guidance, direct non-admin denial, and connected LiveView rendering across desktop, tablet, and mobile. Durable claim, migration, snapshot, receipt, and retention mechanics remain focused integration boundaries in `bnest-app`; the browser adapter proves only behaviour that crosses the routed UI and authorization boundary.

The SQLite authority scenario starts a fresh BEAM process against a paired marked runtime, creates only synthetic identity records, migrates them, removes their flat-file sources, and then proves login, session lookup, logout, and closed bootstrap state through the authoritative database. This regression journey prevents a storage cutover from leaving identity on the retired adapter.

Chat assertions deliberately avoid exact assistant prose. The fixtures emit a stable picker-visible catalog and multiple transport updates, while the browser contract checks deterministic protocol and UI outcomes: complete admin model options, Terra/medium defaulting, locked admin selectors during turns, child Luna/medium and parent Terra/medium sessions without selectors, role-scoped repository badges and controls, write-mode reset after reload and **Clear chat**, incremental completion, same-tab reload restoration, model changes applied to a resumed thread, and a fresh thread after **Clear chat**. Scenario-scoped identities include an isolated `children` plus `admin` account to prove that the child restriction wins. The fixture rejects a switched-model prompt unless Luna/medium receives the existing thread ID, rejects reload continuation without a resumed ID, and rejects a fresh-start prompt if Clear retained that ID. The Sifat Allah browser journeys also verify a confirmed browser-progress reset that persists after reload, version-2 browser-progress compatibility across a live update, browser Back returning an active exercise to its mission dashboard, an answer locking all choices before automatic five-second advancement, every answered question immediately moving between the learned and difficult repeat queues, and the exam skipping learned questions until all 120 are learned. Semantic model quality is outside deterministic browser acceptance and belongs in representative evals with outcome-based graders.

## Structure

- `specs/apps/bnest/app/architecture.md` contains the canonical as-built C4 model.
- `specs/apps/bnest/app/behaviours/` contains the canonical executable journeys.
- `playwright.config.mts` defines BDD discovery, generated output, browser, base URL, and app server.
- `tests/steps/` contains thin Playwright-BDD bindings.
- `tests/steps/release-recovery.steps.ts` owns bounded multi-client reconnect mechanics.
- `tests/support/authentication.ts` owns connected-LiveView setup/login helpers and scenario-scoped synthetic identities.
- `tests/support/centralized-data.ts` owns safe browser-source fixtures and user-scoped record evidence.
- `tests/support/scheduled-backups.ts` owns the isolated admin/non-admin settings journey and responsive UI assertions.
- `tests/support/sqlite-identity.ts` owns the fresh-process SQLite identity retirement journey.
- `tests/support/test-runtime.mts` owns paired marked runtime-root creation and exact cleanup.
- `tools/run-e2e.mts` owns the guarded runtime lifecycle around the canonical Playwright target.
- `.features-gen/` contains ignored, disposable generated Playwright tests.

Keep tests focused on behaviour that requires a real browser or crosses application boundaries. Prefer the narrower `bnest-app` `test:unit` or `test:integration` target when Playwright is unnecessary.
