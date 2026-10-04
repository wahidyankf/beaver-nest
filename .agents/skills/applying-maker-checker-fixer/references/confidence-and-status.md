---
description: >-
  Holds the confidence-to-status table of the applying-maker-checker-fixer skill, moved verbatim from its definition so
  the definition fits its word budget.
when_to_use: >-
  Use when a fixer rates a finding's confidence and sets the row's ledger status.
---

# Confidence Decides the Row's Status

Moved verbatim from [applying-maker-checker-fixer](../SKILL.md), which links each section here, per
[Document Word Budget][catalog-document-word-budget].

## Confidence Decides the Row's Status

| Confidence       | The fixer                                     | Status                        |
| ---------------- | --------------------------------------------- | ----------------------------- |
| `HIGH`           | applies the repair, then verifies the row     | `resolved`, or `not-resolved` |
| `MEDIUM`         | leaves it with the evidence that kept it open | `needs-decision`              |
| `FALSE_POSITIVE` | records the disproof and what would stop it   | `not-applicable`              |

A row whose target state already holds is `resolved` with no edit. A row the fixer did not reach stays `open`.

[catalog-document-word-budget]: https://github.com/wahidyankf/ose-rules/blob/18760a44f7ae4d88e89c0aa79349297f55bb9d9c/repo-governance/conventions/structure/document-word-budget.md
