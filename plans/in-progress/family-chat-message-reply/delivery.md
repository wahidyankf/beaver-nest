# Delivery

## Execution Status and Authority

**Pending. No product implementation, dependency change, product-delivery commit or push, migration, release, or
production mutation has started.** Integrating this plan does not start the checklist or authorize its later
execution. Read all six plan documents and the
[plan-execution workflow](../../../repo-governance/workflows/plan-execution.md) first. Start only from a current,
explicitly authorized, non-blocking plan-quality verdict: `PASS`, or `PASS_WITH_FINDINGS` with every finding recorded
and accepted by that workflow.

For each delivery item that ships code: write or change the Gherkin, bind the owning adapters, capture a behavioural
Nx RED, implement the minimum GREEN, REFACTOR while green, run the smoke and public-boundary proof, and perform the
manual Gherkin implementation review. Test data uses isolated marked roots and `test-user-` identities. Cleanup runs
in `on_exit`/`finally`; cleanup failure fails the gate. Never read or mutate production user or message data.

Every command runs at repository root with `rtk`. Restartable Nx work has one outer checksum-pinned `./hippo` guard.
Self-guarded `test:e2e`, `serve`, and `release:run` targets do not receive a second guard. Exit `75` is requeued only
when its receipt says `never-started`; exit `73` cleans owned storage; exit `78` stops for replanning.

## Canonical Commands

| ID                | Exact command                                                                                                                                |
| ----------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| `BE_UNIT`         | `rtk ./hippo run --class ephemeral --resource-tier standard --disk-path . -- npm exec -- nx run -p bnest-app -t test:unit:be`                |
| `FE_UNIT`         | `rtk ./hippo run --class ephemeral --resource-tier standard --disk-path . -- npm exec -- nx run -p bnest-app -t test:unit:fe`                |
| `UNIT`            | `rtk ./hippo run --class ephemeral --resource-tier standard --disk-path . -- npm exec -- nx run -p bnest-app -t test:unit`                   |
| `INTEGRATION`     | `rtk ./hippo run --class ephemeral --resource-tier standard --disk-path . -- npm exec -- nx run -p bnest-app -t test:integration`            |
| `BEHAVIOUR`       | `rtk ./hippo run --class ephemeral --resource-tier standard --disk-path . -- npm exec -- nx run -p bnest-app -t test:coverage:behaviour`     |
| `BE_E2E_COVERAGE` | `rtk ./hippo run --class ephemeral --resource-tier light --disk-path . -- npm exec -- nx run -p bnest-app-be-e2e -t test:coverage:behaviour` |
| `FE_E2E_COVERAGE` | `rtk ./hippo run --class ephemeral --resource-tier light --disk-path . -- npm exec -- nx run -p bnest-app-fe-e2e -t test:coverage:behaviour` |
| `BE_E2E`          | `rtk npm exec -- nx run -p bnest-app-be-e2e -t test:e2e`                                                                                     |
| `FE_E2E`          | `rtk npm exec -- nx run -p bnest-app-fe-e2e -t test:e2e`                                                                                     |
| `E2E_ALL`         | `rtk npm run test:e2e`                                                                                                                       |
| `APP_QUICK`       | `rtk ./hippo run --class ephemeral --resource-tier standard --disk-path . -- npm exec -- nx run -p bnest-app -t test:quick`                  |
| `RELEASE_TEST`    | `rtk ./hippo run --class ephemeral --resource-tier standard --disk-path . -- npm exec -- nx run -p bnest-app -t release:test`                |
| `REPO`            | `rtk ./hippo run --class ephemeral --resource-tier standard --disk-path . -- npm exec -- nx run -p rhino-consumer -t test:repo`              |

`test:quick` never runs integration or E2E. The root `test:e2e` script runs BE then FE deterministically; each project
leases a distinct port range and isolated runtime root inside its self-guarded target.

`UNIT`, `BE_UNIT`, and `FE_UNIT` carry the repository's **99% line-coverage threshold**; the suite and the threshold
pass or fail together. Every new module this plan creates — `message_actions.js`, `reply_target.js`,
`jump_to_message.js`, and the new migration — must therefore arrive with unit coverage, not acquire it later. A phase
that leaves a new module uncovered fails its own checkpoint before it ever reaches a push.

## Verification Layers

Every layer below is required, each answers a question no other layer can, and each names the phase that owns it. A
phase is not complete while its layer is unproven. `API impact: GraphQL query, mutation, and subscription` — this
change is API-affecting, so the [API testing standard](../../../repo-governance/development/api-testing.md)'s
automated layering **and** its mandatory manual `curl` both apply.

| Layer                                 | Proves                                                                                                                                                                                     | Owned by       |
| ------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | -------------- |
| Backend unit                          | Validation, authorization, mapping, truncation, and error behaviour, with no OS or network access                                                                                          | Phases 2, 3    |
| Backend integration                   | GraphQL routing, document parsing, variable coercion, serialization, and the `data`/`errors` envelope through a loopback listener the test owns and stops — never the routed public origin | Phase 3        |
| Backend behaviour (Gherkin)           | The canonical backend corpus, bound to real adapters                                                                                                                                       | Phase 3        |
| Backend E2E                           | Representative operations through the exact served origin, including the subscription lifecycle                                                                                            | Phase 3        |
| Frontend unit                         | Browserless decisions: gesture timers, menu state, reply-target lifecycle, outbox records, jump arithmetic                                                                                 | Phases 4, 5, 6 |
| Frontend E2E                          | Real pointer, focus, and layout behaviour a browserless harness cannot reach                                                                                                               | Phases 5, 6    |
| **Manual API `curl`**                 | The public boundary, by hand, with authorized and unauthorized synthetic identities                                                                                                        | Phase 7        |
| **Manual UI inspection**              | Routes × states × viewports, seen by a person at the exact origin                                                                                                                          | Phase 8        |
| **Manual keyboard and screen reader** | The journey without a pointer and without sight, recorded as announced                                                                                                                     | Phase 8        |
| **Exploratory pass (spec-aware)**     | Defects the scenarios did not think to ask about                                                                                                                                           | Phase 8        |
| **Usability pass (spec-blind)**       | Whether the feature makes sense to someone who has not read the plan                                                                                                                       | Phase 8        |
| Gherkin implementation review         | That every scenario's proof is real rather than placeholder, no-op, or fabricated                                                                                                          | Phase 8        |
| Routed release proof                  | Responsiveness, mixed-revision safety, reconnect without refresh, and the rollback floor                                                                                                   | Phases 9, 10   |

