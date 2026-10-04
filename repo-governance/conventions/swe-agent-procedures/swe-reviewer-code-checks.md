---
description: >-
  Holds the six code checks of the swe-reviewer agent, moved verbatim from its definition so the definition fits its
  word budget.
when_to_use: >-
  Use when swe-reviewer audits code and its definition points here.
---

# SWE Reviewer Code Checks

Moved verbatim from [swe-reviewer](../../../.agents/agents/swe-reviewer.md), which links each section here, per
[Document Word Budget][catalog-document-word-budget].

## Code

1. **Placement and failure handling.** [Hexagonal Architecture](../../development/quality/code/hexagonal-architecture.md)
   and [Functional Core, Imperative Shell][catalog-functional-core-imperative-shell], with error
   fates, logging, and input validation judged as
   [Developing Applications](../../../.agents/skills/developing-applications/SKILL.md) teaches, and types per
   [Type and Boundary Safety](../../development/quality/code/type-and-boundary-safety.md).
2. **Clarity and cost.** [Code Clarity][catalog-code-clarity],
   [Code as Liability][catalog-code-as-liability],
   [Dependency Selection](../../development/dependency-selection.md), and
   [Shell Scripts](../../development/quality/code/shell-scripts.md) for any script in scope.
3. **Stack rules** from the stacks the project lists, read from the repository's local copies as
   [Stack Packs](../structure/stack-packs.md) resolves them. A stack with no recorded standard gets no
   stack rule, and the missing decision is reported.
4. **Test design.** Each test sits at its layer, per the test-boundary standard below; doubles follow
   [Test Doubles][catalog-test-doubles], data follows
   [Test Data Isolation](../../development/test-identities.md), any git fixture follows
   [Git Fixture Isolation][catalog-git-fixture-isolation], and a coverage number measures only what
   [Meaningful Coverage](../../development/quality/testing/meaningful-coverage.md) allows.
5. **Test-first evidence.** New or changed behaviour has a test, and the records
   [Cycle and Evidence][catalog-001-cycle-and-evidence] requires exist wherever
   the work kept them. Behaviour shipped with no test is a finding.
6. **Regression tests.** Each bug fix carries the test
   [Regression Tests][catalog-003-regression-tests] requires.

[catalog-document-word-budget]: https://github.com/wahidyankf/ose-rules/blob/18760a44f7ae4d88e89c0aa79349297f55bb9d9c/repo-governance/conventions/structure/document-word-budget.md
[catalog-functional-core-imperative-shell]: https://github.com/wahidyankf/ose-rules/blob/18760a44f7ae4d88e89c0aa79349297f55bb9d9c/repo-governance/development/quality/architecture/functional-core-imperative-shell.md
[catalog-code-clarity]: https://github.com/wahidyankf/ose-rules/blob/18760a44f7ae4d88e89c0aa79349297f55bb9d9c/repo-governance/development/quality/code/code-clarity.md
[catalog-code-as-liability]: https://github.com/wahidyankf/ose-rules/blob/18760a44f7ae4d88e89c0aa79349297f55bb9d9c/repo-governance/development/quality/code/code-as-liability.md
[catalog-test-doubles]: https://github.com/wahidyankf/ose-rules/blob/18760a44f7ae4d88e89c0aa79349297f55bb9d9c/repo-governance/development/quality/testing/test-doubles.md
[catalog-git-fixture-isolation]: https://github.com/wahidyankf/ose-rules/blob/18760a44f7ae4d88e89c0aa79349297f55bb9d9c/repo-governance/development/quality/testing/git-fixture-isolation.md
[catalog-001-cycle-and-evidence]: https://github.com/wahidyankf/ose-rules/blob/18760a44f7ae4d88e89c0aa79349297f55bb9d9c/repo-governance/development/quality/testing/test-driven-development/001-cycle-and-evidence.md
[catalog-003-regression-tests]: https://github.com/wahidyankf/ose-rules/blob/18760a44f7ae4d88e89c0aa79349297f55bb9d9c/repo-governance/development/quality/testing/test-driven-development/003-regression-tests.md
