# File Impact, Dependencies, and Operations

This companion is the authoritative path and dependency inventory. Operational sections summarize execution ownership;
the exact snapshot, capacity, restore, staged-release, and rollback procedure is owned by
[Backup, Capacity, Restore, and Release](009-backup-capacity-restore-and-release.md).

## Dependency Decisions

Add compatible locked versions of `absinthe`, `absinthe_plug`, and `absinthe_phoenix`; a maintained Web Push protocol
library; and the minimum browser/test packages for the Absinthe socket client and Vitest coverage. Reuse Phoenix, PubSub,
Req, Exqlite, Playwright, and existing build tooling.

Before each manifest edit, verify the current primary package metadata, license, checksum, supported Elixir/OTP/Node
versions, security advisories, transitive footprint, and protocol coverage. Absinthe supervision must use the same
explicit subscription `pool_size` in every slot. Do not hand-write Web Push cryptography or use a browser library that
cannot authenticate the existing server session.

`VACUUM INTO` remains the backup mechanism. SQLite documents it as a consistent live-backup alternative; the incremental
Backup API would use less CPU but remains unexposed by Exqlite issue 144. Remove the forced `PRAGMA wal_checkpoint(FULL)`
from the backup hot path. Storage relocation is a separate workflow and is not changed unless its own tests prove a
shared helper is necessary.

## Runtime Configuration

| Setting                                  | Contract                                                         | Secret                        |
| ---------------------------------------- | ---------------------------------------------------------------- | ----------------------------- |
| `BNEST_DEPLOY_WEB_PUSH_PUBLIC_KEY_FILE`  | Protected deployment input file                                  | No, but private configuration |
| `BNEST_DEPLOY_WEB_PUSH_PRIVATE_KEY_FILE` | Protected VAPID private-key file                                 | Yes                           |
| `BNEST_WEB_PUSH_SUBJECT`                 | Validated `mailto:` or HTTPS contact                             | Private configuration         |
| `BNEST_BACKUP_TIMEOUT_MS`                | 60,000–7,200,000; default 1,800,000                              | No                            |
| `BNEST_FAMILY_CHAT_ENABLED`              | `false` for compatibility release, `true` for experience release | No                            |

Deployment passes the existing runtime VAPID values to both slots without printing values. The GraphQL subscription
pool is deliberately not an environment setting: code and release manifest fix it at 8 so slots cannot drift. Production
readiness fails closed for missing/malformed VAPID or feature-flag configuration. Development may report push unavailable;
tests use deterministic synthetic values. No real `.env` file is read, edited, or committed during delivery.

## File Impact

Labels are repository-relative: `[N]` new, `[E]` edited, `[M]` moved, `[D]` deleted. New helper paths discovered by an
evidenced RED are recorded in `learnings.md` before creation and reconciled here before completion.

### Domain, GraphQL, push, and backup

