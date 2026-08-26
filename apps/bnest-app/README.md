# bnest-app

`bnest-app` is the Phoenix LiveView application that serves Beaver Nest's local Codex chat. See the [repository README](../../README.md) for the product purpose, shared setup, privacy boundaries, and repository layout.

## Scope

This project owns the OTP application, Phoenix endpoint and router, LiveViews, Codex process bridge, server-rendered UI, browser assets, Progressive Web App (PWA) manifest and service worker, and the unit and local-only integration adapters for Bnest's canonical Gherkin behavior. It includes the child-friendly `/apps/sifat-allah` revision activity. Browser-level acceptance belongs to [bnest-app-e2e](../bnest-app-e2e/README.md); the reusable Elixir BDD engine belongs to [ex-bdd](../../libs/ex-bdd/README.md).

## Setup and Development

The project requires Elixir `~> 1.18` with Erlang/OTP and Mix, Node.js 18 or newer, and Codex authentication available to the local account. From this directory, install its dependencies and assets once:

```sh
mix setup
```

Run project tasks from the repository root:

| Task                                 | Command                                                                              |
| ------------------------------------ | ------------------------------------------------------------------------------------ |
| Start the stable development server  | `npm exec -- nx run -p bnest-app -t serve`                                           |
| Install the stable local Caddy proxy | `npm exec -- nx run -p bnest-app -t proxy:install`                                   |
| Inspect deployment routing           | `npm exec -- nx run -p bnest-app -t proxy:status`                                    |
| Build an immutable candidate release | `npm exec -- nx run -p bnest-app -t release:build`                                   |
| Start an inactive release slot       | `npm exec -- nx run -p bnest-app -t deploy:prepare -- --slot green --revision <sha>` |
| Gracefully promote a release slot    | `npm exec -- nx run -p bnest-app -t deploy:promote -- --slot green`                  |
| Route back to the previous slot      | `npm exec -- nx run -p bnest-app -t deploy:rollback`                                 |
| Stop a drained inactive slot         | `npm exec -- nx run -p bnest-app -t deploy:retire -- --slot blue`                    |
| Enable persistent tailnet HTTPS      | `npm exec -- nx run -p bnest-app -t tailnet:up`                                      |
| Inspect the tailnet proxy            | `npm exec -- nx run -p bnest-app -t tailnet:status`                                  |
| Disable the tailnet proxy            | `npm exec -- nx run -p bnest-app -t tailnet:down`                                    |
| Run the complete quick suite         | `npm exec -- nx run -p bnest-app -t test:quick`                                      |
| Run unit scenarios                   | `npm exec -- nx run -p bnest-app -t test:unit`                                       |
| Run local-only integration scenarios | `npm exec -- nx run -p bnest-app -t test:integration`                                |
| Cover the unit slice                 | `npm exec -- nx run -p bnest-app -t test:coverage:unit`                              |
| Cover the integration slice          | `npm exec -- nx run -p bnest-app -t test:coverage:integration`                       |
| Verify every behavior adapter        | `npm exec -- nx run -p bnest-app -t test:coverage:behaviour`                         |
| Run all application coverage slices  | `npm exec -- nx run -p bnest-app -t test:coverage`                                   |
| Run static type analysis             | `npm exec -- nx run -p bnest-app -t typecheck`                                       |
| Run all linters                      | `npm exec -- nx run -p bnest-app -t lint`                                            |
| Check Elixir and HEEx formatting     | `npm exec -- nx run -p bnest-app -t format`                                          |
| Audit runtime schemas without values | `npm exec -- nx run -p bnest-app -t schema:audit`                                    |
| Benchmark the password verifier      | `npm exec -- nx run -p bnest-app -t identity:benchmark`                              |

`test:quick` runs type checking, linting, unit execution, unit coverage, and static behavior completeness. It intentionally excludes integration runtime and E2E execution. Both numeric coverage slices use Mix line coverage and fail below 99%.

The deployment targets require machine-local `BNEST_DEPLOY_ROOT`, `BNEST_RUNTIME_ROOT`, and `BNEST_DEPLOY_COOKIE_FILE` values outside this repository; release builds also require `BNEST_DEPLOY_WORKTREE`. Their safe creation, promotion, and rollback sequence is defined by the [Caddy deployment workflow](../../repo-governance/workflows/development-caddy-deployment.md).

The serve target defaults to stable development compile mode because the family uses Bnest continuously. The read-only schema audit and password-verifier benchmark use the same mode, so they remain safe while the backend serves. Do not replace it with a command that recompiles the active backend for code reloading; a deliberately isolated, non-routed experiment must opt in to `BNEST_STABLE=false`.

## Shared behavior and boundaries

