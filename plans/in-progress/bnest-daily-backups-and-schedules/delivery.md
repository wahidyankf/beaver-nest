# Delivery Plan

## Execution Record

- 2026-08-30: Moved from backlog to in progress after the plan quality gate passed; active-service baseline is the blocking prerequisite before application edits.
- 2026-08-30: Baseline passed: local and routed Caddy were ready on the active blue slot, SQLite readiness was green, ten anonymous LiveViews reconnected without refresh, and the repository volume had 98 GiB available. No application file had been edited.
- 2026-08-30: Phase 1 red established: recursive behavior coverage bound all 12 scheduled-backup scenarios in unit, integration, and E2E; focused unit execution failed in 17 expected places because scheduler policy and behavior outcomes do not exist yet.
- 2026-08-30: Phase 1 checkpoint passed: app formatting, E2E lint/typecheck, Badakmini repository validation, and diff checks were green. The root hook correctly rejected an intentionally red checkpoint commit, so the contract and implementation are checkpointed together only after all required gates became green.
- 2026-08-30: Phases 2 and 3 passed: additive migration/seed reconciliation, contextual claiming, bounded retries, renewable leases, attempt fencing, verified SQLite snapshots, owned retention, admin-only LiveViews, and typed panel discovery are implemented. Unit coverage is 99.24%, integration coverage is 100%, 231 integration tests pass, and all 37 focused desktop/tablet/mobile browser cases pass with connected LiveView.
- 2026-08-30: Rules propagation added the exact ignored backup-root ownership and retention contract to the canonical runtime-data convention; the existing harness routes already point to that source, and the repository idempotence/links/maps/Mermaid gate passed.
- 2026-08-30: The first managed rollout stopped fail-closed at migration proof before candidate startup because release eval had not started Ecto's repository registry. The active route remained healthy and unchanged. The adapter now starts its database dependencies before the repo, preserves a repo owned by a running Bnest application, closes a repo owned by standalone release eval, and has an exact `--no-start` regression test. Unit, integration, lint, typecheck, and release-tooling gates pass before retry.
- 2026-08-30: The retry stopped fail-closed in pre-artifact integration gates on the reproduced SQLite WAL lifecycle race: the sidecar disappeared between `exists?` and strict `chmod!`. Storage protection now treats only `ENOENT` as a valid transient sidecar outcome, preserves all other permission failures, and proves 25 serial restart cycles before another release attempt.
- 2026-08-30: Revision `272841d4` passed the complete managed rollout, including applied migration, candidate, Caddy promotion, routed LiveView, five-minute drain, and cleanup. Post-cutover proof found the first scheduled backup safely retrying with `default_not_ignored`: the compiled default still named the removed build worktree. Runtime backup resolution now receives the permanent checkout explicitly and has an isolated Git-ignore regression before the corrective release.

## Execution Rules

- Execute through the repository plan workflow and keep one task in progress at a time.
- Apply [live-service continuity](../../../repo-governance/development/live-service-continuity.md) to every candidate, route, drain, recovery, and cleanup action.
- Develop durable behavior as Gherkin, failing bindings, guarded Nx red, implementation, focused integration/E2E, then manual smoke.
- Use isolated test databases, marked backup roots, and `test-user-` identities; never read or mutate real user records in tests.
- Checkpoint each completed phase with thematic commits. Do not deploy merely because a commit was pushed.

## Phase 1 — Contracts and Baseline

- [x] **[AI] [AC-01..11] Add executable behavior contracts**
  - Input: [product requirements](prd.md), current behavior architecture, and adapter conventions.
  - Action: add `scheduled_backups.feature`, both app bindings, exact-origin E2E bindings, and behavior maps; prove every step is bound.
  - Outcome: authorization, context reuse, expiry, typed configuration, persistence, claiming, backup proof, dashboard, and retention are durable specifications.
  - Proof: guarded `bnest-app:test:quick` and affected behavior coverage fail only for missing behavior.
