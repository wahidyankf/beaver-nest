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

### E5: U5 Identity as built (2026-10-01)

- **The scan had nothing to fail on.** No Identity module broke L1, L2 or L4 before the move, so the boundary RED is
  `TYPECHECK` alone: 18 forbidden references over 4 edges.
- **The port came before the contract RED.** The contract dispatches through `Ports.IdentityStore`, so the port
  existed first and the RED is the missing in-memory adapter.
- **`Domain.Credentials` is new.** The username and password rules left `FileStore` and `CredentialVerifier` for a
  pure module that 006 does not list. Its tests sit in `authorization_test.exs`, the path 006 names for the domain.
  Bootstrap checks the password rule before hashing, so the hashers no longer validate; outcomes are unchanged.
- **More port callbacks.** `IdentityStore` adds `new/1` (the facade builds the active handle over
  `Storage.active_store()`), `empty?/1` (false over the routed repository, as before) and `lock_key/1`; production
  bootstrap lock keys are unchanged.
- **Unit adapters come from configuration.** The unit branch of `config/test.exs` selects in-memory hasher,
  notifier and revoker doubles, as 004 says. The identity store stays record-backed, because the unit SQLite-migration
  scenario reaches identity records through Storage. This differs from U4, whose unit tests install doubles per test.
  Integration and both e2e servers run with `BNEST_TEST_LAYER=integration`, so they keep real Argon2.
- **`EndpointSessionNotifier` names `BnestAppWeb.Endpoint`**, which adds no boundary cycle. No test covered the
  logout disconnect broadcast, so U5 added one at the integration layer.
- **Two facade specs dropped.** `bootstrap/2` and `setup_status/1` have no `@spec`; with one, dialyzer flags a
  `BootstrapController` clause as unreachable, and the controller is unchanged.
- **No SQLite contract user.** Production never builds an identity store over a bare SQLite backend.
- **More synthetic usernames renamed** to the `test-user-` form than E4 listed.
- **Manual `curl` of login, logout and setup is deferred to U14**, where closure exercises the served origin; U5
  proves those routes through integration and the focused e2e runs.
- **Gherkin implementation review.** 23 rows (unit 10, integration 13), with 21 PASS and 2 FAIL. Neither FAIL came
  from the refactor. The unit "no plaintext password" outcome no longer checks the Argon2id prefix, because the unit
  hasher is a double. The review accepted it: unit still reads the stored verifier and verifies it through the
  configured hasher, and integration still proves Argon2id.
- **The two FAIL rows predated U5, and U5 fixed them in the drivers.**
  - The unit identity-retirement step deleted the records itself. It now retires through `Storage.retire/3`, whose
    in-memory maintenance double applies the real adapter's checks.
  - The unit settings-denial Thens read literals. They now route requests through the real router and a recording
    record store.
- **Three more fixes on the logout proof.** The integration two-browser and logout scenarios and the unit redirect
  scenarios had literal or flag-selected outcomes. Their Thens now make real requests with each browser's cookie and
  measure record access. The unit logout path also asserts the revoke and disconnect calls.
- **The in-memory identity store's `new/1` raises.** Configuring it as the active store would silently start empty.
- **Fix evidence.** Each fix was seen failing against a deliberately broken production path, and production code
  did not change.
- **Left for the closure review.** The unit relocation and legacy-retirement steps, the unit storage-settings route,
  and the E4 items still build results from literals. They predate this plan, and U14's full-corpus review is the item
  that clears them.

Resolution: applied in U5; 006 stays as authored, and this entry records the as-built difference.

### E6: U6 Preferences as built (2026-10-01)

- **`put_theme/3` takes the request time.** The third argument is `now`; the controller passes `DateTime.utc_now/0`,
  so the facade and domain stay free of clock calls. Choosing `"system"` delegates to `clear_theme/1`, so the
  controller makes one call.
- **An optional `store:` handle** on `theme`, `put_theme` and `clear_theme` lets unit tests pass an in-memory store,
  as 004 describes. Without it the facade uses the configured store's `new/0`, which wraps the routed
  `Storage.Records`, exactly what both callers read before.
- **`themes/0` feeds the controller guard**, so an unknown theme still answers 422 before authorization.
- **The facade exports only `Ports`.** No caller outside the context needs the domain.
- **Unit configuration keeps the record-backed store.** The unit drivers' routed requests and the restart journey
  read the theme through `Records`, as U5's identity store does.
