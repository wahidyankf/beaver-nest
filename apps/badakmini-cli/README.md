# badakmini-cli

`badakmini-cli` is the F# command-line application that validates this repository's governance documents, coding-harness contract, and Markdown conventions. It keeps governed Markdown within its word limit, verifies configured directory-map trees, checks internal link targets, reconciles content-level parity across Codex, Claude Code, and OpenCode, and validates author-controlled Mermaid colors and label legibility. See the [governance index](../../repo-governance/README.md) for the rules it supports.

## Scope

This project owns governance inspection plus its unit and local-only integration tests. Process end-to-end tests live in [`badakmini-cli-e2e`](../badakmini-cli-e2e/README.md). Governance documents remain authoritative; the CLI checks structural constraints implemented in [Governance.fs](Governance.fs) and coding-harness parity in [HarnessContract.fs](HarnessContract.fs).

## Prerequisites and Tasks

Install the repository's npm dependencies and the .NET 10 SDK. Run tasks from the repository root through `apps/resource-guard/resource-guard run --class ephemeral -- <command>` and the workspace [resource guard](../../repo-governance/development/resource-aware-development.md):

| Task                                  | Command                                                            |
| ------------------------------------- | ------------------------------------------------------------------ |
| Validate repository governance        | `npm exec -- nx run -p badakmini-cli -t test:repo`                 |
| Run fake-only unit specifications     | `npm exec -- nx run -p badakmini-cli -t test:unit`                 |
| Run local-only integration tests      | `npm exec -- nx run -p badakmini-cli -t test:integration`          |
| Enforce unit-core coverage            | `npm exec -- nx run -p badakmini-cli -t test:coverage:unit`        |
| Enforce full-app integration coverage | `npm exec -- nx run -p badakmini-cli -t test:coverage:integration` |
| Enforce behavior completeness         | `npm exec -- nx run -p badakmini-cli -t test:coverage:behaviour`   |
| Enforce all coverage                  | `npm exec -- nx run -p badakmini-cli -t test:coverage`             |
| Run quick verification                | `npm exec -- nx run -p badakmini-cli -t test:quick`                |
| Type-check the F# projects            | `npm exec -- nx run -p badakmini-cli -t typecheck`                 |
| Build the release configuration       | `npm exec -- nx run -p badakmini-cli -t build`                     |

The `test:repo` target builds once, then concurrently runs word-budget validation, directory-map validation for `repo-governance/`, `docs/`, `specs/`, and `plans/`, internal-link validation, coding-harness reconciliation, and Mermaid validation with prefixed output. It exits nonzero if any invocation fails.

The `typecheck` target compiles both test projects and their CLI reference into isolated temporary artifact directories, then removes them.

Coverage uses Coverlet Debug instrumentation. `test:coverage:unit` requires at least 99% line coverage over `Governance.fs`, `HarnessContract.fs`, and `Cli.fs`; concrete runtime and entry-point files belong to the integration slice. `test:coverage:integration` requires at least 99% across the complete application. Reports go to `coverage/unit-core/` and `coverage/integration-application/`. `test:coverage` composes both numeric slices and static behavior completeness.

The `test:quick` target runs `typecheck`, `lint`, `test:unit`, `test:coverage:unit`, and `test:coverage:behaviour` sequentially. It stops immediately when a stage fails.

## Behaviour Specifications

The canonical [C4 architecture model](../../specs/apps/badakmini/cli/architecture.md) defines Badakmini's current system, container, and component boundaries. Every `.feature` below [`specs/apps/badakmini/cli/behaviours/`](../../specs/apps/badakmini/cli/behaviours/) is embedded recursively into unit, integration, and process E2E assemblies. Each level runs every expanded scenario through the same [thin bindings](tests/contract/BehaviourSteps.fs) and [support vocabulary](tests/contract/BehaviourSupport.fs); only its driver changes.

The unit driver uses an in-memory filesystem and injected output only. The integration driver uses real temporary local files but its policy test rejects network APIs and endpoints, including loopback. [`badakmini-cli-e2e`](../badakmini-cli-e2e/README.md) invokes the built CLI process and observes public output. `test:coverage:behaviour` statically rejects missing disk or embedded features, empty or malformed scenarios, undefined or ambiguous steps, unused bindings, and incomplete drivers across all adapters without running slow scenarios.

