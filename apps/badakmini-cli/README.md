# badakmini-cli

`badakmini-cli` is the F# command-line application that validates this repository's governance documents and compatible Mermaid diagrams. It keeps governed Markdown within its word limit, verifies governance directory maps, and checks author-controlled Mermaid colors across repository-owned Markdown. See the [governance index](../../repo-governance/README.md) for the rules it supports.

## Scope

This project owns governance inspection and its automated tests. The governance documents remain the authoritative rules; the CLI only checks the structural constraints implemented in [Governance.fs](Governance.fs).

## Prerequisites and Tasks

Install the repository's npm dependencies and the .NET 10 SDK. Run tasks from the repository root:

| Task                            | Command                                  |
| ------------------------------- | ---------------------------------------- |
| Validate repository governance  | `npm exec -- nx run badakmini-cli:check` |
| Run the F# test suite           | `npm exec -- nx run badakmini-cli:test`  |
| Build the release configuration | `npm exec -- nx run badakmini-cli:build` |

The `check` target exits nonzero and reports each violation with its source path and line when applicable. It checks root `AGENTS.md`, Markdown under `repo-governance/`, the 500-word limit, required governance READMEs, complete direct-sibling maps, valid sibling links, and accessible `classDef` colors in supported Mermaid types.

Mermaid enforcement covers `flowchart`, `graph`, `classDiagram`, `stateDiagram`, `stateDiagram-v2`, `erDiagram`, `requirementDiagram`, and `block`. Other types are skipped because their styling syntax is incompatible, unstable, or undocumented. The scanner excludes dependencies, generated output, caches, and filesystem links.

## Structure

- `Governance.fs` contains repository scanning, validation, and diagnostic formatting.
- `Program.fs` contains CLI argument handling and exit codes.
- `Badakmini.Cli.fsproj` targets `net10.0` and defines F# compile order.
- `tests/` contains the xUnit test project and governance behavior tests.
- `project.json` exposes the raw .NET commands as Nx targets without an Nx language plugin.
