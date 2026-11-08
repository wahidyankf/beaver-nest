# bnest-app-be-e2e

`bnest-app-be-e2e` is the dedicated E2E adapter for [`specs/apps/bnest/app-be/behaviours`](../../specs/apps/bnest/app-be/behaviours/), the backend-boundary canonical corpus root shared with [bnest-app](../bnest-app/README.md). It is one of two E2E projects that replaced the single `bnest-app-e2e`; [bnest-app-fe-e2e](../bnest-app-fe-e2e/README.md) owns the frontend root. See the [repository README](../../README.md) for shared setup and test commands.

## Scope

This project owns backend-boundary scenarios that happen to be exercised through a real running server and browser today: server-authoritative password policy and hashing, session persistence and isolation, multi-role authorization, cross-user data isolation, browser-triggered data import server persistence, the headless `mix bnest.storage.migrate`/`relocate`/`retire` SQLite storage lifecycle, and the authenticated family chat GraphQL surface (schema/resolvers, subscription delivery, push retry/retention, Scheduler handler routing, and backup capacity/concurrency/restore). It runs the single shared `bnest-app` process directly, with no Caddy in front of it: rollout, blue/green promotion, and reconnect proofs are `bnest-app-fe-e2e`'s exclusive responsibility. GraphQL and the family chat backend protocol are fully implemented and tested here, gated behind the `BNEST_FAMILY_CHAT_ENABLED` flag, which still defaults to off. Quoted replies are the exception that proves the boundary: `BNEST_FAMILY_CHAT_REPLY_ENABLED` gates only the browser surface, so this project runs its reply coverage with the flag left at its default of off. That is the required value, not an oversight — a reply-aware bundle may reach a member during a rolling release before every backend has the flag on, so `replyToMessageId` and `replyTo` must be accepted and answered here regardless of it.

## Quality Targets

Install the repository dependencies and Playwright's Chromium browser, then run the Nx target from the repository root through the workspace [HIPPO](../../repo-governance/development/resource-aware-development.md):

```sh
npm install
npm exec -- playwright install chromium
./hippo run --class ephemeral --resource-tier standard --disk-path . -- npm exec -- nx run -p bnest-app-be-e2e -t test:quick
```

`test:quick` owns and runs these fail-fast checks in order, without depending on the application's complete quick gate:

1. `typecheck` checks every `.ts` file with TypeScript strict mode, rejects implicit and explicit `any`, and emits no files.
2. `lint` runs Oxlint's correctness, suspicious, pedantic, and performance rules and rejects explicit `any`.
3. `test:unit` runs the Node unit tests of the testing-control client, the instance path mirror and the runtime helpers. The client runs against a loopback stand-in server, and the path mirror is checked against the shared fixture `apps/bnest-app/test/fixtures/test_instance_paths.json`.
4. `test:coverage:behaviour` checks the browser adapter this project owns against the exact `app-be` recursive corpus. It runs the compliance self-tests, generates Playwright tests, and rejects undefined, ambiguous, unused, or incorrectly shaped browser bindings and scenarios.

The managed Bnest release uses `test:release-quick` after the application quick gate. It runs this project's typecheck and lint without needlessly repeating the already-passed application quick and shared behaviour checks.

There is no numeric `test:coverage` target because this project owns only end-to-end tests. `test:coverage:behaviour` measures complete feature-to-binding coverage without collecting numeric TypeScript line coverage or launching a browser. `test:e2e` is intentionally excluded from `test:quick` because browser tests are slow by nature.

## Authoring Behaviours

Every browser journey must originate in an English `.feature` file below [`specs/apps/bnest/app-be/behaviours/`](../../specs/apps/bnest/app-be/behaviours/). Features are discovered recursively. Put routes, user actions, expected content, and examples in Gherkin. Keep Playwright mechanics in thin `tests/steps/*.ts` bindings, and do not add direct `tests/**/*.spec.ts` journey files.

`test:coverage:behaviour` fails for malformed features, missing or ambiguous bindings, incorrect binding arity, direct journey specs, invalid exemption tags, and bindings unused by every feature this project owns. Runtime excludes only a scenario carrying a documented `@e2e-exempt`; most `scheduled_backups` scenarios carry one, since restart reconciliation, SQLite claim fencing, VACUUM proof, coordinator dispatch, and expiration policy have no public trigger, and retention needs a controlled clock — their named `bnest-app:test:integration` scenarios exercise the real local filesystem, process, and SQLite boundaries instead. A green static check never substitutes for the [manual one-by-one implementation review](../../repo-governance/workflows/quality/gherkin-implementation-review.md).