```text
[N] apps/bnest-app/lib/bnest_app/family_chat.ex
[N] apps/bnest-app/lib/bnest_app/family_chat/message.ex
[N] apps/bnest-app/lib/bnest_app/family_chat/store.ex
[N] apps/bnest-app/lib/bnest_app/push_notifications.ex
[N] apps/bnest-app/lib/bnest_app/push_notifications/dispatcher.ex
[N] apps/bnest-app/lib/bnest_app/push_notifications/policy.ex
[N] apps/bnest-app/lib/bnest_app/push_notifications/retention_job.ex
[N] apps/bnest-app/lib/bnest_app/push_notifications/sender.ex
[N] apps/bnest-app/lib/bnest_app/backup.ex
[E] apps/bnest-app/lib/bnest_app/backup/run.ex
[E] apps/bnest-app/lib/bnest_app/backup/receipt.ex
[E] apps/bnest-app/lib/bnest_app/application.ex
[E] apps/bnest-app/lib/bnest_app/identity.ex
[E] apps/bnest-app/lib/bnest_app/identity/session.ex
[E] apps/bnest-app/lib/bnest_app/identity/authorization.ex
[E] apps/bnest-app/lib/bnest_app/scheduler.ex
[E] apps/bnest-app/lib/bnest_app/scheduler/registry.ex
[E] apps/bnest-app/lib/bnest_app/scheduler/store.ex
[N] apps/bnest-app/lib/bnest_app_web/schema.ex
[N] apps/bnest-app/lib/bnest_app_web/schema/types/family_chat_types.ex
[N] apps/bnest-app/lib/bnest_app_web/resolvers/family_chat_resolver.ex
[N] apps/bnest-app/lib/bnest_app_web/resolvers/web_push_resolver.ex
[N] apps/bnest-app/lib/bnest_app_web/user_socket.ex
[E] apps/bnest-app/lib/bnest_app_web/endpoint.ex
[E] apps/bnest-app/lib/bnest_app_web/router.ex
[E] apps/bnest-app/lib/bnest_app_web/user_auth.ex
[E] apps/bnest-app/lib/bnest_app_web/controllers/session_controller.ex
[N] apps/bnest-app/lib/bnest_app_web/controllers/family_chat_controller.ex
[N] apps/bnest-app/lib/bnest_app_web/controllers/family_chat_html.ex
[N] apps/bnest-app/lib/bnest_app_web/controllers/family_chat_html/room.html.heex
[E] apps/bnest-app/lib/bnest_app_web/controllers/page_html/home.html.heex
[E] apps/bnest-app/lib/bnest_app_web/controllers/health_controller.ex
```

`Backup.Run` becomes the registered handler/adapter and delegates to `BnestApp.Backup`; it no longer checkpoints or opens
the application repository connection for snapshot work. GraphQL resolvers call services and contain no SQL.

### Migration, release, and configuration

```text
[N] apps/bnest-app/priv/sqlite_repo/migrations/20260918000000_add_family_chat.exs
[N] apps/bnest-app/lib/bnest_app/release/migrations/family_chat.ex
[N] apps/bnest-app/lib/bnest_app/release/migrations.ex
[E] apps/bnest-app/lib/bnest_app/release/migrations/persistent_schedules.ex
[E] apps/bnest-app/config/config.exs
[E] apps/bnest-app/config/runtime.exs
[E] apps/bnest-app/config/test.exs
[E] apps/bnest-app/mix.exs
[E] apps/bnest-app/mix.lock
[E] apps/bnest-app/tools/deployment.mjs
[E] apps/bnest-app/tools/release.mjs
[E] apps/bnest-app/tools/release.test.mjs
[E] apps/bnest-app/tools/continuity-contract.test.mjs
```

The migration timestamp was selected after inspecting the authoring snapshot, whose latest existing migration is
`20260830000000_add_persistent_schedules.exs`. Execution revalidates the inventory against current `origin/main` before
creating the file; a collision is a recorded File Impact deviation, not permission to overwrite or create two files at
one timestamp.

The migration adds only compatible objects and disabled work. Release code calls public Scheduler operations for handler
activation and one-time backup-time convergence; it never updates schedule or chat tables directly.

`deployment.mjs` must remove `stream_close_delay 5m` from the generated Caddy `reverse_proxy` block while retaining the
global `grace_period 5m`. `release.mjs` keeps the prior application slot warm during its existing five-minute observation
but proves that Caddy config reload closed the prior socket and that the replacement subscribed on the promoted revision
within ten seconds. Release/continuity tests reject a nonzero stream-close delay, a routed handshake reaching the prior
slot after promotion, retirement before the observation passes, or any assumption that independent slots share PubSub.

### Browser and PWA

```text
[N] apps/bnest-app/assets/js/family_chat.js
[N] apps/bnest-app/assets/js/family_chat/graphql.js
[N] apps/bnest-app/assets/js/family_chat/outbox.js
[N] apps/bnest-app/assets/js/family_chat/persistence_indexeddb.js
[N] apps/bnest-app/assets/js/family_chat/reconnect.js
[E] apps/bnest-app/assets/js/app.js
[E] apps/bnest-app/assets/css/app.css
[E] apps/bnest-app/assets/tsconfig.json
[N] apps/bnest-app/assets/vitest.config.mts
[E] apps/bnest-app/priv/static/service-worker.js
[E] apps/bnest-app/priv/static/manifest.webmanifest
[E] package.json
[E] package-lock.json
```

