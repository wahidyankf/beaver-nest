# Docs Quality Gate

Audit human-facing documents and return a verdict with a finite ledger of stale, obsolete, misplaced, and unreadable documents, handing every finding to [docs propagation](docs-propagation.md) instead of editing.

## Entry

Run only when the user explicitly names this gate or directs its audit. A change or a propagation run never authorizes it alone.

- `scope` (`change` or `all`; required): the documents one change affects, or the whole document set [docs propagation](docs-propagation.md) defines.
- `change` (required when `scope` is `change`): the revision range or working-tree change.

## Sequence

1. **Freeze the snapshot:** scope, Git revision, and uncommitted paths. A material external change ends the run as `input-changed`, never restarting it.
2. **Bound the audit.** Under `change`, the documents the change touches and every document citing what it changed; under `all`, the whole document set.
3. **Audit without editing.** Decide for each document whether:
   1. every claim is true to the implementation, checked against the code or an authoritative source, and every command shown was run or is marked not exercised;
   2. it still describes something the repository has; if not, it is obsolete and its resolution is removal;
   3. each fact has one home, a summary sits above its detail per [progressive disclosure](../principles/progressive-disclosure.md), and a `docs/` page serves one mode per [documentation architecture](../conventions/documentation-architecture.md);
   4. a newcomer learns from the opening what it is and why it matters, and finds the next step, judged by reading, never by a score;
   5. under `all`, or when setup changed, a reader with no prior context can follow the setup exactly as written from a clean checkout, each step marked smooth, frustrating, or blocking; and
   6. it agrees with its specification, which is canonical.
4. **Record a finite ledger.** Each row names the document, the gap, the required resolution — update, move, or remove — the evidence, and a status: `open`, `resolved`, `not-applicable` with evidence, or `blocked`. Admit only a document that is wrong, obsolete, unreachable, or unusable by a newcomer; wording preference is not a finding, per [minimal sufficiency](../principles/minimal-sufficiency.md).
5. **Leave machine checks to their tools.** Formatting, links, directory maps, and budgets belong to deterministic checks under the [software-quality map](../development/software-quality-enforcement.md); consume their result instead of repeating them.
6. **Return the verdict.** It passes when the ledger is clear and this command passes:

   ```sh
   ./hippo run --class ephemeral --resource-tier standard --disk-path . -- npm exec -- nx run -p rhino-consumer -t test:repo
   ```

   Otherwise hand the ledger to [docs propagation](docs-propagation.md). Ask the owner through [grill-me](../../.agents/skills/grill-me/SKILL.md) about a finding only they can decide, such as a specification that disagrees with the implementation.

## Exit

Outputs: `verdict` (`pass`, `needs-propagation`, or `input-changed`) and the ledger, written under ignored `local-tmp/`.

`needs-propagation` is a handoff, not a blocked result: the caller runs propagation with the ledger without another request. An input change ends the audit with its ledger kept. A verdict authorizes no commit or push.

## After a Finding

Choose and record one option per request:

| Option                  | What happens                                                                                              | Trade-off                                                    |
| ----------------------- | --------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------ |
| verdict only            | the caller reports propagation's result, and the gate does not run again                                  | one audit per request; a second audit needs a second request |
| repair to zero findings | propagation repairs, then the gate audits the effective state again while open findings strictly decrease | ends on a clean audit; costs repeated audits and a ceiling   |

Under repair to zero findings, declare the ceiling on audit rounds before the first repair, and stop when open findings fail to decrease or the ceiling is reached. Either way the gate never edits a document.

## Why It Runs on Request

Judging whether a document is still true, still needed, and still readable is a reading task. Wired into every change, it produces noise nobody reads or a pass nobody earned; propagation already refreshes each change.
