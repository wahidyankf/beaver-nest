# Plans

Plans are temporary working records for proposed and delivered changes. They explain why work exists, how it will be executed, and what will prove it complete. Current system behavior and architecture remain canonical under [`specs/`](../specs/README.md).

Follow the repository [plan lifecycle convention](../repo-governance/conventions/plan-lifecycle.md).

## Lifecycle

```text
ideas/ → backlogs/ → in-progress/ → done/
```

- [`ideas/`](ideas/README.md) contains rough two-pager briefs grouped by urgency and importance.
- [`backlogs/`](backlogs/README.md) contains complete six-document plans that have not started.
- [`in-progress/`](in-progress/README.md) contains only plans being actively executed.
- [`done/`](done/README.md) preserves completed plans as historical delivery records.

Move one plan through the lifecycle instead of copying it between stages. When implementation changes the as-built system, update all relevant specifications in the same change.

## Directory Map

- [Backlogs](backlogs/README.md) indexes queued plans.
- [Done](done/README.md) indexes completed plans.
- [Ideas](ideas/README.md) indexes rough two-pager briefs.
- [In progress](in-progress/README.md) indexes active plans.