Automation never substitutes for the four bold layers, and a green pipeline does not make them optional.

## Execution Checkout

- Use exactly `worktrees/family-chat-message-reply/` on branch `family-chat-message-reply` from current `origin/main`.
- After the application PR merges, reuse that worktree, sync to `origin/main`, and create
  `family-chat-message-reply-archive` for the completion record.
- `main` is the only persistent branch. Integrate by reviewed PR; never push directly to `main`, and never create
  sibling `*-worktrees/` paths.
- Managed production releases run from the clean primary checkout at the landed `origin/main` revision.
- Preserve unfamiliar changes under `plans/` and `repo-governance/`; stop on dirty overlap or conflict.

## Delivery Units

| Unit                       | Owner | Outcome                                                                                                | Rollback                                            |
| -------------------------- | ----- | ------------------------------------------------------------------------------------------------------ | --------------------------------------------------- |
| DU-1 application PR        | AI    | Specifications, C4, migration, backend, browser, styles, tests, and documentation, with the flag off   | Revert through the PR before any production release |
| DU-2 compatibility release | AI    | The reviewed revision routed with `BNEST_FAMILY_CHAT_REPLY_ENABLED=false`, drained, rollback floor set | Managed Caddy rollback to the prior revision        |
| DU-3 experience release    | AI    | The **same** revision routed with the flag on                                                          | Managed Caddy rollback to DU-2's revision           |
| DU-4 completion PR         | AI    | Evidence reconciled, learnings resolved, plan archived once                                            | Restore the in-progress plan before merge           |

## Pause Safety

At each pause, append a dated sanitized note to [`learnings.md`](learnings.md): checkout and commit, the last
completed and next checkbox, the exact command and result, the HIPPO receipt, the active and candidate revision, both
feature-flag states, the remaining repair and retry budget, and any File Impact deviation. Never record private
origins, real users, message text, cookies, keys, endpoints, database content, or absolute runtime paths.

## Phase 0 — Authorized Start and Preflight

- [x] `[AI] [AC-FCR-01..14]` Run the explicitly authorized plan-quality workflow against this frozen plan and record
      one terminal verdict in `learnings.md`. **Proof:** a current `PASS` or `PASS_WITH_FINDINGS` with every finding
      recorded; any blocking verdict stops execution. Workflow:
      `repo-governance/workflows/plan-quality-gate.md`.
      **2026-09-22:** `PASS`, one cycle, no stabilization cycle needed. Five findings raised and all repaired inside
      the run: Q1 ERD keys and cardinality, Q2 full field guide for the resulting table, Q3 Expand/Migrate/Verify/
      Contract order with source inventory and rollback behaviour, Q4 the exploratory and usability passes specified
      to their workflow's actual contract, Q5 the 99% unit-coverage threshold named. No row left `OPEN` or
      `BLOCKED`; nothing waived. Snapshot, ledger, and tooling result in `learnings.md`.
- [x] `[AI] [AC-FCR-01..14]` Provision `worktrees/family-chat-message-reply/` from current `origin/main`, inspect
      dirty paths, and freeze the Nx project and target inventory in `learnings.md`. **Proof:** clean branch based on
      `origin/main`, exactly one live copy of this plan, and resolved `bnest-app`, `bnest-app-be-e2e`,
      `bnest-app-fe-e2e`, and `rhino-consumer` targets. Commands: `rtk git fetch origin`,
      `rtk git status --short --branch`, and a guarded `npm exec -- nx show project <name> --json`.
      **2026-09-22:** clean worktree at `origin/main`, one live plan copy, five projects resolved, and every
      canonical command's target present. Inventory in `learnings.md`.
- [x] `[AI] [AC-FCR-11]` Record the SQLite version bundled with the running `exqlite`, and whether
      `PRAGMA foreign_keys` is on for the shared `SqliteRepo` connection. **Proof:** both values in `learnings.md`.
      A SQLite version below 3.35 means the migration's down path raises instead of dropping the column — decide and
      record that before Phase 2 writes it, not after.
      **2026-09-22:** `exqlite` 0.40.0 bundling SQLite **3.53.4**, so the down path drops the column rather
      than raising — decided before Phase 2. `PRAGMA foreign_keys` is **on** for a pooled `SqliteRepo`
      connection and off for a bare one; the application check stays the first guard. Probed on an isolated
      scratch database, removed afterwards.
- [x] `[AI] [AC-FCR-14]` Record a 12-sample routed readiness baseline and the current active revision and slot,
      without private values. **Proof:** zero failures, p95 ≤ 500 ms, every sample ≤ 2 s, and the healthy revision
      identifier in `learnings.md`. Procedure: the read-only steps in `docs/how-to-guides/releasing-bnest.md`.
      **2026-09-22:** green slot routed through Caddy, zero failures, p95 248.4 ms, maximum 248.4 ms. Inside
      budget.
- [x] `[AI] [AC-FCR-01..14]` **Blocking checkpoint — Phase 0.** Confirm a non-blocking quality verdict, a clean and
      current checkout, the recorded SQLite and pragma facts, a healthy routed baseline, and that no product file has
      been edited yet.
      **2026-09-22: passed.** Quality verdict `PASS`; checkout clean at `origin/main`; SQLite 3.53.4 and the
      pragma both recorded; routed baseline inside budget; no file outside `plans/` has been touched.

## Phase 1 — Specification and Architecture Delta

- [x] `[AI] [AC-FCR-04, AC-FCR-05, AC-FCR-12]` Add the reply `Rule`s to
      `specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature` and
      `specs/apps/bnest/app-be/behaviours/family_chat_operations.feature`, transcribing the relevant
      [`prd.md`](prd.md) scenarios as observable backend behaviour. Transcribe exactly the scenarios
      [Specification Changes](tech-docs/005-specification-changes.md) selects as durable contracts, and leave the
      outcomes it marks plan-only out of `specs/`. **Proof:** the new Rules exist, every scenario names an outcome
      visible at the GraphQL boundary or in stored state, and no plan-only outcome was copied in. No placeholder,
      no-op, or outcome-table scenario is accepted.
      **2026-09-22:** one new `Rule: Replying to a message` with five scenarios, plus four scenarios added to
      the existing idempotency, display-name, and subscription rules, and two to `family_chat_operations`.
      Every plan-only outcome stayed out. No existing scenario was edited.