- **The theme integration test keeps its record assertions** and adds a second write at revision 1 and read-backs
  through `Preferences.theme/1`.
- **Manual `curl` of `PUT /preferences/theme` is in U14**, with the other routes.
- **The Gherkin review found 3 FAIL rows already on `main`.** None came from U6.
  - Unit and integration "Accepted browser import persists future changes only on the server" never made a future
    change. Both drivers now send `PUT /preferences/theme` through the router and check the server record, the facade
    read-back and the server-storage attributes on `GET /`.
  - BE e2e "SQLite becomes authoritative only after complete verification":
    - it now writes a session and a theme after the switch and proves the rollback flat reader accepts them;
    - it retires the flat identity sources through production `Storage.retire/3` instead of `rmSync`;
    - it reads chat, learning and theme back after the restart;
    - it cleans up in an `After` hook.
  - Each new Then was proved to fail against a temporary product mutation.
- **`FEATURE_DIFF 41c69e7ae` is not empty for U6.** The e2e fix moves scenario 7 out of
  `sqlite_storage_cli.steps.ts` into `sqlite_storage_authority.steps.ts`, to keep within the 300-line step-file budget.
  No feature file changed, so AC-DH-08 holds. From U6 on, `FEATURE_DIFF` may list step bindings that a Gherkin review
  required, and this log must name each one; feature files must still not change.
- **`mix bnest.storage.retire` cannot retire after in-place activation.** It requires `--generation`, but a pointer
  activated in place and never relocated has no `databaseGeneration`, so the task always reports
  `:generation_mismatch`. The e2e step calls `Storage.retire/3`, which the task wraps. Changing the task is a product
  decision outside this structural plan; it is raised with the user at U14.

Resolution: applied in U6; 002 and 006 stay as authored, and this entry records the as-built difference.

### E7: U7 SifatAllah as built (2026-10-01)

- **No `record_answer` in the facade.** Recording an answer is a pure progress change, `Domain.Quiz.record_answer/4`,
  which `SifatAllahLive` already calls through the exported domain before saving. A facade version would either only
  delegate or merge answering with saving, which would change the LiveView's flow.
- **A new `Domain.ProgressRecord`**, which 006 does not list, builds the `sifat-allah-progress` record and its expected
  revision, as `Preferences.Domain.Theme` does for the theme. `Domain.Quiz` stays unchanged, and
  `ProgressRecordKind.record_type/0` reuses it.
- **The port takes a handle first.** `ProgressStore` has `new/0`, `read/2` and `write/4`, following 004 and
  `PreferenceStore`. It has no removal, because a reset writes a fresh revision.
- **The facade reads the clock by default.** `save_progress/3` keeps the arity that 002 and the delivery item name. An
  optional `now:` and `store:` override the clock and store; the domain stays clock-free. This differs from E6, where
  `put_theme/4` takes `now` as an argument.
- **The facade test uses `InMemory.ProgressStore`**, not the in-memory record backend: the unit layer may not name
  `RecordProgressStore`. One non-async test drives the configured store over `Records` on `InMemory.RecordBackend`
  and checks the exact record, a revision-1 save and a stale save.
- **The facade exports `Domain` and `Ports`**, because `SifatAllahLive` renders with `Quiz`.
- **Unit configuration keeps the record-backed store**, as in U5 and U6: the unit SQLite-migration journey reads
  `:sifat_allah` through `Records`.
- **The integration driver reads persisted progress through `SifatAllah.load_progress/1`.**
  `centralized_persistence_test.exs` still reads `Records` directly, because it pins the stored record format.
- **No contract suite.** 004 lists `ProgressStore` as a thin mapping without one.
- **No manual `curl`.** U7 changes a LiveView only; no REST or GraphQL operation changed.
- **The Gherkin review found 16 FAIL rows (82 rows: 62 PASS, 4 EXEMPT).** The U7 diff introduced none.
  - 13 unit rows fell under U7's driver item. The unit driver copied `SifatAllahLive`'s transitions and feedback
    literals, and its reload never read anything back. It now mounts the real LiveView on a bare socket over in-memory
    `Records`. It sends the real events and the auto-advance message, and reloads by remounting. The reload is checked
    against the stored record and `load_progress/1`.
  - Integration and FE e2e "reinforcement after every pair" seeded progress the server ignores. Both now seed through
    `save_progress` and check "120 dari 120 soal sudah hafal" in the Given.
  - The integration exemption on "A quiz locks one answer and moves on automatically" was invalid: the lock and the
    timer are server-side. The tag and its comment are removed. The driver now waits for the real timer instead of
    clicking `next-question`, and the RED is in the log.
  - Both lock checks now also require locked buttons to be present; before, they passed when no buttons rendered.
  - Each new Then was proved to fail against a temporary product mutation.
