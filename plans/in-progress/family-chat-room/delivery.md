# Delivery

## Execution Status and Authority

**Pending. No feature implementation, commit, push, migration, or deployment has started.** This checklist is the
execution contract for a later, separately authorized run. Before the first checkbox, the user must explicitly direct
both the plan quality gate and plan execution. Execution may start only from a current `PASS`; editing this plan does not
authorize that gate. Read all six plan documents and the repository's plan-execution workflow before changing product
code.

The implementation order is Gherkin → bindings → Nx RED → minimum code → Nx GREEN → refactor → smoke. A failure for an
unrelated harness or environment reason is not RED evidence. Every command below runs from the repository root. `rtk`
is mandatory. Restartable Nx compute is guarded exactly once with checksum-pinned `./hippo`; `serve`, `test:e2e`, and
`release:run` already own their required HIPPO guard and must not be wrapped again.

HIPPO recovery is fixed: exit `75` may be requeued only when its receipt says `never-started`; exit `73` requires safe
storage cleanup; exit `76` requires protocol repair; exit `78` stops execution for replanning. Never bypass the guard,
change resource class to force admission, or launch a duplicate retry.

## Canonical Commands

Checklist items name these commands so a cold executor never has to reconstruct a guard, tier, project, or target:

| ID                | Exact repository-root command                                                                                                             |
| ----------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| `UNIT`            | `rtk ./hippo run --class ephemeral --resource-tier standard --disk-path . -- npm exec -- nx run -p bnest-app -t test:unit`                |
| `INTEGRATION`     | `rtk ./hippo run --class ephemeral --resource-tier standard --disk-path . -- npm exec -- nx run -p bnest-app -t test:integration`         |
| `BEHAVIOUR`       | `rtk ./hippo run --class ephemeral --resource-tier standard --disk-path . -- npm exec -- nx run -p bnest-app -t test:coverage:behaviour`  |
| `E2E_BEHAVIOUR`   | `rtk ./hippo run --class ephemeral --resource-tier light --disk-path . -- npm exec -- nx run -p bnest-app-e2e -t test:coverage:behaviour` |
| `E2E_FAMILY_CHAT` | `rtk npm exec -- nx run -p bnest-app-e2e -t test:e2e -- --workers 1 --grep "family chat"`                                                 |
| `E2E_QUICK`       | `rtk ./hippo run --class ephemeral --resource-tier light --disk-path . -- npm exec -- nx run -p bnest-app-e2e -t test:quick`              |
| `RELEASE_TEST`    | `rtk ./hippo run --class ephemeral --resource-tier standard --disk-path . -- npm exec -- nx run -p bnest-app -t release:test`             |
| `APP_QUICK`       | `rtk ./hippo run --class ephemeral --resource-tier standard --disk-path . -- npm exec -- nx run -p bnest-app -t test:quick`               |
| `REPO`            | `rtk ./hippo run --class ephemeral --resource-tier standard --disk-path . -- npm exec -- nx run -p rhino-consumer -t test:repo`           |

`E2E_FAMILY_CHAT` and the later full `test:e2e` invocation are self-guarded by their Nx target. Never put either inside a
second HIPPO command.

## Execution Checkout

- Provision and reuse exactly one implementation checkout at repository-relative `worktrees/family-chat-room/`, starting
  on branch `family-chat-room` from current `origin/main`. Any plan-authoring checkout is not an execution checkout and
  may be gone before delivery starts.
- After the application PR lands, keep the same worktree because the completion-record unit still needs it. Sync that
  checkout to `origin/main`, then create branch `family-chat-room-archive` there for reconciliation and archival; do not
  provision a second worktree for the plan.
- `main` is the only persistent branch. Never implement from the primary checkout, directly push to `main`, or create a
  sibling `*-worktrees/` path.
- The managed production release is the sole exception: after merge, invoke it from the clean primary checkout against
  the landed `origin/main` revision as required by the Caddy deployment workflow.
- Preserve unfamiliar changes under `plans/` and `repo-governance/`. An unclean start, stale integration base, or rebase
  conflict blocks execution and is reported instead of repaired by destructive Git commands.

## Delivery Units

| Unit                  | Owner       | Transaction boundary and testable outcome                                                                                                | Rollback                                                                                       |
| --------------------- | ----------- | ---------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| DU-1 — application PR | AI executor | Branch `family-chat-room` adds specifications, additive schema, domain, LiveView, Web Push, tests, and docs; its reviewed PR lands green | Before merge, revert only this unit's thematic commits; after merge, revert through a new PR   |
| DU-2 — release        | AI executor | The landed `main` revision migrates, proves, promotes, reconnects, drains, and leaves one healthy route                                  | Managed Caddy rollback to the previous compatible release; retain additive tables and messages |
| DU-3 — completion PR  | AI executor | Branch `family-chat-room-archive` reconciles evidence and atomically archives the plan in a second reviewed PR                           | Restore the in-progress folder and indexes on the same branch before merge                     |

## Pause Safety

At every pause, append a dated, sanitized note to [`learnings.md`](learnings.md) containing the current checkout and
commit, last completed checkbox, next unresolved checkbox, exact command and result, relevant HIPPO receipt ID, active
route/candidate state, partially consumed retry or repair budget, and any deviation from File Impact. Never record a
private origin, endpoint, message, preview, user record, cookie, VAPID value or path, or push-provider response body.
Tick a checkbox only after its stated proof exists. A resumed executor continues existing attempt budgets rather than
resetting them.

## Phase 0 — Authorized Start, Drift Check, and Healthy Baseline