- [x] `[AI] [AC-FCR-01, AC-FCR-02, AC-FCR-03, AC-FCR-06..10]` Add the reply `Rule`s to
      `specs/apps/bnest/app-fe/behaviours/family_chat.feature`, tagging each scenario with the layer that will own it
      and writing an explicit `Exemption(e2e)` comment with its alternative proof wherever a scenario is proven at
      FE_UNIT instead of FE_E2E. **Proof:** every new scenario carries an owning tag, and every exemption names the
      exact alternative target and scenario name.
      **2026-09-22:** four new Rules — message actions, composing a reply, reading a reply, keyboard reach —
      plus four offline scenarios on the existing queue rule and one on the promotion rule. Every scenario
      carries its owning tag and a documented exemption; the compliance validator accepts all of them.
- [x] `[AI] [AC-FCR-04, AC-FCR-06]` Update `specs/apps/bnest/app-be/architecture.md` exactly as
      [Specification Changes](tech-docs/005-specification-changes.md) states: in the **Component View** prose, the
      paragraph enumerating the family chat GraphQL surface gains `send_family_chat_message`'s optional
      `reply_to_message_id` argument and the message's `reply_to` field; in **Architectural Constraints**, quote
      resolution is recorded as a read-time derivation inside the `familychat` component. **Proof:** those two
      locations changed and no other. The **Container View** models one `Local SQLite database` node and enumerates
      no tables, and **Behaviour Traceability** is prose naming adapters rather than scenarios — record both as
      deliberately unchanged rather than editing them.
      **2026-09-22:** Component View prose now states the optional `reply_to_message_id` argument and the
      `reply_to` quote field with its four subfields, and says the quote type is distinct rather than
      recursive. Architectural Constraints gained the read-time-derivation rule. Container View and
      Behaviour Traceability were read and left unchanged, deliberately: the former models one SQLite node
      and enumerates no tables, the latter names adapters and no individual scenario.
- [x] `[AI] [AC-FCR-01, AC-FCR-08, AC-FCR-10]` Update `specs/apps/bnest/app-fe/architecture.md` exactly as
      [Specification Changes](tech-docs/005-specification-changes.md) states: the **Component View** prose covering
      the browser-owned `assets/js/family_chat/*` module set gains the action-menu, reply-target, and jump modules
      and the reply flag the route passes to the browser; **Architectural Constraints** gains one bullet for the
      single tab stop with arrow-key movement and one for a quote always being derived at read time and never cached
      in the browser or the service worker. **Proof:** the three modules and the flag appear exactly once each, the
      read-time bullet sits beside the existing service-worker caching constraint it would otherwise seem to
      contradict, and the **Container View** is recorded as deliberately unchanged.
      **2026-09-22:** Component View prose now names the action-menu, reply-target, and jump modules and the
      reply flag the route passes. Two constraints added: the single tab stop with arrow-key movement, and
      read-time quote derivation placed directly beside the service-worker caching rule it would otherwise
      appear to contradict. Container View left unchanged, deliberately.
- [x] `[AI] [AC-FCR-01..14]` Run the repository specification-map gate. **Proof:** `REPO` passes and the delivery
      record names every specification file changed. Command: `REPO`.
      **2026-09-22:** `REPO` green — `public-safety-tree`, `repo-config`, `word-budget`, `directory-map`,
      `harness-adapters`, `internal-links`, `mermaid`. Specification files changed:
      `app-be/behaviours/family_chat_graphql.feature`, `app-be/behaviours/family_chat_operations.feature`,
      `app-fe/behaviours/family_chat.feature`, `app-be/architecture.md`, `app-fe/architecture.md`.
- [x] `[AI] [AC-FCR-01..14]` **Blocking checkpoint — Phase 1.** Specifications and both C4 models describe the
      intended behaviour, `REPO` is green, and no production code has changed.
      **2026-09-22: passed.** Both C4 models and all three feature files describe the intended behaviour,
      `REPO` is green, and no production code has changed — the diff is `specs/` and `plans/` only.

## Phase 2 — Data Model and Migration

- [ ] `[AI] [AC-FCR-11]` **RED** — add migration scenarios to
      `apps/bnest-app/test/integration/bnest_app/family_chat_migration_test.exs`: existing rows survive with a null
      target, a re-run is a no-op, and reversal refuses once a reply row exists. **Proof:** `INTEGRATION` fails
      naming the absent column. Command: `INTEGRATION`.
- [ ] `[AI] [AC-FCR-11]` **GREEN** — write
      `apps/bnest-app/priv/sqlite_repo/migrations/20260922000000_add_family_chat_message_reply.exs` with the additive
      column, the partial index, and the refusing down path recorded in
      [Data Model](tech-docs/001-data-model-and-migration.md). **Proof:** `INTEGRATION` passes. Command:
      `INTEGRATION`.
- [ ] `[AI] [AC-FCR-11]` **REFACTOR** — align the migration's naming, ordering, and refusal message with the existing
      family-chat migration without changing behaviour. **Proof:** `INTEGRATION` still passes. Command: `INTEGRATION`.
- [ ] `[AI] [AC-FCR-04, AC-FCR-05]` **RED** — extend
      `apps/bnest-app/test/unit/bnest_app/family_chat/message_test.exs` for reply-target normalization: nil passes
      through, a positive integer parses, and zero, a negative, and a non-integer are refused. **Proof:** `BE_UNIT`
      fails naming the missing function. Command: `BE_UNIT`.
- [ ] `[AI] [AC-FCR-04, AC-FCR-05]` **GREEN** — add `normalize_reply_to_message_id/1` to
      `apps/bnest-app/lib/bnest_app/family_chat/message.ex`. **Proof:** `BE_UNIT` passes. Command: `BE_UNIT`.
- [ ] `[AI] [AC-FCR-04, AC-FCR-05]` **REFACTOR** — keep the new function's shape and comment style consistent with
      `normalize_body/1` and `valid_client_message_id?/1`. **Proof:** `BE_UNIT` still passes. Command: `BE_UNIT`.