This list is the plan's authored, pre-execution snapshot at the module-group level (e.g., one `outbox.js` entry covers
its later Phase 4 REFACTOR split into `outbox.js`/`outbox_namespace.js`/`outbox_send.js`/`backoff.js`/`clock.js`, and
`mount_browser.js` as the browser bootstrap entry point); `persistence_indexeddb.js` above is added as the one new
top-level production module Phase 9 introduced. `delivery.md`'s own dated phase notes are the authoritative as-built
file list; this snapshot is not backfilled file-for-file on every intra-phase split.

The service worker handles static cache, `push`, and `notificationclick`; it does not own outbox draining or authenticated
GraphQL. The browser app owns IndexedDB only while active.

### Canonical specifications and governance

```text
[N] specs/apps/bnest/README.md
[D] specs/apps/bnest/app/README.md
[D] specs/apps/bnest/app/architecture.md
[D] specs/apps/bnest/app/behaviours/README.md
[N] specs/apps/bnest/app-be/README.md
[N] specs/apps/bnest/app-be/architecture.md
[N] specs/apps/bnest/app-be/behaviours/README.md
[N] specs/apps/bnest/app-be/behaviours/authentication.feature
[N] specs/apps/bnest/app-be/behaviours/centralized_data.feature
[N] specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature
[N] specs/apps/bnest/app-be/behaviours/family_chat_operations.feature
[N] specs/apps/bnest/app-be/behaviours/scheduled_backups.feature
[N] specs/apps/bnest/app-be/behaviours/sqlite_storage.feature
[N] specs/apps/bnest/app-fe/README.md
[N] specs/apps/bnest/app-fe/architecture.md
[N] specs/apps/bnest/app-fe/behaviours/README.md
[N] specs/apps/bnest/app-fe/behaviours/authentication.feature
[M] specs/apps/bnest/app/behaviours/chat.feature -> specs/apps/bnest/app-fe/behaviours/chat.feature
[N] specs/apps/bnest/app-fe/behaviours/centralized_data.feature
[N] specs/apps/bnest/app-fe/behaviours/family_chat.feature
[N] specs/apps/bnest/app-fe/behaviours/scheduled_backups.feature
[M] specs/apps/bnest/app/behaviours/sifat_allah.feature -> specs/apps/bnest/app-fe/behaviours/sifat_allah.feature
[N] specs/apps/bnest/app-fe/behaviours/sqlite_storage.feature
[D] specs/apps/bnest/app/behaviours/authentication.feature
[D] specs/apps/bnest/app/behaviours/centralized_data.feature
[D] specs/apps/bnest/app/behaviours/scheduled_backups.feature
[D] specs/apps/bnest/app/behaviours/sqlite_storage.feature
[E] repo-governance/development/behaviour-driven-development.md
```

Rules propagation may add only exact ledger-proven point-of-use/map paths; reconcile them into this list before commit.

### Application unit and integration adapters