- [ ] `[AI] [AC-FC-01..10]` Input: an explicitly user-directed plan-quality run, this frozen plan snapshot, and the
      current repository. Action: run the plan quality gate exactly once, apply at most its two permitted bounded repair
      cycles, and record its terminal verdict in `plans/in-progress/family-chat-room/learnings.md`. Outcome: execution has a
      current `PASS`; `PASS_WITH_FINDINGS` or `FAIL` blocks this plan. Proof: the gate's dated evidence record names the
      inspected commit without private runtime data. Command: follow
      `repo-governance/workflows/plan-quality-gate.md`; do not infer or repeat authorization.
- [ ] `[AI] [AC-FC-01..10]` Input: branch `family-chat-room`, its upstream, and the approved snapshot. Action: run the
      integration-path sync gate and inspect status without discarding changes. Outcome: this worktree is clean, current,
      and contains exactly one copy of the plan. Proof: sanitized branch/base/status evidence in `learnings.md`. Commands:
      `rtk git status --short --branch`, `rtk git fetch origin`, `rtk git rebase origin/main`, and
      `rtk git merge-base --is-ancestor origin/main HEAD`; stop on dirty state or conflict.
- [ ] `[AI] [AC-FC-10]` Input: current Caddy route, active and previous slots, routed revision, SQLite readiness, and a
      representative logged-in LiveView. Action: capture the live-service baseline before application edits. Outcome: the
      route has zero failures across at least 12 exact-origin samples, p95 is at most 500 ms, every sample is at most 2 s,
      and an existing LiveView reconnects without refresh. Proof: value-free route/revision/sample/WebSocket summary in
      `learnings.md`; any failure stops work until recovery. Commands: `rtk npm exec -- nx run -p bnest-app -t proxy:status`
      plus manual `curl` of the machine-local readiness URL resolved per `docs/how-to-guides/releasing-bnest.md` without
      printing or committing the origin.
- [ ] `[AI] [AC-FC-06] [AC-FC-07]` Input: `web_push_ex` primary package/source metadata and the supported Elixir 1.18,
      OTP 27, and existing Req stack. Action: revalidate version recency, checksum, MIT licence, advisories, RFC 8291
      `aes128gcm`, RFC 8292 VAPID, vector coverage, maintenance, JOSE footprint, and the Apple/Mozilla/Chromium provider-host
      patterns in technical companion 004 before editing manifests. Outcome:
      `{:web_push_ex, "~> 0.2.0"}` remains approved or execution stops to amend this plan; no silent dependency substitute is
      allowed. Proof: source URLs, version, licence, compatibility, advisory result, and decision recorded without package
      credentials in `learnings.md`.
- [ ] `[AI] [AC-FC-01..10]` **Blocking checkpoint — Phase 0.** Confirm the current plan verdict is `PASS`, the checkout
      passed integration sync, dependency selection remains valid, and active-route health/revision/reconnect and the
      numeric responsiveness budget are green. No product file may have changed before this checkpoint.

## Phase 1 — Living Specifications and Failing Bindings

- [ ] `[AI] [AC-FC-01..10]` Input: the PRD scenarios and existing behaviour vocabulary. Action: add
      `specs/apps/bnest/app/behaviours/family_chat.feature`, update
      `specs/apps/bnest/app/behaviours/authentication.feature` and
      `specs/apps/bnest/app/behaviours/scheduled_backups.feature`, and map the corpus from
      `specs/apps/bnest/app/behaviours/README.md`. Outcome: the canonical specification covers authentication, durable text,
      paging, restart, push, retry, privacy, accessibility, and continuity without copying implementation detail. Proof:
      manual Gherkin review under `repo-governance/workflows/gherkin-implementation-review.md` records every scenario as
      observable, singular, and falsifiable.
- [ ] `[AI] [AC-FC-01..10]` **RED** — Input: the reviewed corpus. Action: add
      `apps/bnest-app/test/behaviour/steps/family_chat_steps.exs`, update the unit/integration behaviour drivers listed in
      [File Impact](tech-docs/007-file-impact-dependencies-and-operations.md), and add browser bindings in
      `apps/bnest-app-e2e/tests/steps/family-chat.steps.ts`. Outcome: every step is bound at its correct layer and fails only
      because family-chat behavior is absent. Proof: save the named failing scenarios and assertions. Command:
      `rtk ./hippo run --class ephemeral --resource-tier standard --disk-path . -- npm exec -- nx run -p bnest-app -t test:coverage:behaviour`.
- [ ] `[AI] [AC-FC-01..10]` Input: both adapter sets. Action: run the browser behaviour-compliance check and classify
      physical installed-PWA notification display as the sole browser-automation boundary exemption; no product scenario is
      replaced by an outcome table or no-op step. Outcome: all automatable scenarios have bindings and the physical proof
      remains an explicit later item. Proof: compliance output and exemption rationale. Command:
      `rtk ./hippo run --class ephemeral --resource-tier light --disk-path . -- npm exec -- nx run -p bnest-app-e2e -t test:coverage:behaviour`.
- [ ] `[AI] [AC-FC-01..10]` **Blocking checkpoint — Phase 1.** Confirm the Gherkin review is complete, both adapter
      inventories have no undefined or ambiguous steps, and the Elixir behavior run is red only for named missing
      family-chat outcomes.

## Phase 2 — Additive SQLite Foundation and Domain Contract

- [ ] `[AI] [AC-FC-04] [AC-FC-07] [AC-FC-08]` **RED** — Action: add
      `apps/bnest-app/test/integration/bnest_app/family_chat_migration_test.exs` with isolated marked SQLite roots covering
      fresh migration, repeat migration, exactly one `main` seed, all four schemas/indexes/triggers, audit columns,
      prior-release overlap, and forbidden destructive down migration after data. Expected failure: the migration and
      release verifier do not exist. Command:
      `rtk ./hippo run --class ephemeral --resource-tier standard --disk-path . -- npm exec -- nx run -p bnest-app -t test:integration`.
