# Harness Quality Gate

This gate follows the [Quality Gate Contract](../../development/quality-gate-contract.md): a read-only checker, a frozen
ledger, one separate writer, at most three cycles, and an advisory verdict. It judges upstream drift only: whether the
committed bindings still match what each harness documents today. Whether the bindings agree with their own canonical
source is parity, which [Harness Parity Verification](harness-parity-verification.md) and the adapter validator own.

## Entry

The gate starts only on an explicit request that names it. No workflow calls it. The repository declares at least one
supported harness.

## Inputs

| Input        | Type    | Values                                   | Default  |
| ------------ | ------- | ---------------------------------------- | -------- |
| `subject`    | string  | `all` declared harnesses, or one by name | required |
| `mode`       | enum    | `lax`, `normal`, `strict`, `all`         | `normal` |
| `max-cycles` | integer | 1, 2, or 3                               | 3        |

The frozen subject records the revision and, per harness, the committed files that bind it: adapters, harness
configuration, and any reference record kept of that harness's conventions. Any other `max-cycles` value, or a missing
subject, refuses to start.

## Deterministic Boundary

The checker reports none of these properties. The entry and exit checks run their owners instead.

| Property                                   | Owned by                    | This repository runs              |
| ------------------------------------------ | --------------------------- | --------------------------------- |
| Adapters match their canonical definitions | the adapter validator       | `rhino harness adapters validate` |
| The harness declarations are well formed   | the configuration validator | `rhino repo-config validate`      |
| Markdown formatting                        | the formatter               | `prettier --check`                |

A red adapter validator is a red entry check, repaired at its cause before cycle 1, never a finding. No validator checks
canonical front matter here, so it is judgeable.

## Cycle

Each cycle is one full audit by `harness-checker`, loading the `checking-harness-compatibility` skill, and one repair by
[Harness Propagation](harness-propagation.md), run by `harness-fixer`, per
[Sequence and Termination](../../development/quality-gate-contract/002-sequence-and-termination.md).

The audit researches each harness in the subject, one task per harness, in parallel because none reads another's result,
handed over as Web Research Delegation requires. Each task returns file locations, metadata keys, model identifier
format, permission schema, and breaking changes, citing each fact's authoritative source and retrieval date. Disagreeing
sources come back as a conflict, not a choice.

The checker compares the research with the reference record and the committed bindings. Each difference is a finding
with its local path and upstream citation.

How the writer repairs drift in the canonical sources, regenerates the adapters, and leaves decisions to people is in
[Harness Propagation](harness-propagation.md).

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

No verdict stops the caller.

## Ledger

`local-tmp/quality/harness/<subject-slug>__<YYYYMMDDTHHMMZ>.md`, with the columns and closing verdict block in
[the contract](../../development/quality-gate-contract/003-verdicts-ledger-and-relations.md#ledger). Each row keeps its
upstream citation and retrieval date. It is never committed.

## Example Usage

```text
Run harness-quality-gate on subject all with mode strict.
```

## Related Workflows

- [Harness Parity Verification](harness-parity-verification.md) owns parity between bindings and their source.

## A Check Cannot See Upstream

A repository check compares files the repository holds, so it cannot notice that a harness changed its configuration
format last week. Research can, but it is slow and networked, so it runs on a cadence the adopter chooses: a schedule
catches unannounced changes and runs when nothing changed; running on announced releases costs nothing idle and misses
the rest. This workflow implements Evidence Over Assertion, because every upstream fact is cited and every repair
re-validated.
