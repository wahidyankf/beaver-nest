# Delivery

## Execution Status and Authority

**Pending. No product implementation, dependency change, product-delivery commit/push, migration, release, or production
mutation has started.** Integrating this plan does not start the checklist or authorize its later execution. Read all six
plan documents and the plan-execution workflow first. Start only from a current explicitly authorized non-blocking
plan-quality verdict: `PASS`, or `PASS_WITH_FINDINGS` with every finding recorded and accepted by that workflow.

For each delivery item: write Gherkin, bind the owning adapters, capture a behavioral Nx RED, implement the minimum GREEN,
REFACTOR while green, run smoke/public-boundary proof, and perform the manual Gherkin implementation review. Test data
uses isolated marked roots and `test-user-` identities. Cleanup runs in `on_exit`/`finally`; cleanup failure fails the
gate. Never read or mutate production user/message data.

Every command runs at repository root with `rtk`. Restartable Nx work has one outer checksum-pinned `./hippo` guard.
Self-guarded `test:e2e`, `serve`, and `release:run` targets do not receive a second guard. Exit `75` is requeued only when
its receipt says `never-started`; exit `73` cleans owned storage; exit `78` stops for replanning.

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
| `BE_E2E_QUICK`    | `rtk ./hippo run --class ephemeral --resource-tier light --disk-path . -- npm exec -- nx run -p bnest-app-be-e2e -t test:quick`              |
| `FE_E2E_QUICK`    | `rtk ./hippo run --class ephemeral --resource-tier light --disk-path . -- npm exec -- nx run -p bnest-app-fe-e2e -t test:quick`              |
| `RELEASE_TEST`    | `rtk ./hippo run --class ephemeral --resource-tier standard --disk-path . -- npm exec -- nx run -p bnest-app -t release:test`                |
| `REPO`            | `rtk ./hippo run --class ephemeral --resource-tier standard --disk-path . -- npm exec -- nx run -p rhino-consumer -t test:repo`              |

The implemented root `test:e2e` script runs BE then FE deterministically. Each project leases a distinct port range and
isolated runtime root inside its self-guarded target. `test:quick` never runs integration or E2E.

## Execution Checkout

- Use exactly `worktrees/family-chat-room/` on branch `family-chat-room` from current `origin/main`.
- After the application PR merges, reuse that worktree, sync to `origin/main`, and create
  `family-chat-room-archive` for the completion record.
- `main` is the only persistent branch. Integrate by reviewed PR; never push directly to `main` or create sibling
  `*-worktrees/` paths.
- Managed production releases run from the clean primary checkout at the landed `origin/main` revision.
- Preserve unfamiliar changes under `plans/` and `repo-governance/`; stop on dirty overlap or conflict.

## Delivery Units

| Unit                       | Owner | Outcome                                                                                       | Rollback                                            |
| -------------------------- | ----- | --------------------------------------------------------------------------------------------- | --------------------------------------------------- |
| DU-1 application PR        | AI    | Rules/spec topology, additive schema, GraphQL, services, backup correction, dormant UI, tests | Revert through PR before production                 |
| DU-2 compatibility release | AI    | Compatible revision routed, drained, and established as rollback floor                        | Managed Caddy rollback to prior revision            |
| DU-3 experience release    | AI    | Same reviewed revision is released with navigation/UI flag enabled                            | Roll back to the same revision's compatibility slot |
| DU-4 completion PR         | AI    | Evidence reconciled and plan archived once                                                    | Restore in-progress plan before merge               |

## Pause Safety

At each pause, append a dated sanitized note to [`learnings.md`](learnings.md): checkout/commit, last completed and next
checkbox, exact command/result, HIPPO receipt, active/candidate revision, feature-flag state, schedule state, remaining
repair/retry budget, and File Impact deviation. Never record private origins, users, message text, cookies, keys,
endpoints, database content, or absolute runtime paths.

## Phase 0 — Authorized Start and Preflight