- [ ] `[AI] [AC-FC-04] [AC-FC-07] [AC-FC-08]` **GREEN** — Action: add
      `apps/bnest-app/priv/sqlite_repo/migrations/20260918000000_add_family_chat.exs`,
      `apps/bnest-app/lib/bnest_app/release/migrations/family_chat.ex`, and the general coordinator at
      `apps/bnest-app/lib/bnest_app/release/migrations.ex`; minimally update the existing persistent-schedules verifier and
      release manifest tooling. Expected pass: exact DDL, constraints, indexes, immutable-message triggers, idempotent seed,
      schema verification, and old-reader compatibility pass. Command: `INTEGRATION`.
- [ ] `[AI] [AC-FC-04] [AC-FC-07] [AC-FC-08]` **REFACTOR** — Action: centralize release migration ordering and feature
      verification without changing schema or broadening fallback behavior; update
      `apps/bnest-app/tools/release.test.mjs` and `apps/bnest-app/tools/continuity-contract.test.mjs`. Expected pass: migration
      tests and release tooling remain green, and no migration runs during slot startup. Commands:
      `rtk ./hippo run --class ephemeral --resource-tier standard --disk-path . -- npm exec -- nx run -p bnest-app -t test:integration`
      and `rtk ./hippo run --class ephemeral --resource-tier light --disk-path . -- npm exec -- nx run -p bnest-app -t release:test`.
- [ ] `[AI] [AC-FC-02] [AC-FC-03] [AC-FC-04]` **RED** — Action: add
      `apps/bnest-app/test/unit/bnest_app/family_chat_test.exs` and
      `apps/bnest-app/test/integration/bnest_app/family_chat_test.exs` for `main` lookup, latest/older keyset pages,
      chronological integer-ID ordering, 50-row page/51-row probe, 4,000-grapheme and 16-KiB limits, literal markup,
      immutable rows, permanent retention, and per-author client UUID idempotency. Expected failure: the context/store do not
      exist. Commands: `UNIT`, then `INTEGRATION`.
- [ ] `[AI] [AC-FC-02] [AC-FC-03] [AC-FC-04]` **GREEN** — Action: add
      `apps/bnest-app/lib/bnest_app/family_chat.ex`, `family_chat/message.ex`, and `family_chat/store.ex` with the exact
      transaction/query contracts in technical docs 002 and 003. Expected pass: the domain tests pass against isolated
      SQLite with no network, real user, or production path. Commands: `UNIT`, then `INTEGRATION`.
- [ ] `[AI] [AC-FC-02] [AC-FC-03] [AC-FC-04]` **REFACTOR** — Action: keep validation and query construction behind the
      context/store boundary, remove duplicate SQL/limit constants, and keep message order based only on database ID.
      Expected pass: both suites remain green and no caller accepts a user-supplied author identity. Commands: `UNIT`, then
      `INTEGRATION`.
- [ ] `[AI] [AC-FC-02] [AC-FC-03] [AC-FC-04]` **Blocking checkpoint — Phase 2.** Confirm migration/release tests, unit
      tests, and integration tests pass; the seeded channel is exactly `main`; previous code ignores additive tables; and
      no test accessed production data.

## Phase 3 — Authenticated Realtime Room and Upward History

- [ ] `[AI] [AC-FC-01] [AC-FC-02] [AC-FC-08]` **RED** — Action: add
      `apps/bnest-app/test/integration/bnest_app_web/family_chat_live_test.exs` for all approved roles, logged-out safe return,
      missing capability, literal text, invalid text, two connected clients, commit-before-broadcast, duplicate submission,
      storage failure, and composer clearing only after commit; update `test/unit/bnest_app/identity_policy_test.exs` and
      `test/integration/bnest_app/identity_test.exs` for shared capability allow/deny behavior, and extend
      `test/integration/bnest_app_web/authentication_test.exs` to require an HTTP-only Phoenix session with no digest in DOM
      or logs. Expected failure: route, authorization capability, home link, and LiveView do not exist. Commands: `UNIT`,
      then `INTEGRATION`.
- [ ] `[AI] [AC-FC-01] [AC-FC-02] [AC-FC-08]` **GREEN** — Action: add
      `apps/bnest-app/lib/bnest_app_web/live/family_chat_live.ex`; minimally update `endpoint.ex`, `router.ex`, `user_auth.ex`,
      `page_html/home.html.heex`, `identity.ex`, `identity/session.ex`, and `identity/authorization.ex` to expose a
      server-owned session digest and a shared—not self-owned—`use_family_chat` capability. Expected pass: authorized
      members exchange one committed message through scoped PubSub, malformed roles remain denied, anonymous users see none,
      and duplicate client UUIDs remain one row. Commands: `UNIT`, then `INTEGRATION`.
- [ ] `[AI] [AC-FC-01] [AC-FC-02] [AC-FC-08]` **REFACTOR** — Action: move PubSub topic construction and LiveView event
      parsing behind the family-chat boundary, retaining one `main` channel parameter instead of a global unscoped topic.
      Expected pass: unchanged LiveView and domain results with no hand-built topic outside the context. Commands: `UNIT`,
      then `INTEGRATION`.
- [ ] `[AI] [AC-FC-03] [AC-FC-09]` **RED** — Action: extend the LiveView test and add
      `apps/bnest-app/assets/js/family_chat.js` hook tests through the browser adapter for latest 50, two older pages, terminal
      history, anchor preservation, live arrival away from bottom, the new-message control, reconnect, and retained unsent
      draft. Expected failure: paging/hook behavior is absent. Commands: `INTEGRATION`, then `E2E_FAMILY_CHAT`.
