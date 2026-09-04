# Badakmini CLI Architecture

This is the canonical as-built C4 model for the Badakmini command-line application. Maintain it under the repository [architecture specification standard](../../../../repo-governance/development/architecture-specifications.md).

## System Context

```mermaid
flowchart TB
    contributor(["Person<br/><b>Repository contributor</b><br/>Maintains repository content<br/>and runs checks"])
    automation{{"External system<br/><b>Nx tasks and Git hooks</b><br/>Run checks during development<br/>and before pushes"}}
    badakmini[["Software system<br/><b>Badakmini CLI</b><br/>Inspects governance and Markdown<br/>and reports findings"]]
    repository[("External system / data store<br/><b>Repository tree</b><br/>Repository-owned files<br/>and directories")]

    contributor -->|Invokes<br/>reads results| badakmini
    automation -->|Runs validation commands| badakmini
    badakmini -->|Reads local files| repository

    classDef person fill:#808080,stroke:#000000,color:#000000,stroke-width:2px
    classDef system fill:#0173B2,stroke:#000000,color:#FFFFFF,stroke-width:2px
    classDef external fill:#DE8F05,stroke:#000000,color:#000000,stroke-width:2px
    class contributor person
    class badakmini system
    class automation,repository external
```

Badakmini is a local, network-free governance system. Contributors may invoke it directly; Nx targets and Git hooks are its automated entry points.

## Container View

```mermaid
flowchart TB
    contributor(["Person<br/><b>Repository contributor</b>"])
    automation{{"External system<br/><b>Nx tasks and Git hooks</b>"}}
    repository[("External data store<br/><b>Repository tree</b>")]

    subgraph badakmini["Software system: Badakmini CLI"]
        cli["Container<br/><b>CLI process</b><br/>F# / .NET 10<br/>Parses commands and content<br/>Formats results"]
    end

    contributor -->|Command line<br/>text or JSON results| cli
    automation -->|Child process<br/>exit status| cli
    cli -->|Read-only filesystem API| repository

    classDef person fill:#808080,stroke:#000000,color:#000000,stroke-width:2px
    classDef container fill:#0173B2,stroke:#000000,color:#FFFFFF,stroke-width:2px
    classDef external fill:#DE8F05,stroke:#000000,color:#000000,stroke-width:2px
    class contributor person
    class cli container
    class automation,repository external
```

The compiled CLI is the only runtime container. It does not write inspected repositories or call network services.

## Component View

```mermaid
flowchart TB
    caller(["Person / external system<br/><b>Contributor or automation</b>"])
    repository[("External data store<br/><b>Repository tree</b>")]

    subgraph cli["Container: CLI process"]
        direction TB
        entry["Component<br/><b>Process entry</b><br/>Program.fs"]
        commands["Component<br/><b>Command tree</b><br/>Cli.fs / System.CommandLine"]
        governance["Component<br/><b>Governance inspection</b><br/>Governance.fs"]
        harness["Component<br/><b>Harness reconciliation</b><br/>HarnessContract.fs"]
        runtime["Component<br/><b>Runtime ports</b><br/>Runtime.fs"]

        entry -->|Delegates invocation| commands
        commands -->|Requests inspections| governance
        commands -->|Requests parity check| harness
        governance -->|Reads through| runtime
        harness -->|Reads through| runtime
        commands -->|Writes output through| runtime
    end

    caller -->|Arguments| entry
    runtime -->|Read-only filesystem API| repository

    classDef caller fill:#808080,stroke:#000000,color:#000000,stroke-width:2px
    classDef component fill:#0173B2,stroke:#000000,color:#FFFFFF,stroke-width:2px
    classDef external fill:#DE8F05,stroke:#000000,color:#000000,stroke-width:2px
    class caller caller
    class entry,commands,governance,harness,runtime component
    class repository external
```

## Architectural Constraints

- Command handlers depend on the injectable runtime boundary; unit tests replace the filesystem and output writers.
- Integration tests use isolated local files without network access; E2E tests observe only the built process's public command contract.
- Governance documents remain authoritative. Badakmini reports structural, Markdown-link, Mermaid, and coding-harness parity violations but does not mutate repository content. Harness reconciliation normalizes only BOM and line endings, parses the owned YAML/JSON/JSONC/TOML subsets, compares exact adapter routes and semantic permissions, and hashes complete canonical rule, skill-resource, agent-prompt, and capability records with SHA-256. Mermaid checks enforce accessible colors and renderer-free visible-label grapheme limits across supported diagrams; they may read the complete repository or only caller-selected repository-relative Markdown files.
- Text output is the human default, JSON is the machine-observation boundary, and exit codes distinguish success, findings, and invocation errors.

## Behaviour Traceability

Executable behaviour is specified in [`behaviours/`](behaviours/). The production application and its unit, integration, and process E2E adapters must implement that exact recursive corpus.
