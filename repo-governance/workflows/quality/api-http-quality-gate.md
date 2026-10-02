# API HTTP Quality Gate

This gate follows the [Quality Gate Contract](../../development/quality-gate-contract.md): a read-only checker, a frozen
ledger, one separate writer, at most three cycles, and an advisory verdict. This file states only what is specific to a
running HTTP interface. A web user interface has its own gate, [UI Web Quality Gate](ui-web-quality-gate.md).

## Entry

The gate starts only on an explicit request that names it. No workflow calls it. The interface must be reachable, its
contract must resolve, and every operation in scope must be safe to run against the target's data, per
[Test Data Isolation](../../development/test-identities.md).

## Inputs

| Input        | Type    | Values                                                    | Default  |
| ------------ | ------- | --------------------------------------------------------- | -------- |
| `subject`    | string  | The running address, with the contract and specifications | required |
| `mode`       | enum    | `lax`, `normal`, `strict`, `all`                          | `normal` |
| `max-cycles` | integer | 1, 2, or 3                                                | 3        |

A subject whose contract does not resolve counts as missing. Any other `max-cycles` value, or a missing subject, refuses
to start.

## Deterministic Boundary

The checker reports none of these properties. The entry and exit checks run their owners instead.

| Property                                       | Owned by                        | This repository runs            |
| ---------------------------------------------- | ------------------------------- | ------------------------------- |
| Behaviour the unit and integration tests pin   | the unit and integration suites | `bnest-app` `test:unit`         |
| Scripted API operations pass end to end        | the API end-to-end suite        | `bnest-app-be-e2e` `test:e2e`   |
| Every API scenario is bound and covered        | the behaviour coverage check    | `test:coverage:behaviour`       |
| Types, lint, and formatting of the server code | type checker, linter, formatter | `bnest-app` `typecheck`, `lint` |

No contract linter or schema test runs here, so the REST and GraphQL contracts are judgeable. A property no tool of its
own owns leaves the table and becomes judgeable.

## Cycle

Each cycle is one full audit by `api-http-checker` and one repair by [API HTTP Propagation](api-http-propagation.md),
run by `api-http-fixer`, per
[Sequence and Termination](../../development/quality-gate-contract/002-sequence-and-termination.md). The checker may
delegate the requests to the repository's interface tester. It sends real requests against the contract and behaviour
specifications, and judges:

- status codes, and response and error shapes, where no schema test already pins them;
- authorization boundaries: what each role can and cannot reach;
- pagination, filtering, and ordering at their edges;
- idempotency of operations that claim it, and the effect of a retried request; and
- boundary and malformed payloads, and whether each error tells a caller what to change.

A tester rating on another severity scale maps severity, never priority, onto the criticality levels.

How the writer repairs and verifies each row, with a reproducing test and a redeploy, is in
[API HTTP Propagation](api-http-propagation.md).

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

`local-tmp/quality/api-http/<subject-slug>__<YYYYMMDDTHHMMZ>.md`, with the columns and closing verdict block in
[the contract](../../development/quality-gate-contract/003-verdicts-ledger-and-relations.md#ledger). Each row keeps its
request and response, with secrets and personal data removed. It is never committed.

## Example Usage

```text
Run api-http-quality-gate on the staging address against its published contract.
```

## Related Workflows

- [UI Web Quality Gate](ui-web-quality-gate.md) judges a web interface that consumes this one.
- [PR Review Quality Gate](pr-review-quality-gate.md) judges the change itself; this gate judges what it does.
