# Delivery Contract

`delivery.md` is the executable part of a plan. Everything else describes intent; this is the part someone works
through.

## One Checkbox, One Action

A checklist item represents exactly one independently verifiable action, and it names:

- the **paths** it touches;
- the **command** that performs or proves it, where one exists;
- its **executor** label;
- the **proof** that shows it is done; and
- the **acceptance criteria** it satisfies, by stable identifier.

"Independently verifiable" is the test. If finishing an item leaves no observable difference — no file, no output, no
passing check — it is not an item; it is a thought. If proving it requires first finishing the next item, the split is
in the wrong place.

Items are granular. An item that takes a long session is hiding several items, and hiding them means the first failure
inside it has no checkbox to fail against.

## Executor Labels and AI-First Ownership

Every item carries `[AI]` or `[HUMAN]`. The default is `[AI]`.

`[HUMAN]` is permitted for exactly four reasons:

1. a credential or access the executor does not have;
2. a physical action;
3. an external authority — someone else's approval, a third party's action; or
4. a decision that is genuinely unavailable, because the information needed to make it does not exist yet.

**Significance is never a reason.** An item being important, irreversible, expensive, or public-facing does not transfer
it to a human. Those properties call for care, evidence, and an explicit authorization recorded once — not for
reassigning the work. A plan that marks items `[HUMAN]` because they matter has stopped being executable and become a
request for supervision.

Where the outcome is genuinely uncertain, the item becomes a bounded checkpoint with a predeclared fallback: what is
tried, how many attempts, and what happens at the ceiling. The fallback is decided when the plan is written, not when
the ceiling is reached.

## Structure

`delivery.md` declares, before its phases:

- the **execution checkout** — which working copy the work happens in, and on which branch or worktree;
- the **delivery units** — the transaction boundaries, each with one owner, one testable outcome, and one rollback; and
- **pause safety** — what is recorded at a pause so work resumes without re-deriving it.

Phases follow in dependency order. Substantive completion and archival are separate: archival items live in their own
section, after every substantive phase, because a plan can be finished without being filed.

## Cold-Executor Resumability

The test for `delivery.md` is whether an executor with no memory of the plan can open it and know what to do next.

That means recording results, not only ticks. A ticked box says an action happened; it does not say what it produced,
what it changed, or what surprised the person doing it. Each completed item carries enough of that to be audited later
without re-running it.
