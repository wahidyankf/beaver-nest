# Delivery: DDD and Hexagonal Architecture Adoption

## Execution Status and Authority

**Status: executing.** Each item records its result when it is ticked. A cold executor resumes at the first unticked
item of the lowest-numbered open phase.

**Authority.** On 2026-10-01 the repository owner directed, in one stated goal:

- execution of this plan to completion;
- every commit and push it states;
- pull requests, merged under the [merge preconditions](../../../repo-governance/conventions/pull-request-merge.md);
- the production release of the closure revision (including the `--mode experience` re-promotion if production runs
  with the flags on);
- archival;
- [dev artifact clean-up](../../../repo-governance/workflows/dev-artifact-clean-up.md);
- a return to the primary checkout's local `main`.

The owner also asked for a status update every 30 minutes and for continuous progress without stalls. Execution starts
only from a non-blocking plan quality-gate verdict (Phase 1).

**Per code item.**

1. RED: a failing typecheck, scan, unit or contract test, captured with its exact failure.
2. GREEN: the minimum change that passes it.
3. REFACTOR: cleanup while green.
4. The unchanged Gherkin suite proves behaviour at both layers.
5. Changed drivers (BDD adapters) get the
   [Gherkin implementation review](../../../repo-governance/workflows/gherkin-implementation-review.md).

**Test data.** Tests use isolated, marked test-run roots and `test-user-` identities. Production users or data are never
read or mutated.

**Commands.** Every command runs from the worktree root with `rtk`, except git: it runs as plain `/usr/bin/git`,
because the rtk worktree guard refuses every `rtk`-prefixed git command inside a worktree. Restartable Nx work runs under one outer
checksum-pinned `./hippo` guard; `test:e2e` and `release:run` are self-guarded. Exit `75`: requeue only when the receipt
says `never-started`. Exit `73`: clean owned storage. Exit `78`: stop and replan.

## Execution Checkout, Delivery Units, Pause Safety

- **Execution checkout:** the task worktree `worktrees/ddd-hexa/` under the repository root. Each unit's branch is `ddd-hexa/uNN-<slug>`,
  created from synced `origin/main` after the previous unit merged. The first unit reuses `worktree/ddd-hexa`. Git runs
  as `/usr/bin/git` because of the rtk worktree guard in the user instructions. The release (Phase 15) is the single step
  run from the primary checkout (the repository root).
- **Delivery units:** U1–U15, as tabled in the [README](README.md).
  - Each unit has one owner (`[AI]`), one testable outcome (its phase checkpoint), and one rollback: revert its merge
    commit through a pull request. Every unit is a structural refactor with no schema change, so a revert is always
    deployable.
  - U15 (archival) follows the release.
- **Pause safety:**
  - Before a pause, the current unit's branch is pushed to `origin` and the phase's last result is recorded here.
  - Logs and the touched-path ledger live in `local-tmp/ddd-hexa/` (ignored).
  - Resuming runs `/usr/bin/git fetch origin`, then `/usr/bin/git merge origin/main` on the unit branch (a merge, so a
    pushed branch is never rewritten and no force push is needed), followed by
    `/usr/bin/git merge-base --is-ancestor origin/main HEAD`.

## Canonical Commands

| ID                            | Exact command (from the worktree root)                                                                                                                                                                                                                                                                                                                                                                        |
| ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `TYPECHECK`                   | `rtk ./hippo run --class ephemeral --resource-tier standard --disk-path . -- npm exec -- nx run -p bnest-app -t typecheck --skip-nx-cache`                                                                                                                                                                                                                                                                    |
| `LINT`                        | `rtk ./hippo run --class ephemeral --resource-tier standard --disk-path . -- npm exec -- nx run -p bnest-app -t lint --skip-nx-cache`                                                                                                                                                                                                                                                                         |
| `UNIT`                        | `rtk ./hippo run --class ephemeral --resource-tier standard --disk-path . -- npm exec -- nx run -p bnest-app -t test:unit --skip-nx-cache`                                                                                                                                                                                                                                                                    |
| `INTEGRATION`                 | `rtk ./hippo run --class ephemeral --resource-tier standard --disk-path . -- npm exec -- nx run -p bnest-app -t test:integration --skip-nx-cache`                                                                                                                                                                                                                                                             |
| `BEHAVIOUR`                   | `rtk ./hippo run --class ephemeral --resource-tier standard --disk-path . -- npm exec -- nx run -p bnest-app -t test:coverage:behaviour --skip-nx-cache`                                                                                                                                                                                                                                                      |
| `APP_QUICK`                   | `rtk ./hippo run --class ephemeral --resource-tier standard --disk-path . -- npm exec -- nx run -p bnest-app -t test:quick --skip-nx-cache`                                                                                                                                                                                                                                                                   |
| `FOCUS_UNIT <path>`           | `rtk ./hippo run --class ephemeral --resource-tier standard --disk-path . -- sh -c 'cd apps/bnest-app && BNEST_TEST_LAYER=unit MIX_ENV=test mix test --no-start <path>'`                                                                                                                                                                                                                                      |
| `FOCUS_INT <path>`            | `rtk ./hippo run --class ephemeral --resource-tier standard --disk-path . -- sh -c 'cd apps/bnest-app && BNEST_TEST_LAYER=integration MIX_ENV=test mix test --exclude integration-exempt --max-cases 1 <path>'`                                                                                                                                                                                               |
| `REPO`                        | `rtk ./hippo run --class ephemeral --resource-tier standard --disk-path . -- npm exec -- nx run -p rhino-consumer -t test:repo`                                                                                                                                                                                                                                                                               |
| `BE_E2E` / `FE_E2E`           | `rtk npm run test:e2e:be` / `rtk npm run test:e2e:fe`                                                                                                                                                                                                                                                                                                                                                         |
| `FEATURE_DIFF <base>`         | `/usr/bin/git diff --stat <base>..HEAD -- specs/apps/bnest apps/bnest-app/test/behaviour/steps apps/bnest-app/priv/sqlite_repo/migrations apps/bnest-app/tools apps/bnest-app-be-e2e/tests/steps apps/bnest-app-fe-e2e/tests/steps` (must print nothing). In a context phase, `<base>` is the `origin/main` SHA the unit branched from, recorded in its first item; at U14 it is the U1 base SHA from Phase 0 |
| `BE_COVERAGE` / `FE_COVERAGE` | `rtk ./hippo run --class ephemeral --resource-tier standard --disk-path . -- npm exec -- nx run -p bnest-app-be-e2e -t test:coverage:behaviour --skip-nx-cache` / the same with `-p bnest-app-fe-e2e`                                                                                                                                                                                                         |
| `HARNESS`                     | `rtk ./rhino harness adapters generate`, then `rtk ./rhino harness adapters validate`                                                                                                                                                                                                                                                                                                                         |

