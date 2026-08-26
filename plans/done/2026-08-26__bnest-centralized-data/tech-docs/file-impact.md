# File Impact

This is the reconciled implementation tree relative to the repository at execution start. `[E]` means updated, `[N]` new, `[M]` moved, and `[D]` deleted. Comments align within each tree for scanning. Formal plan documents and their design assets are lifecycle records, not product implementation impact.

## Repository Entry Points

```text
.
├── [E] .gitignore     # Track approved roots while ignoring every generated runtime record.
├── [E] AGENTS.md      # Route continuity, connected-LiveView, test-identity, and changed-file diagram rules.
└── [E] README.md      # Describe authentication, centralized records, runtime roots, and current operation.
```

## Bnest Runtime and Browser Interface

```text
apps/bnest-app/
├── [E] README.md                                             # Document commands, coverage boundaries, identity/data flow, and operation.
├── [E] mix.exs                                               # Add Argon2id and focused unit/integration coverage scopes.
├── [E] mix.lock                                              # Lock Argon2id and its reviewed transitive dependencies.
├── [E] project.json                                          # Add schema-audit and identity-benchmark Nx targets.
├── assets/
│   ├── css/
│   │   └── [E] app.css                                       # Setup/login/import UI, responsive states, focus, and AA contrast fixes.
│   └── js/
│       ├── [E] app.js                                        # Register setup/import hooks and keep unrelated browser state intact.
│       ├── [N] browser_import.js                             # Read only three allow-listed legacy keys and clean accepted keys only.
│       └── [N] identity_setup.js                             # Manage non-password setup drafts without browser persistence.
├── config/
│   ├── [E] config.exs                                        # Runtime-root, cutover, cookie, Argon2id, and repository defaults.
│   ├── [E] dev.exs                                           # Stable-backend mode without code reloaders/watchers.
│   ├── [E] runtime.exs                                       # Resolve port/root/cutover and explicit routed-HTTPS cookie safety.
│   └── [E] test.exs                                          # Require marked integration roots and deterministic identity/Codex fixtures.
├── lib/
│   ├── bnest_app/
│   │   ├── [E] application.ex                               # Supervise repository, identity, and existing Codex boundaries.
│   │   ├── [E] chat.ex                                      # Permit transcript preservation when a retained thread becomes unavailable.
│   │   ├── [N] data_repository.ex                           # Expose the startup-owned typed store facade.
│   │   ├── data_repository/
│   │   │   ├── [N] backup.ex                                # Preserve immutable application/user legacy bytes with checksum proof.
│   │   │   ├── [N] import.ex                                # Allow-list, envelope, normalize, write, read-back, and cleanup outcome.
│   │   │   ├── [N] manifest.ex                              # Deterministic import identity, lifecycle, retry, and safe failure category.
│   │   │   ├── [N] normalizer.ex                            # Convert chat, learning, and theme browser sources into typed candidates.
│   │   │   ├── [N] recovery_source.ex                       # Revalidate immutable browser envelopes before recovery normalization.
│   │   │   ├── [N] schema.ex                                # Validate every version-one record and safe structural audit projection.
│   │   │   └── [N] store.ex                                 # Typed paths, symlink/traversal defense, locks, revisions, atomic read-back.
│   │   ├── [N] identity.ex                                  # Coordinate bootstrap while keeping login/session work concurrent.
│   │   ├── identity/
│   │   │   ├── [N] authorization.ex                         # Self-owned capability matrix and default cross-user denial.
│   │   │   ├── [N] bootstrap.ex                             # One-time journaled account creation and matching-file crash recovery.
│   │   │   ├── [N] credential_verifier.ex                   # Argon2id hashing, verification, boundaries, and timing-safe missing user.
│   │   │   ├── [N] file_store.ex                            # Account, username index, bootstrap, and identity-file operations.
│   │   │   └── [N] session.ex                               # Persistent token-digest sessions and one-browser revocation.
│   │   └── codex/
│   │       └── [E] port_session.ex                           # Surface an unavailable resumed thread as a recoverable event.
│   ├── bnest_app_web/
│   │   ├── [N] user_auth.ex                                 # HTTP/LiveView authentication, safe return paths, and disconnect scope.
│   │   ├── components/
│   │   │   ├── [E] layouts.ex                               # Pass authenticated theme ownership into the root layout.
│   │   │   └── [E] layouts/root.html.heex                   # Global theme dock, server persistence, CSRF, and page description.
│   │   ├── controllers/
│   │   │   ├── [N] bootstrap_controller.ex                  # One final setup POST without retaining plaintext passwords.
│   │   │   ├── [E] page_controller.ex                       # Load authorized home identity/theme state.
│   │   │   ├── [N] session_controller.ex                    # Login/logout and persistent opaque cookie boundary.
│   │   │   ├── [N] theme_controller.ex                      # Save explicit user theme without client persistence.
│   │   │   └── page_html/
│   │   │       └── [E] home.html.heex                        # Protected entry points and accurate centralized-data wording.
│   │   ├── live/
│   │   │   ├── [E] chat_live.ex                             # User-owned revisions, durable transcript, and fresh-thread fallback.
│   │   │   ├── [N] data_migration_live.ex                   # Confirmed source cards, state text, retry, and accepted cleanup signal.
│   │   │   ├── [N] login_live.ex                            # One-time setup and returning-login screens.
│   │   │   └── [E] sifat_allah_live.ex                      # User-owned progress/activity persistence and conflict refresh.
│   │   └── [E] router.ex                                    # Public setup/session endpoints and protected LiveView sessions.
│   └── mix/tasks/
│       ├── [N] bnest.identity.benchmark.ex                   # Report only safe Argon2id parameters and timing class.
│       └── [N] bnest.schema.audit.ex                         # Read-only production/test structural validation.
└── priv/codex/
    └── [E] chat_runner.mjs                                   # Emit resume_failed when failure precedes a resumed thread start.
```