- [ ] `[AI] [AC-FC-03] [AC-FC-09]` **GREEN** — Action: implement the history sentinel and hook in
      `family_chat_live.ex` and `assets/js/family_chat.js`, register it from `assets/js/app.js`, fetch older rows with the
      oldest loaded ID, restore the scroll anchor after prepend, and auto-follow only within 80 px of the bottom. Expected
      pass: pages never duplicate, reading position is stable, and reconnect neither loses the draft nor inserts twice.
      Commands: `INTEGRATION`, then `E2E_FAMILY_CHAT`.
- [ ] `[AI] [AC-FC-03] [AC-FC-09]` **REFACTOR** — Action: consolidate client event names, DOM data attributes, and
      scroll-threshold constants; remove timing sleeps from tests in favor of LiveView/browser readiness. Expected pass:
      unchanged integration and E2E results with all task-created tabs/contexts closed. Commands: `INTEGRATION`, then
      `E2E_FAMILY_CHAT`.
- [ ] `[AI] [AC-FC-01] [AC-FC-02] [AC-FC-03] [AC-FC-09]` **Blocking checkpoint — Phase 3.** Confirm access control,
      commit/broadcast ordering, UUID idempotency, exact 50-message windows, stable upward scrolling, near-bottom behavior,
      draft recovery, and connected LiveView proof are green.

## Phase 4 — Web Push, Transactional Outbox, and Privacy

- [ ] `[AI] [AC-FC-06] [AC-FC-07]` **RED** — Action: add
      `apps/bnest-app/test/unit/bnest_app/push_notifications/policy_test.exs` and `sender_test.exs` for sender-plus-preview
      payloads, grapheme-safe 120-character collapse, self-exclusion, exact approved provider hosts, rejection of IP/userinfo/
      port/fragment/unapproved endpoints without egress, redirect refusal, response classification, no diagnostic secrets, and
      an immediate attempt followed by waits of `30 s`, `2 m`, `8 m`, and `32 m`, with five total attempts and a one-hour
      ceiling. Expected failure: policy
      and sender modules do not exist. Command: `UNIT`.
- [ ] `[AI] [AC-FC-06] [AC-FC-07]` **GREEN** — Action: add `push_notifications.ex`, `policy.ex`, and `sender.ex`; add the
      revalidated dependency to `apps/bnest-app/mix.exs` and its checksum-resolved lock entry to `mix.lock`; use Req only at
      the injected sender boundary with redirects disabled and repeat endpoint validation immediately before send. Expected
      pass: payload and response policy tests pass without filesystem, database, process, or real network access. Command:
      `UNIT`.
- [ ] `[AI] [AC-FC-06] [AC-FC-07]` **REFACTOR** — Action: keep cryptography/library request construction inside the
      sender and pure retry/privacy decisions inside policy, with typed outcomes consumed by the dispatcher. Expected pass:
      unchanged unit results and `mix deps.unlock --check-unused` succeeds through the later lint gate. Command: `UNIT`.
- [ ] `[AI] [AC-FC-06] [AC-FC-07]` **RED** — Action: add
      `apps/bnest-app/test/integration/bnest_app/push_notifications_test.exs` using an injected clock and loopback stub for
      message/outbox atomicity, one row per active non-sender subscription, leases, expired-claim recovery, concurrent
      dispatchers, every response class, five-attempt ceiling, 404/410 retirement, and restart resume. Expected failure: the
      dispatcher and supervision are absent. Command: `INTEGRATION`.
- [ ] `[AI] [AC-FC-06] [AC-FC-07]` **GREEN** — Action: add `push_notifications/dispatcher.ex`; supervise its dedicated
      task supervisor and process from `apps/bnest-app/lib/bnest_app/application.ex`; insert delivery rows in the same SQLite
      transaction as the message and claim bounded batches with expiring leases. Expected pass: no committed message lacks
      intended jobs, concurrent claims do not duplicate an attempt, and interrupted work resumes within the fixed ceiling.
      Command: `INTEGRATION`.
- [ ] `[AI] [AC-FC-06] [AC-FC-07]` **REFACTOR** — Action: isolate claim, outcome, reschedule, and subscription-retirement
      transitions in the store boundary and keep dispatcher logs categorical. Expected pass: unchanged integration results
      and captured logs contain no endpoint, key, message body, or preview. Command: `INTEGRATION`.
- [ ] `[AI] [AC-FC-05] [AC-FC-08]` **RED** — Action: extend LiveView/browser tests for explicit user-gesture opt-in,
      supported/denied/unsupported/not-installed copy, session-scoped enable/disable, two-device independence, logout of one
      session, fail-closed subscription-store error during logout, notification activation, and absence of authenticated
      content in Cache Storage. Update `test/integration/bnest_app_web/authentication_test.exs`. Expected failure:
      subscription events and static-only worker behavior are absent. Commands: `INTEGRATION`, then `E2E_FAMILY_CHAT`.
- [ ] `[AI] [AC-FC-05] [AC-FC-08]` **GREEN** — Action: update `family_chat_live.ex`, `user_auth.ex`,
      `controllers/session_controller.ex`, `assets/js/app.js`, `priv/static/service-worker.js`, and
      `priv/static/manifest.webmanifest` so a gesture exchanges a subscription through authenticated LiveView, logout
      retires only the current `session_digest` before revocation/cookie clearing, refuses partial logout on store failure,
      focuses/opens `/family-chat` on notification click, and never caches runtime/auth responses. Expected pass: chat stays
      usable in every push state and Cache Storage contains explicit static assets only. Commands: `INTEGRATION`, then
      `E2E_FAMILY_CHAT`.