- **A feature file changes: `sifat_allah.feature` loses one `@integration-exempt` tag and its comment.** No scenario
  or step text changes. AC-DH-08 now says "no scenario or step text has changed", and permits only
  review-invalidated exemption tags listed here; this is the first.
- **A test that depended on run order surfaced.** With the scenario no longer exempt, the integration order changed for
  a given seed. `AdminSettingsLiveTest` "reject invalid fields independently" then failed: it hard-coded revision `1`
  and time `02:00`, which an earlier schedule test can change. The test now submits the rendered revision and compares
  against the time it read first. It passes with the failing seed `964352`.

Resolution: applied in U7; 002 and 006 stay as authored, and this entry records the as-built difference.

### E8: U8 CodexChat as built (2026-10-02)

- **The facade carries what `ChatLive` orchestrated.** Its functions are:
  - `models/0`, `model_access/1` and `reasoning_effort/1,2`;
  - `open_conversation/3`, `replace_conversation/4` and `recover_pending_turn/1`;
  - `send_prompt/4`, `close/2` and `apply_event/2`;
  - `load_transcript/2` and `save_transcript/4`.
    Every user-facing string moved with it byte for byte, except the repository-write fallback, which stays in `ChatLive`.
- **No clear-persistence function.** Clearing saves `Transcript.new/2` through `save_transcript`; a separate function
  would only delegate, as with E7's `record_answer`.
- **A new `Domain.TranscriptRecord`**, which 006 does not list, builds the unchanged `chat` record and its expected
  revision. `TranscriptRecordKind.record_type/0` reuses it.
- **`ChatLive` keeps no `session_adapter` assign.** Opening, sending and closing go through the configured
  `agent_session`. One failure-only path changes as a result:
  - Before, after the mount-time connect failed, clearing, changing the model or effort, or toggling repository write
    crashed the LiveView on `nil.close/1`.
  - Now the configured adapter's `close(nil)` returns `:ok` and the LiveView carries on.
  - No scenario observes either outcome. This is recorded as the one behaviour difference in U8.
- **`:codex_models` became the `model_discovery:` adapter.** `BnestApp.Test.CodexFixtureModels` implements
  `discover/1`. `ModelCatalog` lost the special case where passing `:models_runner` forced CLI discovery; its tests pass
  `discovery: CodexCliModelDiscovery` instead. The production path is the same.
- **The fixtures are renamed** `BnestApp.Test.CodexFixtureModels` and `BnestApp.Test.CodexFixtureSession`. Four
  coverage-ignore entries in `mix.exs` fell away, because existing patterns now cover them.
- **The facade exports `Domain` and `Ports`**, because `ChatLive` renders with `Transcript`, `Settings` and
  `RepositoryAccess`. `ModelCatalog` is not exported; `Deployment.readiness` names it by atom.
- **Unit configuration keeps the record-backed transcript store**, as in U5–U7. The new unit doubles
  `InMemory.TranscriptStore` and `InMemory.AgentSession` serve the facade test. There is no contract suite, as 004
  says.
- **`@legacy_records_callers` is empty.** Removing the mechanism is left to U14.
- **A timing-dependent unit failure in `UnitFamilyChatDriver` was fixed here.** Its subscription singletons (PubSub,
  endpoint, `Absinthe.Subscription`) were linked to the scenario's test process. They died asynchronously after it, so
  a later scenario could find them still registered while their tables were gone. They now start with
  `start_supervised!`, which ExUnit stops before the next test. Both failing seeds and three random seeds pass.
- **Stale reference.** `specs/apps/bnest/app-be/architecture.md` still names `BnestApp.Chat`; the U14 C4 update owns
  it.
