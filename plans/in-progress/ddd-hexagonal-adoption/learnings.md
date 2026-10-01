# Learnings: DDD and Hexagonal Architecture Adoption

This file holds two kinds of entry until archival:

- decision records from the planning gates and from execution;
- discoveries made while executing.

Every entry is resolved before archival. It is either promoted to one durable owner or discarded with a reason.

## Pre-Write Decision Gate (2026-10-01)

The gate ran in two rounds with the repository owner: one before the session plan, one before authoring. Each round
presented mutually exclusive options with one recommendation and kept an open alternative available.

| ID  | Branch               | Options presented                                                                | Selected                                                     | Reason                                                                              |
| --- | -------------------- | -------------------------------------------------------------------------------- | ------------------------------------------------------------ | ----------------------------------------------------------------------------------- |
| D1  | Scope before release | standard + pilot context (recommended); standard + full migration; standard only | **Standard + full migration**                                | Owner's choice: the goal is full adoption, not a demonstration                      |
| D2  | Formal plan          | formal plan (recommended); session plan only                                     | **Formal plan, written directly under `plans/in-progress/`** | Owner asked for the "megaplan" first; explicit request satisfies plan authorization |
| D3  | Enforcement          | `boundary` library (recommended); in-repo xref test; review only                 | **`boundary`**                                               | Compile-time, export-aware, and already fails the existing warnings-as-errors gate  |
| D4  | Layering depth       | Domain/Ports/Adapters sub-boundaries (recommended); context-level only           | **Sub-boundaries**                                           | Hexagonal layering only means something if it is enforced inside a context          |
| D5  | Unit doubles         | in-memory adapters + contract suites (recommended); keep SQLite at unit          | **In-memory + contract suites**                              | Isolates the unit layer without letting fakes drift                                 |
| D6  | Pull-request units   | one PR per coherent unit (recommended); a single PR                              | **Per unit**                                                 | Follows pull-request boundaries: each context is independently shippable            |
| D7  | Naming               | `CodexChat` merge (recommended); keep names                                      | **`CodexChat`**                                              | Removes the Chat/FamilyChat ambiguity from the ubiquitous language                  |

## Decisions Made While Authoring

| ID  | Decision                                                                                                                                                                                                                                                                                                   | Reason                                                                                                                                                   |
| --- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| D8  | `DataRepository` and `Storage.*` form one `Storage` context                                                                                                                                                                                                                                                | They depend on each other (`StorageCoordinator` ↔ `Storage.Config`/`Migration`). Two boundaries would encode a cycle                                     |
| D9  | Storage validates context-owned record kinds through a `RecordKind` port registered in configuration                                                                                                                                                                                                       | Removes the `DataRepository.Schema` → `Chat`/`SifatAllah` compile edge without moving schema knowledge away from the context that owns it                |
| D10 | Contexts migrate foundations first (Storage, then Identity, …, Operations last)                                                                                                                                                                                                                            | Each consumer then migrates once, onto its provider's final facade                                                                                       |
| D11 | Scheduler reaches tasks and tick handlers through configuration                                                                                                                                                                                                                                            | Breaks the Scheduler ↔ PushNotifications/Backup cycle that a compile-time registry would create                                                          |
| D12 | `Release.Migrations.*`, `SqliteRepo`, `PubSub`, `Endpoint`, record kind atoms, routes, GraphQL names, SQL, the `Identity` facade functions the be-e2e steps evaluate (`bootstrap`, `setup_status`, `login`, `current_user`, `logout`), and the application env keys set in `config/runtime.exs` are frozen | They are external contracts (deploy-tool and e2e eval, Ecto config and priv path, client contracts, stored data, production environment)                 |
| D13 | Only the closure revision is released                                                                                                                                                                                                                                                                      | One production change proves the whole architecture. Intermediate `main` states stay deployable, so this is a sequencing choice, not a safety dependency |
| D14 | Mock frameworks rejected                                                                                                                                                                                                                                                                                   | Hand-written in-memory adapters follow the existing `MemoryBackend` pattern and need no new test dependency                                              |