- [ ] `[AI] [AC-FCR-04, AC-FCR-06]` **RED** — extend `apps/bnest-app/test/unit/bnest_app/family_chat_test.exs`:
      committing with a target stores it; a page resolves quotes in one extra query; a page with no replies issues no
      extra query; the preview collapses whitespace, cuts at 160 graphemes, and appends an ellipsis only when cut;
      and a row whose target is absent resolves to no quote rather than raising. That last case is unreachable while
      the immutability triggers stand — it is pinned so the degradation stays a decision, as
      [Data Model](tech-docs/001-data-model-and-migration.md) requires, and the test sets it up by inserting the row
      directly rather than by deleting anything. **Proof:** `BE_UNIT` fails on the absent behaviour. Command:
      `BE_UNIT`.
- [ ] `[AI] [AC-FCR-04, AC-FCR-06]` **GREEN** — implement storage and batch quote resolution in
      `apps/bnest-app/lib/bnest_app/family_chat/store.ex` and
      `apps/bnest-app/lib/bnest_app/family_chat.ex`. **Proof:** `BE_UNIT` passes. Command: `BE_UNIT`.
- [ ] `[AI] [AC-FCR-04, AC-FCR-06]` **REFACTOR** — keep truncation in exactly one private function, and keep the
      column list, insert, and row mapper in the store rather than spreading them into the context. **Proof:**
      `BE_UNIT` still passes. Command: `BE_UNIT`.
- [ ] `[AI] [AC-FCR-05]` **RED** — extend the same unit test: a target that does not exist, and one that exists in
      another room, each fail validation and commit nothing. **Proof:** `BE_UNIT` fails. Command: `BE_UNIT`.
- [ ] `[AI] [AC-FCR-05]` **GREEN** — add the same-room existence check to `FamilyChat.send_message/5` before any
      insert is attempted. **Proof:** `BE_UNIT` passes and no row is written on the failing paths. Command: `BE_UNIT`.
- [ ] `[AI] [AC-FCR-05]` **REFACTOR** — express the check through the existing `with` chain and the existing
      `validation_failed/0` helper rather than a new error path. **Proof:** `BE_UNIT` still passes. Command:
      `BE_UNIT`.
- [ ] `[AI] [AC-FCR-04]` **RED** — add the idempotent-replay case: the same client message ID replayed with a
      different target returns the first commit, with the first target. **Proof:** `BE_UNIT` fails. Command:
      `BE_UNIT`.
- [ ] `[AI] [AC-FCR-04]` **GREEN** — confirm the existing `find_message/4` path returns the stored row untouched, and
      add whatever is missing for its quote to be attached on that path too. **Proof:** `BE_UNIT` passes. Command:
      `BE_UNIT`.
- [ ] `[AI] [AC-FCR-04]` **REFACTOR** — remove any duplication between the fresh-commit and replay quote-attachment
      paths. **Proof:** `BE_UNIT` still passes. Command: `BE_UNIT`.
- [ ] `[AI] [AC-FCR-04, AC-FCR-05, AC-FCR-11]` **Blocking checkpoint — Phase 2.** The column exists, validation
      refuses every impossible target before any write, quotes resolve in one extra query per page, the preview rule
      lives in one place, and `UNIT` and `INTEGRATION` are both green. Commands: `UNIT`, `INTEGRATION`.

## Phase 3 — GraphQL Contract

- [ ] `[AI] [AC-FCR-04, AC-FCR-07]` **RED** — extend `apps/bnest-app/test/unit/bnest_app_web/schema_test.exs`: the
      quote object exists with its four fields, `FamilyChatMessage.replyTo` is nullable, the mutation accepts
      `replyToMessageId`, the quote type has **no** field that could carry another quote, and the resolver still
      contains no query logic. **Proof:** `BE_UNIT` fails on the absent type. Command: `BE_UNIT`.
- [ ] `[AI] [AC-FCR-04, AC-FCR-07]` **GREEN** — add the type and field to
      `apps/bnest-app/lib/bnest_app_web/schema/types/family_chat_types.ex`, the argument to
      `apps/bnest-app/lib/bnest_app_web/schema.ex`, and the pass-through to
      `apps/bnest-app/lib/bnest_app_web/resolvers/family_chat_resolver.ex`. **Proof:** `BE_UNIT` passes. Command:
      `BE_UNIT`.
- [ ] `[AI] [AC-FCR-06]` **REFACTOR** — resolve the quote's sender display name through the same
      `Identity.display_name_for/1` seam the message's own name uses, so one change would move both. **Proof:**
      `BE_UNIT` still passes. Command: `BE_UNIT`.
- [ ] `[AI] [AC-FCR-04, AC-FCR-05, AC-FCR-06]` **RED** — bind the new backend scenarios in
      `apps/bnest-app/test/behaviour/steps/family_chat_backend_steps.exs`. **Proof:** `BEHAVIOUR` fails with
      unimplemented or failing steps, not with a harness error. Command: `BEHAVIOUR`.
- [ ] `[AI] [AC-FCR-04, AC-FCR-05, AC-FCR-06]` **GREEN** — make the bound scenarios pass without widening production
      behaviour beyond what they describe. **Proof:** `BEHAVIOUR` passes. Command: `BEHAVIOUR`.
- [ ] `[AI] [AC-FCR-04..06]` **REFACTOR** — remove duplication between the new steps and the existing family-chat
      steps. **Proof:** `BEHAVIOUR` still passes. Command: `BEHAVIOUR`.
- [ ] `[AI] [AC-FCR-04, AC-FCR-05, AC-FCR-07]` **RED** — add GraphQL boundary integration tests under
      `apps/bnest-app/test/integration/bnest_app_web/family_chat_graphql_test.exs` `[N]`, exercising the real
      Absinthe pipeline through a loopback listener the test starts, owns, and stops — never the routed public
      origin. Assert the full contract the API standard names: operation name, HTTP status, content type, variables,
      and the `data`/`errors` envelope, for a successful reply, a rejected target, and an unauthenticated caller.
      HTTP `200` alone never counts as GraphQL success. **Proof:** `INTEGRATION` fails on the absent module. Command:
      `INTEGRATION`.
- [ ] `[AI] [AC-FCR-04, AC-FCR-05, AC-FCR-07]` **GREEN then REFACTOR** — make those tests pass without loosening any
      validation, then remove duplication against the existing integration helpers. **Proof:** `INTEGRATION` passes
      before and after the refactor. Command: `INTEGRATION`.
