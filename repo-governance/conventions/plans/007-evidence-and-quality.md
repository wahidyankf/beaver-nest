# Evidence and Quality

## Terminal Verdicts

A quality gate returns exactly one of four results against a frozen snapshot of the plan:

| Verdict              | Means                                                            |
| -------------------- | ---------------------------------------------------------------- |
| `PASS`               | nothing outstanding                                              |
| `PASS_WITH_FINDINGS` | findings exist, are recorded, and none of them blocks proceeding |
| `FAIL`               | at least one blocking finding remains open                       |
| `BLOCKED`            | the gate could not judge: red tooling, changed input, no tool    |

All four are terminal, and all four are advisory: the caller records the verdict and continues. "Almost passing", "passing pending a fix", and "re-run it and see" are not verdicts — they are
the absence of one, and they let work proceed on an unresolved question while appearing to have cleared a gate.

The snapshot is frozen because a gate that re-reads a changing plan is measuring a moving target and cannot say what it
verified.

## Bounded Repair

A gate does not run until it goes green. It runs within the cycle ceiling the
[Quality Gate Contract](../../development/quality-gate-contract.md) sets, and at the ceiling the outcome is decided
rather than retried. Extending the budget because the next attempt feels close is how an unbounded loop starts.

## Evidence Records

Evidence is a file, not a claim in conversation. Each record carries:

- the exact command that was run;
- the commit it was run against;
- when it ran;
- the result; and
- the findings, sanitized.

Sanitized means the finding is described without reproducing what made it a finding. A record that quotes a discovered
credential has published it a second time; a record that names a private host has leaked the thing the scan existed to
protect. Raw scanner output never becomes evidence.

Evidence that cannot be recorded safely is summarized structurally — how many findings, of what class, in what surface —
and the unsafe detail stays out.

## Current Behaviour Over Past Proof

When a plan-execution check, quality gate, audit, or delivery checklist asks for past proof that can no longer be
produced, or that would only add complexity to rebuild, do not reconstruct it. Examples are a red run never captured, a
baseline from a removed worktree, a notice never recorded, a propagation step that should have run before the edits, and
a reviewed head never written down. Observe current behaviour directly instead: run the current suites on the current
head, read the live state, or read the current files. Record that observation as an ordinary evidence record, plus one
line naming the past proof it replaces and why that proof is unavailable.

A rebuilt record documents the rebuilding, not the event, and costs effort without adding certainty. The criterion is
about how the work behaves now, and that can be observed.

- This substitutes evidence and never waives it: the current observation must establish the criterion on its own.
- A check that can still run today runs today. Only proof tied to a past moment is substituted.
- A check whose purpose is a current property still runs, even when it repeats a past step: a test or gate still shows
  it can fail, per [Test-Driven Development](../../development/test-driven-development.md).
- Never re-stage a past state, back-date a record, or present a new run as an old one.
- When the behaviour itself can no longer be observed, this does not apply; use
  [Accepting a Permanently Unmet Item](008-knowledge-capture-and-archival.md#accepting-a-permanently-unmet-item).

Followed: the record holds a current command, commit, time, and result that establish the criterion, plus the
substitution line. Violated: a past artefact is rebuilt or back-dated; a verdict blocks only on unrecoverable history
while current behaviour establishes the criterion; or a check that can still run is skipped under this rule.

**Enforcement: unenforced by decision.** Whether past proof is unrecoverable and whether a current observation
establishes the criterion are judgements no mechanical check settles; the execution check makes them from the record.

## Manual Verification

Some claims cannot be established by automation, and a green pipeline does not become sufficient because it is
convenient.

A plan whose result has a user-facing surface routes evidence through distinct layers, records each one separately, and
remains incomplete while any applicable layer is unresolved.

This repository serves a user-facing application, and the two layers it routes through are owned by the
[exploratory and usability review](../../workflows/quality/exploratory-usability-review.md) workflow rather than restated
here: a spec-aware pass and a structurally spec-blind one, recorded in separately labelled sections so a reader always
knows which lens produced a finding. A plan whose result has no such surface records both layers as not applicable with
that reason, which is a disposition rather than an omission.
