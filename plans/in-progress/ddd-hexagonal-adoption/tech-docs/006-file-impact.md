# 006: File Impact

Paths are relative to the repository root. `[E]` edited, `[N]` new, `[M]` moved (module renamed with its file), `[D]`
deleted. Execution will discover paths this list could not predict, such as a helper split out of a module during
GREEN. Each one is added here in the same unit that touches it, and recorded in `learnings.md`.

## U1: Plan

- [N] `plans/in-progress/ddd-hexagonal-adoption/README.md`, `brd.md`, `prd.md`, `delivery.md`, `learnings.md`
- [N] `plans/in-progress/ddd-hexagonal-adoption/tech-docs/README.md` and the `001`–`007` companions
- [E] `plans/in-progress/README.md`

## U2: Architecture Standard and Propagation

- [N] `repo-governance/development/quality/code/hexagonal-architecture.md`
- [N] `repo-governance/development/quality/code/hexagonal-architecture/README.md`
- [N] `repo-governance/development/quality/code/hexagonal-architecture/001-domain-driven-design.md`
- [N] `repo-governance/development/quality/code/hexagonal-architecture/002-layers-and-the-dependency-rule.md`
- [N] `repo-governance/development/quality/code/hexagonal-architecture/003-application-shapes.md`
- [N] `repo-governance/development/quality/code/hexagonal-architecture/004-test-doubles.md`
- [E] `repo-governance/development/quality/code/README.md`
- [E] `repo-governance/development/quality/stacks/elixir-standards.md`
- [E] `repo-governance/development/quality/stacks/phoenix-liveview-standards.md`
- [E] `repo-governance/development/quality/stacks/typescript-standards.md`
- [E] `repo-governance/development/quality/stacks/repository-adapter.md`
- [E] `repo-governance/development/software-quality-enforcement.md`
- [E] `.agents/skills/developing-applications/SKILL.md`
- [E] `.agents/skills/programming-elixir/SKILL.md`
- [E] `.agents/skills/framework-phoenix-liveview/SKILL.md`
- [E] `.agents/agents/swe-code-maker.md`
- [E] `.agents/agents/swe-code-checker.md`
- [E] `.agents/agents/swe-code-fixer.md`
- [E] `AGENTS.md`
- [N] `docs/explanation/hexagonal-architecture.md`
- [E] `docs/explanation/README.md`
- [E] `docs/reference/glossary.md`
- [E] `docs/reference/software-development.md`
- [E] `.claude/agents/catalog.json`, `.claude/agents/provenance.json`, `.claude/skills/catalog.json`,
  `.claude/skills/provenance.json`, `.codex/agents/catalog.json`, `.codex/agents/provenance.json`,
  `.opencode/agents/catalog.json`, `.opencode/agents/provenance.json`, and the generated `.claude/`, `.codex/` and
  `.opencode/` adapters of the three `swe-code-*` agents and three edited skills, as `./rhino harness adapters generate`
  rewrites them

## U3: Tooling

- [E] `apps/bnest-app/mix.exs` (dependency, compiler, `boundary` defaults, coverage pattern)
- [E] `apps/bnest-app/mix.lock`
- [E] `apps/bnest-app/lib/bnest_app.ex` (root boundary, `@legacy_exports`)
- [E] `apps/bnest-app/lib/bnest_app/sqlite_repo.ex`
- [E] `apps/bnest-app/lib/bnest_app/application.ex`
- [N] `apps/bnest-app/lib/bnest_app/release.ex` (the `BnestApp.Release` top-level boundary declaration)
- [E] `apps/bnest-app/lib/bnest_app_web.ex`
- [N] `apps/bnest-app/lib/bnest_app_cli.ex`
- [E] `apps/bnest-app/lib/mix/tasks/bnest.identity.benchmark.ex`, `bnest.schema.audit.ex`, `bnest.storage.migrate.ex`,
  `bnest.storage.purge_test_data.ex`, `bnest.storage.relocate.ex`, `bnest.storage.retire.ex` (`classify_to: BnestAppCli`)
- [N] `apps/bnest-app/test/behaviour/behaviour.ex` (the ignored `BnestApp.Behaviour` boundary)
- [E] `apps/bnest-app/test/support/test_runtime_root.ex`, `test_identity.ex`, `schema_source_scan.ex`,
  `test_backup_destination.ex`, `codex_fixture_models.ex`, `conn_case.ex` (boundary classification only; U4, U5, U8
  and U12 edit some of them again for module renames, as listed under their units)
- [E] `apps/bnest-app/test/integration/support/codex_fixture_session.ex`
- [E] `apps/bnest-app/test/behaviour/verify.exs` (unit patterns for `SqliteRepo` and non-in-memory adapters, plus the
  shrinking allow-list)
- [N] `apps/bnest-app/test/integration/architecture/hexagonal_layering_test.exs`
- [N] `apps/bnest-app/test/integration/support/architecture_scan.ex` (the AST walker the layering test uses)

## U4–U13: Bounded Contexts, `lib/`

Generated from the module destinations in [002](002-target-architecture-and-context-map.md). Every `[N]` entry ending
in `/domain.ex`, `/ports.ex` or `/adapters.ex` is a one-line boundary declaration module: `domain.ex` and `ports.ex` declare strict sub-boundaries, and `adapters.ex` declares the strict top-level adapters boundary.

### U4: Storage