## Post-Write Decision Gate (2026-10-01)

These questions were asked of the owner on the complete draft, before the quality gate.

| ID  | Branch the draft revealed              | Options presented                                               | Selected                    | Consequence                                                                                                                                                                                                          |
| --- | -------------------------------------- | --------------------------------------------------------------- | --------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| D15 | Release cut                            | closure revision only (recommended); release after each context | **Closure only**            | Confirms D13                                                                                                                                                                                                         |
| D16 | The `DataRepository` ↔ `Storage` cycle | one Storage context (recommended); two contexts plus a port     | **One Storage context**     | Confirms D8                                                                                                                                                                                                          |
| D17 | Owner of the per-user theme preference | Identity facade (recommended); a new Preferences context        | **New Preferences context** | Owner overrode the recommendation. The plan gained U6 (Preferences), and every later unit and phase shifted by one. Theme is a household-member preference, not an identity concern, and more preferences may follow |

## Plan Quality Gate

**Run 1 (2026-10-01): `FAIL`, reason `BLOCKED_INPUT_CHANGED`.** The draft changed while the checker read it (the E1
topology rewrite, directory maps, and removal of machine paths). The checker still reported seven blocking and ten
non-blocking findings against the current files. Repair cycle 1 resolved each one:

| Finding                                                                                                      | Resolution                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| ------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| B1 checkpoints unlabeled                                                                                     | Every checkpoint carries `[AI]`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| B2 "empty migration set" is false (`release.mjs` declares `bnest-persistent-schedules-v1` in every manifest) | AC-DH-09, README, BRD and 005 now require the migration set and `migrationSetChecksum` to equal the base revision's                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| B3 e2e support evaluates renamed modules                                                                     | 006 lists the four e2e support files under U4 and U11; those phases edit them and run a focused e2e; D12 freezes the `Identity` facade functions the be-e2e steps evaluate; scope text corrected                                                                                                                                                                                                                                                                                                                                                                                                               |
| B4 U3 GREEN impossible without infrastructure deps                                                           | 003 tables the temporary `BnestAppWeb`/`BnestAppCli` deps and the unit that removes each; the U3 proof now targets a fresh strict boundary; the `StorageLive` → `SqliteRepo` row moves to U14                                                                                                                                                                                                                                                                                                                                                                                                                  |
| B5 C4 change lacks the specification-change shape                                                            | New [007](tech-docs/007-specification-changes.md): durable-versus-plan-only dispositions and a `diff` delta; the Phase 14 task names its elements and proof                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| B6 File Impact inexact                                                                                       | Tests section rewritten per unit with exact paths (no globs, conditionals or unnamed users); `StorageCoordinator` placed as an adapter; U15 date template defined                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| B7 combined RED/GREEN and unnamed tests                                                                      | Unit guard split; contract and driver items name exact files                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| N1–N10                                                                                                       | Status ticked with evidence; six names and a six-name proof; L1 and AC-DH-04 aligned, covering `Ecto.Migrator` and `Ecto.UUID`; `PersistentSchedules` keeps its migrator under `BnestApp.Release` deps; per-test adapter handles stated; `put_test_schedule/5` included in the seam grep; `HARNESS` command named; resume uses a merge, not a force push, with `/usr/bin/git`; active service recorded in Phase 0, and reconnect proven by `verify-liveview.mjs` plus the fe-e2e promotion scenario; `BE_COVERAGE`/`FE_COVERAGE`, `FEATURE_DIFF <base>`, the `PreferenceStore` row and AC-DH-07 examples added |

**Run 2 (2026-10-01), cycle 1: `FAIL`.** The draft stayed frozen. `rhino-consumer:test:repo` exited 0. Every run-1
finding was verified fixed except B6 (partial, folded into F1). The run raised four blocking and twelve non-blocking
findings, all repaired:

