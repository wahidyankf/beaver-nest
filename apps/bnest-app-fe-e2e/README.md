# bnest-app-fe-e2e

`bnest-app-fe-e2e` is the dedicated E2E adapter for [`specs/apps/bnest/app-fe/behaviours`](../../specs/apps/bnest/app-fe/behaviours/), the frontend-boundary canonical corpus root shared with [bnest-app](../bnest-app/README.md). It is one of two E2E projects that replaced the single `bnest-app-e2e`; [bnest-app-be-e2e](../bnest-app-be-e2e/README.md) owns the backend root. It carries forward the full Playwright/PWA harness, including Caddy blue/green rollout, that previously lived in `bnest-app-e2e`. See the [repository README](../../README.md) for shared setup and test commands.

## Scope

This project owns thin browser bindings, browser configuration, and assertions across the running application boundary for every route, LiveView, and installable-PWA scenario, plus the routed Caddy blue/green rollout and reconnect journey. Its web server injects deterministic Codex model-catalog and chat runners so acceptance tests cover discovery, model switching, streaming, and page lifecycle without a live model call. It also owns the family chat room's browser-boundary scenarios: the GraphQL-driven room route (canonical route, online send status, bounded per-room IndexedDB outbox with resume/backoff/seven-day expiry, auth-expiry pause and logout isolation), reconnect across a Caddy blue/green promotion, scroll-anchor/live-region accessibility, the quoted-reply journey end to end (the per-message action menu, the composer's reply strip, the quote card, the bounded jump back to a quoted message, and the real Tab order a browserless layer cannot resolve), and the push-permission UX and service-worker Cache-Storage behaviour that must never cache authenticated content. It also owns the Markdown, image, Mermaid diagram, touch-layout and keyboard-reach journeys of the Codex chat and Family Chat. The canonical [C4 architecture model](../../specs/apps/bnest/app-fe/architecture.md), features, and unit/integration adapters are shared concerns rooted in `specs/` and `bnest-app`; component, LiveView, controller, and domain-level tests remain with `bnest-app`.

## Quality Targets

Install the repository dependencies and Playwright's Chromium browser, then run the Nx target from the repository root through the workspace [HIPPO](../../repo-governance/development/resource-aware-development.md):

```sh
npm install
npm exec -- playwright install chromium
./hippo run --class ephemeral --resource-tier standard --disk-path . -- npm exec -- nx run -p bnest-app-fe-e2e -t test:quick
```

`test:quick` owns and runs these fail-fast checks in order, without depending on the application's complete quick gate:

1. `typecheck` checks every `.ts` file with TypeScript strict mode, rejects implicit and explicit `any`, and emits no files.
2. `lint` runs Oxlint's correctness, suspicious, pedantic, and performance rules and rejects explicit `any`.
3. `test:unit` runs the Node unit tests of the testing-control client, the instance path mirror, the runtime helpers, and the per-scenario test-instance lifecycle (its state machine and cleanup order). The client runs against a loopback stand-in server, and the path mirror is checked against the shared fixture `apps/bnest-app/test/fixtures/test_instance_paths.json`.
4. `test:coverage:behaviour` checks the browser adapter this project owns against the exact `app-fe` recursive corpus. It runs the compliance self-tests, generates Playwright tests, and rejects undefined, ambiguous, unused, or incorrectly shaped browser bindings and scenarios. `bnest-app` runs the matching check for its unit and integration adapters.

The managed Bnest release uses `test:release-quick` after the application quick gate. It runs this project's typecheck and lint without needlessly repeating the already-passed application quick and shared behaviour checks.

There is no numeric `test:coverage` target because this project owns only end-to-end tests. `test:coverage:behaviour` measures complete feature-to-binding coverage without collecting numeric TypeScript line coverage or launching a browser. `test:e2e` is intentionally excluded from `test:quick` because browser tests are slow by nature.

## Authoring Behaviours