- [ ] `[AI] [AC-FC-05] [AC-FC-08]` **REFACTOR** — Action: centralize browser capability-state mapping and service-worker
      cache allowlisting, delete broad successful-GET caching, and retain no endpoint or key in DOM attributes, logs, or
      evidence. Expected pass: unchanged integration/E2E results and a post-logout cache inspection is clean. Commands:
      `INTEGRATION`, then `E2E_FAMILY_CHAT`.
- [ ] `[AI] [AC-FC-05..08]` **Blocking checkpoint — Phase 4.** Confirm transactionally complete fan-out, exact retry
      waits/ceiling, dead-subscription retirement, restart recovery, self-exclusion, session-scoped disable/logout,
      static-only caching, safe logs, and no real push endpoint or user data in tests.

## Phase 5 — Selected UI, Accessibility, and Complete Behavior

- [ ] `[AI] [AC-FC-09]` **RED** — Action: add responsive and accessibility assertions to
      `family_chat_live_test.exs` and `apps/bnest-app-e2e/tests/steps/family-chat.steps.ts` for every state named by AC-FC-09,
      desktop `1280×800`, tablet `768×1024`, mobile `393×852`, 200% zoom, keyboard order, visible focus, live regions,
      minimum 44-pixel targets, reduced motion, and no horizontal page scroll. Expected failure: selected Family-hearth
      styles and some semantics are absent. Commands: `INTEGRATION`, then `E2E_FAMILY_CHAT`.
- [ ] `[AI] [AC-FC-09]` **GREEN** — Action: implement the selected direction from
      `tech-docs/005-ui-design.md` in `family_chat_live.ex` and `apps/bnest-app/assets/css/app.css`, using the existing ink,
      paper, lagoon, sun, and coral tokens and the documented real copy/states. Expected pass: all automated viewport and
      accessibility assertions pass without introducing a fake channel switcher. Commands: `INTEGRATION`, then
      `E2E_FAMILY_CHAT`.
- [ ] `[AI] [AC-FC-09]` **REFACTOR** — Action: remove duplicated style/state branches, preserve semantic source order,
      and ensure dynamic announcements never steal composer focus. Expected pass: unchanged integration/E2E results and
      screenshot comparison remains faithful to the three selected hi-fi assets. Commands: `INTEGRATION`, then
      `E2E_FAMILY_CHAT`.
- [ ] `[AI] [AC-FC-01..09]` Input: completed implementation and both behavior adapters. Action: finish the minimum code
      for every bound family-chat scenario and rerun recursive behavior coverage. Outcome: no undefined, ambiguous, unused,
      placeholder, no-op, or outcome-table binding remains. Proof: both behavior gates green. Commands:
      `rtk ./hippo run --class ephemeral --resource-tier standard --disk-path . -- npm exec -- nx run -p bnest-app -t test:coverage:behaviour`
      and `rtk ./hippo run --class ephemeral --resource-tier light --disk-path . -- npm exec -- nx run -p bnest-app-e2e -t test:coverage:behaviour`.
- [ ] `[AI] [AC-FC-09]` Input: the exact local served origin and isolated `test-user-` identities. Action: perform the
      spec-aware exploratory pass across authentication, empty/populated/error/history/push states and all three viewport
      classes, including keyboard, 200% zoom, reduced motion, reconnect, and passive security signals. Outcome: edge cases
      beyond scripted assertions are assessed. Proof: sanitized route/state/viewport findings under `## Exploratory
findings` in `learnings.md`, or an explicit none-found result.
- [ ] `[AI] [AC-FC-09]` Input: only the origin, route, and viewport classes—not the PRD, source, tests, or mockups. Action:
      run the structurally spec-blind usability pass in a fresh context. Outcome: first-time discoverability, chronology,
      history loading, notification choice, error recovery, and composer clarity are independently judged. Proof: separate
      `## Usability findings` in `learnings.md`; shared root causes cross-reference rather than duplicate findings.
- [ ] `[AI] [AC-FC-09]` Input: accepted findings from either manual pass. Action: reconcile each behavioral gap through
      Gherkin → binding → expected RED → minimum GREEN → refactor before marking it resolved. Outcome: no accepted behavior
      change exists only in code or prose. Proof: per-finding test evidence and updated specification; if none are accepted,
      record `Not applicable — no accepted behavior gap`.
- [ ] `[AI] [AC-FC-01..09]` **Blocking checkpoint — Phase 5.** Confirm every automatable acceptance scenario is green,
      the responsive/accessibility matrix passed, both distinctly labelled manual passes are recorded, accepted findings
      were reconciled, and all browser contexts created for testing are closed.

## Phase 6 — Configuration, Documentation, and Non-production Gates

- [ ] `[AI] [AC-FC-05..08]` Input: tested runtime contracts. Action: update `config/config.exs`, `config/runtime.exs`, and
      `config/test.exs` with injected clock/sender/tick defaults and validated VAPID public/private/subject configuration;
      production fails closed when values are absent or malformed while development renders push unavailable. Outcome:
      secrets remain machine-local and tests remain deterministic. Proof: configuration tests plus captured diagnostics show
      booleans/categories only. Commands: `UNIT`, then `INTEGRATION`.
- [ ] `[AI] [AC-FC-04..08]` Input: final migration, dispatcher, and configuration behavior. Action: update
      `health_controller.ex`, `tools/deployment.mjs`, `tools/release.mjs`, `release.test.mjs`, and
      `continuity-contract.test.mjs` to prove schema/seed/dispatcher/configured readiness and the manifest checksum without
      exposing values. Outcome: candidate readiness fails closed for missing production push configuration. Proof: release
      tests green. Command:
      `rtk ./hippo run --class ephemeral --resource-tier standard --disk-path . -- npm exec -- nx run -p bnest-app -t release:test`.
