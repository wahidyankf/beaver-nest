# bnest-app

`bnest-app` is the Phoenix LiveView application that serves Beaver Nest's local Codex chat. See the [repository README](../../README.md) for the product purpose, shared setup, privacy boundaries, and repository layout.

## Scope

This project owns the OTP application, Phoenix endpoint and router, LiveViews, Codex process bridge, server-rendered UI, browser assets, Progressive Web App (PWA) manifest and service worker, and the unit and local-only integration adapters for Bnest's canonical Gherkin behavior. It includes the child-friendly `/apps/sifat-allah` revision activity, the SQLite-backed daily scheduler, and independently verified production SQLite backups. Browser-level acceptance belongs to [bnest-app-e2e](../bnest-app-e2e/README.md); the reusable Elixir BDD engine belongs to [ex-bdd](../../libs/ex-bdd/README.md).

The generic scheduler persists contextual definitions and run claims in authoritative SQLite, dispatches only code-allowlisted handlers through one supervised task pool, renews leases, and fences file publication by attempt. The production backup handler reads the active SQLite source, resolves the ignored `data/backup/` default from the permanent runtime checkout rather than the temporary release-build worktree, and accepts a safe absolute override through private `~/.config/bnest/backup.json`. Only admins can open `/admin/settings` or `/admin/settings/schedules`; configuration panels remain code-owned and each domain validates and saves only its allowlisted fields.

## Setup and Development

The project requires Elixir `~> 1.18` with Erlang/OTP and Mix, Node.js 18 or newer, and Codex authentication available to the local account. From this directory, install its dependencies and assets once:

```sh
mix setup
```

Run project tasks from the repository root:

| Task                                 | Command                                                                                        |
| ------------------------------------ | ---------------------------------------------------------------------------------------------- |
| Start the stable development server  | `npm exec -- nx run -p bnest-app -t serve`                                                     |
| Install the stable local Caddy proxy | `npm exec -- nx run -p bnest-app -t proxy:install`                                             |
| Inspect deployment routing           | `npm exec -- nx run -p bnest-app -t proxy:status`                                              |
| Build an immutable candidate release | `npm exec -- nx run -p bnest-app -t release:build`                                             |
| Test the release transaction         | `npm exec -- nx run -p bnest-app -t release:test`                                              |
| Run one deterministic release        | `npm exec -- nx run -p bnest-app -t release:run -- --revision <sha>`                           |
| Start an inactive release slot       | `npm exec -- nx run -p bnest-app -t deploy:prepare -- --slot green --revision <sha>`           |
| Gracefully promote a release slot    | `npm exec -- nx run -p bnest-app -t deploy:promote -- --slot green`                            |
| Route back to the previous slot      | `npm exec -- nx run -p bnest-app -t deploy:rollback`                                           |
| Stop a drained inactive slot         | `npm exec -- nx run -p bnest-app -t deploy:retire -- --slot blue`                              |
| Enable persistent tailnet HTTPS      | `npm exec -- nx run -p bnest-app -t tailnet:up`                                                |
| Inspect the tailnet proxy            | `npm exec -- nx run -p bnest-app -t tailnet:status`                                            |
| Disable the tailnet proxy            | `npm exec -- nx run -p bnest-app -t tailnet:down`                                              |
| Run the complete quick suite         | `npm exec -- nx run -p bnest-app -t test:quick`                                                |
| Run unit scenarios                   | `npm exec -- nx run -p bnest-app -t test:unit`                                                 |
| Run local-only integration scenarios | `npm exec -- nx run -p bnest-app -t test:integration`                                          |
| Cover the unit slice                 | `npm exec -- nx run -p bnest-app -t test:coverage:unit`                                        |
| Cover the integration slice          | `npm exec -- nx run -p bnest-app -t test:coverage:integration`                                 |
| Verify every behavior adapter        | `npm exec -- nx run -p bnest-app -t test:coverage:behaviour`                                   |
| Run all application coverage slices  | `npm exec -- nx run -p bnest-app -t test:coverage`                                             |
| Run static type analysis             | `npm exec -- nx run -p bnest-app -t typecheck`                                                 |
| Run all linters                      | `npm exec -- nx run -p bnest-app -t lint`                                                      |
| Check Elixir and HEEx formatting     | `npm exec -- nx run -p bnest-app -t format`                                                    |
| Audit runtime schemas without values | `npm exec -- nx run -p bnest-app -t schema:audit`                                              |
| Benchmark the password verifier      | `npm exec -- nx run -p bnest-app -t identity:benchmark`                                        |
| Relocate authoritative SQLite data   | `npm exec -- nx run -p bnest-app -t storage:relocate`                                          |
| Retire verified legacy storage       | `npm exec -- nx run -p bnest-app -t storage:retire -- --root <root> --generation <generation>` |
| Purge legacy production test records | `npm exec -- nx run -p bnest-app -t storage:purge-test-data -- --generation <generation>`      |
| Clean stale isolated test data       | `npm exec -- nx run -p bnest-app -t test-data:cleanup`                                         |

