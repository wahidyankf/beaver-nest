# File Impact

Labels describe changes expected when this plan is executed relative to its repository state at execution start: `[E]` update, `[N]` new, `[M]` moved, `[D]` deleted. Plan documents and design assets already present are decision inputs, not future implementation impact.

Every listed runtime ID is server-generated. Phase 1 replaces only `<legacy-relative-path>` with the exact private inventory mapping outside Git; no other directory, ellipsis, or glob substitutes for a file.

## Application: Runtime and Interface

```text
apps/bnest-app/
├── [E] README.md                                              # Final setup, login, data, recovery-source, and restore guide.
├── [E] assets/css/app.css                                     # Accessible setup, login, source-confirmation, conflict, status, retry UI.
├── [E] assets/js/app.js                                       # Allow-listed import and removal of only accepted Bnest browser keys.
├── [E] config/config.exs                                      # Non-secret identity, repository, Argon2id, and cookie defaults.
├── [E] config/prod.exs                                        # Trust only proxy HTTPS rewriting needed by secure cookies.
├── [E] config/runtime.exs                                     # Resolve one runtime root and production HTTPS/cookie requirements.
├── [E] config/test.exs                                        # Reject production roots and use deterministic isolated-test settings.
├── [E] mix.exs                                                # Add the maintained Argon2id verifier dependency.
├── [E] mix.lock                                               # Lock the reviewed Argon2id dependency resolution.
├── [E] project.json                                           # Add the `schema:audit` Nx target around the read-only Mix task.
├── [E] lib/bnest_app/application.ex                           # Supervise identity and flat-file repository boundaries.
├── [N] lib/bnest_app/identity.ex                              # Bootstrap, login, logout, current-user, and capability API.
├── [N] lib/bnest_app/identity/authorization.ex                # Multi-role capability matrix plus ownership default deny.
├── [N] lib/bnest_app/identity/bootstrap.ex                    # Locked journaled setup, crash recovery, and permanent closure.
├── [N] lib/bnest_app/identity/credential_verifier.ex          # Argon2id hashing, verification, and safe failure behavior.
├── [N] lib/bnest_app/identity/file_store.ex                   # Bootstrap, account, and normalized-username record storage.
├── [N] lib/bnest_app/identity/session.ex                      # Token digest lookup and one-browser issue/revoke operations.
├── [N] lib/bnest_app/data_repository.ex                       # Typed user-owned read, write, import, recovery, and restore API.
├── [N] lib/bnest_app/data_repository/recovery_source.ex       # Envelope/legacy recovery-source checksum verification.
├── [N] lib/bnest_app/data_repository/import.ex                # Allow-list, idempotency, normalization, and state transitions.
├── [N] lib/bnest_app/data_repository/manifest.ex              # Pending/retryable/rejected/accepted manifest operations.
├── [N] lib/bnest_app/data_repository/schema.ex                # Every JSON contract and safe structural projection.
├── [N] lib/bnest_app/data_repository/store.ex                 # Root/path validation, locks, temp writes, atomic replace, read-back.
├── [N] lib/mix/tasks/bnest.schema.audit.ex                    # Read-only public-structure production/test comparison.
├── [N] lib/bnest_app_web/user_auth.ex                         # HTTP/on-mount auth, event scope, and digest-specific disconnect.
├── [E] lib/bnest_app_web/components/core_components.ex        # Setup, password, role, confirmation, alert, and status primitives.
├── [E] lib/bnest_app_web/components/layouts/root.html.heex    # Server-owned explicit theme with browser system fallback.
├── [N] lib/bnest_app_web/controllers/bootstrap_controller.ex  # Atomic setup POST; never renders or retains submitted passwords.
├── [N] lib/bnest_app_web/controllers/session_controller.ex    # Login/logout HTTP boundary that sets or clears the cookie.
├── [E] lib/bnest_app_web/controllers/page_html/home.html.heex # Authorized entry points and accurate central-storage explanation.
├── [E] lib/bnest_app_web/live/chat_live.ex                    # Central chat, revision conflict, and resume-failure transcript safety.
├── [N] lib/bnest_app_web/live/data_migration_live.ex          # Confirmed source list, progress, retry, and accepted cleanup UI.
├── [N] lib/bnest_app_web/live/login_live.ex                   # Mutually exclusive one-time setup and returning-login screens.
├── [E] lib/bnest_app_web/live/sifat_allah_live.ex             # Central progress/session state and revision-conflict refresh.
└── [E] lib/bnest_app_web/router.ex                            # Public auth/setup endpoints and protected LiveView sessions.
```

