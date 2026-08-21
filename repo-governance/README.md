# Repository Governance

This directory contains the repository's detailed rules and working agreements.

Every directory in this tree follows the [governance directory-map convention](conventions/directory-maps.md).

## Directory Map

- [Vision](vision/README.md) defines the future this repository exists to create.
- [Principles](principles/README.md) contain durable constraints within that vision.
- [Conventions](conventions/README.md) define repository-wide choices within the vision and principles.
- [Development](development/README.md) defines engineering standards within all higher levels.
- [Workflows](workflows/README.md) define repeatable procedures within all higher levels and may compose other workflows.

The precedence hierarchy is:

```mermaid
%% Accessible palette: blue #0173B2
flowchart TD
    Vision --> Principles
    Principles --> Conventions
    Conventions --> Development
    Development --> Workflows

    classDef primary fill:#0173B2,stroke:#000000,color:#FFFFFF,stroke-width:2px
    class Vision,Principles,Conventions,Development,Workflows primary
```

The hierarchy flows from top to bottom: a lower level cannot contradict any level above it. Higher levels do not need to conform to lower levels. When documents conflict, the higher level takes precedence and the lower-level document must change. Documents should link to higher-level rules rather than duplicate them.

Root instruction files such as `AGENTS.md` should remain concise—no more than 500 words—and link to the relevant documents here.

The `badakmini-cli` application enforces this limit for root `AGENTS.md` and every Markdown file in this directory, along with the governance navigation requirements. Run it manually with:

```sh
npm exec -- nx run badakmini-cli:test:repo
```

The repository's pre-push hook runs the same governance, documentation-map, and Mermaid-accessibility checks when pushed commits change Markdown anywhere or any content under `docs/`. Other pushes skip them.
