# Rules Propagation

Apply this workflow automatically whenever a repository [rule](../conventions/rules.md) is created, changed, moved, or deleted, even without an explicit request.

## Inputs

- the proposed rule and rationale;
- the people, agents, files, or tasks in scope.

## Idempotence Gate

Before editing, compare the requested outcome with the effective rule by meaning, not wording. The existing rule is sufficient only when all are true:

- the requested outcome is stated with its intended mandatory, expected, or permitted strength;
- scope, required or prohibited actions, boundaries, and exceptions are explicit;
- a reasonable reader need not reconcile conflicts or infer missing conditions; and
- one correctly placed canonical source and any needed point-of-use route exist.

If all pass, change no repository content. Wording, order, style, or personal preference is not a gap. Run verification read-only and report a no-op. Otherwise record each material gap and change only enough to close it.

## Procedure

Continue only when the gate identifies a material gap.

1. **Start at use.** Put the shortest actionable form in the relevant `AGENTS.md` or similar instruction file. Keep non-negotiable constraints visible.
2. **Check the entry point.** A self-contained, non-duplicative rule may stay there when the file remains within its limit; otherwise continue with canonical detail.
3. **Stay proportional.** Apply [minimal sufficiency](../principles/minimal-sufficiency.md). Add only necessary rules, links, and files. Add enforcement only for an explicit need, higher rule, or demonstrated risk.
4. **Tidy affected guidance.** Read governance top to bottom. Consolidate only stale, misplaced, overlapping, or repeated content directly implicated by the gap; leave unrelated and sufficient rules unchanged.
5. **Choose the canonical level.** Put outcomes and boundaries in vision, durable constraints in principles, repository choices in conventions, engineering standards in development, and procedures in workflows.
6. **Check hierarchy.** Compare higher levels in order: `vision > principles > conventions > development > workflows`. Change any lower-level conflict.
7. **Deduplicate.** Search equivalent guidance. Keep one correctly placed canonical statement, merge unique detail, and replace copies with concise links.
8. **Disclose progressively.** Follow [progressive disclosure](../principles/progressive-disclosure.md): keep the shortest useful directive and link at use; place supporting detail canonically.
9. **Verify.** Confirm links, affected [directory maps](../conventions/directory-maps.md), canonical ownership, lower-level alignment, and preserved existing intent. Run:

   ```sh
   npm run resource:run -- --class ephemeral -- npm exec -- nx run -p badakmini-cli -t test:repo
   ```

## Outcome

The result is either a verified no-op or the smallest patch that makes the rule visible where relevant, detailed at the correct level, consistent with higher authority, deduplicated, and within word limits. Repeating the workflow with unchanged inputs and repository state produces no diff.