```text
[E] apps/bnest-app/project.json
[N] apps/bnest-app/behaviour-coverage.json
[E] apps/bnest-app/test/test_helper.exs
[E] apps/bnest-app/test/behaviour/verify.exs
[N] apps/bnest-app/test/behaviour/steps/family_chat_backend_steps.exs
[E] apps/bnest-app/test/behaviour/steps/scheduled_backup_steps.exs
[E] apps/bnest-app/test/behaviour/driver.ex
[E] apps/bnest-app/test/behaviour/support/unit.exs
[E] apps/bnest-app/test/behaviour/support/integration.exs
[N] apps/bnest-app/test/unit/support/family_chat_driver.ex
[N] apps/bnest-app/test/integration/support/family_chat_driver.ex
[N] apps/bnest-app/test/unit/bnest_app/family_chat_test.exs
[N] apps/bnest-app/test/unit/bnest_app_web/schema_test.exs
[N] apps/bnest-app/test/unit/bnest_app/push_notifications/policy_test.exs
[N] apps/bnest-app/test/unit/bnest_app/push_notifications/retention_job_test.exs
[N] apps/bnest-app/test/unit/bnest_app/push_notifications/sender_test.exs
[N] apps/bnest-app/test/unit/bnest_app/backup_test.exs
[N] apps/bnest-app/test/integration/bnest_app/family_chat_test.exs
[N] apps/bnest-app/test/integration/bnest_app/family_chat_migration_test.exs
[N] apps/bnest-app/test/integration/bnest_app/push_notifications_test.exs
[N] apps/bnest-app/test/integration/bnest_app/family_chat_push_delivery_retention_test.exs
[N] apps/bnest-app/test/integration/bnest_app/backup_concurrency_test.exs
[N] apps/bnest-app/test/integration/bnest_app_web/graphql_test.exs
[N] apps/bnest-app/test/integration/bnest_app_web/graphql_socket_test.exs
[E] apps/bnest-app/test/integration/bnest_app/identity_test.exs
[E] apps/bnest-app/test/integration/bnest_app/scheduled_backup_test.exs
[E] apps/bnest-app/test/integration/bnest_app/persistent_schedules_migration_test.exs
[E] apps/bnest-app/test/integration/bnest_app_web/authentication_test.exs
[E] apps/bnest-app/test/integration/bnest_app_web/admin_settings_live_test.exs
[E] apps/bnest-app/test/integration/support/home_page_driver.ex
[E] apps/bnest-app/test/unit/support/home_page_driver.ex
[E] apps/bnest-app/test/support/test_identity.ex
[E] apps/bnest-app/test/support/test_runtime_root.ex
[N] apps/bnest-app/assets/test/behaviour/family_chat.steps.ts
[N] apps/bnest-app/assets/test/behaviour/verify.ts
[N] apps/bnest-app/assets/test/unit/family_chat/outbox.test.ts
[N] apps/bnest-app/assets/test/unit/family_chat/reconnect.test.ts
[N] apps/bnest-app/assets/test/unit/family_chat/state.test.ts
```

`bnest-app:test:unit` aggregates backend ExBDD/ExUnit and frontend Vitest serially while enforcing at least 99% line
coverage. `test:integration` remains real isolated SQLite/loopback only. `test:quick` excludes integration and E2E.

### Backend E2E project

```text
[N] apps/bnest-app-be-e2e/project.json
[N] apps/bnest-app-be-e2e/README.md
[N] apps/bnest-app-be-e2e/tsconfig.json
[N] apps/bnest-app-be-e2e/behaviour-coverage.json
[N] apps/bnest-app-be-e2e/tests/steps/authentication.steps.ts
[N] apps/bnest-app-be-e2e/tests/steps/centralized-data.steps.ts
[N] apps/bnest-app-be-e2e/tests/steps/family-chat.steps.ts
[N] apps/bnest-app-be-e2e/tests/steps/scheduled-backups.steps.ts
[N] apps/bnest-app-be-e2e/tests/steps/sqlite-storage.steps.ts
[N] apps/bnest-app-be-e2e/tests/support/authentication.ts
[N] apps/bnest-app-be-e2e/tests/support/centralized-data.ts
[N] apps/bnest-app-be-e2e/tests/support/graphql.ts
[N] apps/bnest-app-be-e2e/tests/support/scheduled-backups.ts
[N] apps/bnest-app-be-e2e/tests/support/sqlite-storage.ts
[N] apps/bnest-app-be-e2e/tests/support/subscriptions.ts
[N] apps/bnest-app-be-e2e/tests/support/test-identity.ts
[N] apps/bnest-app-be-e2e/tests/support/test-runtime.mts
[N] apps/bnest-app-be-e2e/tools/check-behaviour-compliance.mts
[N] apps/bnest-app-be-e2e/tools/run-e2e.mts
```

### Frontend E2E replacement

