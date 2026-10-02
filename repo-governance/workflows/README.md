# Workflows

Workflows define repeatable procedures for repository tasks, in three groups. A workflow may be complete on its own or compose several smaller workflows when that keeps each procedure focused and reusable.

Workflows are the lowest governance level. Every workflow must conform to the repository [vision](../vision/README.md), [principles](../principles/README.md), [conventions](../conventions/README.md), and [development standards](../development/README.md). When a conflict exists, the workflow must change.

A workflow should define:

- its goal and when to use it;
- prerequisites and required inputs;
- ordered steps;
- verification of the outcome; and
- recovery or rollback guidance when relevant.

When composing workflows:

- link to the canonical workflow instead of copying its steps;
- state the invocation order and any data passed between workflows;
- keep each component usable independently where practical; and
- avoid circular workflow dependencies.

## Directory Map

- [Plan](plan/README.md) holds the plan lifecycle: planning, execution, grooming, and the execution check.
- [Quality](quality/README.md) holds every quality gate with its propagation, and every single-pass review.
- [Maintenance](maintenance/README.md) holds upkeep and delivery: clean-up, rules grooming, and the development server, proxy, and deployment procedures.