- [ ] `[AI] [AC-FC-01..10]` Input: the final as-built system. Action: update
      `specs/apps/bnest/app/architecture.md` in its affected System Context, Container, Component, and Architectural
      Constraints views and update `specs/apps/bnest/app/README.md` traceability. Outcome: the canonical C4 model describes
      family chat, SQLite authority, PubSub, Web Push, Caddy, trust boundaries, and future channel scope as built. Proof:
      `REPO` passes its Mermaid and specification checks.
- [ ] `[AI] [AC-FC-01..10]` Input: final commands and maintenance surface. Action: update `README.md`,
      `apps/bnest-app/README.md`, and `apps/bnest-app-e2e/README.md` with route ownership, configuration categories,
      test targets, data retention, and troubleshooting, then maintain affected directory maps and links. Outcome: a junior
      maintainer can operate and test the feature without reading this plan. Proof: `REPO` passes.
- [ ] `[AI] [AC-FC-01..10]` Input: every execution-created or modified repository rule, if any. Action: apply
      `repo-governance/workflows/rules-propagation.md` only to the bounded rule delta and record its terminal result; if no
      rule changed, run its inventory/remainder check and record `PASS_NO_CHANGE`. Outcome: rules do not silently drift.
      Proof: terminal workflow record in `learnings.md` and repository gate green.
- [ ] `[AI] [AC-FC-01..09]` Input: all non-production code. Action: run the app quick and integration gates serially.
      Outcome: typecheck, lint, unit, behavior coverage, dependency hygiene, and integration are green. Proof: exact command
      outputs recorded. Commands:
      `rtk ./hippo run --class ephemeral --resource-tier standard --disk-path . -- npm exec -- nx run -p bnest-app -t test:quick`
      and `rtk ./hippo run --class ephemeral --resource-tier standard --disk-path . -- npm exec -- nx run -p bnest-app -t test:integration`.
- [ ] `[AI] [AC-FC-01..09]` Input: all browser code and isolated runtime fixtures. Action: run E2E quick, then the full
      self-guarded E2E target serially at its leased exact origin. Outcome: static checks, behavior compliance, desktop,
      tablet, mobile, reconnect, and cache behavior pass with synthetic users. Proof: green target summaries and no leaked
      tabs, contexts, port leases, or test roots. Commands:
      `rtk ./hippo run --class ephemeral --resource-tier light --disk-path . -- npm exec -- nx run -p bnest-app-e2e -t test:quick`
      and `rtk npm exec -- nx run -p bnest-app-e2e -t test:e2e`.
- [ ] `[AI] [AC-FC-01..10]` Input: completed code/spec/docs. Action: run the repository gate and inspect the complete
      diff for public-data safety, prohibited values, accidental runtime data, whitespace, links, maps, Mermaid limits, and
      undeclared File Impact. Outcome: the PR is safe and internally consistent. Proof: green gate, `git diff --check`,
      sanitized secret/path scan summary, and reconciled File Impact. Commands:
      `rtk ./hippo run --class ephemeral --resource-tier standard --disk-path . -- npm exec -- nx run -p rhino-consumer -t test:repo`,
      `rtk git diff --check`, and `rtk git status --short`.
- [ ] `[AI] [AC-FC-01..10]` **Blocking checkpoint — Phase 6.** Confirm all app, browser, release, repository, data-safety,
      documentation, architecture, and rule-propagation results are green with no untracked runtime fixture or unneeded
      local process.

## Phase 7 — Thematic Commits and PR Integration

- [ ] `[AI] [AC-FC-01..10]` Input: explicit commit authorization and the green Phase 6 diff. Action: stage the coherent
      DU-1 paths, inspect the staged diff, and create one thematic commit without rewriting user commits. Outcome: the whole
      deployable family-chat increment is reviewable and contains no secret or runtime data. Proof: staged file inventory,
      staged public-data-safety review, and passing commit hooks. Commands: run
      `rtk git add -- <exact-path>` once for every reconciled `[N]` or `[E]` path in File Impact, then run
      `rtk git diff --cached --check`, `rtk git diff --cached --stat`, and
      `rtk git commit -m "feat(bnest): add family chat room"`; any hook failure is fixed at root, never bypassed.
- [ ] `[AI] [AC-FC-01..10]` Input: explicit push authorization and the committed branch. Action: push
      `family-chat-room` to its same-named origin branch. Outcome: no commit exists only locally. Proof:
      `rtk git log family-chat-room --not --remotes` prints nothing after
      `rtk git push -u origin family-chat-room`.
- [ ] `[AI] [AC-FC-01..10]` Input: the pushed branch and a sanitized PR body at
      `local-tmp/family-chat-room-pr.md`. Action: open one draft PR against `main`. Outcome: DU-1 has one branch and one PR;
      no private origin or runtime evidence appears in its body. Proof: returned PR identifier. Command:
      `rtk gh pr create --draft --base main --head family-chat-room --title "feat(bnest): add family chat room" --body-file local-tmp/family-chat-room-pr.md`.
- [ ] `[AI] [AC-FC-01..10]` Input: finished DU-1 and its exact-head merge preconditions. Action: mark the draft ready.
      Outcome: readiness truthfully states that the increment is complete. Proof: GitHub reports the PR ready. Command:
      `rtk gh pr ready <application-pr-number>`.
- [ ] `[AI] [AC-FC-01..10]` Input: the ready PR with exact-head green Quality gate, posted passing leak review, branch
      currency, resolved conversations, and green surface gates. Action: merge by rebase without bypass. Outcome: `main` is
      the release source. Proof: GitHub reports the PR merged at the reviewed head and the landed diff matches DU-1. Command:
      `rtk gh pr merge <application-pr-number> --rebase --delete-branch`.
