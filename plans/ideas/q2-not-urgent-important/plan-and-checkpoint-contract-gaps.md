# Plan and Checkpoint Contract Gaps

Two proposals the `family-chat-message-reply` execution raised and rules propagation deliberately deferred: what a
plan's File Impact table must cover when it introduces a runtime flag, and what a phase checkpoint's command set
must name. Provenance: execution learnings captured 2026-09-22; raised late, after an execution check found neither
had reached a document.

## Problem / Context

**A File Impact table that stops at the application misses the release path.** The plan introduced
`BNEST_FAMILY_CHAT_REPLY_ENABLED` and listed every application file that reads it. It did not list
`apps/bnest-app/tools/deployment.mjs`, `tools/release.mjs`, or `tools/release.test.mjs` — the files that pass the
flag to a slot. Without those changes the experience release would have promoted a revision that never receives
the flag, and the promotion would have looked successful. The work was done and recorded as drift; nothing in the
plan's own contract required it to be foreseen.

**A checkpoint that names its suites but not its typecheck lets a gate stay red.** The frontend typecheck gate was
red for three phases before anyone noticed, because each phase checkpoint listed the test targets it ran and
typecheck was not among them. The suites were green the whole time, so nothing contradicted the record. That is
the single most useful thing this execution learned about its own checkpoints, and it came from a gate failure
rather than from the checkpoint contract.

A later execution check found that neither proposal had been raised, because both were routed to "at archival" and
archival is where the routing was supposed to happen. Twenty-three entries in that plan's learnings used the same
phrase; this is the pair that had nowhere else to land.

## Why Now

Neither is urgent — the specific failures were caught, one by a gate and one by the release working correctly. They
belong here because both are one-sentence additions to documents that already exist, and both describe a way for a
plan to look complete while missing something a later phase depends on.

## Prior Art / Precedents

- The repository's [software quality map](../../../repo-governance/development/software-quality-enforcement.md)
  already owns what a checkpoint must prove; the typecheck proposal is a missing line in it rather than a new
  document.
- The [plans convention](../../../repo-governance/conventions/plans.md) already fixes the six documents a plan
  carries; the File Impact proposal narrows what one of them must contain in one specific case.

## Proposed Direction (Sketch)

1. When a plan introduces or removes a runtime flag, its File Impact table covers the release path that carries
   that flag to a slot, not only the application code that reads it.
2. A phase checkpoint's command set names the typecheck target alongside its suites, so a red typecheck cannot sit
   behind green tests across several phases.

## Rough Scope & Non-Goals

In scope: two documentation additions, and a check on whether the second is better enforced by the checkpoint
template than by prose.

Out of scope: the flag mechanism; the release tool's own structure; and any attempt to make File Impact tables
exhaustive in general, which would make them unreadable and is not what either failure showed.

## Risks & Open Questions

- The File Impact rule is easy to state for flags and tempting to generalise to "anything with a deployment
  consequence", which is where it stops being checkable.
- Naming typecheck in every checkpoint adds a line to every phase of every plan. Whether that is better than
  making the quick-suite target include typecheck is genuinely open, and the second option fixes it once.

## What Success Looks Like + Promotion Signal

Success: a plan that introduces a flag names the files that ship it, and a red typecheck is caught by the phase
that broke it.

Promotion signal: a second plan whose release path is missing from its File Impact, or a second gate found red
across more than one phase, promotes this brief to a plan.