- [ ] `[AI] [AC-FC-01..13]` Run the explicitly authorized plan-quality workflow against this frozen plan and record one
      terminal verdict in `learnings.md`. **Proof:** current `PASS` or `PASS_WITH_FINDINGS`; every `BLOCKED_*` verdict
      blocks execution. Command/workflow:
      `repo-governance/workflows/plan-quality-gate.md`.
- [ ] `[AI] [AC-FC-01..13]` Provision/sync `worktrees/family-chat-room/`, inspect dirty paths, and freeze the current Nx
      project/target inventory in `learnings.md`. **Proof:** clean branch based on `origin/main`, one live plan copy, and
      resolved `bnest-app`, `bnest-app-e2e`, and `rhino-consumer` targets. Commands: `rtk git status --short --branch`,
      `rtk git fetch origin`, `rtk git rebase origin/main`, and guarded `npm exec -- nx show project <name> --json`.
- [ ] `[AI] [AC-FC-05..07]` Revalidate Absinthe, Absinthe Phoenix/Plug, browser socket client, Web Push library, and
      Vitest dependencies before changing `apps/bnest-app/mix.exs`, `mix.lock`, `package.json`, or `package-lock.json`.
      **Proof:** versions/checksums/licenses/compatibility/advisories and accept/block decision in `learnings.md`; no silent
      substitute.
- [ ] `[AI] [AC-FC-13]` Record current database bytes/page count/page size/WAL, backup destination capacity, current
      `prod-sqlite-backup-daily` time, and a 12-sample routed baseline without values. **Proof:** zero failures, p95 ≤500 ms,
      every sample ≤2 s, healthy revision/readiness, and disk calculation from tech docs 002 and 009. Commands:
      `rtk npm exec -- nx run -p bnest-app -t proxy:status` plus the private read-only procedure in
      `docs/how-to-guides/releasing-bnest.md`.
- [ ] `[AI] [AC-FC-01..13]` **Blocking checkpoint — Phase 0.** Confirm a non-blocking plan-quality verdict,
      clean/current checkout, accepted dependencies, healthy route, measured capacity, and no product edit before the
      checkpoint.

## Phase 1 — Rules Propagation and Test Topology

- [ ] `[AI] [AC-FC-01..13]` Apply `repo-governance/workflows/rules-propagation.md` to
      `repo-governance/development/behaviour-driven-development.md` and only ledger-proven points of use so one application
      may own boundary-specific roots with aggregate ownership and per-project adapter checks. **Proof:** terminal
      `PASS_CHANGED` in `learnings.md` and command `REPO` green.
- [ ] `[AI] [AC-FC-01..13]` Record the generator assessment in `learnings.md`: installed/local discovery has no suitable
      generator for this ExBDD/Playwright split, so manual construction is selected. **Proof:** discovered generator list
      and decision; no unrelated generator run.
- [ ] `[AI] [AC-FC-01..13]` Create the exact `specs/apps/bnest/app-be/`, `app-fe/`, and aggregate map paths from tech doc 006. Move/split every old scenario with a one-to-one ledger; keep transition copies non-canonical and uncommitted.
      **Proof:** every old scenario has exactly one destination and both architecture entrypoints validate.
- [ ] `[AI] [AC-FC-01..13]` Create `bnest-app-be-e2e` and the temporary `bnest-app-fe-e2e` replacement, update
      `apps/bnest-app/project.json`, `package.json`, and harness coverage configs, then move the current browser harness.
      **Proof:** `BEHAVIOUR`, `BE_E2E_COVERAGE`, and `FE_E2E_COVERAGE` green for preserved behavior; old project still
      exists only until both replacement runtime targets pass.
- [ ] `[AI] [AC-FC-01..13]` Run `BE_E2E` and `FE_E2E` on preserved journeys, then delete `apps/bnest-app-e2e/` and remove
      its Nx/root-script references. **Proof:** both replacement targets green with distinct ports/roots, old project
      absent, `nx show projects --json` lists both replacements, and cleanup leaves no tabs/processes/test roots.
- [ ] `[AI] [AC-FC-01..13]` **Blocking checkpoint — Phase 1.** Confirm rules `PASS_CHANGED`, one canonical owner per old
      scenario, both replacement E2E projects green, `bnest-app` aggregate coverage green, and old topology retired.

