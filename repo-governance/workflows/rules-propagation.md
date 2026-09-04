# Rules Propagation

Apply this workflow automatically whenever a repository [rule](../conventions/rules.md) is created, changed, moved, or deleted, even without an explicit request. It is the sole writer for rule propagation and composes the read-only [rules quality gate](rules-quality-gate.md). Neither workflow invokes itself; edits inside one propagation transaction do not start another transaction.

## Inputs and Transaction

- the proposed rule and rationale;
- its intended mandatory, expected, or permitted strength;
- the people, agents, files, or tasks in scope; and
- known enforcement and evidence routes.

Freeze those inputs, the Git revision and dirty paths, affected entry points, relevant canonical sources, and cycle `1`. Preserve the snapshot, gate ledgers, cycle, pending verification, and authorization through compaction or handoff. Material external input change ends the transaction as `BLOCKED_INPUT_CHANGED`; it never causes an automatic restart.

## Bounded Procedure

1. Run the [rules quality gate](rules-quality-gate.md) in `PROPOSAL` mode with the frozen inputs.
   - On `PASS_NO_CHANGE`, make no edits and return `PASS_NO_CHANGE`.
   - On `PASS_READY`, continue with its finite ledger.
   - On any `BLOCKED_*`, preserve the evidence and stop.
2. Apply one propagation cycle, changing only what the accepted outcome and ledger require:
   - put the shortest actionable form at each applicable `AGENTS.md` or equivalent point of use, keeping non-negotiable constraints visible;
   - keep self-contained canonical detail there only when it remains concise; otherwise link to the correct governance level;
   - place outcomes and boundaries in vision, durable constraints in principles, repository choices in conventions, engineering standards in development, and procedures in workflows;
   - compare authority in order: `vision > principles > conventions > development > workflows`, resolving lower-level conflicts;
   - keep one canonical statement, merge unique meaning, replace copies with concise links, and apply [progressive disclosure](../principles/progressive-disclosure.md);
   - inspect affected guidance top to bottom and change only stale, misplaced, overlapping, or repeated content implicated by the ledger; and
   - name truthful enforcement under the [software-quality map](../development/software-quality-enforcement.md), adding machinery only for an explicit need or demonstrated risk.
3. Run the rules quality gate in `EFFECTIVE` mode.
   - On `PASS_EFFECTIVE`, return `PASS_CHANGED`.
   - On `BLOCKED_TOOLING` or `BLOCKED_INPUT_CHANGED`, stop with its evidence.
   - On `BLOCKED_SEMANTIC`, allow exactly one stabilization cycle only when every remaining finding is within the accepted outcome or was caused by the first-cycle edits.
   - Otherwise stop with the gate's blocker and evidence.
4. Freeze the combined proposal and effective ledgers as the stabilization repair set, set cycle `2`, and repair only that set. Do not expand scope, revisit a closed preference, or invent missing authority.
5. Run the gate once more in `EFFECTIVE` mode. Return `PASS_CHANGED` on `PASS_EFFECTIVE`. Otherwise return `BLOCKED_NON_CONVERGENT` with the remaining ledger and evidence; do not repair, restart, or invoke either workflow again automatically.

Canonical resource-guard recovery required by its standard is infrastructure handling, not another propagation or quality cycle.

## Terminal Contract

`PASS_NO_CHANGE` and `PASS_CHANGED` mean good enough, not perfect or future-proof. They authorize neither commit nor push. Every `BLOCKED_*` result names the remaining rows and external change required before a fresh transaction may begin. One transaction invokes the quality gate at most three times. With unchanged inputs and repository state, another authorized transaction produces no diff.