```text
[M] apps/bnest-app-e2e/project.json -> apps/bnest-app-fe-e2e/project.json
[M] apps/bnest-app-e2e/README.md -> apps/bnest-app-fe-e2e/README.md
[M] apps/bnest-app-e2e/tsconfig.json -> apps/bnest-app-fe-e2e/tsconfig.json
[M] apps/bnest-app-e2e/playwright.config.mts -> apps/bnest-app-fe-e2e/playwright.config.mts
[N] apps/bnest-app-fe-e2e/behaviour-coverage.json
[M] apps/bnest-app-e2e/tools/behaviour-compliance.mts -> apps/bnest-app-fe-e2e/tools/behaviour-compliance.mts
[M] apps/bnest-app-e2e/tools/behaviour-compliance.test.mts -> apps/bnest-app-fe-e2e/tools/behaviour-compliance.test.mts
[M] apps/bnest-app-e2e/tools/check-behaviour-compliance.mts -> apps/bnest-app-fe-e2e/tools/check-behaviour-compliance.mts
[M] apps/bnest-app-e2e/tools/run-caddy.mts -> apps/bnest-app-fe-e2e/tools/run-caddy.mts
[M] apps/bnest-app-e2e/tools/run-e2e.mts -> apps/bnest-app-fe-e2e/tools/run-e2e.mts
[M] apps/bnest-app-e2e/tests/steps/authentication.steps.ts -> apps/bnest-app-fe-e2e/tests/steps/authentication.steps.ts
[M] apps/bnest-app-e2e/tests/steps/authorization.steps.ts -> apps/bnest-app-fe-e2e/tests/steps/authorization.steps.ts
[M] apps/bnest-app-e2e/tests/steps/browser.steps.ts -> apps/bnest-app-fe-e2e/tests/steps/browser.steps.ts
[M] apps/bnest-app-e2e/tests/steps/centralized_data.steps.ts -> apps/bnest-app-fe-e2e/tests/steps/centralized_data.steps.ts
[M] apps/bnest-app-e2e/tests/steps/codex_progress.steps.ts -> apps/bnest-app-fe-e2e/tests/steps/codex_progress.steps.ts
[M] apps/bnest-app-e2e/tests/steps/codex-settings.steps.ts -> apps/bnest-app-fe-e2e/tests/steps/codex-settings.steps.ts
[M] apps/bnest-app-e2e/tests/steps/home-layout.steps.ts -> apps/bnest-app-fe-e2e/tests/steps/home-layout.steps.ts
[M] apps/bnest-app-e2e/tests/steps/home.steps.ts -> apps/bnest-app-fe-e2e/tests/steps/home.steps.ts
[M] apps/bnest-app-e2e/tests/steps/release-recovery.steps.ts -> apps/bnest-app-fe-e2e/tests/steps/release-recovery.steps.ts
[M] apps/bnest-app-e2e/tests/steps/scheduled-backups.steps.ts -> apps/bnest-app-fe-e2e/tests/steps/scheduled-backups.steps.ts
[M] apps/bnest-app-e2e/tests/steps/sifat_allah.steps.ts -> apps/bnest-app-fe-e2e/tests/steps/sifat_allah.steps.ts
[M] apps/bnest-app-e2e/tests/steps/sqlite_storage_access.steps.ts -> apps/bnest-app-fe-e2e/tests/steps/sqlite_storage_access.steps.ts
[M] apps/bnest-app-e2e/tests/steps/sqlite_storage_admin_ui.steps.ts -> apps/bnest-app-fe-e2e/tests/steps/sqlite_storage_admin_ui.steps.ts
[M] apps/bnest-app-e2e/tests/steps/sqlite_storage_cli.steps.ts -> apps/bnest-app-fe-e2e/tests/steps/sqlite_storage_cli.steps.ts
[M] apps/bnest-app-e2e/tests/steps/sqlite_storage_lifecycle.steps.ts -> apps/bnest-app-fe-e2e/tests/steps/sqlite_storage_lifecycle.steps.ts
[M] apps/bnest-app-e2e/tests/support/authentication.ts -> apps/bnest-app-fe-e2e/tests/support/authentication.ts
[M] apps/bnest-app-e2e/tests/support/centralized-data.ts -> apps/bnest-app-fe-e2e/tests/support/centralized-data.ts
[M] apps/bnest-app-e2e/tests/support/process-lifecycle.ts -> apps/bnest-app-fe-e2e/tests/support/process-lifecycle.ts
[M] apps/bnest-app-e2e/tests/support/routed-rollout.ts -> apps/bnest-app-fe-e2e/tests/support/routed-rollout.ts
[M] apps/bnest-app-e2e/tests/support/scheduled-backups.ts -> apps/bnest-app-fe-e2e/tests/support/scheduled-backups.ts
[M] apps/bnest-app-e2e/tests/support/sqlite-identity.ts -> apps/bnest-app-fe-e2e/tests/support/sqlite-identity.ts
[M] apps/bnest-app-e2e/tests/support/sqlite-storage.ts -> apps/bnest-app-fe-e2e/tests/support/sqlite-storage.ts
[M] apps/bnest-app-e2e/tests/support/storage-authority.ts -> apps/bnest-app-fe-e2e/tests/support/storage-authority.ts
[M] apps/bnest-app-e2e/tests/support/test-identity.ts -> apps/bnest-app-fe-e2e/tests/support/test-identity.ts
[M] apps/bnest-app-e2e/tests/support/test-runtime.mts -> apps/bnest-app-fe-e2e/tests/support/test-runtime.mts
[N] apps/bnest-app-fe-e2e/tests/steps/family-chat.steps.ts
[N] apps/bnest-app-fe-e2e/tests/steps/family-chat-offline-persistence.steps.ts
[N] apps/bnest-app-fe-e2e/tests/support/family-chat.ts
```

