# Badakmini CLI Behaviours

The `.feature` files in this directory form the canonical executable behaviour corpus shared by every Badakmini test adapter.

Unit implements every scenario. A scenario may omit Integration, E2E, or both only when each omitted boundary fundamentally cannot express the behaviour, using independently documented `@integration-exempt` and `@e2e-exempt` tags from the repository [BDD standard](../../../../../repo-governance/development/behaviour-driven-development.md). Binding counts are necessary but not sufficient; adapter changes require the [manual implementation review](../../../../../repo-governance/workflows/gherkin-implementation-review.md).

## Directory Map

- [CLI contract](cli-contract.feature) specifies command routing, options, output, and exit behaviour.
- [Directory maps](directory-map.feature) specify recursive README and sibling-link validation.
- [Harness contract](harness-contract.feature) specifies content-level parity across Codex, Claude Code, and OpenCode.
- [Markdown links](markdown-links.feature) specify internal-link validation and archive handling.
- [Mermaid CLI](mermaid-cli.feature) specifies public Mermaid accessibility commands.
- [Mermaid governance](mermaid-governance.feature) specifies Mermaid inspection rules.
- [Word budget](word-budget.feature) specifies governed Markdown scanning and limits.
