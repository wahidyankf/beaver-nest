# Behaviour-Driven Development

Every application and library below `apps/` or `libs/` must keep observable behavior readable and executable in canonical Gherkin `.feature` files. Dedicated E2E harnesses implement their owning application's corpus, not a separate specification. The `libs/ex-bdd` runner is exempt.

## Iron Rule

Canonical Gherkin states behavioral intent first; test declarations, bindings, drivers, and implementations make it executable. Before interpreting or changing production code, read the relevant feature, scenarios, and steps, then their test code.

For every observable application behavior change, the mandatory order is: update Gherkin → bind its steps as failing tests in every applicable adapter → confirm red through Nx → implement production code. Never skip or reorder this sequence. Finish with no placeholder or unimplemented step. Establish a new project's corpus and adapters before implementing its behavior.

For refactors or implementation-only changes preserving observable behavior, do not alter Gherkin. Read relevant specifications and tests, establish a green baseline or characterization coverage, then keep them green. `libs/ex-bdd` starts from its tests under the [TDD standard](test-driven-development.md).

## Required Layers

| Project role         | Required adapters                                                                                                   |
| -------------------- | ------------------------------------------------------------------------------------------------------------------- |
| Application          | Unit, local-only integration, and E2E in a dedicated Nx project, all consuming the same corpus.                     |
| Library              | Unit; add local-only integration only when the library owns a real local resource boundary. Never put E2E in a lib. |
| Dedicated E2E app    | E2E for its owning application's corpus; it is not an independent behavior owner.                                   |
| `libs/ex-bdd` runner | Exempt from this standard.                                                                                          |

A library without an integration adapter must have no owned filesystem, database, process, or similar local integration boundary. Behavior that needs proof at a public system boundary belongs to a consuming application's E2E corpus. Document the corpus path, required adapters, targets, and any inapplicable library integration layer in the project README.

## Shared Requirements

- Keep canonical application behavior, inputs, and results below `specs/apps/`; keep library corpora below `specs/libs/`.
- Discover every `.feature` recursively. Adding or nesting one must not require manual project or runner registration.
- Give every scenario an explicit `When` and `Then`. Reject empty features and undefined or ambiguous steps.
- Keep bindings thin and put reusable operations or state in support modules.
- Execute every feature, expanded scenario, and step in every applicable adapter. Exempt a specific adapter only when its boundary makes the step impossible, and document why. Never exempt all adapters; remove a scenario that no adapter can implement.
- Use `test:coverage:behaviour` to prove each required adapter embeds the exact recursive corpus, implements the complete driver contract, resolves every step exactly once, and has no unused binding. Deleting behavior is valid only when no stale binding remains.
- Make each corpus an Nx input of its owner and E2E harness so pre-push affected `test:quick` runs unit scenarios and static behavior coverage; integration and E2E runtime remain outside `test:quick` under the [quality-gate](quality-gates.md) and [E2E](end-to-end-testing.md) standards.
- Apply the [test boundaries](quality-gates.md): unit replaces system resources with doubles, integration uses isolated local resources without any network, and E2E exercises public production-like boundaries.

Run commands through Nx from the repository root.