- [M] `apps/bnest-app/lib/bnest_app/data_repository.ex` → `apps/bnest-app/lib/bnest_app/storage/records.ex`
- [M] `apps/bnest-app/lib/bnest_app/data_repository/storage_coordinator.ex` → `apps/bnest-app/lib/bnest_app/storage/adapters/sqlite_coordinator.ex`
- [M] `apps/bnest-app/lib/bnest_app/data_repository/import.ex` → `apps/bnest-app/lib/bnest_app/storage/import.ex`
- [M] `apps/bnest-app/lib/bnest_app/data_repository/recovery_source.ex` → `apps/bnest-app/lib/bnest_app/storage/recovery_source.ex`
- [M] `apps/bnest-app/lib/bnest_app/data_repository/schema.ex` → `apps/bnest-app/lib/bnest_app/storage/domain/record_schema.ex`
- [M] `apps/bnest-app/lib/bnest_app/data_repository/normalizer.ex` → `apps/bnest-app/lib/bnest_app/storage/domain/normalizer.ex`
- [M] `apps/bnest-app/lib/bnest_app/data_repository/canonical_json.ex` → `apps/bnest-app/lib/bnest_app/storage/domain/canonical_json.ex`
- [M] `apps/bnest-app/lib/bnest_app/data_repository/manifest.ex` → `apps/bnest-app/lib/bnest_app/storage/domain/manifest.ex`
- [M] `apps/bnest-app/lib/bnest_app/storage/record_map.ex` → `apps/bnest-app/lib/bnest_app/storage/domain/record_map.ex`
- [M] `apps/bnest-app/lib/bnest_app/storage/location.ex` → `apps/bnest-app/lib/bnest_app/storage/domain/location.ex`
- [M] `apps/bnest-app/lib/bnest_app/data_repository/backend.ex` → `apps/bnest-app/lib/bnest_app/storage/ports/record_backend.ex`
- [M] `apps/bnest-app/lib/bnest_app/data_repository/store.ex` → `apps/bnest-app/lib/bnest_app/storage/adapters/file_record_backend.ex`
- [M] `apps/bnest-app/lib/bnest_app/data_repository/sqlite_store.ex` → `apps/bnest-app/lib/bnest_app/storage/adapters/sqlite_record_backend.ex`
- [M] `apps/bnest-app/lib/bnest_app/data_repository/backup.ex` → `apps/bnest-app/lib/bnest_app/storage/adapters/file_record_export.ex`
- [M] `apps/bnest-app/lib/bnest_app/storage/config.ex` → `apps/bnest-app/lib/bnest_app/storage/adapters/file_config_store.ex`
- [M] `apps/bnest-app/lib/bnest_app/storage/lock.ex` → `apps/bnest-app/lib/bnest_app/storage/adapters/file_lock.ex`
- [M] `apps/bnest-app/lib/bnest_app/storage/migration.ex` → `apps/bnest-app/lib/bnest_app/storage/adapters/sqlite_migration.ex`
- [M] `apps/bnest-app/lib/bnest_app/storage/relocation.ex` → `apps/bnest-app/lib/bnest_app/storage/adapters/sqlite_relocation.ex`
- [M] `apps/bnest-app/lib/bnest_app/storage/retirement.ex` → `apps/bnest-app/lib/bnest_app/storage/adapters/flat_retirement.ex`
- [M] `apps/bnest-app/lib/bnest_app/storage/test_data_cleanup.ex` → `apps/bnest-app/lib/bnest_app/storage/adapters/test_data_cleanup.ex`
- [N] `apps/bnest-app/lib/bnest_app/storage.ex`
- [N] `apps/bnest-app/lib/bnest_app/storage/domain.ex`
- [N] `apps/bnest-app/lib/bnest_app/storage/ports.ex`
- [N] `apps/bnest-app/lib/bnest_app/storage/adapters.ex`
- [N] `apps/bnest-app/lib/bnest_app/storage/ports/record_kind.ex`
- [N] `apps/bnest-app/lib/bnest_app/storage/ports/config_store.ex`
- [N] `apps/bnest-app/lib/bnest_app/storage/ports/lock.ex`
- [N] `apps/bnest-app/lib/bnest_app/storage/ports/maintenance.ex`
- [N] `apps/bnest-app/lib/bnest_app/storage/ports/database_lifecycle.ex`
- [E] callers of the renamed Storage modules, which move to the `Storage` facade or `Storage.Records`:
  `apps/bnest-app/lib/bnest_app.ex`, `lib/bnest_app/application.ex`, `lib/bnest_app/sqlite_repo.ex`,
  `lib/bnest_app/identity.ex`, `lib/bnest_app/identity/bootstrap.ex`, `lib/bnest_app/identity/file_store.ex`,
  `lib/bnest_app/family_chat/store.ex`, `lib/bnest_app/backup.ex`, `lib/bnest_app/backup/location.ex`,
  `lib/bnest_app/admin_config/registry.ex`, `lib/bnest_app/deployment.ex`,
  `lib/bnest_app/release/migrations/family_chat.ex`, `lib/bnest_app/release/migrations/persistent_schedules.ex`,
  `lib/bnest_app_web/user_auth.ex`, `lib/bnest_app_web/controllers/theme_controller.ex`,
  `lib/bnest_app_web/controllers/health_controller.ex`, `lib/bnest_app_web/live/chat_live.ex`,
  `lib/bnest_app_web/live/sifat_allah_live.ex` (all under `apps/bnest-app/`)
