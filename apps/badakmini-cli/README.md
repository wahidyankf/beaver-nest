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

The `check` target builds once, then concurrently runs word-budget validation, directory-map validation for `repo-governance/` and `docs/`, and Mermaid validation with prefixed output. It exits nonzero if any invocation fails.

## Commands

The CLI uses noun groups followed by a final verb:

```text
badakmini-cli governance word-budget validate [--root <path>]
badakmini-cli governance directory-map validate [--root <path>] [--directory <path>]
badakmini-cli md mermaid validate [--root <path>]
```

`--root` is available throughout the command tree and defaults to the current directory. The directory-map leaf's `--directory` is relative to that root and defaults to `repo-governance`. Run a leaf directly from the repository root with, for example:

```bash
dotnet run --project apps/badakmini-cli/Badakmini.Cli.fsproj -- \
  governance word-budget validate --root .
```

There is no aggregate CLI command; use the Nx `check` target to run every validator. Exit code `0` means success or help, `1` means validation findings, and `2` means an invalid invocation, invalid root, or execution error.

The word-budget leaf applies the 500-word limit only to root `AGENTS.md` and Markdown under `repo-governance/`. Markdown anywhere under `docs/` is intentionally excluded. Directory-map validation checks required READMEs, complete direct-sibling maps, and valid sibling links in each configured tree. Mermaid validation checks accessible `classDef` colors in supported diagram types. Findings include their source path and line when applicable.

Mermaid enforcement covers `flowchart`, `graph`, `classDiagram`, `stateDiagram`, `stateDiagram-v2`, `erDiagram`, `requirementDiagram`, and `block`. Other types are skipped because their styling syntax is incompatible, unstable, or undocumented. The scanner excludes dependencies, generated output, caches, and filesystem links.

## Structure

- `Governance.fs` contains repository scanning, validation, and diagnostic formatting.
- `Cli.fs` declares the `System.CommandLine` hierarchy, leaf handlers, summaries, and exit codes.
- `Program.fs` delegates process entry to the command tree.
- `Badakmini.Cli.fsproj` targets `net10.0` and defines F# compile order.
- `tests/` contains the xUnit test project and governance behavior tests.
- `project.json` composes the raw .NET commands as Nx targets without an Nx language plugin.