- **The Gherkin review found 21 FAIL rows (102 rows: 77 PASS, 4 EXEMPT).** The U8 diff introduced none.
  - 11 unit chat rows fell under U8's driver item. The unit driver rendered `ChatLive` from assigns it built itself,
    with copied model lists, an effort fallback, a write flag, a driver-held saved chat and literal failure texts. It
    now mounts the real `ChatLive` over in-memory `Records` with the fixture `AgentSession`. It sends real events and
    Codex messages through controls the page renders enabled, and reloads by remounting after checking
    `load_transcript/2` against the stored record.
  - The failed-thread resume at unit and integration read a driver-built map. It now seeds a transcript on an
    unavailable thread through `save_transcript/4` and observes production's fresh-conversation alert, and the
    transcript is kept on a new thread. The alert is read from the page rendered at mount, because production reports
    the fresh conversation when it opens and clears the error on the next send.
  - The unit install row reads the rendered root layout's manifest and icon links.
  - The integration `reconnect/1` served only exempt scenarios and produced the very error they assert. It now raises,
    naming the exemption.
  - The integration interrupted import stages a real interruption with a backend wrapper that fails the first `:chat`
    write.
  - The BE e2e resume Then waits for the alert and reads the stored thread id.
  - The SQLite journey checks also require `load_transcript/2` to agree with the stored record.
  - Each new Then was proved to fail against a temporary product mutation.
- **For U14:** `config/test.exs` selects the real Codex port session whenever `BNEST_CODEX_RUNNER` has any value, so
  the selection does not fail closed. This predates U8.

Resolution: applied in U8; 002 and 006 stay as authored, and this entry records the as-built difference.

### E9: U9 FamilyChat as built (2026-10-02)

- **No `adapters:` option on the facade.** 004 describes one. Instead, the configured `InMemory.RoomStore.new/0`
  serves a named store that each test installs, so resolvers, the controller and the socket reach it without threading
  options. The facade's unit tests therefore run `async: false`.
- **`converge_after_drain!/0` is a `RoomStore` callback.** The SQLite adapter still calls `Scheduler.Store` and
  `Scheduler`, so the `FamilyChat.Adapters` boundary keeps `BnestApp` as a legacy dependency until U11.
- **`Domain.Message` absorbed the quote rules**: the quote, the 160-grapheme preview and the live sender name. The
  facade keeps `live_sender_display_name/2` as a delegate. **`Domain.Policy`** holds the safe errors and the session
  digest. **`Domain.Cursor`** only validates; paging stays in the adapters.
- **`SqliteRoomStore.new(database_path:)`** lets the real-adapter contract run on an isolated database.
- **`MessagePublisher.publish/2` takes the topic**, which the facade computes. The GraphQL types alias `Domain.Message`.
- **Release evals restore the production adapters.** The migration test runs its evals in the unit layer, which would
  select the in-memory adapters, so each eval first puts the production adapters back.
- **The in-memory store has test seams** (`put_room/3`, `put_subscription/2`) and readers (`deliveries/1`,
  `convergences/1`), because subscriptions belong to PushNotifications.
- **Store-level unit tests moved into the `RoomStore` contract**, which runs against both adapters. Refusals raise in
  both, with different exception types, so the contract only asserts that something is raised.
- **`UnitFamilyChatDriver` writes through the facade into an in-memory store installed per scenario.** Clauses that
  need push delivery, scheduler or backup SQLite state still select SQLite through
  `test/unit/support/legacy_sqlite_room_store.ex`, under allow-list lines labelled U10–U12.
- **A U4 regression surfaced in a focused e2e run.** U4 changed the storage panel's owner from the removed
  `BnestApp.Storage.Config` to `BnestApp.Storage`, so its rendered `data-config-owner` changed. FE e2e "Discover typed
  admin configuration" had failed on `main` since then, because U4's focused e2e did not include
  "Bnest scheduled backups". The owner is the Storage context, which validates and saves nothing (no editable fields).
  The e2e support now expects `BnestApp.Storage` exactly. **Lesson:** focused e2e runs must cover every page that
  renders a moved module's name or data, and U14 runs both full e2e suites.