- [N] `apps/bnest-app/lib/bnest_app/codex_chat/adapters/transcript_record_kind.ex`
- [N] `apps/bnest-app/lib/bnest_app/sifat_allah/adapters/progress_record_kind.ex`

### U5: Identity

- [E] `apps/bnest-app/lib/bnest_app/identity.ex`
- [E] `apps/bnest-app/lib/bnest_app/identity/login.ex`
- [E] `apps/bnest-app/lib/bnest_app/identity/bootstrap.ex`
- [M] `apps/bnest-app/lib/bnest_app/identity/session.ex` → `apps/bnest-app/lib/bnest_app/identity/sessions.ex`
- [M] `apps/bnest-app/lib/bnest_app/identity/authorization.ex` → `apps/bnest-app/lib/bnest_app/identity/domain/authorization.ex`
- [M] `apps/bnest-app/lib/bnest_app/identity/file_store.ex` → `apps/bnest-app/lib/bnest_app/identity/adapters/record_identity_store.ex`
- [M] `apps/bnest-app/lib/bnest_app/identity/credential_verifier.ex` → `apps/bnest-app/lib/bnest_app/identity/adapters/argon2_credential_hasher.ex`
- [N] `apps/bnest-app/lib/bnest_app/identity/domain.ex`
- [N] `apps/bnest-app/lib/bnest_app/identity/ports.ex`
- [N] `apps/bnest-app/lib/bnest_app/identity/adapters.ex`
- [N] `apps/bnest-app/lib/bnest_app/identity/domain/session.ex`
- [N] `apps/bnest-app/lib/bnest_app/identity/ports/identity_store.ex`
- [N] `apps/bnest-app/lib/bnest_app/identity/ports/credential_hasher.ex`
- [N] `apps/bnest-app/lib/bnest_app/identity/ports/session_notifier.ex`
- [N] `apps/bnest-app/lib/bnest_app/identity/adapters/endpoint_session_notifier.ex`
- [N] `apps/bnest-app/lib/bnest_app/identity/ports/subscription_revoker.ex`
- [N] `apps/bnest-app/lib/bnest_app/identity/adapters/push_subscription_revoker.ex`

### U6: Preferences

- [N] `apps/bnest-app/lib/bnest_app/preferences.ex`
- [N] `apps/bnest-app/lib/bnest_app/preferences/domain.ex`
- [N] `apps/bnest-app/lib/bnest_app/preferences/ports.ex`
- [N] `apps/bnest-app/lib/bnest_app/preferences/adapters.ex`
- [N] `apps/bnest-app/lib/bnest_app/preferences/domain/theme.ex`
- [N] `apps/bnest-app/lib/bnest_app/preferences/ports/preference_store.ex`
- [N] `apps/bnest-app/lib/bnest_app/preferences/adapters/record_preference_store.ex`

### U7: SifatAllah

- [M] `apps/bnest-app/lib/bnest_app/sifat_allah.ex` → `apps/bnest-app/lib/bnest_app/sifat_allah/domain/quiz.ex`
- [N] `apps/bnest-app/lib/bnest_app/sifat_allah.ex`
- [N] `apps/bnest-app/lib/bnest_app/sifat_allah/domain.ex`
- [N] `apps/bnest-app/lib/bnest_app/sifat_allah/ports.ex`
- [N] `apps/bnest-app/lib/bnest_app/sifat_allah/adapters.ex`
- [N] `apps/bnest-app/lib/bnest_app/sifat_allah/ports/progress_store.ex`
- [N] `apps/bnest-app/lib/bnest_app/sifat_allah/adapters/record_progress_store.ex`

### U8: CodexChat

- [M] `apps/bnest-app/lib/bnest_app/chat.ex` → `apps/bnest-app/lib/bnest_app/codex_chat/domain/transcript.ex`
- [M] `apps/bnest-app/lib/bnest_app/codex/settings.ex` → `apps/bnest-app/lib/bnest_app/codex_chat/domain/settings.ex`
- [M] `apps/bnest-app/lib/bnest_app/codex/model_access.ex` → `apps/bnest-app/lib/bnest_app/codex_chat/domain/model_access.ex`
- [M] `apps/bnest-app/lib/bnest_app/codex/repository_access.ex` → `apps/bnest-app/lib/bnest_app/codex_chat/domain/repository_access.ex`
- [M] `apps/bnest-app/lib/bnest_app/codex/session.ex` → `apps/bnest-app/lib/bnest_app/codex_chat/ports/agent_session.ex`
- [M] `apps/bnest-app/lib/bnest_app/codex/model_discovery.ex` → `apps/bnest-app/lib/bnest_app/codex_chat/ports/model_discovery.ex`
- [M] `apps/bnest-app/lib/bnest_app/codex/port_session.ex` → `apps/bnest-app/lib/bnest_app/codex_chat/adapters/codex_port_session.ex`
- [M] `apps/bnest-app/lib/bnest_app/codex/model_catalog.ex` → `apps/bnest-app/lib/bnest_app/codex_chat/model_catalog.ex`
- [N] `apps/bnest-app/lib/bnest_app/codex_chat.ex`
- [N] `apps/bnest-app/lib/bnest_app/codex_chat/domain.ex`
- [N] `apps/bnest-app/lib/bnest_app/codex_chat/ports.ex`
- [N] `apps/bnest-app/lib/bnest_app/codex_chat/adapters.ex`
- [N] `apps/bnest-app/lib/bnest_app/codex_chat/adapters/codex_cli_model_discovery.ex`
- [N] `apps/bnest-app/lib/bnest_app/codex_chat/ports/transcript_store.ex`
- [N] `apps/bnest-app/lib/bnest_app/codex_chat/adapters/record_transcript_store.ex`
- [E] `apps/bnest-app/lib/bnest_app/application.ex` (`CodexChat.child_specs/0`)