Run compute-bearing rows through `apps/resource-guard/resource-guard run --class ephemeral -- <command>` and the repository [resource guard](../../repo-governance/development/resource-aware-development.md); `serve`, managed release, and pre-push enter it automatically. Use the `transactional` class for storage mutations so admitted work is never killed mid-transaction. Recovery, proxy status, rollback, retire, and tailnet controls remain direct.

`test:quick` runs type checking, linting, unit execution, unit coverage, and static behavior completeness. It intentionally excludes integration runtime and E2E execution. Both numeric coverage slices use Mix line coverage and fail below 99%.

The deployment targets require machine-local `BNEST_DEPLOY_ROOT`, `BNEST_RUNTIME_ROOT`, `BNEST_DEPLOY_COOKIE_FILE`, `BNEST_DEPLOY_SECRET_KEY_BASE_FILE`, and a bare-HTTPS `BNEST_PRODUCTION_ORIGIN` outside this repository; release builds also require `BNEST_DEPLOY_WORKTREE`. Candidate preparation derives `PHX_HOST` from that validated origin and injects the permanent checkout as `BNEST_REPOSITORY_ROOT`, so routed WebSocket checks stay strict and runtime backups never inherit the disposable build path. The managed release target accepts only a clean `origin/main` revision, owns release and shared resource locks, checks capacity and exact port ownership, runs a fixed uncached gate manifest, builds once in a detached worktree, records a digest and checksum-bound migration manifest, proves the inactive slot and routed revision, qualifies ten distinct synthetic identities in three groups at an isolated exact origin, exercises 10 anonymous routed LiveViews without reload, drains for five minutes, and retains only the active and previous artifacts. Its schema-v4 evidence records an available non-compressed estimate, exported macOS pressure, compressor availability and payload, interval CPU utilization, service RSS, disk, swap-in/out and free space, local Caddy latency, and exact routed-user-surface latency without recording origins, paths, arguments, or user data. Admission requires normal pressure, at least 9 GiB estimated availability, compressor availability, six CPU units of release/safety headroom, and 13 GiB disk. Final proof preserves a 2 GiB floor, two p95 CPU units, zero local or routed health failures, routed p95 at or below 500 ms, and every routed sample at or below 2 seconds; swap activity is additional pressure below 4 GiB. Compressor payload is never interpreted as fullness. A non-empty migration set fails closed until an approved expand–migrate–verify adapter exists.

The launcher preserves its executable search path, gives each Phoenix slot enough file descriptors for long-lived connections, and points Codex model discovery at the permanent main checkout, so the temporary build worktree can be deleted immediately after the immutable release is built. Release slots remain independent; Caddy preserves the healthy slot during candidate readiness and cutover without requiring an Erlang peer connection. Caddy binds only to loopback, accepts the Host header forwarded by Tailscale Serve, and forwards the HTTPS scheme to Phoenix so its secure cookies and redirects remain correct. Their safe creation, promotion, and rollback sequence is defined by the [Caddy deployment workflow](../../repo-governance/workflows/development-caddy-deployment.md).

The serve target defaults to stable development compile mode because the family uses Bnest continuously. The read-only schema audit and password-verifier benchmark use the same mode, so they remain safe while the backend serves. Do not replace it with a command that recompiles the active backend for code reloading; a deliberately isolated, non-routed experiment must opt in to `BNEST_STABLE=false`.

## Shared behavior and boundaries

The canonical [C4 architecture model](../../specs/apps/bnest/app/architecture.md) defines Bnest's current system, container, component, data, and process boundaries. Every Bnest behavior starts in [`specs/apps/bnest/app/behaviours/`](../../specs/apps/bnest/app/behaviours/). The same recursively discovered feature, expanded scenarios, and shared step bindings run at both application levels:

- The unit adapter calls the subject directly without starting the OTP application. Filesystem, database, process, network, and other system resources must be replaced by test doubles.
- The integration adapter uses real in-process Phoenix components and isolated local resources. The endpoint server remains disabled, and network access—including loopback and local servers—is forbidden.
- The browser adapter lives in `bnest-app-e2e` and exercises the public HTTP boundary.