Keep inputs in feature tables or DocStrings. TickSpec 2.0.5 treats every literal `#` in a feature as the start of a comment, including inside those values; use `{hash}` in inline Markdown and let the binding expand it.

The suite runs serially for deterministic adapter state and emits standard test-runner output. Follow the repository [BDD standard](../../repo-governance/development/behaviour-driven-development.md) when changing behavior.

## Commands

The CLI uses noun groups followed by a final verb:

```text
badakmini-cli governance word-budget validate [--root <path>]
badakmini-cli governance directory-map validate [--root <path>] [--directory <path>]
badakmini-cli governance harness-contract validate [--root <path>]
badakmini-cli md links validate [--root <path>]
badakmini-cli md mermaid validate [--root <path>] [--file <path> ...]
badakmini-cli md word-count inspect --file <path> [--root <path>]
```

`--root` and `--format text|json` are recursive and may appear before or after nested commands. Root defaults to the current directory and text output remains the default. The directory-map leaf's `--directory` is relative to root and defaults to `repo-governance`. Run a leaf directly with:

```bash
dotnet run --project apps/badakmini-cli/Badakmini.Cli.fsproj -- \
  governance word-budget validate --root .
```

There is no aggregate CLI command; use the Nx `test:repo` target to run every validator. Exit code `0` means success or help, `1` means validation findings, and `2` means an invalid invocation, invalid root, or execution error.

The word-budget leaf applies the [750-word governance budget](../../repo-governance/conventions/directory-maps.md#word-budget) only to root `AGENTS.md` and Markdown under `repo-governance/`. Markdown under `docs/`, `specs/`, and `plans/` is intentionally excluded. Directory-map validation checks required READMEs, complete direct-sibling maps, and valid sibling links in each configured tree. Harness-contract validation reads only repository-contained regular files, normalizes UTF-8 BOM and line endings, hashes full canonical rule, skill-resource, agent-prompt, and capability records, and rejects missing, extra, stale, malformed, or semantically weaker adapters. Link validation checks local Markdown targets across repository-owned Markdown, excluding `plans/done/` as archived sources. Mermaid validation checks accessible `classDef` colors plus visible node/state segments of at most 32 graphemes and edge/transition segments of at most 24. Repeat `--file` to inspect only changed repository-relative Markdown files; omitted, it scans the repository. Legibility findings include `labelRole`, `actualLength`, and `limit` with their source path and line.

Mermaid enforcement covers `flowchart`, `graph`, `classDiagram`, `stateDiagram`, `stateDiagram-v2`, `erDiagram`, `requirementDiagram`, and `block`. `<br>`, `<br/>`, and escaped newlines split measured label segments. Class members, ER attributes, requirement body fields, directives, comments, and front matter are excluded. Other diagram types are skipped because their styling syntax is incompatible, unstable, or undocumented. The scanner excludes dependencies, generated output, caches, worktrees, and filesystem links.

## Structure

- `Governance.fs` contains repository scanning, validation, and diagnostic formatting.
- `HarnessContract.fs` reconciles normalized canonical content and native harness adapters without network, child processes, or writes.
- `Runtime.fs` defines injectable filesystem and CLI runtime ports.
- `Cli.fs` declares the `System.CommandLine` hierarchy, leaf handlers, summaries, and exit codes.
- `Program.fs` delegates process entry to the command tree.
- `Badakmini.Cli.fsproj` targets `net10.0` and defines F# compile order.
- `tests/contract/` owns shared scenario state, bindings, discovery, compliance, and CLI contract tests.
- `tests/unit/` owns the fake-only driver and unit assembly.
- `tests/integration/` owns the real-local driver, network policy, and integration assembly.
- `specs/apps/badakmini/cli/architecture.md` contains the canonical as-built C4 model.
- `specs/apps/badakmini/cli/behaviours/` contains the executable `.feature` specifications.
- `project.json` composes the raw .NET commands as Nx targets without an Nx language plugin.