## Phase 2 — New Gherkin, Bindings, and RED

- [ ] `[AI] [AC-FC-01..13]` Write `family_chat_graphql.feature`, `family_chat_operations.feature`, and frontend
      `family_chat.feature` first, plus the exact auth/backup/spec-map deltas from tech doc 006. **Proof:** scenario names
      cover auth, room, pagination, idempotency, subscription/catch-up, system service, push, retention, backup,
      offline/reconnect, accessibility, Caddy socket evacuation, and release with one owner each.
- [ ] `[AI] [AC-FC-01..13]` Add backend ExBDD, frontend Vitest-Gherkin, BE E2E, and FE E2E bindings/support at the File
      Impact paths. **Proof:** coverage targets report no undefined, ambiguous, unused, no-op, or blanket-exempt step.
      Commands: `BEHAVIOUR`, `BE_E2E_COVERAGE`, `FE_E2E_COVERAGE`.
- [ ] `[AI] [AC-FC-01..13]` **RED** Run `BE_UNIT`, `FE_UNIT`, `INTEGRATION`, affected `BE_E2E`, and affected `FE_E2E`.
      **Proof:** named assertions fail because the feature is absent, not for harness, identity, port, or cleanup defects;
      record each scenario/test/expected failure in `learnings.md`.
- [ ] `[AI] [AC-FC-01..13]` Review every new/changed feature and binding using
      `repo-governance/workflows/gherkin-implementation-review.md`. **Proof:** scenario-level ledger names boundary,
      independent evidence, exemptions, and pass/fail; any placeholder blocks GREEN work.
- [ ] `[AI] [AC-FC-01..13]` **Blocking checkpoint — Phase 2.** Confirm Gherkin-first ordering, complete adapters, valid
      behavioral RED, safe fixtures, and exact cleanup.

## Phase 3 — SQLite, Domain, and GraphQL GREEN/REFACTOR

- [ ] `[AI] [AC-FC-02..04] [AC-FC-11]` **GREEN** Add the exact migration, Family Chat context/store/message, release
      verifier, room seed, sender model, idempotent user/system transactions, pagination, and retention store operations
      listed in tech doc 007. **Proof:** `BE_UNIT` and `INTEGRATION` pass fresh/repeat migration, seed, transaction rollback,
      restart, pages, duplicate keys, internal system posting, and old-reader overlap.
- [ ] `[AI] [AC-FC-02..05] [AC-FC-08]` **GREEN** Add Absinthe schema/types/resolvers/socket, router/endpoint/session
      wiring, fixed pool size, CSRF, safe errors, and production GraphiQL disable. **Proof:** `BE_UNIT`, `INTEGRATION`, and
      focused `BE_E2E` pass every named query/mutation plus subscription auth/post-commit behavior.
- [ ] `[AI] [AC-FC-02..04]` **REFACTOR** Remove resolver SQL, centralize room authorization/topic/cursor limits, and keep
      public user identity server-owned. **Proof:** the same three targets remain green and dependency-direction tests reject
      bypasses.
- [ ] `[AI] [AC-FC-02..05] [AC-FC-08]` Run manual isolated API proof: `curl` every named query/mutation and use a
      protocol-capable client for `familyChatMessageCommitted` following tech doc 008. **Proof:** redacted operation matrix records status,
      content type, `data`/`errors`, auth failures, validation, idempotency, and independent side effects.
- [ ] `[AI] [AC-FC-02..04]` **Smoke** Restart the isolated app, make seed sources unavailable, and re-read room/messages
      through GraphQL. **Proof:** same server IDs/order and no production root/user access.
- [ ] `[AI] [AC-FC-02..05]` **Blocking checkpoint — Phase 3.** Confirm additive schema, exact seed, internal-only system
      posting, GraphQL contract, fixed pool, manual API proof, and fresh-process recovery are green.

## Phase 4 — Browser Outbox, Reconnect, and UI GREEN/REFACTOR