- [x] **[AI] [AC-01..11] Add focused red tests**
  - Input: injected clock, isolated SQLite databases, marked temporary destinations, and synthetic identities.
  - Action: cover startup reconciliation, immediate claims, overlap, leases/retries, both contexts, synthetic second handlers, every expiry mode, typed panel allowlists, source selection, receipts, cleanup, route denial, and responsive states.
  - Outcome: tests define the narrow implementation surface without touching production data.
  - Proof: guarded affected Nx targets show the expected red assertions.
- [x] **[AI] [AC-01..11] Checkpoint phase 1**
  - Input: complete red contract inventory and rendered UI assets.
  - Action: reconcile file impact, links, maps, and accessibility expectations.
  - Outcome: implementation can proceed without inventing product or failure behavior.
  - Proof: plan gate passes; record intentional red evidence.

## Phase 2 — Persistent Scheduler Expansion

- [x] **[AI] [AC-02, AC-03, AC-05, AC-06, AC-09, AC-11] Expand the SQLite schema**
  - Input: persistent schedule/run model and release migration adapter.
  - Action: add contextual schedules, expiration/counter constraints, unique run IDs, run occurrences, due/context indexes, and the approved `bnest-persistent-schedules-v1` release adapter; seed/reconcile the fixed-never-expiring backup schedule from the latest eligible slot and refuse destructive down migration with records.
  - Outcome: current release ignores compatible tables; candidate can prove them before startup.
  - Proof: migration tests cover empty upgrade, repeat reconciliation, incompatible rows, and protected rollback.
- [x] **[AI] [AC-02, AC-03, AC-05, AC-09, AC-11] Implement generic OTP coordination**
  - Input: `GenServer`, `Process.send_after/3`, named `Task.Supervisor`, injected clock, and code allowlist.
  - Action: implement startup/minute reconciliation, generic registry dispatch, short claims, future advancement, eligible catch-up, absolute/occurrence expiry, leases, no-overlap, and bounded retries.
  - Outcome: SQLite remains authoritative; both contexts share one core and process loss cannot lose, recount, or duplicate work.
  - Proof: coordinator tests pass across restart, two instances, retries, expiry boundaries, and synthetic handlers in both contexts.
- [x] **[AI] [AC-06, AC-07, AC-09, AC-11] Expose policy-bound scheduler reads**
  - Input: persisted schedules and safe run fields.
  - Action: add admin-grouped and family-only reads for context, cadence, expiry/progress, next run, active state, and last safe result; expose no unscoped public list or path/payload.
  - Outcome: admin inventory is persistent and future family surfaces can reuse only the permitted context.
  - Proof: queries cover both/empty groups, cross-context denial, all expiry modes, enabled, disabled, never-run, retrying, failed, expired, and verified states.
- [x] **[AI] [AC-02, AC-03, AC-05, AC-06, AC-07, AC-09, AC-11] Checkpoint phase 2**
  - Input: green scheduler schema and coordinator tests.
  - Action: run affected guarded quality gates and inspect migration/release compatibility.
  - Outcome: durable scheduling is independently shippable but remains inactive until the backup handler is ready.
  - Proof: affected Nx targets and release migration tests pass.

## Phase 3 — Verified Backup and Admin Dashboard

- [x] **[AI] [AC-01, AC-04, AC-05, AC-08] Implement private backup ownership**
  - Input: `@data/backup/` default, optional pointer, protected-root exception, existing `/data/*` Git-ignore rule, exact JSON contracts, permissions, marker, naming, and seven-WIB-day policy.
  - Action: add headless default resolution, atomic override, exact-repository-path validation, destination-ID-bound partial/final ownership, receipts, one-pair-per-date retention, current-folder-only cleanup, and `git check-ignore` release/readiness proof.
  - Outcome: closed snapshots sync through Dropbox while Bnest writes/deletes only exact ignored owned files; live SQLite stays outside Dropbox.
  - Proof: tests cover missing config default, tracked-file rejection, symlinks, other repository paths, source overlap, partial sync/recovery, same-day supersession, date boundaries, unknown files, repeated saves, and destination changes.