- [ ] `[AI] [AC-FCR-04, AC-FCR-05, AC-FCR-06, AC-FCR-12]` **RED then GREEN** — bind and pass the backend E2E
      scenarios in `apps/bnest-app-be-e2e/tests/steps/family-chat.steps.ts`, including the subscription carrying
      `replyTo` and a reply producing exactly one delivery row per other subscription. **Proof:** `BE_E2E_COVERAGE`
      reports full coverage of the new backend scenarios and `BE_E2E` passes. Commands: `BE_E2E_COVERAGE`, `BE_E2E`.
- [ ] `[AI] [AC-FCR-04..07, AC-FCR-12]` **Blocking checkpoint — Phase 3.** The schema is flat by construction, the
      resolver is still thin, and every backend scenario is bound and green at all four backend layers — unit,
      integration, behaviour, and E2E. A layer that was skipped rather than run fails this checkpoint.

## Phase 4 — Send Path and Offline Outbox

- [ ] `[AI] [AC-FCR-09]` **RED** — extend `apps/bnest-app/assets/test/unit/family_chat/outbox.test.ts`: a queued
      reply carries its target, survives a persistence round trip, drains with the argument, and a legacy record
      without the field drains as an ordinary message. **Proof:** `FE_UNIT` fails. Command: `FE_UNIT`.
- [ ] `[AI] [AC-FCR-09]` **GREEN** — carry `replyToMessageId` through
      `apps/bnest-app/assets/js/family_chat/outbox.js`, `outbox_namespace.js`, `outbox_send.js`, and
      `persistence_indexeddb.js`, leaving `DB_VERSION` at 1. **Proof:** `FE_UNIT` passes. Command: `FE_UNIT`.
- [ ] `[AI] [AC-FCR-09]` **REFACTOR** — keep the field optional everywhere rather than defaulting it to null in the
      record shape, so a legacy row and a non-reply are indistinguishable by design. **Proof:** `FE_UNIT` still
      passes. Command: `FE_UNIT`.
- [ ] `[AI] [AC-FCR-03, AC-FCR-05]` **RED** — extend `apps/bnest-app/assets/test/unit/family_chat/composer.test.ts`:
      the target is carried into submit, cleared on success, and **kept** when the queue refuses. **Proof:**
      `FE_UNIT` fails. Command: `FE_UNIT`.
- [ ] `[AI] [AC-FCR-03, AC-FCR-05]` **GREEN** — implement the reply-target lifecycle in
      `apps/bnest-app/assets/js/family_chat/reply_target.js` and `composer.js`. **Proof:** `FE_UNIT` passes. Command:
      `FE_UNIT`.
- [ ] `[AI] [AC-FCR-03]` **REFACTOR** — keep the reply target out of the composer's own draft state so the two clear
      independently. **Proof:** `FE_UNIT` still passes. Command: `FE_UNIT`.
- [ ] `[AI] [AC-FCR-04, AC-FCR-06]` **RED then GREEN** — add the flag-aware `messageFields({replies})` to
      `apps/bnest-app/assets/js/family_chat/operations.js` and prove the query, mutation, and subscription documents
      all derive from it, so none can drift. **Proof:** `FE_UNIT` fails on the absent export, then passes with a test
      asserting all three documents agree. Command: `FE_UNIT`.
- [ ] `[AI] [AC-FCR-03, AC-FCR-09]` **Blocking checkpoint — Phase 4.** A reply can be queued, persisted, hydrated,
      and drained with its target; legacy records still send; no document can ask for a field another omits.

## Phase 5 — Action Menu, Composer Strip, and Keyboard Reach

- [ ] `[AI] [AC-FCR-01, AC-FCR-02]` **RED** — add
      `apps/bnest-app/assets/test/unit/family_chat/message_actions.test.ts` covering the decisions without a browser:
      a hold under 500 ms or over 10 px does not open; four triggers reach one open function; a message with no
      server ID yields Reply unavailable with its reason; copy success and copy refusal produce their announcements.
      **Proof:** `FE_UNIT` fails. Command: `FE_UNIT`.
- [ ] `[AI] [AC-FCR-01, AC-FCR-02]` **GREEN** — implement
      `apps/bnest-app/assets/js/family_chat/message_actions.js`. **Proof:** `FE_UNIT` passes. Command: `FE_UNIT`.
- [ ] `[AI] [AC-FCR-01]` **REFACTOR** — keep gesture recognition, menu state, and action execution in separate
      functions so a later per-message action adds an item and nothing else. **Proof:** `FE_UNIT` still passes.
      Command: `FE_UNIT`.
- [ ] `[AI] [AC-FCR-01, AC-FCR-03]` **RED then GREEN** — add the menu host and the reply strip to
      `apps/bnest-app/lib/bnest_app_web/controllers/family_chat_html/room.html.heex`, the handles to `elements.js`,
      and the bindings to `mount_browser.js` and `mount_browser_composer.js`, including Escape in the textarea.
      **Proof:** `FE_UNIT` covers the binding decisions and passes; the template renders without the flag as well as
      with it. Command: `FE_UNIT`.
- [ ] `[AI] [AC-FCR-10]` **RED** — extend `apps/bnest-app/assets/js/family_chat/accessibility.js`'s own tests so the
      keyboard-reachability proxy asserts the roving contract on the rendered list — exactly one `tabindex="0"` among
      message items — instead of only scanning the template text. **Proof:** `FE_UNIT` fails against the current
      renderer. Command: `FE_UNIT`.
- [ ] `[AI] [AC-FCR-10]` **GREEN** — implement roving tabindex and arrow-key movement in `message_render.js` and
      `real_store.js`, and replace `accessibility.js`'s template text scan with the rendered-list invariant.
      **Proof:** `FE_UNIT` passes, and the new check fails when the roving invariant is broken deliberately — prove
      that by breaking it once and recording the failure before restoring it. Command: `FE_UNIT`.
- [ ] `[AI] [AC-FCR-10]` **REFACTOR** — keep the roving stop in the store's state rather than recomputing it from the
      DOM on every key press. **Proof:** `FE_UNIT` still passes. Command: `FE_UNIT`.
