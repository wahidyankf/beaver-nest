# Rules

A rule is a repository statement that directs or constrains a decision, behavior, standard, or procedure within a stated scope. It tells people or agents what is required, prohibited, expected, recommended, or permitted.

## Interpretation

- **Must** and **must not** identify mandatory requirements or prohibitions.
- **Should** and **should not** identify expected behavior; deviation requires a justified reason.
- **May** identifies permission, not an obligation.
- A direct imperative, such as “run the check,” is mandatory unless its context explicitly makes it optional.

A rule's scope may identify people, agents, files, components, or tasks directly or through the location containing the rule. Rationale, explanations, and examples support a rule but do not create additional rules unless they contain their own direction or constraint.

## Authority

Every rule must have one canonical source. Its governance level and precedence are determined by that source under the repository [governance hierarchy](../README.md). Concise references at points of use must link to the canonical rule rather than restating it.

Creating, adding, updating, moving, deleting, or otherwise changing a rule automatically invokes the [rules-propagation workflow](../workflows/rules-propagation.md), even when it is not explicitly requested.