The canonical [C4 architecture model](../../specs/apps/bnest/app/architecture.md) defines Bnest's current system, container, component, data, and process boundaries. Every Bnest behavior starts in [`specs/apps/bnest/app/behaviours/`](../../specs/apps/bnest/app/behaviours/). The same recursively discovered feature, expanded scenarios, and shared step bindings run at both application levels:

- The unit adapter calls the subject directly without starting the OTP application. Filesystem, database, process, network, and other system resources must be replaced by test doubles.
- The integration adapter uses real in-process Phoenix components and isolated local resources. The endpoint server remains disabled, and network access—including loopback and local servers—is forbidden.
- The browser adapter lives in `bnest-app-e2e` and exercises the public HTTP boundary.

`test:coverage:behaviour` statically checks the unit, integration, and E2E adapters against the exact corpus. It rejects empty features, scenarios without explicit `When` and `Then`, undefined or ambiguous steps, unused bindings, incomplete drivers, and unit or integration boundary-policy violations.

The unit slice measures resource-free domain code: chat, learning, Codex session/settings, browser-source normalization, authorization, PWA metadata, and JSON rendering. The integration slice measures the repository and identity application facades plus model catalog, endpoint, and telemetry wiring. Generated/static Phoenix code, test scaffolding, CLI tasks, HTTP/LiveView adapters, filesystem stores, Argon2, bootstrap/import transactions, and session-record adapters are excluded from numeric line coverage because their behavior is exercised by integration, behavior, E2E, schema-audit, identity-benchmark, and manual-browser gates. Both numeric slices remain at least 99%; exclusions never remove their functional tests.

Type checking treats Elixir compiler warnings as errors, runs Dialyzer through Dialyxir, and strictly checks browser JavaScript without emitting files. Linting checks formatting, runs Credo in strict mode, runs Oxlint on browser JavaScript, and rejects unused locked dependencies without changing the lockfile.

