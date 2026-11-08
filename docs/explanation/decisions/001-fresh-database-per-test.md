# 001. Fresh Real SQLite Database For Every Database-Touching Test

Date: 2026-11-08

Status: Proposed

## Context

Integration tests (`apps/bnest-app/test/integration`, run serially with `--max-cases 1`) and both browser E2E projects
(`apps/bnest-app-be-e2e`, `apps/bnest-app-fe-e2e`) share one database for a whole run. Facts checked in the code:

- `config/test.exs` (integration layer) creates one marked pair of roots per `mix` invocation:
  `data/test/runs/<run-id>/` and `~/bnest/data/test/runs/<run-id>/`. `ConnCase` lazily creates
  `test-user-integration`, `test-user-other` and one `test-user-bdd-<hash>` per scenario; they live for the whole run.
- `tools/run-e2e.mts` (both projects) creates one runtime through `tests/support/test-runtime.mts` and starts one
  `MIX_ENV=test mix phx.server`. Seeding is a mix of the UI one-shot `POST /setup`, account JSON files written
  straight into the run root followed by `mix bnest.storage.migrate`, and `mix run -e` calls
  (`live-sqlite.ts`, `test-user-records.ts`, `liveJson`). Each `mix run -e` boots a second BEAM on a 2 vCPU host.
  Between scenarios `restoreStorageAuthority` copies files back and runs `DELETE FROM` on six tables.
- `Identity.bootstrap/1` is one-shot (`/setup` closes forever), GraphQL has only family-chat and push mutations, and a
  system-sender chat message has no public mutation. The app has no testing header and no `Mix.env()` gate. Production
  safety today is configuration only (`:dev_routes` in `router.ex`, `test_runtime_owned`).
- `config/test.exs` points Family Chat at a second SQLite file,
  `~/bnest/data/test/family-chat/<run>/bnest.sqlite3`, outside the paired roots. It is not swept by
  `tools/test-data-cleanup.mjs` (24 such directories exist on this host today) and it makes the test schema layout
  differ from production, which has one database.
- `SqliteCoordinator.ensure_started!/1` already re-points the one named `SqliteRepo` when the resolved path changes
  (`:global.trans`, stop, start). `FileConfigStore` re-reads the storage pointer file on every operation.
  `Storage.migrate/2` and `ScratchCopy` already depend on this. `Records` holds its flat store in GenServer state.
  `BnestApp.TestRuntimeRoot` and `BnestApp.TestIdentity` live in `test/support`, which `mix.exs` compiles only for
  `MIX_ENV=test`.
- Release migration path (`tools/deployment.mjs`, `release.mjs`): `release:migrate` evaluates
  `BnestApp.Release.Migrations.PersistentSchedules.apply_and_verify!/1`, which runs `Ecto.Migrator` over
  `priv/sqlite_repo/migrations` (4 files) under the exclusive storage lock, reconciles the `prod-sqlite-backup-daily`
  seed and verifies objects. `BnestApp.Release.Migrations.FamilyChat` runs the Family Chat migration, seed room,
  retention schedule and handler check. `BnestApp.Release.Migrations.apply_and_verify!/0` calls both.
  `mix bnest.storage.migrate` calls `Storage.migrate/2`, which runs the same Ecto migrations through
  `SqliteCoordinator.migrate_schema!/0` and optionally activates SQLite.
- Governance: [test identities](../../../repo-governance/development/test-identities.md) (synthetic `test-user-`
  accounts, paired marked roots, fail closed, exact-pair cleanup, 24 h stale sweep),
  [runtime flat-file data](../../../repo-governance/conventions/runtime-flat-file-data.md),
  [end-to-end testing](../../../repo-governance/development/end-to-end-testing.md),
  [live-service continuity](../../../repo-governance/development/live-service-continuity.md),
  [specification maintenance](../../../repo-governance/development/specification-maintenance.md) and
  [resource-aware development](../../../repo-governance/development/resource-aware-development.md).

The user goal: every integration and E2E test that touches the database spawns a new database and fills it with seed
(through an API; any API that is dangerous in production sits behind a special testing header that production does not
have), tears it down, and ships to production. Extra requirements: the database is a real SQLite file used through the
real Repo and coordinator with no in-memory doubles; tests use the normal application code paths; every spawn runs the
real release migrations; there is no snapshot copy and no `DELETE FROM` reset; the order is spawn, migrate, seed, test,
teardown; and the migrated test schema must equal what the release migrations produce.

Options considered: (a) keep one database and reset rows (today; not a new database and it leaks state); (b) restart
the Phoenix server per scenario (a fresh BEAM, Argon2, Ecto and asset boot per scenario on 2 vCPU is too heavy and
disturbs port leases); (c) copy a prebuilt snapshot database (rejected by the requirement, and it can drift from the
migrations); (d) re-point the running test server at a newly spawned database. Option (d) is chosen.

## Decision

### 1. What "fresh database" means

A **test instance** is one empty SQLite database file, created, migrated, seeded, used by exactly one test, and deleted.

| Layer                                        | Granularity                                                                                                                                           | Reason                                                                              |
| -------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| Integration (in-process ExUnit)              | one instance per ExUnit test; an ExBdd scenario is one test                                                                                           | `--max-cases 1` makes tests serial, so a switch never races another test            |
| E2E (`bnest-app-be-e2e`, `bnest-app-fe-e2e`) | one instance per Gherkin scenario per Playwright project (the same scenario in `chromium`, `tablet-chromium`, `mobile-chromium` gets three instances) | `workers: 1` and `fullyParallel: false` make one active instance per server correct |