### U9: FamilyChat

- [E] `apps/bnest-app/lib/bnest_app/family_chat.ex`
- [E] `apps/bnest-app/lib/bnest_app/release/migrations/family_chat.ex`
- [M] `apps/bnest-app/lib/bnest_app/family_chat/message.ex` → `apps/bnest-app/lib/bnest_app/family_chat/domain/message.ex`
- [M] `apps/bnest-app/lib/bnest_app/family_chat/store.ex` → `apps/bnest-app/lib/bnest_app/family_chat/adapters/sqlite_room_store.ex`
- [N] `apps/bnest-app/lib/bnest_app/family_chat/domain.ex`
- [N] `apps/bnest-app/lib/bnest_app/family_chat/ports.ex`
- [N] `apps/bnest-app/lib/bnest_app/family_chat/adapters.ex`
- [N] `apps/bnest-app/lib/bnest_app/family_chat/domain/policy.ex`
- [N] `apps/bnest-app/lib/bnest_app/family_chat/domain/cursor.ex`
- [N] `apps/bnest-app/lib/bnest_app/family_chat/ports/room_store.ex`
- [N] `apps/bnest-app/lib/bnest_app/family_chat/ports/message_publisher.ex`
- [N] `apps/bnest-app/lib/bnest_app/family_chat/adapters/absinthe_message_publisher.ex`
- [E] `apps/bnest-app/lib/bnest_app/push_notifications.ex`, `apps/bnest-app/lib/bnest_app/push_notifications/dispatcher.ex`,
  `apps/bnest-app/lib/bnest_app/backup.ex` (`FamilyChat.Store` calls become FamilyChat facade calls)

### U10: PushNotifications

- [E] `apps/bnest-app/lib/bnest_app/push_notifications.ex`
- [E] `apps/bnest-app/lib/bnest_app/push_notifications/dispatcher.ex`
- [M] `apps/bnest-app/lib/bnest_app/push_notifications/policy.ex` → `apps/bnest-app/lib/bnest_app/push_notifications/domain/policy.ex`
- [M] `apps/bnest-app/lib/bnest_app/push_notifications/sender.ex` → `apps/bnest-app/lib/bnest_app/push_notifications/adapters/web_push_sender.ex`
- [M] `apps/bnest-app/lib/bnest_app/push_notifications/retention_job.ex` → `apps/bnest-app/lib/bnest_app/push_notifications/adapters/retention_task.ex`
- [N] `apps/bnest-app/lib/bnest_app/push_notifications/domain.ex`
- [N] `apps/bnest-app/lib/bnest_app/push_notifications/ports.ex`
- [N] `apps/bnest-app/lib/bnest_app/push_notifications/adapters.ex`
- [N] `apps/bnest-app/lib/bnest_app/push_notifications/ports/push_sender.ex`
- [N] `apps/bnest-app/lib/bnest_app/push_notifications/ports/subscription_store.ex`
- [N] `apps/bnest-app/lib/bnest_app/push_notifications/ports/delivery_store.ex`
- [N] `apps/bnest-app/lib/bnest_app/push_notifications/adapters/recording_push_sender.ex`
- [N] `apps/bnest-app/lib/bnest_app/push_notifications/adapters/sqlite_subscription_store.ex`
- [N] `apps/bnest-app/lib/bnest_app/push_notifications/adapters/sqlite_delivery_store.ex`
- [E] `apps/bnest-app/lib/bnest_app/identity/adapters.ex` (`BnestApp` dep becomes `BnestApp.PushNotifications`)
- [E] `apps/bnest-app/lib/bnest_app/scheduler/registry.ex`, `apps/bnest-app/lib/bnest_app/release/migrations/family_chat.ex`
  (the `RetentionJob` handler atom becomes `Adapters.RetentionTask`)

### U11: Scheduler

- [E] `apps/bnest-app/lib/bnest_app/scheduler.ex`
- [E] `apps/bnest-app/lib/bnest_app/scheduler/run.ex`
- [E] `apps/bnest-app/lib/bnest_app/release/migrations/persistent_schedules.ex`
- [M] `apps/bnest-app/lib/bnest_app/scheduler/policy.ex` → `apps/bnest-app/lib/bnest_app/scheduler/domain/policy.ex`
- [M] `apps/bnest-app/lib/bnest_app/scheduler/store.ex` → `apps/bnest-app/lib/bnest_app/scheduler/adapters/sqlite_schedule_store.ex`
- [M] `apps/bnest-app/lib/bnest_app/scheduler/registry.ex` → `apps/bnest-app/lib/bnest_app/scheduler/task_registry.ex`
- [N] `apps/bnest-app/lib/bnest_app/scheduler/domain.ex`
- [N] `apps/bnest-app/lib/bnest_app/scheduler/ports.ex`
- [N] `apps/bnest-app/lib/bnest_app/scheduler/adapters.ex`
- [N] `apps/bnest-app/lib/bnest_app/scheduler/ports/schedule_store.ex`
- [N] `apps/bnest-app/lib/bnest_app/scheduler/ports/task.ex`
- [E] `apps/bnest-app/lib/bnest_app/push_notifications/adapters/retention_task.ex` (`@behaviour` of `Ports.Task`)
- [E] `apps/bnest-app/lib/bnest_app/backup/run.ex`, `apps/bnest-app/lib/bnest_app/release/migrations/family_chat.ex`
  (`Scheduler.Store` and `Registry` calls become Scheduler facade calls)