## Application: Behavior, Unit, and Integration Tests

```text
apps/bnest-app/
├── [N] test/support/test_identity.ex                               # Synthetic users and account fixtures only.
├── [N] test/support/test_runtime_root.ex                           # Marked run creation, prod rejection, stop checks, exact cleanup.
├── [E] test/behaviour/driver.ex                                    # Auth, import, migration-state, and cross-user operations.
├── [E] test/behaviour/steps/home_page_steps.exs                    # Updated protected home/chat/learning bindings.
├── [N] test/behaviour/steps/authentication_steps.exs               # Setup, hash login, persistence, two-browser, roles, isolation.
├── [N] test/behaviour/steps/centralized_data_steps.exs             # Import, retry, read-back, cleanup, legacy, and resume bindings.
├── [E] test/behaviour/support/integration.exs                      # Isolated runtime and identity resources for integration bindings.
├── [E] test/behaviour/support/unit.exs                             # Identity/repository doubles for unit bindings.
├── [N] test/integration/bnest_app/centralized_data_test.exs        # Filesystem import, manifests, retry, recovery, restore, cleanup.
├── [N] test/integration/bnest_app/schema_audit_test.exs            # Safe structural comparison and forbidden-output assertions.
├── [N] test/integration/bnest_app_web/authentication_test.exs      # Setup transaction, login cookie, protected routes, two browsers.
├── [E] test/integration/bnest_app_web/chat_live_test.exs           # Protected central chat, persistence, isolation, failed resume.
├── [N] test/integration/bnest_app_web/data_migration_live_test.exs # Confirm/import/status/retry/client-cleanup interface.
├── [E] test/integration/bnest_app_web/sifat_allah_live_test.exs    # Protected central progress and reset isolation.
├── [E] test/unit/bnest_app/chat_test.exs                           # Source v1/v2 normalization and failed-resume behavior.
├── [N] test/unit/bnest_app/data_repository_test.exs                # Contracts, paths, locks, checksums, atomic writes, idempotency.
├── [N] test/unit/bnest_app/identity_test.exs                       # Username policy, bootstrap, Argon2id, sessions, authorization.
└── [E] test/unit/bnest_app/sifat_allah_test.exs                    # Source v1/v2 normalization and activity-session fallback.
```

## Browser E2E

```text
apps/bnest-app-e2e/
├── [E] README.md                             # Isolated runtime/profile setup and journey coverage.
├── [E] playwright.config.mts                 # Unique run root, web process, browser profile, and cleanup lifecycle.
├── [N] tests/support/test-user.ts            # `test-user-` account factory with synthetic credentials.
├── [N] tests/support/test-runtime.ts         # Marker/root validation, dedicated server start, and exact cleanup.
├── [N] tests/steps/authentication.steps.ts   # Setup/login, persistence, two-browser, roles, and isolation journeys.
├── [E] tests/steps/browser.steps.ts          # Protected chat and centralized continuation journeys.
├── [N] tests/steps/centralized_data.steps.ts # Import, preservation, retry, theme, cleanup, and failed resume journeys.
└── [E] tests/steps/sifat_allah.steps.ts      # Protected centralized learning journeys.
```

## Ignored Runtime Records

