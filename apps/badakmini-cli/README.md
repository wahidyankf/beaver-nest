# badakmini-cli

`badakmini-cli` is the F# command-line application that validates this repository's governance documents and compatible Mermaid diagrams. It keeps governed Markdown within its word limit, verifies governance directory maps, and checks author-controlled Mermaid colors across repository-owned Markdown. See the [governance index](../../repo-governance/README.md) for the rules it supports.

## Scope

This project owns governance inspection and its automated tests. The governance documents remain the authoritative rules; the CLI only checks the structural constraints implemented in [Governance.fs](Governance.fs).

## Prerequisites and Tasks

Install the repository's npm dependencies and the .NET 10 SDK. Run tasks from the repository root:

| Task                            | Command                                                          |
| ------------------------------- | ---------------------------------------------------------------- |
| Validate repository governance  | `npm exec -- nx run -p badakmini-cli -t test:repo`               |
| Run the BDD unit specifications | `npm exec -- nx run -p badakmini-cli -t test:unit`               |
| Enforce application coverage    | `npm exec -- nx run -p badakmini-cli -t test:coverage:unit`      |
| Enforce binding coverage        | `npm exec -- nx run -p badakmini-cli -t test:coverage:behaviour` |
| Enforce all coverage            | `npm exec -- nx run -p badakmini-cli -t test:coverage`           |
| Run the quick verification      | `npm exec -- nx run -p badakmini-cli -t test:quick`              |
| Type-check the F# projects      | `npm exec -- nx run -p badakmini-cli -t typecheck`               |
| Build the release configuration | `npm exec -- nx run -p badakmini-cli -t build`                   |

The `test:repo` target builds once, then concurrently runs word-budget validation, directory-map validation for `repo-governance/` and `docs/`, and Mermaid validation with prefixed output. It exits nonzero if any invocation fails.

The `typecheck` target compiles the test project and its CLI project reference into an isolated temporary artifacts directory, then removes that directory on exit. It performs project-aware F# type checking without leaving build output behind.

The coverage targets use Coverlet's MSBuild integration with Debug instrumentation. `test:coverage:unit` fails when application line coverage is below 99%. `test:coverage:behaviour` includes the test assembly, isolates the thin TickSpec binding module, and fails unless every binding line is covered. `test:coverage` composes both named targets for compatibility. Debug symbols keep F# source-line attribution accurate while `test:unit` independently exercises the Release build. The ignored JSON reports are written below `coverage/application/` and `coverage/behaviour-steps/`.

The `test:quick` target runs `typecheck`, `lint`, `test:unit`, `test:coverage:unit`, and `test:coverage:behaviour` sequentially. It stops immediately when a stage fails.

## Behaviour Specifications

`test:unit` recursively discovers and executes every `.feature` file under [`specs/badakmini/cli/behaviours/`](../../specs/badakmini/cli/behaviours/). Adding or nesting a feature requires no project-file or runner registration. The `.feature` files own the readable behavior and examples. [`BehaviourSteps.fs`](tests/BehaviourSteps.fs) contains the thin TickSpec bindings, while [`BehaviourSupport.fs`](tests/BehaviourSupport.fs) implements their repository, governance, Mermaid, and CLI operations. Follow the repository's [BDD standard](../../repo-governance/development/behaviour-driven-development.md) when changing this behavior.

Every feature must declare exactly one feature-level execution boundary: `@pure` or `@process_global`. Boundary tags below `Feature:` are rejected. A feature must contain at least one scenario, and every scenario must contain an explicit `When` and `Then`. Missing or ambiguous step definitions fail during discovery, before any scenario runs. The separate 100% binding-coverage pass also fails when a binding remains implemented but no feature uses it. Other feature and scenario tags remain available for ordinary categorization.

Keep small inputs in feature tables or DocStrings. Put a large reusable input under `specs/badakmini/cli/fixtures/` and refer to it from a behavior step. TickSpec 2.0.5 treats every literal `#` in a feature as the start of a comment, including inside tables and DocStrings; use `{hash}` in inline Markdown and let the binding expand it.

`@pure` scenarios may run in parallel. `@process_global` scenarios share the `Process-global CLI behaviours` xUnit collection because they capture `Console` or temporarily change the current directory. The suite emits standard test-runner output only and does not generate a separate BDD report.

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

There is no aggregate CLI command; use the Nx `test:repo` target to run every validator. Exit code `0` means success or help, `1` means validation findings, and `2` means an invalid invocation, invalid root, or execution error.

The word-budget leaf applies the 500-word limit only to root `AGENTS.md` and Markdown under `repo-governance/`. Markdown anywhere under `docs/` is intentionally excluded. Directory-map validation checks required READMEs, complete direct-sibling maps, and valid sibling links in each configured tree. Mermaid validation checks accessible `classDef` colors in supported diagram types. Findings include their source path and line when applicable.

Mermaid enforcement covers `flowchart`, `graph`, `classDiagram`, `stateDiagram`, `stateDiagram-v2`, `erDiagram`, `requirementDiagram`, and `block`. Other types are skipped because their styling syntax is incompatible, unstable, or undocumented. The scanner excludes dependencies, generated output, caches, and filesystem links.

## Structure

- `Governance.fs` contains repository scanning, validation, and diagnostic formatting.
- `Cli.fs` declares the `System.CommandLine` hierarchy, leaf handlers, summaries, and exit codes.
- `Program.fs` delegates process entry to the command tree.
- `Badakmini.Cli.fsproj` targets `net10.0` and defines F# compile order.
- `tests/BehaviourCompliance.fs` validates feature structure, discovers embedded features, and classifies execution boundaries.
- `tests/BehaviourComplianceTests.fs` locks down feature and binding compliance rules.
- `tests/BehaviourSupport.fs` owns disposable scenario state and implements reusable test operations.
- `tests/BehaviourSteps.fs` contains only the thin TickSpec binding vocabulary.
- `tests/BehaviourTests.fs` executes discovered scenarios as parallel-safe or serialized tests.
- `specs/badakmini/cli/behaviours/` contains the executable `.feature` specifications.
- `specs/badakmini/cli/fixtures/` is reserved for large reusable behavior inputs.
- `project.json` composes the raw .NET commands as Nx targets without an Nx language plugin.