Every browser journey must originate in an English `.feature` file below [`specs/apps/bnest/app-fe/behaviours/`](../../specs/apps/bnest/app-fe/behaviours/). Features are discovered recursively, so adding or nesting one requires no registration. Put routes, user actions, expected content, and examples in Gherkin. Keep Playwright mechanics in thin `tests/steps/*.ts` bindings, and do not add direct `tests/**/*.spec.ts` journey files.

Every feature must contain a scenario, and every scenario must contain an explicit `When` and `Then`. `test:coverage:behaviour` fails for malformed features, missing or ambiguous bindings, incorrect binding arity, direct journey specs, invalid exemption tags, and bindings unused by every feature. Runtime excludes only a scenario carrying a documented `@e2e-exempt`; unit has no exemption, and `@integration-exempt` affects only the integration adapter. A green static check never substitutes for the [manual one-by-one implementation review](../../repo-governance/workflows/quality/gherkin-implementation-review.md).

During development, follow the [end-to-end testing standard](../../repo-governance/development/end-to-end-testing.md) and run only cases plausibly affected by the change. Pass a scenario-title or tag `--grep` filter through the Nx target:

```sh
npm exec -- nx run -p bnest-app-fe-e2e -t test:e2e -- --grep "An automatic LiveView reconnect"
npm exec -- nx run -p bnest-app-fe-e2e -t test:e2e -- --project chromium --grep "Ten synthetic visitors preserve recoverable state"
```