- [ ] `[AI] [AC-FC-01..10]` Input: the merged application PR and clean retained worktree. Action: fetch/prune, reconcile
      the checkout to landed `origin/main`, and create `family-chat-room-archive` in that same worktree. Outcome: completion
      evidence will be authored on a fresh branch without provisioning another worktree. Proof: clean status, merge-base
      success, and current branch name. Commands: `rtk git status --short`, `rtk git fetch origin --prune`,
      `rtk git switch -c family-chat-room-archive origin/main`, and
      `rtk git merge-base --is-ancestor origin/main HEAD`.
- [ ] `[AI] [AC-FC-01..10]` **Blocking checkpoint — Phase 7.** Confirm the exact reviewed application revision is on
      `main`, CI is green, and the one plan worktree is clean on `family-chat-room-archive` for DU-3.

## Phase 8 — Continuity-safe Production Release

- [ ] `[HUMAN] [AC-FC-05] [AC-FC-10]` Input: access to machine-local deployment secrets unavailable to the executor, if
      applicable. Action: place a generated VAPID public-key file, private-key file, and validated `mailto:` or HTTPS subject
      in the existing protected deployment location and report only `configured: true`; never paste values or paths into
      Git, chat, logs, or plan evidence. Outcome: the managed release can consume production push configuration. Proof:
      external operator confirms file modes and availability without revealing content. If the executor already has
      authorized access, relabel this one item `[AI]` before execution and record why.
- [ ] `[AI] [AC-FC-10]` Input: clean primary checkout at the landed `origin/main` revision and the still-healthy active
      route. Action: repeat the value-free 12-sample/revision/connected-LiveView baseline and confirm release capacity and
      protected configuration presence. Outcome: release starts only while the old revision is healthy with zero failures,
      p95 ≤500 ms, max ≤2 s, and configuration readiness true. Proof: sanitized preflight record; any failure invokes the
      first recovery item. Commands: `rtk npm exec -- nx run -p bnest-app -t proxy:status` and the release guide's private
      exact-origin readiness/sample procedure.
- [ ] `[AI] [AC-FC-04..10]` Input: the landed revision and healthy baseline. Action: execute the single managed release
      transaction, which owns build, locks, additive migration verification, inactive candidate, direct revision/readiness,
      connected LiveView proof, Caddy promotion, routed proof, five-minute drain, retention, and cleanup. Outcome: the
      intended revision serves through Caddy and Tailscale while the prior backend remains available until proof completes.
      Proof: sanitized release evidence IDs, migration checksum/outcome, candidate/routed revision match, zero failed
      samples, p95 ≤500 ms, max ≤2 s, and one active listener. Command:
      `rtk npm exec -- nx run -p bnest-app -t release:run -- --revision <landed-main-sha>` (self-guarded transactional target;
      never add an outer HIPPO invocation).
- [ ] `[AI] [AC-FC-01..10]` Input: the routed intended revision and two isolated synthetic accounts. Action: manually
      `curl` readiness/revision and exercise login → home → Family chat, two-user send, upward paging, literal markup,
      notification settings, an existing non-chat journey, and LiveView/WebSocket reconnect with one unsent draft and no
      refresh. Outcome: the routed application—not merely the candidate—serves the intended behavior and existing paths
      remain compatible. Proof: value-free pass/fail by operation; no product REST/GraphQL curl is invented because none was
      added.
- [ ] `[HUMAN] [AC-FC-05] [AC-FC-06] [AC-FC-08]` Input: one supported physical phone with the routed PWA installed and
      two synthetic accounts. Action: explicitly enable notifications, background/close the PWA, send a synthetic message
      from the other account, inspect sender plus ≤120-grapheme preview, activate it, verify `/family-chat`, disable the
      device, and prove a later message produces no notification. Outcome: the physical OS boundary and per-device opt-out
      work. Proof: a sanitized pass/fail matrix without screenshot content, endpoint, key, account, origin, or message text.
- [ ] `[AI] [AC-FC-04] [AC-FC-08]` Input: the next independent production SQLite backup created by the existing schedule.
      Action: verify its receipt/checksum, open a copy in an isolated restore root, prove the four schemas, `main` seed, and
      synthetic structural state through the normal family-chat boundary, then remove only the marked restore fixture.
      Outcome: backup/restore covers the additive data without touching live records. Proof: structural counts/categories,
      integrity result, and cleanup; never copy transcript text into evidence.
- [ ] `[AI] [AC-FC-10]` **Recovery, only if triggered before or during candidate proof** — Input: unhealthy baseline,
      migration error, candidate mismatch, readiness failure, or HIPPO terminal receipt. Action: keep the prior route
      authoritative, preserve SQLite and safe evidence, release managed locks, retire only the failed candidate, and stop
      until diagnosis or replan. Outcome: no unsafe promotion or destructive schema change. Proof: prior routed revision and
      critical journey green. If never triggered, record dated `Not triggered` with the successful managed-release proof.
- [ ] `[AI] [AC-FC-10]` **Recovery, only if triggered after promotion** — Input: routed failure, wrong revision,
      LiveView/WebSocket recovery failure, any sample >2 s, rolling-minute p95 >500 ms, secret exposure, or defective
      dispatcher/configuration. Action: run the managed Caddy rollback to the prior compatible release, verify route and
      revision, bounded-drain/retire the rejected candidate, and retain additive tables/messages. Outcome: the last healthy
      release serves with no data loss. Proof: `proxy:status`, routed readiness/revision, and critical journey green. If
      never triggered, record dated `Not triggered`.
- [ ] `[AI] [AC-FC-07]` **Recovery, only if a push provider is unavailable** — Input: categorized retryable provider
      failures with otherwise healthy chat. Action: leave the healthy chat release active and observe the bounded outbox to
      its fixed ceiling; do not retry manually or roll back solely for provider unavailability. Outcome: delivery remains
      best-effort and no sixth attempt occurs. Proof: aggregate state/attempt categories only. If never triggered, record
      dated `Not triggered`.