| Finding                                                                     | Repair                                                                                                                                                                                                                         |
| --------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| F1 Storage's published API is unnamed, and U4's broken callers are unlisted | 002 names the facade functions that replace every coordinator, config, lock and repository call; 006 lists all 18 callers under U4; Phase 4 GREEN (layers) names both                                                          |
| F2 AC-DH-09 unprovable                                                      | `FEATURE_DIFF` covers `apps/bnest-app/tools`; 007 states why an empty diff implies an equal checksum; a U4 characterization test pins every record kind's `schemaVersion`, and Phase 14 re-proves it with a literal comparison |
| F3 no fallback for an occupied inactive slot                                | Phase 15 identifies the routed slot, retires only an unrouted one once, and otherwise stops and reports                                                                                                                        |
| F4 REST curl evidence missing                                               | Phase 14 curls every affected REST route and GraphQL operation, authenticated and unauthenticated                                                                                                                              |
| N1, N7 missing and reversed edges                                           | Identity → PushNotifications through a `SubscriptionRevoker` port; PushNotifications → Scheduler through `Ports.Task`; 007 direction corrected; U10/U11 file entries added                                                     |
| N2 root deps and cycles                                                     | Facades never list `BnestApp`; only `Adapters` boundaries may, so no cycle can form; root deps grow and shrink per unit                                                                                                        |
| N3 boundary table rows                                                      | `Jason` listed by the Storage facade and domain as a pure library; `SqliteRepo` lists its `Ecto` boundaries                                                                                                                    |
| N4 `Storage.Records` from web                                               | Rule L4 and AC-DH-05 forbid it; the U6 RED expectation restated                                                                                                                                                                |
| N5 contract proofs before the move                                          | Each real-adapter `FOCUS_INT` is a separate item after GREEN (layers)                                                                                                                                                          |
| N6 scratch-copy proofs                                                      | Edge proofs run in the worktree, then `git restore`                                                                                                                                                                            |
| N8 ports                                                                    | Cleanup proof covers `4010`–`4039`                                                                                                                                                                                             |
| N9 list agreement                                                           | Exports are a subset of modules                                                                                                                                                                                                |
| N10 harness                                                                 | Always regenerate and commit; 001 and 006 aligned                                                                                                                                                                              |
| N11 "SQL helper"                                                            | Removed                                                                                                                                                                                                                        |
| N12 backlog conflict                                                        | README dependency note; archival flags `family-learning-engine` for re-planning                                                                                                                                                |

**Run 2, cycle 2 (stabilization).** Verification of cycle 1 found F1, F3, F4, N1, N3, N5, N7–N11 fixed and seven
repair-caused gaps, each repaired once:

| Finding                                                                                | Repair                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| -------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| S1 moved modules in U8–U12 still called by name from other contexts and from `Release` | 002 names facade functions for every caller (`CodexChat.child_specs/0`; FamilyChat `ensure_ready!/0`, `canonical_room/0`, `insert_message!/6`, `migrate!/0`; Scheduler `complete_run/4`, `skip_run/4`, `active_attempt?/3`, `activate_if_pristine!/2`, `registered_handler/1`); the PushNotifications switch moves to U9; each caller is `[E]` in 006 and named in its GREEN (layers) item; handler and panel atoms are recorded as data guarded by integration tests |
| S2 L4's `Storage.Records` ban against U4's caller moves                                | Temporary `@legacy_records_callers` allow-list, emptied by U6–U8, required empty at U14; U6, U7 and U8 RED items remove their entries                                                                                                                                                                                                                                                                                                                                 |
| S3 a grep proof that fails falsely                                                     | AC-DH-09's version clause rests on the characterization test and `BEHAVIOUR`; a value-only `git grep -o …                                                                                                                                                                                                                                                                                                                                                             | sort -u` comparison supports it |
| S4 `rtk` with `/usr/bin/git` refused                                                   | Git runs as plain `/usr/bin/git`, stated in the Commands paragraph                                                                                                                                                                                                                                                                                                                                                                                                    |
| S5 the no-cycle argument contradicted itself                                           | Restated as a path argument over declared deps                                                                                                                                                                                                                                                                                                                                                                                                                        |
| S6 005 lacked the slot step                                                            | Added to 005 step 4                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| S7 an edit to another plan                                                             | Dropped; the conflict is routed to the owner at completion                                                                                                                                                                                                                                                                                                                                                                                                            |

