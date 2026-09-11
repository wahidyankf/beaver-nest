# Lifecycle and Folders

Plans live under `plans/` in exactly four roots. The spelling is fixed, not stylistic: a validator matches these names
literally, and an agent locating work relies on them without searching.

| Root                 | Holds                                         | Slug form            |
| -------------------- | --------------------------------------------- | -------------------- |
| `plans/ideas/`       | two-page briefs that are not yet formal plans | `<slug>`             |
| `plans/backlog/`     | formal plans that are ready but not started   | `<slug>`             |
| `plans/in-progress/` | the formal plans currently being executed     | `<slug>`             |
| `plans/done/`        | completed plans, kept as history              | `YYYY-MM-DD__<slug>` |

`in-progress` is hyphenated. `done` is not `completed`, `archive`, `archived`, or `finished`. A repository that prefers
different words does not have this convention; it has a different one, and its plans will not validate.

## Slug Rules

A slug is lowercase, alphanumeric, and hyphen-separated. It names the outcome, not the ticket, the quarter, or the
person: `retire-the-legacy-importer`, not `q3-cleanup` or `alex-refactor`.

Slugs carry no date while a plan is live. A dated slug in `backlog/` or `in-progress/` is wrong, because the date it
would carry — creation, target, estimate — is either meaningless or a commitment the plan system does not make.

`done/` is the exception, and the date it carries is the **completion** date, joined to the slug by a double underscore:
`2026-01-15__retire-the-legacy-importer`. The double underscore is what lets the date be split off mechanically without
guessing where the slug begins.

## One Plan, One Root

A plan occupies exactly one root at a time. Moving it between stages is a move, not a copy: no stub, no forwarding
pointer, and no second folder left behind under the old stage. A slug appearing under two roots is a validation failure
rather than a merge to resolve, because the two copies will disagree and there is no rule for which one wins.

Movement runs forward — idea to backlog to in-progress to done — with one deliberate reverse edge: a plan that turns out
not to be ready may return from `in-progress/` to `backlog/`. Returning to `ideas/` is not a move; an idea brief and a
formal plan are different documents, and going back means writing the brief again.

## Ideas Are Not Formal Plans

An idea is a two-pager: what the problem is, why it might be worth solving, roughly what solving it would involve, and
what would make it not worth doing. It is deliberately cheap, and it is exempt from the document requirements in
[Required Documents](002-required-documents.md).

Promotion from idea to backlog is authorship, not renaming. The brief is the input to writing the plan; it is not the
plan with a folder moved.