The old `apps/bnest-app-e2e/` directory is absent after the atomic move and both replacement projects are green.

### Documentation and plan assets

```text
[E] README.md
[E] apps/bnest-app/README.md
[N] apps/bnest-app-be-e2e/README.md
[N] apps/bnest-app-fe-e2e/README.md
[E] docs/how-to-guides/releasing-bnest.md
[E] docs/reference/glossary.md
[E] specs/apps/README.md
[E] plans/in-progress/README.md
[E] plans/in-progress/family-chat-room/README.md
[E] plans/in-progress/family-chat-room/brd.md
[E] plans/in-progress/family-chat-room/prd.md
[E] plans/in-progress/family-chat-room/delivery.md
[E] plans/in-progress/family-chat-room/learnings.md
[E] plans/in-progress/family-chat-room/tech-docs/001-architecture-and-data-flow.md
[E] plans/in-progress/family-chat-room/tech-docs/002-data-model-and-migration-contract.md
[E] plans/in-progress/family-chat-room/tech-docs/003-realtime-pagination-and-consistency.md
[E] plans/in-progress/family-chat-room/tech-docs/004-web-push-notifications-and-privacy.md
[E] plans/in-progress/family-chat-room/tech-docs/005-ui-design.md
[E] plans/in-progress/family-chat-room/tech-docs/006-specification-delta-and-adapter-map.md
[E] plans/in-progress/family-chat-room/tech-docs/007-file-impact-dependencies-and-operations.md
[N] plans/in-progress/family-chat-room/tech-docs/008-graphql-api-authentication-and-errors.md
[N] plans/in-progress/family-chat-room/tech-docs/009-backup-capacity-restore-and-release.md
[E] plans/in-progress/family-chat-room/tech-docs/README.md
[E] plans/in-progress/family-chat-room/assets/README.md
[E] plans/in-progress/family-chat-room/assets/ui-hearth-lofi-desktop.svg
[E] plans/in-progress/family-chat-room/assets/ui-hearth-lofi-tablet.svg
[E] plans/in-progress/family-chat-room/assets/ui-hearth-lofi-mobile.svg
[E] plans/in-progress/family-chat-room/assets/ui-hearth-hifi-desktop.svg
[E] plans/in-progress/family-chat-room/assets/ui-hearth-hifi-tablet.svg
[E] plans/in-progress/family-chat-room/assets/ui-hearth-hifi-mobile.svg
```

Documentation edits occur during implementation when the as-built behavior exists. This plan amendment changes only the
plan and its assets now; it does not prematurely rewrite current-state project/specification documentation.

## Backup Operation