- [ ] `[AI] [AC-FC-01] [AC-FC-03] [AC-FC-08..10] [AC-FC-12]` **GREEN** Add the room controller/template, GraphQL
      client, IndexedDB outbox, reconnect module, status projection, CSS, static-cache restriction, and feature flag at the
      paths in tech doc 007; keep navigation off by default. **Proof:** `FE_UNIT` passes queue cap, FIFO, backoff/jitter,
      online hint, terminal classes, auth pause, expiry, acknowledgement deletion, logout isolation, and reconciliation.
- [ ] `[AI] [AC-FC-01] [AC-FC-03] [AC-FC-09] [AC-FC-12]` **GREEN** Implement canonical redirect, room/history UI,
      scroll anchor, live arrival, offline banner, statuses/actions, reload recovery, and accessibility semantics.
      **Proof:** focused `FE_E2E` passes desktop/tablet/mobile, 200% zoom automation, two contexts, offline/reopen, and
      socket reconnect without refresh.
- [ ] `[AI] [AC-FC-03] [AC-FC-08..10] [AC-FC-12]` **REFACTOR** Centralize operation documents, clocks/randomness,
      queue schema/version, merge-by-server-ID, and DOM state names; remove timing sleeps. **Proof:** `FE_UNIT`, `FE_E2E`,
      and `BE_E2E` remain green and task-created contexts/roots close.
- [ ] `[AI] [AC-FC-10] [AC-FC-12]` **GREEN** Update `tools/deployment.mjs` so generated Caddy reverse-proxy config
      omits `stream_close_delay 5m` while retaining global `grace_period 5m`; update `tools/release.mjs` to keep the prior
      process warm during observation while proving its sockets closed at reload. **Proof:** release/continuity tests reject
      any nonzero stream-close delay or cross-slot PubSub assumption, and routed E2E proves promoted subscription within
      ten seconds plus exact-once gap catch-up.
- [ ] `[AI] [AC-FC-09] [AC-FC-12]` **Smoke** Run exact-origin spec-aware exploratory and structurally spec-blind
      usability passes at all viewports, zoom, keyboard, and screen reader. **Proof:** separate sanitized findings and
      dispositions in `learnings.md`; static assets/tests do not substitute.
- [ ] `[AI] [AC-FC-01] [AC-FC-03] [AC-FC-08..10] [AC-FC-12]` **Blocking checkpoint — Phase 4.** Confirm no LiveView
      chat command event remains, committed history is absent from browser storage, status/reconnect behavior is green,
      and navigation remains dormant.

## Phase 5 — Push, Retention, and Backup GREEN/REFACTOR

- [ ] `[AI] [AC-FC-05..08] [AC-FC-11]` **GREEN** Add Push Notifications policy/sender/dispatcher/retention and GraphQL
      subscription lifecycle. **Proof:** `BE_UNIT` and `INTEGRATION` pass provider allowlist, encrypted loopback request,
      no redirects, retry ceiling, sender exclusion, lease recovery, seven-plus-seven retention, and logout ordering.
- [ ] `[AI] [AC-FC-05] [AC-FC-08]` **GREEN** Add service-worker push/click handling and GraphQL permission UI. **Proof:**
      `FE_UNIT` and focused `FE_E2E` pass supported/blocked/install-required/disable states and Cache Storage inspection.
- [ ] `[AI] [AC-FC-13]` **GREEN** Add `BnestApp.Backup`, make `Backup.Run` a registered adapter, remove forced
      `wal_checkpoint(FULL)`, and implement measured capacity guard, dedicated connection, timeout/cancellation,
      telemetry, proof, atomic rename, receipt, and existing retention exactly as tech doc 009. **Proof:** `BE_UNIT` and `INTEGRATION` pass normal,
      insufficient-space, timeout, corrupt-partial, stale-claim, retry, and seven-date cases.
- [ ] `[AI] [AC-FC-11] [AC-FC-13]` **GREEN** Update Scheduler service/registry/store and release migration verifier for
      registered handlers, disabled retention seed, post-compatible activation, and one-time 18:00 UTC backup convergence
      without removing later configurability. **Proof:** `INTEGRATION` and `RELEASE_TEST` reject direct SQL/unknown handler
      overlap and pass fresh/existing/operator-edited schedules.
