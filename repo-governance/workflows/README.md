# Workflows

Workflows define repeatable procedures for repository tasks. A workflow may be complete on its own or compose several smaller workflows when that keeps each procedure focused and reusable.

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

- [Rules propagation](rules-propagation.md) automatically governs every repository rule change while preserving hierarchy, concision, and a single canonical source.
