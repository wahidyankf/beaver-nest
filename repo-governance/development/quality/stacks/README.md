# Stack Standards

One standard per adopted stack, each paired with its skill under `.agents/skills/`, as the
[Stack Packs](../../../conventions/structure/stack-packs.md) convention places them. The
[repository adapter](repository-adapter.md) records which packs apply and every local decision.

## Directory Map

- [Elixir standards](elixir-standards.md) fix formatter, compiler, test-load, lint, and Dialyzer gates, tagged-tuple failures, and process rules.
- [JavaScript standards](javascript-standards.md) fix JSDoc type checking, runtime validation at input, and handled promises.
- [Nx standards](nx-standards.md) fix project graph boundaries, affected runs, cache inputs, and the exact Nx pin.
- [Phoenix LiveView standards](phoenix-liveview-standards.md) fix contexts, per-entry-point authorization, the two-pass mount, and live tests.
- [Repository adapter](repository-adapter.md) records the adopted packs, adopter decisions, deviations, and project links.
- [Shell standards](shell-standards.md) fix the analysable dialect, analyser and formatter gates, quoting, and behaviour tests.
- [TypeScript standards](typescript-standards.md) fix strict compiler options, no `any`, validated boundaries, and returned failures.