### U12: Backup

- [E] `apps/bnest-app/lib/bnest_app/backup.ex`
- [M] `apps/bnest-app/lib/bnest_app/backup/receipt.ex` → `apps/bnest-app/lib/bnest_app/backup/domain/receipt.ex`
- [M] `apps/bnest-app/lib/bnest_app/backup/capacity.ex` → `apps/bnest-app/lib/bnest_app/backup/adapters/df_capacity_probe.ex`
- [M] `apps/bnest-app/lib/bnest_app/backup/location.ex` → `apps/bnest-app/lib/bnest_app/backup/domain/location.ex`
- [M] `apps/bnest-app/lib/bnest_app/backup/config.ex` → `apps/bnest-app/lib/bnest_app/backup/adapters/file_config_store.ex`
- [M] `apps/bnest-app/lib/bnest_app/backup/run.ex` → `apps/bnest-app/lib/bnest_app/backup/adapters/scheduled_backup_task.ex`
- [N] `apps/bnest-app/lib/bnest_app/backup/domain.ex`
- [N] `apps/bnest-app/lib/bnest_app/backup/ports.ex`
- [N] `apps/bnest-app/lib/bnest_app/backup/adapters.ex`
- [N] `apps/bnest-app/lib/bnest_app/backup/domain/retention.ex`
- [N] `apps/bnest-app/lib/bnest_app/backup/domain/capacity_policy.ex`
- [N] `apps/bnest-app/lib/bnest_app/backup/ports/capacity_probe.ex`
- [N] `apps/bnest-app/lib/bnest_app/backup/ports/ignore_check.ex`
- [N] `apps/bnest-app/lib/bnest_app/backup/ports/config_store.ex`
- [N] `apps/bnest-app/lib/bnest_app/backup/ports/artifact_store.ex`
- [N] `apps/bnest-app/lib/bnest_app/backup/ports/database_snapshot.ex`
- [N] `apps/bnest-app/lib/bnest_app/backup/adapters/git_ignore_check.ex`
- [N] `apps/bnest-app/lib/bnest_app/backup/adapters/file_artifact_store.ex`
- [N] `apps/bnest-app/lib/bnest_app/backup/adapters/sqlite_database_snapshot.ex`
- [E] `apps/bnest-app/lib/bnest_app/admin_config/registry.ex` (panel owner atom)

### U13: Operations

- [M] `apps/bnest-app/lib/bnest_app/deployment.ex` → `apps/bnest-app/lib/bnest_app/operations/adapters/system_release_environment.ex`
- [M] `apps/bnest-app/lib/bnest_app/admin_config/registry.ex` → `apps/bnest-app/lib/bnest_app/operations/domain/admin_panels.ex`
- [N] `apps/bnest-app/lib/bnest_app/operations.ex`
- [N] `apps/bnest-app/lib/bnest_app/operations/domain.ex`
- [N] `apps/bnest-app/lib/bnest_app/operations/ports.ex`
- [N] `apps/bnest-app/lib/bnest_app/operations/adapters.ex`
- [N] `apps/bnest-app/lib/bnest_app/operations/ports/release_environment.ex`

## U4–U13: Inbound Adapters and Configuration

| Unit | Paths (under `apps/bnest-app/`) |
| --- | --- |
| U4 Storage | [E] `lib/bnest_app_web/live/storage_live.ex`, `lib/bnest_app_web/live/data_migration_live.ex`, the five storage and schema Mix tasks under `lib/mix/tasks/`, `config/config.exs`, `config/test.exs` |
| U5 Identity | [E] `lib/bnest_app_web/user_auth.ex`, `lib/bnest_app_web/controllers/session_controller.ex`, `lib/bnest_app_web/controllers/bootstrap_controller.ex`, `lib/bnest_app_web/live/login_live.ex`, `lib/mix/tasks/bnest.identity.benchmark.ex`, `config/config.exs`, `config/test.exs` |
| U6 Preferences | [E] `lib/bnest_app_web/controllers/theme_controller.ex`, `lib/bnest_app_web/user_auth.ex`, `config/config.exs`, `config/test.exs` |
| U7 SifatAllah | [E] `lib/bnest_app_web/live/sifat_allah_live.ex`, `config/config.exs`, `config/test.exs` |
| U8 CodexChat | [E] `lib/bnest_app_web/live/chat_live.ex`, `config/config.exs`, `config/test.exs` (`config/runtime.exs` keeps the frozen `:codex` `working_directory` key) |
| U9 FamilyChat | [E] `lib/bnest_app_web/controllers/family_chat_controller.ex`, `lib/bnest_app_web/user_socket.ex`, `lib/bnest_app_web/resolvers/family_chat_resolver.ex`, `lib/bnest_app_web/schema/types/family_chat_types.ex`, `config/config.exs`, `config/test.exs` |
| U10 PushNotifications | [E] `lib/bnest_app_web/resolvers/web_push_resolver.ex`, `config/config.exs`, `config/test.exs` |
| U11 Scheduler | [E] `lib/bnest_app_web/live/admin_schedule_settings_live.ex`, `config/config.exs`, `config/test.exs` |
| U12 Backup | [E] `lib/bnest_app_web/live/admin_schedule_settings_live.ex`, `config/config.exs`, `config/test.exs` |
| U13 Operations | [E] `lib/bnest_app_web/controllers/health_controller.ex`, `lib/bnest_app_web/release_headers.ex`, `lib/bnest_app_web/live/admin_settings_live.ex`, `lib/bnest_app_web/live/admin_schedule_settings_live.ex`, `config/config.exs` |