The development server is available at [http://localhost:4000](http://localhost:4000). Normal Elixir, HEEx, JavaScript, and CSS changes reload only in an isolated non-stable experiment. Dependency, runtime configuration, and supervision-tree changes require the repository's [development-server restart workflow](../../repo-governance/workflows/development-server-restart.md). The always-available route is Tailscale Serve → loopback Caddy → one immutable Phoenix slot; Caddy changes upstream with a graceful reload while the previous LiveView connections drain and reconnect automatically. Follow the [Caddy deployment workflow](../../repo-governance/workflows/development-caddy-deployment.md) and [Tailnet proxy workflow](../../repo-governance/workflows/development-tailnet-proxy.md).

The home page at `/` is the child-friendly entry point and links to `/chat`, `/apps/sifat-allah`, and the authenticated `/data-migration` compatibility flow. One-time `/setup` creates every initial account and permanently closes; `/login` then protects family data. There is no public registration or password-recovery flow.

## Identity and Runtime Data

Production resolves one server-owned runtime root at `data/prod`; tests use a unique marked mirror below `data/test/runs/` and reject the production root. Initial accounts have a normalized username, one or more `children`, `parents`, and `admin` roles, and an Argon2id password verifier. Passwords have no application character-count rule, but each must contain a letter, number, and punctuation mark such as `_`. The browser receives only a persistent opaque session cookie; the server stores its SHA-256 digest, has no automatic session expiration, and lets one user remain logged in independently in multiple browsers. Logout revokes only that browser session. Cross-user data access is denied regardless of role.

The routed HTTPS service must start with `BNEST_COOKIE_SECURE=true`; `BNEST_IDENTITY_CUTOVER=true` enables setup/login only when the replacement backend and import path are ready. Both variables accept only `true` or `false`. Local HTTP development keeps the secure-cookie override unset, while production Mix configuration enables it automatically.

Chat, Sifat Allah progress, and explicit theme preference are versioned user-owned JSON records. The typed repository derives paths from the authenticated user, validates schemas, locks per path, writes a temporary file, atomically replaces, and reads the result back. Mutable records require the last revision. Browser import reads only `bnest.chat.v1`, `bnest.sifat-allah.v1`, and `phx:theme`; it keeps an immutable envelope and manifest, normalizes and reads the destination through the normal repository, then removes only the accepted browser key. Unknown, malformed, oversized, interrupted, or stale sources remain in the browser and cannot replace accepted data. Immutable envelopes, legacy copies, manifests, and old readers are retained for recovery.

## Visual Language

Every Bnest interface uses the **Nest workshop** visual language defined by the `--bnest-*` tokens in [`assets/css/app.css`](assets/css/app.css). Reuse those tokens rather than adding page-local colors, fonts, corner treatments, or shadows.

- **Color:** ink `#153f42`, canvas `#d8f1ec`, paper `#fff9ed`, sunflower `#f7b84b`, coral `#e5633d`, and lagoon `#80c5b8`.
- **Type:** use the rounded display stack for page titles and prominent actions; use the body stack for reading and controls.
- **Shape:** cards and primary actions use an asymmetric rounded corner with a solid ink outline and offset ink shadow. Focus states use coral; hover motion is small and respects the control's purpose.

The home-page chat card is the reference primary action. New routes should feel like the same playful workshop while keeping one obvious next action and accessible keyboard focus.

## Installable web app

The root layout links a standalone PWA manifest and Beaver Nest icon sizes for Android, desktop Chromium browsers, and Apple home-screen use. Browser JavaScript registers the service worker, which keeps a cached application shell as an offline fallback while preferring the live app whenever the home host is reachable. To install on a device, use Beaver Nest's Tailscale HTTPS address: choose **Install app** in a Chromium browser or **Share → Add to Home Screen** in Safari. The installed PWA is a private web client, not a native application; Codex conversations still require the home host to be online.

## Chat runtime

At application startup, a supervised catalog asks the local [Codex app server](https://learn.chatgpt.com/docs/app-server) for every picker-visible model and caches the validated result. If local discovery fails or returns no valid choices, the app keeps chat available with a safe Terra-only fallback. `gpt-5.6-terra` with medium reasoning effort is the application default even when Codex declares another model as its own default. The reasoning-effort selector is populated from the selected model's discovered capabilities. Changing models preserves the current effort when the new model supports it, otherwise it falls back to medium when available and then to that model's declared default.

Each connected LiveView owns one Node bridge. The bridge starts a Codex SDK thread for a fresh chat or resumes the stored thread ID. The model and reasoning-effort selectors are disabled during an active turn. Selecting either setting between turns replaces only the bridge process while preserving the transcript and thread. Active turns checkpoint their prompt, thread, and partial transcript; after a deployment reconnect, Bnest asks the retained thread to continue once without repeating shown text. If a retained Codex thread is unavailable, Bnest keeps the transcript, reports the fallback, clears only that thread ID, and starts a fresh conversation. **Clear chat** atomically saves an empty transcript and opens a fresh thread. Events carry their bridge identity so queued updates from a replaced bridge cannot modify the active chat.

Every chat runner uses read-only sandbox access, approval policy `never`, and disabled network and web search. Assistant message updates stream into the transcript as plain text. **Shift+Enter** submits the composer, while plain Enter remains available for multiline input.

The Sifat Allah activity saves version-2 progress and optional activity state to the authenticated user's central record, so it continues across that user's browsers. Version-1 browser snapshots normalize to version 2 during confirmed import while preserving progress; invalid optional activity state falls back to the dashboard without losing valid progress. **Reset progress** requires a second confirmation and saves a fresh zero-progress revision. Its two repeat queues remain question-level, quiz answers still lock before five-second advancement, and Browser Back still returns an active exercise to the mission dashboard. The app has no database, uploads, or Markdown rendering. The underlying Codex CLI may still create its normal account-level session artifacts outside the application.

The test environment substitutes a deterministic model catalog and session, and browser tests start deterministic catalog and chat runners. These fixtures verify the complete model catalog, model-specific effort choices, effective model and effort arguments, streaming, and same-thread resume protocol, but the canonical Gherkin never requires particular model wording. A real-model smoke check should assert only discovery, protocol health, stable thread identity, and non-empty completed responses; model-quality requirements belong in representative evals with outcome-based graders.

## Structure

- `lib/bnest_app/` contains the OTP application, identity boundary, and typed data repository.
- `lib/bnest_app/codex/` owns the SDK subprocess protocol and resumable session lifecycle.
- `lib/bnest_app_web/` contains the endpoint, protected router, authentication/import controllers and LiveViews, chat/learning LiveViews, and components.
- `priv/codex/` contains the SDK chat runner and the app-server model discovery helper.
- `assets/` contains browser JavaScript, CSS, and declaration boundaries used for strict checking.
- `config/` contains compile-time and runtime environment configuration.
- `tools/deployment.mjs` owns the machine-local Caddy, release-slot, and rollback commands.
- `priv/` contains static assets and translations.
- `test/behaviour/` contains the shared driver contract, bindings, adapter hooks, and static completeness check.
- `test/unit/` contains unit tests and the system-resource-free unit driver.
- `test/integration/` contains local-only integration tests and the in-process Phoenix driver.
- `test/support/` contains marked runtime-root and synthetic-identity helpers plus deterministic Codex runners.
- `specs/apps/bnest/app/architecture.md` contains the canonical as-built C4 model.

The current operating model is a loopback Bnest server behind an independently managed private Tailscale Serve route. Follow the repository's [continuity](../../repo-governance/development/live-service-continuity.md), [restart](../../repo-governance/workflows/development-server-restart.md), and [proxy](../../repo-governance/workflows/development-tailnet-proxy.md) guidance; generated Phoenix cloud-deployment comments are not the deployment contract.
