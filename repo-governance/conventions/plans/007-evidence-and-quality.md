# Evidence and Quality

## Terminal Verdicts

A quality gate returns exactly one of three results against a frozen snapshot of the plan:

| Verdict              | Means                                                            |
| -------------------- | ---------------------------------------------------------------- |
| `PASS`               | nothing outstanding                                              |
| `PASS_WITH_FINDINGS` | findings exist, are recorded, and none of them blocks proceeding |
| `FAIL`               | at least one finding blocks proceeding                           |

All three are terminal. "Almost passing", "passing pending a fix", and "re-run it and see" are not verdicts — they are
the absence of one, and they let work proceed on an unresolved question while appearing to have cleared a gate.

The snapshot is frozen because a gate that re-reads a changing plan is measuring a moving target and cannot say what it
verified.

## Bounded Repair

A gate does not run until it goes green. It runs once, and findings may then be repaired for at most two cycles.

At the ceiling the outcome is decided rather than retried: either the repaired plan is accepted on its merits or the
last known-good state is kept, whichever is better against the criteria that were declared before the first cycle. That
decision is recorded with its reasoning. Extending the budget because the next attempt feels close is how an unbounded
loop starts.

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

## Manual Verification

Some claims cannot be established by automation, and a green pipeline does not become sufficient because it is
convenient.

A plan whose result has a user-facing surface routes evidence through distinct layers, records each one separately, and
remains incomplete while any applicable layer is unresolved.

This repository serves a user-facing application, and the two layers it routes through are owned by the
[exploratory and usability testing](../../workflows/exploratory-and-usability-testing.md) workflow rather than restated
here: a spec-aware pass and a structurally spec-blind one, recorded in separately labelled sections so a reader always
knows which lens produced a finding. A plan whose result has no such surface records both layers as not applicable with
that reason, which is a disposition rather than an omission.
