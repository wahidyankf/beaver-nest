# Required Documents

Every formal plan — one in `plans/backlog/` or `plans/in-progress/` — contains six documents. Not five, and not five
plus an optional sixth.

| Document            | Answers                                                                                      |
| ------------------- | -------------------------------------------------------------------------------------------- |
| `README.md`         | status, context, scope, approach, dependencies, and how to navigate the plan                 |
| `brd.md`            | the business goal, the roles it serves, the outcomes, the non-goals, the business risks      |
| `prd.md`            | personas, user stories, testable acceptance criteria, product scope, product risks           |
| one technical shape | how it will actually be built — see [Technical Shape](003-technical-shape-and-companions.md) |
| `delivery.md`       | the ordered, granular, execution-grade checklist and its proof                               |
| `learnings.md`      | what was discovered while executing, held until it is routed somewhere durable               |

The technical shape is one of the six, not an addition to them. A plan root therefore holds six documents when the
technical shape is a single file, and five files plus one directory when it is a directory.

## Why Six

The first three separate concerns that are genuinely different and are routinely conflated: why the work is worth doing,
what the result must do, and how it will be built. Collapsing them produces a document that argues for itself, which is
exactly the document nobody can review.

`delivery.md` exists because a plan that cannot be executed step by step has not finished being a plan.

`learnings.md` is the sixth and the one most often dropped. Execution always discovers things — a wrong assumption, a
tool that does not behave as documented, a rule that turned out to be load-bearing. Without a place to put them, those
discoveries are lost at exactly the moment they are most valuable, and the next plan rediscovers them. It is transient
by design: see [Knowledge Capture and Archival](008-knowledge-capture-and-archival.md).

## No Five-Document Rule

`learnings.md` is not optional, and no artifact in a repository may say otherwise. This applies to every place a plan's
contents can be described: governance prose, skills, agent definitions, workflows, templates, validators, and repository
instructions.

A repository adopting this convention must search its live corpus for descriptions of plan contents and correct every
one that enumerates five documents. Leaving one behind is not a cosmetic inconsistency — it is a live rule contradicting
another live rule, and an executor following it will produce a plan that fails validation for a reason the text told it
was correct.

Any five-document description that remains is a defect regardless of where it lives or how old it is.
