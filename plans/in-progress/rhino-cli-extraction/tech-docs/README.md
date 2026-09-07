# Technical Design

This plan changes two repositories with different owners, and adds a contract between them. The technical set is split along that boundary: what RHINO becomes, what the contract between tool and repository is, and what BeaverNest does to adopt it and retire what it replaces.

Read [`01-rhino-repository.md`](01-rhino-repository.md) first for the upstream design, then [`02-configuration-contract.md`](02-configuration-contract.md) for the schema that both sides depend on, then [`03-beaver-nest-cutover.md`](03-beaver-nest-cutover.md) for the consumer change.

## Boundary

```mermaid
flowchart TB
    maintainer(["Person<br/><b>Maintainer</b><br/>Authors governed Markdown"])

    subgraph upstream["Repository: wahidyankf/rhino"]
        crate["Container<br/><b>rhino binary</b><br/>Rust<br/>Owns validator behaviour"]
        corpus["Container<br/><b>Behaviour corpus</b><br/>Gherkin<br/>Owns the specification"]
        release["Container<br/><b>Release pipeline</b><br/>Immutable tags and checksums"]
    end

    subgraph consumer["Repository: beaver-nest"]
        config[("Data store<br/><b>repo-config.yml</b><br/>Owns this repo's policy")]
        lock[("Data store<br/><b>rhino.lock</b><br/>Owns the pinned release")]
        boot["Container<br/><b>./rhino bootstrap</b><br/>POSIX shell<br/>Verifies then executes"]
    end

    corpus -->|Specifies| crate
    crate -->|Built and published by| release
    release -->|Pinned by digest| lock
    lock -->|Read by| boot
    boot -->|Executes verified binary| crate
    config -->|Supplies policy| crate
    maintainer -->|Runs the gate| boot

    classDef person fill:#808080,stroke:#000000,color:#000000,stroke-width:2px
    classDef unit fill:#0173B2,stroke:#000000,color:#FFFFFF,stroke-width:2px
    classDef store fill:#DE8F05,stroke:#000000,color:#000000,stroke-width:2px
    class maintainer person
    class crate,corpus,release,boot unit
    class config,lock store
```

The arrow that matters is `config -->|Supplies policy| crate`. Today that arrow does not exist: the policy is compiled into `Governance.fs` and `HarnessContract.fs`. Every other change in this plan follows from introducing it.

## Decisions

| Decision                     | Choice                                                         | Why not the alternative                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| ---------------------------- | -------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Language                     | Rust                                                           | Two reasons. **Size:** every consumer downloads and caches this artifact per platform, so a small executable is a product requirement, not an aesthetic; a .NET self-contained publish or a Go build both ship materially more bytes for the same behaviour. **Type safety:** Badakmini's correctness rests on exhaustively matched discriminated unions, and Rust's enums with exhaustive `match` and no null are the closest equivalent, so the port preserves the property rather than trading it away. Rust also removes the .NET SDK from this repository's prerequisites. |
| Distribution                 | Pinned release archives with a POSIX bootstrap                 | Matches the proven HIPPO consumer. `cargo install` would need a Rust toolchain in every consumer and pins a crate version, not a verified artifact.                                                                                                                                                                                                                                                                                                                                                                                                                             |
| Scope of v0.1.0              | All five validators, configuration-driven                      | A partial port leaves this repository running two validators and two toolchains, and defers the hard question — generalizing harness parity — past the point where it is cheap to answer.                                                                                                                                                                                                                                                                                                                                                                                       |
| Policy location              | Consumer's `repo-config.yml`                                   | A tool released to five repositories cannot hold one repository's constants. This is a boundary requirement, not speculative generality.                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| Schema and command alignment | Follow `ose-public`'s `rhino-cli` where surfaces already agree | Both projects carry the RHINO name and an overlapping command surface. A third dialect guarantees a reconciliation cost later.                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| Behaviour proof              | Shared Gherkin corpus at unit, integration, and process levels | A full differential run was considered and declined; see the residual risk and the one numeric exception in [the cutover design](03-beaver-nest-cutover.md).                                                                                                                                                                                                                                                                                                                                                                                                                    |
| Exit codes                   | `0` clean, `1` findings, `2` invocation or configuration error | Badakmini's existing contract, which every rule and harness already depends on. HIPPO's `73`/`75`/`78` are process-guard semantics and are deliberately not adopted.                                                                                                                                                                                                                                                                                                                                                                                                            |
| Design philosophy            | Unix: one job per leaf, quiet when clean, composable output    | A multi-validator binary is only defensible if each leaf behaves like a small tool. See the philosophy section in [the upstream design](01-rhino-repository.md).                                                                                                                                                                                                                                                                                                                                                                                                                |
| First consumer               | RHINO itself, before BeaverNest                                | Generalization is a claim until a second repository tests it. RHINO's own tree has no `repo-governance/`, no `plans/`, and no harness roster, so it breaks BeaverNest-shaped assumptions while the schema is still soft — and it keeps doing so in CI afterwards.                                                                                                                                                                                                                                                                                                               |
| Retirement timing            | Same plan as adoption                                          | Two validators enforcing one contract is the failure mode this plan exists to remove.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |

## Specification Changes

The [Badakmini C4 model](../../../../specs/apps/badakmini/cli/architecture.md) and its [behaviour corpus](../../../../specs/apps/badakmini/cli/behaviours/README.md) describe a system that will no longer exist in this repository. Both move upstream and are rewritten there for the Rust containers and the configuration boundary. BeaverNest gains `specs/tools/rhino-consumer/`, mirroring the existing [HIPPO consumer specification](../../../../specs/tools/hippo-consumer/README.md), which owns only the bootstrap's observable behaviour. Follow the [plan specification-change convention](../../../../repo-governance/conventions/plan-specification-changes.md) and [specification maintenance](../../../../repo-governance/development/specification-maintenance.md).

## Continuity

This plan changes no BeaverNest application code, storage, route, or deployment, so no Caddy candidate, promotion, or drain is required. [Live-service continuity](../../../../repo-governance/development/live-service-continuity.md) still applies as a guard: baseline the routed origin's health and revision before work starts, confirm both are unchanged at the final checkpoint, and stop the line if either degrades. Every compute-bearing command runs through the pinned `./hippo` guard per [resource-aware development](../../../../repo-governance/development/resource-aware-development.md).

## Directory Map

- [`01-rhino-repository.md`](01-rhino-repository.md) — upstream crate architecture, dependency decisions, test adapters, and the release pipeline.
- [`02-configuration-contract.md`](02-configuration-contract.md) — the `repo-config.yml` schema, its record model, its field guide, and the migration of hard-coded constants into it.
- [`03-beaver-nest-cutover.md`](03-beaver-nest-cutover.md) — bootstrap, lock, Nx and hook wiring, authority cutover, retirement, and file impact.