- [ ] `[AI] [AC-FCR-10]` **RED then GREEN** — prove the **real** focus order in a browser: a scenario in
      `apps/bnest-app-fe-e2e/tests/steps/family-chat-reply.steps.ts` that tabs into the history exactly once, moves
      between messages with the arrow keys, opens the menu with Enter, and tabs out exactly once, with 50 messages
      loaded. **Proof:** the scenario fails against the pre-roving renderer and passes after it; `FE_E2E` green.
      This is the layer the `FE_UNIT` invariant cannot reach — the unit layer has no focus or layout engine.
      Commands: `FE_E2E_COVERAGE`, `FE_E2E`.
- [ ] `[AI] [AC-FCR-01, AC-FCR-02, AC-FCR-03, AC-FCR-10]` **Blocking checkpoint — Phase 5.** One menu exists with
      four triggers and two items, the strip appears and clears correctly, the history has a single tab stop with
      arrow-key movement, the `FE_UNIT` check now tests the rendered invariant rather than template text, and a real
      browser has walked the focus order end to end.

## Phase 6 — Quote Rendering, Jump, and Styles

- [ ] `[AI] [AC-FCR-06, AC-FCR-07]` **RED** — extend the frontend unit suite: a message with `replyTo` renders a
      quote button with the sender, the preview, and the composed accessible name; a message without it renders none;
      a quote never renders a nested quote; and every window path — initial, older, resumed, appended, and reconciled
      — renders the same quote for the same message. **Proof:** `FE_UNIT` fails. Command: `FE_UNIT`.
- [ ] `[AI] [AC-FCR-06, AC-FCR-07]` **GREEN** — implement quote rendering in `message_render.js` and wire it into
      `real_store_render.js`. **Proof:** `FE_UNIT` passes. Command: `FE_UNIT`.
- [ ] `[AI] [AC-FCR-06]` **REFACTOR** — render the quote through one function used by every path, so a new path
      cannot forget it. **Proof:** `FE_UNIT` still passes. Command: `FE_UNIT`.
- [ ] `[AI] [AC-FCR-08]` **RED** — extend `apps/bnest-app/assets/test/unit/family_chat/history.test.ts`: a target in
      the window jumps without fetching; a target two pages up loads exactly two pages; a target beyond five pages
      requests exactly five and then announces the refusal; and the unread divider and `hasNewer` are untouched in
      all three cases. **Proof:** `FE_UNIT` fails. Command: `FE_UNIT`.
- [ ] `[AI] [AC-FCR-08]` **GREEN** — implement `apps/bnest-app/assets/js/family_chat/jump_to_message.js` and its
      bounded use of the existing older-page path in `history.js`. **Proof:** `FE_UNIT` passes. Command: `FE_UNIT`.
- [ ] `[AI] [AC-FCR-08]` **REFACTOR** — express the bound as one named constant beside the page size rather than a
      literal at the call site. **Proof:** `FE_UNIT` still passes. Command: `FE_UNIT`.
- [ ] `[AI] [AC-FCR-08, AC-FCR-10]` **RED then GREEN** — add the quote card, menu, mobile sheet, reply strip,
      highlight, `prefers-reduced-motion`, and coarse-pointer rules to `apps/bnest-app/assets/css/app.css`.
      **Proof:** the existing horizontal-overflow structural check still passes with no fixed pixel width added, and
      `FE_UNIT` is green. Command: `FE_UNIT`.
- [ ] `[AI] [AC-FCR-01, AC-FCR-02, AC-FCR-03, AC-FCR-06, AC-FCR-08, AC-FCR-09, AC-FCR-10]` **RED then GREEN** — bind
      and pass the browser scenarios in `apps/bnest-app-fe-e2e/tests/steps/family-chat-reply.steps.ts` and
      `apps/bnest-app-fe-e2e/tests/support/family-chat-reply.ts`, awaiting real state rather than sleeping, using
      isolated `test-user-` identities, and closing every tab and context the task creates. **Proof:**
      `FE_E2E_COVERAGE` reports full coverage of the new frontend scenarios and `FE_E2E` passes. Commands:
      `FE_E2E_COVERAGE`, `FE_E2E`.
- [ ] `[AI] [AC-FCR-01..10]` **Blocking checkpoint — Phase 6.** Quotes render identically on every path, the jump is
      bounded and refuses out loud, the styles introduce no overflow, and the browser suite is green.

## Phase 7 — Documentation, Rules, and Public-Boundary Proof

- [ ] `[AI] [AC-FCR-04, AC-FCR-05, AC-FCR-06]` **Mandatory manual API proof.** Invoke every affected operation by
      hand with `curl` against the exact isolated served origin, starting from validated isolated test state under a
      `test-user-` identity and cleaning it afterwards. This is required even though the unit, integration,
      behaviour, and E2E layers are green. Cover each of the following as its own separate observation:
      `familyChatMessages` returning a page in which one node carries a populated `replyTo` and another carries
      `null`; `sendFamilyChatMessage` with a valid `replyToMessageId`, the success path; `sendFamilyChatMessage`
      with a non-existent `replyToMessageId`, and again with one from another room, each being a materially changed
      validation path; and the same successful operation as an **unauthenticated** caller and as an authenticated
      caller **without** the family-chat capability, confirming both are refused. **Proof:** for each observation,
      record in `learnings.md` the redacted command shape, the exact origin, the operation name, the observed HTTP
      status, the shape of `data` and `errors`, the independently observed side effect (a row committed, or no row
      committed), and pass or fail. HTTP `200` alone never counts as GraphQL success. Never record secrets, cookies,
      private payloads, or real message text.

- [ ] `[AI] [AC-FCR-06]` **Subscription lifecycle proof.** `curl` proves only the handshake, which is insufficient
      on its own: after it, observe `familyChatMessageCommitted` delivering a reply with its quote through a
      protocol-capable client for the full lifecycle — subscribe, receive, and disconnect. **Proof:** the handshake
      status and the sanitized received payload shape in `learnings.md`.
- [ ] `[AI] [AC-FCR-04, AC-FCR-06]` Update `README.md`, `apps/bnest-app/README.md`,
      `apps/bnest-app-be-e2e/README.md`, `apps/bnest-app-fe-e2e/README.md`,
      `docs/how-to-guides/releasing-bnest.md`, and `docs/reference/glossary.md` per
      [File Impact](tech-docs/006-file-impact-and-release.md). **Proof:** each file states the new flag, surface, or
      term exactly once, in the Diátaxis category it belongs to, with no duplicated prose between them.