The `test:e2e` target owns the single HIPPO boundary because it also owns the E2E port lease; callers invoke the Nx target directly. It uses [playwright.config.mts](playwright.config.mts) to start an isolated `bnest-app` directly on `http://127.0.0.1:<port>` (no reverse proxy). It leases `4030` by default from the exclusive `4030`–`4039` pool, disjoint from `bnest-app-fe-e2e`'s `4010`–`4019` pool so both can run concurrently. Every scenario spawns its own test instance through the testing control API and seeds its `test-user-` accounts through that same API (ADR 001). A scenario never shares a database, never restores a snapshot, and never writes account files or runs `DELETE FROM`. The harness never reuses a development server or production data.

## Structure

- `specs/apps/bnest/app-be/architecture.md` contains the canonical as-built C4 model for the backend surface.
- `specs/apps/bnest/app-be/behaviours/` contains the canonical executable backend journeys.
- `playwright.config.mts` defines BDD discovery, generated output, browser, base URL, and the single app server (no Caddy).
- `tests/steps/` contains thin Playwright-BDD bindings, including the headless `mix bnest.storage.migrate` and `mix bnest.storage.retire` CLI flows.
- `tests/steps/lifecycle.steps.ts` owns the per-scenario Before and After hooks. Before spawns the scenario's test instance (`sqlite_primary`, or `flat_primary` for `@flat-primary` scenarios, with no seeded account for `@open-setup`, and with no storage pointer or database for `@storage-unconfigured`, the state before an administrator chooses the database location). After closes the browser contexts and then deletes the instance. `tests/support/test-fixtures.ts` adds a worker fixture that deletes any instance a missing After left behind.
- `tests/support/test-instance-lifecycle.mts` holds the pure helpers (labels, phases, instance ids, `test-user-` usernames, account plans) and the state machine that keeps one current instance. `tests/support/active-instance.mts` holds the process-wide lifecycle and the shared control client.
- `tests/support/instance-identities.ts` names the current instance's accounts. `tests/support/instance-records.ts` and `tests/support/live-sqlite.ts` run the secondary `mix run -e` reads with that instance's environment. `tests/support/instance-record-read.mts` holds the read expression and its parser; the FE project keeps a byte-identical copy, enforced by `shared-support-parity.test.mts`.
- `tests/support/test-isolation-probes.ts` probes the testing routes (missing, wrong, and forwarded headers) and `/health/ready` with Node `fetch`.
- `tests/support/live-sqlite.ts` gives secondary `mix run -e` processes the current instance's environment, and the backup configuration path under the SQLite run root. It starts from `secondaryEnvironment` in `tests/support/secondary-environment.mts`, so the inherited test-control secret is removed.
- `tests/support/secondary-environment.mts` holds the secret filter for every process that step code starts (`mix run -e` reads, storage CLI runs, rollout candidates). It repeats `browserEnvironment`'s filter on purpose: the Playwright config imports `browser-environment.mts`, and a module the config imports cannot be loaded by step code through CommonJS. `secondary-environment.test.mts` keeps the two filters equal.
- `tests/support/browser-environment.mts` gives browsers the environment without `BNEST_TEST_CONTROL_SECRET`. Only the Playwright process and the primary `mix phx.server` keep the secret, because the control client and the probes call the routes from Playwright's process.
- `tests/support/sqlite-storage.ts` and `tests/support/sqlite-identity.ts` own isolated, self-contained storage-migration fixtures.
- `tests/support/testing-control.mts` is the typed Node `fetch` client for the test-only `/__bnest_testing/v1` routes. It reads the per-run secret from the environment on each call and never logs it. `testing-control-records.mts` holds the record guards, `testing-control-error.mts` the typed errors, and `testing-control-stand-in.mts` the loopback server its unit tests use.
- `tests/support/test-instance-paths.mts` mirrors `BnestApp.TestInstance.Paths.derive/4`. Its parity test reads `apps/bnest-app/test/fixtures/test_instance_paths.json`.
- `tests/support/test-runtime.mts` owns the paired marked run roots, the leak audit that lists instances left under them, and the global teardown. The teardown deletes the current instance while the server is still up, then checks that the run base holds no account or SQLite file. It does not remove the roots. `flatAccountFiles` lists the account, username, and user files of a flat-primary instance root, which the empty-database scenario checks next to its row counts.
- `tools/run-e2e.mts` owns the guarded runtime lifecycle around the canonical Playwright target. It generates a 32-byte secret per run and passes it only through the environment. After Playwright and its servers exit, it fails the run on any instance left under either root, then removes the validated pair.
- `.features-gen/` contains ignored, disposable generated Playwright tests.

Keep tests focused on behaviour that requires a real browser or process boundary. Prefer the narrower `bnest-app` `test:unit` or `test:integration` target when Playwright is unnecessary.