## Phase 0: Preflight (not a delivery boundary)

- [x] [AI] Sync the worktree: `/usr/bin/git fetch origin`, `/usr/bin/git rebase origin/main` (the U1 branch is not yet
      pushed), `/usr/bin/git merge-base --is-ancestor origin/main HEAD`. Proof: exit 0, recorded base SHA. AC: none
      (prerequisite).
  - 2026-10-01: fast-forwarded to `7e23669c912c7d0064efcd923a077594efff7dd3` (the uncommitted plan draft blocks a
    rebase; a fast-forward is equivalent here); ancestry check exit 0. This is the U1 base SHA.
- [x] [AI] Initialize dependencies: root `npm install` and `apps/bnest-app` `mix deps.get`, each under `./hippo run
--class transactional`. Proof: `node_modules/.bin/nx` exists and `mix deps` reports no unavailable dependency.
  - 2026-10-01: both present after the dependency fetch; the baseline runs below compiled.
- [x] [AI] Baseline: `APP_QUICK` on the base revision. Proof: exit 0, and the log in
      `local-tmp/ddd-hexa/baseline-quick.log`, with the unit coverage percentage recorded. AC-DH-08.
  - 2026-10-01: exit 0 on `b85e5e497`; unit coverage 99.11%. The later base `7e23669c9` changes only leak-review
    governance and scripts, no application path, so the baseline stands.
- [x] [AI] Baseline: `INTEGRATION` on the base revision. Proof: exit 0 and the scenario count recorded. AC-DH-08.
  - 2026-10-01: exit 0; 330 tests, 0 failures, 17 excluded.
- [x] [AI] Record the active service: `npm exec -- nx run -p bnest-app -t proxy:status`, the listening slot on
      `4000`/`4001`, and its working directory from `lsof -p`. Proof: the active slot runs from a release artifact
      outside this worktree, so the dependency and code edits here cannot affect it.
  - 2026-10-01: `proxy:status` needs the deploy environment, which Phase 15 loads. Both `4000` and `4001` listen,
    each a launchd `beam.smp` with working directory `/`, running the release artifact of revision `5b08a27f`
    under the machine-local deployment root. Nothing runs from this worktree. Phase 15 preflight resolves which slot
    Caddy routes and whether the second listener is a retained slot.
- [x] [AI] **Checkpoint 0 (blocking):** baseline green. If it is red, stop. A pre-existing red baseline is a defect to report,
      not to absorb.

## Phase 1: U1, Plan

- [x] [AI] Run the post-write decision gate on the complete draft and record D-entries in `learnings.md`. Proof:
      D15–D17 recorded.
- [x] [AI] Run the [plan quality gate](../../../repo-governance/workflows/plan-quality-gate.md) through the
      `plan-checker` agent on a frozen snapshot, with at most two repair cycles. Proof: a terminal verdict recorded in
      `learnings.md`.
  - 2026-10-01: run 1 `BLOCKED_INPUT_CHANGED`; run 2 `PASS_WITH_FINDINGS` after two cycles; both remaining findings
    accepted.
- [x] [AI] Update the `plans/in-progress/README.md` active-plan section and directory map. Proof: the map lists
      `ddd-hexagonal-adoption/`.
- [x] [AI] `REPO`. Proof: exit 0.
  - 2026-10-01: `rhino-consumer:test:repo` exit 0 (all eight gates).
- [x] [AI] Commit `docs(plans): add ddd and hexagonal architecture adoption plan` after the data-safety review. Push,
      open a draft PR, mark it ready, post the leak review of the exact head, wait for the exact-head `Quality gate`, then
      merge. Proof: the PR number and merge SHA recorded here.
  - 2026-10-01: PR #116 merged as `e68a41b44`. It supersedes #113 and #115: each fell behind `main` (the second on
    the new Mermaid palette policy), and a force push is not authorized.
- [x] [AI] **Checkpoint 1 (blocking):** verdict `PASS` or `PASS_WITH_FINDINGS` with every finding accepted; U1 merged.

## Phase 2: U2, Architecture Standard (AC-DH-01)

- [x] [AI] Write `repo-governance/development/quality/code/hexagonal-architecture.md` and its four modules plus
      `README.md`, per [001](tech-docs/001-architecture-standard.md). Proof: rhino word budget passes in `REPO`.
  - 2026-10-01: written; the word budget passes in `REPO`.