## U4–U13: Tests and End-to-End Support

Each unit moves its context's tests so their paths mirror the new module paths, and edits every other test file that
names a module it moves. Paths are under `apps/bnest-app/` unless they start with `apps/`. A file that a unit moves is
named at its new path by every later unit. The e2e projects evaluate application modules by name through
`mix run -e` in `MIX_ENV=test`, so the unit that renames such a module edits the expression in the same pull request.

### U4: Storage

- [M] `test/unit/bnest_app/data_repository_test.exs` → `test/unit/bnest_app/storage/records_test.exs`
- [M] `test/unit/bnest_app/data_repository_named_test.exs` → `test/unit/bnest_app/storage/records_named_test.exs`
- [M] `test/unit/bnest_app/data_normalizer_test.exs` → `test/unit/bnest_app/storage/normalizer_test.exs`
- [M] `test/unit/bnest_app/canonical_json_test.exs` → `test/unit/bnest_app/storage/canonical_json_test.exs`
- [M] `test/unit/bnest_app/data_repository/backend_test.exs` → `test/unit/bnest_app/storage/record_backend_test.exs`
- [M] `test/integration/bnest_app/data_repository_test.exs` → `test/integration/bnest_app/storage/records_test.exs`
- [M] `test/integration/bnest_app/sqlite_storage_test.exs` → `test/integration/bnest_app/storage/sqlite_storage_test.exs`
- [M] `test/integration/bnest_app/sqlite_storage_migration_test.exs` →
  `test/integration/bnest_app/storage/sqlite_storage_migration_test.exs`
- [M] `test/integration/bnest_app/storage_config_test.exs` → `test/integration/bnest_app/storage/storage_config_test.exs`
- [M] `test/integration/bnest_app/test_data_cleanup_test.exs` →
  `test/integration/bnest_app/storage/test_data_cleanup_test.exs`
- [M] `test/integration/bnest_app/browser_import_test.exs` → `test/integration/bnest_app/storage/browser_import_test.exs`
- [M] `test/integration/bnest_app/schema_audit_test.exs` → `test/integration/bnest_app/storage/schema_audit_test.exs`
- [N] `test/unit/bnest_app/storage/domain/record_schema_test.exs` (characterization: the accepted `schemaVersion` of
  every record kind, written against `DataRepository.Schema` before the move)
- [N] `test/support/contracts/record_backend_contract.ex`
- [N] `test/unit/support/in_memory/record_backend.ex` (from `MemoryBackend` in `test/unit/support/home_page_driver.ex`)
- [N] `test/unit/bnest_app/storage/in_memory_record_backend_test.exs`
- [N] `test/integration/bnest_app/storage/sqlite_record_backend_test.exs`
- [N] `test/integration/bnest_app/storage/file_record_backend_test.exs`
- [E] `test/integration/bnest_app/application_test.exs`, `backup_test.exs`, `family_chat_migration_test.exs`,
  `identity_test.exs`, `persistent_schedules_migration_test.exs`, `scheduled_backup_test.exs`, `scheduler_test.exs`
  (all under `test/integration/bnest_app/`)
- [E] `test/integration/bnest_app_web/authentication_test.exs`
- [E] `test/integration/bnest_app_web/centralized_persistence_test.exs`
- [E] `test/integration/bnest_app_web/health_controller_test.exs`
- [E] `test/support/conn_case.ex`
- [E] `test/unit/support/home_page_driver.ex`
- [E] `test/integration/support/home_page_driver.ex`
- [E] `test/integration/support/family_chat_driver.ex`
- [E] `apps/bnest-app-be-e2e/tests/support/sqlite-storage.ts` (`DataRepository.{SqliteStore, StorageCoordinator}`)
- [E] `apps/bnest-app-be-e2e/tests/support/storage-authority.ts` (`DataRepository.StorageCoordinator`)
- [E] `apps/bnest-app-fe-e2e/tests/support/storage-authority.ts` (`DataRepository.StorageCoordinator`)

### U5: Identity

- [M] `test/unit/bnest_app/identity_test.exs` → `test/unit/bnest_app/identity/identity_test.exs`
- [M] `test/unit/bnest_app/identity_policy_test.exs` → `test/unit/bnest_app/identity/authorization_test.exs`
- [M] `test/integration/bnest_app/identity_test.exs` → `test/integration/bnest_app/identity/identity_test.exs`
- [N] `test/support/contracts/identity_store_contract.ex`
- [N] `test/unit/support/in_memory/identity_store.ex`
- [N] `test/unit/support/in_memory/credential_hasher.ex`
- [N] `test/unit/support/in_memory/session_notifier.ex`
- [N] `test/unit/bnest_app/identity/in_memory_identity_store_test.exs`
- [N] `test/integration/bnest_app/identity/record_identity_store_test.exs`
- [E] `test/integration/bnest_app_web/authentication_test.exs`
- [E] `test/integration/bnest_app_web/family_chat_graphql_test.exs`
- [E] `test/support/conn_case.ex`
- [E] `test/unit/support/home_page_driver.ex`, `test/unit/support/family_chat_driver.ex`
- [E] `test/integration/support/home_page_driver.ex`, `test/integration/support/family_chat_driver.ex`