- [ ] `[AI] [AC-FC-13]` Run the isolated concurrent-write load proof for the full backup interval. **Proof:** complete
      verified restore artifact, zero routed failures, p95 ≤500 ms, every sample ≤2 s, timeout/cancellation evidence, and
      cleanup of only owned fixtures.
- [ ] `[AI] [AC-FC-05..08] [AC-FC-11] [AC-FC-13]` **REFACTOR** Keep Scheduler→handler→service→store directions,
      consolidate safe telemetry categories, and remove duplicate time/capacity policy. **Proof:** dependency tests and all
      Phase 5 targets remain green.
- [ ] `[AI] [AC-FC-05..08] [AC-FC-11] [AC-FC-13]` **Blocking checkpoint — Phase 5.** Confirm push, retention, low-impact
      whole-database backup, restore, capacity, concurrency, schedule, privacy, and cleanup proof.

## Phase 6 — As-built Specs, Documentation, and Compatibility Gates

- [ ] `[AI] [AC-FC-01..13]` Update both canonical C4 files, both behavior maps, aggregate `specs/apps/bnest/README.md`,
      root/app/E2E READMEs, release guide, glossary, and directory maps to the final compatible implementation. **Proof:**
      links/Mermaid/maps pass `REPO`; current and future feature-flag states are distinguished.
- [ ] `[AI] [AC-FC-01..13]` Run `APP_QUICK`, `INTEGRATION`, `BE_E2E_QUICK`, `FE_E2E_QUICK`, `BE_E2E`, `FE_E2E`,
      `RELEASE_TEST`, then `REPO` serially. **Proof:** ≥99% unit coverage, real isolated integration, both routed E2E
      projects, dependency/security review, release tests, and repository gate green; cleanup leaves no owned runtime.
- [ ] `[AI] [AC-FC-01..13]` Inspect `rtk git diff --check`, `rtk git status --short`, File Impact, public-data safety,
      secrets/private paths, and prohibited runtime artifacts. **Proof:** sanitized audit and fully reconciled path list.
- [ ] `[AI] [AC-FC-01..13]` **Blocking checkpoint — Phase 6.** Confirm the compatibility increment is green, feature flag
      off, no stale `bnest-app-e2e` or `specs/apps/bnest/app/`, and no unneeded process/root/tab.

## Phase 7 — Compatibility PR and Release

- [ ] `[AI] [AC-FC-01..13]` With explicit commit/push authority, create thematic commits on
      `family-chat-room`, run hooks without bypass, push, open a draft PR, make it ready only after exact-head
      gates/review, and rebase-merge it. **Proof:** staged path/public-safety audit, green CI, resolved review, landed SHA.
      Commands use `rtk git add -- <exact-path>`, `rtk git commit`, `rtk git push`, and `rtk gh pr ...` under the integration
      convention.
- [ ] `[AI] [AC-FC-10] [AC-FC-13]` From clean primary `main`, repeat health/capacity baseline and run self-guarded
      `rtk npm exec -- nx run -p bnest-app -t release:run -- --revision <compatibility-sha>`. **Proof:** additive migration,
      candidate revision/readiness, fixed subscription pool, GraphQL probes, Caddy promotion, immediate prior-socket close,
      promoted GraphQL subscription within ten seconds, existing LiveView reconnect, exact-once gap catch-up, zero
      failures, p95/max budget, five-minute warm prior-slot observation, and prior-slot retirement.
- [ ] `[AI] [AC-FC-11] [AC-FC-13]` After drain, enable retention and converge backup schedule through Scheduler services,
      then verify one value-safe run state and 01:00 WIB next slot. **Proof:** no SQL shortcut, every runnable slot knows
      handlers, operator edit remains possible, and compatibility revision is recorded as rollback floor.
- [ ] `[AI] [AC-FC-10]` **Recovery if triggered:** keep or restore prior route on migration/candidate/probe failure; after
      promotion, disable newly activated handlers before routing code that lacks them. Preserve additive data and retire
      only the failed candidate. **Proof:** healthy routed revision/journey or dated `Not triggered`.
