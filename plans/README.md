# Plans

Plans are temporary working records for proposed and delivered changes. They explain why work exists, how it will be executed, and what will prove it complete. Current system behaviour and architecture remain canonical under [`specs/`](../specs/README.md).

Follow the [plans convention](../repo-governance/conventions/plans.md) and the local [plan lifecycle convention](../repo-governance/conventions/plan-lifecycle.md).

## Lifecycle

```mermaid
flowchart LR
    accTitle: Plan lifecycle stages
    accDescr: A plan moves one way through four stages -- ideas, backlog, in-progress, then done -- and is never copied between them.

    Ideas["Ideas"] --> Backlog["Backlog"]
    Backlog --> InProgress["In progress"]
    InProgress --> Done["Done"]

    classDef idea fill:#CC78BC,stroke:#000000,color:#000000,stroke-width:2px
    classDef queued fill:#DE8F05,stroke:#000000,color:#000000,stroke-width:2px
    classDef active fill:#0173B2,stroke:#000000,color:#FFFFFF,stroke-width:2px
    classDef complete fill:#029E73,stroke:#000000,color:#000000,stroke-width:2px
    class Ideas idea
    class Backlog queued
    class InProgress active
    class Done complete
```

- [`ideas/`](ideas/README.md) contains rough two-pager briefs grouped by urgency and importance.
- [`backlog/`](backlog/README.md) contains complete formal plans with self-contained technical-document sets that have not started.
- [`in-progress/`](in-progress/README.md) contains only plans being actively executed.
- [`done/`](done/README.md) preserves completed plans as historical delivery records.

Move one plan through the lifecycle instead of copying it between stages. When implementation changes the as-built system, update all relevant specifications in the same change.

## Directory Map

- [Backlog](backlog/README.md) indexes queued plans.
- [Done](done/README.md) indexes completed plans.
- [Ideas](ideas/README.md) indexes rough two-pager briefs.
- [In progress](in-progress/README.md) indexes active plans.