### U6: Preferences

- [N] `test/unit/bnest_app/preferences/preferences_test.exs`
- [N] `test/unit/support/in_memory/preference_store.ex`
- [E] `test/integration/bnest_app_web/authentication_test.exs` (theme read-back through `BnestApp.Preferences.theme/1`)
- [E] `test/unit/support/home_page_driver.ex`, `test/integration/support/home_page_driver.ex`

### U7: SifatAllah

- [M] `test/unit/bnest_app/sifat_allah_test.exs` → `test/unit/bnest_app/sifat_allah/quiz_test.exs`
- [N] `test/unit/bnest_app/sifat_allah/sifat_allah_test.exs` (facade)
- [E] `test/integration/bnest_app_web/sifat_allah_live_test.exs`
- [E] `test/integration/bnest_app/storage/browser_import_test.exs`
- [E] `test/unit/bnest_app/storage/normalizer_test.exs`
- [E] `test/unit/support/home_page_driver.ex`, `test/integration/support/home_page_driver.ex`

### U8: CodexChat

- [M] `test/unit/bnest_app/chat_test.exs` → `test/unit/bnest_app/codex_chat/transcript_test.exs`
- [M] `test/unit/bnest_app/codex/model_access_test.exs` → `test/unit/bnest_app/codex_chat/model_access_test.exs`
- [M] `test/unit/bnest_app/codex/model_catalog_test.exs` → `test/unit/bnest_app/codex_chat/model_catalog_test.exs`
- [M] `test/unit/bnest_app/codex/model_catalog_configured_test.exs` →
  `test/unit/bnest_app/codex_chat/model_catalog_configured_test.exs`
- [M] `test/unit/bnest_app/codex/repository_access_test.exs` →
  `test/unit/bnest_app/codex_chat/repository_access_test.exs`
- [M] `test/integration/bnest_app/codex/model_catalog_test.exs` →
  `test/integration/bnest_app/codex_chat/model_catalog_test.exs`
- [N] `test/unit/bnest_app/codex_chat/codex_chat_test.exs`
- [E] `test/integration/bnest_app_web/chat_live_test.exs`
- [E] `test/support/codex_fixture_models.ex`, `test/integration/support/codex_fixture_session.ex`
- [E] `config/test.exs` (`:codex_session` and `:codex_models` become `config :bnest_app, BnestApp.CodexChat` keys)
- [E] `test/unit/support/home_page_driver.ex`, `test/integration/support/home_page_driver.ex`

### U9: FamilyChat

- [M] `test/unit/bnest_app/family_chat_test.exs` → `test/unit/bnest_app/family_chat/family_chat_test.exs`
- [M] `test/unit/bnest_app/family_chat/message_test.exs` → `test/unit/bnest_app/family_chat/domain/message_test.exs`
- [M] `test/integration/bnest_app/family_chat_migration_test.exs` →
  `test/integration/bnest_app/family_chat/family_chat_migration_test.exs`
- [N] `test/support/contracts/room_store_contract.ex`
- [N] `test/unit/support/in_memory/room_store.ex`, `test/unit/support/in_memory/message_publisher.ex`
- [N] `test/unit/bnest_app/family_chat/in_memory_room_store_test.exs`
- [N] `test/integration/bnest_app/family_chat/sqlite_room_store_test.exs`
- [E] `test/integration/bnest_app_web/family_chat_graphql_test.exs`
- [E] `test/integration/bnest_app_web/family_chat_room_page_test.exs`
- [E] `test/unit/bnest_app_web/schema_test.exs`
- [E] `test/unit/bnest_app/backup_restore_test.exs`, `test/unit/bnest_app/push_notifications_test.exs`
- [E] `config/test.exs`
- [E] `test/unit/support/family_chat_driver.ex`, `test/unit/support/home_page_driver.ex`,
  `test/integration/support/family_chat_driver.ex`

### U10: PushNotifications

- [M] `test/unit/bnest_app/push_notifications_test.exs` →
  `test/unit/bnest_app/push_notifications/push_notifications_test.exs`
- [M] `test/unit/bnest_app/push_notifications/policy_test.exs` →
  `test/unit/bnest_app/push_notifications/domain/policy_test.exs`
- [N] `test/support/contracts/subscription_store_contract.ex`, `test/support/contracts/delivery_store_contract.ex`
- [N] `test/unit/support/in_memory/subscription_store.ex`, `test/unit/support/in_memory/delivery_store.ex`,
  `test/unit/support/in_memory/push_sender.ex`
- [N] `test/unit/bnest_app/push_notifications/in_memory_subscription_store_test.exs`,
  `test/unit/bnest_app/push_notifications/in_memory_delivery_store_test.exs`
- [N] `test/integration/bnest_app/push_notifications/sqlite_subscription_store_test.exs`,
  `test/integration/bnest_app/push_notifications/sqlite_delivery_store_test.exs`
