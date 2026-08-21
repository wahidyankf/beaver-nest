# Rules Propagation

This workflow automatically and mandatorily applies whenever a repository [rule](../conventions/rules.md) is created, added, updated, moved, deleted, or otherwise changed. Follow it even when the user does not explicitly name or request the workflow.

## Inputs

- the proposed rule;
- why it is needed; and
- the people, agents, files, or tasks it applies to.

## Procedure

1. **Start at the point of use.** Draft the shortest actionable form of the rule in the relevant `AGENTS.md` or similar instruction file. Keep non-negotiable constraints visible there.
2. **Check the entry point.** If the rule is self-contained, non-duplicative, and the instruction file remains within its limit, it may stay there. Otherwise, continue with the full details.
3. **Keep propagation proportional.** Apply [minimal sufficiency](../principles/minimal-sufficiency.md). Add only the rules, links, and files needed to express the requirement clearly. Do not create validators, automation, abstractions, or other enforcement merely because a rule exists; require an explicit need, applicable higher rule, or concrete demonstrated risk.
4. **Tidy before adding.** Read existing governance from top to bottom. Identify stale, misplaced, overlapping, or repeated content. Consolidate it without weakening its intent.
5. **Choose the canonical level.** Place desired outcomes and boundaries in vision, durable constraints in principles, repository-wide choices in conventions, engineering standards in development, and repeatable procedures in workflows.
6. **Check for contradictions.** Compare the rule with every higher level in order: `vision > principles > conventions > development > workflows`. A lower rule must change if it contradicts a higher rule.
7. **Deduplicate.** Search instruction and governance files for equivalent guidance. Keep one canonical statement in the correct governance location, merge useful unique detail, and replace other copies with concise links.
8. **Apply [progressive disclosure](../principles/progressive-disclosure.md).** When the instruction-file limit is reached or the rule needs supporting detail, move the full content into its canonical governance document. Leave only the shortest useful directive and link at the point of use.
9. **Verify the result.** Confirm links resolve, affected [directory maps](../conventions/directory-maps.md) list every sibling, the rule has one canonical source, lower levels remain aligned, and no existing rule was unintentionally weakened. Run:

   ```sh
   npm exec -- nx run badakmini-cli:check
   ```

## Outcome

The rule is visible where it becomes relevant, detailed at the correct governance level, consistent with all higher authority, deduplicated, and within repository word limits.
