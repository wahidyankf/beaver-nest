# Technical Design

## Entry State and Invariants

Execution starts only after the SQLite plan is Done. Its final database must be `sqlite_primary`, `PRAGMA quick_check` must pass, an isolated backup must restore through normal repository reads, and every allow-listed source must have accepted migration evidence. The active Caddy route and previous rollback-eligible artifact must both support SQLite without requiring flat files.

No time-based waiting period is added. Safety depends on evidence and artifact compatibility, not elapsed days.

## Decisions

1. Add a committed headless Nx target `bnest-app:storage:retire-flat-files` backed by `Mix.Tasks.Bnest.Storage.RetireFlatFiles`; UI never supplies deletion paths.
2. Generate one private `flat-files-v1-retirement-v1` manifest under the configured SQLite directory. It records source-relative path, source checksum, migrated target identity/checksum, and retirement outcome without entering Git or logs.
3. Deploy SQLite-only reads and writes before deletion. The prior eligible rollback artifact must also honor `sqlite_primary`; any flat-only listener or eligible artifact blocks retirement.
4. Delete files individually with exact containment, lstat/symlink rejection, checksum recheck, and receipt update. Never call recursive deletion on a runtime root.
5. Remove a directory only when it is an exact known legacy directory and empty after proven file deletion. Preserve roots and placeholders.
6. Do not implement a down migration that recreates deleted flat files. Recovery restores SQLite from its verified backup and rolls the application only to an SQLite-capable artifact.

## Retirement Manifest

Private pointer: `<database-directory>/retirement/flat-files-v1-retirement-v1.json`, mode `0600`, parent mode `0700`.

```json
{
  "schemaVersion": 1,
  "retirementId": "flat-files-v1-retirement-v1",
  "migrationId": "flat-files-v1-to-sqlite-v1",
  "databaseSchemaVersion": 1,
  "state": "eligible",
  "items": [
    {
      "sourceRelativePath": "users/<user-id>/chat/current.json",
      "sourceSha256": "<sha256>",
      "targetRecordType": "chat",
      "targetRecordKeyDigest": "<sha256>",
      "targetSha256": "<sha256>",
      "outcome": "pending",
      "deletedAt": null
    }
  ]
}
```

Allowed states are `inventory`, `blocked`, `eligible`, `deleting`, `verified`, and `failed`. Item outcomes are `pending`, `deleted`, `changed`, `unproven`, `missing-without-receipt`, and `failed`. Concrete record keys remain private; committed examples use placeholders or digests.

The manifest fingerprint is SHA-256 over ordered migration item identity, source checksum, target checksum, and relative path. On retry, `deleted` plus a missing exact source is accepted; missing without a prior deletion receipt blocks completion. A present file always gets lstat, containment, and checksum proof again.

## Exact Source Inventory

The retirement adapter compiles only these templates; the current `DataRepository.Store` identity validators generate each placeholder:

```text
system/bootstrap.json
system/accounts/<user-id>.json
system/usernames/<username>.json
system/sessions/<digest>.json
system/manifests/<import-id>.json
system/schema-registry.json
users/<user-id>/imports/<import-id>.json
users/<user-id>/chat/current.json
users/<user-id>/sifat-allah/progress.json
users/<user-id>/preferences/theme.json
apps/beaver-nest/legacy/<import-id>/source.bin
users/<user-id>/legacy/<import-id>/source.bin
```

JSON sources must map to a validated `bnest_records` row with equal payload checksum and normal read-back. Binary sources must map to `bnest_recovery_sources` with equal BLOB checksum and byte size. Unknown siblings are reported structurally and left unchanged; their presence prevents claiming the whole runtime root is retired but never authorizes deletion.

## Sequence

1. **Reconcile:** acquire the host migration lock, freeze flat mirror writes briefly, inventory sources, join every source to SQLite evidence, create a fresh SQLite backup, restore it in an isolated marked destination, and fail closed on any mismatch.
2. **Contract code:** remove flat-primary/fallback/mirror branches and obsolete runtime-root requirements, keep exact retirement reader only, and produce an SQLite-only candidate.
3. **Promote:** prove candidate revision/readiness and synthetic SQLite flows, promote via Caddy, prove routed LiveView/WebSocket reconnect, drain five minutes, and retire the prior process. Both retained artifacts must remain SQLite-capable.
4. **Delete:** reacquire the lock, recheck active/previous compatibility and every source checksum, delete one exact file at a time, sync its parent, then atomically record the receipt. Stop on the first unsafe item.
5. **Verify:** assert every manifest item is `deleted`, no allow-listed file remains, unknown siblings are unchanged, no app journey recreates a flat file, SQLite integrity/restore/restart/routed flows pass, and only then mark `verified`.

## Failure and Recovery

- Before deletion: roll the application route back to the last healthy SQLite-capable artifact; sources remain intact.
- During partial deletion: keep SQLite authoritative, preserve receipts and database backup, block flat-only rollback, diagnose, and retry only exact remaining items.
- Changed or unproven source: preserve it and all unrelated files; return to migration reconciliation rather than forcing deletion.
- SQLite or routed failure after deletion: restore SQLite into a new verified destination and promote an SQLite-capable artifact. Never recreate flat files from stale sources.
- Cleanup removes only marked restore databases, temporary candidates, and proven-empty legacy subdirectories; it retains the active database, backup, migration evidence, and retirement receipts.