## Bnest Tests and Fixtures

```text
apps/bnest-app/test/
├── [E] test_helper.exs                                           # Own one integration runtime and exact after-suite cleanup.
├── behaviour/
│   ├── [E] driver.ex                                             # Add authentication, import, isolation, and resume operations.
│   ├── steps/
│   │   ├── [N] authentication_steps.exs                          # Bind eight identity/session scenarios.
│   │   └── [N] centralized_data_steps.exs                        # Bind seven import/persistence/resume scenarios.
│   └── support/
│       └── [E] integration.exs                                   # Dispatch new behavior through isolated real components.
├── integration/
│   ├── support/
│   │   ├── [E] codex_fixture_session.ex                          # Exercise successful and unavailable resume outcomes.
│   │   └── [E] home_page_driver.ex                               # Drive authenticated behavior and user-scoped evidence.
│   ├── bnest_app/
│   │   ├── [E] application_test.exs                              # Prove immutable startup root and production-root rejection.
│   │   ├── [N] backup_test.exs                                   # Prove immutable collision/checksum/restore behavior.
│   │   ├── [N] browser_import_test.exs                           # Prove allow-list, idempotency, stale/rejected, and recovery behavior.
│   │   ├── [N] data_repository_test.exs                          # Prove contracts, typed paths, races, failures, facade, and cleanup.
│   │   ├── [N] identity_test.exs                                 # Prove bootstrap, hash, sessions, recovery, roles, and facade failures.
│   │   └── [N] schema_audit_test.exs                             # Prove value-free read-only structural output.
│   └── bnest_app_web/
│       ├── [N] authentication_test.exs                            # Prove setup, generic login, cookies, protection, and two browsers.
│       ├── [N] centralized_persistence_test.exs                   # Prove fresh server-only chat, learning, and theme writes.
│       ├── [E] chat_live_test.exs                                 # Prove persistence, isolation, and resume-failure transcript safety.
│       └── [E] sifat_allah_live_test.exs                          # Prove central progress/reset isolation.
├── support/
│   ├── [E] codex_fixture_runner.mjs                              # Simulate unavailable resumed threads deterministically.
│   ├── [E] conn_case.ex                                          # Provide authenticated integration connection helpers.
│   ├── [N] test_identity.ex                                      # Generate only scenario-safe `test-user-` identities.
│   └── [N] test_runtime_root.ex                                  # Mark, validate, reject production, and clean one exact root.
└── unit/
    ├── support/
    │   └── [E] home_page_driver.ex                               # Bind new behavior with resource-free doubles.
    ├── bnest_app/
    │   ├── [E] chat_test.exs                                     # Cover nil-thread transcript preservation.
    │   ├── [N] data_normalizer_test.exs                           # Cover allow-listed values, safe fallback, and rejection.
    │   └── [N] identity_policy_test.exs                           # Cover username/password boundaries and capability denial.
    └── bnest_app_web/
        └── [N] user_auth_test.exs                                 # Cover safe return-path and cookie/session decisions.
```

