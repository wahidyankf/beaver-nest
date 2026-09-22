# Plan and Checkpoint Contract Gaps

Three proposals the `family-chat-message-reply` execution raised: what a plan's File Impact table must cover when
it introduces a runtime flag, what a phase checkpoint's command set must name, and what a correction sweep must
cover once a claim is found to be wrong. Provenance: execution learnings captured 2026-09-22; the first two were
deferred by rules propagation and raised late, after an execution check found neither had reached a document. The
third was added 2026-09-22 after a third execution check.

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

**A correction sweep scoped to ticked items leaves the same false claim standing in a disposition.** Two rounds of
corrections unticked the two delivery items that rested on a duplicated 12-sample measurement. A third place
carried the same figures — the `Not triggered` disposition of a Recovery-and-Rollback item, which is unticked by
design and whose disposition _is_ its record. Both sweeps missed it, because each was scoped to "items claiming
this evidence" and read that as checkboxes. The proposal: when a correction retracts a measurement or a claim,
the sweep runs over every occurrence of the claim in the plan's six documents, not over the items that were ticked
on it. This is checkable mechanically — the retracted figures were byte-identical in all three places.

A later execution check found that neither of the first two proposals had been raised, because both were routed to
"at archival" and
archival is where the routing was supposed to happen. **Twenty-two** owner declarations in that plan's learnings
deferred their action the same way; this is the pair that had nowhere else to land. (This brief first said
twenty-three, written before any of them were counted.)

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

In scope: three documentation additions, and a check on whether the second is better enforced by the checkpoint
template than by prose.

Out of scope: the flag mechanism; the release tool's own structure; and any attempt to make File Impact tables
exhaustive in general, which would make them unreadable and is not what either failure showed.

## Risks & Open Questions

- The File Impact rule is easy to state for flags and tempting to generalise to "anything with a deployment
  consequence", which is where it stops being checkable.
- Naming typecheck in every checkpoint adds a line to every phase of every plan. Whether that is better than
  making the quick-suite target include typecheck is genuinely open, and the second option fixes it once.

## What Success Looks Like + Promotion Signal

Success: a plan that introduces a flag names the files that ship it, a red typecheck is caught by the phase that
broke it, and a retracted measurement disappears from every document that cited it in one pass.

Promotion signal: a second plan whose release path is missing from its File Impact, a second gate found red across
more than one phase, or a second correction sweep that leaves a retracted figure standing somewhere it was not
looking, promotes this brief to a plan.