The server is not restarted. The test build re-points the running server's storage at the new instance (a "switch").
Module-level `setup_all` sharing of a database is not allowed for database-touching tests. A test that needs no storage
(pure functions, and the `unit` layer with its in-memory doubles) spawns nothing. The unit layer keeps its doubles
because it never touches a database; the rule "real SQLite, no doubles" covers every integration and E2E test. Only
external-boundary doubles stay: `RecordingPushSender` (no real push provider) and the Codex fixture session.

**Switch protocol.** `BnestApp.TestInstance.spawn!/2` (test build only), in this order:

1. Take the single in-process `TestInstance` lock and refuse with `:instance_active` if an instance is current.
2. Refuse with `:instance_busy` if `Task.Supervisor.children(BnestApp.Scheduler.Tasks) != []`.
3. Create the instance directories and markers (section 3).
4. Inside `Storage.with_exclusive_lock/1` (drains every `Records` operation that holds a shared lease):
   `Storage.stop/0`;
   write the storage pointer (`FileConfigStore.write!/1`, a normal `schemaVersion: 1` pointer whose
   `databaseDirectory` is the instance `db/` directory and whose `databaseGeneration` is `test-<instanceId>`); set
   `Application.put_env` for `:backup_repository_root`; for a flat-primary instance also `:runtime_root` and the
   `Records` store (`:sys.replace_state(Records, ...)` with `FileRecordBackend.new!(instanceFlatRoot)`, done from
   `test/support` so no production module changes); delete `<run>/storage-config/backup.json`. Release the lease.
5. Migrate (section 4), then seed (section 2).

If any step fails, `spawn!/2` stops the repo, removes the instance directories, restores the "no instance" state and
raises with the failed step. A new instance is the only way to a different database; nothing resets rows.

**Why re-pointing is safe, and only in the test build.** `SqliteCoordinator` already restarts the repo under
`:global.trans` when the path changes, and the pointer is re-read on every operation, so the switch composes two
existing mechanisms. The exclusive lease drains `Records` users. Family Chat, Push and Scheduler SQL users do not hold
the lease, so the switch also needs quiescence: the scenario's browser contexts are closed before `DELETE`, the
scheduler is not automatic in the test layer (`scheduler_automatic?: false`), and the busy check above refuses a switch
while a scheduler task runs. The switch code (`TestInstance`, the `Records` state replacement, `put_env`) lives in
`test/support` and is compiled only for `MIX_ENV=test`; production code gains no re-pointing entry point. The run base
(the run-level root pair) must stay data-free: its `users/` and `system/accounts` are empty and it holds no
`*.sqlite3` file. The health endpoint reads storage only in the `sqlite_primary` phase, so an idle test server does not
create a base database. `/health/ready` reports `storageGeneration == test-<instanceId>` after a spawn, which is the
proof that the server serves the new database.

**Family Chat uses the instance database, as in production.** The instance sets no `:family_chat_sqlite_path`, so
Family Chat resolves `Storage.database_path()` like production. The separate Family Chat file and its leaking
`~/bnest/data/test/family-chat/` directory are removed from the integration layer (the `unit` layer keeps its setting).
`backup_config_path` and `backup_repository_root` move under the paired roots too (section 3).

**Phase.** `phase` is `sqlite_primary` by default (what production runs) and `flat_primary` only for scenarios that test
flat files or migration. A `sqlite_primary` instance reaches that phase by the real path, `Storage.migrate/2` with
`activate?: true` over an empty flat root (the same call as `mix bnest.storage.migrate --activate`), before any account
exists. A `flat_primary` instance also gets a flat instance root; a `sqlite_primary` instance does not, which keeps
Dropbox (it synchronizes `data/`) from syncing thousands of short-lived files.

A `flat_primary` instance can also be spawned with `storage: "unconfigured"` (the default is `"configured"`). It is the
state of a fresh installation before an administrator chooses the database location: the spawn writes no storage
pointer, runs no migration, and leaves `db/` empty. The storage page offers the choice only while no pointer exists
(`Storage.persist_directory/1` refuses a second one), and it opens the profile's default location when it reads storage
with no pointer. The default location of the test profile is the run base, which must stay data-free, so the spawn
re-points `:storage_profile` at the instance's own `db/` directory, and the drop restores it. The state is only for
scenarios whose subject is that choice (the Gherkin tag `@storage-unconfigured`); `sqlite_primary` always has a pointer,
so the server refuses the pair with `invalid_request`. Such an instance holds no SQLite database for Family Chat or
push, so a seed that fills `familyChat` or `pushSubscriptions` is refused with `wrong_phase`. Accounts and flat records
seed as on any `flat_primary` instance. The instance drop removes the pointer the choice wrote, as for any instance.

**Secondary BEAMs.** `mix run -e` helpers and FE rollout candidates are other processes. The harness starts them per
scenario after the instance exists and passes `BNEST_TEST_INSTANCE_ID`, `BNEST_RUNTIME_ROOT` (the flat instance root,
or the run base for `sqlite_primary`) and the same `BNEST_STORAGE_CONFIG`. `config/test.exs` derives paths from
`BNEST_TEST_INSTANCE_ID` through `BnestApp.TestInstance.Paths` (a pure module, mirrored in TypeScript with a parity
test). They are never switched at runtime. The seeding API removes most `mix run -e` calls (section 2).

