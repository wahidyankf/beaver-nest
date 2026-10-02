# Plan Quality Gate

This gate follows the [Quality Gate Contract](../../development/quality-gate-contract.md): a read-only checker, a frozen
ledger, one separate writer, at most three cycles, and an advisory verdict. This file states only what is specific to
plans.

## Entry

The gate starts only on an explicit request that names it, or from [Planning](../plan/plan-planning.md), after the
post-write gate.

Creating, editing, or executing a plan never starts it alone. Each run serves one named checkpoint: before execution, or
after a material change.

## Inputs

| Input        | Type    | Values                                    | Default  |
| ------------ | ------- | ----------------------------------------- | -------- |
| `subject`    | string  | One plan folder, with both decision gates | required |
| `mode`       | enum    | `lax`, `normal`, `strict`, `all`          | `normal` |
| `max-cycles` | integer | 1, 2, or 3                                | 3        |

Any other `max-cycles` value, or a missing subject, refuses to start.

## Deterministic Boundary

The checker reports none of these properties. The entry and exit checks run their owners instead.

| Property                   | Owned by                  | This repository runs                      |
| -------------------------- | ------------------------- | ----------------------------------------- |
| Markdown formatting        | the formatter             | `prettier --check`                        |
| Internal links and anchors | the link validator        | `rhino md internal-link validate`         |
| Word budgets               | the word-budget validator | `rhino governance word-budget validate`   |
| Directory maps             | the map validator         | `rhino governance directory-map validate` |
| Mermaid diagrams           | the diagram validator     | `rhino md mermaid validate`               |

The plan structural validator that [Structural Validation](../../conventions/plans/006-structural-validation.md)
describes is not built here, so plan layout, documents, and labels are judgeable. A property no tool of its own owns
leaves the table and becomes judgeable.

## Cycle

Each cycle is one full audit by `plan-checker`, loading the `plan-validating-quality` skill, and one repair by
[Plan Propagation](plan-propagation.md), run by `plan-fixer`, per
[Sequence and Termination](../../development/quality-gate-contract/002-sequence-and-termination.md). The audit reads the
frozen plan and asks whether:

1. the acceptance criteria are testable, and are the right ones for the stated outcome;
2. `delivery.md` is executable by someone who was not present, in dependency order, per
   [Plans](../../conventions/plans.md);
3. the technical shape matches the work, and each of the six documents answers its own question;
4. for a bug-fix plan, the root cause carries checkable evidence and the solution cites references; and
5. every decision the plan relies on is recorded, so an executor invents no policy.

Wording preference and speculative cases are not findings, per
[Minimal Sufficiency](../../principles/minimal-sufficiency.md). `plan-maker` authors plans; `plan-fixer` only repairs
ledger rows.

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

No verdict stops the caller, and none authorizes execution, a commit, or a push. The plan records one line in its
`delivery.md`, for example `plan-quality-gate: PASS_WITH_FINDINGS (2 cycles, 3 LOW open)`.

## Ledger

`local-tmp/quality/plan/<plan-slug>__<YYYYMMDDTHHMMZ>.md`, with the columns and closing verdict block in
[the contract](../../development/quality-gate-contract/003-verdicts-ledger-and-relations.md#ledger). It is never
committed.

## Example Usage

```text
Run plan-quality-gate on plans/in-progress/billing-retry with mode normal.
```

## Related Workflows

- [Planning](../plan/plan-planning.md) authors the draft this gate judges.
- [Execution Check](../plan/plan-execution-check.md) judges finished execution, not a draft.