- [ ] `[AI] [AC-FC-01..10]` **Blocking checkpoint — Phase 8.** Confirm intended routed revision, schema/seed/dispatcher
      readiness, two-user chat, existing journey, no-refresh reconnect with draft, physical-phone result, backup/restore,
      numeric responsiveness from preflight through drain, recovery dispositions, and cleanup of every unneeded candidate,
      watcher, proxy, stub, test root, and inactive listener.

## Phase 9 — Reconciliation and Archival

- [ ] `[AI] [AC-FC-01..10]` Input: the implementation diff, routed evidence, manual findings, and recovery dispositions.
      Action: reconcile `README.md`, `brd.md`, `prd.md`, every technical companion, File Impact, and `learnings.md` to the
      as-built system; record deviations and discovered helpers rather than rewriting history. Outcome: the six-document
      plan and canonical specs tell the same truth. Proof: criterion-to-evidence review has no unresolved acceptance item.
- [ ] `[AI] [AC-FC-01..10]` Input: all substantive terminal items. Action: run the plan execution check and record its
      verdict; separately run a completion plan-quality gate only when the user explicitly directs it. Outcome: archival is
      blocked by any unresolved item, activated recovery, finding, data-safety issue, dirty runtime, or non-terminal gate.
      Proof: execution-check record and, if authorized, completion quality-gate record against named commits.
- [ ] `[AI] [AC-FC-01..10]` Input: reconciled docs and clean runtime. Action: rerun the complete completion verification
      serially. Outcome: completion evidence is current and only the active route plus intended rollback capacity remains.
      Proof: dated command results in `learnings.md`. Commands: `APP_QUICK`, `INTEGRATION`, `E2E_QUICK`,
      `rtk npm exec -- nx run -p bnest-app-e2e -t test:e2e`, `RELEASE_TEST`, `REPO`, `rtk git diff --check`, and the
      process/port inventory named by the live-service continuity workflow.
- [ ] `[AI] [AC-FC-01..10]` Input: verified archive readiness and final local date. Action: refuse an existing destination,
      then atomically move—never copy—this directory to `plans/done/YYYY-MM-DD__family-chat-room/`, set README status to
      Completed, and update both stage indexes and every live inbound link. Outcome: the completion record exists once on
      `family-chat-room-archive`. Proof: absent source, unique destination, reconciled links/maps, and `REPO` green after the
      move.
- [ ] `[AI] [AC-FC-01..10]` Input: the green archived diff and explicit commit authorization. Action: create one thematic
      completion-record commit on `family-chat-room-archive`. Outcome: archival is reviewable and reversible before merge.
      Proof: staged diff contains only the reconciled record, lifecycle move, and maps; commit hooks pass without bypass.
      Commands: `rtk git add -A -- plans/in-progress/family-chat-room plans/in-progress/README.md plans/done/README.md plans/done/YYYY-MM-DD__family-chat-room`,
      `rtk git diff --cached --check`, and `rtk git commit -m "docs(plans): archive family chat room"`.
- [ ] `[AI] [AC-FC-01..10]` Input: explicit push authorization and the completion-record commit. Action: push
      `family-chat-room-archive`. Outcome: no completion commit exists only locally. Proof:
      `rtk git log family-chat-room-archive --not --remotes` prints nothing after
      `rtk git push -u origin family-chat-room-archive`.
- [ ] `[AI] [AC-FC-01..10]` Input: the pushed completion branch and sanitized body at
      `local-tmp/family-chat-room-archive-pr.md`. Action: open its one draft PR against `main`. Outcome: DU-3 has one branch
      and one PR. Proof: returned PR identifier and body explaining the archival transaction and deployable state. Command:
      `rtk gh pr create --draft --base main --head family-chat-room-archive --title "docs(plans): archive family chat room" --body-file local-tmp/family-chat-room-archive-pr.md`.
- [ ] `[AI] [AC-FC-01..10]` Input: finished DU-3 and its exact-head merge preconditions. Action: mark the completion PR
      ready. Outcome: readiness truthfully states that reconciliation and archival are complete. Proof: GitHub reports the
      PR ready. Command: `rtk gh pr ready <completion-pr-number>`.
- [ ] `[AI] [AC-FC-01..10]` Input: the ready completion PR with exact-head green Quality gate, posted passing leak
      review, branch currency, resolved conversations, and green surface gates. Action: merge by rebase without bypass.
      Outcome: the archived record lands on `main`. Proof: GitHub reports the PR merged at the reviewed head. Command:
      `rtk gh pr merge <completion-pr-number> --rebase --delete-branch`.
- [ ] `[AI] [AC-FC-01..10]` Input: every delivery unit landed and no process running in the plan worktree. Action: from
      the primary checkout, execute `repo-governance/workflows/dev-artifact-clean-up.md` for
      `worktrees/family-chat-room/`, local branches `family-chat-room` and `family-chat-room-archive`, any surviving remote
      copies, and this work's regenerable build output only. Outcome: task artifacts are gone and local `main` equals
      `origin/main`. Proof: no listed worktree/branch/remote branch, purged owned build output, and
      `rtk git rev-list --left-right --count HEAD...origin/main` returns `0 0`; never delete `.env*` or unrelated artifacts.
- [ ] `[AI] [AC-FC-01..10]` **Final checkpoint.** Confirm all criteria and checkboxes are terminal; every conditional has
      executed proof or dated `Not triggered`; the authoritative SQLite data is retained; the intended revision is routed;
      physical and automated verification are recorded; docs/specs/learnings agree; temporary resources are absent; and
      the archive exists exactly once before reporting completion.
