# Learnings — Family Chat Room

## Capture Timing

- Record a dated entry before editing when repository reality differs from the plan's schema, reader/writer inventory,
  browser capability, release path, or file impact.
- Record a dated entry after every phase checkpoint, migration or retry fault injection, physical-phone push test,
  rollback, routed proof, and final reconciliation.
- Amend the active plan immediately when a learning changes acceptance, technical contracts, or delivery order.

## Safe Evidence

- Allowed: revision IDs, migration versions/checksums, synthetic message IDs, generic browser families, attempt numbers,
  durations, counts from isolated fixtures, outcome categories, and pass/fail states.
- Prohibited: production usernames or IDs, message text or previews, notification endpoints, `p256dh` or auth keys, VAPID
  values, cookies, private origins, absolute runtime paths, account counts, or database contents.

## Expected Questions

- Whether `web_push_ex` 0.2.x remains compatible with the locked OTP/Elixir stack and all required browser push services.
- Whether LiveView stream prepends preserve the visible scroll anchor across each supported browser and viewport.
- Whether the two-slot outbox claim behaves correctly under a killed dispatcher and a restarted candidate.
- Whether iOS notification permission and click behavior differ between Safari tabs and installed Home Screen apps.
- Whether current release migration orchestration should be generalized or extended through a narrow family-chat verifier.

## Planning Decisions

- 2026-09-18 — The user selected permanent message retention, sender-plus-preview notification content, and a
  transactional outbox with bounded exponential backoff.
- 2026-09-18 — Five total push attempts use an immediate first attempt followed by waits of 30 seconds, 2 minutes,
  8 minutes, and 32 minutes after retryable failures, with an absolute one-hour ceiling; `404/410` is terminal and
  retires the subscription.
- 2026-09-18 — Version one exposes only `main`, but channel identity is stored from the first migration so future
  multi-channel work does not rewrite message ownership.
- 2026-09-18 — WhatsApp remains the location of older external conversation history; no import is included.
- 2026-09-18 — UI exploration selects the focused Family hearth direction over a premature channel rail and a denser
  message ledger.

## Plan Quality Gate — 2026-09-18

**Verdict: PASS.** The authorized authoring-time gate inspected the uncommitted plan snapshot based on
`ae30736c860eb1d0c5a2f4d3258551692b47d40b`. One bounded repair cycle resolved every blocking finding; no feature code,
runtime data, migration, release, or deployment was created. Delivery Phase 0 deliberately requires a fresh gate against
the later execution snapshot so this authoring result cannot mask drift.

| ID         | Blocking gap                                                                                          | Repair and proof                                                                                                    | Status |
| ---------- | ----------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------- | ------ |
| `QG-FC-01` | Execution named the disposable authoring checkout                                                     | Replaced it with repository-relative `worktrees/family-chat-room/` and future branches                              | Fixed  |
| `QG-FC-02` | Several checklist steps required an executor to reconstruct commands or staging scope                 | Added canonical guarded commands and exact per-path staging instructions                                            | Fixed  |
| `QG-FC-03` | Retry wording could mean absolute offsets or waits after failure                                      | Defined one immediate attempt plus four failure-relative waits everywhere                                           | Fixed  |
| `QG-FC-04` | Shared authorization, session ownership, and logout failure ordering were underspecified              | Bound canonical roles to a shared ownerless capability and specified digest ownership plus fail-closed logout tests | Fixed  |
| `QG-FC-05` | Arbitrary HTTPS push endpoints could create server-side request forgery or redirect egress            | Added a code-owned provider allowlist, bounded key/URL shapes, repeated pre-send validation, and redirect refusal   | Fixed  |
| `QG-FC-06` | Application merge, release, archival, and cleanup crossed one branch transaction ambiguously          | Split three delivery units while retaining exactly one implementation worktree and two reviewed PR boundaries       | Fixed  |
| `QG-FC-07` | Role tokens, visible channel copy, and two delivery-phase references did not match repository reality | Reconciled `children`/`parents`/`admin`, visible `Main`, and the Phase 0/8 references                               | Fixed  |

Primary-source feasibility was rechecked against the current `web_push_ex` package/source metadata, RFC 8291/8292,
WebKit Home Screen Web Push guidance, and browser-provider documentation. Execution must repeat dependency and provider
host validation before changing the manifest. The terminal repository gate used HIPPO receipt
`development-ephemeral-1789690848474-65010` and passed `public-safety`, `public-safety-tests`, `repo-config`,
`word-budget`, `directory-map`, `harness-parity`, `internal-link`, `mermaid`, and `plan`.

## Execution Log

No implementation phase has started.

## Destination

Before archival, resolve every entry into one durable owner: canonical specification, test, code comment, permanent
documentation, governance, deduplicated idea brief, or a recorded discard reason. Do not archive unresolved notes.