**Verdict (2026-10-01): `PASS_WITH_FINDINGS`**, within the two-cycle limit. HEAD `7e23669c9`; draft frozen;
`rhino-consumer:test:repo` exit 0 with all eight gates passing. Two non-blocking findings, both accepted and applied
when their items execute, without editing the gated snapshot:

1. 005 step 4 combines "free the inactive slot" with preflight. Accepted: Phase 15 runs them as its two separate items
   in order, and archival splits the step and renumbers the step references.
2. The Phase 14 supporting value check misses `@schema_version` attributes. Accepted: Phase 14 also compares
   `/usr/bin/git grep -hoE '@schema_version [0-9]+' … | sort -u` between the base and `HEAD`.

## Execution Log

_(Append dated entries: discoveries, surprises, deviations, and Gherkin implementation reviews.)_

### E1: `boundary` prototype changed the topology (2026-10-01, during authoring)

A throwaway Mix project (`local-tmp/ddd-hexa/proto/`, `boundary` 0.11.0, Elixir 1.18) compiled three layouts:

1. **Nested strict context with an `Adapters` sub-boundary.** The compiler refused `Adapters` listing `SqliteRepo` or
   `Jason`: "can't be listed as a dependency because it's not a sibling, a parent, or a dep of some ancestor". Listing
   is limited to the dependencies of ancestors up to the first strict ancestor. The facade would therefore have to list
   `SqliteRepo` itself, which defeats the layering.
2. **A top-level `Adapters` beside a nested context.** It could not list the nested context, because a top-level
   boundary may depend only on other top-level boundaries.
3. **A top-level strict facade (with `Domain` and `Ports` sub-boundaries) plus a top-level strict `Adapters`.** It
   produced exactly the intended warnings:
   - facade → `Repo`, `Jason` and adapters;
   - domain → adapters;
   - another context → adapters;
   - web → adapters and `Repo`.

   No allowed edge warned. The standard library (`DateTime.utc_now`) is never checked, which confirms that the
   layering scan is needed for L1 and L2.

[002](tech-docs/002-target-architecture-and-context-map.md) and [003](tech-docs/003-boundary-enforcement.md) were
rewritten to layout 3 before the quality gate. Resolution: promote to the governance standard's Elixir mapping (U2),
which is the durable owner.

### E2: No word budget left for the `AGENTS.md` line or a map row (2026-10-01, U2)

`main` sits at about 749 of the 750 counted words in `AGENTS.md` and 748 in `software-quality-enforcement.md`, and the
counter also counts the words of link paths. The shortest linked `AGENTS.md` bullet cost 11 words, and the smallest
map change (a link folded into the typecheck row) cost 9. Trimming other rules to make room is outside the
rules-propagation ledger, so U2 adds neither. The standard stays reachable and truthfully enforced without them:

- the `developing-applications` skill and the three `swe-code-*` agents link it where code placement is decided;
- `repository-adapter.md` records the `boundary` adopter decision and its `typecheck` route;
- the map's existing typecheck row stays true, because `boundary` violations are compiler warnings, and
  `--warnings-as-errors` already fails on them from U3.

Resolution: accepted deviation from the U2 delivery item; the plan-execution checker reads it here.

### E3: U3 boundary tooling findings (2026-10-01)

- **The legacy root needs infrastructure deps.** The `default: [check: [apps: …]]` setting applies to the relaxed root
  as well, so its legacy modules' direct calls to `Argon2`, `Ecto.Migrator`, `Ecto.Query`, `Ecto.UUID`, `Exqlite`,
  `Req` and `WebPush` failed. [003](tech-docs/003-boundary-enforcement.md) tabled only the inbound adapters' temporary
  deps. The root now lists them under a `legacy:` comment, and each leaves with its last legacy caller.