- [x] [AI] Link the six names in `.agents/skills/developing-applications/SKILL.md`,
      `.agents/skills/programming-elixir/SKILL.md`, `.agents/skills/framework-phoenix-liveview/SKILL.md`, the three
      `.agents/agents/swe-code-maker.md`, `swe-code-checker.md`, `swe-code-fixer.md`, and the Elixir, Phoenix LiveView and
      TypeScript stack standards. Proof: for each of the six names ("Hexagonal Architecture", "Layers and the Dependency
      Rule", "Application Shapes", "Functional Core, Imperative Shell", "Test Doubles", "Implementation Stages"),
      `grep -rnF "<name>" .agents repo-governance/development/quality/stacks` shows every hit inside a markdown link
      (`[<name>](`) or a heading of the standard itself. AC-DH-01.
  - 2026-10-01: 21 links added; the six-name scan reports 0 unlinked hits. The Phoenix LiveView skill carried none
    of the names.
- [x] [AI] Amend "Contexts Own the Application" in `phoenix-liveview-standards.md` to say that a context is the facade
      of one bounded context, and that live views, controllers, resolvers and plugs are inbound adapters.
  - 2026-10-01: amended; Mix tasks are named as inbound adapters too.
- [x] [AI] Record the `boundary` adopter decision and rewrite the boundary deviation in `repository-adapter.md`. Add the
      enforcement row to `software-quality-enforcement.md` and the link line to `AGENTS.md` (within the 750-word budget).
  - 2026-10-01: adopter decision and deviation recorded. The map row and the `AGENTS.md` line do not fit the word
    budget; accepted deviation [E2](learnings.md#e2-no-word-budget-left-for-the-agentsmd-line-or-a-map-row-2026-10-01-u2).
- [x] [AI] Docs: `docs/explanation/hexagonal-architecture.md` (with an accessible Mermaid context map),
      `docs/explanation/README.md`, `docs/reference/glossary.md`, `docs/reference/software-development.md`.
  - 2026-10-01: written; the diagram is the layers-of-one-context view on the canonical palette.
- [x] [AI] Apply the [rules-propagation workflow](../../../repo-governance/workflows/rules-propagation.md) to the new
      standard and record its terminal result (`PASS_CHANGED` or `PASS_NO_CHANGE`).
  - 2026-10-01: `PASS_CHANGED`.
- [x] [AI] Apply the [docs-propagation workflow](../../../repo-governance/workflows/docs-propagation.md) and record its
      terminal result.
  - 2026-10-01: `PASS_CHANGED`.
- [x] [AI] Regenerate the harness adapters for the edited skills and agents under the
      [harness contract change workflow](../../../repo-governance/workflows/coding-harness-contract-change.md): `HARNESS`.
      Proof: validate exits 0, and the regenerated `.claude/`, `.opencode/` and `.codex/` adapter files are committed.
  - 2026-10-01: generate is current and validate is clean.
- [x] [AI] `REPO`. Proof: exit 0. AC-DH-01.
  - 2026-10-01: `rhino-consumer:test:repo` exit 0 (all eight gates).
- [x] [AI] Commit `docs(governance): adopt ddd and hexagonal architecture standard`; PR, leak review, exact-head gate,
      merge. Proof: PR number and merge SHA.
  - 2026-10-01: PR #117 merged as `8819ebff2`.
- [x] [AI] **Checkpoint 2 (blocking):** U2 merged and `REPO` green on `main`.
  - 2026-10-01: the exact-head "Repository and consumer contracts" job (which runs `REPO`) passed on #117, and the rebase
    merge left `main` at that tree.

## Phase 3: U3, Boundary Tooling (AC-DH-02, AC-DH-03, AC-DH-04)

- [x] [AI] RED (tooling): add `{:boundary, "~> 0.11", runtime: false}`, the `:boundary` compiler and the
      `default: [check: [apps: …]]` settings to `apps/bnest-app/mix.exs`, then fetch dependencies. Declare `BnestApp` with an
      empty `@legacy_exports`, `BnestAppWeb`, `BnestAppCli`, `BnestApp.Application` and `BnestApp.SqliteRepo`. Run
      `TYPECHECK`. Expected: it **fails** with boundary warnings for every web, CLI and application call into
      `BnestApp.*`. Record the warning count and the distinct callee list in
      `local-tmp/ddd-hexa/u3-red-warnings.txt`. AC-DH-03.
  - 2026-10-01: `TYPECHECK` exit 1 with 285 warnings over 70 distinct edges (29 legacy callees from web and CLI,
    test drivers classified into the root, and infrastructure calls from the root and `SqliteRepo`); summary in
    `u3-red-warnings.txt`.
- [x] [AI] GREEN (tooling): set `@legacy_exports` to exactly the callee list; add the temporary infrastructure deps
      tabled in [003](tech-docs/003-boundary-enforcement.md) to `BnestAppWeb` and `BnestAppCli`, each marked with the unit
      that removes it; classify the Mix tasks; mark the test-support modules as ignored top-level boundaries; and declare
      `BnestApp.Release` (new `lib/bnest_app/release.ex`) as a top-level boundary with its permanent deps. Run `TYPECHECK`.
      Expected: exit 0. AC-DH-02 (partial).
  - 2026-10-01: exit 0, no warnings. `@legacy_exports` holds 31 entries (the 29 web and CLI callees plus
    `FamilyChat.Store` and `Scheduler.Policy`, which `BnestApp.Release` calls). The root also lists the
    infrastructure its legacy modules call; see [E3](learnings.md#e3-u3-boundary-tooling-findings-2026-10-01).
- [x] [AI] RED (forbidden edge proof): in the worktree, declare `BnestApp.Backup` (`lib/bnest_app/backup.ex`) a
      top-level strict boundary with no deps and add `BnestApp.SqliteRepo.query!("SELECT 1")` to it. Run `TYPECHECK`.
      Expected: fails with a boundary warning naming both modules. Record it, then
      `/usr/bin/git restore apps/bnest-app/lib/bnest_app/backup.ex`. This proves the gate wiring; the AC-DH-03 rows
      are proved at U14.
  - 2026-10-01: exit 1, `references from BnestApp.Backup to BnestApp.SqliteRepo are not allowed`
    (`lib/bnest_app/backup.ex:19`); file restored.
- [x] [AI] RED (scan): write `test/integration/architecture/hexagonal_layering_test.exs` and
      `test/integration/support/architecture_scan.ex` with rules L1, L2 and L4, and an empty `@legacy_modules`. Run
      `FOCUS_INT test/integration/architecture/hexagonal_layering_test.exs`. Expected: it fails, listing current
      violations. AC-DH-04.
  - 2026-10-01: 2 of 3 tests fail; 195 violations (185 L1, 10 L4) over 24 modules.
- [x] [AI] GREEN (scan): set `@legacy_modules` to the violators, and assert in the test that every `@legacy_exports`
      entry is in `@legacy_modules`. Re-run `FOCUS_INT`. Expected: pass.
  - 2026-10-01: pass. `@legacy_modules` holds 43 entries (24 violators plus the remaining legacy exports).
- [x] [AI] RED (unit guard): add the `BnestApp.SqliteRepo` and `\.Adapters\.(?!InMemory)` patterns to
      `test/behaviour/verify.exs`. Run `BEHAVIOUR`. Expected: fails, listing the matching lines of
      `test/unit/support/home_page_driver.ex` and `test/unit/support/family_chat_driver.ex`. AC-DH-06 (partial).
  - 2026-10-01: fails on five lines: `backup_restore_test.exs:9`, three `family_chat_test.exs` lines, and
    `unit/support/family_chat_driver.ex:19`. The home-page driver has none.
- [x] [AI] GREEN (unit guard): add an allow-list of exactly those lines, each tagged with the unit that removes it. Run
      `BEHAVIOUR`. Expected: pass.
  - 2026-10-01: pass; the allow-list tags the Backup line `U12` and the FamilyChat lines `U9`.
- [x] [AI] REFACTOR: replace the named `boundary_adapters` coverage entries with `~r/\.Adapters\./` plus named inbound
      modules. Proof: `UNIT` passes with coverage ≥ 99%, and the percentage is recorded.
  - 2026-10-01: 99.11%. Legacy core modules that still perform I/O stay named in a `legacy_core` list until
    their context unit brings them under the threshold.
- [x] [AI] `APP_QUICK` and `INTEGRATION`. Proof: both exit 0; `FEATURE_DIFF` empty. AC-DH-08.
  - 2026-10-01: `APP_QUICK` exit 0 (330 unit tests); `INTEGRATION` exit 0 (333 tests, 17 excluded);
    `FEATURE_DIFF e68a41b44` empty.
- [ ] [AI] Commit `build(bnest-app): enforce module boundaries with boundary`, with the dependency-selection record in
      the PR body; PR, leak review, gate, merge.
- [ ] [AI] **Checkpoint 3 (blocking):** U3 merged; `@legacy_exports` recorded with N entries.

## Phases 4–13: One Bounded Context Each

Every context phase runs the same nine items, in this order, with the context's own paths from
[002](tech-docs/002-target-architecture-and-context-map.md) and [006](tech-docs/006-file-impact.md):

1. RED (boundary): declare the facade `top_level?: true, type: :strict`, create `<context>/domain.ex` and `ports.ex`
   (strict sub-boundaries) and `<context>/adapters.ex` (`top_level?: true, type: :strict`), per
   [002](tech-docs/002-target-architecture-and-context-map.md), and delete the context's entries from
   `@legacy_exports` and `@legacy_modules`. Run
   `TYPECHECK` and `FOCUS_INT …/hexagonal_layering_test.exs`. Expected: **both fail**, naming the context's current
   edges. Record the counts.
2. RED (contract, stateful ports only): write the contract suite and its unit user against a not-yet-written in-memory
   adapter. Run `FOCUS_UNIT`. Expected: fails (module undefined).
3. GREEN (contract): implement the in-memory adapter until `FOCUS_UNIT` passes. The integration user runs against the
   real adapter only after item 4 has moved it, as a separate GREEN (contract, real adapter) item.
4. GREEN (layers): move the modules to their destinations, extract the ports, move effects into adapters, wire adapters
   in `config/config.exs` and `config/test.exs`, and thin the inbound adapters to facade calls. Run `TYPECHECK` and the
   layering scan. Expected: pass.
5. GREEN (drivers): point the unit drivers at the facade with in-memory adapters, and delete the context's lines from
   the `verify.exs` allow-list. Run `UNIT` and `BEHAVIOUR`. Expected: pass, coverage ≥ 99%.
6. REFACTOR: remove dead aliases and moved `*_for_test!` seams, and update moduledocs. Run `LINT` and `APP_QUICK`.
   Expected: pass.
7. Integration and behaviour proof: `INTEGRATION` passes; `FEATURE_DIFF` is empty.
8. Gherkin implementation review of the changed drivers, recorded in `learnings.md`.
9. Commit `refactor(bnest-app): adopt hexagonal layers in <context>`; PR, leak review, exact-head gate, merge.

### Phase 4: U4, Storage

- [ ] [AI] Characterization (green by design; this is a refactor): `test/unit/bnest_app/storage/domain/record_schema_test.exs`
      pins the accepted and rejected `schemaVersion` of every record kind against today's `DataRepository.Schema`.
      `FOCUS_UNIT` passes before any move and is retargeted at `Storage.Domain.RecordSchema` by GREEN (layers). AC-DH-09.
- [ ] [AI] RED (boundary): `apps/bnest-app/lib/bnest_app/storage/{domain,ports,adapters}.ex`, with
      `lib/bnest_app/storage.ex` strict; delete the `DataRepository.*` and `Storage.*` legacy entries. `TYPECHECK` and the
      scan fail. AC-DH-02, AC-DH-04.
- [ ] [AI] RED (contract): `test/support/contracts/record_backend_contract.ex`, used by
      `test/unit/bnest_app/storage/in_memory_record_backend_test.exs`. `FOCUS_UNIT` fails. AC-DH-07.
- [ ] [AI] GREEN (contract): `test/unit/support/in_memory/record_backend.ex` (from `MemoryBackend`). `FOCUS_UNIT`
      passes. AC-DH-07.
- [ ] [AI] GREEN (layers): the U4 moves in 006. Add the `RecordKind` port and register `:chat` and `:sifat_allah` kinds
      in configuration; the `Storage` facade with the functions 002 names (`ensure_started!/0,1`, `stop/0`,
      `database_path/0`, `database_generation/0`, `phase/0`, `with_shared_lock/1`, `with_exclusive_lock/1`,
      `active_store/0`); every caller 006 lists under U4 moves to them or to `Storage.Records`, and the root boundary
      lists `BnestApp.Storage`; the web callers that move to `Storage.Records` (`UserAuth`, `ThemeController`,
      `SifatAllahLive`, `ChatLive`) enter the scan's `@legacy_records_callers` allow-list, each tagged with the unit that
      removes it; `StorageLive`, `DataMigrationLive` and the storage and schema Mix tasks call only `BnestApp.Storage`; the readiness process name becomes `BnestApp.Storage.Records`. The e2e support expressions in
      `apps/bnest-app-be-e2e/tests/support/sqlite-storage.ts` and both projects' `tests/support/storage-authority.ts` name
      the new modules. `TYPECHECK` and the scan pass. AC-DH-04, AC-DH-05.
- [ ] [AI] GREEN (contract, real adapter): `FOCUS_INT` passes on
      `test/integration/bnest_app/storage/sqlite_record_backend_test.exs` and
      `test/integration/bnest_app/storage/file_record_backend_test.exs`. AC-DH-07.
- [ ] [AI] GREEN (drivers): the unit `home_page_driver.ex` and `family_chat_driver.ex` use the Storage facade with the
      in-memory backend; the allow-list loses the Storage lines. `UNIT` and `BEHAVIOUR` pass. AC-DH-06.
- [ ] [AI] REFACTOR: `LINT` and `APP_QUICK` pass.
- [ ] [AI] `INTEGRATION` passes and `FEATURE_DIFF` is empty. AC-DH-08, AC-DH-09.
- [ ] [AI] Focused e2e for the changed support: `BE_E2E` and `FE_E2E`, each with `-- --grep "Bnest SQLite storage"`
      appended. Proof: pass counts recorded.
- [ ] [AI] Gherkin implementation review of the changed drivers and e2e support, recorded.
- [ ] [AI] Commit, PR, leak review, gate, merge `refactor(bnest-app): adopt hexagonal layers in storage`.
- [ ] [AI] **Checkpoint 4 (blocking):** U4 merged, and the Storage entries are gone from both legacy lists.

### Phase 5: U5, Identity

- [ ] [AI] RED (boundary): `lib/bnest_app/identity/{domain,ports,adapters}.ex`, with the facade strict. `TYPECHECK` and
      the scan fail.
- [ ] [AI] RED (contract): `test/support/contracts/identity_store_contract.ex`, used by
      `test/unit/bnest_app/identity/in_memory_identity_store_test.exs`. `FOCUS_UNIT` fails. AC-DH-07.
- [ ] [AI] GREEN (contract): `test/unit/support/in_memory/identity_store.ex`, `credential_hasher.ex` and
      `session_notifier.ex` until `FOCUS_UNIT` passes.
- [ ] [AI] GREEN (layers): the U5 moves, including `Ports.SubscriptionRevoker` and `Adapters.PushSubscriptionRevoker`
      (whose `Adapters` boundary lists `BnestApp` until U10). `UserAuth` (account), `SessionController`, `BootstrapController`,
      `LoginLive` and `bnest.identity.benchmark` call only `BnestApp.Identity`. `TYPECHECK` and the scan pass. AC-DH-05.
- [ ] [AI] GREEN (contract, real adapter):
      `FOCUS_INT test/integration/bnest_app/identity/record_identity_store_test.exs` passes against `RecordIdentityStore`.
      AC-DH-07.
- [ ] [AI] GREEN (drivers): `test/unit/support/home_page_driver.ex` and `test/unit/support/family_chat_driver.ex` use the facade with in-memory adapters, and the
      `test/behaviour/verify.exs` allow-list loses its U5 lines. `UNIT` and `BEHAVIOUR` pass. AC-DH-06.
- [ ] [AI] REFACTOR: `LINT` and `APP_QUICK` pass.
- [ ] [AI] `INTEGRATION` passes; `FEATURE_DIFF` is empty. AC-DH-08.
- [ ] [AI] Gherkin implementation review, recorded.
- [ ] [AI] Commit, PR, leak review, gate, merge.
- [ ] [AI] **Checkpoint 5 (blocking):** U5 merged.

### Phase 6: U6, Preferences

- [ ] [AI] RED (boundary): `lib/bnest_app/preferences.ex` and `lib/bnest_app/preferences/{domain,ports,adapters}.ex`
      declared strict, and `ThemeController` and `UserAuth` removed from `@legacy_records_callers`. Expected: the scan
      fails (rule L4 names both → `Storage.Records` for `:theme`); `TYPECHECK` still passes because the new boundaries
      have no callers yet. Record both.
- [ ] [AI] RED (facade): `test/unit/bnest_app/preferences/preferences_test.exs` covers `theme/1`, `put_theme/3` with
      its revision conflict, `clear_theme/1`, and rejection of an unknown theme, all against
      `test/unit/support/in_memory/preference_store.ex`. `FOCUS_UNIT` fails (undefined).
- [ ] [AI] GREEN (layers): add the facade, `Domain.Theme`, `Ports.PreferenceStore` and `Adapters.RecordPreferenceStore`
      (`:theme` record unchanged); `ThemeController` and `UserAuth` call only `BnestApp.Preferences` for theme.
      `TYPECHECK`, the scan and `FOCUS_UNIT` pass. AC-DH-05.
- [ ] [AI] GREEN (drivers): `test/unit/support/home_page_driver.ex` use the facade with in-memory adapters, and the
      `test/behaviour/verify.exs` allow-list loses its U6 lines. `UNIT` and `BEHAVIOUR` pass.
- [ ] [AI] REFACTOR: `LINT` and `APP_QUICK` pass.
- [ ] [AI] `INTEGRATION` passes; `FEATURE_DIFF` is empty.
- [ ] [AI] Gherkin implementation review, recorded.
- [ ] [AI] Commit, PR, leak review, gate, merge.
- [ ] [AI] **Checkpoint 6 (blocking):** U6 merged.

### Phase 7: U7, SifatAllah

- [ ] [AI] RED (boundary): `lib/bnest_app/sifat_allah/{domain,ports,adapters}.ex`, and `SifatAllahLive` removed from
      `@legacy_records_callers`; `TYPECHECK` and the scan fail.
- [ ] [AI] RED (facade): `test/unit/bnest_app/sifat_allah/sifat_allah_test.exs` asserts `load_progress/1` and
      `save_progress/3` against the in-memory record backend. `FOCUS_UNIT` fails (undefined).
- [ ] [AI] GREEN (layers): move the pure module to `SifatAllah.Domain.Quiz` and add the facade, `ProgressStore` and
      `RecordProgressStore`. `SifatAllahLive` persists only through the facade. `TYPECHECK`, the scan and `FOCUS_UNIT` pass.
- [ ] [AI] GREEN (drivers): `test/unit/support/home_page_driver.ex` use the facade with in-memory adapters, and the
      `test/behaviour/verify.exs` allow-list loses its U7 lines. `UNIT` and `BEHAVIOUR` pass.
- [ ] [AI] REFACTOR: `LINT` and `APP_QUICK` pass.
- [ ] [AI] `INTEGRATION` passes; `FEATURE_DIFF` is empty.
- [ ] [AI] Gherkin implementation review, recorded.
- [ ] [AI] Commit, PR, leak review, gate, merge.
- [ ] [AI] **Checkpoint 7 (blocking):** U7 merged.

### Phase 8: U8, CodexChat

- [ ] [AI] RED (boundary): `lib/bnest_app/codex_chat.ex` and `lib/bnest_app/codex_chat/{domain,ports,adapters}.ex`;
      delete the `Chat` and `Codex.*` legacy entries, and remove `ChatLive` from `@legacy_records_callers`. `TYPECHECK` and
      the scan fail.
- [ ] [AI] RED (facade): `test/unit/bnest_app/codex_chat/codex_chat_test.exs` covers opening a conversation, sending a
      prompt through the fixture `AgentSession`, and persisting the snapshot through the in-memory backend. `FOCUS_UNIT`
      fails.
- [ ] [AI] GREEN (layers): the U8 moves; adapter keys move to `config :bnest_app, BnestApp.CodexChat`;
      `application.ex` starts `CodexChat.child_specs/0`. `ChatLive` calls only the facade; readiness checks `CodexChat.ModelCatalog`. `TYPECHECK`, the scan and `FOCUS_UNIT` pass.
- [ ] [AI] GREEN (drivers): `test/unit/support/home_page_driver.ex` use the facade with in-memory adapters, and the
      `test/behaviour/verify.exs` allow-list loses its U8 lines. `UNIT` and `BEHAVIOUR` pass.
- [ ] [AI] REFACTOR: `LINT` and `APP_QUICK` pass.
- [ ] [AI] `INTEGRATION` passes; `FEATURE_DIFF` is empty.
- [ ] [AI] Gherkin implementation review, recorded.
- [ ] [AI] Commit, PR, leak review, gate, merge.
- [ ] [AI] **Checkpoint 8 (blocking):** U8 merged.

### Phase 9: U9, FamilyChat

- [ ] [AI] RED (boundary): `lib/bnest_app/family_chat/{domain,ports,adapters}.ex`; `TYPECHECK` and the scan fail.
- [ ] [AI] RED (contract): `test/support/contracts/room_store_contract.ex` (idempotency, ordering, cursor pagination,
      reply linkage, append-only), used by `test/unit/bnest_app/family_chat/in_memory_room_store_test.exs`. `FOCUS_UNIT`
      fails. AC-DH-07.
- [ ] [AI] GREEN (contract): `test/unit/support/in_memory/room_store.ex` and `message_publisher.ex` until `FOCUS_UNIT`
      passes.
- [ ] [AI] GREEN (layers): the U9 moves. `Release.Migrations.FamilyChat` keeps its name and delegates to the facade.
      `push_notifications.ex`, `push_notifications/dispatcher.ex` and `backup.ex` call `FamilyChat.ensure_ready!/0`,
      `canonical_room/0` and `insert_message!/6` in place of `FamilyChat.Store`, and the root lists
      `BnestApp.FamilyChat`.
      The controller, socket, resolver and types call only the facade and exported `Domain.Message`. `TYPECHECK` and the scan
      pass.
- [ ] [AI] GREEN (contract, real adapter):
      `FOCUS_INT test/integration/bnest_app/family_chat/sqlite_room_store_test.exs` passes. AC-DH-07.
- [ ] [AI] GREEN (drivers): `UnitFamilyChatDriver` no longer opens SQLite; allow-list updated. `UNIT` and `BEHAVIOUR`
      pass. AC-DH-06.
- [ ] [AI] REFACTOR: `LINT` and `APP_QUICK` pass.
- [ ] [AI] `INTEGRATION` passes (including "Independent slot-local PubSub"); `FEATURE_DIFF` is empty.
- [ ] [AI] Gherkin implementation review, recorded.
- [ ] [AI] Commit, PR, leak review, gate, merge.
- [ ] [AI] **Checkpoint 9 (blocking):** U9 merged.

### Phase 10: U10, PushNotifications

- [ ] [AI] RED (boundary): `lib/bnest_app/push_notifications/{domain,ports,adapters}.ex`; `TYPECHECK` and the scan fail.
- [ ] [AI] RED (contract): `test/support/contracts/subscription_store_contract.ex` and `delivery_store_contract.ex`,
      used by `test/unit/bnest_app/push_notifications/in_memory_subscription_store_test.exs` and
      `in_memory_delivery_store_test.exs`. `FOCUS_UNIT` fails. AC-DH-07.
- [ ] [AI] GREEN (contract): `test/unit/support/in_memory/subscription_store.ex`, `delivery_store.ex` and
      `push_sender.ex` until `FOCUS_UNIT` passes.
- [ ] [AI] GREEN (layers): the U10 moves. `:push_notifications_test_provider?` becomes adapter selection; the
      `RetentionJob` handler atom in `scheduler/registry.ex` and `release/migrations/family_chat.ex` becomes
      `Adapters.RetentionTask`; `lib/bnest_app/identity/adapters.ex` swaps its
      `BnestApp` dep for `BnestApp.PushNotifications`. `TYPECHECK` and the scan pass. AC-DH-03 row 3.
- [ ] [AI] GREEN (contract, real adapter): `FOCUS_INT` passes on
      `test/integration/bnest_app/push_notifications/sqlite_subscription_store_test.exs` and
      `test/integration/bnest_app/push_notifications/sqlite_delivery_store_test.exs`. AC-DH-07.
- [ ] [AI] GREEN (drivers): `test/unit/support/family_chat_driver.ex` use the facade with in-memory adapters, and the
      `test/behaviour/verify.exs` allow-list loses its U10 lines. `UNIT` and `BEHAVIOUR` pass.
- [ ] [AI] REFACTOR: `LINT` and `APP_QUICK` pass.
- [ ] [AI] `INTEGRATION` passes; `FEATURE_DIFF` is empty.
- [ ] [AI] Gherkin implementation review, recorded.
- [ ] [AI] Commit, PR, leak review, gate, merge.
- [ ] [AI] **Checkpoint 10 (blocking):** U10 merged.

### Phase 11: U11, Scheduler

- [ ] [AI] RED (boundary): `lib/bnest_app/scheduler/{domain,ports,adapters}.ex`; `TYPECHECK` and the scan fail.
- [ ] [AI] RED (contract): `test/support/contracts/schedule_store_contract.ex` (claims, retries, due computation
      inputs, daily update), used by `test/unit/bnest_app/scheduler/in_memory_schedule_store_test.exs`. `FOCUS_UNIT`
      fails. AC-DH-07.
- [ ] [AI] GREEN (contract): `test/unit/support/in_memory/schedule_store.ex` until `FOCUS_UNIT` passes.
- [ ] [AI] GREEN (layers): the U11 moves. Add the `Ports.Task` behaviour; the task map and tick handlers come from
      configuration; the `*_for_test!` seams and `put_test_schedule/5` move to `test/integration/support/seeds/schedules.ex`,
      and `apps/bnest-app-fe-e2e/tests/support/scheduled-backups.ts` calls `BnestApp.Test.Seeds.Schedules`;
      `PushNotifications.Adapters.RetentionTask` declares `@behaviour BnestApp.Scheduler.Ports.Task`; `backup/run.ex` and
      `release/migrations/family_chat.ex` call `Scheduler.complete_run/4`, `skip_run/4`, `active_attempt?/3`,
      `activate_if_pristine!/2` and `registered_handler/1`;
      `AdminScheduleSettingsLive` calls only facades. `TYPECHECK` and the scan pass.
- [ ] [AI] GREEN (contract, real adapter): `FOCUS_INT test/integration/bnest_app/scheduler/sqlite_schedule_store_test.exs`
      passes. AC-DH-07.
- [ ] [AI] GREEN (drivers): `test/unit/support/home_page_driver.ex` and `test/unit/support/family_chat_driver.ex` use the facade with in-memory adapters, and the
      `test/behaviour/verify.exs` allow-list loses its U11 lines. `UNIT` and `BEHAVIOUR` pass.
- [ ] [AI] REFACTOR: `LINT` and `APP_QUICK` pass.
- [ ] [AI] `INTEGRATION` passes; `FEATURE_DIFF` is empty.
- [ ] [AI] Focused e2e for the changed support: `FE_E2E` with `-- --grep "Bnest scheduled backups"` appended.
      Proof: pass count recorded.
- [ ] [AI] Gherkin implementation review of the changed drivers and e2e support, recorded.
- [ ] [AI] Commit, PR, leak review, gate, merge.
- [ ] [AI] **Checkpoint 11 (blocking):** U11 merged.

### Phase 12: U12, Backup

- [ ] [AI] RED (boundary): `lib/bnest_app/backup/{domain,ports,adapters}.ex`; `TYPECHECK` and the scan fail.
- [ ] [AI] RED (facade): `test/unit/bnest_app/backup/backup_test.exs` covers capacity refusal, retention selection,
      receipt writing and ignore-check refusal with in-memory probes. `FOCUS_UNIT` fails.
- [ ] [AI] GREEN (layers): the U12 moves; `ScheduledBackupTask` implements `Scheduler.Ports.Task`; the handler atom in
      `config/config.exs` and the panel owner atom in `admin_config/registry.ex` follow the renames. `TYPECHECK`, the scan
      and `FOCUS_UNIT` pass.
- [ ] [AI] GREEN (drivers): `test/unit/support/home_page_driver.ex` and `test/unit/support/family_chat_driver.ex` use the facade with in-memory adapters, and the
      `test/behaviour/verify.exs` allow-list loses its U12 lines. `UNIT` and `BEHAVIOUR` pass.
- [ ] [AI] REFACTOR: `LINT` and `APP_QUICK` pass.
- [ ] [AI] `INTEGRATION` passes; `FEATURE_DIFF` is empty.
- [ ] [AI] Gherkin implementation review, recorded.
- [ ] [AI] Commit, PR, leak review, gate, merge.
- [ ] [AI] **Checkpoint 12 (blocking):** U12 merged.

### Phase 13: U13, Operations

- [ ] [AI] RED (boundary): `lib/bnest_app/operations.ex` and `lib/bnest_app/operations/{domain,ports,adapters}.ex`;
      delete the `Deployment` and `AdminConfig` legacy entries. `TYPECHECK` and the scan fail.
- [ ] [AI] RED (facade): `test/unit/bnest_app/operations/operations_test.exs` covers liveness, readiness and health
      aggregation with an in-memory `ReleaseEnvironment`. `FOCUS_UNIT` fails.
- [ ] [AI] GREEN (layers): the U13 moves. `HealthController`, `ReleaseHeaders`, `AdminSettingsLive` and
      `AdminScheduleSettingsLive` call only facades. `TYPECHECK`, the scan and `FOCUS_UNIT` pass.
- [ ] [AI] GREEN (drivers): `test/unit/support/home_page_driver.ex` use the facade with in-memory adapters, and the
      `test/behaviour/verify.exs` allow-list loses its U13 lines. `UNIT` and `BEHAVIOUR` pass.
- [ ] [AI] REFACTOR: `LINT` and `APP_QUICK` pass.
- [ ] [AI] `INTEGRATION` passes; `FEATURE_DIFF` is empty.
- [ ] [AI] Gherkin implementation review, recorded.
- [ ] [AI] Commit, PR, leak review, gate, merge.
- [ ] [AI] **Checkpoint 13 (blocking):** U13 merged; `@legacy_exports` holds no context module.

## Phase 14: U14, Closure (AC-DH-01 to AC-DH-09)

- [ ] [AI] RED: enable scan rule L3 and delete `@legacy_exports`, `@legacy_modules`, every remaining `BnestApp` dep of
      an `Adapters`, web, CLI, release or application boundary, `@legacy_records_callers` (already empty after U8), and the
      `verify.exs` allow-list. `TYPECHECK`, the scan and `BEHAVIOUR` fail if anything remains.
      Record the result; an immediate pass is recorded as such.
- [ ] [AI] GREEN: resolve any remainder. `TYPECHECK`, the scan and `BEHAVIOUR` pass. AC-DH-02, AC-DH-04, AC-DH-06.
- [ ] [AI] Forbidden-edge proof: for each AC-DH-03 example row in turn, add the call to the caller's file in the
      worktree, run `TYPECHECK`, record the boundary warning naming both modules, then
      `/usr/bin/git restore <that file>`. Proof: four recorded failures and a clean `git status`. AC-DH-03.
- [ ] [AI] `grep -rnE "_for_test|put_test_" apps/bnest-app/lib` prints nothing; `FEATURE_DIFF <U1 base>` prints nothing.
      AC-DH-08, AC-DH-09.
- [ ] [AI] Record schema proof: `FOCUS_UNIT test/unit/bnest_app/storage/domain/record_schema_test.exs` passes with its
      assertions unchanged since U4, and `BEHAVIOUR` passed above, which reads and writes every record kind. Supporting
      value check: `/usr/bin/git grep -hoE '"schemaVersion" => [0-9]+' <U1 base> -- apps/bnest-app/lib | sort -u` prints
      the same set as the same command at `HEAD` (whitespace and counts are excluded by `-o` and `-u`). AC-DH-09.
- [ ] [AI] `APP_QUICK`, `INTEGRATION`, `REPO`, `BE_COVERAGE` and `FE_COVERAGE` pass. AC-DH-08.
- [ ] [AI] `BE_E2E` and `FE_E2E` for the affected states (storage, identity, family chat, push, scheduler/backup admin,
      Codex chat, SifatAllah) at the exact local origin, with LiveView awaited and isolated `test-user-` identities. Proof:
      pass counts. AC-DH-08.
- [ ] [AI] Manual `curl`, per [API testing](../../../repo-governance/development/api-testing.md), against a local test
      server on a leased development port with an isolated run root, once with a `test-user-` session and once
      unauthenticated where authentication applies: `GET /health/live`, `GET /health/ready`, `POST /login`,
      `DELETE /logout`, `POST /setup`, `PUT /preferences/theme`, `GET /family-chat`, `GET /family-chat/:slug`, and
      `POST /api/graphql` for the family chat rooms, room and messages queries, the send mutation, the four Web Push
      operations, and the subscription handshake. Proof: per operation, the status, content type, response shape and
      side effect (for example, `DELETE /logout` disabling the session's push subscription) recorded, each matching what
      the route's existing integration test asserts. AC-DH-08.
- [ ] [AI] Manual UI inspection of every thinned LiveView at the exact local origin and the standard viewports, with
      spec-aware and spec-blind
      [exploratory passes](../../../repo-governance/workflows/exploratory-and-usability-testing.md) recorded in separate
      `learnings.md` sections. Expected: no visible change. AC-DH-08.
- [ ] [AI] C4 update of `specs/apps/bnest/app-be/architecture.md` per
      [007](tech-docs/007-specification-changes.md): the Component View nodes and relationships, the prose under it, and
      the Architectural Constraints entries named there, synchronized with the as-built code. Proof: `REPO` (Mermaid,
      links) exits 0, and every component node names a facade that exists in `apps/bnest-app/lib`.
- [ ] [AI] Rules propagation for any rule changed during execution; record the terminal result.
- [ ] [AI] Update `apps/bnest-app/README.md` (architecture section) and `docs/explanation/hexagonal-architecture.md`
      (as-built map); run docs propagation and record the result.
- [ ] [AI] Stop every non-production server, watcher and proxy started during execution. Proof: `lsof` on ports
      `4010`–`4039` is empty.
- [ ] [AI] Commit, PR, leak review, gate, merge `refactor(bnest-app): complete hexagonal architecture adoption`.
- [ ] [AI] **Checkpoint 14 (blocking):** U14 merged; every AC except AC-DH-10 is met with evidence.

## Phase 15: Production Release (AC-DH-10)

Run per [005](tech-docs/005-release-continuity-and-rollback.md), from the primary checkout.

- [ ] [AI] Reconcile the primary checkout `main` to `origin/main`. Proof: `0 0` divergence and a clean tree.
- [ ] [AI] Load the machine-local deploy environment (paths only) and read the active slot's flag mode.
- [ ] [AI] Free the inactive slot (Phase 0 found both `4000` and `4001` listening). Identify the routed slot with
      `proxy:status` and the routed `/health/ready` revision and port. If exactly one slot is routed and the other is not,
      run `rtk ./hippo run --class transactional --resource-tier light --disk-path . -- npm exec -- nx run -p bnest-app -t
deploy:retire -- --slot <unrouted colour>` once, then `lsof -nP -iTCP:4000 -iTCP:4001 -sTCP:LISTEN` shows only the
      routed slot. If routing is ambiguous or the retire fails, stop the release and report to the owner. Never retire
      the routed slot. Proof: the routed colour, the retired colour (or "already free"), and the listener check.
- [ ] [AI] Preflight: `proxy:status`, readiness local and routed, 12 exact-origin samples within budget, a
      representative journey, `./hippo status` normal, inactive slot free. Proof: sample summary recorded.
- [ ] [AI] Start the background exact-origin sampler.
- [ ] [AI] `release:run -- --revision <closure-sha>`. Proof: `outcome: passed`.
- [ ] [AI] Experience re-promotion, only if the active mode had the flags on. Proof: `outcome: passed`, or "not
      applicable" with the recorded mode.
- [ ] [AI] Routed proof: Caddy and Tailnet `/health/ready` revision equal the closure SHA; synthetic LiveView connected;
      its JSON reports `reconnected: true`, per [005](tech-docs/005-release-continuity-and-rollback.md) step 8; sampler
      budget met.
- [ ] [AI] Drain and cleanup: one slot listening, no release worktree, sampler stopped.
- [ ] [AI] **Checkpoint 15 (blocking):** AC-DH-10 met.

## Recovery and Rollback

These items stay unticked unless their trigger fires. Each is resolved at reconciliation with a dated `Not triggered`
disposition and evidence.

- [ ] [AI] Trigger: a unit's merged revision fails a gate on `main`. Action: revert the merge through a pull request,
      then diagnose on a new branch.
- [ ] [AI] Trigger: candidate health, revision, LiveView or routed proof fails during the release. Action:
      `npm exec -- nx run -p bnest-app -t deploy:rollback`, then diagnose.
- [ ] [AI] Trigger: a responsiveness sample fails or the budget is exceeded during promotion or drain. Action:
      `deploy:rollback` immediately, then re-verify the journey and budget.
- [ ] [AI] Trigger: a post-drain defect. Action: request the owner's confirmation and re-release the previous revision.

## Archival

- [ ] [AI] Resolve every `learnings.md` entry to a durable owner or a reasoned discard.
- [ ] [AI] Report the `family-learning-engine` backlog conflict to the owner in the completion summary (it plans
      against `sifat_allah_live.ex` and `application.ex` as they were before this plan). This plan does not edit
      another plan. Proof: the `learnings.md` entry resolved as "routed to the owner".
- [ ] [AI] Run the [plan execution check](../../../repo-governance/workflows/plan-execution-check.md) through
      `plan-execution-checker`, and record its verdict in `learnings.md`.
- [ ] [AI] Move the plan to `plans/done/<completion-date>__ddd-hexagonal-adoption/`; update `plans/in-progress/README.md`,
      `plans/done/README.md` and every live link; run `REPO` from the archived state.
- [ ] [AI] Commit `docs(plans): archive ddd and hexagonal architecture adoption`; PR, leak review, gate, merge.
- [ ] [AI] Apply [dev artifact clean-up](../../../repo-governance/workflows/dev-artifact-clean-up.md). Remove this
      worktree and its local and remote branches once nothing is unpushed or running, and reconcile the primary checkout's
      `main` to `origin/main` (`0 0`).