1. Scheduler claims `prod-sqlite-backup-daily` and calls its registered adapter.
2. Adapter delegates to `BnestApp.Backup` with a cancellable deadline and claim fence.
3. Service reads actual database bytes, page count/page size, WAL bytes, and destination free capacity. It requires the
   measured snapshot reserve before opening output.
4. A dedicated Exqlite connection runs `VACUUM INTO` to a non-existing partial path. No forced full WAL checkpoint runs.
5. Timeout, cancellation, or error removes only the owned partial artifact and returns a retryable categorized failure.
6. An independent read-only connection runs quick/integrity and logical schema proof. The service syncs and atomically
   renames the artifact, writes a value-safe receipt, then retains one newest owned pair across seven WIB dates.
7. Scheduler owns persisted retries; application traffic is never intentionally stopped.

Concurrent-write proof runs routed read/write probes for the entire backup interval and requires zero failures, p95 at
most 500 ms, and every probe at most two seconds. Any breach fails the plan and activates recovery.

## Two-stage Production Release

### Compatibility release

- Add additive schema/seed, GraphQL HTTP/socket, fixed Absinthe pool, services, handlers, backup correction, split test
  topology, and dormant room shell with feature flag off.
- Promote through Caddy while continuous exact-origin HTTP/readiness/revision and GraphQL-socket probes run. Config reload
  closes prior-slot sockets immediately; replacement sockets must subscribe on the promoted revision within ten seconds.
- Keep the prior revision process-warm but unrouted through the five-minute observation, then retire it. The compatibility
  revision becomes the rollback floor.
- Only after every runnable slot knows the handlers, enable push retention and converge backup time through Scheduler.

### Experience release

- Enable home navigation, canonical route, room UI, IndexedDB outbox, and reconnect behavior without schema breakage.
- Existing clients reconnect to the promoted slot, subscribe, catch up, and drain without page refresh. A commit inside
  the Caddy-close/reconnect gap renders exactly once.
- Two isolated authenticated synthetic contexts prove draft preservation, queued send, reconnect, catch-up, and exact-once
  rendering. Production verification itself uses only health/readiness/schema/operational evidence and creates no test
  user or message in production.

Both stages use slot-local PubSub with `RELEASE_DISTRIBUTION=none`; a nonzero Caddy `stream_close_delay` is forbidden.
They require zero routed failures, p95 at or below 500 ms, and every sample at or below two seconds from preflight through
bounded drain. After proof, stop old slots, candidates, temporary servers, watchers, stubs, and proxies; retain only the
active route and valid rollback artifact.

## Manual and Operational Verification

- Use `curl` against an isolated exact origin for every named GraphQL query/mutation. Assert status, content type,
  `data`/`errors`, authorized and unauthenticated outcomes, validation, idempotency, and side effects.
- Use a protocol-capable client for `familyChatMessageCommitted`; handshake alone is insufficient.
- Hold a routed socket across Caddy reload, assert prior connection close, promoted revision on the replacement handshake,
  subscription acknowledgement within ten seconds, gap catch-up, and no routed handshake on the warm prior slot.
- Exercise desktop/tablet/mobile, 200% zoom, keyboard, screen-reader announcements, offline/reopen/reconnect, exploratory,
  spec-blind usability, and release cutover.
- Restore a complete snapshot into an isolated marked root and prove room, messages, push subscriptions, delivery state,
  and Scheduler state without printing body or secret values.
- Record measured storage inputs and selected reserve. Capacity failure stops before snapshot; health failure stops release.

## Recovery

- **Before promotion:** keep the current route; remove only owned candidate/partial artifacts after evidence capture.
- **Backup timeout/capacity/integrity failure:** Scheduler retries according to policy; do not block application traffic or
  promote an unverified artifact.
- **Compatibility failure:** never enable new handlers or experience UI; return to the prior healthy route.
- **Experience failure:** roll back through Caddy to the compatibility floor, preserve additive data, and let clients
  reconnect/catch up.
- **Post-promotion responsiveness breach:** route the last healthy compatible revision, prove revision and journeys, drain
  the rejected slot, and retain additive tables/messages.
- **Provider outage:** leave healthy chat active; bounded push retry owns external unavailability.