- [x] **[AI] [AC-01, AC-04, AC-05] Implement the backup handler**
  - Input: accepted run claim and authoritative `sqlite_primary` storage config.
  - Action: use `VACUUM INTO`, independent `quick_check`, schema/logical proof, fsync, atomic rename, safe receipts, and classified retry outcomes.
  - Outcome: only a fully verified SQLite snapshot becomes the latest backup.
  - Proof: focused tests interrupt every boundary and preserve the last verified pair.
- [x] **[AI] [AC-01, AC-02, AC-06, AC-07, AC-09, AC-10, AC-11] Build Admin settings and schedules**
  - Input: selected responsive assets, code-owned panel registry, policy-bound reads, and existing admin-only pipeline.
  - Action: add `/admin/settings`, `/admin/settings/schedules`, role-gated home entries, family/admin-system groups, expiry summaries, independent schedule/backup forms, setup claim, status announcements, and focus handling.
  - Outcome: admins discover all declared settings from home; each owner saves atomically and only admins inspect or change schedules.
  - Proof: LiveView tests cover panel discovery/allowlists, home navigation, contexts, expiry, separate form failures, all states, and pre-read denial for every non-admin class.
- [x] **[AI] [AC-01, AC-06, AC-07, AC-09, AC-10, AC-11] Prove the routed journey**
  - Input: exact served application origin and isolated admin/non-admin identities.
  - Action: navigate home → settings → schedules and the shortcut; exercise both context groups, expiry summaries/controls, independent save failures, desktop/tablet/mobile, keyboard, zoom, reduced motion, reconnect, setup/run/failure states, non-admin omission, and direct denial.
  - Outcome: the selected UI works accessibly through real LiveView/WebSocket behavior.
  - Proof: focused guarded E2E passes with connected LiveView and zero real-user access.
- [x] **[AI] [AC-01, AC-08, AC-09, AC-10, AC-11] Apply rule propagation**
  - Input: implemented runtime-backup rule changes and every other rule delta discovered during execution, including a verified empty remainder.
  - Action: apply [rules propagation](../../../repo-governance/workflows/rules-propagation.md), including `repo-governance/conventions/runtime-flat-file-data.md`, and reconcile canonical ownership/harness routes through its idempotence gate.
  - Outcome: the ignored `data/backup/` runtime contract and any other necessary rule changes match implemented behavior exactly; otherwise the relevant delta records a verified no-op.
  - Proof: rules-propagation verification and guarded repository gate pass.
- [x] **[AI] [AC-01..11] Update the canonical Bnest C4 model**
  - Input: final as-built settings, scheduler, live SQLite, Dropbox-synced backup folder, authorization, and Caddy relationships.
  - Action: update `specs/apps/bnest/app/architecture.md` System Context with Administrator/Dropbox sync, Container View with the backup folder and schedule rows, Component View with settings/coordinator/supervisor/registry/backup proof, and Architectural Constraints with source, authorization, additive overlap, ownership, and no-download rules.
  - Outcome: the canonical C4 model describes only the delivered architecture and links the new durable behavior.
  - Proof: architecture/specification maintenance checks and guarded repository gate pass.
- [x] **[AI] [AC-01..11] Checkpoint phase 3**
  - Input: green scheduler, backup, route, and UI behavior.
  - Action: update affected project READMEs/spec maps and run affected guarded gates serially.
  - Outcome: implementation is release-ready with documentation synchronized.
  - Proof: affected lint, typecheck, test, build, and Badakmini checks pass.

## Phase 4 — No-downtime Production Rollout

- [x] **[AI] [AC-01..11] Baseline the active service**
  - Input: current Caddy route, active revision, health, WebSocket, database mode, and free space.
  - Action: record value-free baseline evidence; stop immediately if health is not green.
  - Outcome: promotion and recovery have an authoritative comparison point.
  - Proof: routed health and revision evidence are captured.
