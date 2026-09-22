# bnest-app-fe-e2e

`bnest-app-fe-e2e` is the dedicated E2E adapter for [`specs/apps/bnest/app-fe/behaviours`](../../specs/apps/bnest/app-fe/behaviours/), the frontend-boundary canonical corpus root shared with [bnest-app](../bnest-app/README.md). It is one of two E2E projects that replaced the single `bnest-app-e2e`; [bnest-app-be-e2e](../bnest-app-be-e2e/README.md) owns the backend root. It carries forward the full Playwright/PWA harness, including Caddy blue/green rollout, that previously lived in `bnest-app-e2e`. See the [repository README](../../README.md) for shared setup and test commands.

## Scope

This project owns thin browser bindings, browser configuration, and assertions across the running application boundary for every route, LiveView, and installable-PWA scenario, plus the routed Caddy blue/green rollout and reconnect journey. Its web server injects deterministic Codex model-catalog and chat runners so acceptance tests cover discovery, model switching, streaming, and page lifecycle without a live model call. It also owns the family chat room's browser-boundary scenarios: the GraphQL-driven room route (canonical route, online send status, bounded per-room IndexedDB outbox with resume/backoff/seven-day expiry, auth-expiry pause and logout isolation), reconnect across a Caddy blue/green promotion, scroll-anchor/live-region accessibility, the quoted-reply journey end to end (the per-message action menu, the composer's reply strip, the quote card, the bounded jump back to a quoted message, and the real Tab order a browserless layer cannot resolve), and the push-permission UX and service-worker Cache-Storage behaviour that must never cache authenticated content. The canonical [C4 architecture model](../../specs/apps/bnest/app-fe/architecture.md), features, and unit/integration adapters are shared concerns rooted in `specs/` and `bnest-app`; component, LiveView, controller, and domain-level tests remain with `bnest-app`.

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
3. `test:coverage:behaviour` checks the browser adapter this project owns against the exact `app-fe` recursive corpus. It runs the compliance self-tests, generates Playwright tests, and rejects undefined, ambiguous, unused, or incorrectly shaped browser bindings and scenarios. `bnest-app` runs the matching check for its unit and integration adapters.

The managed Bnest release uses `test:release-quick` after the application quick gate. It runs this project's typecheck and lint without needlessly repeating the already-passed application quick and shared behaviour checks.

There is no `test:unit` or numeric `test:coverage` target because this project owns only end-to-end tests. `test:coverage:behaviour` measures complete feature-to-binding coverage without collecting numeric TypeScript line coverage or launching a browser. `test:e2e` is intentionally excluded from `test:quick` because browser tests are slow by nature.

## Authoring Behaviours

Every browser journey must originate in an English `.feature` file below [`specs/apps/bnest/app-fe/behaviours/`](../../specs/apps/bnest/app-fe/behaviours/). Features are discovered recursively, so adding or nesting one requires no registration. Put routes, user actions, expected content, and examples in Gherkin. Keep Playwright mechanics in thin `tests/steps/*.ts` bindings, and do not add direct `tests/**/*.spec.ts` journey files.

Every feature must contain a scenario, and every scenario must contain an explicit `When` and `Then`. `test:coverage:behaviour` fails for malformed features, missing or ambiguous bindings, incorrect binding arity, direct journey specs, invalid exemption tags, and bindings unused by every feature. Runtime excludes only a scenario carrying a documented `@e2e-exempt`; unit has no exemption, and `@integration-exempt` affects only the integration adapter. A green static check never substitutes for the [manual one-by-one implementation review](../../repo-governance/workflows/gherkin-implementation-review.md).

During development, follow the [end-to-end testing standard](../../repo-governance/development/end-to-end-testing.md) and run only cases plausibly affected by the change. Pass a scenario-title or tag `--grep` filter through the Nx target:

```sh
npm exec -- nx run -p bnest-app-fe-e2e -t test:e2e -- --grep "An automatic LiveView reconnect"
npm exec -- nx run -p bnest-app-fe-e2e -t test:e2e -- --project chromium --grep "Ten synthetic visitors preserve recoverable state"
```

The `test:e2e` target owns the single HIPPO boundary because it also owns the E2E port lease; callers invoke the Nx target directly. It first enforces behaviour coverage and rebuilds browser assets from the current source, preventing stale generated CSS or JavaScript from masking a UI regression. It then cleans stale marked roots, creates paired flat-file and SQLite roots with the same run marker, leases `4010` by default from the exclusive `4010`–`4019` E2E pool (disjoint from `bnest-app-be-e2e`'s `4030`–`4039` pool), and uses [playwright.config.mts](playwright.config.mts) to start an isolated primary `bnest-app` behind Caddy at the exact `http://localhost:<port>` public origin with `BNEST_FAMILY_CHAT_REPLY_ENABLED=true`, because the browser surface this project owns exists only when that flag is on. Compatibility scenarios pin the flag per candidate instead, so a reply-aware and a reply-free backend can be routed against one another within the same run. Every scenario creates its own `test-user-` identity and user-owned paths within the marked run; desktop, tablet, mobile, and parallel workers never assert mutable aggregate counts. Reconnect scenarios start a revision-distinct candidate against the same isolated SQLite authority, reload the Caddy upstream, prove the routed revision and readiness, and await automatic LiveView reconnection without `page.reload()`. The harness never reuses a development server or production data, cleans only its validated paired roots, and records a trace on first retry.

## Structure

- `specs/apps/bnest/app-fe/architecture.md` contains the canonical as-built C4 model for the frontend surface.
- `specs/apps/bnest/app-fe/behaviours/` contains the canonical executable frontend journeys.
- `playwright.config.mts` defines BDD discovery, generated output, browser, base URL, and the dual app+Caddy server.
- `tests/steps/` contains thin Playwright-BDD bindings.
- `tests/steps/release-recovery.steps.ts` owns bounded multi-client reconnect mechanics.
- `tests/steps/family-chat-resume.steps.ts` owns where a returning member lands in the family chat room.
- `tests/steps/family-chat-reply.steps.ts`, `family-chat-reply-reading.steps.ts`, and
  `family-chat-reply-keyboard.steps.ts` own choosing a reply, reading one back, and reaching both by keyboard.
- `tests/support/family-chat-reply.ts` and `tests/support/family-chat-reply-room.ts` own reply-scenario state,
  the shared locators for the menu, strip, and quote card, and rooms pinned to a chosen value of the reply flag.
- `tests/support/family-chat-resume.ts` owns stored-read-position reads/writes and settled scroll-placement assertions.
- `tests/support/family-chat-composer.ts` owns composer focus-loss recording.
- `tests/support/family-chat-seeding.ts` owns shared-room history top-up and away-member posting.
- `tests/support/authentication.ts` owns connected-LiveView setup/login helpers and scenario-scoped synthetic identities.
- `tests/support/routed-rollout.ts` owns Caddy blue/green candidate promotion and live-SQLite activation.
- `tests/support/test-runtime.mts` owns paired marked runtime-root creation and exact cleanup.
- `tools/run-e2e.mts` owns the guarded runtime lifecycle around the canonical Playwright target.
- `.features-gen/` contains ignored, disposable generated Playwright tests.

Keep tests focused on behaviour that requires a real browser or crosses application boundaries. Prefer the narrower `bnest-app` `test:unit` or `test:integration` target when Playwright is unnecessary.
