# UI Web Quality Gate

This gate follows the [Quality Gate Contract](../../development/quality-gate-contract.md): a read-only checker, a frozen
ledger, one separate writer, at most three cycles, and an advisory verdict. This file states only what is specific to a
running web user interface. An HTTP interface has its own gate, [API HTTP Quality Gate](api-http-quality-gate.md).

## Entry

The gate starts only on an explicit request that names it. No workflow calls it. The interface must be reachable, its
specification must resolve, and every interaction in scope must be safe to run against the target's data, per
[Test Data Isolation](../../development/test-identities.md).

## Inputs

| Input        | Type    | Values                                                       | Default  |
| ------------ | ------- | ------------------------------------------------------------ | -------- |
| `subject`    | string  | The running address or component set, with its specification | required |
| `mode`       | enum    | `lax`, `normal`, `strict`, `all`                             | `normal` |
| `max-cycles` | integer | 1, 2, or 3                                                   | 3        |

A subject whose specification does not resolve counts as missing. Any other `max-cycles` value, or a missing subject,
refuses to start.

## Deterministic Boundary

The checker reports none of these properties. The entry and exit checks run their owners instead.

| Property                                     | Owned by                        | This repository runs            |
| -------------------------------------------- | ------------------------------- | ------------------------------- |
| Component and LiveView behaviour tests pin   | the unit suites                 | `bnest-app` `test:unit`         |
| Scripted journeys pass in a browser          | the end-to-end browser suite    | `bnest-app-fe-e2e` `test:e2e`   |
| Every browser scenario is bound and covered  | the behaviour coverage check    | `test:coverage:behaviour`       |
| Types, lint, and formatting of the UI source | type checker, linter, formatter | `bnest-app` `typecheck`, `lint` |

No accessibility scanner runs here, so accessibility is judgeable. A property no tool of its own owns leaves the table
and becomes judgeable.

## Cycle

Each cycle is one full audit by `ui-web-checker` and one repair by [UI Web Propagation](ui-web-propagation.md), run by
`ui-web-fixer`, per [Sequence and Termination](../../development/quality-gate-contract/002-sequence-and-termination.md).
The checker may delegate reading to the repository's interface testers and judges, through the interface's components
and interactions:

- behaviour against the specification's scenarios, including empty, error, and loading states;
- fidelity to the adopted design rules and design system;
- accessibility that no scanner settles: focus order, keyboard paths, names that make sense, and meaning carried by more
  than colour; and
- usability: whether a first-time user can finish each specified task without guessing.

A tester rating on another severity scale maps severity, never priority, onto the criticality levels.

How the writer repairs and verifies each row, with a reproducing test and a redeploy, is in
[UI Web Propagation](ui-web-propagation.md).

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

No verdict stops the caller. Merge readiness stays with the repository's deterministic gates and
[Pull Request Merge](../../conventions/pull-request-merge.md).

## Ledger

`local-tmp/quality/ui-web/<subject-slug>__<YYYYMMDDTHHMMZ>.md`, with the columns and closing verdict block in
[the contract](../../development/quality-gate-contract/003-verdicts-ledger-and-relations.md#ledger). Each row keeps its
reproduction steps. It is never committed.

## Example Usage

```text
Run ui-web-quality-gate on the staging address and its checkout specification.
```

## Related Workflows

- [Exploratory and Usability Review](exploratory-usability-review.md) explores a running application for what no
  specification states.
- [API HTTP Quality Gate](api-http-quality-gate.md) judges the HTTP interface behind it.