### 2. Seeding API

Which API is used:

- **Public API (GraphQL, HTTP, LiveView) under a seeded user's real session** for anything production can already do:
  `sendFamilyChatMessage`, `upsertWebPushSubscription`, `PUT /preferences/theme`, `POST /login`. Small
  scenario-specific state uses it, because it exercises production code. Existing steps such as `postMessages` stay.
- **Testing endpoints** only for what production cannot do or what would be too slow: instance lifecycle, accounts
  (setup is one-shot), system-sender messages, records with no public mutation (Sifat Allah progress, Codex chat
  transcript), and bulk history. Seeding code calls the production facades in-process: `Identity.bootstrap/1` for the
  first admin set, then the identity store `put_account`/`put_username`; the Family Chat send entry point the GraphQL
  resolver uses; `PushNotifications` subscribe; `SifatAllah.save_progress`; the CodexChat transcript store. It never
  writes SQL, files or fixtures directly. On a `sqlite_primary` instance the first admin set also goes through the
  identity store, because bootstrap is refused there (see the accounts rule below).
- No endpoint evaluates code, accepts SQL, or accepts a path. Reads that tests do today with `mix run -e`
  (`liveJson`, claim counts) stay on `mix run -e` in this change, now instance-aware; named, allow-listed read
  operations are a follow-up.

**Routes** (all under `/__bnest_testing/v1`, JSON, `content-type: application/json`, bodies at most 256 KiB):

| Route                      | Success                                                                                                                                                          | Purpose                                                      |
| -------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------ |
| `GET /state`               | 200 `{schemaVersion:1, runId, instance: null or {instanceId, label, phase, generation, createdAt}}`                                                              | diagnostics and leak audit                                   |
| `POST /instances`          | 201 `{instanceId, label, phase, generation, accounts:[{username,userId,roles}], environment:{BNEST_TEST_INSTANCE_ID, BNEST_RUNTIME_ROOT, BNEST_STORAGE_CONFIG}}` | spawn, migrate, seed                                         |
| `POST /instances/:id/seed` | 200 `{seedKey, applied}`                                                                                                                                         | more seed for the current instance, idempotent per `seedKey` |
| `DELETE /instances/:id`    | 204                                                                                                                                                              | teardown of the current instance                             |

`POST /instances/:id/seed` body: `{seedKey, seed}`, where `seed` has the shape of the `seed` object of
`POST /instances`. Its response is `{seedKey, applied}`; `applied` is `false` when the same key comes again with the
same body, and `:id` must be the current instance (another id is `not_current`).

`POST /instances` body: `{runId, label, instanceId?, phase?, storage?, seed?}`. `label` is a slug of at most 60 characters.
`instanceId` is the client's own random id matching `^[a-z0-9]{16}$`; when it is absent the server generates it. `seed`
is `{accounts?, familyChat?, pushSubscriptions?, records?}`:

```json
{
  "accounts": [
    {
      "username": "test-user-admin-1a2b3c4d",
      "password": "<synthetic>",
      "roles": ["admin", "parents"]
    }
  ],
  "familyChat": {
    "messages": [
      {
        "sender": "<username> or system",
        "body": "...",
        "idempotencyKey": "k1"
      }
    ]
  },
  "pushSubscriptions": [
    {
      "owner": "<username>",
      "endpoint": "https://push.allowed.example.com/<id>",
      "p256dh": "...",
      "auth": "..."
    }
  ],
  "records": [
    {
      "owner": "<username>",
      "kind": "sifatAllahProgress | codexChatTranscript | themePreference | browserImportInterrupted",
      "value": {}
    }
  ]
}
```