- **The Gherkin review covered the whole family-chat corpus: 438 rows, 166 PASS, 105 EXEMPT, 167 FAIL.** Only 2 FAIL
  rows came from U9. The unit fan-out came from the in-memory store with no contract case, and the payload check
  scanned maps that can never hold text. The other 165 predate U9. They are split by owner:
  - **Fixed in U9:** the two U9 rows, plus the pre-existing defects in the drivers U9 rewrote and in BE e2e:
    - the resolver bypass for missing capability;
    - the quote event;
    - pagination evidence;
    - the no-new-message, migration idempotency, old-release and system-message Thens;
    - local broadcast scope;
    - the two BE e2e Thens.
      Each new Then was proved to fail against a temporary product mutation.
  - **Moved to U10:** delivery-state and Web Push Thens. **Moved to U11:** scheduler handler Thens. Those units move
    the code the Thens observe.
  - **Moved to U14's full-corpus review:**
    - the FE Vitest rows (a test branch inside production code, a leaking outbox namespace, constant readers);
    - the FE e2e bindings;
    - the exemption-form and exemption-reason defects, which change feature-file tags and comments;
    - the invalid integration exemptions on the subscription scenarios;
    - the scheduled-backups "Discover typed admin configuration" save proof;
    - the Caddy handshake-routing Thens, which read configuration text. A real proof needs the live slots, which
      continuity forbids touching, or a feature-file change that points the exemption at the FE e2e rollout scenario.
      U14 must close them before the release.

Resolution: applied in U9; 002, 004 and 006 stay as authored, and this entry records the as-built difference.

### E10: U10 PushNotifications as built (2026-10-02)

- **The dispatcher's test seam is gone.** The simulated `attempt(:retryable | :gone)` outcome and its bootstrap fixture
  left production code; only `attempt/0` remains. Test outcomes now come from the push-sender doubles, and the lease
  is computed from the same `now` as the attempt.
- **`Domain.Policy` is pure.** `validate_subscription_input/2` and `allowlisted_hosts/1` take the extra hosts as an
  argument. They come from a new `PushSender.synthetic_provider_hosts/0` callback, which returns `[]` for
  `WebPushSender`.
- **`:push_notifications_test_provider?` became adapter selection.**
  - `config/test.exs` selects `BnestApp.Test.RecordingPushSender` for the integration layer and the end-to-end
    servers. It lives under `test/support/`, which those servers compile, so no release ships it (U8's fixture model
    catalog is the precedent).
  - The unit layer selects the `BnestApp.Test.InMemory` doubles. Integration failure scenarios swap `push_sender` to
    the in-memory double through application env, restored `on_exit`, so the integration target stays serial.
- **The handler atom changed without a data step.** Schedule rows store only the `handler_key` string, so
  `scheduler/registry.ex` and the `Release.Migrations.FamilyChat` check name `Adapters.RetentionTask` directly.
- **Store details.**
  - `SqliteDeliveryStore` interpolates `LIMIT` behind an integer guard; the SQL result is unchanged.
  - The subscription contract uses 64-hex session digests because of the SQLite `CHECK` constraint.
  - Elapsed time is simulated with the in-memory delivery store's `put/3` seam at unit and SQL `UPDATE`s on the
    isolated database at integration.
- **Two latent order dependencies in unit scheduler Givens surfaced.** Push scenarios no longer start SQLite, so
  `:schedule_*` and `:convergence_already_ran` could run first on an unprepared database. Both now call
  `scheduler_database!/0`.
- **One frontend e2e flake.** In the first focused run, two socket-reconnect scenarios failed on one viewport each
  ("Reconnect across Caddy promotion" on tablet, "Reconnect on visibility resume" on mobile). The rerun of those
  titles and a full rerun passed. U14's full suites must watch them.
- **Gherkin review: 54 rows, 29 PASS, 18 EXEMPT, 7 FAIL, none introduced by U10.** U9's carried F14 (G35–G41) and
  F10 (O9–O11) now pass at both layers. Of the remaining rows:
  - **Fixed in U10:**
    - N1 (O8 at both layers): production could retry past the one-hour ceiling. A failure at 3500 s scheduled the
      120 s wait, and the claim side never checked age. This contradicts O8 and AC-FC-07. The fix: the policy
      refuses a wait that would cross 3600 s, and the dispatcher retires an over-age claimed row as `ceiling`
      without sending. This is the only behaviour change in U10, in its own `fix` commit. The new Thens were
      proved to fail when either half of the fix is reverted.
    - N2 (integration O7): the payload Then now reads the recording sender's payloads, not a table with no payload
      column.
  - **Moved to U11:** N3, the scheduler handler Thens (O12, O13), joining U9's F11.
  - **Non-blocking, for U14:**
    - unit Thens assert `deleted_by` values the store contracts do not pin;
    - `Adapters.WebPushSender` has no test at any layer;
    - the G35–G41 e2e exemption reason reads as redundancy rather than a boundary mismatch.

Resolution: applied in U10; 002, 004 and 006 stay as authored, and this entry records the as-built difference.

