# Browser Suite Timing Reliability

The family-chat browser scenarios release a real pointer, or wait on a real socket, against margins measured in
tens of milliseconds. Two of them lose that race often enough to turn a declared gate red on an unchanged tree.
Provenance: measured 2026-09-22 during the third execution check of `family-chat-message-reply`, one fixed and one
still open.

## Problem / Context

**A gate that is red for timing reasons stops being evidence.** `FE_E2E` is named as the proof for eleven
frontend scenarios. A full run on an unchanged tree returned 299 tests, 297 passed, 2 failed; a second run after
one fix returned 298 passed, 1 failed, with a different scenario failing. Nothing about the application changed
between them.

**One cause is now understood, and it was in the harness rather than the application.** `A member opens the
message action menu` released the pointer `holdMs + 50` after pressing it. The release calls the application's
`gesture.end()`, which clears the `setTimeout(500)` the assertion is waiting on, so any event-loop delay past
50 ms cancelled the gesture. A trace showed the pointer down on the correct message for 559 ms with no
`pointercancel`, no `pointermove` and no DOM mutation — the timer simply had not fired. Fixed by holding until
the menu appears: 121 for 121 afterwards, against a baseline of two failures in twenty-four.

**A third cause, wider than both, surfaced on 2026-09-23.** Five full runs on an unchanged tree returned five
different results: 297/2, 298/1, 299/0, 293/6, 299/0. The 293/6 run failed on release infrastructure rather than
on product assertions — `routed SQLite activation failed: ** (RuntimeError) storage drain lock timed out`, and a
`data-connection-state` stuck at `booting` past 15 s — and took the whole `Reconnect across Caddy promotion` rule
with it, plus two scenarios outside family chat entirely (`chat.feature`'s LiveView reconnect and
`scheduled_backups.feature`). It followed a previous full run back-to-back; a later run after a pause was green,
so contention is a plausible confound and is recorded as one rather than as the cause.

This matters more than the two scenario-level cases below, because it is not scenario-level: any scenario that
promotes a slot and then reads or writes sits in the same window, which is the window
`family-chat-message-reply`'s learnings already record version four of its rollback-floor scenario losing to.
A slot that answers `/health/ready` is not yet a slot that can serve a write.

**The second scenario-level cause is open.** `A tab backgrounded with a dead connection reconnects once it becomes visible again`
fails roughly one run in eight — three of twenty-four across the three viewports — polling for ten seconds for a
fresh socket that never arrives. It predates the reply plan, which never touched
`family-chat-visibility-resume.steps.ts`; the last change to that file was
`fix(bnest-app): force a fresh family chat socket on every visibility resume`. Whether the harness backgrounds
the tab in a way Chromium throttles differently per viewport, or the application's resume path genuinely races,
is unknown and should be measured rather than guessed — guessing produced three wrong mechanisms for the first
one.

## Why Now

Not urgent: no production impact, and `test:quick` excludes E2E, so no CI check is red. Important because plan
records cite this gate as proof. The reply plan's delivery asserted `FE_E2E` green in five places while it was
not, and that went unnoticed for two rounds of corrections precisely because a suite that is usually green reads
as green.

## Prior Art / Precedents

- [End-to-end testing](../../../repo-governance/development/end-to-end-testing.md) already owns how these
  scenarios run; this is a reliability property of the existing guidance, not a new layer.
- The fixed case is written up in `family-chat-message-reply`'s `learnings.md`, including the trace that settled
  it, and is the worked example of measuring rather than reasoning about a timing failure.

## Proposed Direction (Sketch)

1. Find the second cause the same way the first was found — instrument, reproduce, read the trace — rather than
   raising the ten-second poll, which would hide it.
2. Decide whether the readiness signal a promotion waits on should mean "this slot can serve a write" rather than
   "this process is up". The drain-lock failure above, and the `waitForRoutedReads` helper the reply plan had to
   write to work around it, are the same gap observed twice.
3. Review the remaining browser scenarios for the same shape: a fixed wait chosen to be just longer than an
   application timeout, where the waiter's own completion cancels what it waits for.
4. Decide whether a known-flaky scenario should be quarantined so the gate's colour keeps meaning something,
   rather than left to fail one run in eight.

## Rough Scope & Non-Goals

In scope: the two scenarios named above, the slot-activation window they sit in, and a sweep for the
margin-too-thin pattern.

Out of scope: Playwright retries as a remedy — a retry turns a measurable defect into an invisible one; the
application's reconnect design, unless the second investigation implicates it; and any change to what the
scenarios assert.

## Risks & Open Questions

- The second failure may be an application defect rather than a harness one, in which case this brief is the
  wrong home and it becomes a bug with a user-visible consequence: a backgrounded tab that never reconnects.
- Quarantine is easy to reach for and easy to forget; if it is adopted it needs an expiry.
- The first fix couples a gesture helper to the menu it opens. That is honest for a scenario whose whole subject
  is "hold opens the menu", and it would be wrong for any future scenario asserting that a hold opens nothing —
  none exists at this layer today, because the sub-threshold decisions are proven at `FE_UNIT`.

## What Success Looks Like + Promotion Signal

Success: repeated full runs of `FE_E2E` on an unchanged tree return the same result every time.

Promotion signal: a third scenario found flaky for timing reasons, the open one traced to the application rather
than the harness, or a second observation of the drain-lock window outside a back-to-back run, promotes this brief
to a plan.
