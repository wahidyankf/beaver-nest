---
description: >-
  Holds the roles table and role boundaries of the applying-maker-checker-fixer skill, moved verbatim from its
  definition so the definition fits its word budget.
when_to_use: >-
  Use when deciding which of maker, checker, or fixer a request calls for.
---

# Three Roles, Three Questions

Moved verbatim from [applying-maker-checker-fixer](../SKILL.md), which links each section here, per
[Document Word Budget][catalog-document-word-budget].

## Three Roles, Three Questions

| Role    | Asks                                                        | Never                         |
| ------- | ----------------------------------------------------------- | ----------------------------- |
| maker   | what should exist, and what else must change with it        | grades its own output as done |
| checker | does the content meet the rules it is held to               | edits what it judges          |
| fixer   | which confirmed findings are safe to apply without a person | creates content from scratch  |

A checker rates criticality only. The fixer, as `<family>-fixer`, executes `<family>-propagation`, the family's one
writer, and rates confidence as it re-validates each row.

A request to create or substantially reshape content is a maker's job. A report of rule violations is a fixer's. A
finding that needs taste, restructuring, or context nobody recorded is neither: it goes to the maker or a person, and a
fixer that attempts it produces confident damage.

A checker never edits what it judges, for the reason Agent Authoring gives: once it edits, nothing independent is left
to judge the edit.

[catalog-document-word-budget]: https://github.com/wahidyankf/ose-rules/blob/18760a44f7ae4d88e89c0aa79349297f55bb9d9c/repo-governance/conventions/structure/document-word-budget.md