- **Evidence beat the tabled callers.** `BnestAppCli` never names `BnestApp.SqliteRepo`, so it does not list it.
  `BnestApp.Release` calls `FamilyChat.Store` and `Scheduler.Policy`, so both are legacy exports. `BnestApp.SqliteRepo`
  lists `Ecto.Repo`, `Ecto.Adapters.SQL` and `Ecto.Multi`.
- **`FOCUS_INT` lacked `--exclude integration-exempt`.** Without it, a focused run also executes the four exempt
  scenarios and fails on them. The canonical command now carries the flag that `test:integration` uses.
- **The scan skips `use Boundary`.** A boundary declaration names dependencies without calling them.
- **Unit guard lines.** The SQLite lines sit in `backup_restore_test.exs`, `family_chat_test.exs` and the unit
  family-chat driver, not the home-page driver.

Resolution: applied in U3; 003 stays as authored, and this entry records the as-built difference.

### E4: U4 Storage as built (2026-10-01)

- **More adapters than 006 lists.** The flat-to-SQLite run became pure `Domain.FlatMigration` plus the
  `SqliteMigration` adapter. `Adapters.LocalMaintenance` implements the `Maintenance` port by delegating to the
  migration, relocation, retirement and cleanup adapters. `Adapters.SchemaAudit` holds the audit that left
  `RecordSchema`.
- **`RecordKind` names its own key and source.** Besides `record_type/0`, `valid?/1` and `normalize/1`, each kind
  exports `kind/0` and `source/0`, so `RecordSchema` and `Normalizer` find it without a table. The two kinds live
  in their owners' trees: `CodexChat.Adapters.TranscriptRecordKind` and `SifatAllah.Adapters.ProgressRecordKind`.
- **No backend fallback.** `Ports.RecordBackend` dispatches only through the store's `backend` field. Every store
  now carries one, so the test of the old flat-store fallback was dropped.
- **The pointer rule is application logic.** `persist_directory/1,2` (write once, then `:immutable`) sits in the
  facade over the `ConfigStore` port; the adapter only reads, validates and writes.
- **Agent-backed doubles.** The non-record port doubles share one agent started by `StoragePorts.install/1`, and the
  import test's failing backend keeps its failure list in an agent. The unit guard forbids `Process.`, so the first
  process-dictionary version failed `BEHAVIOUR`.
- **The migration identifier is domain.** Tests read `FlatMigration.migration_id/0`; the adapter has none.
- **`HealthController` keeps `SqliteRepo`** for its readiness query until U13, and stays in `@legacy_modules`.
- **The RED (boundary) output was not kept** before the callers moved. It was reproduced after GREEN with a
  temporary probe; delivery records both outcomes.
- **Gherkin implementation review.** An agent reviewed the changed drivers, the in-memory backend and the e2e
  support: 101 rows (unit 20, integration 67, e2e 14), with 84 PASS, 7 EXEMPT and 10 FAIL. No FAIL came from
  the refactor, and no changed function asserts less than on `origin/main`. All 10 FAIL rows predated U4: each
  Then read a driver literal, a map the driver built, or a tautology. The scenarios were setup warning (unit,
  integration), unsafe folder (unit), deterministic inventory (unit), SQLite authority (unit, integration),
  browser key cleanup (unit, integration), managed default without storage UI (integration) and the
  Dropbox-synced backup default (integration). U4 fixed all ten in the drivers without production, feature or
  step changes. Each Then now reads evidence from production code, and each was seen failing against a
  deliberately broken production path. Synthetic usernames gained the `test-user-` prefix.
- **Left for later units.** `identity_test.exs` keeps two unprefixed synthetic usernames (U5). The unit backup
  default and the unit storage-UI visit count still use driver literals (U12, U13). Comments in
  `experience-release.steps.ts` and `family_chat.feature` still name `StorageCoordinator`, and `FEATURE_DIFF`
  forbids touching them inside this plan.

Resolution: applied in U4; 006 stays as authored, and this entry records the as-built difference.