- [ ] `[AI] [AC-FCR-01..14]` Apply the bounded
      [rules-propagation workflow](../../../repo-governance/workflows/rules-propagation.md) to any repository rule
      this execution created, changed, moved, or deleted, and record its terminal result. **Proof:** a recorded
      terminal result in `learnings.md`; `PASS_NO_CHANGE` is a valid outcome and is expected here.
- [ ] `[AI] [AC-FCR-01..14]` Run the full application and repository gates. **Proof:** `UNIT`, `INTEGRATION`,
      `BEHAVIOUR`, `RELEASE_TEST`, `E2E_ALL`, and `REPO` all green, with receipts recorded. Commands: `UNIT`,
      `INTEGRATION`, `BEHAVIOUR`, `RELEASE_TEST`, `E2E_ALL`, `REPO`.
- [ ] `[AI] [AC-FCR-01..14]` **Blocking checkpoint — Phase 7.** Every public operation has manual proof,
      documentation matches the built behaviour, rules propagation has a terminal result, and every gate is green.

## Phase 8 — Manual Verification

- [ ] `[AI] [AC-FCR-01, AC-FCR-02, AC-FCR-03, AC-FCR-06, AC-FCR-08]` Walk the full UI matrix by hand at the exact
      served origin: routes `/family-chat/ruang-keluarga`; states idle, focused, menu open, Reply unavailable, strip
      shown, reply rendered, jump succeeded, jump refused, reduced motion, and offline; viewports 320 × 568,
      768 × 1024, and 1440 × 900. **Proof:** a route/state/viewport/pass-fail table in `learnings.md` with no private
      values. Automation, code inspection, and static assets supplement this and never replace it.
- [ ] `[AI] [AC-FCR-10]` Perform the complete reply journey with the keyboard alone, and again with a screen reader,
      recording what was announced at each step in the member's own terms. **Proof:** both walkthroughs in
      `learnings.md`, including the exact announced text for the quote card and the disabled Reply item.
- [ ] `[AI] [AC-FCR-01..10]` **Exploratory pass (spec-aware), first.** Drive Playwright MCP against the running
      application at its exact served origin, across all three supported viewport classes, using isolated
      `test-user-` identities and mutating no shared or production state. Compare live behaviour against the changed
      `specs/**` Gherkin and actively probe beyond the scripted cases: boundary conditions, route and URL structure,
      and passive security signals such as exposed identifiers or a missing authorization check. **Proof:** every
      finding recorded in `learnings.md` under the exact heading `## Exploratory findings`, each with its route,
      state, and category, and no private values. This pass is finished and recorded **before** the usability pass
      begins, so the two lenses never blend.
- [ ] `[AI] [AC-FCR-01..10]` **Usability pass (spec-blind), second.** Blindness must be structural, not declared: a
      context that implemented this change has already read the specs and cannot un-read them. Delegate the pass to a
      fresh agent context given only the origin, the affected routes, and the viewport classes — withholding the
      specs, the source, and the twelve design assets. If no delegation is available, run it and record explicitly
      that it ran spec-aware, so its findings are read with that limitation. Judge only first-time-user perception
      against Nielsen's ten heuristics, a cognitive walkthrough, the empty, loading, error, and zero-result states,
      and responsive usability. **Proof:** findings under the exact heading `## Usability findings`, never merged
      into the exploratory section.
- [ ] `[AI] [AC-FCR-01..10]` Cross-reference the two sets: where an exploratory and a usability finding describe one
      underlying defect, add a short note in **both** sections naming the shared root cause, so it is fixed once.
      **Proof:** the cross-reference notes, or a recorded statement that no finding pair shared a root cause.
- [ ] `[AI] [AC-FCR-01..10]` For every finding that reveals correct-but-unspecced behaviour, reconcile it through the
      [BDD Iron Rule](../../../repo-governance/development/behaviour-driven-development.md) as its own cycle: update
      the Gherkin, bind failing steps, confirm RED, then implement. Never merge an unreconciled proposal into
      `specs/**`. Label a usability-sourced proposal as such. **Proof:** for each accepted proposal, the scenario
      name, its RED evidence, and its GREEN result; or a recorded statement that no finding proposed a spec change.
      Commands: `BEHAVIOUR`, `FE_E2E_COVERAGE`.
- [ ] `[AI] [AC-FCR-01..12]` Perform the
      [Gherkin implementation review](../../../repo-governance/workflows/gherkin-implementation-review.md) over every
      changed feature file and its bindings. **Proof:** a per-scenario verdict in `learnings.md`; any fabricated,
      placeholder, or no-op proof is fixed before this item is ticked.
- [ ] `[AI] [AC-FCR-01..10]` Confirm, before the phase checkpoint, that both passes ran, that findings are present or
      explicitly recorded as none found, that both headings are correctly labelled, that cross-references are noted,
      and that every accepted spec proposal completed the Iron Rule with its `delivery.md` proof. **Proof:** the
      confirmation recorded in `learnings.md` against each of those five conditions.
- [ ] `[AI] [AC-FCR-01..12]` **Blocking checkpoint — Phase 8.** All six manual layers are recorded and separately
      labelled — the API `curl` and subscription proofs from Phase 7, and this phase's UI matrix, keyboard and
      screen-reader walkthrough, spec-aware exploratory pass, spec-blind usability pass, and Gherkin implementation
      review. Every finding is either fixed or explicitly accepted as non-blocking with its reason written down. An
      unexamined finding blocks the release; an examined and accepted one does not.

## Phase 9 — Compatibility Release

- [ ] `[AI] [AC-FCR-13]` Merge DU-1 through a reviewed PR with
      `BNEST_FAMILY_CHAT_REPLY_ENABLED=false`. **Proof:** the merge commit on `origin/main`, every gate green on the
      merged revision, and no direct push to `main`.
- [ ] `[AI] [AC-FCR-14]` Preflight the release: confirm the routed baseline, disk headroom, and a healthy slot pair.
      **Proof:** 12 samples with zero failures, p95 ≤ 500 ms, every sample ≤ 2 s, recorded without private values.