Limits: at most 40 accounts, 500 messages, 40 push subscriptions and 40 records. Usernames match
`^test-user-[a-z0-9-]{1,22}$` (at most 32 characters in all, which is the production username rule and the `maxlength` of
the login form's username field) and carry the instance short id (the first 8 characters of `instanceId`) as one
hyphen-separated segment, so identities stay unique per instance and traceable. The server generates an absent id only
after it parses the body, so a spawn whose seed names accounts sends its own `instanceId`, which the usernames then
carry. On a `flat_primary` instance, a seed with accounts that include an admin sends the first admin set through
`Identity.bootstrap/1`, so setup closes exactly as in production. On a
`sqlite_primary` instance production refuses bootstrap, because its routed identity store never reads as empty, so
the seed writes every account, admins included, through the identity-store port (`put_account`/`put_username`, with
the configured credential hasher), and `/setup` stays unopened. A spawn with no accounts leaves `/setup` open only on
a `flat_primary` instance, which is how "Initial setup creates accounts exactly once" gets a pristine database; that
scenario must use phase `flat_primary`.

`browserImportInterrupted` takes `value: {storageArea, storageKey, payload}`. The pair must be a source that
`BnestApp.Storage.Import` recognizes: `sessionStorage` `bnest.chat.v1` (at most 500000 bytes), `localStorage`
`bnest.sifat-allah.v1` (at most 10000 bytes) or `localStorage` `phx:theme` (at most 16 bytes). The seed writes what an
import leaves when it stops after preserving its envelope: the envelope, and a manifest with status `retryable` and
failure `read-back-failed`. Its import id is the production identity of the owner, source and payload, so a later
browser import of the same payload resumes that manifest. The kind is accepted on a `flat_primary` instance only,
because a SQLite instance's records store is the run base, which must stay data-free.

**Error codes.** Every body is `{"error": {"code": "<code>", "detail": "<text>", "path": "<seed path or null>"}}` and
never contains a secret, a password or a filesystem path outside the run.

| Status | Code                          | When                                                                                                                                                                                                                     |
| ------ | ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 404    | stock `ErrorJSON` "Not Found" | any failed guard below; identical to a missing route                                                                                                                                                                     |
| 400    | `invalid_request`             | malformed JSON, wrong content type, unknown top-level key, or an `instanceId` that is not 16 lowercase letters or digits                                                                                                 |
| 409    | `run_mismatch`                | body `runId` differs from the server's run id                                                                                                                                                                            |
| 409    | `instance_active`             | spawn while an instance is current, or spawn with an `instanceId` whose directories already exist (its own detail)                                                                                                       |
| 409    | `not_current`                 | `:id` is not the current instance                                                                                                                                                                                        |
| 409    | `instance_busy`               | scheduler task running during spawn or delete                                                                                                                                                                            |
| 409    | `seed_conflict`               | same `seedKey` with a different body                                                                                                                                                                                     |
| 422    | `seed_invalid`                | `invalid_username`, `invalid_role`, `duplicate_username`, `unknown_sender`, `unknown_owner`, `unknown_seed_key`, `too_many`, `invalid_payload`, `wrong_phase`, `unsupported_source`, `oversized`; `path` names the field |
| 500    | `spawn_failed`                | with `step` of `create`, `migrate`, `activate` or `seed`; the server already rolled back                                                                                                                                 |
| 500    | `seed_failed`                 | a production write refused a seed of `POST /instances/:id/seed`; the instance is kept, and the test deletes it                                                                                                           |
| 500    | `cleanup_failed`              | with the retained synthetic path (inside the run roots); fails the scenario                                                                                                                                              |

**Guards (all must pass, in this order, otherwise the stock 404 with no side effect):**

1. **Compiled out of production.** The routes exist only when `BnestAppWeb.TestingRoutes.mounted?(Mix.env(),
Application.compile_env(:bnest_app, :testing_control, false))` is true at compile time. It is true only for
   `Mix.env() == :test` with `config :bnest_app, :testing_control, true`, which only `config/test.exs` sets.
   `mounted?/2` is a pure function in `lib/` (like `DevRoutes.mounted?/1`) so a unit test can assert that `:prod` and
   `:dev` give false for every flag value. The plug, controller (`BnestAppWeb.TestingControl.*`) and all of
   `BnestApp.TestInstance.*` live in `test/support`, so the production build does not contain them even if the router
   condition were wrong; a router that mounted them in production would fail to compile (fail closed at build time).
2. The peer is loopback (`conn.remote_ip` is `127.0.0.1` or `::1`) and there is no `x-forwarded-for`,
   `x-forwarded-host` or `x-forwarded-proto` header, so a request that came through Caddy is refused.
3. `Application.get_env(:bnest_app, :test_runtime_owned) == true` and both run roots validate with
   `TestRuntimeRoot.validate/1` and `validate_sqlite/1` (exact parent, no symlink, marker with matching `runId`).
4. Header `x-bnest-testing: <secret>`, compared with `Plug.Crypto.secure_compare/2` against
   `System.get_env("BNEST_TEST_CONTROL_SECRET")`, read at request time inside the test-only plug. A missing secret, or
   one shorter than 32 bytes, closes every request. The runner generates 32 random bytes (hex) per run and passes them
   only through the environment of the Phoenix `webServer`, the Playwright process and secondary BEAMs; it never logs or
   writes them. Support code calls the endpoints with Node `fetch`, not Playwright's request context, so traces do not
   capture the header.
5. Every path an operation touches is derived from `(runId, instanceId)` by `TestInstance.Paths`, never from input.
   `instanceId` matches `^[a-z0-9]{16}$`. Spawn and delete re-validate both markers before acting.

**Caddy.** Production Caddy is a catch-all `reverse_proxy`. Compile-out already yields 404; a second, independent layer
is added to the generated Caddyfile (`tools/caddy-config.mjs`): a matcher on `/__bnest_testing/*` answers `404` and the
proxy strips `x-bnest-testing` from upstream requests. It is regenerated on the next promote, so it needs no separate
reload. The FE E2E Caddy is separate, and the testing client talks to the backend loopback port directly
(`BNEST_E2E_BACKEND_PORT`), never through Caddy; browsers never receive the secret.

### 3. Roots, markers and teardown

Layout. The paired run roots and their marker rule do not change; instances are validated children of them:

```text
data/test/runs/<run>/                      run base flat root (marker; must stay data-free)
data/test/runs/<run>/instances/<inst>/     flat instance root, flat_primary only (marker recordType bnest-test-instance)
~/bnest/data/test/runs/<run>/              run base SQLite root (marker)
~/bnest/data/test/runs/<run>/instances/<inst>/{db/,backup-repository/}   (marker; db/bnest.sqlite3 is the database)
```

A flat instance root also holds `.bnest-test-run.json`, a `bnest-test-run` marker whose `runId` is the instance id. The
application start validates a test runtime root through `FileRecordBackend.new!/1`, which reads exactly that file name
and requires `runId` to equal the root's basename, and a secondary BEAM boots on the flat instance root. Production
validation is not loosened; the instance marker stays the proof of ownership and the only marker the teardown trusts.

`backup-repository/` is an isolated git repository (as `createBackupRepository` builds today) beside, not inside, `db/`,
because Backup refuses a destination inside the live database directory. `BNEST_BACKUP_CONFIG` stays one fixed file in
the run base `storage-config/`; each spawn and each delete removes it. The instance marker is
`{schemaVersion:1, recordType:"bnest-test-instance", runId, instanceId, owner:"bnest-test-harness", createdAt}`.
`test-runtime.mts` stops creating `~/bnest/data/test/backup-repository/<run>`.

Who deletes what:

| When                        | Actor                                                                                                                                                                                                                                                                          | Action                                                                                                                                                                                                                                                                                                              |
| --------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| After each integration test | ExUnit `on_exit` registered by the spawning `setup` (`FreshDatabaseCase`, `ConnCase`, the ExBdd `before_scenario`/`after_scenario` hooks)                                                                                                                                      | `TestInstance.drop!/1`: validate markers, `Storage.stop/0`, remove the pointer and the instance directories, restore "no instance"                                                                                                                                                                                  |
| After each E2E scenario     | playwright-bdd `After` hook in `lifecycle.steps.ts` (replaces `restoreStorageAuthority`): closes browser contexts first, then `DELETE /instances/:id`; a worker-scoped auto fixture repeats the delete if the hook never ran                                                   | same, over HTTP                                                                                                                                                                                                                                                                                                     |
| End of an integration run   | existing `ExUnit.after_suite`                                                                                                                                                                                                                                                  | counts remaining instance directories, then `TestRuntimeRoot.cleanup!`; a leftover instance fails the run (`System.halt(1)` after cleanup if `after_suite` cannot change the exit status)                                                                                                                           |
| End of an E2E run           | `globalTeardown` (server still up): `GET /state`, `DELETE` any current instance, assert the base is data-free. `run-e2e.mts` `finally`, after Playwright and its servers exit: list instance directories in both roots, set exit code 1 on any, then remove the validated pair | the existing exact-pair cleanup, moved after server stop; `globalTeardown` no longer removes the roots while the server may still write                                                                                                                                                                             |
| Crash or kill               | `cleanupStaleTestData()` at the start of every `run-e2e.mts` and on schedule                                                                                                                                                                                                   | removes whole run directories older than 24 h with a valid marker and a dead owner pid; instances go with their run. It also sweeps the legacy `~/bnest/data/test/{family-chat,backup-config,backup-repository}` directories (no marker, so only directories older than 24 h, only under those three exact parents) |
| Failed teardown             | any of the above                                                                                                                                                                                                                                                               | `cleanup_failed` reports the exact retained synthetic path and fails the test; nothing outside the validated pair is deleted                                                                                                                                                                                        |

A crash between spawn steps can leave an empty, unmarked instance root for a short moment: each root is created and its
marker is written at once, and no database file exists before its marker. The empty root holds no data, and the run's
removal (the stale sweep or the run's own teardown) deletes it with its run.
`restore_rehearsal` writes a short-lived file in the system temp directory and removes it in the same call; it is not
part of the instance.

### 4. Order, real migrations, cost and schema parity

Order for every test: **spawn** (directories, markers, pointer, repo started on an empty file) -> **migrate** ->
**seed**
-> **test** -> **teardown**.

**Migrate** uses only production entry points, in the order a release uses them:

1. `Storage.migrate/2` (which calls `SqliteCoordinator.migrate_schema!/0`) for the `sqlite_primary` activation; for a
   `flat_primary` instance `SqliteCoordinator.migrate_schema!/0` alone. Both run the `priv/sqlite_repo/migrations` set
   through `Ecto.Migrator`.
2. `BnestApp.Release.Migrations.apply_and_verify!/0`, which is `PersistentSchedules.apply_and_verify!/1` then
   `FamilyChat.apply_and_verify!/0`. Migrations are already up, so it reconciles the release seeds and runs the
   release's own verification. The two steps never nest the exclusive lock; the switch releases its lease first.

Test-support code may not contain `CREATE`, `ALTER`, `Ecto.Migrator`, a reference to `priv/sqlite_repo`, a copy of an
existing `.sqlite3` file, or a table-wide `DELETE`. A source-scan test (like `SchemaSourceScan`) fails the build if it
does. A test database is never a snapshot and never reset in place.

**Cost per spawn, from reading the code (no job was run).** `config.exs` sets `synchronous: :full` and `pool_size: 5`.
A spawn pays: about 10 inodes and two small marker writes (under 5 ms); the pointer's atomic write; coordinator start
(open, `PRAGMA journal_mode=WAL`, close, then a 5-connection pool); `Ecto.Migrator` creating `schema_migrations` and
applying 4 migrations, each compiled with `Code.compile_file` and committed in its own transaction (about 6 to 8
fsync-bound commits); the release seed inserts (a handful of single-statement commits); `PRAGMA quick_check` and
`VACUUM INTO` of a near-empty database for the activation; account seeding (Argon2 with `m_cost: 8, t_cost: 1` in test,
about 1 ms each); and `git init` for the backup repository (one short process, only when the scenario needs backup).
Estimate: 80 to 250 ms typical, up to 500 ms on a busy disk. With about 250 integration tests, and about 250 scenarios
per
E2E project, that is roughly one minute added per run, against a suite that today pays per-scenario `mix run -e` BEAM
boots (hundreds of ms of CPU each), which this change removes. A per-test spawn is acceptable on 2 vCPU because it is
serial, mostly I/O bound, and replaces heavier work. The estimate is a hypothesis and becomes a gate: a timing test
records p50 and p95 of 20 spawns and fails above p95 500 ms. If it fails, the fallback keeps one spawn per test but
skips `git init` and `quick_check` for scenarios that do not need them; it never shares a database.

**Schema parity check.** A test (`test/integration/bnest_app/storage/test_instance_schema_test.exs`) computes a
fingerprint of a spawned instance: SHA-256 over the sorted rows of `SELECT type, name, tbl_name, sql FROM sqlite_master
WHERE name NOT LIKE 'sqlite_%'` plus the sorted `schema_migrations` versions. It must equal the fingerprint of a second
empty database built independently by calling the release entry points as `tools/deployment.mjs` does
(`PersistentSchedules.apply_and_verify!(DateTime.utc_now())`, then `FamilyChat.apply_and_verify!()`), and the version
set
must equal the version prefixes of the files in `priv/sqlite_repo/migrations`. A test-only migration, a skipped
migration or extra DDL fails it. The same test asserts that the rows the release seeds (the backup schedule, the Family
Chat room and the retention schedule) are present and that no other schedule exists.

### 5. Where the code goes

| Piece                                                                                                                                                                                                                                                     | Location                                                                                                               | Project               |
| --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- | --------------------- |
| Pure gate `BnestAppWeb.TestingRoutes.mounted?/2` and the conditional route block                                                                                                                                                                          | `lib/bnest_app_web/testing_routes.ex`, `lib/bnest_app_web/router.ex` (the only production-visible change)              | `bnest-app`           |
| Plug, controller, JSON view                                                                                                                                                                                                                               | `test/support/testing_control/*.ex`                                                                                    | `bnest-app`           |
| `BnestApp.TestInstance` (spawn, drop, state, audit), `.Paths`, `.Seed`, `.Fingerprint`                                                                                                                                                                    | `test/support/test_instance*.ex`                                                                                       | `bnest-app`           |
| `BnestApp.FreshDatabaseCase`, `ConnCase` and `IntegrationSupport` hooks, `test_helper.exs` suite audit                                                                                                                                                    | `test/support`, `test/behaviour/support/integration.exs`, `test/test_helper.exs`                                       | `bnest-app`           |
| `config/test.exs`: `:testing_control`, paths from `BNEST_TEST_INSTANCE_ID`, no integration `family_chat_sqlite_path`, backup paths under the paired roots                                                                                                 | `config/test.exs`                                                                                                      | `bnest-app`           |
| Caddy deny and header strip                                                                                                                                                                                                                               | `tools/caddy-config.mjs` and its test                                                                                  | `bnest-app`           |
| Release artifact audit                                                                                                                                                                                                                                    | `tools/release-artifact-audit.mjs`, called from `tools/release.mjs` after `release:build`                              | `bnest-app`           |
| Runner: secret generation, env, `finally` leak audit, legacy-directory sweep                                                                                                                                                                              | `tools/run-e2e.mts` and `tests/support/test-runtime.mts` in both E2E projects; `bnest-app/tools/test-data-cleanup.mjs` | both E2E, `bnest-app` |
| Typed client `testing-control.mts` (Node `fetch`, secret from env), `lifecycle.steps.ts` hook, instance-aware `routedEnvironment()`/`liveEnvironment()`, removal of the `storage-authority` snapshot and `DELETE FROM`, and of file-writing `seedAccount` | `tests/support`, `tests/steps`                                                                                         | both E2E              |

Boundary rules: `test/support` modules keep `use Boundary, top_level?: true, check: [in: false, out: false]` like
`TestRuntimeRoot`. Nothing in `lib/` may reference `BnestApp.TestInstance` or `BnestAppWeb.TestingControl` except the
compile-time-gated router block; a source-scan test fails the build otherwise.

Governance and specification propagation: `test-identities.md`, `runtime-flat-file-data.md` and
`end-to-end-testing.md` get the instance layout, markers, teardown and the testing-header rule through the
[rules](../../../repo-governance/workflows/quality/rules-propagation.md) and
[docs](../../../repo-governance/workflows/quality/docs-propagation.md) propagation workflows; the C4 model
`specs/apps/bnest/app-be/architecture.md` gains the test-only Testing Control component, marked absent from production;
`docs/explanation/README.md` lists this decisions directory. The synthetic identity rules hold: every account is
`test-user-` prefixed, every payload is synthetic, and nothing is read from `data/prod/` or `~/bnest/data/prod/`.

### 6. Tests and specs, in order (spec first, red, green)

1. **Gherkin** (`specs/apps/bnest/app-be/behaviours/test_isolation.feature`, plus directory map and
   `behaviour-coverage.json` updates): each scenario gets its own empty migrated database; the schema equals the release
   schema; teardown leaves nothing; testing endpoints answer 404 without the header, with a wrong header, with a
   forwarded header and from a non-loopback peer; the endpoints are absent from a production build; seeded accounts are
   `test-user-` only; a failed spawn rolls back. Tag each for the layers that can prove it, per the BDD standard.
2. **Bindings** for those scenarios (Elixir ExBdd steps; Playwright steps in `bnest-app-be-e2e`), red.
3. **Unit tests (mandatory), red**: `TestingRoutes.mounted?/2` is false for `:prod` and `:dev` with any flag and true
   only
   for `:test` plus flag; `Paths` derivation and rejection of bad ids; seed validation (every `seed_invalid` code);
   secret comparison fails closed for an unset or short secret; the TypeScript path mirror equals `Paths` output.
4. **Router and plug regression tests, red**: in the test build the routes exist, and each guard failure returns the
   stock
   404 with the database untouched. **Prod-compiled absence:** `tools/release-artifact-audit.mjs` (Node, no BEAM) runs
   on
   the freshly built release and fails if `ebin` holds any `Elixir.BnestApp.TestInstance*`,
   `Elixir.BnestAppWeb.TestingControl*` or `Elixir.BnestApp.Test*` beam, or if `Elixir.BnestAppWeb.Router.beam` contains
   `__bnest_testing` or those module names. It runs in `release:run` right after `release:build` as evidence id
   `artifact-audit`, and its unit test (`tools/release.test.mjs`) uses beam-like fixtures with and without those
   strings.
   The release already compiles `MIX_ENV=prod`, so no extra production compile is added to the quick gates.
5. **Integration tests, red then green**: spawn, migrate, seed and drop; two consecutive tests see disjoint databases;
   the
   base stays data-free; the schema-parity test; the source-scan test; the leak audit fails on a deliberately leaked
   instance; spawn rollback on a forced seed failure; the 20-spawn timing gate.
6. **E2E**: a smoke scenario per project that checks `storageGeneration` after spawn and that the previous scenario's
   account is gone; then the existing suites move onto the new hook.
7. Each step follows the repository TDD rule (RED, GREEN, REFACTOR with evidence) and
   [specification maintenance](../../../repo-governance/development/specification-maintenance.md); changed Gherkin goes
   through the [Gherkin implementation
   review](../../../repo-governance/workflows/quality/gherkin-implementation-review.md).

### 7. Production release impact and deployment

What changes in the production build:

- **Code:** `router.ex` gains a compile-time-elided route block and `testing_routes_enabled?/0` (like
  `dev_routes_enabled?/0`), and `lib/bnest_app_web/testing_routes.ex` adds one pure function. No route, plug,
  controller, module or config key for testing exists in the production beams. `config/prod.exs` and
  `config/runtime.exs` are not touched. `Storage`, `SqliteCoordinator`, `Records` and `FileConfigStore` are not touched.
- **Tooling in the repository, not in the release:** the Caddyfile generator gains the deny block (the only
  runtime-visible change, and it denies a path that already returns 404), and the artifact audit gate.
- **Migrations:** none. No file under `priv/sqlite_repo/migrations` changes, so the `release:migrate` step is a no-op
  for
  this revision and both slots can run against the same database.
- **Check that nothing else changed:** the artifact audit plus a diff review that `lib/` changes only `router.ex` and
  `testing_routes.ex`.

Deployment. [AGENTS.md](../../../AGENTS.md) requires integration by pull request with leak review, so "commit and push
to main" means merging the reviewed PR (no direct push), then deleting the worktree and branch. Then, from the primary
checkout on a clean `origin/main`, baseline [live-service
continuity](../../../repo-governance/development/live-service-continuity.md)
first (12 exact-origin samples, p95 at most 500 ms, no sample above 2 s, a representative routed journey), and:

1. `npm exec -- nx run -p bnest-app -t release:run -- --revision <sha>` (default `--mode compatibility`). The existing
   gates (quick, integration, both E2E quick suites, recovery and load E2E, repository) now run on the new harness; any
   failure stops before promotion with no production effect. Then build, `artifact-audit`, no-op migrate, candidate on
   the idle slot, promotion by graceful Caddy reload (with the new Caddyfile), routed LiveView proof, bounded drain
   (clients reconnect without a manual refresh), and cleanup.
2. A compatibility release boots with `BNEST_FAMILY_CHAT_ENABLED` unset. If the previous release was promoted in
   experience mode, run `npm exec -- nx run -p bnest-app -t release:run -- --revision <same sha> --mode experience`
   after the drain: it re-runs only the experience gate and promotes a flag-on candidate of the same revision. Skip it
   only if production did not have Family Chat enabled before.
3. Verify the routed backend serves `<sha>`, and that `/__bnest_testing/v1/state` returns 404 on the production origin
   with no header and with a made-up header. Stop unused candidates and servers.

Rollback is `deploy:rollback` to the retained previous slot; nothing is stored that the previous release cannot read.

### 8. Task breakdown (dependency order, one `swe-developer` run each)

Compute rule: every Mix compile and every E2E run goes through one HIPPO guard (`ephemeral`, `standard`) and runs one at
a time; Elixir tasks share `_build`, so they never overlap. Only documentation, specification and TypeScript authoring
without a test run can overlap with them.

| #   | Task                                                                                                                                                                                | Project and files                          | Depends on        | Parallel                       |
| --- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------ | ----------------- | ------------------------------ |
| T1  | Gherkin `test_isolation.feature`, map and coverage updates, C4 Testing Control component                                                                                            | `specs/apps/bnest/app-be/**`               | none              | with T2                        |
| T2  | Governance and docs propagation: `test-identities.md`, `runtime-flat-file-data.md`, `end-to-end-testing.md`, `docs/explanation/README.md` map                                       | `repo-governance/**`, `docs/**`            | none              | with T1                        |
| T3  | `TestingRoutes.mounted?/2` + router block + `config/test.exs` flag, unit tests (RED then GREEN)                                                                                     | `bnest-app`                                | T1                | no                             |
| T4  | `TestInstance.Paths`, marker and directory create/drop, `drop!` safety tests                                                                                                        | `bnest-app` `test/support`, `test/unit`    | T3                | no                             |
| T5  | `TestInstance.spawn!` switch protocol, migrate step through release entry points, rollback, source-scan and `Records` replace tests                                                 | `bnest-app`                                | T4                | no                             |
| T6  | Schema-parity fingerprint test and the 20-spawn timing gate                                                                                                                         | `bnest-app` `test/integration`             | T5                | no                             |
| T7  | `TestInstance.Seed` (accounts, family chat, push, records) over production facades                                                                                                  | `bnest-app`                                | T5                | no                             |
| T8  | Testing plug, controller, error codes, guard tests, header-secret tests                                                                                                             | `bnest-app` `test/support/testing_control` | T5, T7            | no                             |
| T9  | Integration adoption: `FreshDatabaseCase`, `ConnCase`, ExBdd hooks, `after_suite` leak audit, drop integration `family_chat_sqlite_path`, fix tests that assumed shared state       | `bnest-app`                                | T6, T7            | no                             |
| T10 | Caddy deny block, `release-artifact-audit.mjs`, wiring in `release.mjs`, Node tests (`release:test`)                                                                                | `bnest-app` `tools`                        | T3                | with T9 (Node tests are light) |
| T11 | Shared TypeScript pieces: `testing-control.mts` client, path mirror and parity test, runner secret and env, `finally` leak audit, legacy-directory sweep in `test-data-cleanup.mjs` | both E2E, `bnest-app/tools`                | T8                | with T10                       |
| T12 | BE E2E adoption: `lifecycle.steps.ts`, seed through the API, delete `storage-authority`, `seedAccount`, `live-sqlite` activation                                                    | `bnest-app-be-e2e`                         | T11               | with T13 authoring only        |
| T13 | FE E2E adoption including rollout candidates' instance env and `test-user-records.ts` replacement                                                                                   | `bnest-app-fe-e2e`                         | T11               | with T12 authoring only        |
| T14 | Full verification: `release:test`, integration, both E2E quick suites, parity, audit, leak checks                                                                                   | all                                        | T9, T10, T12, T13 | no                             |
| T15 | PR with leak review, merge, `release:run` compatibility, experience re-promotion if needed, continuity proof, delete worktree, branch and dev artifacts                             | repository                                 | T14               | no                             |

## Threat notes

- **Assets:** production data, the run secret, the production Caddy route.
- **Entry points created:** four loopback-only test endpoints, present only in `MIX_ENV=test` builds.
- **Threats and mitigations:** an exposed endpoint in production (compile-out, module absence, Node artifact audit and a
  Caddy deny, so several independent layers); a header guess (32 random bytes per run, constant-time compare, closed
  when unset, stock 404); path traversal or touching production (paths derived from validated ids only, marker checks,
  no input paths); deletion of the wrong directory (exact-child checks plus both markers before any removal; the sweeper
  never deletes by prefix or age alone); secret leakage through traces or logs (Node `fetch`, no logging, a per-run
  secret
  that dies with the run); a secondary BEAM writing to the wrong database (environment derived from the instance, and
  the
  base-must-stay-empty audit).

## Consequences

### Positive

- Every integration test and E2E scenario starts from an empty, really migrated SQLite file, so tests cannot depend on
  each other's leftovers, and the ordering workarounds in the E2E suites (`sqliteStorageScenario` exclusions,
  `ensureAtLeast` top-ups, per-title digest accounts) can later be removed.
- Test schemas are the release schemas, proved by a fingerprint test, and Family Chat follows the production
  single-database layout.
- Most per-scenario `mix run -e` BEAM boots are replaced by in-process calls, which lowers CPU use on a 2 vCPU host.
- Production changes are almost only absences, protected by independent compile-time, tooling and proxy layers.

### Negative

- Extra time per test (estimated 80 to 250 ms, gate 500 ms p95) and more fsyncs on a shared host.
- The test server relies on `:sys.replace_state` for the `Records` store and on `Application.put_env` switching. This is
  contained in `test/support` but coupled to `Records` internals, and it needs a quiescence rule because Family Chat,
  Push and Scheduler do not hold the storage lease.
- A new control surface in every test build needs a secret, guards and an audit; a teardown bug can leak directories
  (mitigated by the leak audit and the sweeper).
- The production Caddyfile and `router.ex` change, so the release needs the full gate run and, when applicable, an
  experience re-promotion.
- FE rollout scenarios with several BEAMs need the harness to pass the instance environment correctly; mistakes show up
  as the base-must-stay-empty audit failing.

### Neutral

- The `unit` layer keeps its in-memory doubles; only database-touching integration and E2E tests change.
- Read-only inspections through `mix run -e` remain for now.
- Governance documents and the C4 model need propagation updates in the same change.