```text
[E] .gitignore                                                             # Track approved placeholders; ignore every runtime record.

data/
├── prod/
│   ├── [N] general/.gitkeep                                       # Production shared-data placeholder.
│   ├── [N] apps/beaver-nest/.gitkeep                              # Production Bnest-shared placeholder.
│   ├── [N] system/.gitkeep                                        # Production operational-state placeholder.
│   ├── [N] users/.gitkeep                                         # Production user-data placeholder.
│   ├── [N] general/<legacy-relative-path>                         # Verified copy selected by private inventory.
│   ├── [N] apps/beaver-nest/legacy/<import-id>/source.bin         # Immutable opaque Bnest legacy copy.
│   ├── [N] system/bootstrap.json                                  # Pending/closed setup journal and crash recovery authority.
│   ├── [N] system/accounts/<user-id>.json                         # Username metadata, roles, Argon2id verifier.
│   ├── [N] system/manifests/<import-id>.json                      # Import identity, outcome, retry, and restore evidence.
│   ├── [N] system/schema-registry.json                            # Supported record/source versions and migrations.
│   ├── [N] system/sessions/<session-record-id>.json               # Token-digest browser session; no raw cookie token.
│   ├── [N] system/usernames/<normalized-username>.json            # Normalized username-to-user-ID lookup.
│   ├── [N] users/<user-id>/chat/current.json                      # Central chat and private Codex resume state.
│   ├── [N] users/<user-id>/imports/<import-id>.json               # Immutable exact browser-source envelope.
│   ├── [N] users/<user-id>/legacy/<import-id>/source.bin          # Immutable user-owned legacy recovery source when ownership is proven.
│   ├── [N] users/<user-id>/preferences/theme.json                 # Explicit light/dark preference only.
│   └── [N] users/<user-id>/sifat-allah/progress.json              # Central progress and optional activity session.
└── test/
    └── runs/
        ├── [N] .gitkeep                                             # Tracked parent only; generated runs remain ignored.
        └── <run-id>/
            ├── [N] .bnest-test-run.json                             # Exact-run cleanup authority marker.
            ├── [N] apps/beaver-nest/legacy/<import-id>/source.bin   # Synthetic opaque legacy source.
            ├── [N] system/bootstrap.json                            # Synthetic pending/closed setup journal.
            ├── [N] system/accounts/<user-id>.json                   # Synthetic `test-user-` account.
            ├── [N] system/manifests/<import-id>.json                # Synthetic import manifest.
            ├── [N] system/schema-registry.json                      # Mirrored test schema registry.
            ├── [N] system/sessions/<session-record-id>.json         # Isolated test-browser token digest.
            ├── [N] system/usernames/<normalized-username>.json      # Synthetic username index.
            ├── [N] users/<user-id>/chat/current.json                # Synthetic central chat.
            ├── [N] users/<user-id>/imports/<import-id>.json         # Synthetic exact browser envelope.
            ├── [N] users/<user-id>/legacy/<import-id>/source.bin    # Synthetic user-owned legacy recovery source.
            ├── [N] users/<user-id>/preferences/theme.json           # Synthetic explicit preference.
            └── [N] users/<user-id>/sifat-allah/progress.json        # Synthetic central learning state.
```

Root-level `data/{general,apps,system,users}/` is absent from the changed tree because every entry remains an unchanged read-only migration source. `<legacy-relative-path>` is the only unresolved private filename; Phase 1 must inventory it without putting the value in Git. Production and test paths otherwise mirror the [fixed contracts](data-contracts.md).

## Specifications and Documentation

```text
specs/apps/bnest/app/
├── [E] architecture.md              # Auth, token-digest session, repository, import, manifest, recovery boundaries.
├── [E] README.md                    # Application map for the new architecture and behavior.
└── behaviours/
    ├── [E] README.md                # Behavior map for the new features.
    ├── [E] chat.feature             # Protected user-owned central chat behavior.
    ├── [E] sifat_allah.feature      # Protected user-owned central learning behavior.
    ├── [N] authentication.feature   # Setup once, hash login, persistent sessions, roles, isolation.
    └── [N] centralized_data.feature # Import, read-back cleanup, retry, theme, and resume behavior.
```

No governance file is listed as future implementation impact: the planning and runtime-data rules are aligned while this backlog plan is refined. Delivery changes governance later only if final as-built evidence reveals a genuinely reusable rule gap.
