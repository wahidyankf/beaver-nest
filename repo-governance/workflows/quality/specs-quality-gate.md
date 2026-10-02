# Specs Quality Gate

This gate follows the [Quality Gate Contract](../../development/quality-gate-contract.md): a read-only checker, a frozen
ledger, one separate writer, at most three cycles, and an advisory verdict. This file states only what is specific to
specifications.

## Entry

The gate starts only on an explicit request that names it. No workflow calls it.

## Inputs

| Input        | Type    | Values                                             | Default  |
| ------------ | ------- | -------------------------------------------------- | -------- |
| `subject`    | string  | The specification folders to judge, listed by name | required |
| `mode`       | enum    | `lax`, `normal`, `strict`, `all`                   | `normal` |
| `max-cycles` | integer | 1, 2, or 3                                         | 3        |

Each listed folder is judged with its subfolders, and nothing else; the gate never discovers or scans a whole
specification tree. Any other `max-cycles` value, or a missing subject, refuses to start.

## Deterministic Boundary

The checker reports none of these properties. The entry and exit checks run their owners instead.

| Property                                  | Owned by                       | This repository runs                      |
| ----------------------------------------- | ------------------------------ | ----------------------------------------- |
| Every scenario is bound and covered       | the behaviour coverage checks  | each project's `test:coverage:behaviour`  |
| Scenarios pass against the implementation | the unit and end-to-end suites | `test:unit`, `test:e2e` of each project   |
| Markdown formatting                       | the formatter                  | `prettier --check`                        |
| Internal links and directory maps resolve | the link and map validators    | `rhino md internal-link validate` and map |

No Gherkin linter or specification-index validator runs here, so scenario wording and index content are judgeable. A
property no tool of its own owns leaves the table and becomes judgeable.

## Cycle

Each cycle is one full audit by `specs-checker` and one repair by [Specs Propagation](specs-propagation.md), run by
`specs-fixer`, per [Sequence and Termination](../../development/quality-gate-contract/002-sequence-and-termination.md).
The writer edits only within the listed folders. The audit reads every listed folder for:

- **structure**: indexes that describe their folder, and a tree shaped per
  [Specification Tree](../../development/specification-maintenance.md);
- **scenario quality**: feature headers, user stories, shared setup, and naming per
  [Behaviour-Driven Development](../../development/behaviour-driven-development.md);
- **consistency**: shared domains, terms, and diagrams agreeing across the listed folders, judged only when two or more
  are listed;
- **references**: each link pointing at what its text claims it points at; and
- **implementation alignment**: every implementation a specification names exists.

A repair that would change what a specification requires is a judgement the ledger does not settle, so its row is
`needs-decision`.

## Termination

The contract's [termination table](../../development/quality-gate-contract/002-sequence-and-termination.md#termination)
applies unchanged. This gate adds no row.

## Verdict

| Verdict              | The caller                                                                          |
| -------------------- | ----------------------------------------------------------------------------------- |
| `PASS`               | records the verdict and continues                                                   |
| `PASS_WITH_FINDINGS` | records the verdict and the open non-blocking rows, and continues                   |
| `FAIL`               | gives each open blocking row an owner (idea brief, plan item, or issue), continues  |
| `BLOCKED`            | records the cause (tooling, input-changed, or unavailable), then acts as for `FAIL` |

No verdict stops the caller, and none authorizes a commit or a push.

## Ledger

`local-tmp/quality/specs/<subject-slug>__<YYYYMMDDTHHMMZ>.md`, with the columns and closing verdict block in
[the contract](../../development/quality-gate-contract/003-verdicts-ledger-and-relations.md#ledger). It is never
committed.

## Example Usage

```text
Run specs-quality-gate on the folders billing/api and billing/web with mode strict.
```

## Related Workflows

- [Gherkin Implementation Review](gherkin-implementation-review.md) checks that the code honours these scenarios.
- [Docs Propagation](docs-propagation.md) keeps the documents that cite these specifications true to them.

## Why Listed Folders Only

A gate that discovers its own scope reports a different count each time the tree grows, so its progress measure resets
and its result cannot be compared with the last run. Naming the folders freezes the subject and makes cross-folder
consistency a deliberate choice. This workflow implements Explicit Over Implicit.