- [ ] `[AI] [AC-FCR-11, AC-FCR-13]` Release the merged revision to the candidate slot with the flag off, run the
      migration, and verify the candidate's health before any route change. **Proof:** candidate readiness healthy,
      the column present, and existing messages unchanged.
- [ ] `[AI] [AC-FCR-13]` Promote through Caddy and prove mixed-revision safety at the routed origin: a browser
      holding the **previous** bundle loads the room and sends a message. **Proof:** both observations recorded, with
      no page refresh required and no forced reload.
- [ ] `[AI] [AC-FCR-04, AC-FCR-13]` Prove the field is answerable everywhere before any bundle asks for it: a `curl`
      requesting `replyTo` against the routed origin returns data rather than a document rejection. **Proof:** the
      sanitized response in `learnings.md`.
- [ ] `[AI] [AC-FCR-14]` Hold the drain window, keep the prior slot warm for five minutes, then retire it. **Proof:**
      a 12-sample post-promotion set and a 12-sample post-drain set, both within budget, and the prior slot confirmed
      stopped.
- [ ] `[AI] [AC-FCR-11, AC-FCR-13, AC-FCR-14]` **Blocking checkpoint — Phase 9.** The compatibility revision is
      routed and drained, it is the recorded rollback floor, and every routed sample is within budget.

## Phase 10 — Experience Release

- [ ] `[AI] [AC-FCR-13]` Release the **same reviewed revision** with `BNEST_FAMILY_CHAT_REPLY_ENABLED=true` to the
      candidate slot and verify candidate health before any route change. **Proof:** the candidate's revision
      identifier equals Phase 9's, and readiness is healthy.
- [ ] `[AI] [AC-FCR-13]` Promote through Caddy and confirm connected clients reconnect and catch up without a
      refresh, including a message committed during the promotion appearing exactly once for each. **Proof:** two
      `test-user-` contexts observed through the routed origin, recorded without message content.
- [ ] `[AI] [AC-FCR-01, AC-FCR-03, AC-FCR-06, AC-FCR-08]` Exercise the feature at the routed origin on the real
      household surface: open the menu, reply, see the quote, and jump back. **Proof:** a routed pass record; a 2xx
      status alone is not accepted as proof.
- [ ] `[AI] [AC-FCR-13]` Prove the rollback floor still serves the reply-aware bundle: against the Phase 9 revision,
      a browser holding the current bundle loads the room and renders existing quotes. **Proof:** recorded
      observation. This is a proof, not a rollback — the route is not moved.
- [ ] `[AI] [AC-FCR-14]` Hold the drain window, then retire the prior slot. **Proof:** post-promotion and post-drain
      12-sample sets within budget and the prior slot confirmed stopped.
- [ ] `[AI] [AC-FCR-01..14]` **Blocking checkpoint — Phase 10.** The feature is routed and working at the exact
      origin, the rollback floor is proven, responsiveness held throughout, and no candidate, watcher, or temporary
      proxy is still running.

## Recovery and Rollback

Dormant until triggered. If a trigger does not fire, record an evidence-backed `Not triggered` disposition at
reconciliation rather than ticking the item.

- [ ] `[AI] [AC-FCR-14]` **Trigger: any failed readiness sample, p95 above 500 ms, or any sample above 2 s at any
      release stage.** Roll the route back to the recorded floor through the managed Caddy path, confirm
      responsiveness returns to budget, and stop. **Proof:** the trigger observation, the rollback, and a recovered
      12-sample set.
- [ ] `[AI] [AC-FCR-13]` **Trigger: a GraphQL document rejection observed at the routed origin, or a room that fails
      to load for either bundle.** Roll back to the floor, capture the rejected operation name and code without
      private values, and stop for diagnosis rather than fixing forward. **Proof:** the sanitized rejection and the
      restored route.
- [ ] `[AI] [AC-FCR-11]` **Trigger: the migration fails or leaves the candidate unhealthy.** Do not promote. Retire
      the candidate slot, leave the current route untouched, and record the failure. The production database is
      unchanged because the migration runs on the candidate before any route change. **Proof:** candidate retired,
      route unchanged, failure recorded.
- [ ] `[AI] [AC-FCR-01..10]` **Trigger: a blocking finding from either manual pass after the experience release.**
      Set `BNEST_FAMILY_CHAT_REPLY_ENABLED=false` on the routed slot, which hides the feature without moving the
      route or touching data, and reopen the owning phase. **Proof:** the flag state, the finding, and the reopened
      phase.

## Archival

Runs only after every substantive phase above is complete and its checkpoint is green.

- [ ] `[AI] [AC-FCR-01..14]` Resolve every `learnings.md` entry to exactly one durable owner — governance,
      specification, test, code comment, permanent documentation, or idea brief — or discard it with a stated
      reason. **Proof:** no unresolved entry remains; each carries its owner or its discard reason.
- [ ] `[AI] [AC-FCR-01..14]` Raise the follow-up idea briefs this plan deliberately deferred, deduplicated against
      the existing ones: retiring `BNEST_FAMILY_CHAT_REPLY_ENABLED` after the rollback window, and swipe-to-reply as
      an optional gesture with its accessibility evidence. **Proof:** the briefs exist under `plans/ideas/<quadrant>/`
      with their quadrant justified by dated evidence, or a recorded decision not to raise them.
- [ ] `[AI] [AC-FCR-01..14]` Run the
      [plan-execution-check workflow](../../../repo-governance/workflows/plan-execution-check.md) and record its
      terminal verdict. **Proof:** the verdict in `learnings.md`. Archival is not permitted while any acceptance
      criterion or delivery unit is unresolved.
- [ ] `[AI] [AC-FCR-01..14]` Run the [dev-artifact-clean-up workflow](../../../repo-governance/workflows/dev-artifact-clean-up.md):
      stop every non-production server, watcher, candidate, and temporary proxy this work started; remove this
      execution's `local-tmp/` scratch; and delete the worktree and its branch after the PR merges. **Proof:** only
      the active route and its bounded drain remain, and both the worktree and the branch are gone.
- [ ] `[AI] [AC-FCR-01..14]` Move this folder to `plans/done/YYYY-MM-DD__family-chat-message-reply` using the
      completion date, update both stage indexes and every live reference to the old path, run `REPO` **from the
      archived state**, and commit the move as one transaction. **Proof:** one live copy of the plan, no stale
      reference, and `REPO` green after the move. Command: `REPO`.