## Active-Service Continuity

The plan follows the Caddy workflow: baseline current local/routed health, prepare an independent candidate, require revision-specific readiness, promote with graceful reload, prove local Caddy and Tailnet HTTPS, verify connected LiveView/WebSocket reconnect without refresh, drain, retire, and clean up. Deletion cannot start while any running or rollback-eligible artifact requires flat data.

## Specification Changes

All outcomes become durable because they change architecture, storage ownership, authorization, deletion behavior, or recovery.

### [E] `specs/apps/bnest/app/architecture.md`

```diff
- Flat files remain a compatibility source/mirror during SQLite rollback.
+ SQLite and its verified backup are the only Bnest application data stores.
+ Retirement coordinator owns exact evidence-driven legacy deletion.
```

- = Preserve Caddy routing, auth/roles, ownership, Codex, and resumable LiveView state.
- ✓ Proof: architecture map gate, SQLite-only restart, routed revision, and reconnect.

### [E] `specs/apps/bnest/app/behaviours/sqlite_storage.feature`

```diff
+ Retirement waits for complete SQLite proof.
+ Unproven or changed source is preserved.
+ Proven legacy sources are deleted exactly once.
+ Bnest remains usable and recreates no flat file.
+ Only an admin can view storage retirement status.
```

- → Bindings: existing SQLite storage unit/integration/E2E step and support files.
- ✓ Proof: behavior coverage, focused exact-origin E2E, and runtime deletion tests.

### [E] `specs/apps/bnest/app/behaviours/centralized_data.feature`

```diff
- Future records use the active repository backend with flat compatibility.
+ Future records use SQLite only after verified retirement.
```

- = Preserve all browser import, stale-write, cleanup, and Codex-resume scenarios.
- ✓ Proof: behavior coverage and post-deletion import continuation journey.

## File Impact

```text
apps/bnest-app/
├── [E] README.md
├── [E] project.json
├── config/
│   ├── [E] config.exs
│   ├── [E] runtime.exs
│   └── [E] test.exs
├── lib/bnest_app/
│   ├── [E] application.ex
│   ├── [E] data_repository.ex
│   ├── [E] identity/bootstrap.ex
│   ├── [E] identity/file_store.ex
│   ├── data_repository/
│   │   ├── [E] backup.ex
│   │   ├── [E] store.ex
│   │   └── [E] storage_coordinator.ex
│   └── storage/
│       └── [N] flat_file_retirement.ex
├── lib/bnest_app_web/
│   ├── [E] router.ex
│   ├── [E] user_auth.ex
│   └── live/
│       └── [E] storage_live.ex
├── lib/mix/tasks/
│   └── [N] bnest.storage.retire_flat_files.ex
└── tools/
    ├── [E] deployment.mjs
    ├── [E] release.mjs
    └── [E] release.test.mjs
```

```text
apps/bnest-app/test/behaviour/steps/sqlite_storage_steps.exs          [E]
apps/bnest-app/test/behaviour/support/integration.exs                 [E]
apps/bnest-app/test/behaviour/support/unit.exs                        [E]
apps/bnest-app/test/integration/bnest_app/data_repository_test.exs   [E]
apps/bnest-app/test/integration/bnest_app/sqlite_storage_test.exs    [E]
apps/bnest-app/test/integration/bnest_app/flat_file_retirement_test.exs [N]
apps/bnest-app/test/unit/bnest_app/storage_migration_test.exs        [E]
apps/bnest-app/test/unit/bnest_app/flat_file_retirement_test.exs     [N]
apps/bnest-app-e2e/README.md                                         [E]
apps/bnest-app-e2e/tests/steps/sqlite_storage.steps.ts                [E]
apps/bnest-app-e2e/tests/support/sqlite-storage.ts                    [E]
specs/apps/bnest/app/architecture.md                                 [E]
specs/apps/bnest/app/behaviours/centralized_data.feature             [E]
specs/apps/bnest/app/behaviours/sqlite_storage.feature               [E]
README.md                                                             [E]
```

```text
<legacy-runtime-root>/system/bootstrap.json                              [D]
<legacy-runtime-root>/system/accounts/<user-id>.json                    [D]
<legacy-runtime-root>/system/usernames/<username>.json                  [D]
<legacy-runtime-root>/system/sessions/<digest>.json                     [D]
<legacy-runtime-root>/system/manifests/<import-id>.json                 [D]
<legacy-runtime-root>/system/schema-registry.json                       [D]
<legacy-runtime-root>/users/<user-id>/imports/<import-id>.json          [D]
<legacy-runtime-root>/users/<user-id>/chat/current.json                 [D]
<legacy-runtime-root>/users/<user-id>/sifat-allah/progress.json         [D]
<legacy-runtime-root>/users/<user-id>/preferences/theme.json            [D]
<legacy-runtime-root>/apps/beaver-nest/legacy/<import-id>/source.bin    [D]
<legacy-runtime-root>/users/<user-id>/legacy/<import-id>/source.bin     [D]
```

Each `[D]` template is instantiated only by validated IDs from the verified retirement manifest. `<database-directory>/retirement/flat-files-v1-retirement-v1.json` is `[N]` private runtime evidence. The shared legacy root, unknown siblings, database, WAL/SHM, backup, migration evidence, and placeholders are unchanged.
