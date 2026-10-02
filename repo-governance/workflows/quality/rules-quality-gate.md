# Rules Quality Gate

This gate follows the [Quality Gate Contract](../../development/quality-gate-contract.md): a read-only checker, a frozen
ledger, one separate writer, at most three cycles, and an advisory verdict. This file states only what is specific to
rules.

## Entry

The gate starts only on an explicit request that names it. No workflow calls it;
[Rules Grooming](../maintenance/rules-grooming.md) never invokes it. A rule change, review request, or propagation run
never starts it alone.

## Inputs

| Input        | Type    | Values                                                 | Default  |
| ------------ | ------- | ------------------------------------------------------ | -------- |
| `subject`    | string  | A rule outcome with its reason, `proposal`/`effective` | required |
| `mode`       | enum    | `lax`, `normal`, `strict`, `all`                       | `normal` |
| `max-cycles` | integer | 1, 2, or 3                                             | 3        |

A `proposal` subject compares a requested outcome with the current rules before any edit; an `effective` subject judges
the repository after propagation wrote. Any other `max-cycles` value, or a missing subject, refuses to start.

## Deterministic Boundary

The checker reports none of these properties. The entry and exit checks run their owners instead.

| Property                            | Owned by                  | This repository runs                      |
| ----------------------------------- | ------------------------- | ----------------------------------------- |
| Markdown formatting                 | the formatter             | `prettier --check`                        |
| Internal links                      | the link validator        | `rhino md internal-link validate`         |
| Word budgets                        | the word-budget validator | `rhino governance word-budget validate`   |
| Directory maps                      | the map validator         | `rhino governance directory-map validate` |
| Harness adapters match their source | the adapter validator     | `rhino harness adapters validate`         |

No validator checks front matter here, so it is judgeable. A property no tool of its own owns leaves the table and
becomes judgeable.

## Cycle

Each cycle is one full audit by `rules-checker` and one repair by [Rules Propagation](rules-propagation.md), run by
`rules-fixer`, per [Sequence and Termination](../../development/quality-gate-contract/002-sequence-and-termination.md).
The frozen subject records intended strength, scope, consumers, any move or deletion, canonical sources, and the
enforcement route. The audit covers the affected rule, its uses, the authority above it, and overlapping guidance; for
grooming, that run's manifest. It asks whether:

1. the need, outcome, and reason are concrete enough to judge;
2. the wording's strength matches the intended strength, per [Rule Definition](../../conventions/rules.md);
3. scope, trigger, action, boundaries, and necessary exceptions are explicit;
4. the rule sits at the right level, and nothing lower contradicts a higher rule;
5. one canonical source owns the meaning, and links keep it findable without copies;
6. every enforcement claim names a truthful route, with evidence where automation cannot decide;
7. the rule survives compaction and handover at every entry point;
8. a reasonable reader can act without inventing policy; and
9. a move or deletion keeps unique intent and updates its consumers.

Only a rule violation, or a gap leaving the outcome unsafe, contradictory, undiscoverable, or materially ambiguous, is a
finding. Wording preference, speculative cases, and unneeded automation are not, per
[Minimal Sufficiency](../../principles/minimal-sufficiency.md). After the first repair, a `proposal` subject is audited
as written.

## Termination

The contract's [termination table](../../development/quality-gate-contract/002-sequence-and-termination.md#termination)
applies unchanged. This gate adds no row.

## Verdict

| Verdict              | The caller                                                                          |
| -------------------- | ----------------------------------------------------------------------------------- |
| `PASS`               | records the verdict and continues; for a proposal, current rules already suffice    |
| `PASS_WITH_FINDINGS` | records the verdict and the open non-blocking rows, and continues                   |
| `FAIL`               | gives each open blocking row an owner (idea brief, plan item, or issue), continues  |
| `BLOCKED`            | records the cause (tooling, input-changed, or unavailable), then acts as for `FAIL` |

No verdict stops the caller, and none authorizes a commit or a push.

## Ledger

`local-tmp/quality/rules/<outcome-slug>__<YYYYMMDDTHHMMZ>.md`, with the columns and closing verdict block in
[the contract](../../development/quality-gate-contract/003-verdicts-ledger-and-relations.md#ledger). It is never
committed.

## Example Usage

```text
Run rules-quality-gate on proposal "Require a dry run for every script that deletes files."
```

## Related Workflows

- [Rules Propagation](rules-propagation.md) repairs every blocking row.
- [Rules Grooming](../maintenance/rules-grooming.md) hands its approved reductions to propagation and never runs this
  gate.