The `test:e2e` target owns the single HIPPO boundary because it also owns the E2E port lease; callers invoke the Nx target directly. It first enforces behaviour coverage and rebuilds browser assets from the current source, preventing stale generated CSS or JavaScript from masking a UI regression. It then cleans stale marked roots, creates paired flat-file and SQLite roots with the same run marker, leases `4010` by default from the exclusive `4010`–`4019` E2E pool (disjoint from `bnest-app-be-e2e`'s `4030`–`4039` pool), and uses [playwright.config.mts](playwright.config.mts) to start an isolated primary `bnest-app` behind Caddy at the exact `http://localhost:<port>` public origin with `BNEST_FAMILY_CHAT_REPLY_ENABLED=true`, because the browser surface this project owns exists only when that flag is on. Compatibility scenarios pin the flag per candidate instead, so a reply-aware and a reply-free backend can be routed against one another within the same run. Desktop, tablet, mobile, and parallel workers never assert mutable aggregate counts. Reconnect scenarios start a revision-distinct candidate against the same test instance, reload the Caddy upstream, prove the routed revision and readiness, and await automatic LiveView reconnection without `page.reload()`. The harness never reuses a development server or production data, cleans only its validated paired roots, and records a trace on first retry.

## Test Instances

Each scenario gets its own test instance, as [ADR 001](../../docs/explanation/decisions/001-fresh-database-per-test.md) requires. The `Before` hook in `tests/steps/lifecycle.steps.ts` spawns it through the testing-control routes, labelled with the scenario title. A scenario not tagged `@flat-primary` starts from `sqlite_primary`. A scenario tagged `@flat-primary` starts from a flat-primary instance, which is where Bnest keeps browser-import records as flat files. A scenario that is also tagged `@open-setup` seeds no account, so its own setup can create them. A scenario tagged `@backup-repository` has its instance's `backup-repository/` made a git repository that ignores `data/`, which Backup's default destination needs. Every scenario without `@open-setup`, flat-primary or not, gets four synthetic accounts named `test-user-<role>-<first eight characters of the instance id>`, seeded through the seed route. The `After` hook routes the browser back to the primary, waits for every page to answer the requests it already sent (`tests/support/pages-idle.mts`, because the server keeps working on a request after its page is gone), closes every browser context, stops the rollout candidates, and deletes the instance. Each step runs even when an earlier one fails, and a failed delete fails the scenario. A worker-scoped fixture in `tests/support/test-fixtures.ts` deletes an instance that a failed hook left behind.

The spawn response reports `BNEST_TEST_INSTANCE_ID`, `BNEST_RUNTIME_ROOT`, and `BNEST_STORAGE_CONFIG`. Every secondary process (rollout candidates and `mix run -e` reads) takes these from the current instance, so none reads the flat run root for storage. The storage pointer and backup config live under the run's SQLite root, `storage-config/{storage,backup}.json`, which `tools/run-e2e.mts` derives with `runConfigPaths` and passes to the Playwright config as `BNEST_E2E_STORAGE_CONFIG` and `BNEST_E2E_BACKUP_CONFIG`.

Scenarios never write SQL, never copy or restore storage authority, and never write account files. Steps read the database through production routes, except the `mix run -e` reads and writes listed below.

## Structure

- `specs/apps/bnest/app-fe/architecture.md` contains the canonical as-built C4 model for the frontend surface.
- `specs/apps/bnest/app-fe/behaviours/` contains the canonical executable frontend journeys.
- `playwright.config.mts` defines BDD discovery, generated output, browser, base URL, and the dual app+Caddy server.
- `tests/steps/` contains thin Playwright-BDD bindings.
- `tests/steps/lifecycle.steps.ts` owns the per-scenario Before and After hooks for the test instance.
- `tests/steps/test_instances.steps.ts` owns the replacement-instance scenario: a fresh instance serves its own storage, and the previous admin cannot log in.
- `tests/steps/release-recovery.steps.ts` owns bounded multi-client reconnect mechanics.
- `tests/steps/codex_markdown.steps.ts` owns the Markdown reply, unfinished-reply, raw-HTML, link, and repository-image checks in `/chat`. `tests/steps/codex_diagram.steps.ts` owns the diagram-marker checks, which read the server's `pre[data-bnest-diagram]` output and treat the marker or the drawn figure as the drawn state.
- `tests/steps/codex_diagrams.steps.ts` owns the Codex diagram checks in real Chromium: the real engine draws the picture, the engine is requested lazily, the engine start can fail and be retried, nothing leaves the test origin, and hostile diagram text runs no script. `codex_diagrams_layout.steps.ts` owns its 320 px picture-layout steps, and `tests/support/codex-diagrams.ts` holds the shared selectors, request recording and timing helpers.
- `tests/steps/codex_header.steps.ts` owns the Codex header and composer checks on touch and short screens: every header control can be scrolled to both edges, the row's end padding clears its edge fade, and the header is at most 160 px tall.
- `tests/steps/codex_header_access.steps.ts` owns the repository access state and the composer checks on short screens: the access state is visible without scrolling and its write toggle is at least 44 px tall, the message box stops at its height cap and scrolls a long draft, and the visible "Message" label takes no space while the box keeps its name.
- `tests/steps/codex_touch.steps.ts` owns the Codex touch and focus checks: control heights on a touch pointer, the composer text size, the scroll cues, the coral focus ring on a link, a table, a code block and a diagram source (each reached with Tab and read through its computed outline), and the code block's height cap. `tests/steps/codex_theme_focus.steps.ts` owns the coral focus ring on the Codex theme buttons. `tests/steps/codex_composer_fit.steps.ts` owns the long unbroken draft rows: the Codex panel, the Send button and the page stay inside the screen while the box holds a 230-character address.
- `tests/steps/codex_layout.steps.ts` owns the phone-width layout checks of a Codex reply: a wide table scrolls inside the bubble, a task checkbox sits beside its text, a link is underlined, and an image stays inside the bubble. `tests/steps/codex_touch.steps.ts` owns the touch and short-screen checks, such as touch-target size, code-block height and image share of the screen. `tests/steps/codex_follow.steps.ts` owns the follow checks (the newest message is in view, a reader who scrolled up keeps their place, a drawn diagram keeps the newest reply in view), the fit of the panel and composer at each screen size, the bubble width of a wide diagram, the region names and the write-toggle contrast.
- `tests/steps/family-chat-markdown.steps.ts` owns the formatted-message checks in Family Chat, with `tests/support/family-chat-markdown.ts` for the remote images a scenario names (answered inside the browser context, so no real internet is used).
- `tests/steps/family-chat-diagrams.steps.ts` and `family-chat-diagram-layout.steps.ts` own the Family Chat diagram checks (drawn picture, fallback, readable size, 320 px fit). `tests/support/family-chat-diagrams.ts` holds the message bodies and request recording, and `family-chat-diagram-settle.ts` waits for the target message to be committed and drawn.
- `tests/steps/family-chat-content-keyboard.steps.ts` owns the keyboard reach of message content (one tab group for the stop message, Escape, the focus ring). `tests/support/family-chat-keyboard.ts` holds its locators and focus readers.
- `tests/steps/family-chat-long-draft.steps.ts` owns the long unbroken draft rows of the room: the room, the Send button and the page stay inside the screen at six viewports.
- `tests/steps/family-chat-history-scroll.steps.ts` owns the keyboard scroll rows of the history: an arrow, Home or End press brings the focused message into the visible window, a message taller than the window shows its top when focus reaches it, a message already in view does not move the history, and the message action menu opened from the keyboard sits beside its message.
- `tests/steps/family-chat-follow.steps.ts` owns the follow checks of the room (the newest message stays in view, and a diagram that draws keeps it there) and the theme control's place in the header, its size on touch, and that it does not cover the title.
- `tests/steps/family-chat-layout.steps.ts` owns the layout checks of the room (short screens, phone width, composer growth, Send button contrast). `tests/steps/family-chat-presentation.steps.ts` owns the no-authenticated-caching and presentation checks.
- `tests/steps/family-chat-resume.steps.ts` owns where a returning member lands in the family chat room.
- `tests/steps/family-chat-reply.steps.ts`, `family-chat-reply-reading.steps.ts`, and
  `family-chat-reply-keyboard.steps.ts` own choosing a reply, reading one back, and reaching both by keyboard.
- `tests/support/family-chat-reply.ts` and `tests/support/family-chat-reply-room.ts` own reply-scenario state,
  the shared locators for the menu, strip, and quote card, and rooms pinned to a chosen value of the reply flag.
- `tests/support/family-chat-resume.ts` owns stored-read-position reads/writes and settled scroll-placement assertions.
- `tests/support/family-chat-composer.ts` owns composer focus-loss recording.
- `tests/support/family-chat-seeding.ts` owns shared-room history top-up and away-member posting.
- `tests/support/test-instance-lifecycle.mts` owns the pure instance helpers (scenario labels, the `@flat-primary` phase, instance ids, the synthetic usernames and account plan, the run config paths, and the cleanup order) and the lifecycle state machine. The delete waits a bounded time while the server answers `instance_busy` (`tests/support/delete-when-idle.mts`), and the `@open-setup` and `@backup-repository` tags are read in `tests/support/scenario-tags.mts`. The lifecycle talks to the server only through an injected client, so `tests/support/test-instance-lifecycle.test.mts` and `tests/support/test-instance-lifecycle-state.test.mts` test it without a server.
- `tests/support/touch-pointer.ts` owns `emulateTouchPointer`, which sets a page to a touch pointer for the touch-size checks of both rooms.
- `tests/support/active-instance.ts` holds the worker's one current instance, the secondary-process environment taken from it, the browser-context close, and the leftover reaper.
- `tests/support/test-fixtures.ts` is the `test` object the generated specs import, and its worker-scoped fixture reaps a leftover instance.
- `tests/support/instance-identities.ts` gives steps the current instance's synthetic accounts and seeds the extra accounts a load scenario needs.
- `tests/support/instance-records.ts` reads one record of the current instance through a `mix run -e` process with that instance's environment. The read expression and its parser are in `tests/support/instance-record-read.mts`, which the BE project keeps byte-identical.
- `tests/support/authentication.ts` owns connected-LiveView setup/login helpers and synthetic identities, and digests the current instance's database files.
- `tests/support/routed-rollout.ts` owns Caddy blue/green candidate promotion, stopping rollout candidates, and restoring the primary route.
- `tests/support/sifat-allah-progress.ts` owns saving a synthetic learner's Sifat Allah progress on the server.
- `tests/support/codex-chat-transcript.ts` owns saving a synthetic user's chat on the Codex thread whose fixture runner
  has exited, through the seed route.
- `tests/support/testing-control.mts` is the typed Node `fetch` client for the test-only `/__bnest_testing/v1` routes. It reads the per-run secret from the environment on each call and never logs it. `testing-control-records.mts` holds the record guards, `testing-control-error.mts` the typed errors, and `testing-control-stand-in.mts` the loopback server its unit tests use. The client talks to the backend loopback port, never through Caddy.
- `tests/support/test-instance-paths.mts` mirrors `BnestApp.TestInstance.Paths.derive/4`. Its parity test reads `apps/bnest-app/test/fixtures/test_instance_paths.json`.
- `tests/support/test-runtime.mts` owns the paired marked runtime roots, the leak audit that lists instances left under them, and the global teardown. The teardown deletes the current instance while the server is still up, then checks that the run base holds no account or SQLite file. It does not remove the roots.
- `tools/run-e2e.mts` owns the guarded runtime lifecycle around the canonical Playwright target. It generates a 32-byte secret per run and passes it only through the environment of the Playwright process, which the primary server inherits through its webServer. It also passes the run's storage and backup config paths to Playwright.
- Least privilege for the secret: only the Playwright process (the steps and the control client) and the primary `mix phx.server` carry `BNEST_TEST_CONTROL_SECRET`. Browsers and the Caddy process (`browserEnvironment` in `playwright.config.mts`) start without it. Rollout candidates and every `mix run -e` read start from `routedEnvironment()`, which uses `secondaryEnvironment` in `tests/support/secondary-environment.mts`, so none of them can call the control routes. After Playwright and its servers exit, it fails the run on any instance left under either root, then removes the validated pair.
- `.features-gen/` contains ignored, disposable generated Playwright tests.

### Remaining `mix run -e` Reads and Writes

Steps still reach the application through `mix run -e` only where no testing-control route or production route exists yet. Each one runs with the current instance's environment:

- `tests/support/instance-records.ts` reads the child's chat record after a Codex resume (no route reads a chat record).
- `tests/support/scheduled-backups.ts` creates a test schedule and reads a backup schedule back (no route exists for either).
- `tests/support/backup-integrity-label.ts` reads the integrity JSON that the backup label scenarios compare.
- `tests/support/sifat-allah-progress.ts` writes the learner's "every pair remembered" progress, derived from the curriculum.
- `tests/support/family-chat-session.ts` reads the push-enabled flag and posts a system message (no route exists for either).

## Hazards

- **Stale compressed bundles.** The endpoint serves a `.gz` file next to a bundle when the server does not reload code (`gzip: not code_reloading?` in `endpoint.ex`). The folder `apps/bnest-app/priv/static/assets` is ignored by git, so an old `*.gz` file there can make `Plug.Static` serve an old bundle after you rebuild. Delete stale `*.gz` files before an affected run. Do not run `phx.digest` into `priv/static`.
- **Full `/tmp` quota.** On a host where the per-user quota of `/tmp` is full, Chromium crashes. Set `TMPDIR` to a folder on `/dev/shm` for the run.

Keep tests focused on behaviour that requires a real browser or crosses application boundaries. Prefer the narrower `bnest-app` `test:unit` or `test:integration` target when Playwright is unnecessary.
