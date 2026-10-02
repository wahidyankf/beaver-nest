# Harness Propagation

## Contract

This is the `harness` family's sole writer, under
[Sole-Writer Propagation](../../development/sole-writer-propagation.md).

## Scope

The canonical agent and skill artifacts, the adapter generator's mapping, the reference record kept of each harness's
conventions, and the adapters the generator regenerates from them. A generated adapter is never edited by hand, per
[Harness Adapters](../../conventions/coding-harness-contract.md).

## Executor

`harness-fixer`, loading the `checking-harness-compatibility` skill.

## Row Verification

A row closes when the committed binding now agrees with the row's cited upstream fact, the adapters were regenerated
with the repository's generator, and the repository's parity check and Markdown gates exit 0. Each ledger row ends
`resolved`, `not-resolved`, `not-applicable`, or `needs-decision`, with evidence.

## Family Rules

### Entry

The [Harness Quality Gate](harness-quality-gate.md) hands over a frozen ledger, or an explicit request names its rows.

- `findings` (`file`, required): the frozen ledger, each row with its upstream citation and retrieval date.

### Sequence

1. **Re-read each named file against its citation.** A file that already agrees with the cited fact is `not-applicable`,
   since the drift is gone; a file that holds neither the quoted value nor the cited one is `needs-decision`, because
   the ground moved under the row.
2. **Repair the source, never the output.** Drift the evidence settles unambiguously, such as a renamed metadata key or
   a moved file location, is repaired in the canonical artifact, the generator mapping, or the reference record.
3. **Leave decisions to people.** A source conflict, a change to what a permission means, adding or removing a harness,
   a change to the generator's logic, and a retired model identifier without a named successor are `needs-decision`,
   with the citation and the options.
4. **Regenerate the adapters,** then verify each row.

The writer does not research. A row its citation and the repository cannot confirm stays `needs-decision`, and new
research returns to the checking side, per Web Research Delegation. It never weakens the parity check, drops a
restriction, or excludes a path to reach a clean result.

### Canonical Changes

This writer keeps the trigger it already had here: adding, changing, renaming, or removing a canonical rule, skill,
agent, required capability, or adapter enters it automatically, with no ledger, and follows
[Canonical Change](harness-propagation/001-canonical-change.md).

### Exit

Outputs: `status` (`enum`: `no-change`, `landed`, `partial`, `input-changed`) and the ledger, each row with its status
and evidence. The caller commits the repairs with the regenerated adapters. A rerun on unchanged inputs changes nothing.

## Example Usage

```text
Run harness-propagation with the ledger the harness quality gate froze for subject all.
```

## Related Workflows

- [Harness Quality Gate](harness-quality-gate.md) researches upstream drift and hands its blocking rows here.
- [Harness Parity Verification](harness-parity-verification.md) owns parity between bindings and their source.

## Modules

1. [Canonical Change](harness-propagation/001-canonical-change.md)
