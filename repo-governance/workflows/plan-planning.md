# Planning

## Entry

Someone has asked for a formal plan, or a brief has been promoted by [Ideas Grooming](plan-ideas-grooming.md).

## Sequence

1. **Inspect before asking.** Read the repository — its instructions, its current state, the surfaces the work touches —
   so the first gate presents real choices rather than questions the repository already answers.
2. **Run the pre-write gate.** Every material branch is resolved here, and **no plan document is authored until it
   completes**. A plan written first and questioned afterwards has already committed to the answers.
3. **Author all six documents.** `README.md`, `brd.md`, `prd.md`, one technical shape, `delivery.md`, `learnings.md`.
   The document set and its rules are the [Plans Convention](../conventions/plans.md)'s; this workflow does
   not restate them.
4. **Write `delivery.md` last.** It depends on every other document, and writing it first produces a checklist for a
   plan that does not exist yet.
5. **Run the post-write gate.** A separate gate, on the complete draft, resolving what only became visible once the plan
   existed. It does not merge into the first gate — see
   [Decision Gates](../development/planning-capabilities/003-decision-gates.md).
6. **Run the [Quality Gate](plan-quality-gate.md)** and repair within its bounded budget.

## Exit

Six documents exist, both gates have completed and left decision records, and the quality gate has returned a terminal
verdict.

## Gate Ordering Is Not Negotiable

The two gates ask different questions at different times. Before authoring, the open questions are about approach,
scope, and constraint. After a draft, they are about what the draft revealed — a dependency nobody expected, a seam that
turned out to be in the wrong place.

Running one gate instead of two means asking the second set of questions before the information needed to answer them
exists.