- [ ] `[AI] [AC-FC-01..13]` **Blocking checkpoint — Phase 7.** Confirm compatibility revision routed, drained, handler
      and backup schedule state correct, navigation still off, and one healthy route plus rollback artifact remains.

## Phase 8 — Experience Release

- [ ] `[AI] [AC-FC-01] [AC-FC-09] [AC-FC-12]` From the same reviewed compatibility SHA, prepare the inactive candidate
      with `BNEST_FAMILY_CHAT_ENABLED=true`; make no repository edit or schema change. Rerun candidate quick/release and
      exact route/UI checks before promotion. **Proof:** candidate reports the same revision, enabled flag, matching GraphQL
      schema/pool, and green assets/navigation while the routed compatibility slot remains flag-off.
- [ ] `[AI] [AC-FC-10] [AC-FC-12]` Run the managed experience release for `<compatibility-sha>` with continuous HTTP/readiness/revision
      and GraphQL-socket probes. Against an isolated candidate/routed test root, use two synthetic authenticated contexts
      to prove draft, queued send, Caddy-triggered prior-socket close, promoted subscription within ten seconds, catch-up,
      and exact-once rendering. **Proof:** no nonzero `stream_close_delay`, no refresh, no prior-slot handshake after
      promotion, zero failures, p95 ≤500 ms, max ≤2 s, warm observation/cleanup complete. Production database receives
      no synthetic user/message.
- [ ] `[AI] [AC-FC-13]` Verify the next complete backup receipt and restore a copy into an isolated root; prove room,
      message structure, push subscriptions, delivery state, and Scheduler state without printing bodies/secrets.
      **Proof:** checksum/integrity/logical categories and exact cleanup.
- [ ] `[AI] [AC-FC-10] [AC-FC-12]` **Recovery if triggered:** managed Caddy rollback to the compatibility floor, prove
      routed revision/GraphQL/readiness, observe rejected-slot socket close, let clients reconnect/catch up, drain the
      rejected slot, and retain data. **Proof:** healthy floor or dated `Not triggered`.
- [ ] `[AI] [AC-FC-01..13]` **Blocking checkpoint — Phase 8.** Confirm intended experience revision, operational-only
      production proof, isolated synthetic proof, backup restore, responsiveness, recovery dispositions, and
      cleanup of candidates/watchers/stubs/proxies/test roots.

## Phase 9 — Reconciliation and Archival

- [ ] `[AI] [AC-FC-01..13]` Reconcile all six plan documents, both C4 surfaces, behavior maps, File Impact, and
      `learnings.md` to the as-built system; route every learning to a durable owner or discard reason. **Proof:** each AC
      maps to automated/manual/release evidence and no stale channel/LiveView/single-corpus claim remains.
- [ ] `[AI] [AC-FC-01..13]` Run the plan execution check and, only if explicitly directed, the completion plan-quality
      gate; then repeat `APP_QUICK`, `INTEGRATION`, both quick/E2E targets, `RELEASE_TEST`, `REPO`, `git diff --check`, and
      process/port inventory. **Proof:** terminal completion evidence and only active route/rollback capacity retained.
- [ ] `[AI] [AC-FC-01..13]` Move—never copy—the plan to the unused
      `plans/done/YYYY-MM-DD__family-chat-room/`, set Completed status, and update stage maps/links. **Proof:** source absent,
      destination unique, `REPO` green.
- [ ] `[AI] [AC-FC-01..13]` With explicit authority, commit/push/review/rebase-merge the completion PR on
      `family-chat-room-archive`, then run the artifact cleanup workflow for the one worktree and two task branches.
      **Proof:** archive on `main`, no task worktree/branch/process/build output, and local `main` equals `origin/main`.
- [ ] `[AI] [AC-FC-01..13]` **Final checkpoint.** Confirm every checkbox and conditional is terminal, authoritative data
      retained, intended revision routed, documentation/specs/evidence agree, temporary resources absent, and archive
      exists exactly once.