### E11: U11 Scheduler as built (2026-10-02)

- **The task map and tick handlers are configuration.**
  - `config :bnest_app, BnestApp.Scheduler, tasks:` maps each handler key to its task module, label, context, settings
    key and timezone. `TaskRegistry` reads it.
  - `tick_handlers:` names `{BnestApp.PushNotifications, :dispatch_all_due!, []}`, so `scheduler.ex` names no other
    context.
  - Schedule rows store only the handler key, so no data step was needed.
  - The `"fixture"` family task stays in the shared configuration because the base registry shipped it. U13/U14 decide
    whether it moves to test configuration.
- **`Scheduler.Ports.Task` is enforced.** Every task declares it, and `dependency_test.exs` checks this.
  `registered_handler/1` returns `{:ok, module}` or `:error`; the FamilyChat release migration checks the retention
  task through it.
- **The lease-renewal interval is configuration** (`lease_renewal_interval_ms`, still 60 s). Once `Run` left the
  legacy coverage group, its renewal and rescue branches counted toward coverage, so a unit test exercises them.
- **Test seams moved to test code.** `BnestApp.Test.Seeds.Schedules` (`test/integration/support/seeds/schedules.ex`)
  holds the former `*_for_test!` seams and `put_test_schedule/5` with byte-identical SQL. The end-to-end servers run
  `MIX_ENV=test`, which compiles `test/integration/support`, and reach it through `mix run -e`. The unused
  `force_daily_time_for_test!` was dropped.
- **`Domain.Policy` gained `setup_claim_key/1`, `valid_destination_id?/1` and `daily_edit/2`.** Setup-claim
  validation and the admin edit moved out of `AdminScheduleSettingsLive` into the facade.
- **Handler Thens observe invocation by BEAM call tracing.** `test/support/call_trace.ex` and `scheduler_dispatch.ex`
  record which configured task's `execute/2` ran, how often, for which run, and which calls it made, including that it
  made no `SqliteRepo` call. Tracing is global, so both behaviour layers stay serial. A SQL call through
  `Ecto.Adapters.SQL` or in tail position could slip past the trace; the `dependency_test.exs` source scan covers it.
- **Unit "Bnest starts again" converges through `Scheduler.converge_backup_time!`** rather than the release
  migrations, which need SQLite; integration still runs the real start. Unit O12 still runs the real `Backup.Run` over
  SQLite through the U12 legacy selection.
- **A moved test kept a stale relative path.** `persistent_schedules_migration_test.exs` pointed one directory short
  after its move; moved tests must recompute `__DIR__`-relative paths.
- **Gherkin review: 54 rows, 28 PASS, 16 EXEMPT, 10 FAIL, none introduced by U11.** U9's F11 and U10's N3 (O12, O13)
  now pass at both layers. Of the rest:
  - **Fixed in U11:**
    - N1 (unit O19) now runs the backup through the Scheduler under the forced timeout;
    - N2 (S8 at both layers) observes the shared coordinator dispatch the run;
    - N3 (integration S4) seeds more than one missed slot.
    - N6, a product defect: push retention never recorded its scheduled run as complete. Each daily run was
      lease-recovered and rerun until it failed at the attempt limit, and the admin page showed a failure. This
      contradicted the `Ports.Task` contract and family-chat tech-doc 009. The task now completes its run with an
      empty receipt. It is U11's only behaviour change, in its own `fix` commit.
  - **Moved to U12:** N4, the unit backup Thens that assert driver-built values (S1, S2, S5, S7).
- **Test backups reached the production backup directory (pre-existing, fixed in U11).**
  - With `BNEST_BACKUP_CONFIG` unset, `Backup.Config.config_path/0` fell back to the real
    `~/.config/bnest/backup.json`. Its destination is the production backup directory.
  - Behaviour scenarios that ran a backup without their own configuration wrote there. Read-only inspection found
    two verified artifacts with `bdd-` schedule keys and dozens of test-sized `.partial` files dating from 2026-09-18.
    The integration restart scenario's wall-clock tick is one path.
  - The path now falls back to an application setting first, and `config/test.exs` points it at each run's
    isolated test root. A unit test proved the real path before the fix and the test path after. The gate run
    after the fix left the production backup directory unchanged.
  - The fix is its own commit, first in U11. Removing the test files from the production directory is destructive
    and waits for the user's approval.
  - **Lesson:** every configuration path that defaults to a real home-directory file needs a test-environment
    default, not only an environment variable that each scenario must remember to set.
