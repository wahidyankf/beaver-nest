# badakmini-cli

`badakmini-cli` is the F# command-line application that validates this repository's governance documents. It keeps root instructions and governance Markdown within their word limits and verifies governance directory maps. See the [governance index](../../repo-governance/README.md) for the rules it supports.

## Scope

This project owns governance inspection and its automated tests. The governance documents remain the authoritative rules; the CLI only checks the structural constraints implemented in [Governance.fs](Governance.fs).

## Prerequisites and Tasks

Install the repository's npm dependencies and the .NET 10 SDK. Run tasks from the repository root:

| Task                            | Command                                  |
| ------------------------------- | ---------------------------------------- |
| Validate repository governance  | `npm exec -- nx run badakmini-cli:check` |
| Run the F# test suite           | `npm exec -- nx run badakmini-cli:test`  |
| Build the release configuration | `npm exec -- nx run badakmini-cli:build` |

The `check` target exits nonzero and reports each violation when validation fails. It currently checks root `AGENTS.md`, Markdown under `repo-governance/`, the 500-word limit, required governance READMEs, complete direct-sibling maps, and valid sibling links.

## Structure

- `Governance.fs` contains repository scanning, validation, and diagnostic formatting.
- `Program.fs` contains CLI argument handling and exit codes.
- `Badakmini.Cli.fsproj` targets `net10.0` and defines F# compile order.
- `tests/` contains the xUnit test project and governance behavior tests.
- `project.json` exposes the raw .NET commands as Nx targets without an Nx language plugin.