- [ ] **[AI] [AC-01..11] Apply expansion and start an independent candidate**
  - Input: approved `bnest-persistent-schedules-v1` adapter and built release artifact.
  - Action: use managed `release:run` to apply/retry/verify the manifest-bound adapter under the release/storage locks, start the candidate separately, and prove schema, scheduler liveness, allowlist reconciliation, admin denial, and isolated backup smoke.
  - Outcome: candidate is compatible before receiving active traffic.
  - Proof: candidate health/revision plus direct schedule/backup evidence pass.
- [ ] **[AI] [AC-06, AC-07, AC-10] Promote through Caddy and prove recovery**
  - Input: healthy candidate and connected admin LiveView session.
  - Action: switch Caddy, verify intended routed revision, observe LiveView/WebSocket reconnect and authoritative socket-state recovery without refresh, then run admin/non-admin journeys.
  - Outcome: active users retain compatible state and only the intended candidate serves traffic.
  - Proof: routed revision, WebSocket, state recovery, and role-boundary evidence pass.
- [ ] **[AI] [AC-01..11] Drain and clean the successful promotion**
  - Input: green routed revision, reconnect proof, and five-minute bounded drain.
  - Action: drain the old slot, stop unneeded candidates/watchers/proxies, and retain only the active route plus the approved previous artifact.
  - Outcome: the promoted service remains healthy with no orphan process or temporary route.
  - Proof: final routed health/revision is green and process/route inventory is clean.
- [ ] **[AI] [AC-01..11] Roll back only if promotion proof fails**
  - Input: trigger evidence from any failed routed health, revision, LiveView/WebSocket recovery, role-boundary, or backup smoke check and the previous compatible artifact.
  - Action: restore Caddy to the previous release without deleting expanded tables or backup artifacts, then stop the rejected candidate after bounded drain.
  - Outcome: the last healthy release serves users and all recoverable schedule/backup state remains intact; if no trigger occurs, record `Not triggered` with the successful proof.
  - Proof: previous routed revision and critical journey are green, or the reconciliation records evidence-backed `Not triggered`.
- [ ] **[AI] [AC-01..11] Checkpoint phase 4**
  - Input: final routed evidence, clean process inventory, and rollback disposition.
  - Action: block advancement unless the active revision, WebSocket recovery, role boundary, and isolated backup smoke are green.
  - Outcome: production rollout has one healthy route and an explicit rollback result.
  - Proof: phase evidence contains no unresolved health, revision, cleanup, or recovery failure.

## Phase 5 — Completion

- [ ] **[AI] [AC-01..11] Reconcile documentation and evidence**
  - Input: implementation diff, accepted criteria, release evidence, and value-free first-backup receipt.
  - Action: update plan docs, application/E2E READMEs, runtime-data governance through rules propagation, specs, maps, and learnings; verify the existing `/data/*` ignore rule covers the backup root and remove stale assumptions.
  - Outcome: repository documentation matches delivered behavior.
  - Proof: links, maps, plan gate, repo tests, and affected quality gates pass.
- [ ] **[AI] [AC-01..11] Checkpoint phase 5**
  - Input: every acceptance criterion, conditional disposition, final evidence, and clean working process inventory.
  - Action: rerun the plan quality gate and repository hooks, and block archival while any required task or conditional remains unresolved.
  - Outcome: the completed active-stage record is self-consistent and authorized for its atomic lifecycle move.
  - Proof: plan gate, links, maps, repository tests, and stage inventory all pass.

## Archival

- [ ] **[AI] [AC-01..11] Move the completed plan**
  - Input: passed phase 5 checkpoint and a non-existing dated done destination.
  - Action: move the whole plan directory atomically from backlog to done, update both indexes, and verify links/maps against the dated destination.
  - Outcome: no stale backlog copy remains and the completed plan has exactly one archived stage.
  - Proof: lifecycle checks pass and the final thematic commit records the verified move.