- **The unit layer also read the real storage pointer (pre-existing, fixed in U11).** Its `storage_config_path` was
  unset, so storage resolved the real `~/.config/bnest/storage.json`, which names the production database. Locally
  that file exists, so the gates passed. On CI it is absent and no run identifier is set, so resolving the default
  directory raised, and CI failed the two scenarios whose new Givens configure a backup destination. The unit layer now
  has an absent pointer and a run identifier under its own test directory, so local runs match CI. A unit test pins
  both.
  - **Moved to U13:** N5, the contextual schedule Thens (F1 at unit and integration).
  - **For U14:** `specs/apps/bnest/app-be/architecture.md` still names `Scheduler.Registry` and `RetentionJob`.

Resolution: applied in U11; 002, 004 and 006 stay as authored, and this entry records the as-built difference.

### E12: U12 Backup as built (2026-10-02)

- **The facade gained functions** beyond 002: `validate_destination/1`, `record_receipt/4`, `owned_receipts/1` and
  `retain_owned/1`, which returns `{:ok, kept}`. The handler Thens need that `{:ok, _}` shape to prove the task makes
  no direct SQL.
- **A domain module and a port callback outside 006.** `Domain.RestoreEvidence` holds the restore evidence rules, and
  the `DatabaseSnapshot` port carries `message_exists?/3` for the restore probe.
- **`Domain.Retention` duplicates the WIB +7 h rule** from `Scheduler.Domain.Policy`, because Backup's Domain has no
  dependencies.
- **The test-only `:capacity_check` option is gone.** The integration capacity scenario swaps in the in-memory capacity
  probe through application env, restored on exit, so the integration target stays serial.
- **Naming.** `SchedulerDispatch` maps `Backup.Adapters.ScheduledBackupTask` to the feature's "Backup.Run". Mutant
  B10 shows the mapping still tells modules apart. U14's C4 and spec pass should note the feature's name.
- **The unit layer no longer opens SQLite.** Every Backup port has an in-memory double that raises unless installed.
  The `verify.exs` allow-list is empty, and `test/unit/support/legacy_sqlite_room_store.ex` is deleted.
- **The moved integration `backup_test.exs` tests Storage's `FileRecordExport`.** It moved as 006 says; U14 may move it
  under `storage/`.