`test:coverage:behaviour` statically checks the unit, integration, and E2E adapters against the exact corpus. It rejects empty features, scenarios without explicit `When` and `Then`, undefined or ambiguous steps, unused bindings, incomplete drivers, and unit or integration boundary-policy violations.

The unit slice measures resource-free domain code: chat, learning, Codex model access/session/settings, browser-source normalization, authorization, PWA metadata, and JSON rendering. The integration slice measures the repository and identity application facades plus model catalog, endpoint, and telemetry wiring. Generated/static Phoenix code, test scaffolding, CLI tasks, HTTP/LiveView adapters, filesystem stores, Argon2, bootstrap/import transactions, and session-record adapters are excluded from numeric line coverage because their behavior is exercised by integration, behavior, E2E, schema-audit, identity-benchmark, and manual-browser gates. Both numeric slices remain at least 99%; layer exclusions leave the owning slice and all functional tests intact.

Type checking treats Elixir compiler warnings as errors, runs Dialyzer through Dialyxir, and strictly checks browser JavaScript without emitting files. Linting checks formatting, runs Credo in strict mode, runs Oxlint on browser JavaScript, and rejects unused locked dependencies without changing the lockfile.

The development server defaults to [http://localhost:4020](http://localhost:4020) and may lease `4020`–`4029` through `BNEST_DEV_PORT`; production alone owns `4000`/`4001`, E2E owns `4010`–`4019`, and Caddy owns `4100`. Normal Elixir, HEEx, JavaScript, and CSS changes reload only in an isolated non-stable experiment. Dependency, runtime configuration, and supervision-tree changes require the repository's [development-server restart workflow](../../repo-governance/workflows/development-server-restart.md). The always-available route is Tailscale Serve → loopback Caddy → one immutable Phoenix slot; Caddy changes upstream with a graceful reload while the previous LiveView connections drain and reconnect automatically. The chat composer uses LiveView auto-recovery so an unsent draft and route survive a compatible transport reconnect without `page.reload()`. Follow the [Caddy deployment workflow](../../repo-governance/workflows/development-caddy-deployment.md) and [Tailnet proxy workflow](../../repo-governance/workflows/development-tailnet-proxy.md).

The home page at `/` is the child-friendly entry point and links to `/chat`, `/apps/sifat-allah`, and the authenticated `/data-migration` compatibility flow. One-time `/setup` creates every initial account and permanently closes; `/login` then protects family data. There is no public registration or password-recovery flow.

## Identity and Runtime Data

Production SQLite data defaults to `~/bnest/data/prod/`; repository `data/prod/` is only a verified legacy migration source until retirement. Each test uses the same marked run identifier in a flat-file fixture root below `data/test/runs/` and a SQLite root below `~/bnest/data/test/runs/`; either root being absent, shared, or mismatched fails closed. Initial accounts have a normalized username, one or more `children`, `parents`, and `admin` roles, and an Argon2id password verifier. Passwords have no application character-count rule, but each must contain a letter, number, and punctuation mark such as `_`. The browser receives only a persistent opaque session cookie; the server stores its SHA-256 digest, has no automatic session expiration, and lets one user remain logged in independently in multiple browsers. Logout revokes only that browser session. Cross-user data access is denied regardless of role.

The routed HTTPS service must start with `BNEST_COOKIE_SECURE=true`; `BNEST_IDENTITY_CUTOVER=true` enables setup/login only when the replacement backend and import path are ready. Both variables accept only `true` or `false`. Local HTTP development keeps the secure-cookie override unset, while production Mix configuration enables it automatically.

Chat, Sifat Allah progress, and explicit theme preference are versioned user-owned JSON records. The typed repository derives paths from the authenticated user, validates schemas, locks per path, writes a temporary file, atomically replaces, and reads the result back. Mutable records require the last revision. Browser import reads only `bnest.chat.v1`, `bnest.sifat-allah.v1`, and `phx:theme`; it keeps an immutable envelope and manifest, normalizes and reads the destination through the normal repository, then removes only the accepted browser key. Unknown, malformed, oversized, interrupted, or stale sources remain in the browser and cannot replace accepted data. Immutable envelopes, legacy copies, manifests, and old readers are retained for recovery.

## SQLite Storage

Bnest's user-owned state moves from the flat-file runtime root into a private local SQLite database. The stable pointer at `~/.config/bnest/storage.json` (or `BNEST_STORAGE_CONFIG` for machine-local overrides) remains configuration and resolves the database directory, generation, and `flat_primary`/`sqlite_primary` phase. Production data defaults to `~/bnest/data/prod/bnest.sqlite3`; tests use `~/bnest/data/test/runs/<run-id>/bnest.sqlite3`. An authenticated `admin`-role user may optionally select a different private, writable, non-symlinked, non-world-writable folder outside the repository and migration sources before migration starts.

The versioned DDL migration at `priv/sqlite_repo/migrations/` never scans flat files; data copying is owned by the reproducible `flat-files-v1-to-sqlite-v1` backfill adapter (`lib/bnest_app/storage/migration.ex`), which the headless `mix bnest.storage.migrate` task (Nx target `storage:migrate`) and the optional `/storage` admin LiveView both call through the same domain module. Every recognized source is inventoried in deterministic path order, copied with immutable source/target checksum evidence, and read back through the normal repository before SQLite becomes authoritative; a changed or malformed source blocks the phase switch without mutating the flat-primary service, and retrying the same migration identifier never rewrites or duplicates accepted items. Activation requires schema, backfill, parity, integrity (`PRAGMA quick_check`), and an isolated `VACUUM INTO` restore rehearsal to all pass first. Repo queries never log record payloads (`log: false` on `BnestApp.SqliteRepo`), keeping migration output as value-free as the flat-file adapter it replaces.

`storage:relocate` serializes repository access across processes, checkpoints the source, copies it through `VACUUM INTO`, compares value-free logical evidence, atomically updates the pointer with a new generation, and keeps the old database available for rollback. After the managed release and routed health response prove that exact generation, `storage:retire` rechecks database integrity and migration checksums before deleting only the verified repository flat-file sources and the legacy SQLite database and sidecars. `test-data:cleanup` removes only marked, inactive paired test roots older than 24 hours; each test suite also cleans its own pair in its finalizer.

## Visual Language

Every Bnest interface uses the **Nest workshop** visual language defined by the `--bnest-*` tokens in [`assets/css/app.css`](assets/css/app.css). Reuse those tokens rather than adding page-local colors, fonts, corner treatments, or shadows.

- **Color:** ink `#153f42`, canvas `#d8f1ec`, paper `#fff9ed`, sunflower `#f7b84b`, coral `#e5633d`, and lagoon `#80c5b8`.
- **Type:** use the rounded display stack for page titles and prominent actions; use the body stack for reading and controls.
- **Shape:** cards and primary actions use an asymmetric rounded corner with a solid ink outline and offset ink shadow. Focus states use coral; hover motion is small and respects the control's purpose.

The home-page chat card is the reference primary action. New routes should feel like the same playful workshop while keeping one obvious next action and accessible keyboard focus.

## Installable web app

The root layout links a standalone PWA manifest and Beaver Nest icon sizes for Android, desktop Chromium browsers, and Apple home-screen use. Browser JavaScript registers the service worker, which keeps a cached application shell as an offline fallback while preferring the live app whenever the home host is reachable. To install on a device, use Beaver Nest's Tailscale HTTPS address: choose **Install app** in a Chromium browser or **Share → Add to Home Screen** in Safari. The installed PWA is a private web client, not a native application; Codex conversations still require the home host to be online.

## Chat runtime

At application startup, a supervised catalog asks the local [Codex app server](https://learn.chatgpt.com/docs/app-server) for every picker-visible model and caches the validated result. If local discovery fails or returns no valid choices, the app keeps chat available with a safe Terra-only fallback. `gpt-5.6-terra` with medium reasoning effort is the application default even when Codex declares another model as its own default. The role access policy is enforced server-side on mount, restoration, and selection events: admins retain the full discovered catalog, parents are fixed to Terra/medium, and children are fixed to Luna/medium. Parent and child model/effort controls are not rendered. If a required fixed model is unavailable, that role's chat is disabled rather than silently falling back to another model. The reasoning-effort selector is populated from the selected model's discovered capabilities. Changing models preserves the current effort when the new model supports it, otherwise it falls back to medium when available and then to that model's declared default.

The Beaver Nest brand in the chat header is a home link, so the logo and wordmark return the visitor to the authenticated home page.

The theme picker belongs to the current page's controls rather than floating over chat content. In chat it shares the wrapped control row with the model status and **Clear chat**, so narrow screens retain every control without covering the brand.

Each connected LiveView owns one Node bridge. The bridge starts a Codex SDK thread for a fresh chat or resumes the stored thread ID. Admin model and reasoning-effort selectors are disabled during an active turn; parent and child sessions have no selector to manipulate. Selecting either setting between turns replaces only the bridge process while preserving the transcript and thread. Active turns checkpoint their prompt, thread, partial transcript, and public reasoning/progress entries; after a deployment reconnect, Bnest asks the retained thread to continue once without repeating shown text. If a retained Codex thread is unavailable, Bnest keeps the transcript, reports the fallback, clears only that thread ID, and starts a fresh conversation. **Clear chat** atomically saves an empty transcript and opens a fresh thread. Events carry their bridge identity so queued updates from a replaced bridge cannot modify the active chat.

Every chat runner uses read-only sandbox access, approval policy `never`, and disabled network and web search. Assistant message updates stream into the transcript as plain text. Public SDK reasoning summaries and generic activity status display in a collapsible **Thinking** section, keyed by their runner item IDs, and stay beside the final answer when a later assistant item arrives. Raw private reasoning and tool input are never stored or displayed. **Shift+Enter** submits the composer, while plain Enter remains available for multiline input.

The Sifat Allah activity saves version-2 progress and optional activity state to the authenticated user's central record, so it continues across that user's browsers. Version-1 browser snapshots normalize to version 2 during confirmed import while preserving progress; invalid optional activity state falls back to the dashboard without losing valid progress. **Reset progress** requires a second confirmation and saves a fresh zero-progress revision. Its two repeat queues remain question-level, quiz answers still lock before five-second advancement, and Browser Back still returns an active exercise to the mission dashboard. The app has no database, uploads, or Markdown rendering. The underlying Codex CLI may still create its normal account-level session artifacts outside the application.

The test environment substitutes a deterministic model catalog and session, and browser tests start deterministic catalog and chat runners. These fixtures verify the complete model catalog, model-specific effort choices, effective model and effort arguments, streaming, and same-thread resume protocol, but the canonical Gherkin never requires particular model wording. A real-model smoke check should assert only discovery, protocol health, stable thread identity, and non-empty completed responses; model-quality requirements belong in representative evals with outcome-based graders.

## Structure

- `lib/bnest_app/` contains the OTP application, identity boundary, and typed data repository.
- `lib/bnest_app/codex/` owns the SDK subprocess protocol and resumable session lifecycle.
- `lib/bnest_app/storage/` and `lib/bnest_app/data_repository/sqlite_store.ex` own SQLite location validation, the storage pointer, the flat-file backfill adapter, and the phase-aware storage coordinator.
- `lib/bnest_app/scheduler/` and `lib/bnest_app/scheduler.ex` own daily policy, durable claims, policy-bound inventory, retries, leases, registry dispatch, and coordination.
- `lib/bnest_app/backup/` owns the private destination pointer, marker, independent snapshot proof, fenced publication, receipts, and seven-WIB-day retention.
- `lib/bnest_app/admin_config/` declares the typed Admin settings panel registry without storing domain values.
- `lib/mix/tasks/bnest.storage.*.ex` runs headless migration, relocation, and verified retirement without a browser visit.
- `lib/bnest_app_web/` contains the endpoint, protected router, authentication/import controllers and LiveViews, chat/learning LiveViews, admin-only storage/settings/schedule LiveViews, and components.
- `priv/codex/` contains the SDK chat runner and the app-server model discovery helper.
- `priv/sqlite_repo/migrations/` contains the versioned, committed SQLite DDL, including persistent schedule and run ledgers.
- `assets/` contains browser JavaScript, CSS, and declaration boundaries used for strict checking.
- `config/` contains compile-time and runtime environment configuration.
- `tools/deployment.mjs` owns machine-local Caddy, release-slot, and rollback primitives.
- `tools/release.mjs` owns the deterministic release transaction and immutable migration identity; its adjacent tests and continuity contract prove recovery, serialization, and future resumable multi-client state.
- The repository Go resource guard adds routed-service evidence and writes a bounded schema-v4 release summary with hard routed-responsiveness budgets.
- `tools/production-origin.mjs` validates the routed HTTPS origin and exposes only its normalized origin and hostname.
- The repository Go resource guard owns bounded development and E2E listener leases before either runtime starts.
- `priv/` contains static assets and translations.
- `test/behaviour/` contains the shared driver contract, bindings, adapter hooks, and static completeness check.
- `test/unit/` contains unit tests and the system-resource-free unit driver.
- `test/integration/` contains local-only integration tests and the in-process Phoenix driver.
- `test/support/` contains marked runtime-root and synthetic-identity helpers plus deterministic Codex runners.
- `specs/apps/bnest/app/architecture.md` contains the canonical as-built C4 model.

The current operating model is a loopback Bnest server behind an independently managed private Tailscale Serve route. Follow the repository's [continuity](../../repo-governance/development/live-service-continuity.md), [restart](../../repo-governance/workflows/development-server-restart.md), and [proxy](../../repo-governance/workflows/development-tailnet-proxy.md) guidance; generated Phoenix cloud-deployment comments are not the deployment contract.