- [E] `test/unit/bnest_app/scheduler/dependency_test.exs`
- [E] `config/test.exs` (`:push_notifications_test_provider?` becomes the `PushSender` adapter key)
- [E] `test/unit/support/family_chat_driver.ex`, `test/integration/support/family_chat_driver.ex`

### U11: Scheduler

- [M] `test/unit/bnest_app/scheduler/policy_test.exs` → `test/unit/bnest_app/scheduler/domain/policy_test.exs`
- [M] `test/integration/bnest_app/scheduler_test.exs` → `test/integration/bnest_app/scheduler/scheduler_test.exs`
- [M] `test/integration/bnest_app/persistent_schedules_migration_test.exs` →
  `test/integration/bnest_app/scheduler/persistent_schedules_migration_test.exs`
- [N] `test/support/contracts/schedule_store_contract.ex`
- [N] `test/unit/support/in_memory/schedule_store.ex`
- [N] `test/unit/bnest_app/scheduler/in_memory_schedule_store_test.exs`
- [N] `test/integration/bnest_app/scheduler/sqlite_schedule_store_test.exs`
- [N] `test/integration/support/seeds/schedules.ex` (`BnestApp.Test.Seeds.Schedules`: the former `*_for_test!` seams
  and `put_test_schedule/5`)
- [E] `test/unit/bnest_app/scheduler/dependency_test.exs`
- [E] `test/integration/bnest_app/scheduled_backup_test.exs`
- [E] `test/unit/support/family_chat_driver.ex`, `test/unit/support/home_page_driver.ex`,
  `test/integration/support/family_chat_driver.ex`, `test/integration/support/home_page_driver.ex`
- [E] `apps/bnest-app-fe-e2e/tests/support/scheduled-backups.ts` (`Scheduler.Store.put_test_schedule` becomes
  `BnestApp.Test.Seeds.Schedules.put_test_schedule`)

### U12: Backup

- [M] `test/unit/bnest_app/backup_restore_test.exs` → `test/unit/bnest_app/backup/backup_restore_test.exs`
- [M] `test/integration/bnest_app/backup_test.exs` → `test/integration/bnest_app/backup/backup_test.exs`
- [M] `test/integration/bnest_app/scheduled_backup_test.exs` →
  `test/integration/bnest_app/backup/scheduled_backup_test.exs`
- [N] `test/unit/bnest_app/backup/backup_test.exs` (facade)
- [N] `test/unit/support/in_memory/capacity_probe.ex`, `test/unit/support/in_memory/ignore_check.ex`,
  `test/unit/support/in_memory/artifact_store.ex`, `test/unit/support/in_memory/database_snapshot.ex`,
  `test/unit/support/in_memory/backup_config_store.ex`
- [E] `test/support/test_backup_destination.ex`
- [E] `test/unit/bnest_app/scheduler/dependency_test.exs`
- [E] `test/unit/support/family_chat_driver.ex`, `test/unit/support/home_page_driver.ex`,
  `test/integration/support/family_chat_driver.ex`, `test/integration/support/home_page_driver.ex`

### U13: Operations

- [M] `test/integration/bnest_app/application_test.exs` → `test/integration/bnest_app/operations/application_test.exs`
- [N] `test/unit/bnest_app/operations/operations_test.exs`
- [N] `test/unit/support/in_memory/release_environment.ex`
- [E] `test/integration/bnest_app_web/health_controller_test.exs`
- [E] `test/integration/endpoint_policy_test.exs`
- [E] `test/unit/support/home_page_driver.ex`, `test/integration/support/home_page_driver.ex`

### Every Context Unit

- [E] `test/behaviour/verify.exs` (the unit's allow-list lines removed)
- [E] `mix.exs` (named coverage entries for the unit's moved inbound modules)

## U14: Closure

- [E] `apps/bnest-app/lib/bnest_app.ex` (`@legacy_exports` deleted)
- [E] `apps/bnest-app/test/integration/architecture/hexagonal_layering_test.exs` (rule L3 enabled, legacy allow-list
  deleted)
- [E] `apps/bnest-app/test/behaviour/verify.exs` (allow-list deleted)
- [E] `specs/apps/bnest/app-be/architecture.md` (C4 component view by bounded context)
- [E] `apps/bnest-app/README.md` (architecture section and module map)
- [E] `docs/explanation/hexagonal-architecture.md` (as-built context map)

## U15: Archival

- [M] `plans/in-progress/ddd-hexagonal-adoption/` → `plans/done/<completion-date>__ddd-hexagonal-adoption/`, where the
  executor generates `<completion-date>` as the archival commit's WIB date in `YYYY-MM-DD` form
- [E] `plans/in-progress/README.md`, `plans/done/README.md`: the only files linking to the plan directory today;
  `rhino md internal-link validate` in `REPO` proves no other link points at the old path

## Never Touched

`apps/bnest-app/priv/sqlite_repo/migrations/**`, `specs/apps/bnest/**/*.feature`, `apps/bnest-app/test/behaviour/steps/**`,
`apps/bnest-app/assets/**`, `apps/bnest-app/tools/**`, `libs/ex-bdd/**`, and every file of `apps/bnest-app-be-e2e/` and
`apps/bnest-app-fe-e2e/` other than the four support files named under U4 and U11. The e2e `tests/steps/**` files and
features stay unchanged, which `FEATURE_DIFF` checks.