- **Gherkin review: 30 rows, 17 PASS, 8 EXEMPT, 5 FAIL, none introduced by U12.** U11's carried N4 (S1, S2, S5, S7 at
  unit) now passes. Of the rest:
  - **Fixed in U12:** N1, the integration O17 and O19 Thens, which never read the destination. They now run against
    an isolated destination and assert that no artifact or partial remains.
  - **Test-data safety S-1 (pre-existing, fixed in U12 in its own commit).** The default backup destination is
    `<repository root>/data/backup`, with the root compiled from the checkout.
    - In the permanent checkout that is the production backup directory. A test build there, or a run with an
      inherited `BNEST_REPOSITORY_ROOT`, resolved it.
    - The integration coordinator also caught up the shared daily backup row that one scenario forced due, running a
      real backup at wall-clock time. The worktree's ignored `data/backup` held two such test pairs.
    - Tests now resolve a per-run repository root that wins over the environment variable. It is not a git
      repository, so a default-destination backup fails closed. The forced-due row is returned to not-due on exit.
    - With E11 this is the third test path into production-adjacent state. **Lesson:** every default that derives
      from the checkout or the home directory needs a test-only override that wins.
  - **Moved to U13:** N2, "each owner validates and saves only its allowlisted fields" (F3 at all layers; U9's F17).
  - **Non-blocking, for U14:**
    - the in-memory snapshot double returns constant proof values;
    - its restore strips message bodies itself, so the unit O20 Then cannot fail and only integration proves it;
    - no shared contract suite runs the Backup doubles and real adapters through the same tests;
    - U-O18 skips the 2 s per-sample bound, and U-O19 probes before the backup rather than during it.

Resolution: applied in U12; 002, 004 and 006 stay as authored, and this entry records the as-built difference.

### E13: U13 Operations as built (2026-10-02)

- **Health reads SQLite reachability through the Scheduler facade.** 002 names a Storage health probe that does not
  exist, so `Operations.health/0` matches `Scheduler.get_schedule/1` on the backup schedule's handler and expiration
  instead of a raw `COUNT`. The schedule store's transient retry and row parsing are the only edge differences; any
  raise still reports `:sqlite_not_ready`, and the controller still returns 503 `{"status":"not_ready"}`.
- **Defaults moved to the facade.** The `ReleaseEnvironment` port returns raw values, `nil` when unset, and the facade
  applies `"development"` and `"standalone"`; an empty value behaves as before. The readiness process list is a facade
  attribute, and the facade exports only `Ports`.
- **Panel owners stay context facade atoms** (`BnestApp.Storage`, `BnestApp.Backup`), as the spec requires, rather than
  002's context names, so `data-config-owner` renders unchanged.
- **Legacy lists.** `@legacy_exports` and `@legacy_modules` are empty but still declared, and the empty `legacy_core`
  coverage list is gone from `mix.exs`. U14 deletes the attributes and the remaining `BnestApp` deps of the web, CLI and
  application boundaries.
- **Gherkin review: 9 rows, 7 PASS, 1 EXEMPT, 1 FAIL, none introduced by U13.**
  - **Fixed in U13:** N5 (F1 contextual schedules) at unit and integration, which now persist schedules and read the
    rendered rows per group; and N2 (F3 allowlisted fields) at unit and integration, which drive the Storage, Backup and
    Scheduler facades with forged input and read the stored state back. Eight mutants each failed the intended Then.
  - **Moved to U14:** the e2e part of N2. The frontend e2e support still asserts static attributes only.
  - **Non-blocking, for U14:** the integration "from home" Whens request the route directly; the F1 safe-status check
    covers only the family row; no shared contract runs both release-environment adapters.
- **The `"fixture"` task stays in production configuration.** Moving it to test configuration is safe only after a
  read-only check confirms no production schedule row names `fixture` as its handler, since the Scheduler could
  otherwise not resolve that row. U14 or a later change decides, with the owner's approval for the production read.
- **The curl server ran as a background task**, because the shell guard refuses tmux commands that carry a command
  string. It used an isolated run root and a leased port, and was stopped afterwards.

Resolution: applied in U13; 002, 004 and 006 stay as authored, and this entry records the as-built difference.

### E14: U14 Closure scope and structural closure (2026-10-02)

- **The full-corpus review found 267 FAIL rows out of 714.** Five reviews covered every Bnest feature (core 132 rows,
  family chat GraphQL 135, family chat operations 69, frontend family chat 231, chat and SifatAllah 147). Nearly all
  predate this plan. Their fixes reach unit and integration drivers, e2e support and step bindings, frontend Vitest
  steps and `assets/js`, feature-file exemption tags and comments, and production code: test-only code shipped in
  `lib/` (`Release.CaddyConfig`, `Backup.run/1`'s probe workload), the socket's session digest, the service worker's
  credentialed precache of `/`, the Codex port session after its runner exits, and the flat-to-SQLite migration logic
  inside an adapter.
- **Owner decision (2026-10-02): fix every row and the architecture before the release.** This amends the plan:
  - U14 may edit the paths 006 lists as "Never Touched": feature files (tags, exemption comments and wording that
    contradicts recorded design), e2e `tests/steps/**`, and `apps/bnest-app/assets/**`. Changed Gherkin follows
    [specification maintenance](../../../repo-governance/development/specification-maintenance.md) and gets the
    manual review.
  - The production changes the review needs are in scope. Each behaviour change lands in its own `fix` commit.
  - `FEATURE_DIFF` stops being empty. AC-DH-09's purpose, unchanged record schemas and outcomes, is held by the record
    schema proof and by every changed scenario's review row.
  - U14 lands as several pull requests: the structural closure, then one or more per review group, then C4 and
    documentation. Checkpoint 14 is met when the last one merges.
- **Structural closure as built.**
  - L3 treats any two-segment `BnestApp.<Name>` with a strict `use Boundary` as a context, found by scanning, so no
    context list is hard-coded. The other owners allowed are `SqliteRepo`, `Application`, `Release`, `Mailer` and the
    root, which keeps only itself and the mailer.
  - The scan's `violations/0` takes no arguments; the two legacy tests were deleted rather than emptied.
  - The boundary warnings name the caller's boundary, not the caller module; the file and line identify the module.
- **The Codex test selection fails closed.** Only a `BNEST_CODEX_RUNNER` naming the bundled fixture runner, compared by
  file identity, selects the real port session; this closes the E8 note and the chat review's X-1.