## Browser E2E Harness

```text
apps/bnest-app-e2e/
├── [E] README.md                                  # Document connected readiness and scenario identity isolation.
├── [E] playwright.config.mts                      # Use one marked run and exact localhost origin.
├── [E] project.json                               # Wrap the E2E target in guarded runtime lifecycle tooling.
├── tests/
│   ├── steps/
│   │   ├── [N] authentication.steps.ts            # Setup, login, restart, two-browser, roles, and isolation journeys.
│   │   └── [N] centralized_data.steps.ts          # Import, retry, cleanup, continuation, theme, and resume journeys.
│   └── support/
│       ├── [N] authentication.ts                  # Connected-LiveView login/setup helpers per scenario.
│       ├── [N] centralized-data.ts                # Synthetic legacy values and user-scoped record evidence.
│       ├── [N] test-identity.ts                   # Unique `test-user-` credentials and bootstrap input.
│       └── [N] test-runtime.mts                   # Marker validation and exact cleanup primitive.
└── tools/
    └── [N] run-e2e.mts                            # Create/clean the exact runtime around Playwright.
```

## Runtime Roots

```text
data/
├── prod/
│   ├── [N] general/.gitkeep              # Tracked production shared-data placeholder.
│   ├── apps/beaver-nest/
│   │   └── [N] .gitkeep                  # Tracked application-shared placeholder.
│   ├── [N] system/.gitkeep               # Tracked identity/operational placeholder.
│   └── [N] users/.gitkeep                # Tracked user-owned placeholder.
└── test/
    └── runs/
        └── [N] .gitkeep                  # Tracked parent; generated marked runs remain ignored.
```

Generated records mirror `{general,apps/beaver-nest,system,users}` below either root. Production may generate bootstrap, account, username-index, session, manifest, schema-registry, import-envelope, chat, learning, theme, and immutable legacy-copy files. Tests generate the same shapes only below one marked `data/test/runs/<run-id>/`. The private root-level inventory found zero non-placeholder sources, so no legacy copy or normalized production record was needed and no source changed.

## Specifications, Governance, and Learning

```text
specs/apps/bnest/app/
├── [E] architecture.md                     # Canonical authenticated centralized-data C4 model.
└── behaviours/
    ├── [E] README.md                       # Map the new canonical feature files.
    ├── [N] authentication.feature          # Eight identity/session/authorization scenarios.
    ├── [N] centralized_data.feature        # Seven import/persistence/recovery scenarios.
    ├── [E] chat.feature                    # Keep public PWA separate; authenticate user-owned chat.
    └── [E] sifat_allah.feature             # Authenticate centralized learning behavior.

repo-governance/
├── development/
│   ├── [E] README.md                       # Map the new continuity standard.
│   ├── [E] end-to-end-testing.md           # Require exact origins, connected readiness, and user-scoped parallel proof.
│   ├── [N] live-service-continuity.md      # Make active local/routed availability a blocking invariant.
│   └── [E] test-identities.md              # Require distinct parallel identities and prohibit aggregate shared assertions.
└── workflows/
    ├── [E] development-server-restart.md   # Require a verified alternate backend before routed restart.
    ├── [E] development-tailnet-proxy.md    # Define alternate-port promotion and routed LiveView proof.
    └── [E] plan-execution.md                # Detect active services and stop work on degraded endpoints.

plans/ideas/q1-urgent-important/
├── [E] README.md                           # Map the rollout learning.
└── [N] zero-downtime-local-rollouts.md     # Capture a future repeatable promoter without duplicating this plan.
```

The plan moved from `plans/backlogs/bnest-centralized-data/` to `plans/in-progress/bnest-centralized-data/`, then after every human and AI gate passed to `plans/done/2026-08-26__bnest-centralized-data/`; both stage READMEs were updated for each move. Its 12 Markdown documents and 12 synthetic SVG assets remain fully mapped by the archived plan READMEs.
